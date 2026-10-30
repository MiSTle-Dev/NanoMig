////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Copyright 2006, 2007 Dennis van Weeren                                     //
// Copyright 2008, Jakub Bedmarski                                            //
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
// Sprite DMA engine                                                           //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


/*
JB: some conclusions of sprite engine investigation, it seems to be as follows:
- during vblank sprite dma is disabled by hardware, no automatic fetches occur but copper or cpu
can write to any sprite register, and all SPRxPTR pointers should be refreshed
- during the last line of vblank (PAL: $19, NTSC: $14) if sprite dma is enabled
it fetches SPRxPOS/SPRxCTL registers according to current SPRxPTR pointers
  This is the only chance for DMA to fetch new values of SPRxPOS/SPRxCTL. If DMA isn't enabled
during this line new values won't be placed into SPRxPOS/SPRxCTL registers.
  Enabling DMA after this line can have two results depending on current value of SPRxPOS/SPRxCTL.
- if VSTOP value is matched first with VERBEAM, data from memory is fetched and placed into SPRxPOS/SPRxCTL
- or if VSTART value is matched with VERBEAM, data from memory is fetched and placed into SPRxDATA/SPRxDATB
  and the situation repeats with every new line until VSTOP condition is met.
The VSTOP condition takes precedence.
  If you set VSTART to value lower or the same (remember that VSTOP takes precedence) as the current VERBEAM
this condition will never be met and sprite engine will wait till VSTOP matches VERBEAM. If it happens then it
fetches another two words into SPRxPOS/SPRxCTL. And again if new VSTART is lower or the same as VERBEAM
it will fetch another new SPRxPOS/SPRxCTL when VSTOP is met (or will wait till next vbl).
  To disable further sprite list processing it's enough to set VSTART and VSTOP to values which are outside
of the screen or has been already achieved.

  When waiting for VSTART condition any write to SPRxDATA (write to SPRxDATB takes no effect) makes the written value
visible on the screen but it doesn't start DMA although it's enabled. The same value is displayed in every subsequent
line until DMA starts and delivers new data to SPRxDAT or SPRxCTL is written (by DMA, copper or cpu).
It seems like only VSTART condition starts DMA transfer.
  Any write to SPRxCTL while DMA is active doesn't stop display but new value of VSTOP takes effect. Actually
display is reenabled by DMA write to SPRxDATA in next line.
  The same applies to SPRxPOS writes when sprite is beeing displayed - only HSTART position changes (if new VSTART
is specified to be met before VSTOP nothing interesting happens).

  The DMA engine sees VSTART condition as true even if DMA is dissabled. Enabling DMA after VSTART and before VSTOP
starts sprite display in enabled line (if it's enabled early enough).
  Dissabling DMA in the line when new SPRxPOS/SPRxCTL is fetched and enabling it in the next one results in stopped
DMA transfer but the last line of sprite is displayed till the end of the screen.

VSTART and VSTOP specified within vbl are not met.
vbl stops dma transfer.
The first possible line to display a sprite is line $1A (PAL).
During vbl SPRxPOS/SPRxCTL are not automatically modified, values written before vbl are still present when vbl ends.

algo:
  if vbl or VSTOP : disable data dma
  else if VSTART: start data dma

  if vblend or (VSTOP and not vbl): dma transfer to sprxpos/sprxctl
  else if data dma active: transfer to sprxdata/sprcdatb

It doesn't seem to be complicated :)

Sprite which has been triggered by write to SPRxDATA is not disabled by vbl.
It seems that vstop and vstart conditions are checked every cycle.
Dma doesn't fetch new pos/ctl if vstop is not equal to the current line number.

Feature:
If new vstart is specified to be the same as the line during which it's fetched, display starts in the next line
but is one line shorter.
*/

module agnus_spritedma (
  input   clk,              // bus clock
  input clk7_en,
  input reset,
  input aga,
  input  ecs,            // enable ECS extension bits
  output  reg reqdma,          // sprite dma engine requests dma cycle
  input  ackdma,            // agnus dma priority logic grants dma cycle
  input  [8:0] hpos,          // agnus internal horizontal position counter (advanced by 4 CCKs)
  input  [10:0] vpos,        // vertical beam counter
  input  vbl,            // vertical blanking
  input  vblend,            // last line of vertical blanking
  input  [8:1] reg_address_in,    // register address inputs
  output   reg [8:1] reg_address_out,  // register address outputs
  input  [15:0] data_in,        // bus data in
  output  [20:1] address_out      // chip address out
);


//register names and adresses
parameter SPRPTBASE_REG     = 9'h120;    //sprite pointers base address
parameter SPRPOSCTLBASE_REG = 9'h140;    //sprite data, position and control register base address
parameter FMODE_REG         = 9'h1fc;

//local signals
reg   [20:16] sprpth [7:0];    //upper 5 bits sprite pointers register bank
reg   [15:1]  sprptl [7:0];    //lower 16 bits sprite pointers register bank
reg    [15:8]  sprpos [7:0];    //sprite vertical start position register bank
reg           sprposh [7:0];  // sprite horizontal position (SH10)
reg    [15:4]  sprctl [7:0];    //sprite vertical stop position register bank
                  //JB: implementing ECS extended vertical sprite position

wire  [9:0] vstart;        //vertical start of selected sprite
wire        spr_sscan2;   // sprite scan double bit
wire  [9:0] vstop;        //vertical stop of selected sprite
reg    [2:0] sprite;        //sprite select signal
wire  [20:1] newptr;        //new sprite pointer value

reg   enable;            //horizontal position in sprite region

//the following signals change their value during cycle 0 of 4-cycle dma sprite window
reg    sprvstop;          //current line is sprite's vstop
reg    sprdmastate;        //sprite dma state (sprite image data cycles)

reg    dmastate_mem [7:0];      //dma state for every sprite
wire  dmastate;          //output from memory
reg    dmastate_in;        //input to memory

reg    [2:0] sprsel;        //memory selection

//sprite selection signal (in real amiga sprites are evaluated concurently,
//in our solution to save resources they are evaluated sequencially but 8 times faster (28MHz clock)
always @ (posedge clk) begin
  if (sprsel[2]==hpos[0])    //sprsel[2] is synced with hpos[0]
    sprsel <= sprsel + 1'b1;
end

//--------------------------------------------------------------------------------------

// fmode reg
reg  [16-1:0] fmode;

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      fmode <= 0;
    else if (aga && (reg_address_in[8:1] == FMODE_REG[8:1]))
      fmode <= data_in;
  end
end

reg  [ 3-1:0] spr_fmode_ptradd;

always @ (*) begin
  case(fmode[3:2])
    2'b00   : spr_fmode_ptradd = 3'd1;
    2'b11   : spr_fmode_ptradd = 3'd4;
    default : spr_fmode_ptradd = 3'd2;
  endcase
end

//register bank address multiplexer
wire  [2:0] ptsel;      //sprite pointer and state registers select
wire  [2:0] pcsel;      //sprite position and control registers select

assign ptsel = (ackdma) ? sprite : reg_address_in[4:2];
assign pcsel = (ackdma) ? sprite : reg_address_in[5:3];

//sprite pointer arithmetic unit
assign newptr = address_out[20:1] + spr_fmode_ptradd;

//sprite pointer high word register bank (implemented using distributed ram)
wire [20:16] sprpth_in;
assign sprpth_in = ackdma ? newptr[20:16] : data_in[4:0];

always @ (posedge clk) begin
  if (clk7_en) begin
    if (ackdma || ((reg_address_in[8:5]==SPRPTBASE_REG[8:5]) && !reg_address_in[1]))//if dma cycle or bus write
      sprpth[ptsel] <= sprpth_in;
  end
end

assign address_out[20:16] = sprpth[sprite];

//sprite pointer low word register bank (implemented using distributed ram)
wire [15:1]sprptl_in;
assign sprptl_in = ackdma ? newptr[15:1] : data_in[15:1];
always @ (posedge clk) begin
  if (clk7_en) begin
    if (ackdma || ((reg_address_in[8:5]==SPRPTBASE_REG[8:5]) && reg_address_in[1]))//if dma cycle or bus write
      sprptl[ptsel] <= sprptl_in;
  end
end

assign address_out[15:1] = sprptl[sprite];

//sprite vertical start position register bank (implemented using distributed ram)
always @ (posedge clk) begin
  if (clk7_en) begin
    if ((reg_address_in[8:6]==SPRPOSCTLBASE_REG[8:6]) && (reg_address_in[2:1]==2'b00)) begin
      // if bus write
      sprpos[pcsel]  <= data_in[15:8];
      sprposh[pcsel] <= data_in[7];
    end
  end
end

assign vstart[7:0] = sprpos[sprsel];

assign spr_sscan2 = sprposh[sprsel];

//sprite vertical stop position register bank (implemented using distributed ram)
always @ (posedge clk) begin
  if (clk7_en) begin
    if ((reg_address_in[8:6]==SPRPOSCTLBASE_REG[8:6]) && (reg_address_in[2:1]==2'b01))//if bus write
      sprctl[pcsel] <= {data_in[15:8],data_in[6],data_in[5],data_in[2],data_in[1]};
  end
end

assign {vstop[7:0],vstart[9],vstop[9],vstart[8],vstop[8]} = sprctl[sprsel];

//sprite dma channel state register bank
//update dmastate when hpos is in sprite fetch region
//every sprite has allocated 8 system clock cycles with two active dma slots:
//the first during cycle #3 and the second during cycle #7
//first slot transfers data to sprxpos register during vstop or vblend or to sprxdata when dma is active
//second slot transfers data to sprxctl register during vstop or vblend or to sprxdatb when dma is active
//current dmastate is valid after cycle for given sprite and it's needed during cycle #3 and #7
always @ (posedge clk) begin
  dmastate_mem[sprsel] <= dmastate_in;
end

assign dmastate = dmastate_mem[sprsel];

//evaluating sprite image dma data state
always @ (*) begin
  if (vbl || ({ecs&vstop[9],vstop[8:0]}==vpos[9:0]))
    dmastate_in = 0;
  else if ({ecs&vstart[9],vstart[8:0]}==vpos[9:0])
    dmastate_in = 1;
  else
    dmastate_in = dmastate;
end

always @ (posedge clk) begin
  if (sprite==sprsel && hpos[2:1]==2'b01)
    sprdmastate <= dmastate & ~(fmode[15] && spr_sscan2 && (vpos[0] != vstart[0]));
end

always @ (posedge clk) begin
  if (sprite==sprsel && hpos[2:1]==2'b01)
    sprvstop <= ({ecs&vstop[9],vstop[8:0]}==vpos[9:0]);
end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//check if we are allowed to allocate dma slots for sprites
//dma slots for sprites: even cycles from 18 to 38 (inclusive)
always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[8:1]==8'h18 && hpos[0])
      enable <= 1;
    else if (hpos[8:1]==8'h38 && hpos[0])
      enable <= 0;
  end
end

//get sprite number for which we are going to do dma
always @ (posedge clk) begin
  if (clk7_en) begin
    if (hpos[2:0]==3'b001)
      sprite[2:0] <= {hpos[5]^hpos[4],~hpos[4],hpos[3]};
  end
end

//generate reqdma signal
always @ (*) begin
  if (enable && hpos[1:0]==2'b01)
  begin
    if (vblend || (sprvstop && ~vbl))
    begin
      reqdma = 1;
      if (hpos[2])
        reg_address_out[8:1] = {SPRPOSCTLBASE_REG[8:6],sprite,2'b00};  //SPRxPOS
      else
        reg_address_out[8:1] = {SPRPOSCTLBASE_REG[8:6],sprite,2'b01};  //SPRxCTL
    end
    else if (sprdmastate)
    begin
      reqdma = 1;
      if (hpos[2])
        reg_address_out[8:1] = {SPRPOSCTLBASE_REG[8:6],sprite,2'b10};  //SPRxDATA
      else
        reg_address_out[8:1] = {SPRPOSCTLBASE_REG[8:6],sprite,2'b11};  //SPRxDATB
    end
    else
    begin
      reqdma = 0;
      reg_address_out[8:1] = 8'hFF;
    end
  end
  else
  begin
    reqdma = 0;
    reg_address_out[8:1] = 8'hFF;
  end
end


endmodule

