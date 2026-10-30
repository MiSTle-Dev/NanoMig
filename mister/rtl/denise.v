////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Copyright 2006, 2007 Dennis van Weeren                                     //
// Copyright 2008, Jakub Bednarski                                            //
// Copyright 2011-2015, Rok Krajnc                                            //
//                                                                            //
// This file is part of Minimig                                               //
//                                                                            //
// Minimig is free software; you can redistribute it and/or modify            //
// it under the terms of the GNU General Public License as published by       //
// the Free Software Foundation; either version 3 of the License, or          //
// (at your option) any later version.                                        //
//                                                                            //
// Minimig is distributed in the hope that it will be useful,                 //
// but WITHOUT ANY WARRANTY; without even the implied warranty of             //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              //
// GNU General Public License for more details.                               //
//                                                                            //
// You should have received a copy of the GNU General Public License          //
// along with this program.  If not, see <http://www.gnu.org/licenses/>.      //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// This is Denise                                                             //
// This module  is a complete implementation of the Amiga OCS Denise chip     //
// It supports all OCS modes including HAM, EHB and interlaced video          //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


module denise (
  input  wire           clk,            // 28MHz clock
  input  wire           clk7_en,        // 7MHz clock enable
  input  wire           c1 ,            // 35ns clock enable signals (for synchronization with clk)
  input  wire           c3,
  input  wire           cck,            // colour clock enable
  input  wire           reset,          // reset
  input wire ham_frame_start,
  input wire [15:0] ham_control,
  input  wire           strhor,         // horizontal strobe
  input  wire           bitplane_dma,
  input  wire           bitplane_fetch_phase,
  input  wire           bitplane_fetch_phase_valid,
  input  wire           bitplane_fetch_unit_start,
  input  wire [  9-1:1] reg_address_in, // register adress inputs
  input  wire [ 16-1:0] data_in,        // bus data in
  input  wire [ 48-1:0] chip48,         // big chipram read
  output wire [ 16-1:0] data_out,       // bus data out
  input  wire           blank,          // blanking input
  output wire [  8-1:0] red,            // red componenent video out
  output wire [  8-1:0] green,          // green component video out
  output wire [  8-1:0] blue,           // blue component video out
  input  wire           a1k,            // control EHB chipset feature
  input  wire           ecs,            // enables ECS chipset features
  input  wire           aga,            // enables AGA features
  output wire           hires,          // hires
  output wire           shres           // shres
);


// register names and adresses
parameter DIWSTRT  = 9'h08e;
parameter DIWSTOP  = 9'h090;
parameter DIWHIGH  = 9'h1e4;
parameter BPLCON0  = 9'h100;
parameter BPLCON2  = 9'h104;
parameter BPLCON3  = 9'h106;
parameter BPLCON4  = 9'h10c;
parameter DENISEID = 9'h07c;
parameter BPL1DAT  = 9'h110;
parameter COLORBASE = 9'h180;


// local signals
reg    [8:0] hpos;        // horizontal beamcounter
reg [3:0] ham_raw_bpu;
always @(posedge clk) begin
 if(reset)ham_raw_bpu<=0;
 else if(clk7_en && reg_address_in[8:1]==BPL1DAT[8:1])ham_raw_bpu<=bpu;
end
reg    [3:0] l_bpu;      // latched bitplane enable

reg    [8:0] hdiwstrt;      // horizontal display window start position
reg    [8:0] hdiwstop;      // horizontal display window stop position
reg    [1:0] hdiwstrt_lo;
reg    [1:0] hdiwstop_lo;

wire  [8:1] bpldata_out;    // bitplane serial data out from shifters
wire bpl_pixel_tick;
wire  [8:1] bpldata;      // raw bitplane serial video data
wire  [7:0] sprdata;      // sprite serial video data
wire  [7:0] plfdata;      // playfield serial video data
wire  [2:1] nplayfield;    // playfield 1,2 valid data signals
wire  [7:0] nsprite;      // sprite 0-7 valid data signals
wire  sprsel;          // sprite select

wire  [23:0] ham_rgb;      // hold and modify mode RGB video data
reg    [7:0] clut_data;    // colour table colour select in
reg    window;          // window enable signal

wire  [15:0] deniseid_out;   // deniseid data_out
wire  [15:0] col_out;      // collision detection data_out
wire  [15:0] rgb_out;      // RGB data_out (rdram)

reg    display_ena;          // in OCS sprites are visible between first write to BPL1DAT and end of scanline

//--------------------------------------------------------------------------------------

// data out multiplexer
assign data_out = col_out | deniseid_out | rgb_out;

//--------------------------------------------------------------------------------------

// Denise horizontal counter counting range: $01-$E3 CCKs (2-455 lores pixels)
always @(posedge clk)
  if (clk7_en) begin
    if (strhor)
      hpos <= 9'd2;
    else
      hpos <= hpos + 9'd1;
  end

//--------------------------------------------------------------------------------------

// sprite display enable signal - sprites are visible after the first write to the BPL1DAT register in a scanline
always @(posedge clk)
  if (clk7_en) begin
    if (reset || blank)
      display_ena <= 0;
    else if (reg_address_in[8:1]==BPL1DAT[8:1])
      display_ena <= 1;
  end

// BPLCON0 register
reg  [16-1:0] bplcon0;    // bplcon0 register
//wire          hires;      // hires (640*200/640*400 interlace) mode
wire [ 4-1:0] bpu;        // bit planes used
wire          ham;        // hold and modify mode
wire          dpf;        // double playfield mode
//wire          color;      // color burst output signal
//wire          gaud;       // genlock audio enable
//wire          uhres;      // ultra-hires enables the UHRES pointers; needs bits in DMACON also
//wire          shres;      // super-hires mode
//wire          bypass;     // bypass color table; 8-bit wide data appears on r[7:0]
//wire          lpen;       // light pen enable
//wire          lace;       // interlace enable
//wire          ersy;       // external resync
wire          ecsena;     // disables BRDRBLNK,BRDNTRAN,ZDCLKEN,BRDSPRT, and EXTBLKEN bits in BPLCON3

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      bplcon0 <= #1 16'h0000;
    else if (reg_address_in[8:1] == BPLCON0[8:1])
      bplcon0[15:0] <= #1 data_in[15:0];
  end
end

assign hires    = bplcon0[15];
assign bpu      = {bplcon0[4] & aga, bplcon0[14:12]};
assign ham      = bplcon0[11];
assign dpf      = bplcon0[10];
//assign color    = bplcon0[9];
//assign gaud     = bplcon0[8];
//assign uhres    = bplcon0[7];
assign shres    = bplcon0[6];
//assign bypass   = bplcon0[5];
//assign lpen     = bplcon0[3];
//assign lace     = bplcon0[2];
//assign ersy     = bplcon0[1];
assign ecsena   = bplcon0[0];

// bpu is updated when bpl1dat register is written
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reg_address_in[8:1]==BPL1DAT[8:1])
      if (aga)
        l_bpu <= #1 bpu;
      else
        l_bpu <= #1 bpu == 4'd7 ? 4'd6 : bpu; // Denise thinks this is EHB 6-plane mode
  end
end

// BPLCON2 register
reg  [16-1:0] bplcon2;    // bplcon2 register
wire          rdram;      // read the color table instead of writing to it
wire          killehb;    // disable ehb mode

always @(posedge clk) begin
  if (clk7_en) begin
    if (reset)
      bplcon2 <= 16'h0000;
    else if (reg_address_in[8:1]==BPLCON2[8:1])
      bplcon2[15:0] <= data_in[15:0];
  end
end

assign rdram = bplcon2[8] & aga;
assign rgb_out = (reg_address_in[8:6] == COLORBASE[8:6]) && rdram
                   ? {4'b0000, loct ? {clut_rgb[19:16], clut_rgb[11:8], clut_rgb[3:0]}
                                    : {clut_rgb[23:20], clut_rgb[15:12], clut_rgb[7:4]}}
                   : 16'h0000;
assign killehb = bplcon2[9] & ecs;

// BPLCON3 register
reg  [16-1:0] bplcon3;    // bplcon3 register
wire [ 3-1:0] bank;       // color bank select
wire [ 3-1:0] pf2of;      // bitplane color table offset when playfield 2 has priority in dpf mode
wire          loct;       // 12-bit color palette select
wire [ 2-1:0] spres;      // sprite resolution select
wire          brdrblnk;   // border blank enable; disabled when ECSENA is low
//wire          brdntran;   // border area is non-transparent; disabled when ECSENA is low
//wire          zdclken;    // zd pin ??
wire          brdsprt;    // enable srpites outside the display window; disabled when ECSENA is low
//wire          extblken;   // causes blank output to be programmable; disabled when ECSENA is low

always @(posedge clk) begin
  if (clk7_en) begin
    if (reset)
      bplcon3 <= 16'h0c00;
    else if (reg_address_in[8:1] == BPLCON3[8:1])
      bplcon3[15:0] <= data_in[15:0];
  end
end

assign bank     = bplcon3[15:13] & {3{aga}};
assign pf2of    = bplcon3[12:10];
assign loct     = bplcon3[9] & aga;
assign spres    = bplcon3[7:6] & {2{aga}};
assign brdrblnk = bplcon3[5] & ecsena;
//assign brdntran = bplcon3[4] & ecsena;
//assign zdclken  = bplcon3[2] & ecsena;
assign brdsprt  = bplcon3[1] & ecsena;
//assign extblken = bplcon3[0] & ecsena;

// BPLCON4 register
reg  [16-1:0] bplcon4;    // bplcon3 register
reg  [ 8-1:0] bplxor;     // color select xor value
reg  [ 4-1:0] esprm;      // even sprites 4 MSB color table address
reg  [ 4-1:0] osprm;      // odd sprites 4 MSB color table address

always @(posedge clk) begin
  if (clk7_en) begin
    if (reset)
      bplcon4 <= 16'h0011;
    else if (aga && (reg_address_in[8:1] == BPLCON4[8:1]))
      bplcon4[15:0] <= data_in[15:0];
  end
end

// BPLCON4 values are delayed for 1 lores pixel - TODO double-check this!
// AMR - bplxor is active from first write to BPL1DAT until DIWSTOP. (Fixes Andromeda: Nexus 7, shade cluster part)
always @ (posedge clk) begin
  if (clk7_en) begin
    if(reset || hpos[8:0]==hdiwstop[8:0])
      bplxor   <= 8'd0;
	else if (display_ena)
      bplxor   <= bplcon4[15:8];
  end
end
// AMR - FIXME - should be the sprite colour offsets be treated as per bplxor? Probably not since sprites can appear in the border.
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset) begin
      esprm    <= 4'd1;
      osprm    <= 4'd1;
    end else begin
      esprm    <= bplcon4[7:4];
      osprm    <= bplcon4[3:0];
    end
  end
end


// DIWSTART and DIWSTOP registers (vertical and horizontal limits of display window)

// HDIWSTRT
always @(posedge clk)
  if (clk7_en) begin
    if (reg_address_in[8:1]==DIWSTRT[8:1])
      hdiwstrt[7:0] <= data_in[7:0];
  end

always @(posedge clk)
  if (clk7_en) begin
    if (reg_address_in[8:1]==DIWSTRT[8:1])
      {hdiwstrt[8],hdiwstrt_lo} <= 3'b000; // diwstop H9 = 0
    else if (reg_address_in[8:1]==DIWHIGH[8:1] && ecs)
      {hdiwstrt[8],hdiwstrt_lo} <= {data_in[5],aga ? data_in[4:3] : 2'b00};
  end

// HDIWSTOP
always @(posedge clk)
  if (clk7_en) begin
    if (reg_address_in[8:1]==DIWSTOP[8:1])
      hdiwstop[7:0] <= data_in[7:0];
  end

always @(posedge clk)
  if (clk7_en) begin
    if (reg_address_in[8:1]==DIWSTOP[8:1])
      {hdiwstop[8],hdiwstop_lo} <= 3'b100; // diwstop H8 = 1
    else if (reg_address_in[8:1]==DIWHIGH[8:1] && ecs)
      {hdiwstop[8],hdiwstop_lo} <= {data_in[13],aga ? data_in[12:11] : 2'b00};
  end

assign deniseid_out = reg_address_in[8:1]==DENISEID[8:1] ? aga ? 16'h00f8 : ecs ? 16'hfffc : 16'hffff : 16'h0000;

//--------------------------------------------------------------------------------------

// generate window enable signal
// true when beamcounter satisfies horizontal diwstrt/diwstop limits
reg  [2:0] strt_d, stop_d;
wire [3:0] strt_s = {strt_d, clk7_en && hpos[8:0]==hdiwstrt[8:0]};
wire [3:0] stop_s = {stop_d, clk7_en && hpos[8:0]==hdiwstop[8:0]};

always @(posedge clk) begin
  strt_d <= strt_s[2:0];
  stop_d <= stop_s[2:0];
  if (strt_s[hdiwstrt_lo])
    window <= 1;
  else if (stop_s[hdiwstop_lo])
    window <= 0;
end

reg [3:0] window_d;
always @(posedge clk) window_d <= {window_d[2:0], window};
wire window_ena = window_d[3];

//--------------------------------------------------------------------------------------

// instantiate bitplane module
denise_bitplanes bplm0
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .c1(c1),
  .c3(c3),
  .aga(aga),
  .reg_address_in(reg_address_in),
  .data_in(data_in),
  .chip48(chip48),
  .hires(hires),
  .shres(shres & ecs),
  .hpos(hpos),
  .strhor(strhor),
  .bitplane_dma(bitplane_dma),
  .bitplane_fetch_phase(bitplane_fetch_phase),
  .bitplane_fetch_phase_valid(bitplane_fetch_phase_valid),
  .bitplane_fetch_unit_start(bitplane_fetch_unit_start),
  .blank(blank),
  .hdiw(window),
  .planes(bpu),
  .bpldata(bpldata_out),
  .pixel_tick(bpl_pixel_tick)
);

// AMR - mask bpldata against window_ena, so that the HAM generator always receives
// the background colour outside the display window, to prevent the HAM generator
// reacting to pixels scrolled off the left hand side of the screen.
// Fixes Desire: Hamazing's "Hambarger" scene.
assign bpldata[1] = window_ena && (l_bpu > 0) ? bpldata_out[1] : 1'b0;
assign bpldata[2] = window_ena && (l_bpu > 1) ? bpldata_out[2] : 1'b0;
assign bpldata[3] = window_ena && (l_bpu > 2) ? bpldata_out[3] : 1'b0;
assign bpldata[4] = window_ena && (l_bpu > 3) ? bpldata_out[4] : 1'b0;
assign bpldata[5] = window_ena && (l_bpu > 4) ? bpldata_out[5] : 1'b0;
assign bpldata[6] = window_ena && (l_bpu > 5) ? bpldata_out[6] : 1'b0;
assign bpldata[7] = window_ena && (l_bpu > 6) ? bpldata_out[7] : 1'b0;
assign bpldata[8] = window_ena && (l_bpu > 7) ? bpldata_out[8] : 1'b0;

// instantiate playfield module
denise_playfields plfm0
(
  .aga (aga),
  .bpldata(bpldata),
  .dblpf(dpf),
  .pf2of(pf2of),
  .bplcon2(bplcon2[6:0]),
  .nplayfield(nplayfield),
  .plfdata(plfdata)
);

// instantiate sprite module

wire [1:0] spres_d;
assign spres_d = (spres == 2'b00) ? shres ? 2'b10 : 2'b01 : spres;

denise_sprites sprm0
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .c1(c1),
  .c3(c3),
  .aga(aga),
  .reg_address_in(reg_address_in),
  .hpos(hpos),
  .data_in(data_in),
  .chip48(chip48),
  .sprena(display_ena | brdsprt),
  .esprm(esprm),
  .osprm(osprm),
  .spres(spres_d),
  .nsprite(nsprite),
  .sprdata(sprdata)
);

// instantiate video priority logic module
wire [2:1] nplayfield_masked = nplayfield & {window_ena,window_ena};
denise_spritepriority spm0
(
  .bplcon2(bplcon2[5:0]),
  .nplayfield(nplayfield_masked),
  .nsprite(nsprite),
  .sprsel(sprsel)
);

// instantiate colour look up table
wire  [24-1:0] clut_rgb;    // colour table rgb data out
wire           ehb_en;      // ehb enable

assign ehb_en = !killehb && !a1k && !ham && !dpf && (l_bpu == 4'd6);

denise_colortable clut0
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reg_address_in(reg_address_in),
  .data_in(data_in[11:0]),
  .rdram(rdram),
  .select(clut_data),
  .bplxor(bplxor),
  .bank(bank),
  .loct(loct),
  .ehb_en(ehb_en),
  .rgb(clut_rgb) // rgb data is delayed by one clk28m clock cycle
);

// instantiate HAM (hold and modify) module
wire ham8 = ham && (l_bpu == 4'd8);
wire ham_sel = ham;// && ((l_bpu == 4'd6) || (l_bpu == 4'd8));

denise_hamgenerator ham0
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reg_address_in(reg_address_in),
  .data_in(data_in[11:0]),
  .select(bpldata),
  .bplxor(bplxor),
  .bank(bank),
  .loct(loct),
  .ham8(ham8),
  .rgb(ham_rgb)
);

// AGA lowres, hires and superhires, single playfield. Up to eight planes
// require FMODE=1/2 in hires and FMODE=3 in superhires.
// AGA is required for the complete 8-bit palette and eight bitplanes.
wire ext_supported = aga && !dpf;
// Keep the established lowres phase. Hires follows the actual scroller
// output event, including its fine-scroll pipeline delay.
wire ext_pixel_tick = (hires || shres) ? bpl_pixel_tick : (c1 && c3);
wire ext_selected = ham_control[15] && ext_supported &&
 ((ham_raw_bpu==3)||(ham_raw_bpu==4)||(ham_raw_bpu==5)||
  (ham_raw_bpu==6)||(ham_raw_bpu==8));
wire [23:0] ext_rgb;
wire ext_rgb_valid;
ham_video_pipeline ext_ham (
 .clk(clk),.reset(reset),.frame_start(ham_frame_start),
 .pixel_valid(ext_selected && window_ena && !blank && display_ena && ext_pixel_tick),
 .planes(ham_raw_bpu),.code(bpldata),.control(ham_control),
 .clk7_en(clk7_en),.reg_address_in(reg_address_in),.data_in(data_in[11:0]),
 .bank(bank),.loct(loct),.rdram(rdram),.rgb(ext_rgb),.rgb_valid(ext_rgb_valid)
);

// instantiate collision detection module
denise_collision col0
(
  .clk(clk),
  .clk7_en(clk7_en),
  .reset(reset),
  .aga(aga),
  .reg_address_in(reg_address_in),
  .data_in(data_in),
  .data_out(col_out),
  .dblpf(dpf),
  .bpldata(bpldata),
  .nsprite(nsprite)
);


always @(*) begin
  if (brdsprt && sprsel) // select border sprites
    clut_data = sprdata;
  else if (!window_ena) // we are outside of the visible window region, display border colour
    clut_data = 8'b000000;
  else if (sprsel) // select sprites
    clut_data = sprdata;
  else // select playfield
    clut_data = plfdata ^ bplxor;
end

reg window_del;
reg sprsel_del;

always @(posedge clk) begin
  window_del <= window_ena;
  sprsel_del <= sprsel;
end

// ham_rgb / clut_rgb multiplexer
wire  [24-1:0] out_rgb  = ham_sel && window_del && !sprsel_del ? ham_rgb : clut_rgb; //if no HAM mode, always select normal (table selected) rgb data

//--------------------------------------------------------------------------------------

wire t_blank;

assign t_blank = /*blank |*/ (ecs & ecsena & brdrblnk & (~window_del | ~display_ena));

// RGB video output
// The extension adds one clock after the normal palette latency. Delay
// border/sprites and their selection together only while the extension is on.
reg [23:0] ext_normal_rgb;
reg ext_window,ext_sprite,ext_blank,ext_on;
always @(posedge clk) begin
 ext_normal_rgb<=out_rgb;ext_window<=window_del;ext_sprite<=sprsel_del;
 ext_blank<=t_blank;ext_on<=ext_selected;
end
wire [23:0] ext_output = ext_window && !ext_sprite ? ext_rgb : ext_normal_rgb;
assign {red[7:0],green[7:0],blue[7:0]} = ext_on ?
 (ext_blank ? 24'h000000 : ext_output) : (t_blank ? 24'h000000 : out_rgb);


endmodule

