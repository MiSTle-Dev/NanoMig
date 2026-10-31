// Copyright 2006,2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License,or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not,see <http://www.gnu.org/licenses/>.
//
//
//
// This is the Blitter (part of the Agnus chip)
//
// 14-08-2005	-started coding
// 16-08-2005	-done more coding
// 19-08-2005	-added C source channel
//				-added minterm function generator
// 21-08-2005	-added proper masking for A channel
//				-added fill logic and D destination channel
//				-added normal/line mode control logic
//				-added address generator but it needs more work to reduce slices
// 23-08-2005	-done more work
//				-added blitsize counter
// 24-08-2005	-done some cleanup
// 28-08-2005	-redesigned address generator module
//				-started coding of main state machine
// 29-08-2005	-added blitter zero detect
//				-added logic for special line mode to channel D 
// 31-08-2005	-blitsize is now decremented automatically during channel D cycle
//				-added delayed version for lwt called lwtd (needed for pipelining)
// 04-09-2005	-added state machine for normal blitter mode	
//				-added data output gate in channel D (needed for integration into Agnus)
// 05-09-2005	-fixed bug in bltaddress module
//				-modified state machine start of blit handling
// 06-09-2005	-restored state machine,we should now have a working blitter (normal mode)
//				-fixed bug,channel B preload didn't work
// 14-09-2005	-fixed bug in channel A masking logic when doing 1 word wide blits
//				 (and subsequently found another error in the Hardware Reference Manual)
// 18-09-2005	-added sign bit handling for line mode
//				-redesigned address pointer ALU
//				-adapted state machine to use new style ALU codes
//				-added experimental line mode for octant 0,3,4,7
// 19-09-2005	-fixed bugs in line mode state machine and it begins to start working..
// 20-09-2005	-testing
// 25-09-2005	-complete redesign of controller logic
//				-added new linemode logic for all octants
// 27-09-2005	-fixed problem in linemode with dma/channel D modulo: it seems like the real blitter
//				 uses only C modulo for channel C and D during linemode,same for USEC/USED
//				-sign is taken from bit 15 of pointer A,NOT bit 20! -->fixed
//				-line drawing in octant 0,3,4,7 now works!
// 28-09-2005	-line drawing in octant 1,2,5,6 now works too!
// 02-10-2005	-special line draw mode added (single bit per horizontal line)
//				 this completes the blitter (but some bugs may still remain...)
// 17-10-2005	-fixed typo in sensitivity list of always block
// 22-01-2006	-fixed bug in special line draw mode
// 25-01-2006	-added bblck signal	
// 14-02-2006	-improved bblck table
// 07-07-2006	-added some comments
// ----------
// JB:
// 2008-03-03	- added BLTCON0L, BLTSIZH and BLTSIZV
// 2008-07-08	- clean up
// 2008-10-20	- changed name of horbeam[0] to bltena
// 2009-05-24	- clean-up & renaming
// 2009-05-29	- changed enable signal to be more cycle exact
//				- removed bblck as not needed anymore
//				- there is still incopatibility when C channel is selected without D: extra idle cycle is inserted 
// 2009-12-15	- fixed channel B data flow
// 2009-12-19	- ECS extensions available only with ECS chipset selected

module agnus_blitter
(
	input 	clk,	 					// bus clock
  input clk7_en,
	input 	reset,	 					// reset
	input	ecs,						// enable ECS extensions
	input	clkena,						// enables blitter operation (used to slow it down)
	input	enadma,						// no other dma channel is granted the bus
	output	reqdma,						// blitter requests dma cycle
	input	ackdma,						// agnus dma priority logic grants dma cycle
	output	we,							// write enable (blitter writes to memory)
	output	reg zero,					// blitter zero status
	output	reg busy,					// blitter busy status
	output	int3,						// blitter finish interrupt request
	input 	[15:0] data_in,	    		// bus data in
	output	[15:0] data_out,			// bus data out
	input 	[8:1] reg_address_in,		// register address inputs
	output 	[20:1] address_out, 		// chip address outputs
	output 	reg [8:1] reg_address_out	// register address outputs
);

//register names and adresses		
parameter BLTCON0  = 9'h040;
parameter BLTCON0L = 9'h05A;
parameter BLTCON1  = 9'h042;
parameter BLTAFWM  = 9'h044;
parameter BLTALWM  = 9'h046;
parameter BLTADAT  = 9'h074;
parameter BLTBDAT  = 9'h072;
parameter BLTCDAT  = 9'h070;
parameter BLTDDAT  = 9'h000;
parameter BLTSIZE  = 9'h058;
parameter BLTSIZH  = 9'h05E;
parameter BLTSIZV  = 9'h05C;

//channel select codes
parameter CHA = 2'b10;	// channel A
parameter CHB = 2'b01;	// channel B
parameter CHC = 2'b00;	// channel C
parameter CHD = 2'b11;	// channel D


parameter BLT_IDLE = 5'b00000;
parameter BLT_INIT = 5'b00001;
parameter BLT_A    = 5'b01001;
parameter BLT_B    = 5'b01011;
parameter BLT_C    = 5'b01010;
parameter BLT_D    = 5'b01000;
parameter BLT_E    = 5'b01100;
parameter BLT_F    = 5'b00100;
parameter BLT_L1   = 5'b11001;
parameter BLT_L2   = 5'b11011;
parameter BLT_L3   = 5'b11010;
parameter BLT_L4   = 5'b11000;
parameter BLT_FROZEN = 5'b11111;

//local signals
reg		[15:0] bltcon0;			// blitter control register 0
wire	[3:0] ash;				// bltcon0 aliases
wire	usea;
wire	useb;
wire	usec;
wire	used;
reg		enad;					// do not disable D channel

reg		[15:0] bltcon1;			// blitter control register 1
wire	[3:0] bsh;				// bltcon1 aliases
wire	desc;					// enable descending mode (and not line mode)
wire	line;					// enable line mode
wire	ife;					// enable inclusive fill mode
wire	efe;					// enable exclusive fill mode

reg		[15:0] bltafwm;			// blitter first word mask for source A
reg		[15:0] bltalwm;			// blitter last word mask for source A
reg		[15:0] bltadat;			// blitter source A data register
reg		[15:0] bltbdat;			// blitter source B data register
reg		[15:0] bltcdat;			// blitter source C data register
reg		[15:0] bltaold;			// blitter source A 'old' data
reg		[15:0] bltbold;			// blitter source B 'old' data
reg		[15:0] bltahold;		// A holding register
reg		[15:0] bltbhold;		// B holding register
reg		[15:0] bltdhold;		// D holding register
reg		[10:0] width;			// blitsize number of words (width)
reg		[14:0] height;			// blitsize number of lines (height)

reg		[4:0] blt_state;		// blitter state
reg		[4:0] blt_next;			// blitter next state

wire	enable;					// blit cycle enable signal

reg		[1:0] chsel;			// channel selection - affects register bus address during DMA transactions
reg		[1:0] ptrsel;			// pointer selection - DMA memory bus address
reg		[1:0] modsel;			// modulo selection (blitter is a little bit weird in line mode0
reg		enaptr;					// enable selected pointer
reg		incptr;					// increment selected pointer
reg		decptr;					// decrement selected pointer
reg		addmod;					// add selected modulo
reg		submod;					// substract selected modulo

wire	incash;					// increment ASH (line mode)
wire	decash;					// decrement ASH (line mode)
wire	decbsh;					// decrement BSH (line mode)

wire	sign_out;				// new accumulator sign calculated by address generator (line mode)
reg		sign;					// current sign of accumulator (line mode)
reg		sign_del;
reg		first_pixel;			// first pixel in a horizontal segment (used in one-dot line mode)
reg   first_line_pixel; // first pixel of line (use D pointer)

reg		start;					// busy delayed by one blitter cycle (for cycle exact compatibility)
wire	init;					// blitter initialization cycle
wire	next_word;				// indicates last cycle of a single sequence
reg		store_result;			// updates D hold register
reg		pipeline_full;			// indicated update of D holding register
wire 	first_word;				// first word of a line
reg		first_word_del;			// delayed signal for use in fill mode (initial fill carry selection)
wire 	last_word; 				// last word of a line
reg		last_word_del;			// delayed signal for adding modulo to D channel pointer register
wire 	last_line; 				// last line of the blit
wire	done;					// indicates the end of the blit (clears busy)

wire	[15:0] minterm_out; 	// minterm generator output
wire	[15:0] fill_out;		// fill logic output
wire	fci;					// fill carry in
wire	fco;	    			// fill carry out
reg		fcy;	   				// fill carry latch (for the next word)

reg		[10:0] width_cnt;		// blitter width counter (in words)
wire 	width_cnt_dec;			// decrement width counter
wire 	width_cnt_rld;			// reload width counter
reg 	[14:0] height_cnt;		// blitter height counter (in lines)

reg		[15:0] bltamask;
wire	[15:0] shiftaout;
wire	[15:0] shiftbout;

reg		dma_req;
wire	dma_ack;

//--------------------------------------------------------------------------------------

//bltcon0: ASH part
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		bltcon0[15:12] <= 0;
  	else if (enable && incash) // increment ash (line mode)
  		bltcon0[15:12] <= bltcon0[15:12] + 4'b0001;
  	else if (enable && decash) // decrement ash (line mode)
  		bltcon0[15:12] <= bltcon0[15:12] - 4'b0001;
  	else if (reg_address_in[8:1]==BLTCON0[8:1])
  		bltcon0[15:12] <= data_in[15:12];
  end

assign ash[3:0] = bltcon0[15:12];

//bltcon0: USE part
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		bltcon0[11:8] <= 0;
  	else if (reg_address_in[8:1]==BLTCON0[8:1])
  		bltcon0[11:8] <= data_in[11:8];
  end

// writing blitcon0 while a blit is active disables D channel (not always but it's very likely)
always @(posedge clk)
  if (clk7_en) begin
  	if (init)
  		enad <= 1'b1;
  	else if (reg_address_in[8:1]==BLTCON0[8:1] && busy)
  		enad <= 1'b0;	
  end

assign {usea, useb, usec, used} = {bltcon0[11:9], bltcon0[8] & enad}; // DMA channels enable		

//bltcon0: LF part
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		bltcon0[7:0] <= 0;
  	else if (reg_address_in[8:1]==BLTCON0[8:1] || reg_address_in[8:1]==BLTCON0L[8:1] && ecs)
  		bltcon0[7:0] <= data_in[7:0];
  end

//bltcon1: BSH part
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		bltcon1[15:12] <= 0;
  	else if (enable && decbsh) // decrement bsh (line mode - texturing)
  		bltcon1[15:12] <= bltcon1[15:12] - 4'b0001;
  	else if (reg_address_in[8:1]==BLTCON1[8:1])
  		bltcon1[15:12] <= data_in[15:12];
  end

assign bsh[3:0] = bltcon1[15:12];

//bltcon1: the rest
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		bltcon1[11:0] <= 0;
  	else if (reg_address_in[8:1]==BLTCON1[8:1])
  		bltcon1[11:0] <= data_in[11:0];
  end

assign line = bltcon1[0]; // line mode
assign desc = ~line & bltcon1[1]; // descending blit mode		
assign efe = ~line & bltcon1[4]; // exclusive fill mode
assign ife = ~line & bltcon1[3]; // inclusive fill mode

// Real Amiga blitter freezes when BLTCON1 disables fill
// while an extra-cycle D-only fill blit is still active.
wire bltcon1_write =
    reg_address_in[8:1] == BLTCON1[8:1];

wire extra_fill_mode =
    !line &&
    (ife || efe) &&
    (bltcon0[9:8] == 2'b01);

wire freeze_on_bltcon1 =
    busy &&
    bltcon1_write &&
    extra_fill_mode &&
    !data_in[0] &&
    !data_in[4] &&
    !data_in[3];

//--------------------------------------------------------------------------------------

//bltafwm register (first word mask for channel A)
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		bltafwm[15:0] <= 0;
  	else if (reg_address_in[8:1]==BLTAFWM[8:1])
  		bltafwm[15:0] <= data_in[15:0];
  end

//bltalwm register (last word mask for channel A)
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		bltalwm[15:0] <= 0;
  	else if (reg_address_in[8:1]==BLTALWM[8:1])
  		bltalwm[15:0] <= data_in[15:0];
  end

//channel A mask select
always @(*)
	if (first_word && last_word)
		bltamask[15:0] = bltafwm[15:0] & bltalwm[15:0];
	else if (last_word)
		bltamask[15:0] = bltalwm[15:0];
	else if (first_word)
		bltamask[15:0] = bltafwm[15:0];	
	else
		bltamask[15:0] = 16'hFF_FF;
		
//bltadat register
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		bltadat[15:0] <= 0;
  	else if (reg_address_in[8:1]==BLTADAT[8:1])
  		bltadat[15:0] <= data_in[15:0];
  end

//channel A 'old' register
always @(posedge clk)
  if (clk7_en) begin
  	if (enable)
  		if (init)
  			bltaold[15:0] <= 0;
  		else if (next_word && !line) // in line mode this register is equal zero all the time
  			bltaold[15:0] <= bltadat[15:0] & bltamask[15:0];
  end

//channel A barrel shifter
agnus_blitter_barrelshifter barrel_shifter_A
(
	.desc(desc),
	.shift(ash),
	.new_val(bltadat & bltamask),
	.old_val(bltaold),
	.out(shiftaout)
);

//channel A holding register
always @(posedge clk)
  if (clk7_en) begin
  	if (enable)
  		bltahold[15:0] <= shiftaout[15:0];
  end

//--------------------------------------------------------------------------------------

//bltbdat register
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		bltbdat[15:0] <= 0;
  	else if (reg_address_in[8:1]==BLTBDAT[8:1])
  		bltbdat[15:0] <= data_in[15:0];
  end
		
reg bltbold_init;
always @(posedge clk)
  if (clk7_en) begin
  	if (reset || done)
  		bltbold_init <= 1'b1;
  	else if (reg_address_in[8:1]==BLTBDAT[8:1])
  		bltbold_init <= 1'b0;
  end

//channel B 'old' register
always @(posedge clk)
  if (clk7_en) begin
  	if (reg_address_in[8:1]==BLTBDAT[8:1])
  		if (bltbold_init)
  			bltbold[15:0] <= 0;
  		else
  			bltbold[15:0] <= bltbdat[15:0];
  end

reg bltbdat_wrtn;		
always @(posedge clk)
  if (clk7_en) begin
  	if (reg_address_in[8:1]==BLTBDAT[8:1])
  		bltbdat_wrtn <= 1'b1;
  	else
  		bltbdat_wrtn <= 1'b0;
  end

//channel B barrel shifter
agnus_blitter_barrelshifter barrel_shifter_B
(
	.desc(desc),
	.shift(bsh),
	.new_val(bltbdat),
	.old_val(bltbold),
	.out(shiftbout)
);

//channel B holding register
always @(posedge clk)
  if (clk7_en) begin
  	if (line)
  		bltbhold[15:0] <= {16{shiftbout[0]}}; // in line mode only one selected bit of BLTBDAT register (LSB) is used for texturing
  	// AMR - Contraz Domination uses clr.w bltcon1, which does a phantom read from a w/o register, momentarily enabling line mode and wiping out bltbhold
  	else if(enable)	// if (bltbdat_wrtn)
  		bltbhold[15:0] <= shiftbout[15:0];
  end
	
//--------------------------------------------------------------------------------------

//bltcdat register
always @(posedge clk)
  if (clk7_en) begin
  	if (reg_address_in[8:1]==BLTCDAT[8:1])
  		bltcdat[15:0] <= data_in[15:0];
  end
		
//--------------------------------------------------------------------------------------

 
always @(posedge clk)
  if (clk7_en) begin
  	if (next_word && enable)
  		last_word_del <= last_word;
  end

always @(posedge clk)
  if (clk7_en) begin
  	if (next_word && enable)
  		first_word_del <= first_word; // used in fill mode for selecting initial fci state
  end

//--------------------------------------------------------------------------------------

//minterm generator instantation
agnus_blitter_minterm bltmt1
(
	.lf(bltcon0[7:0]),
	.ain(bltahold[15:0]),
	.bin(bltbhold[15:0]),
	.cin(bltcdat[15:0]),
	.out(minterm_out[15:0])
);


//fill logic instantiation
agnus_blitter_fill bltfl1
(
	.ife(ife),
	.efe(efe),
	.fci(fci),
	.fco(fco),
	.in(minterm_out[15:0]),
	.out(fill_out[15:0])
);

//fill carry input
assign fci = first_word_del ? bltcon1[2] : fcy;

// carry out latch (updated at the same time as channel D holding register)
always @(posedge clk)
  if (clk7_en) begin
  	if (store_result)
  		fcy <= fco;
  end

// channel D holding register (updated one cycle later after a write to other holding registers)
always @(posedge clk)
  if (clk7_en) begin
  	if (store_result)
  		bltdhold[15:0] <= fill_out[15:0];
  end

// channel D 'zero' flag
always @(posedge clk)
  if (clk7_en) begin
  	if (enable && init)
  		zero <= 1;
  	else if (store_result && |fill_out[15:0])
  		zero <= 0;
  end

//channel D data output
assign data_out[15:0] = ackdma && chsel[1:0]==CHD ? bltdhold[15:0] : 16'h00_00;
assign we = ackdma && chsel[1:0]==CHD ? 1'b1 : 1'b0;

//--------------------------------------------------------------------------------------

// 'busy' flag control
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		busy <= 0;
  	else if (reg_address_in[8:1]==BLTSIZE[8:1] || reg_address_in[8:1]==BLTSIZH[8:1] && ecs) // set immediately after a write to BLTSIZE or BLTSIZH (ECS)
  		busy <= 1;
  	else if (done) // cleared when the blit is done
  		busy <= 0;
  end

// blitter finish interrupt request
assign int3 = done;

// FSM start control (one bus clock cycle delay for cycle exact compatibility)
always @(posedge clk)
  if (clk7_en) begin
  	if (reset || done)
  		start <= 0;
  	else if (clkena && busy)
  		start <= 1;
  end

// blit width register (backup)
always @(posedge clk)
  if (clk7_en) begin
  	if (reg_address_in[8:1]==BLTSIZE[8:1]) // OCS
  		width[10:0] <= {4'b0000, ~|data_in[5:0], data_in[5:0]};
  	else if (reg_address_in[8:1]==BLTSIZH[8:1] && ecs) // ECS
  		width[10:0] <= data_in[10:0];
  end

assign width_cnt_dec = enable & next_word;
assign width_cnt_rld = enable & next_word & last_word | init & enable;

// blit width counter
always @(posedge clk)
  if (clk7_en) begin
  	if (width_cnt_rld) // reload counter
  		width_cnt[10:0] <= width[10:0];
  	else if (width_cnt_dec) // decrement counter
  		width_cnt[10:0] <= width_cnt[10:0] - 1'b1;
  end

assign last_word = width_cnt[10:0]==1 ? 1'b1 : 1'b0;
assign first_word = width_cnt[10:0]==width[10:0] ? 1'b1 : 1'b0;
assign last_line = height_cnt[14:0]==1 ? 1'b1 : 1'b0;

// ECS large blit height holding register 
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		height[14:0] <= 0;
  	else if (reg_address_in[8:1]==BLTSIZV[8:1]) // ECS BLTSIZV register
  		height[14:0] <= data_in[14:0];
  end

// blit height counter
always @(posedge clk)
  if (clk7_en) begin
  	if (reg_address_in[8:1]==BLTSIZE[8:1]) // OCS
  		height_cnt[14:0] <= {4'b0000, ~|data_in[15:6], data_in[15:6]};
  	else if (reg_address_in[8:1]==BLTSIZH[8:1] && ecs) // ECS
  		height_cnt[14:0] <= height[14:0];
  	else if (enable && next_word && last_word) // decrement height counter
  		height_cnt[14:0] <= height_cnt[14:0] - 1'b1;
  end

// pipeline is full (first set of sources has been fetched)
always @(posedge clk)
  if (clk7_en) begin
  	if (enable)
  		if (init)
  			pipeline_full <= 0;
  		else if (next_word)
  			pipeline_full <= 1;
  end
			
//--------------------------------------------------------------------------------------

// instantiate address generation unit
agnus_blitter_adrgen address_generator_1
(
	.clk(clk),
  .clk7_en(clk7_en),
	.reset(reset),
	.ptrsel(ptrsel),
	.modsel(modsel),
	.enaptr(enaptr),
	.incptr(incptr),
	.decptr(decptr),
	.addmod(addmod),
	.submod(submod),
	.sign_out(sign_out),
	.data_in(data_in),
	.reg_address_in(reg_address_in),
	.address_out(address_out)
);

// custom register address output
always @(*)
	case (chsel)
		CHA : reg_address_out = BLTADAT[8:1]; 
		CHB : reg_address_out = BLTBDAT[8:1]; 
		CHC : reg_address_out = BLTCDAT[8:1]; 
		CHD : reg_address_out = BLTDDAT[8:1]; 
	endcase

//--------------------------------------------------------------------------------------

assign 	enable = enadma & clkena;
assign 	reqdma = dma_req & enable;
assign	dma_ack = ackdma;

wire   lineinc = (bltcon1[4] && !bltcon1[2] || !bltcon1[4] && !bltcon1[3] && !sign_del) && ash==4'b1111 ? 1'b1 : 1'b0;
wire   linedec = (bltcon1[4] &&  bltcon1[2] || !bltcon1[4] &&  bltcon1[3] && !sign_del) && ash==4'b0000 ? 1'b1 : 1'b0;
wire   lineadd = !bltcon1[4] && !bltcon1[2] ||  bltcon1[4] && !bltcon1[3] && !sign_del ? 1'b1 : 1'b0;
wire   linesub = !bltcon1[4] &&  bltcon1[2] ||  bltcon1[4] &&  bltcon1[3] && !sign_del ? 1'b1 : 1'b0;

// blitter FSM
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      blt_state <= BLT_IDLE;
    else if (blt_state == BLT_FROZEN) begin
      // A new BLTSIZE starts the next blit and releases the freeze.
      if (reg_address_in[8:1] == BLTSIZE[8:1] ||
          (reg_address_in[8:1] == BLTSIZH[8:1] && ecs))
        blt_state <= BLT_INIT;
      else
        blt_state <= BLT_FROZEN;
    end
    else if (freeze_on_bltcon1)
      blt_state <= BLT_FROZEN;
    else
      blt_state <= blt_next;
  end

always @(*)
	case (blt_state)
	
		BLT_IDLE:
		begin
			chsel = 2'bXX;
			ptrsel = 2'bXX;
			modsel = 2'bXX;
			enaptr = 1'b0;
			incptr = 1'bX;
			decptr = 1'bX;
			addmod = 1'bX;
			submod = 1'bX;
			dma_req = 1'b0;

			if (enable)
				if (start)
					blt_next = BLT_INIT;
				else
					blt_next = BLT_IDLE;
			else
				blt_next = BLT_IDLE;
		end
				
		BLT_INIT:
		begin
			chsel = 2'bXX;
			ptrsel = 2'bXX;
			modsel = 2'bXX;
			enaptr = 1'b0;
			incptr = 1'bX;
			decptr = 1'bX;
			addmod = 1'bX;
			submod = 1'bX;
			dma_req = 1'b0;
			
			if (enable)
				if (line)
					blt_next = BLT_L1; // go to first line draw cycle
				else
					blt_next = BLT_A;
			else
				blt_next = BLT_INIT;
		end
		
		BLT_A: // first blit cycle (channel A source data fetch or empty cycle)
		begin
			chsel = CHA;
			ptrsel = CHA;
			modsel = CHA;
			enaptr = dma_ack;
			incptr = ~desc;
			decptr = desc;
			addmod = ~desc & last_word; // add or substract modulo when last word in a line is fetched
			submod = desc & last_word;
			dma_req = usea; // empty cycle if channel A is not enabled

			if (enable)			
				if (useb)
					blt_next = BLT_B;
				else if (usec || ife || efe) // in fill modes channel C cycle is always used (might be empty if channel C is not enabled)
					blt_next = BLT_C;
				else
					blt_next = BLT_D;
			else
				blt_next = BLT_A;
		end
		
		BLT_B: // second blit cycle (always channel B fetch - if channel B is not enabled this cycle is skipped)
		begin
			chsel = CHB;
			ptrsel = CHB;
			modsel = CHB;
			enaptr = dma_ack;
			incptr = ~desc;
			decptr = desc;
			addmod = ~desc & last_word;
			submod = desc & last_word;
			dma_req = 1'b1; // we can only reach this state if channel B is enabled (USEB is set)

			if (enable)			
				if (usec || ife || efe) // in fill modes channel C cycle is always used (might be empty if channel C is not enabled)
					blt_next = BLT_C;
				else
					blt_next = BLT_D;
			else
				blt_next = BLT_B;
		end
		
		BLT_C:
		begin
			chsel = CHC;
			ptrsel = CHC;
			modsel = CHC;
			enaptr = dma_ack;
			incptr = ~desc;
			decptr = desc;
			addmod = ~desc & last_word;
			submod = desc & last_word;
			dma_req = usec; // channel C is enabled when USEC is set - in fill mode empty cycle if not enabled

			if (enable)
				if (used)
					blt_next = BLT_D;
				else if (last_word && last_line)
					blt_next = BLT_IDLE;
				else
					blt_next = BLT_A;			
			else
				blt_next = BLT_C;
		end
		
		BLT_D:
		begin
			chsel = CHD;
			ptrsel = CHD;
			modsel = CHD;
			enaptr = dma_ack;
			incptr = ~desc;
			decptr = desc;
			addmod = ~desc & last_word_del;
			submod = desc & last_word_del;
			dma_req = used & pipeline_full; // request DMA cycle if channel D holding register is full
			
			if (enable)
				if (last_word && last_line) 
					if (used)
						blt_next = BLT_E; // if last data store cycle go to the first pipeline flush state
					else
						blt_next = BLT_IDLE; // if D channel is not used go to IDLE state
				else
					blt_next = BLT_A;
			else
				blt_next = BLT_D;
		end

		BLT_E: // empty cycle to allow data propagation through D hold register
		begin
			chsel = 2'bXX;
			ptrsel = 2'bXX;
			modsel = 2'bXX;
			enaptr = 1'b0;
			incptr = 1'bX;
			decptr = 1'bX;
			addmod = 1'bX;
			submod = 1'bX;
			dma_req = 1'b0;
			
			if (clkena)
				blt_next = BLT_F; // go to the last D hold register store cycle
			else
				blt_next = BLT_E;
		end

		BLT_F: // flush pipeline (store the last D hold register value)
		begin
			chsel = CHD;
			ptrsel = CHD;
			modsel = CHD;
			enaptr = dma_ack;
			incptr = ~desc;
			decptr = desc;
			addmod = ~desc & last_word_del;
			submod = desc & last_word_del;
			dma_req = 1'b1; // request DMA cycle (D holding register is full)
			
			if (enable)
				blt_next = BLT_IDLE; // it's the last cycle so go to IDLE state
			else
				blt_next = BLT_F;
		end
		
		BLT_L1: // update error accumulator
		begin
			chsel = CHA;
			ptrsel = CHA;
			modsel = sign ? CHB : CHA;
			enaptr = enable;
			incptr = 0;
			decptr = 0;
			addmod = 1;//pipeline_full; // update error accumulator
			submod = 0;
			dma_req = 0; // internal cycle - no DMA access

			if (enable)
				blt_next = BLT_L2;
			else
				blt_next = BLT_L1;
		end
		
		BLT_L2: // fetch source data from channel C
		begin
			chsel = CHC;
			ptrsel = CHC;
			modsel = CHC;
			enaptr = enable;   // no pointer increment except first pixel
			incptr = first_line_pixel ? lineinc : 1'b0;
			decptr = first_line_pixel ? linedec : 1'b0;
			addmod = first_line_pixel ? lineadd : 1'b0;
			submod = first_line_pixel ? linesub : 1'b0;
			dma_req = usec;
			
			if (enable)
				blt_next = BLT_L3;
			else
				blt_next = BLT_L2;
		end
		
		BLT_L3: // free cycle (data propagates from source holding registers to channel D hold register - no pipelining)
		begin   // increment D pointer except first pixel
			chsel = CHA;
			ptrsel = CHD;   //CHA;
			modsel = CHD;   //CHA;
			enaptr = first_line_pixel ? 1'b0 : enable;   //0;
			incptr = lineinc;   //0;
			decptr = linedec;   //0;
			addmod = lineadd;   //0;
			submod = linesub;   //0;
			dma_req = 0;

			if (enable)
				blt_next = BLT_L4;
			else
				blt_next = BLT_L3;
		end
		
		BLT_L4: // store cycle - initial write @ D ptr, all succesive @ C ptr, always modulo C used
		begin
			chsel = CHD;
			ptrsel = first_line_pixel ? CHD : CHC;
			modsel = first_line_pixel ? CHD : CHC;
			enaptr = enable;
			incptr = lineinc;
			decptr = linedec;
			addmod = lineadd;
			submod = linesub;
			// in 'one dot' mode this might be a free bus cycle
			dma_req = usec & (~bltcon1[1] | ~bltcon1[4] | first_pixel); // request DMA cycle
			
			if (enable)
				if (last_line) // if last data store go to idle state
					blt_next = BLT_IDLE;
				else
					blt_next = BLT_L1;
			else
				blt_next = BLT_L4;
		end

		BLT_FROZEN:
			begin
			// Real Amiga blitter is frozen.
			// No DMA cycle, no address generation and no state progress.
			chsel  = 2'bXX;
			ptrsel = 2'bXX;
			modsel = 2'bXX;

			enaptr = 1'b0;
			incptr = 1'b0;
			decptr = 1'b0;
			addmod = 1'b0;
			submod = 1'b0;

			dma_req = 1'b0;

			blt_next = BLT_FROZEN;
		end

		default:
		begin
			chsel = CHA;
			ptrsel = 2'bXX;
			modsel = 2'bXX;
			enaptr = 0;
			incptr = 0;
			decptr = 0;
			addmod = 0;
			submod = 0;
			dma_req = 0;
			
			blt_next = BLT_IDLE;
		end
		
	endcase

// init blitter pipeline (reload height counter)
assign init = blt_state==BLT_INIT ? 1'b1 : 1'b0;
	
// indicates last cycle of a single sequence	
assign next_word = blt_state==BLT_C && !used || blt_state==BLT_D || blt_state==BLT_L2 || blt_state==BLT_L4 ? 1'b1 : 1'b0;

// stores a new value to D hold register
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		store_result <= 0;
  	else
  		store_result <= enable && next_word;
  end

// blitter busy flag is cleared immediately after last source data is fetched (if D channel is not enabled) or the last but one result is stored
// signal 'done' is used to clear the 'busy' and 'start' flags
assign done = (blt_state==BLT_C && !used || blt_state==BLT_D) && last_word && last_line || blt_state==BLT_L4 && last_line ? enable : 1'b0;

always @(posedge clk)
  if (clk7_en) begin
  	if (enable)
  		if (blt_state==BLT_INIT)
  			first_pixel <= 1'b1;
  		else if (blt_state==BLT_L4)
  			first_pixel <= ~sign_del;
  end

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset) begin
      first_line_pixel <= #1 1'b0;
    end else if (enable) begin
      if (blt_state == BLT_INIT)
        first_line_pixel <= #1 1'b1;
      else if (blt_state == BLT_L4)
        first_line_pixel <= #1 1'b0;
    end
  end
end

always @(posedge clk)
  if (clk7_en) begin
  	if (reg_address_in[8:1]==BLTCON1[8:1])
  		sign <= data_in[6]; // initial sign value
  	else if (enable && blt_state==BLT_L1)
  		sign <= sign_out; // latch sign output from error accumulator
  end

always @(posedge clk)
  if (clk7_en) begin
  	if (enable && blt_state==BLT_L1)
  		sign_del <= sign;
  end

assign incash = enable && blt_state==BLT_L4 && (bltcon1[4] && !bltcon1[2] || !bltcon1[4] && !bltcon1[3] && !sign_del) ? 1'b1 : 1'b0;
assign decash = enable && blt_state==BLT_L4 && (bltcon1[4] &&  bltcon1[2] || !bltcon1[4] &&  bltcon1[3] && !sign_del) ? 1'b1 : 1'b0;
assign decbsh = enable && blt_state==BLT_L4 ? 1'b1 : 1'b0;

//--------------------------------------------------------------------------------------


endmodule

