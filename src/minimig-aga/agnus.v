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
// This is Agnus
// The copper, blitter and sprite dma have a reqdma output and an ackdma input
// if they are ready for dma they do a dma request by asserting reqdma
// the dma priority logic circuit then checks which module is granted access by
// looking at their priorities and asserting the ackdma signal of the module that
// has the highest priority
//
// Other dma channels (bitplane, audio and disk) only have an enable input (bitplane)
// or only a dma request input from Paula (dmal input, disk and audio)
// and an dma output to indicate that they are using their slot.
// this is because they have the highest priority in the system and cannot be hold up
//
// The bus clock runs at 7.09MHz which is twice as fast as in the original amiga and
// the same as the pixel clock / horizontal beam counter.
//
// general cycle allocation is as follows:
// (lowest 2 bits of horizontal beam counter)
//
// slot 0:  68000 (priority in that order, extra slots because of higher bus speed)
// slot 1:  disk, bitplanes, copper, blitter and 68000 (priority in that order)
// slot 2:  blitter and 68000 (priority in that order, extra slots because of higher bus speed)
// slot 3:  disk, bitplanes, sprites, audio and 68000 (priority in that order)
//
// because only the odd slots are used by the chipset, the chipset runs at the same
// virtual speed as the original. The cpu gets the extra even slots allowing for
// faster cpu's without the need for an extra fastram controller
// Blitter timing is not completely accurate, it uses slot 1 and 2 instead of 1 and 3, this is to let
// the blitter not slow down too much dma contention. (most compatible solution for now)
// Blitter nasty mode activates the buspri signal to indicate to gary to stop access to the chipram/chipregisters.
// Blitter nasty mode is only activated if blitter activates bltpri cause it depends on blitter settings if blitter
// will really block the cpu.
//


module agnus
(
	input         clk,             // clock
	input         clk7_en,         
	input         cck,             // colour clock enable, active whenever hpos[0] is high (odd dma slots used by chipset)
	input         reset,           // reset
	input         aen,             // bus adress enable (register bank)
	input         rd,              // bus read
	input         hwr,             // bus high write
	input         lwr,             // bus low write
	input  [15:0] data_in,         // data bus in
	output [15:0] data_out,        // data bus out
	input   [8:1] address_in,      // 256 words (512 bytes) adress input,
	output reg [20:1] address_out, // chip address output,
	output  [8:1] reg_address_out, // 256 words (512 bytes) register address out,
	output reg    cpu_custom,      // CPU has access to custom chipset (registers and chipRAM / slowRAM)
	output reg    dbr,             // agnus requests data bus
	output reg    dbwe,            // agnus does a memory write cycle (only disk and blitter dma channels may do this)
	output reg    refresh,         // a refresh cycle is in progress
	output        _hsync,          // horizontal sync
	output        _vsync,          // vertical sync
	output        _csync,          // composite sync
	output        field1,
	output        lace,
	output        hblank,          // video blanking
	output        vblank,          // video blanking
	output        hde,             // video horizontal data enable
	output        sol,             // start of video line (active during last pixel of previous line)
	output        sof,             // start of video frame (active during last pixel of previous frame)
	output        vbl_int,         // vertical blanking interrupt request for Paula
	output        strhor_denise,   // horizontal strobe for Denise (due to not cycle exact implementation of Denise it must be delayed by one CCK)
	output        strhor_paula,    // horizontal strobe for Paula
	output  [8:0] htotal,          // video line length
	output        harddis,
	output        varbeamen,
	output        int3,            // blitter finished interrupt (to Paula)
	input   [3:0] audio_dmal,      // audio dma data transfer request (from Paula)
	input   [3:0] audio_dmas,      // audio dma location pointer restart (from Paula)
	input         disk_dmal,       // disk dma data transfer request (from Paula)
	input         disk_dmas,       // disk dma special request (from Paula)
	input         bls,             // blitter slowdown
	input         ntsc,            // chip is NTSC
	input         a1k,             // enable A1000 OCS features
	input         ecs,             // enable ECS features
	input         aga,             // enables AGA features
	input         floppy_speed     // allocates refresh slots for disk DMA
);

//register names and adresses
localparam DMACON  = 9'h096;
localparam DMACONR = 9'h002;
localparam DIWSTRT = 9'h08e;
localparam DIWSTOP = 9'h090;
localparam DIWHIGH = 9'h1E4;

parameter BLS_CNT_MAX = 3;    //when CPU misses the bus for 3 consecutive memory cycles the blitter is blocked until CPU accesses the bus

//--------------------------------------------------------------------------------------

//cpu address decoder
wire [8:1] reg_address_cpu = (aen&(rd|hwr|lwr)) ? address_in : 8'hFF;

//--------------------------------------------------------------------------------------

wire req_spr;         //sprite dma request
wire req_cop;         //copper dma request
wire req_blt;         //blitter dma request
wire spren;
wire copen;
wire blten;
   
wire dma_spr = req_spr & spren; //sprite dma is using its slot
wire dma_cop = req_cop & copen; //copper dma is using its slot
wire dma_blt = req_blt & blten; //blitter dma is using its slot
wire dma_ref;                   //refresh dma slots

reg       ack_cop;        //copper dma acknowledge
reg       ack_blt;        //blitter dma acknowledge
reg       ack_spr;        //sprite dma acknowledge
reg [8:1] reg_address;    //local register address bus

//register address bus output
assign reg_address_out = reg_address;

wire        dma_dsk;         //disk dma uses its slot
wire        wr_dsk;          //disk dma engine write enable out
wire [20:1] address_dsk;     //disk dma engine chip address out
wire  [8:1] reg_address_dsk; //disk dma engine register address out

wire        dma_aud;         //audio dma uses its slot
wire [20:1] address_aud;     //audio dma engine chip address out
wire  [8:1] reg_address_aud; //audio dma engine register address out

wire        dma_bpl;         //bitplane dma engine uses it's slot
wire [20:1] address_bpl;     //bitplane dma engine chip address out
wire  [8:1] reg_address_bpl; //bitplane dma engine register address out

wire [20:1] address_spr;     //sprite dma engine chip address out
wire  [8:1] reg_address_spr; //sprite dma engine register address out

wire [20:1] address_cop;     //copper dma engine chip address out
wire  [8:1] reg_address_cop; //copper dma engine register address out

wire        blit_zero;       //blitter zero status
wire [20:1] address_blt;     //blitter dma engine chip address out
wire  [8:1] reg_address_blt; //blitter dma engine register address out
wire [15:0] data_blt;        //blitter dma engine data out
wire        we_blt;          //blitter dma engine write enable out

wire [15:0] data_bmc;  //beam counter data out
reg [1:0] bls_cnt;      //blitter slowdown counter, counts memory cycles when the CPU misses the bus

//chip address, register address and control signal multiplexer
//AND dma priority handler
//first item in this if else if list has highest priority
always @(*)
begin
	if (dma_dsk) begin
		// bus allocated to disk dma engine
		cpu_custom = 0;
		dbr = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		address_out = address_dsk;
		reg_address = reg_address_dsk;
		dbwe = wr_dsk;
		refresh = 0;
	end
	else if (dma_ref) begin
		// bus allocated to refresh dma engine
		cpu_custom = 0;
		dbr = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		address_out = 0;
		reg_address = 8'hFF;
		dbwe = 0;
		refresh = 1;
	end
	else if (dma_aud) begin
		// bus allocated to audio dma engine
		cpu_custom = 0;
		dbr = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		address_out = address_aud;
		reg_address = reg_address_aud;
		dbwe = 0;
		refresh = 0;
	end
	else if (dma_bpl) begin
		// bus allocated to bitplane dma engine
		cpu_custom = 0;
		dbr = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		address_out = address_bpl;
		reg_address = reg_address_bpl;
		dbwe = 0;
		refresh = 0;
	end
	else if (dma_spr) begin
		// bus allocated to sprite dma engine
		cpu_custom = 0;
		dbr = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 1;
		address_out = address_spr;
		reg_address = reg_address_spr;
		dbwe = 0;
		refresh = 0;
	end
	else if (dma_cop) begin
		// bus allocated to copper
		cpu_custom = 0;
		dbr = 1;
		ack_cop = 1;
		ack_blt = 0;
		ack_spr = 0;
		address_out = address_cop;
		reg_address = reg_address_cop;
		dbwe = 0;
		refresh = 0;
	end
	else if (dma_blt && bls_cnt!=BLS_CNT_MAX) begin
		// bus allocated to blitter
		cpu_custom = 0;
		dbr = 1;
		ack_cop = 0;
		ack_blt = 1;
		ack_spr = 0;
		address_out = address_blt;
		reg_address = reg_address_blt;
		dbwe = we_blt;
		refresh = 0;
	end
	else begin
		// bus not allocated by agnus
		cpu_custom = 1;
		dbr = 0;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		address_out = 0;
		reg_address = reg_address_cpu; // pass register addresses from cpu address bus
		dbwe = 0;
		refresh = 0;
	end
end

//--------------------------------------------------------------------------------------

reg [12:0] dmacon;
reg [15:0] dmaconr;      //dma control read register

wire        blit_busy;       //blitter busy status

//data out multiplexer
assign data_out = data_bmc | dmaconr | data_blt;

//dma control register read
always @(*) begin
	if (reg_address[8:1]==DMACONR[8:1]) dmaconr[15:0] = {1'b0, blit_busy, blit_zero, dmacon[12:0]};
	else                                dmaconr = 0;
end

//dma control register write
always @(posedge clk) begin
	if (clk7_en) begin
		if (reset) dmacon <= 0;
		else if (reg_address[8:1]==DMACON[8:1])
		begin
			if (data_in[15]) dmacon[12:0] <= dmacon[12:0] | data_in[12:0];
			else             dmacon[12:0] <= dmacon[12:0] & ~data_in[12:0];
		end
	end
end

//assign dma enable bits
wire bltpri = dmacon[10];
wire bplen  = dmacon[8] & dmacon[9];
assign copen  = dmacon[7] & dmacon[9];
assign blten  = dmacon[6] & dmacon[9];
assign spren  = dmacon[5] & dmacon[9];

//copper dma is enabled only when any higher priority dma channel is inactive
//copper uses dma slots which can be optionally assigned only to bitplane dma (also to blitter but it has lower priority than copper)
//it is ok to generate this signal form bitplane dma signal only
wire ena_cop = ~dma_bpl;
//dma enable for blitter tells the blitter that no higher priority dma channel is using the bus
//since blitter has the lowest priority and can use any dma slot (even and odd) all other dma channels block blitter activity
wire ena_blt = ~(dma_ref | dma_dsk | dma_aud | dma_spr | dma_bpl | dma_cop) && bls_cnt!=BLS_CNT_MAX ? 1'b1 : 1'b0;

wire  [8:0] hpos;      //alternative horizontal beam counter
wire [10:0] vpos;      //vertical beam counter
wire        vbl;       //JB: vertical blanking
wire        vblend;    //JB: last line of vertical blanking
   
//--------------------------------------------------------------------------------------

agnus_refresh ref1
(
	.hpos(hpos),
	.dma(dma_ref)
);

//instantiate disk dma engine
agnus_diskdma dsk1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.dma(dma_dsk),
	.dmal(disk_dmal),
	.dmas(disk_dmas),
	.speed(floppy_speed),
	.hpos(hpos),
	.wr(wr_dsk),
	.reg_address_in(reg_address),
	.reg_address_out(reg_address_dsk),
	.data_in(data_in),
	.address_out(address_dsk)
);

//--------------------------------------------------------------------------------------

//instantiate audio dma engine
agnus_audiodma aud1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.dma(dma_aud),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.hpos(hpos),
	.reg_address_in(reg_address),
	.reg_address_out(reg_address_aud),
	.data_in(data_in),
	.address_out(address_aud)
);

//--------------------------------------------------------------------------------------

//instantiate bitplane dma
agnus_bitplanedma bpd1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(reset),
	.harddis(harddis),
	.aga(aga),
	.ecs(ecs),
	.a1k(a1k),
	.sof(sof),
	.dmaena(bplen),
	.vpos(vpos),
	.hpos(hpos),
	.hde(hde),
	.dma(dma_bpl),
	.reg_address_in(reg_address),
	.reg_address_out(reg_address_bpl),
	.data_in(data_in),
	.address_out(address_bpl)
);

//--------------------------------------------------------------------------------------

//instantiate sprite dma engine
agnus_spritedma spr1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(reset),
	.aga(aga),
	.ecs(ecs),
	.reqdma(req_spr),
	.ackdma(ack_spr),
	.hpos(hpos),
	.vpos(vpos),
	.vbl(vbl),
	.vblend(vblend),
	.reg_address_in(reg_address),
	.reg_address_out(reg_address_spr),
	.data_in(data_in),
	.address_out(address_spr)
);

//--------------------------------------------------------------------------------------

//instantiate copper
agnus_copper cp1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(reset),
	.ecs(ecs),
	.reqdma(req_cop),
	.ackdma(ack_cop),
	.enadma(ena_cop),
	.sof(sof),
	.blit_busy(blit_busy),
	.vpos(vpos[7:0]),
	.hpos(hpos),
	.data_in(data_in),
	.reg_address_in(reg_address),
	.reg_address_out(reg_address_cop),
	.address_out(address_cop)
);

//--------------------------------------------------------------------------------------

always @(posedge clk) if (clk7_en) begin
	if (!cck)
		if (!bls || bltpri) bls_cnt <= 2'b00;
		else if (bls_cnt[1:0] != BLS_CNT_MAX) bls_cnt <= bls_cnt + 2'b01;
end

//instantiate blitter
agnus_blitter bl1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(reset),
	.ecs(ecs),
	.clkena(cck),
	.enadma(blten & ena_blt),
	.reqdma(req_blt),
	.ackdma(ack_blt),
	.we(we_blt),
	.zero(blit_zero),
	.busy(blit_busy),
	.int3(int3),
	.data_in(data_in),
	.data_out(data_blt),
	.reg_address_in(reg_address),
	.address_out(address_blt),
	.reg_address_out(reg_address_blt)
);

//--------------------------------------------------------------------------------------

//instantiate beam counters
agnus_beamcounter  bc1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(reset),
	.cck(cck),
	.ntsc(ntsc),
	.aga(aga),
	.ecs(ecs),
	.a1k(a1k),
	.reg_address_in(reg_address),
	.data_in(data_in),
	.data_out(data_bmc),
	.hpos(hpos),
	.vpos(vpos),
	._hsync(_hsync),
	._vsync(_vsync),
	._csync(_csync),
	.field1(field1),
	.lace(lace),
	.hblank(hblank),
	.vblank(vblank),
	.vbl(vbl),
	.vblend(vblend),
	.eol(sol),
	.eof(sof),
	.vbl_int(vbl_int),
	.htotal_out(htotal),
	.harddis_out(harddis),
	.varbeamen_out(varbeamen)
);

//horizontal strobe for Denise
//in real Amiga Denise's hpos counter seems to be advanced by 4 CCKs in regards to Agnus' one
//Minimig isn't cycle exact and compensation for different data delay in implemented Denise's video pipeline is required
assign strhor_denise = hpos==(6*2-1) && (vpos > 8 || ecs) ? 1'b1 : 1'b0;
assign strhor_paula = hpos==(6*2+1) ? 1'b1 : 1'b0; //hack

//--------------------------------------------------------------------------------------


endmodule

