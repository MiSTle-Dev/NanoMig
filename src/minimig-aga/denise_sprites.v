// Copyright 2006, 2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
//
// This is the sprites part of denise
// It supports all OCS sprite modes.

`ifdef DENISE_EBR
// ----------------------------------------------------------------------------
// Copyright 2026 Mateusz Nalewajski
//
// This is EBR refactor of sprites to optimize FF resource usage on
// ECP5 platform; with a valid BRAM primitive can be adapted to other FPGAs
// ----------------------------------------------------------------------------
`endif

module denise_sprites
(
  input   clk,          // 28MHz clock
  input clk7_en,
  input   reset,            // reset
  input c1,
  input c3,
  input aga,
  input  [8:1] reg_address_in,  // register address input
  input  [8:0] hpos,        // horizontal beam counter
  input   [15:0] data_in,     // bus data in
`ifdef DENISE_EBR
  input   [15:0] chip16_r,
  input   [1:0] chip16_idx,
  input  sprena,          // sprite enable signal
  input [3:0] esprm,
  input [3:0] osprm,
  input [1:0] spres,
  output   [7:0] nsprite,        // sprite data valid signals
  output  reg [7:0] sprdata    // sprite data out
);

//register names and adresses
parameter SPRPOSCTLBASE = 9'h140;  //sprite data, position and control register base address
`else
  input [47:0] chip48,
  input  sprena,          // sprite enable signal
  input [3:0] esprm,
  input [3:0] osprm,
  input [1:0] spres,
  output   [7:0] nsprite,        // sprite data valid signals
  output  reg [7:0] sprdata    // sprite data out
);

//register names and adresses
parameter  SPRPOSCTLBASE = 9'h140;  //sprite data, position and control register base address
`endif
parameter FMODE         = 9'h1fc;

//local signals
wire    selspr0;        // select sprite 0
wire    selspr1;        // select sprite 1
wire    selspr2;        // select sprite 2
wire    selspr3;        // select sprite 3
wire    selspr4;        // select sprite 4
wire    selspr5;        // select sprite 5
wire    selspr6;        // select sprite 6
wire    selspr7;        // select sprite 7

wire    [1:0] sprdat0;      // data sprite 0
wire    [1:0] sprdat1;      // data sprite 1
wire    [1:0] sprdat2;      // data sprite 2
wire    [1:0] sprdat3;      // data sprite 3
wire    [1:0] sprdat4;      // data sprite 4
wire    [1:0] sprdat5;      // data sprite 5
wire    [1:0] sprdat6;      // data sprite 6
wire    [1:0] sprdat7;      // data sprite 7

wire    attach0;        // attach sprite 0,1
wire    attach1;        // attach sprite 0,1
wire    attach2;        // attach sprite 2,3
wire    attach3;        // attach sprite 2,3
wire    attach4;        // attach sprite 4,5
wire    attach5;        // attach sprite 4,5
wire    attach6;        // attach sprite 6,7
wire    attach7;        // attach sprite 6,7

//--------------------------------------------------------------------------------------

// sprite register address decoder
wire  selsprx;

assign selsprx = SPRPOSCTLBASE[8:6]==reg_address_in[8:6] ? 1'b1 : 1'b0; // base address
assign selspr0 = selsprx && reg_address_in[5:3]==3'd0    ? 1'b1 : 1'b0;
assign selspr1 = selsprx && reg_address_in[5:3]==3'd1    ? 1'b1 : 1'b0;
assign selspr2 = selsprx && reg_address_in[5:3]==3'd2    ? 1'b1 : 1'b0;
assign selspr3 = selsprx && reg_address_in[5:3]==3'd3    ? 1'b1 : 1'b0;
assign selspr4 = selsprx && reg_address_in[5:3]==3'd4    ? 1'b1 : 1'b0;
assign selspr5 = selsprx && reg_address_in[5:3]==3'd5    ? 1'b1 : 1'b0;
assign selspr6 = selsprx && reg_address_in[5:3]==3'd6    ? 1'b1 : 1'b0;
assign selspr7 = selsprx && reg_address_in[5:3]==3'd7    ? 1'b1 : 1'b0;

//--------------------------------------------------------------------------------------

`ifdef DENISE_EBR
// fmode reg
reg  [15:0] fmode;

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      fmode <= #1 16'h0000;
    else if (aga && (reg_address_in[8:1] == FMODE[8:1]))
      fmode <= #1 data_in;
  end
end

wire [1:0] spr_bankwr_idx;
reg  [1:0] spr_bankrd_num;

assign spr_bankwr_idx = chip16_idx;

// set number of banks to be read according to fmode
always @(*) begin
  case(fmode[3:2])
    2'b00   : spr_bankrd_num = 1;
    2'b11   : spr_bankrd_num = 0;
    default : spr_bankrd_num = 2;
  endcase
end
`else

// fmode reg
reg  [16-1:0] fmode;

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      fmode <= #1 16'h0000;
    else if (aga && (reg_address_in[8:1] == FMODE[8:1]))
      fmode <= #1 data_in;
  end
end

`endif

// shift value
reg shift;
always @ (*) begin
  case (spres)
    2'b11   : shift = 1'b1;
    2'b10   : shift = ~c1 ^ c3;
    default : shift = ~c1 & ~c3;
  endcase
end

`ifdef DENISE_EBR
// instantiate sprite 0
denise_sprites_shifter sps0
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .aen(selspr0),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .spr_dat(chip16_r),
  .spr_bankwr_idx(spr_bankwr_idx),
  .spr_bankrd_num(spr_bankrd_num),
  .data_in(data_in),
  .sprdata(sprdat0),
  .attach(attach0)
);

// instantiate sprite 1
denise_sprites_shifter sps1
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .aen(selspr1),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .spr_dat(chip16_r),
  .spr_bankwr_idx(spr_bankwr_idx),
  .spr_bankrd_num(spr_bankrd_num),
  .data_in(data_in),
  .sprdata(sprdat1),
  .attach(attach1)
);

// instantiate sprite 2
denise_sprites_shifter sps2
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .aen(selspr2),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .spr_dat(chip16_r),
  .spr_bankwr_idx(spr_bankwr_idx),
  .spr_bankrd_num(spr_bankrd_num),
  .data_in(data_in),
  .sprdata(sprdat2),
  .attach(attach2)
);

// instantiate sprite 3
denise_sprites_shifter sps3
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .aen(selspr3),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .spr_dat(chip16_r),
  .spr_bankwr_idx(spr_bankwr_idx),
  .spr_bankrd_num(spr_bankrd_num),
  .data_in(data_in),
  .sprdata(sprdat3),
  .attach(attach3)
);

// instantiate sprite 4
denise_sprites_shifter sps4
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .aen(selspr4),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .spr_dat(chip16_r),
  .spr_bankwr_idx(spr_bankwr_idx),
  .spr_bankrd_num(spr_bankrd_num),
  .data_in(data_in),
  .sprdata(sprdat4),
  .attach(attach4)
);

// instantiate sprite 5
denise_sprites_shifter sps5
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .aen(selspr5),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .spr_dat(chip16_r),
  .spr_bankwr_idx(spr_bankwr_idx),
  .spr_bankrd_num(spr_bankrd_num),
  .data_in(data_in),
  .sprdata(sprdat5),
  .attach(attach5)
);

// instantiate sprite 6
denise_sprites_shifter sps6
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .aen(selspr6),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .spr_dat(chip16_r),
  .spr_bankwr_idx(spr_bankwr_idx),
  .spr_bankrd_num(spr_bankrd_num),
  .data_in(data_in),
  .sprdata(sprdat6),
  .attach(attach6)
);

// instantiate sprite 7
denise_sprites_shifter sps7
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .aen(selspr7),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .spr_dat(chip16_r),
  .spr_bankwr_idx(spr_bankwr_idx),
  .spr_bankrd_num(spr_bankrd_num),
`else
wire clk7n_en = c1 & c3;


// instantiate sprite 0
denise_sprites_shifter sps0
(
  .clk(clk),
  .clk7_en(clk7_en),
  .clk7n_en(clk7n_en),
  .reset(reset),
  .aen(selspr0),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .chip48(chip48),
  .data_in(data_in),
  .sprdata(sprdat0),
  .attach(attach0)
);

// instantiate sprite 1
denise_sprites_shifter sps1
(
  .clk(clk),
  .clk7_en(clk7_en),
  .clk7n_en(clk7n_en),
  .reset(reset),
  .aen(selspr1),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .chip48(chip48),
  .data_in(data_in),
  .sprdata(sprdat1),
  .attach(attach1)
);

// instantiate sprite 2
denise_sprites_shifter sps2
(
  .clk(clk),
  .clk7_en(clk7_en),
  .clk7n_en(clk7n_en),
  .reset(reset),
  .aen(selspr2),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .chip48(chip48),
  .data_in(data_in),
  .sprdata(sprdat2),
  .attach(attach2)
);

// instantiate sprite 3
denise_sprites_shifter sps3
(
  .clk(clk),
  .clk7_en(clk7_en),
  .clk7n_en(clk7n_en),
  .reset(reset),
  .aen(selspr3),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .chip48(chip48),
  .data_in(data_in),
  .sprdata(sprdat3),
  .attach(attach3)
);

// instantiate sprite 4
denise_sprites_shifter sps4
(
  .clk(clk),
  .clk7_en(clk7_en),
  .clk7n_en(clk7n_en),
  .reset(reset),
  .aen(selspr4),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .chip48(chip48),
  .data_in(data_in),
  .sprdata(sprdat4),
  .attach(attach4)
);

// instantiate sprite 5
denise_sprites_shifter sps5
(
  .clk(clk),
  .clk7_en(clk7_en),
  .clk7n_en(clk7n_en),
  .reset(reset),
  .aen(selspr5),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .chip48(chip48),
  .data_in(data_in),
  .sprdata(sprdat5),
  .attach(attach5)
);

// instantiate sprite 6
denise_sprites_shifter sps6
(
  .clk(clk),
  .clk7_en(clk7_en),
  .clk7n_en(clk7n_en),
  .reset(reset),
  .aen(selspr6),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .chip48(chip48),
  .data_in(data_in),
  .sprdata(sprdat6),
  .attach(attach6)
);

// instantiate sprite 7
denise_sprites_shifter sps7
(
  .clk(clk),
  .clk7_en(clk7_en),
  .clk7n_en(clk7n_en),
  .reset(reset),
  .aen(selspr7),
  .address(reg_address_in[2:1]),
  .hpos(hpos),
  .fmode(fmode),
  .shift(shift),
  .chip48(chip48),
`endif
  .data_in(data_in),
  .sprdata(sprdat7),
  .attach(attach7)
);

//--------------------------------------------------------------------------------------

// generate sprite data valid signals
assign nsprite[0] = (sprena && sprdat0[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[1] = (sprena && sprdat1[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[2] = (sprena && sprdat2[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[3] = (sprena && sprdat3[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[4] = (sprena && sprdat4[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[5] = (sprena && sprdat5[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[6] = (sprena && sprdat6[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[7] = (sprena && sprdat7[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data

//--------------------------------------------------------------------------------------

// sprite video priority logic and color decoder
always @(*)
begin
  if (nsprite[1:0]!=2'b00) // sprites 0,1 non transparant ?
  begin
    if (attach1 || (!aga && attach0)) // sprites are attached -> 15 colors + transparant
      sprdata[7:0] = {osprm,sprdat1[1:0],sprdat0[1:0]};
       else if (nsprite[0]) // output lowered number sprite
      sprdata[7:0] = {esprm,2'b00,sprdat0[1:0]};
       else // output higher numbered sprite
      sprdata[7:0] = {osprm,2'b00,sprdat1[1:0]};
  end
  else if (nsprite[3:2]!=2'b00) // sprites 2,3 non transparant ?
  begin
    if (attach3 || (!aga && attach2)) // sprites are attached -> 15 colors + transparant
      sprdata[7:0] = {osprm,sprdat3[1:0],sprdat2[1:0]};
       else if (nsprite[2]) // output lowered number sprite
      sprdata[7:0] = {esprm,2'b01,sprdat2[1:0]};
       else // output higher numbered sprite
      sprdata[7:0] = {osprm,2'b01,sprdat3[1:0]};
  end
  else if (nsprite[5:4]!=2'b00) // sprites 4,5 non transparant ?
  begin
    if (attach5 || (!aga && attach4)) // sprites are attached -> 15 colors + transparant
      sprdata[7:0] = {osprm,sprdat5[1:0],sprdat4[1:0]};
       else if (nsprite[4]) // output lowered number sprite
      sprdata[7:0] = {esprm,2'b10,sprdat4[1:0]};
       else // output higher numbered sprite
      sprdata[7:0] = {osprm,2'b10,sprdat5[1:0]};
  end
  else if (nsprite[7:6]!=2'b00) // sprites 6,7 non transparant ?
  begin
    if (attach7 || (!aga && attach6)) // sprites are attached -> 15 colors + transparant
      sprdata[7:0] = {osprm,sprdat7[1:0],sprdat6[1:0]};
       else if (nsprite[6]) // output lowered number sprite
      sprdata[7:0] = {esprm,2'b11,sprdat6[1:0]};
       else // output higher numbered sprite
      sprdata[7:0] = {osprm,2'b11,sprdat7[1:0]};
  end
  else // all sprites transparant
  begin
    sprdata[7:0] = 8'b00000000;
  end
end

//--------------------------------------------------------------------------------------

endmodule

