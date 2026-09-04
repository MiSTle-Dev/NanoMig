/*cia b*/


module ciab
(
  input   clk,          // clock
  input clk7_en,
  input   aen,          // adress enable
  input  rd,          // read enable
  input  wr,          // write enable
  input   reset,         // reset
  input   [3:0] rs,         // register select (address)
  input   [7:0] data_in,    // bus data in
  output   [7:0] data_out,    // bus data out
  input   tick,        // tick (counter input for TOD timer)
  input   eclk,           // eclk (counter input for timer A/B)
  input   flag,         // flag (set FLG bit in ICR register)
  output   irq,           // interrupt request out
  input  [5:0] porta_in,   // input port
  output   [7:6] porta_out,  // output port
  output  [7:0] portb_out    // output port
);

// local signals
  wire   [7:0] icr_out;
  wire  [7:0] tmra_out;
  wire  [7:0] tmrb_out;
  wire  [7:0] tmrd_out;
  reg    [7:0] pa_out;
  reg    [7:0] pb_out;
  wire  alrm;        // TOD interrupt
  wire  ta;          // TIMER A interrupt
  wire  tb;          // TIMER B interrupt
  wire  tmra_ovf;      // TIMER A underflow (for Timer B)

  reg    [7:0] sdr_latch;
  wire  [7:0] sdr_out;

  reg    tick_del;      // required for edge detection

//----------------------------------------------------------------------------------
// address decoder
//----------------------------------------------------------------------------------
  wire  pra,prb,ddra,ddrb,cra,talo,tahi,crb,tblo,tbhi,tdlo,tdme,tdhi,sdr,icrs;
  wire  enable;

assign enable = aen & (rd | wr);

// decoder
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

//----------------------------------------------------------------------------------
// data_out multiplexer
//----------------------------------------------------------------------------------
assign data_out = icr_out | tmra_out | tmrb_out | tmrd_out | sdr_out | pb_out | pa_out;

// fake serial port data register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      sdr_latch[7:0] <= 8'h00;
    else if (wr & sdr)
      sdr_latch[7:0] <= data_in[7:0];
  end

// sdr register read
assign sdr_out = (!wr && sdr) ? sdr_latch[7:0] : 8'h00;

//----------------------------------------------------------------------------------
// porta
//----------------------------------------------------------------------------------
reg [5:0] porta_in2;
reg [7:0] regporta;
reg [7:0] ddrporta;

// synchronizing of input data
always @(posedge clk)
  if (clk7_en) begin
    porta_in2 <= porta_in;
  end

// writing of output port
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      regporta[7:0] <= 8'd0;
    else if (wr && pra)
      regporta[7:0] <= data_in[7:0];
  end

// writing of ddr register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      ddrporta[7:0] <= 8'd0;
    else if (wr && ddra)
       ddrporta[7:0] <= data_in[7:0];
  end

// reading of port/ddr register
always @(*)
begin
  if (!wr && pra)
    pa_out[7:0] = {porta_out[7:6],porta_in2[5:0]};
  else if (!wr && ddra)
    pa_out[7:0] = ddrporta[7:0];
  else
    pa_out[7:0] = 8'h00;
end

// assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign porta_out[7:6] = (~ddrporta[7:6]) | regporta[7:6];

//----------------------------------------------------------------------------------
// portb
//----------------------------------------------------------------------------------
reg [7:0] regportb;
reg [7:0] ddrportb;

// writing of output port
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      regportb[7:0] <= 8'd0;
    else if (wr && prb)
      regportb[7:0] <= data_in[7:0];
  end

// writing of ddr register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      ddrportb[7:0] <= 8'd0;
    else if (wr && ddrb)
       ddrportb[7:0] <= data_in[7:0];
  end

// reading of port/ddr register
always @(*)
begin
  if (!wr && prb)
    pb_out[7:0] = portb_out[7:0];
  else if (!wr && ddrb)
    pb_out[7:0] = ddrportb[7:0];
  else
    pb_out[7:0] = 8'h00;
end

// assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign portb_out[7:0] = (~ddrportb[7:0]) | regportb[7:0];

// deleyed tick signal for edge detection
always @(posedge clk)
  if (clk7_en) begin
    tick_del <= tick;
  end

//----------------------------------------------------------------------------------
// instantiate cia interrupt controller
//----------------------------------------------------------------------------------
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
  .flag(flag),
  .ser(1'b0),
  .data_in(data_in),
  .data_out(icr_out),
  .irq(irq)
);

//----------------------------------------------------------------------------------
// instantiate timer A
//----------------------------------------------------------------------------------
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
  .tmra_ovf(tmra_ovf),
  .spmode(),
  .irq(ta)
);

//----------------------------------------------------------------------------------
// instantiate timer B
//----------------------------------------------------------------------------------
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
  .tmra_ovf(tmra_ovf),
  .irq(tb)
);

//----------------------------------------------------------------------------------
// instantiate timer D
//----------------------------------------------------------------------------------
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
  .count(tick & ~tick_del),
  .irq(alrm)
);

endmodule

