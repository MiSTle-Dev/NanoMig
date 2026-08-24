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
// This is the bitplane part of denise
// It accepts data from the bus and converts it to serial video data (6 bits).
// It supports all ocs modes and also handles the pf1<->pf2 priority handling in
// a seperate module.

// ----------------------------------------------------------------------------
// Copyright 2026 Mateusz Nalewajski
//
// This is EBR refactor of bitplanes to optimize FF resource usage on
// ECP5 platform; with a valid BRAM primitive can be adapted to other FPGAs
// ----------------------------------------------------------------------------

module denise_bitplanes
(
  input   clk,             // system bus clock
  input   clk7_en,
  input   reset,
  input   c1,            // 35ns clock enable signals (for synchronization with clk)
  input   c3,
  input   aga,
  input   [8:1] reg_address_in,   // register address
  input   [15:0] data_in,       // bus data in
  input   [15:0] chip16_r,
  input   [1:0] chip16_idx,
  input   hires,             // high resolution mode select
  input   shres,             // super high resolution mode select
  input   [8:0] hpos,        // horizontal position (70ns resolution)
  output   [8:1] bpldata      // bitplane data out
);


//register names and adresses
parameter BPLCON1     = 9'h102;
parameter BPLXDATBASE = 9'h110;
parameter FMODE       = 9'h1fc;

//local signals
wire    selbpl1;        // select bitplane 0
wire    selbpl2;        // select bitplane 1
wire    selbpl3;        // select bitplane 2
wire    selbpl4;        // select bitplane 3
wire    selbpl5;        // select bitplane 4
wire    selbpl6;        // select bitplane 5
wire    selbpl7;        // select bitplane 6
wire    selbpl8;        // select bitplane 7

reg   [15:0] bplcon1;    // bplcon1 register
reg   [15:0] fmode;     // fmod reg
reg    load;        // bpl1dat written => load shift registers

reg    [7:0] extra_delay_f0;  // extra delay when not alligned ddfstart
reg    [7:0] extra_delay_f12;
reg    [7:0] extra_delay_f3;
reg    [7:0] extra_delay_r;
reg    [7:0] pf1h;      // playfield 1 horizontal scroll
reg    [7:0] pf2h;      // playfield 2 horizontal scroll
reg    [7:0] pf1h_del;    // delayed playfield 1 horizontal scroll
reg    [7:0] pf2h_del;    // delayed playfield 2 horizontal scroll

//--------------------------------------------------------------------------------------

// sprite register address decoder
wire  selbplx;

assign selbplx = BPLXDATBASE[8:4]==reg_address_in[8:4];
assign selbpl1 = selbplx && reg_address_in[3:1]==3'd0;
assign selbpl2 = selbplx && reg_address_in[3:1]==3'd1;
assign selbpl3 = selbplx && reg_address_in[3:1]==3'd2;
assign selbpl4 = selbplx && reg_address_in[3:1]==3'd3;
assign selbpl5 = selbplx && reg_address_in[3:1]==3'd4;
assign selbpl6 = selbplx && reg_address_in[3:1]==3'd5;
assign selbpl7 = selbplx && reg_address_in[3:1]==3'd6;
assign selbpl8 = selbplx && reg_address_in[3:1]==3'd7;

//--------------------------------------------------------------------------------------

// horizontal scroll depends on horizontal position when BPL0DAT in written
// visible display scroll is updated on fetch boundaries
// increasing scroll value during active display inserts blank pixels

always @(hpos)
  case (hpos[3:2])
    2'b00 : extra_delay_f0 = 8'b00_0000_00;
    2'b01 : extra_delay_f0 = 8'b00_1100_00;
    2'b10 : extra_delay_f0 = 8'b00_1000_00;
    2'b11 : extra_delay_f0 = 8'b00_0100_00;
  endcase

always @(hpos)
  case (hpos[4:3]) // AMR - FIXME - will probably need to adjust these too.
    2'b00 : extra_delay_f12 = 8'b00_0000_00;
    2'b01 : extra_delay_f12 = 8'b01_1000_00;
    2'b10 : extra_delay_f12 = 8'b01_0000_00;
    2'b11 : extra_delay_f12 = 8'b00_1000_00;
  endcase

always @(hpos)
  case (hpos[5:2]) // AMR - adjust fetch offsets
    4'b0000 : extra_delay_f3 = 8'b00_0000_00;
    4'b0001 : extra_delay_f3 = 8'b11_1100_00;
    4'b0010 : extra_delay_f3 = 8'b11_1000_00;
    4'b0011 : extra_delay_f3 = 8'b11_0100_00;
    4'b0100 : extra_delay_f3 = 8'b11_0000_00;
    4'b0101 : extra_delay_f3 = 8'b10_1100_00;
    4'b0110 : extra_delay_f3 = 8'b10_1000_00;
    4'b0111 : extra_delay_f3 = 8'b10_0100_00;
    4'b1000 : extra_delay_f3 = 8'b10_0000_00;
    4'b1001 : extra_delay_f3 = 8'b01_1100_00;
    4'b1010 : extra_delay_f3 = 8'b01_1000_00;
    4'b1011 : extra_delay_f3 = 8'b01_0100_00;
    4'b1100 : extra_delay_f3 = 8'b01_0000_00;
    4'b1101 : extra_delay_f3 = 8'b00_1100_00;
    4'b1110 : extra_delay_f3 = 8'b00_1000_00;
    4'b1111 : extra_delay_f3 = 8'b00_0100_00;
  endcase

always @ (posedge clk) begin
  if (clk7_en) begin
    if (load) extra_delay_r <= #1 (fmode[1:0] == 2'b00) ? extra_delay_f0 : (fmode[1:0] == 2'b11) ? extra_delay_f3 : extra_delay_f12;
  end
end

//playfield 1 effective horizontal scroll
always @(posedge clk)
  if (clk7_en) begin
    if (load)
      pf1h <= {bplcon1[11:10],bplcon1[3:0],bplcon1[9:8]};
  end

always @(posedge clk)
  if (clk7_en) begin
    pf1h_del <= pf1h + extra_delay_r;
  end

//playfield 2 effective horizontal scroll
always @(posedge clk)
  if (clk7_en) begin
    if (load)
      pf2h <= {bplcon1[15:14],bplcon1[7:4],bplcon1[13:12]};
  end

always @(posedge clk)
  if (clk7_en) begin
    pf2h_del <= pf2h + extra_delay_r;
  end

//writing bplcon1 register : horizontal scroll codes for even and odd bitplanes
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      bplcon1 <= #1 16'h3300;
    if ((reg_address_in[8:1] == BPLCON1[8:1]))
      bplcon1 <= #1 aga ? data_in[15:0] : {2'b00,2'b11,2'b00,2'b11,data_in[7:0]};
  end

// fmode
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      fmode <= #1 16'h0000;
    else if (aga && (reg_address_in[8:1] == FMODE[8:1]))
      fmode <= #1 data_in;
  end
end

//--------------------------------------------------------------------------------------
// shared bitplane-shifter control
//
// The BRAM read pointer, shift index and shift/load timing are identical in
// every plane (they depend only on load, c1, c3, fmode and the shared bank
// count), so they are generated here ONCE instead of being replicated inside
// each of the 8 denise_bitplane_shifter instances. Only the per-plane data
// path (BRAM contents, shifter, scroller, output) lives in the shifter itself.
//--------------------------------------------------------------------------------------

wire [1:0] bpl_bankwr_idx;    // BRAM write bank index
reg  [2:0] bpl_bankrd_idx;    // BRAM read bank index
reg  [2:0] bpl_bankrd_num;    // BRAM max read bank index

assign bpl_bankwr_idx = chip16_idx;

always @(posedge clk) begin
  if (clk7_en) begin
    // generate load signal when plane 1 is written
    load <= selbpl1;
  end
end

reg [5:0] fmode_mask;    // fetchmode mask
reg       shift;         // shifter enable
reg [2:0] shiftidx;      // current shift index

// c1 is the 7MHz clock, c3 the same clock shifted 90deg; together they mark
// the four phases of a 7MHz period within the 28MHz clk domain
wire ld_start   = selbpl1 & clk7_en;       // fetch start
wire ld_pix     = load & ~c1 & ~c3;        // load first byte (c1,c3 = 0,0)
wire idx_last   = &shiftidx;               // current byte shifted out
wire fetch_next = shift & idx_last;        // time to advance to next byte
wire reload     = fetch_next & (bpl_bankrd_idx != bpl_bankrd_num);
wire shifter_load = ld_pix | reload;       // load strobe fed to every shifter

// BRAM addresses shared by all planes (writes 16-bit, reads 8-bit)
wire [1:0] ram_addra = bpl_bankwr_idx;
wire [2:0] ram_addrb = bpl_bankrd_idx;

// fetchmode mask
always @ (*) begin
  case (fmode[1:0])
    2'b00 : fmode_mask = 6'b00_1111;
    2'b01,
    2'b10 : fmode_mask = 6'b01_1111;
    2'b11 : fmode_mask = 6'b11_1111;
  endcase
end

// shifter enable: lowres shifts once every 4 cycles, hires every other, shres always
always @ (*) begin
  if (shres)      shift = 1'b1;
  else if (hires) shift = ~c1 ^ c3;
  else            shift = ~c1 & ~c3;
end

// bank read/write address control
always @ (posedge clk) begin
  // one 7MHz cycle after bpldat1 write
  if (load && clk7_en) begin
    // set number of banks to be read according to fmode
    case(fmode[1:0])
      2'b11   : bpl_bankrd_num <= 0;
      2'b10,
      2'b01   : bpl_bankrd_num <= 4;
      default : bpl_bankrd_num <= 2;
    endcase
  end

  if (ld_start) begin
    // reset read bank index
    bpl_bankrd_idx <= 3'd0;

  end else if (shifter_load) begin
    // advance BRAM read address in lockstep with the shifter reload
    bpl_bankrd_idx <= bpl_bankrd_idx + 3'd1;
  end
end

// shift index
always @ (posedge clk) begin
  if (shifter_load)
    shiftidx <= 3'd0;
  else if (shift)
    shiftidx <= shiftidx + 3'd1;
end

//--------------------------------------------------------------------------------------

//instantiate the 8 bitplane parallel to serial converters; odd planes scroll
//with playfield 1, even planes with playfield 2. All shared control is wired
//in identically; only aen, scroll and out differ per plane.
wire [8:1] selbpl = {selbpl8, selbpl7, selbpl6, selbpl5, selbpl4, selbpl3, selbpl2, selbpl1};

genvar i;
generate
  for (i = 1; i <= 8; i = i + 1) begin : bplshft
    denise_bitplane_shifter bplshft
    (
      .clk(clk),
      .clk7_en(clk7_en),
      .aen(selbpl[i]),
      .bpl1(i == 1),
      .shift(shift),
      .shifter_load(shifter_load),
      .ld_start(ld_start),
      .ram_addra(ram_addra),
      .ram_addrb(ram_addrb),
      .bpl_dat(chip16_r),
      .fmode_mask(fmode_mask),
      .hires(hires),
      .shres(shres),
      .aga(aga),
      .scroll((i % 2) ? pf1h_del : pf2h_del),  // odd plane -> pf1, even -> pf2
      .out(bpldata[i])
    );
  end
endgenerate

endmodule

