// this is the 32 colour colour table
// because this module also supports EHB (extra half brite) mode,
// it actually has a 6bit colour select input
// the 6th bit selects EHB colour while the lower 5 bit select the actual colour register


module denise_colortable
(
  input  wire           clk,              // 28MHz clock
  input  wire           clk7_en,          // 7MHz clock enable
  input  wire [  9-1:1] reg_address_in,   // register adress inputs
  input  wire [ 12-1:0] data_in,          // bus data in
  input  wire           rdram,            // read the color table instead of writing to it
  input  wire [  8-1:0] select,           // colour select input
  input  wire [  8-1:0] bplxor,           // clut address xor value
  input  wire [  3-1:0] bank,             // color bank select
  input  wire           loct,             // 12-bit palette select
  input  wire           ehb_en,           // EHB enable
  output reg  [ 24-1:0] rgb               // RGB output
);


// register names and adresses
parameter COLORBASE = 9'h180;         // colour table base address

// select xor
wire [ 8-1:0] select_xored = select;// ^ bplxor;

// color ram
wire [ 8-1:0] wr_adr = {bank[2:0], reg_address_in[5:1]};
wire          wr_en  = (reg_address_in[8:6] == COLORBASE[8:6]) && clk7_en && !rdram;
wire [32-1:0] wr_dat = {4'b0, data_in[11:0], 4'b0, data_in[11:0]};
wire [ 4-1:0] wr_bs  = loct ? 4'b0011 : 4'b1111;
wire [ 8-1:0] rd_adr = rdram ? wr_adr : ehb_en ? {3'b000, select_xored[4:0]} : select_xored;
wire [32-1:0] rd_dat;
reg           ehb_sel;

// color lut
denise_colortable_ram_mf clut
(
  .clock      (clk    ),
  .enable     (1'b1   ),
  .wraddress  (wr_adr ),
  .wren       (wr_en  ),
  .byteena_a  (wr_bs  ),
  .data       (wr_dat ),
  .rdaddress  (rd_adr ),
  .q          (rd_dat )
);

// register half-brite bit
always @ (posedge clk) begin
  ehb_sel <= #1 select_xored[5];
end

// pack color values
wire [12-1:0] color_hi = rd_dat[12-1+16:0+16];
wire [12-1:0] color_lo = rd_dat[12-1+ 0:0+ 0];
wire [24-1:0] color = {color_hi[11:8], color_lo[11:8], color_hi[7:4], color_lo[7:4], color_hi[3:0], color_lo[3:0]};

// extra half brite mode shifter
always @ (*) begin
  if (ehb_sel && ehb_en) // half bright, shift every component 1 position to the right
    rgb = {1'b0,color[23:17],1'b0,color[15:9],1'b0,color[7:1]};
  else // normal colour select
    rgb = color;
end


endmodule

