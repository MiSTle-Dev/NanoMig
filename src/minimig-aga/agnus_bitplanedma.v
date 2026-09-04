////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Copyright 2006, 2007 Dennis van Weeren                                     //
// Copyright 2008, Jakub Bednarski                                            //
// Copyright 2011-20015, Rok Krajnc                                           //
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
// Bitplane DMA engine                                                        //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


module agnus_bitplanedma (
  input  wire           clk,              // 28MHz clock
  input  wire           clk7_en,          // 7MHz clock enable
  input  wire           reset,            // reset
  input  wire           harddis,
  input  wire           aga,              // aga config
  input  wire           ecs,              // ddfstrt/ddfstop ECS bits enable
  input  wire           a1k,              // DIP Agnus feature
  input  wire           sof,              // start of frame
  input  wire           dmaena,           // enable dma input
  input  wire [ 11-1:0] vpos,             // vertical position counter
  input  wire [  9-1:0] hpos,             // agnus internal horizontal position counter (advanced by 4 CCK)
  output reg            hde,              // video data enable (horizontal)
  output wire           dma,              // true if bitplane dma engine uses it's cycle
  input  wire [  9-1:1] reg_address_in,   // register address inputs
  output reg  [  9-1:1] reg_address_out,  // register address outputs
  input  wire [ 16-1:0] data_in,          // bus data in
  output wire [ 21-1:1] address_out       // chip address out
);


// register names and adresses
localparam DIWSTRT_REG   = 9'h08E;
localparam DIWSTOP_REG   = 9'h090;
localparam DIWHIGH_REG   = 9'h1E4;
localparam BPLPTBASE_REG = 9'h0E0; // bitplane pointers base address
localparam DDFSTRT_REG   = 9'h092;
localparam DDFSTOP_REG   = 9'h094;
localparam BPL1MOD_REG   = 9'h108;
localparam BPL2MOD_REG   = 9'h10a;
localparam BPLCON0_REG   = 9'h100;
localparam FMODE_REG     = 9'h1fc;

// local signals
reg  [ 8: 2] ddfstrt;             // display data fetch start
reg  [ 8: 2] ddfstop;             // display data fetch stop
wire [ 8: 2] ddfdiff;
wire [ 8: 2] ddfdiff_masked;
reg  [15: 1] bpl1mod;             // modulo for odd bitplanes
reg  [15: 1] bpl2mod;             // modulo for even bitplanes
reg [15: 1] bpl1mod_bscan;        // modulo for odd bitplanes, adjusted for bitplane scandoubling - AMR, and extra delay, for RAMJAM: Copperslave.
reg [15: 1] bpl2mod_bscan;        // modulo for even bitplanes, adjusted for bitplane scandoubling

reg  [ 5: 0] bplcon0;             // bitplane control (SHRES, HIRES and BPU bits)
reg  [ 5: 0] bplcon0_delayed;     // delayed bplcon0 (compatibility)
reg  [ 5: 0] bplcon0_delay [1:0];
reg  [15: 0] fmode;

wire         hires;               // bplcon0 - high resolution display mode
wire         shres;               // bplcon0 - super high resolution display mode
wire [ 3: 0] bpu;                 // bplcon0 - selected number of bitplanes

reg  [20: 1] newpt;               // new pointer
reg  [20:16] bplpth [7:0];        // upper 5 bits bitplane pointers
reg  [15: 1] bplptl [7:0];        // lower 16 bits bitplane pointers
reg  [ 4: 0] plane;               // plane pointer select

wire         mod;                 // end of data fetch, add modulo

reg          hardena;             // hardware display data fetch enable ($18-$D8)
reg          softena;             // software display data fetch enable
reg          ddfena;              // combined display data fetch
reg          ddfena_0;

reg  [ 4: 0] ddfseq;              // bitplane DMA fetch cycle sequencer
reg          ddfrun;              // set when display dma fetches data
reg          ddfend;              // indicates the last display data fetch sequence

reg  [ 1: 0] dmaena_delayed;      // delayed bitplane dma enable signal (compatibility)

reg  [10: 0] vdiwstrt;            // vertical display window start position
reg  [10: 0] vdiwstop;            // vertical display window stop position
reg          vdiwena;             // vertical display window enable

reg    [8:0] hdiwstrt;
reg    [8:0] hdiwstop;

wire [ 2: 0] bplptr_sel;          // bitplane pointer select
wire [20:16] bplpth_in;
wire [15: 1] bplptl_in;
wire         ddfstrt_sel;

wire         bp_fmode0;           // FMODE == 0
wire         bp_fmode12;          // FMODE == 1 || FMODE == 2
wire         bp_fmode3;           // FMODE == 3

reg          soft_start;
reg          soft_stop;
reg          hard_start;
reg          hard_stop;

wire         ddfseq_match;


// display data fetches can take place during blanking (when vdiwstrt is set to 0 the display is distorted)
// diw vstop/vstart conditiotions are continuously checked
// first visible line $1A
// vstop forced by vbl
// last visible line is displayed in colour 0
// vdiwstop = N (M>N)
// wait vpos N-1 hpos $d7, move vdiwstop M : effective
// wait vpos N-1 hpos $d9, move vdiwstop M : non effective

// display not active:
// wait vpos N hpos $dd, move vdiwstrt N : display starts
// wait vpos N hpos $df, move vdiwstrt N : display doesn't start

// if vdiwstrt==vdiwstop : no display
// if vdiwstrt>vdiwstop : display from vdiwstrt till screen bottom

// display dma can be started in the middle of a scanline by setting vdiwstrt to the current line number (ECS only)
// OCS: the display starts when ddfstrt condition is true
// display dma can be stopped in the middle of a scanline by setting vdiwstop to the current line number
// if display starts all enabled planes are fetched
// if hstop is set 4 CCKs after hstart to the same line no display occurs
// if hstop is set 8 CCKs after hstart one 16 pixel chunk is displayed (lowres)

// ECS: DDFSTOP = $E2($E3) display data fetch stopped ($00 stops the display as well)
// ECS: DDFSTOP = $E4 display data fetch not stopped


always @ (posedge clk) begin
	reg [8:0] best_hdiwstrt, cur_hdiwstrt, prev_hdiwstrt;
	reg [8:0] best_hdiwstop, cur_hdiwstop, prev_hdiwstop;
	reg [10:0] d_hde;

	if (clk7_en) begin
		if(!hpos) begin
			if((hdiwstrt < hdiwstop) && ((best_hdiwstop-best_hdiwstrt)<(hdiwstop-hdiwstrt))) begin
				best_hdiwstrt <= hdiwstrt;
				best_hdiwstop <= hdiwstop;
			end
			if(!vpos) begin
				if(best_hdiwstrt || best_hdiwstop) begin
					cur_hdiwstrt <= best_hdiwstrt;
					cur_hdiwstop <= best_hdiwstop;
				end
				best_hdiwstrt <= 0;
				best_hdiwstop <= 0;
			end
		end

		if(hpos == cur_hdiwstrt) d_hde[0] <= 1;
		if(hpos == cur_hdiwstop || !hpos) d_hde[0] <= 0;

		//delay DE. Why??
		d_hde[10:1] <= d_hde[9:0];
		hde <= d_hde[10];
	end
end


// vdiwstart
always @ (posedge clk) begin
	if (clk7_en) begin
		if (reg_address_in[8:1]==DIWSTRT_REG[8:1]) begin
			vdiwstrt <= {3'b000, data_in[15:8]}; // reset V10-V9 when writing DIWSTRT_REG
			hdiwstrt <= {1'b0, data_in[7:0]};
		end else if (reg_address_in[8:1]==DIWHIGH_REG[8:1] && ecs) begin // ECS
			vdiwstrt[10:8] <= data_in[2:0];
			hdiwstrt[8]    <= data_in[5];
		end
	end
end

// vdiwstop
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reg_address_in[8:1]==DIWSTOP_REG[8:1]) begin
      vdiwstop <= {2'b00,~data_in[15], data_in[15:8]}; // V8 = ~V7
		hdiwstop <= {1'b1, data_in[7:0]};
    end else if (reg_address_in[8:1]==DIWHIGH_REG[8:1] && ecs) begin // ECS
      vdiwstop[10:8] <= data_in[10:8];
		hdiwstop[8]    <= data_in[13];
	 end
  end
end

// vertical display window enable
always @ (posedge clk) begin
  if (clk7_en) begin
    if ((sof && ~a1k) || (vpos[10:0]==0 && a1k) || (vpos[10:0]==vdiwstop[10:0])) // DIP Agnus can't start display DMA at scanline 0
      vdiwena <= #1 1'b0;
    else if (vpos[10:0]==vdiwstrt[10:0])
      vdiwena <= #1 1'b1;
  end
end

assign bplptr_sel = dma ? plane[2:0] : reg_address_in[4:2];

// high word pointer register bank (implemented using distributed ram)
assign bplpth_in = dma ? newpt[20:16] : data_in[4:0];

// TODO high bitplane pointer probably needs a delay (writing to pointer doesn't seem to take effect next cycle ...)
always @ (posedge clk) begin
  if (clk7_en) begin
    if (dma || ((reg_address_in[8:5]==BPLPTBASE_REG[8:5]) && !reg_address_in[1])) // if bitplane dma cycle or bus write
      bplpth[bplptr_sel] <= #1 bplpth_in;
  end
end

assign address_out[20:16] = bplpth[plane[2:0]];

// low word pointer register bank (implemented using distributed ram)
assign bplptl_in = dma ? newpt[15:1] : data_in[15:1];

always @ (posedge clk) begin
  if (clk7_en) begin
    if (dma || ((reg_address_in[8:5]==BPLPTBASE_REG[8:5]) && reg_address_in[1])) // if bitplane dma cycle or bus write
      bplptl[bplptr_sel] <= #1 bplptl_in;
  end
end

assign address_out[15:1] = bplptl[plane[2:0]];

assign ddfstrt_sel = reg_address_in[8:1]==DDFSTRT_REG[8:1] ? 1'b1 : 1'b0;

// write ddfstrt and ddfstop registers
always @ (posedge clk) begin
  if (clk7_en) begin
    if (ddfstrt_sel)
      ddfstrt[8:2] <= #1 data_in[7:1];
  end
end

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reg_address_in[8:1]==DDFSTOP_REG[8:1])
      ddfstop[8:2] <= #1 data_in[7:1];
  end
end

// write modulo registers
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reg_address_in[8:1]==BPL1MOD_REG[8:1])
      bpl1mod[15:1] <= #1 data_in[15:1];
  end
end

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reg_address_in[8:1]==BPL2MOD_REG[8:1])
      bpl2mod[15:1] <= #1 data_in[15:1];
  end
end

// write those parts of bplcon0 register that are relevant to bitplane DMA sequencer
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      bplcon0 <= #1 6'b00_0000;
    else if (reg_address_in[8:1]==BPLCON0_REG[8:1])
      bplcon0 <= #1 {data_in[6], data_in[15], aga & data_in[4], data_in[14:12]}; //SHRES,HIRES,BPU3,BPU2,BPU1,BPU0
  end
end

// delay by 8 clocks (in real Amiga DMA sequencer is pipelined and features a delay of 3 CCKs)
// delayed BPLCON0 by 3 CCKs
always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0]) begin
      bplcon0_delay[0] <= #1 bplcon0;
      bplcon0_delay[1] <= #1 bplcon0_delay[0];
      bplcon0_delayed  <= #1 bplcon0_delay[1];
    end
  end
end

assign shres = ecs & bplcon0_delayed[5];
assign hires = bplcon0_delayed[4];
assign bpu = aga ? bplcon0_delayed[3:0] : {1'b0, &bplcon0_delayed[2:0] ? 3'd4 : bplcon0_delayed[2:0]};

// fmode
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      fmode <= #1 16'h0000;
    else if (aga && (reg_address_in[8:1] == FMODE_REG[8:1]))
      fmode <= #1 data_in;
  end
end

assign bp_fmode0  = (fmode[1:0] == 2'b00);
assign bp_fmode12 = (fmode[1:0] == 2'b01) || (fmode[1:0] == 2'b10);
assign bp_fmode3  = (fmode[1:0] == 2'b11);

// bitplane dma enable bit delayed by 4 CCKs
always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[1:0]==2'b11)
      dmaena_delayed[1:0] <= #1 {dmaena_delayed[0], dmaena};
  end
end


//  Display DMA can start and stop on any (within hardware limits) 2-CCK boundary regardless of a choosen resolution.
//  Non-aligned start position causes addition of extra shift value to horizontal scroll.
//  This values depends on which horizontal position BPL0DAT register is written.
//  One full display DMA sequence lasts 8 CCKs. When sequence restarts finish condition is checked (ddfstop position passed).
//  The last DMA sequence adds modulo to bitplane pointers.
//  The state of BPLCON0 is delayed by 3 CCKs (real Agnus has pipelining in DMA engine).
//
//  ddf start condition is checked 2 CCKs before actual position, ddf stop is checked 4 CCKs in advance <- that's not true
//  ddf start condition is checked 4 CCKs before the first bitplane data fetch
//  magic: writing DDFSTRT register when the hpos=ddfstrt doesn't start the bitplane DMA

always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0])
      if (hpos[8:1]=={ddfstrt[8:3], ddfstrt[2] & ecs, 1'b0})
        soft_start <= #1 1'b1;
      else
        soft_start <= #1 1'b0;
  end
end

always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0])
      if (hpos[8:1] == {ddfstop[8:3], ddfstop[2] & ecs, 1'b0})
        soft_stop <= #1 1'b1;
      else
        soft_stop <= #1 1'b0;
  end
end

always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0])
      if (hpos[8:1]==8'h18)
        hard_start <= #1 1'b1;
      else
        hard_start <= #1 1'b0;
  end
end

always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0])
      if (hpos[8:1]==8'hD8)
        hard_stop <= #1 1'b1;
      else
        hard_stop <= #1 1'b0;
  end
end

// softena : software display data fetch window

// AMR - OCS and ECS/AGA behave differently when DDFSTRT == DDFSTOP.
// On OCS the fetch runs until hard_stop. On ECS/AGA it stops after one complete fetch cycle.
reg softena_off;

always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0]) begin
      if (soft_start && (ecs || vdiwena && dmaena) && !ddfstrt_sel) // OCS: display can start only when vdiwena condition is true
        softena <= #1 1'b1;
      else if (softena_off || (soft_stop || !ecs && hard_stop))
        softena <= #1 1'b0;
      softena_off<=soft_stop && soft_start && ecs;  // AMR - ECS / AGA: DDFSTRT==DDFSTOP, disable fetch after one fetch cycle.
    end
  end
end

// hardena : hardware limits of display data fetch
always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0])
      if (hard_start)
        hardena <= #1 1'b1;
      else if (hard_stop)
        hardena <= #1 1'b0;
  end
end

// ddfena signal is set and cleared 2 CCKs before actual transfer should start or stop
// delayed DDFENA by 2 CCKs
always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0]) begin
      ddfena_0 <= #1 (hardena || harddis) && softena;
      ddfena <= #1 ddfena_0;
    end
  end
end

// this signal is for matching ddfseq with last dma cycle (after ddfstop)
assign ddfseq_match = ((!hires && !shres && bp_fmode3)                            && (ddfseq[4:0] == 5'd7)) ||
                      (((!shres && !hires && bp_fmode12) || (hires && bp_fmode3)) && (ddfseq[3:0] == 4'd7)) ||
                      (!(!hires && !shres && bp_fmode3) && !((!shres && !hires && bp_fmode12) || (hires && bp_fmode3))) && (ddfseq[2:0] == 3'd7);

// this signal enables bitplane DMA sequencer
always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0]) //cycle alligment
      if (ddfena && vdiwena && !hpos[1] && dmaena_delayed[0]) // bitplane DMA starts at odd timeslot
        ddfrun <= #1 1'b1;
      else if ((ddfend || !vdiwena) && ddfseq_match) // cleared at the end of last bitplane DMA cycle
        ddfrun <= #1 1'b0;
  end
end

// bitplane fetch dma sequence counter (1 bitplane DMA sequence lasts 8 CCK cycles)
always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0]) // cycle alligment
      if (ddfrun) // if enabled go to the next state
        ddfseq <= #1 ddfseq + 5'd1;
      else
        ddfseq <= #1 5'd0;
  end
end

// the last sequence of the bitplane DMA (time to add modulo)
always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[0] && ddfseq_match && ddfend)
      ddfend <= #1 1'b0;
    else if (hpos[0] && (ddfseq[2:0]==7) && !ddfena)
      ddfend <= #1 1'b1;
  end
end

// signal for adding modulo to the bitplane pointers
assign mod = (shres && bp_fmode0) ? ddfend & ddfseq[2] & ddfseq[1] : ((hires && bp_fmode0) || (shres && bp_fmode12)) ? ddfend & ddfseq[2] : ddfend;

// plane number encoder
always @ (*) begin
  if (shres && bp_fmode0) // shres+fmode0, up to 2bpls (2+2+2+2)
    plane = {4'b0000,~ddfseq[0]};
  else if ((hires && bp_fmode0) || (shres && bp_fmode12)) // hires+fmode0 or shres+fmode12, up to 4 bpls (4+4)
    plane = {3'b000,~ddfseq[0],~ddfseq[1]};
  else if ((!shres && !hires && bp_fmode0) || (hires && bp_fmode12) || (shres && bp_fmode3)) // lores+fmode0 or hires+fmode12 or shres+fmode3, up to 8 bpls (8)
    plane = {2'b00,~ddfseq[0],~ddfseq[1],~ddfseq[2]};
  else if ((!shres && !hires && bp_fmode12) || (hires && bp_fmode3)) // lores+fmode12 or hires+fmode3, up to 8 bpls, 8 free cycles (8+8f)
    plane = {1'b0,ddfseq[3],~ddfseq[0],~ddfseq[1],~ddfseq[2]};
  else // lores+fmode3, up to 8 bpls, 24 free cycles (8+8f+8f+8f)
    plane = {ddfseq[4],ddfseq[3],~ddfseq[0],~ddfseq[1],~ddfseq[2]};
end

// generate dma signal
// for a dma to happen plane must be less than BPU, dma must be enabled and data fetch must be true
assign dma = (ddfrun) && dmaena_delayed[1] && hpos[0] && (plane[4:0] < {1'b0,bpu[3:0]}) ? 1'b1 : 1'b0;

// adjust BPLxMOD for scandoubling
// AMR - incorporate a delay too
always @(posedge clk) begin
	if (clk7_en && hpos[0]) begin
		bpl1mod_bscan <= fmode[14] ? ((vdiwstrt[0] ^ vpos[0]) ? bpl2mod : bpl1mod) : bpl1mod;
		bpl2mod_bscan <= fmode[14] ? ((vdiwstrt[0] ^ vpos[0]) ? bpl2mod : bpl1mod) : bpl2mod;
	end
end

// dma pointer arithmetic unit
always @ (*) begin
  if (mod) begin
    if (plane[0]) // even plane modulo
      newpt[20:1] = address_out[20:1] + {{5{bpl2mod_bscan[15]}},bpl2mod_bscan[15:1]} + (fmode[1:0] == 2'b11 ? 3'd4 : fmode[1:0] == 2'b00 ? 3'd1 : 3'd2);
    else // odd plane modulo
      newpt[20:1] = address_out[20:1] + {{5{bpl1mod_bscan[15]}},bpl1mod_bscan[15:1]} + (fmode[1:0] == 2'b11 ? 3'd4 : fmode[1:0] == 2'b00 ? 3'd1 : 3'd2);
  end else begin
    newpt[20:1] = address_out[20:1] + (fmode[1:0] == 2'b11 ? 3'd4 : fmode[1:0] == 2'b00 ? 3'd1 : 3'd2);
  end
end

// Denise bitplane shift registers address lookup table
always @ (*) begin
  case (plane[2:0])
    3'b000 : reg_address_out[8:1] = 8'h88;
    3'b001 : reg_address_out[8:1] = 8'h89;
    3'b010 : reg_address_out[8:1] = 8'h8A;
    3'b011 : reg_address_out[8:1] = 8'h8B;
    3'b100 : reg_address_out[8:1] = 8'h8C;
    3'b101 : reg_address_out[8:1] = 8'h8D;
    3'b110 : reg_address_out[8:1] = 8'h8E;
    3'b111 : reg_address_out[8:1] = 8'h8F;
  endcase
end


endmodule

