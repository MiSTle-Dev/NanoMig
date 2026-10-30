// this module handles the hold and modify mode (HAM)
// the module has its own colour pallete bank, this is to let
// the sprites run simultaneously with a HAM playfield


module denise_hamgenerator
(
  input  wire           clk,              // 28MHz clock
  input  wire           clk7_en,          // 7MHz clock enable
  input  wire [  9-1:1] reg_address_in,   // register adress inputs
  input  wire [ 12-1:0] data_in,          // bus data in
  input  wire [  8-1:0] select,           // colour select input
  input  wire [  8-1:0] bplxor,           // clut address xor value
  input  wire [  3-1:0] bank,             // color bank select
  input  wire           loct,             // 12-bit pallete select
  input  wire           ham8,             // HAM8 mode
  output reg  [ 24-1:0] rgb               // RGB output
);


// register names and adresses
parameter COLORBASE = 9'h180;         // colour table base address

// select xor
wire [ 8-1:0] select_xored = select ^ bplxor;

// color ram
wire [ 8-1:0] wr_adr = {bank[2:0], reg_address_in[5:1]};
wire          wr_en  = (reg_address_in[8:6] == COLORBASE[8:6]) && clk7_en;
wire [32-1:0] wr_dat = {4'b0, data_in[11:0], 4'b0, data_in[11:0]};
wire [ 4-1:0] wr_bs  = loct ? 4'b0011 : 4'b1111;
wire [ 8-1:0] rd_adr = ham8 ? {2'b00, select_xored[7:2]} : select_xored;
wire [32-1:0] rd_dat;
reg  [24-1:0] rgb_prev;
reg  [ 8-1:0] select_r;

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

// pack color values
wire [12-1:0] color_hi = rd_dat[12-1+16:0+16];
wire [12-1:0] color_lo = rd_dat[12-1+ 0:0+ 0];
wire [24-1:0] color = {color_hi[11:8], color_lo[11:8], color_hi[7:4], color_lo[7:4], color_hi[3:0], color_lo[3:0]};

// register previous rgb value
always @ (posedge clk) begin
  rgb_prev <= #1 rgb;
end

// register previous select
always @ (posedge clk) begin
  select_r <= #1 select_xored;
end

// HAM instruction decoder/processor
always @ (*) begin
  if (ham8) begin
    case (select_r[1:0])
      2'b00: // load rgb output with colour from table
        rgb = color;
      2'b01: // hold green and red, modify blue
        rgb = {rgb_prev[23:8],select_r[7:2],rgb_prev[1:0]};
      2'b10: // hold green and blue, modify red
        rgb = {select_r[7:2],rgb_prev[17:16],rgb_prev[15:0]};
      2'b11: // hold blue and red, modify green
        rgb = {rgb_prev[23:16],select_r[7:2],rgb_prev[9:8],rgb_prev[7:0]};
      default:
        rgb = color;
    endcase
  end else begin
    case (select_r[5:4])
      2'b00: // load rgb output with colour from table
        rgb = color;
      2'b01: // hold green and red, modify blue
        rgb = {rgb_prev[23:8],select_r[3:0],select_r[3:0]};
      2'b10: // hold green and blue, modify red
        rgb = {select_r[3:0],select_r[3:0],rgb_prev[15:0]};
      2'b11: // hold blue and red, modify green
        rgb = {rgb_prev[23:16],select_r[3:0],select_r[3:0],rgb_prev[7:0]};
      default:
        rgb = color;
    endcase
  end
end


endmodule

