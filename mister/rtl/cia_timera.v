// CIA Timer A Module
// 16-bit down counter with multiple operating modes
// Can be used for timing, event counting, and serial port baud rate generation
module cia_timera
(
  input   clk,            // System clock
  input clk7_en,          // 7MHz clock enable for synchronization
  input  wr,              // Write enable signal
  input   reset,          // Synchronous reset

  // Register select signals from address decoder
  input   tlo,            // Timer low byte select ($x4)
  input  thi,             // Timer high byte select ($x5)
  input  tcr,             // Timer control register select ($xE)

  input   [7:0] data_in,  // CPU data bus input
  output   [7:0] data_out, // CPU data bus output
  input  eclk,            // External clock input (usually E clock = system clock/10)
  input  cnt,             // CNT pin input
  output  tmra_ovf,       // Timer A overflow signal (used by Timer B cascade mode)
  output  spmode,         // Serial port mode: 0=input, 1=output
  output  irq             // Timer underflow interrupt request
);

// Internal registers
reg    [15:0] tmr;        // 16-bit timer counter (counts down)
reg    [7:0] tmlh;        // Timer latch high byte (reload value)
reg    [7:0] tmll;        // Timer latch low byte (reload value)
reg    [6:0] tmcr;        // Timer control register (bit 4 excluded - it's strobe only)
reg    forceload;         // Force load strobe signal
wire  oneshot;            // One-shot mode flag
wire  start;              // Timer start/stop control
reg    thi_load;          // Load timer when high byte written
wire  reload;             // Reload timer from latch
wire  zero;               // Timer reached zero
wire  underflow;          // Timer underflow condition
wire  count;              // Count enable signal
reg    [2:0] cnt_sync;    // CNT pin synchroniser and edge detect
wire  cnt_rise;           // CNT pin positive transition
reg    [1:0] start_delay;

always @(posedge clk)
  if (reset)
    cnt_sync[2:0] <= 3'b111;
  else if (clk7_en)
    cnt_sync[2:0] <= {cnt_sync[1:0],cnt};

assign cnt_rise = cnt_sync[1] & ~cnt_sync[2];

// Count source selected by CRA bit 5 (INMODE)
assign count = tmcr[5] ? cnt_rise : (eclk & start_delay[1]);

always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      start_delay <= 2'b00;
    else if (!start)
      start_delay <= 2'b00;
    else if (thi_load && oneshot)
      start_delay <= 2'b00;
    else if (tcr && wr && !data_in[0])
      start_delay <= 2'b00;
    else if (eclk)
      start_delay <= {start_delay[0],1'b1};
  end

// Timer Control Register (CRA) bit definitions:
// Bit 0: START - Start/stop timer (1=start, 0=stop)
// Bit 1: PBON - PB6 output mode (not implemented in simplified version)
// Bit 2: OUTMODE - PB6 output mode (not implemented)
// Bit 3: RUNMODE - 0=continuous, 1=one-shot
// Bit 4: LOAD - Force load timer from latch (strobe, write-only)
// Bit 5: INMODE - Count source: 0=system clock, 1=CNT pin
// Bit 6: SPMODE - Serial port mode: 0=input, 1=output (for baud rate generation)
// Bit 7: Unused (TOD clock select on CRB register only)

// Write to control register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      tmcr[6:0] <= 7'd0;
    else if (tcr && wr)
      // Load control register, bit 4 (LOAD strobe) is not stored
      tmcr[6:0] <= {data_in[6:5],1'b0,data_in[3:0]};
    else if (thi_load && oneshot)
      // In one-shot mode, writing to timer high byte starts the timer
      tmcr[0] <= 1'd1;
    else if (underflow && oneshot)
      // In one-shot mode, timer stops automatically on underflow
      tmcr[0] <= 1'd0;
  end

// Capture force load strobe (bit 4 of control register write)
always @(posedge clk)
  if (clk7_en) begin
    forceload <= tcr & wr & data_in[4];
  end

// Control register bit aliases for readability
assign oneshot = tmcr[3];    // One-shot mode enable
assign start = tmcr[0];      // Timer start/stop
assign spmode = tmcr[6];     // Serial port mode output

// Timer latch registers - hold reload value
// Low byte latch
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      tmll[7:0] <= 8'b1111_1111;  // Default to $FF
    else if (tlo && wr)
      tmll[7:0] <= data_in[7:0];
  end

// High byte latch
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      tmlh[7:0] <= 8'b1111_1111;  // Default to $FF
    else if (thi && wr)
      tmlh[7:0] <= data_in[7:0];
  end

reg thi_load_latched;
wire thi_load_eclk= thi_load_latched & eclk;

// Detect write to timer high byte
// In stopped state or one-shot mode, this triggers timer reload
always @(posedge clk)
  if (clk7_en) begin
  	if(eclk)
		  thi_load_latched<=1'b0;
	  if (thi & wr & (~start | oneshot))
		  thi_load_latched <= 1'b1;
    thi_load <= thi & wr & (~start | oneshot);
  end

// Timer reload conditions:
// 1. Force load strobe (bit 4 of control register)
// 2. Write to high byte when stopped or in one-shot mode
// 3. Timer underflow (automatic reload)
assign reload = thi_load_eclk | forceload | underflow;

// 16-bit down counter
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      tmr[15:0] <= 16'hFF_FF;  // Reset to maximum value
    else if (reload)
      tmr[15:0] <= {tmlh[7:0],tmll[7:0]};  // Load from latches
    else if (start && count)
      tmr[15:0] <= tmr[15:0] - 16'd1;     // Count down
  end

// Timer state detection
assign zero = ~|tmr;                    // Timer equals zero
assign underflow = zero & start & count; // Underflow when counting through zero

// Output signals
assign tmra_ovf = underflow;  // Timer A overflow for Timer B cascade mode
assign irq = underflow;       // Interrupt request on underflow

// CPU read data multiplexer
// Reading timer returns current count
// Reading control register returns current settings (bit 4 always reads as 0)
assign data_out[7:0] = ({8{~wr&tlo}} & tmr[7:0])        // Timer low byte
          | ({8{~wr&thi}} & tmr[15:8])                  // Timer high byte
          | ({8{~wr&tcr}} & {1'b0,tmcr[6:0]});         // Control register


endmodule