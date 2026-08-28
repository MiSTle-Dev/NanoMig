// this is the sprite parallel to serial converter
// clk is 7.09379 MHz (low resolution pixel clock)
// the sprdata assign circuitry is constructed differently from the hardware
// as described  in the amiga hardware reference manual
// this is to make sure that the horizontal start position of a sprite
// aligns with the bitplane/playfield start position

`ifdef DENISE_EBR
// ----------------------------------------------------------------------------
// Copyright 2026 Mateusz Nalewajski
//
// This is EBR refactor of sprite shifter to optimize FF resource usage on
// ECP5 platform; with a valid BRAM primitive can be adapted to other FPGAs
// ----------------------------------------------------------------------------

module denise_sprites_shifter
(
  input  clk,          // 28MHz clock
  input  clk7_en,
  input  reset,            // reset
  input  aen,          // address enable
  input  [15:0] fmode,
  input  [1:0] address,         // register address input
  input  [8:0] hpos,        // horizontal beam counter
  input  shift,
  input  [15:0] spr_dat,
  input  [1:0] spr_bankwr_idx,
  input  [1:0] spr_bankrd_num,
  input  [15:0] data_in,      // bus data in
  output [1:0] sprdata,       // serialized sprite data out
  output reg attach          // sprite is attached
);

// register names and adresses
parameter POS  = 2'b00;
parameter CTL  = 2'b01;
parameter DATA = 2'b10;
parameter DATB = 2'b11;

// local signals
reg [15:0] shifta;    // shift register A
reg [15:0] shiftb;    // shift register B
reg  [3:0] shiftidx;  // current shift index
reg  [8:0] hstart;    // horizontal start value

reg armed;  // sprite "armed" signal
reg load;   // load shift register signal

//--------------------------------------------------------------------------------------
`else

module denise_sprites_shifter
(
  input   clk,          // 28MHz clock
  input clk7_en,
  input clk7n_en,  // 7MHz clock enable
  input   reset,            // reset
  input  aen,          // address enable
  input  [1:0] address,         // register address input
  input  [8:0] hpos,        // horizontal beam counter
  input [15:0] fmode,
  input shift,
  input [48-1:0] chip48,
  input   [15:0] data_in,     // bus data in
  output  [1:0] sprdata,      // serialized sprite data out
  output  reg attach        // sprite is attached
);

// register names and adresses
parameter POS  = 2'b00;
parameter CTL  = 2'b01;
parameter DATA = 2'b10;
parameter DATB = 2'b11;

// local signals
reg    [63:0] datla;    // data register A
reg    [63:0] datlb;    // data register B
reg    [63:0] shifta;    // shift register A
reg    [63:0] shiftb;    // shift register B
reg    [8:0] hstart;    // horizontal start value
reg    armed;        // sprite "armed" signal
reg    load;        // load shift register signal
reg    load_del;

//--------------------------------------------------------------------------------------

reg [15:0] data16;
always @(posedge clk) if (clk7_en) data16 <= data_in;

// switch data according to fmode
reg  [64-1:0] spr_fmode_dat;

always @ (*) begin
  case(fmode[3:2])
    2'b00   : spr_fmode_dat = {data16, 48'h000000000000};
    2'b11   : spr_fmode_dat = {data16, chip48[47:0]};
    default : spr_fmode_dat = {data16, chip48[47:32], 32'h00000000};
  endcase
end
`endif

// generate armed signal
always @(posedge clk)
  if (clk7_en) begin
    if (reset) // reset disables sprite
      armed <= 0;
    else if (aen && address==CTL) // writing CTL register disables sprite
      armed <= 0;
    else if (aen && address==DATA) // writing data register A arms sprite
      armed <= 1;
  end
`ifndef DENISE_EBR

//--------------------------------------------------------------------------------------

// generate load signal
always @(posedge clk)
  if (clk7_en) begin
    load <= armed && (hpos[7:0] == hstart[7:0]) && (fmode[15] || (hpos[8] == hstart[8])) ? 1'b1 : 1'b0;
  end

//always @(posedge clk)
//  if (clk7_en) begin
//    load_del <= load;  // AMR - delaying this screws up the scoreboard in hybris.
//  end
`endif

//--------------------------------------------------------------------------------------

// POS register
always @(posedge clk)
  if (clk7_en) begin
    if (aen && address==POS)
      hstart[8:1] <= data_in[7:0];
  end

// CTL register
always @(posedge clk)
  if (clk7_en) begin
    if (aen && address==CTL)
      {attach,hstart[0]} <= {data_in[7],data_in[0]};
  end

`ifdef DENISE_EBR
//--------------------------------------------------------------------------------------

// interface with BRAM sprite buffer
wire [31:0] ram_doutb;
wire  [3:0] ram_addra;
wire  [2:0] ram_addrb;
wire [15:0] ram_din;
reg         ram_wea;

wire [1:0] bankwr_idx;
reg        bankwr_reg;
reg        bankwr_buf;

reg [1:0] bankrd_idx;
reg       bankrd_buf;

sprite_ram ram (
  .clk(clk),
  .wea(ram_wea),
  .addra(ram_addra),
  .dina(ram_din),
  .addrb(ram_addrb),
  .doutb(ram_doutb)
);

// BRAM writes are 16-bit, reads 32-bit
assign ram_addra = {bankwr_buf, bankwr_idx, bankwr_reg};
assign ram_addrb = {bankrd_buf, bankrd_idx};
assign ram_din   = spr_dat;

assign bankwr_idx = spr_bankwr_idx;

// translate data registers write
always @(posedge clk) begin
  if (clk7_en) begin
    // finish writing when we get a full 7MHz cycle
    ram_wea <= 0;

    if (aen) begin
      // initiate data transfer and continue for the next 4 cycles
      case (address)
        DATA: begin ram_wea <= 1; bankwr_reg <= 0; end
        DATB: begin ram_wea <= 1; bankwr_reg <= 1; end
        default: ;
      endcase

      // ensure we won't overwrite currently read data
      bankwr_buf <= ~bankrd_buf;
    end
  end
end

//--------------------------------------------------------------------------------------

// shared control decodes (used by both the bank-index and the shift register)
wire spr_hit  = armed & (hpos[7:0] == hstart[7:0]) & (fmode[15] | (hpos[8] == hstart[8]));
wire idx_last = &shiftidx;                                         // shift registers drained
wire reload   = shift & idx_last & (bankrd_idx != spr_bankrd_num); // fetch next bank

// generate load signal and advance the BRAM read-bank pointer
always @(posedge clk) begin
  // load pulse is timed on the 7MHz enable
  if (clk7_en)
    load <= spr_hit;

  // reset the read bank on sprite start, then advance it in lockstep with
  // every shift-register (re)load. The reload path is deliberately NOT gated
  // by clk7_en so the pointer keeps up at full shift speed in (super)hires.
  if (clk7_en && spr_hit) begin
    bankrd_buf <= bankwr_buf;   // switch reads to current write buffer
    bankrd_idx <= 2'd0;         // reset read bank index
  end else if ((clk7_en && load) || reload) begin
    bankrd_idx <= bankrd_idx + 2'd1;
  end
end

//--------------------------------------------------------------------------------------

// sprite shift register
always @(posedge clk)
  if ((clk7_en && load) || reload) begin
    // (re)load current sprite data
    shifta[15:0] <= ram_doutb[15: 0];
    shiftb[15:0] <= ram_doutb[31:16];
    shiftidx     <= 4'd0;
  end
  else if (shift) begin
    // shift out already loaded data
    shifta[15:0] <= {shifta[14:0],1'b0};
    shiftb[15:0] <= {shiftb[14:0],1'b0};
    shiftidx     <= shiftidx + 4'd1;
  end

// assign serialized output data
// AMR - register the output data to delay it by one clk7, compensating for removing load_del
reg [7:0] sprdata_r;
always @(posedge clk)
  sprdata_r <= {shiftb[15],shifta[15],sprdata_r[7:2]}; // Ugly - are we masking a copper timing problem here?

assign sprdata[1:0] = sprdata_r[1:0]; // {shiftb[63],shifta[63]};

//--------------------------------------------------------------------------------------

endmodule

`else
// data register A
always @(posedge clk) begin
	reg st;
	if(clk7_en && aen && address==DATA) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		datla <= spr_fmode_dat;
	end
end

// data register B
always @(posedge clk) begin
	reg st;
	if(clk7_en && aen && address==DATB) st <= 1;
	if(st & clk7n_en) begin
		st <= 0;
		datlb <= spr_fmode_dat;
	end
end

//--------------------------------------------------------------------------------------

// sprite shift register
always @(posedge clk)
  if (clk7_en && load) // AMR - load_del) // load new data into shift register
  begin
    shifta[63:0] <= datla[63:0];
    shiftb[63:0] <= datlb[63:0];
  end
  else if (shift)
  begin
    shifta[63:0] <= {shifta[62:0],1'b0};
    shiftb[63:0] <= {shiftb[62:0],1'b0};
  end

// assign serialized output data
// AMR - register the output data to delay it by one clk7, compensating for removing load_del
// Fixed highres sprites by pipelining shifter output.
reg [7:0] sprdata_r;
always @(posedge clk)
  sprdata_r <= {shiftb[63],shifta[63],sprdata_r[7:2]}; // Ugly - are we masking a copper timing problem here?

assign sprdata[1:0] = sprdata_r[1:0]; // {shiftb[63],shifta[63]};
//--------------------------------------------------------------------------------------

endmodule


`endif