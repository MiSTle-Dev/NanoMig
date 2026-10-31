// this is the sprite parallel to serial converter
// clk is 7.09379 MHz (low resolution pixel clock)
// the sprdata assign circuitry is constructed differently from the hardware
// as described  in the amiga hardware reference manual
// this is to make sure that the horizontal start position of a sprite
// aligns with the bitplane/playfield start position


module denise_sprites_shifter
(
  input   clk,          // 28MHz clock
  input clk7_en,
  input clk7n_en,  // 7MHz clock enable
  input   reset,            // reset
  input  aen,          // address enable
  input  [1:0] address,         // register address input
  input  [8:0] hpos,        // horizontal beam counter
  input aga,
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
reg    [1:0] hstart_lo;
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
      {attach,hstart[0],hstart_lo} <= {data_in[7],data_in[0],aga ? data_in[4:3] : 2'b00};
  end

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

reg  [2:0] load_d;
wire [3:0] load_s = {load_d, clk7_en & load};
always @(posedge clk) load_d <= load_s[2:0];

// sprite shift register
always @(posedge clk)
  if (load_s[hstart_lo]) // AMR - load_del) // load new data into shift register
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

