// CIA B (Complex Interface Adapter B)
// MOS 8520 CIA implementation for Amiga computers
//
// CIA B handles:
// - Serial port control (RS-232)
// - Disk drive selection and motor control
// - Disk step and direction signals
// - FLAG input for disk index detection
// - Two 16-bit timers
// - Time-of-day clock with alarm
// - Interrupt generation (generates INT6)
//
// Memory mapped at $BFD000-$BFDF00 (even addresses)

module ciab
(
  input   clk,              // System clock
  input clk7_en,            // 7MHz clock enable
  input   aen,              // Address enable (chip select)
  input  rd,                // Read enable
  input  wr,                // Write enable
  input   reset,            // System reset
  input   [3:0] rs,         // Register select (address bits)
  input   [7:0] data_in,    // CPU data bus input
  output   [7:0] data_out,  // CPU data bus output
  input   tick,             // TOD tick input (50/60 Hz)
  input   eclk,             // E clock (system clock / 10)
  input   cnt_in,           // CNT pin input
  input   flag,             // FLAG input (disk index pulse)
  output   irq,             // Interrupt request (INT6)

  // Port A connections (serial and disk control)
  input  [5:0] porta_in,    // Port A inputs
  output   [7:6] porta_out, // Port A outputs
  // Bit 0: /RTS - RS-232 Request To Send (input)
  // Bit 1: /CD  - RS-232 Carrier Detect (input)
  // Bit 2: /CTS - RS-232 Clear To Send (input)
  // Bit 3: /DSR - RS-232 Data Set Ready (input)
  // Bit 4: SEL  - Centronics Select (input)
  // Bit 5: POUT - Centronics Paper Out (input)
  // Bit 6: /DTR - RS-232 Data Terminal Ready (output)
  // Bit 7: /RE  - RS-232 Ring Indicator (output)

  // Port B - Disk drive control signals
  output  [7:0] portb_out   // Port B outputs
  // Bit 0: /STEP - Disk head step pulse
  // Bit 1: DIR   - Disk head direction (0=out, 1=in)
  // Bit 2: /SIDE - Disk side select (0=upper, 1=lower)
  // Bit 3: /SEL0 - Select drive 0 (internal)
  // Bit 4: /SEL1 - Select drive 1 (external)
  // Bit 5: /SEL2 - Select drive 2 (external)
  // Bit 6: /SEL3 - Select drive 3 (external)
  // Bit 7: /MTR  - Disk motor on/off
);

// Internal signal declarations
  wire   [7:0] icr_out;     // Interrupt control register output
  wire  [7:0] tmra_out;     // Timer A data output
  wire  [7:0] tmrb_out;     // Timer B data output
  wire  [7:0] tmrd_out;     // Timer D (TOD) data output
  reg    [7:0] pa_out;      // Port A data output
  reg    [7:0] pb_out;      // Port B data output
  wire  alrm;               // TOD alarm interrupt
  wire  ta;                 // Timer A interrupt
  wire  tb;                 // Timer B interrupt
  wire  tmra_ovf;           // Timer A underflow signal

  reg    [7:0] sdr_latch;   // Serial data register (dummy)
  wire  [7:0] sdr_out;      // SDR output

  reg    tick_del;          // Delayed tick for edge detection

//----------------------------------------------------------------------------------
// Address decoder for CIA registers
//----------------------------------------------------------------------------------
  wire  pra,prb,ddra,ddrb,cra,talo,tahi,crb,tblo,tbhi,tdlo,tdme,tdhi,sdr,icrs;
  wire  enable;

assign enable = aen & (rd | wr);

// CIA B Register Map (same offsets as CIA A):
// $BFD000 - PRA   - Port A data (serial port control)
// $BFD100 - PRB   - Port B data (disk drive control)
// $BFD200 - DDRA  - Port A direction
// $BFD300 - DDRB  - Port B direction
// $BFD400 - TALO  - Timer A low byte
// $BFD500 - TAHI  - Timer A high byte
// $BFD600 - TBLO  - Timer B low byte
// $BFD700 - TBHI  - Timer B high byte
// $BFD800 - TDLO  - TOD low byte (1/10 seconds)
// $BFD900 - TDME  - TOD middle byte (seconds)
// $BFDA00 - TDHI  - TOD high byte (minutes)
// $BFDC00 - SDR   - Serial data register (unused)
// $BFDD00 - ICR   - Interrupt control register
// $BFDE00 - CRA   - Control register A
// $BFDF00 - CRB   - Control register B

// Generate register select signals
assign  pra  = (enable && rs==4'h0) ? 1'b1 : 1'b0;
assign  prb  = (enable && rs==4'h1) ? 1'b1 : 1'b0;
assign  ddra = (enable && rs==4'h2) ? 1'b1 : 1'b0;
assign  ddrb = (enable && rs==4'h3) ? 1'b1 : 1'b0;
assign  talo = (enable && rs==4'h4) ? 1'b1 : 1'b0;
assign  tahi = (enable && rs==4'h5) ? 1'b1 : 1'b0;
assign  tblo = (enable && rs==4'h6) ? 1'b1 : 1'b0;
assign  tbhi = (enable && rs==4'h7) ? 1'b1 : 1'b0;
assign  tdlo = (enable && rs==4'h8) ? 1'b1 : 1'b0;
assign  tdme = (enable && rs==4'h9) ? 1'b1 : 1'b0;
assign  tdhi = (enable && rs==4'hA) ? 1'b1 : 1'b0;
assign  sdr  = (enable && rs==4'hC) ? 1'b1 : 1'b0;
assign  icrs = (enable && rs==4'hD) ? 1'b1 : 1'b0;
assign  cra  = (enable && rs==4'hE) ? 1'b1 : 1'b0;
assign  crb  = (enable && rs==4'hF) ? 1'b1 : 1'b0;

// Data output multiplexer - OR together all module outputs
assign data_out = icr_out | tmra_out | tmrb_out | tmrd_out | sdr_out | pb_out | pa_out;

// Dummy serial port data register
// CIA B's serial port is not implemented in this simplified version
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      sdr_latch[7:0] <= 8'h00;
    else if (wr & sdr)
      sdr_latch[7:0] <= data_in[7:0];
  end

// SDR read returns last written value
assign sdr_out = (!wr && sdr) ? sdr_latch[7:0] : 8'h00;

//----------------------------------------------------------------------------------
// Port A - Serial port control signals
//----------------------------------------------------------------------------------
reg [5:0] porta_in2;        // Synchronized input data
reg [7:0] regporta;         // Port A output register
reg [7:0] ddrporta;         // Port A direction register

// Synchronize external inputs
always @(posedge clk)
  if (clk7_en) begin
    porta_in2 <= porta_in;
  end

// Port A output register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      regporta[7:0] <= 8'd0;
    else if (wr && pra)
      regporta[7:0] <= data_in[7:0];
  end

// Port A direction register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      ddrporta[7:0] <= 8'd0;
    else if (wr && ddra)
       ddrporta[7:0] <= data_in[7:0];
  end

// Port A read multiplexer
always @(*)
begin
  if (!wr && pra)
    pa_out[7:0] = {porta_out[7:6],porta_in2[5:0]}; // Mix outputs and inputs
  else if (!wr && ddra)
    pa_out[7:0] = ddrporta[7:0];                   // Read direction register
  else
    pa_out[7:0] = 8'h00;
end

// Port A outputs (only bits 7:6 are outputs on CIA B)
// Pull-ups ensure undriven pins read as 1
assign porta_out[7:6] = (~ddrporta[7:6]) | regporta[7:6];

//----------------------------------------------------------------------------------
// Port B - Disk drive control (all outputs)
//----------------------------------------------------------------------------------
reg [7:0] regportb;         // Port B output register
reg [7:0] ddrportb;         // Port B direction register

// Port B output register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      regportb[7:0] <= 8'd0;
    else if (wr && prb)
      regportb[7:0] <= data_in[7:0];
  end

// Port B direction register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      ddrportb[7:0] <= 8'd0;
    else if (wr && ddrb)
       ddrportb[7:0] <= data_in[7:0];
  end

// Port B read multiplexer
always @(*)
begin
  if (!wr && prb)
    pb_out[7:0] = portb_out[7:0];  // Read output state
  else if (!wr && ddrb)
    pb_out[7:0] = ddrportb[7:0];   // Read direction register
  else
    pb_out[7:0] = 8'h00;
end

// Port B outputs with pull-up simulation
// All bits are typically configured as outputs for disk control
assign portb_out[7:0] = (~ddrportb[7:0]) | regportb[7:0];

// Delayed tick signal for edge detection
always @(posedge clk)
  if (clk7_en) begin
    tick_del <= tick;
  end

//----------------------------------------------------------------------------------
// Instantiate sub-modules
//----------------------------------------------------------------------------------

// Interrupt controller
cia_int cnt
(
  .clk(clk),
  .clk7_en(clk7_en),
  .wr(wr),
  .reset(reset),
  .icrs(icrs),
  .ta(ta),
  .tb(tb),
  .alrm(alrm),
  .flag(flag),              // Disk index pulse interrupt
  .ser(1'b0),               // Serial port not implemented
  .data_in(data_in),
  .data_out(icr_out),
  .irq(irq)
);

// Timer A - General purpose timer
cia_timera tmra
(
  .clk(clk),
  .clk7_en(clk7_en),
  .wr(wr),
  .reset(reset),
  .tlo(talo),
  .thi(tahi),
  .tcr(cra),
  .data_in(data_in),
  .data_out(tmra_out),
  .eclk(eclk),
  .cnt(cnt_in),
  .tmra_ovf(tmra_ovf),
  .irq(ta)
);

// Timer B - General purpose timer, can cascade with Timer A
cia_timerb tmrb
(
  .clk(clk),
  .clk7_en(clk7_en),
  .wr(wr),
  .reset(reset),
  .tlo(tblo),
  .thi(tbhi),
  .tcr(crb),
  .data_in(data_in),
  .data_out(tmrb_out),
  .eclk(eclk),
  .cnt(cnt_in),
  .tmra_ovf(tmra_ovf),
  .irq(tb)
);

// Timer D - Time of Day clock with alarm
cia_timerd tmrd
(
  .clk(clk),
  .clk7_en(clk7_en),
  .wr(wr),
  .reset(reset),
  .tlo(tdlo),
  .tme(tdme),
  .thi(tdhi),
  .tcr(crb),
  .data_in(data_in),
  .data_out(tmrd_out),
  .count(tick & ~tick_del),  // Count on rising edge of tick
  .irq(alrm)
);

endmodule