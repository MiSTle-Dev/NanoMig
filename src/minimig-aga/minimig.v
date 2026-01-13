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
// This is the top module for the Minimig rev1.0 board
//
// 19-03-2005 	-started coding
// 10-04-2005	-added cia's 
//				-verified timers a/b and I/O ports
// 11-04-2005	-adapted top to cleaned up address decoder
//				-connected cia's to .clk(~qclk) and .tick(e) for testing
// 13-04-2005	-_foe and _loe are now made with clocks driving FF's
//				-sram_bridge now also gets .clk(clk)
// 18-04-2005	-added second synchronisation latch for mreset
// 19-04-2005	-bootrom is now 2Kbyte large
// 05-05-2005	-made preparations for dma (bus multiplexers between agnus and cpu)
// 15-05-2005	-added denise
// 				-connected vertb (vertical blank intterupt) to int3 input of paula
// 18-05-2005	-removed interlaced top input pin
// 28-06-2005	-done some experimentation to solve logic loop in Agnus
// 17-07-2005	-connected second ram bank to hold kickstart rom
// 				-added ovl (kickstart overlay) and boot (bootrom overlay) signals
//				-wired cia in/out ports more correctly
//				-wired vsync/hsync to cia's
// 18-07-2005	-experimented to get kickstart running
// 20-07-2005	-still experimenting..
// 07-08-2005	-Jahoeee!! kickstart doesn't guru anymore but 'clicks' the floppy drive !
//				-the guru's were caused by spurious writes to ram which is fixed now in the sram controller
//				-unfortunately still no insert workbench screen but that may be caused by the missing blitter
// 04-09-2005	-added blitter finished interrupt
// 11-09-2005	-added 2meg addressing for Agnus
// 13-09-2005	-added 4bit (per color) video output
// 16-10-2005	-added user IO module
// 23-10-2005	-added dmal signal wire
// 08-11-2005	-fixed typo in instantiation of Paula
// 21-11-2005	-added some signals to handle floppy
// 22-11-2005	-adapted to new add-on develop board
//				-added joystick 1 port
// 10-12-2005	-done some experimentation to find floppy bug
// 21-12-2005	-reworked code to use new style gary module
// 27-12-2005	-added dskindx interrupt
// 03-01-2006	-added dmas to avoid interference with copper cycles
// 11-01-2006	-added Amber
// 15-01-2006	-added syscontrol module to handle automatic boot sequence
// 22-01-2006	-removed _csync port from agnus
// 23-01-2006	-added fastblit input
// 24-01-2006	-cia's now count positive _hsync/_vsync transitions
// 14-02-2006	-code clean up
//				-added fastchip input
// 19-02-2006	-improved indx disk interrupt timing
//				-cia timers now connect to sol/sof
// 12-11-2006	-started porting code to Minimig rev1.0 board
// 17-11-2006	-added address decoding for Minimig rev1.0 ram
// 22-11-2006	-added keyboard reset
// 27-11-2006	-code adapted to new synchronous bootrom
// 03-12-2006	-added dimming powerled
// 11-12-2006	-updated code to new ciaa
// 27-12-2006	-updated code to new ciab
// 24-06-2007	-moved cpu/sram/clock and syscontrol to this file to reduce number of source files
//
// TODO: 		-fixs bug and implement things I forgot.....

//JB:
// 2008-07-17
//	- scan doubler with vertical and horizontal interpolation
//	- transparent osd window
//	- selected osd line highlight
//	- osd control by joystick (up and down pressed simultaneously invoke menu) 
//	- memory configuration from osd (512KB chip, 1MB chip, 512KB chip/512KB slow, 1MB chip/512KB slow)
//	- video interpolation filter configuration from osd (vertical and horizontal)
//	- user reset accessible from osd
//	- user reset to bootloader (kickstart reloading)
//	- new bootloader (text messages during kickstart loading)
//	- ECS blittter
//	- PAL/NTSC selection
//	- modified display dma engine (better compatibility)
//	- modified sprite dma engine (better compatibility)
//	- modified copper timing (better compatibility) 
//	- modified floppy interface (better read and write support)
//	- Action Replay III module for debugging (takes 512KB memory bank)
//
// Thanks to:
// Dennis for his great Minimig
// Loriano for impressive enclosure 
// Darrin and Oscar for their ideas, support and help
// Toni for his indispensable help and logic analyzer (and WinUAE :-)
//
// 2008-09-22 	- code clean-up
// 2008-09-23	- added c1 and c3 clock anable signals
//				- adapted sram bridge to use only clk28m clock
// 2008-09-24	- added support for floppy _sel[3:1] signals
// 2008-11-14	- ram interface synchronous with clk28m, 70ns access cycle
// 2009-04-21	- code clean up
//
// Thanks to Loriano, Darrin, Richard, Edwin, Sascha, Peter and others for their help, support, ideas, testing, bug reports and feature requests.
//
// 2009-05-17	- hires OSD
// 2009-05-23	- more cycle exact CPU bus timing during CIA access
// 2009-05-24	- clean-up & renaming
// 2009-05-29	- changed blitter timing to be more cycle exact
// 2009-06-09	- fixed disk index pulses to 5 Hz (300 RPM)
// 2009-06-10	- fixed non-interlaced frames to be long
// 2009-06-11	- fixed serial port divider
// 2009-06-12	- CIA's SDR register returns written value
// 2009-07-01	- enabling of ddfstrt/ddfstop ECS extension bits is configurable
// 2009-08-11	- support for second hardfile
// 2009-08-16	- Action Replay problem fixed (thanks Sascha)
// 2009-12-15 - improved blitter data flow
// 2009-12-16 - improved bitplane dma timing
//        - Denise id is selectable
// 2010-05-30 - htotal changed
// 2010-07-27 - fixed isue with external reset
// 2010-07-28 - added vsync for the MCU
// 2010-08-05 - added cache for the CPU
// 2010-08-15 - added joystick emulation
//
// SB:
// 2010-12-22 - better drive step sound at 31KHz mode
// 2011-03-06 - changed autofire function to handless mode
// 2011-03-08 - added dip and fat agnus DIWSTRT handling (fix RoboCop2)
// 2011-04-02 - added functional ciaa port b (parallel) register to let Unreal game work and some trainer store data
// 2011-04-04 - added pwm controlled power-led at "off" state and active Turbo mode (thanks Herzi for the idea)
// 2011-04-10 - added readable VPOSW and VHPOSW register (fix for RSI slideshow)
// 11-04-2011 - autofire function toggle able via capslock / led status
// 2011-04-24 - fixed CIA TOD read
// 2011-07-21 - changed '#' key scan code, thanks Chris
//
// TobiFlex(TF):
// 2012-02-12  - change sigma/delta module
//
// SB:
// 2012-03-23 - fixed sprite enable signal (coppermaster demo)

module minimig
(
	//m68k pins
	input [23:1]  cpu_address, // m68k address bus
	output [15:0] cpu_data, // m68k data bus
	input [15:0]  cpudata_in, // m68k data in
	output [2:0]  _cpu_ipl, // m68k interrupt request
	input	      _cpu_as, // m68k address strobe
	input	      _cpu_uds, // m68k upper data strobe
	input	      _cpu_lds, // m68k lower data strobe
	input	      cpu_r_w, // m68k read / write
	output	      _cpu_dtack, // m68k data acknowledge
	output	      _cpu_reset, // m68k reset
	input	      _cpu_reset_in,//m68k reset in
	input [31:0]  nmi_addr, // m68k NMI address
	output	      ovr, // NMI address decoding override
	output reg    ovl, //kickstart overlay enable

	//sram pins
	output [15:0] ram_data, // sram data bus
	input [15:0]  ramdata_in, // sram data bus in
	output [23:1] ram_address, // sram address bus
	output	      _ram_bhe, // sram upper byte select
	output	      _ram_ble, // sram lower byte select
	output	      _ram_we, // sram write enable
	output	      _ram_oe, // sram output enable
	input [47:0]  chip48, // big chipram read
        output	      refresh, // current bus cycle is refresh
 
	//system	pins
	input	      rst_ext, // reset from ctrl block
	output	      rst_out, // minimig reset status
	input	      clk, // 28.37516 MHz clock
	input	      clk7_en, // 7MHz clock enable
	input	      clk7n_en, // 7MHz negedge clock enable
	input	      c1, // clock enable signal
	input	      c3, // clock enable signal
	input	      cck, // colour clock enable
	input [9:0]   eclk, // ECLK enable (1/10th of CLK)

	//rs232 pins
	input	      rxd, // rs232 receive
	output	      txd, // rs232 send
	input	      cts, // rs232 clear to send
	output	      rts, // rs232 request to send
	output	      dtr, // rs232 Data Terminal Ready
	input	      dsr, // rs232 Data Set Ready
	input	      cd, // rs232 Carrier Detect
	input	      ri, // rs232 Ring Indicator

	//I/O
	input [15:0]  _joy1, // joystick 1 [fire2,fire,up,down,left,right] (default mouse port)
	input [15:0]  _joy2, // joystick 2 [fire2,fire,up,down,left,right] (default joystick port)
	input [15:0]  _joy3, // joystick 3 [fire2,fire,up,down,left,right]
	input [15:0]  _joy4, // joystick 4 [fire2,fire,up,down,left,right]
	input [15:0]  joya1,
	input [15:0]  joya2,
	input [2:0]   mouse_btn, // mouse buttons
	input	      kms_level,
	input [1:0]   kbd_mouse_type,
	input [7:0]   kbd_mouse_data,
	output	      pwr_led, // power led
	output	      fdd_led, // disk activity LED, active when DMA is on
	output	      hdd_led,
	input [64:0]  rtc,

	input [7:0]   memory_config,
	input [5:0]   chipset_config,
	input [3:0]   floppy_config,
	input [5:0]   ide_config,

	//host controller interface (SPI)
	input	      IO_UIO,
	input	      IO_FPGA,
	input	      IO_STROBE,
	output	      IO_WAIT,
	input [15:0]  IO_DIN,
	output [15:0] IO_DOUT,

        // Interface MiSTeryNano sd card interface. This very simple connection allows the core
        // to request sectors from within a OSD selected image file
	input [3:0]   sdc_img_mounted,
	input [31:0]  sdc_img_size,
        output [3:0]  sdc_rd,
        output [31:0] sdc_sector,
        input	      sdc_busy,
        input	      sdc_done,
	input	      sdc_byte_in_strobe,
	input [8:0]   sdc_byte_addr,
	input [7:0]   sdc_byte_in_data, 
 
	//video
	output	      _hsync, // horizontal sync
	output	      _vsync, // vertical sync
	output	      _csync, // composite sync
	output	      field1,
	output	      lace,
	output	      hblank,
	output	      vblank,
	output [7:0]  red,
	output [7:0]  green,
	output [7:0]  blue,
	output [1:0]  ar,
	output [2:0]  scanline,
	output	      ce_pix,
	output [1:0]  res,
	output [8:0]  htotal, //video line length (140ns units)

	//audio
	output [14:0] ldata, // left DAC data
	output [14:0] rdata, // right DAC data
	output [8:0]  ldata_okk, // left DAC data  (PWM volume)
	output [8:0]  rdata_okk, // right DAC data (PWM volume)
	output [1:0]  aud_mix,

`ifdef ENABLE_TOCCATA
	// Toccata audio
	input	      toccata_ena,
	input [7:0]   toccata_base,
	output [15:0] toccata_aud_left,
	output [15:0] toccata_aud_right,
`endif
 
	//user i/o
`ifndef ENABLE_USERIO_SPI   
	input [1:0]   cpucfg,
	input [2:0]   cachecfg,
`else
	output [1:0]  cpucfg,
	output [2:0]  cachecfg,
`endif
	output [6:0]  memcfg,
	output	      bootrom, // enable bootrom magic in gary.v
	output	      ide_ena,

	output	      ide_fast,
	input	      ide_ext_irq,
	output [5:0]  ide_req,
	input [4:0]   ide_address,
	input	      ide_write,
	input [15:0]  ide_writedata,
	input	      ide_read,
	output [15:0] ide_readdata
);
   
//--------------------------------------------------------------------------------------

parameter [0:0] NTSC = 1'b0;	//Agnus type (PAL/NTSC)

//--------------------------------------------------------------------------------------

//local signals for data bus
wire [15:0] cpu_data_in;		//cpu data bus in
wire [15:0] cpu_data_out;	   //cpu data bus out
wire [15:0] ram_data_in;		//ram data bus in
wire [15:0] ram_data_out;	   //ram data bus out
wire [15:0] custom_data_in;	//custom chips data bus in
wire [15:0] custom_data_out;	//custom chips data bus out
wire [15:0] agnus_data_out;	//agnus data out
wire [15:0] paula_data_out;	//paula data bus out
wire [15:0] denise_data_out;	//denise data bus out
wire [15:0] user_data_out;	   //user IO data out
wire [15:0] gary_data_out;	   //data out from memory bus multiplexer
wire [15:0] gayle_data_out;	//Gayle data out
wire [15:0] cia_data_out;	   //cia A+B data bus out
wire [15:0] ar3_data_out;	   //Action Replay data out

//local signals for address bus
wire [23:1] cpu_address_out;	//cpu address out
wire [20:1] dma_address_out;	//agnus address out
wire [23:1] ram_address_out;	//ram address out

//local signals for control bus
wire        ram_rd;				//ram read enable
wire        ram_hwr;				//ram high byte write enable 
wire        ram_lwr;				//ram low byte write enable 
wire        cpu_rd; 				//cpu read enable
wire        rd_cyc;
wire        cpu_hwr;				//cpu high byte write enable
wire        cpu_lwr;				//cpu low byte write enable

//register address bus
wire  [8:1] reg_address; 		//main register address bus

//rest of local signals
wire        cpu_custom;
wire        dbr;					//data bus request, Agnus tells CPU that she is using the bus
wire        dbwe;					//data bus write enable, Agnus tells the RAM it's writing data
wire        dbs;					//data bus slow down, used for slowing down CPU access to chip, slow and custor register address space
wire        xbs;					//cross bridge access (memory and custom registers)
wire        _led;					//power led
wire  [3:0] sel_chip;			//chip ram select
wire  [2:0] sel_slow;			//slow ram select
wire        sel_kick;			//rom select
wire        sel_kick1mb;      // 1MB upper rom select
wire        sel_kick256kmirror;// mirror f8-fb to fc-ff in a1k mode    
wire        sel_cia;				//CIA address space
wire        sel_reg;				//chip register select
wire        sel_rtc;
wire        sel_cia_a;			//cia A select
wire        sel_cia_b;			//cia B select
`ifdef ENABLE_TOCCATA
wire        sel_toccata;
`endif
wire        int2;					//intterrupt 2
wire        int3;					//intterrupt 3 
wire        int6;					//intterrupt 6
wire        int6_toccata;
wire        freeze;				//Action Replay freeze button
wire        _fire0;				//joystick 1 fire signal to cia A
wire        _fire1;				//joystick 2 fire signal to cia A
wire        _fire0_dat;
wire        _fire1_dat;
wire  [3:0] audio_dmal;		   //audio dma data transfer request from Paula to Agnus
wire  [3:0] audio_dmas;		   //audio dma location pointer restart from Paula to Agnus
wire        disk_dmal;			//disk dma data transfer request from Paula to Agnus
wire        disk_dmas;			//disk dma special request from Paula to Agnus
wire        index;				//disk index interrupt

//local video signals
wire        sol;					//start of video line
wire        sof;					//start of video frame
wire        vbl_int;          // vertical blanking interrupt
wire        strhor_denise;		//horizontal strobe for Denise
wire        strhor_paula;		//horizontal strobe for Paula
wire        harddis;
wire        varbeamen;

//local floppy signals (CIA<-->Paula)
wire        _step;				//step heads of disk
wire        direc;				//step heads direction
wire        _sel0;				//disk0 select 	
wire        _sel1;				//disk1 select 	
wire        _sel2;				//disk2 select 	
wire        _sel3;				//disk3 select 	
wire        side;					//upper/lower disk head
wire        _motor;				//disk motor control
wire        _track0;				//track zero detect
wire        _change;				//disk has been removed from drive
wire        _ready;				//disk is ready
wire        _wprot;				//disk is write-protected

wire  [1:0] blver;
wire        hbl, hde;
assign      hblank = blver ? ~hde : hbl;

wire        IO_WAIT_PAULA, IO_WAIT_OSD;
wire [15:0] IO_DOUT_PAULA;

assign      IO_DOUT = IO_DOUT_PAULA;
assign      IO_WAIT = IO_WAIT_PAULA | IO_WAIT_OSD;

//--------------------------------------------------------------------------------------

wire        bls;					//blitter slowdown - required for sharing bus cycles between Blitter and CPU

wire        cpurst;
wire        cpuhlt;

wire        int7;					//int7 interrupt request from Action Replay
wire  [2:0] _iplx;			   //interrupt request lines from Paula
wire        sel_cart;			//Action Replay RAM select
wire [15:0] cart_data_out;

wire        usrrst;				//user reset from osd interface
wire        hires;				//hires signal from Denise for interpolation filter enable in Amber

//gayle stuff
wire        sel_ide;				//select IDE drive registers
wire        sel_gayle;			//select GAYLE control registers
wire        gayle_irq;			//interrupt request
wire        gayle_nrdy;       // HDD fifo is not ready for reading

wire	[7:0] bank;					//memory bank select

reg         ntsc = NTSC;		//PAL/NTSC video mode selection

// host interface
wire        host_cs;
wire [23:0] host_adr;
wire        host_we;
wire [ 1:0] host_bs;
wire [15:0] host_wdat;
wire [15:0] host_rdat;
wire        host_ack;

wire        sys_reset;    		//reset output from minimig_syscontrol.v
wire        rom_readonly; 		//writeprotect $f8-ff in gary.v

wire        reset = sys_reset | ~_cpu_reset_in; // both tg68k and minimig_syscontrol hold the reset signal for some clicks

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

assign pwr_led = ~_led;

assign memcfg = {memory_config[7],memory_config[5:0]};
// assign cachecfg = {cachecfg_pre[2], ~ovl, ~ovl};

// NTSC/PAL switching is controlled by OSD menu, change requires reset to take effect
always @(posedge clk) if (clk7_en && reset) ntsc <= chipset_config[1];

assign ide_ena  = ide_config[0];
assign ide_fast = ~ide_config[5] & cpucfg[1];

//--------------------------------------------------------------------------------------

//instantiate agnus
agnus AGNUS1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.cck(cck),
	.reset(reset),
	.aen(sel_reg),
	.rd(cpu_rd),
	.hwr(cpu_hwr),
	.lwr(cpu_lwr),
	.data_in(custom_data_in),
	.data_out(agnus_data_out),
	.address_in(cpu_address_out[8:1]),
	.address_out(dma_address_out),
	.reg_address_out(reg_address),
	.cpu_custom(cpu_custom),
	.dbr(dbr),
	.dbwe(dbwe),
	.refresh(refresh),
	._hsync(_hsync),
	._vsync(_vsync),
	._csync(_csync),
	.hde(hde),
	.field1(field1),
	.lace(lace),
	.hblank(hbl),
	.vblank(vblank),
	.sol(sol),
	.sof(sof),
	.vbl_int(vbl_int),
	.strhor_denise(strhor_denise),
	.strhor_paula(strhor_paula),
	.htotal(htotal),
	.harddis(harddis),
	.varbeamen(varbeamen),
	.int3(int3),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.disk_dmal(disk_dmal),
	.disk_dmas(disk_dmas),
	.bls(bls),
	.ntsc(ntsc),
	.a1k(chipset_config[2]),
	.ecs(|chipset_config[4:3]),
	.aga(chipset_config[4]),
	.floppy_speed(floppy_config[0])
);

//instantiate paula
paula PAULA1
(
	.clk(clk),
	.clk7_en (clk7_en),
	.clk7n_en (clk7n_en),
	.cck(cck),
	.reset(reset),
	.reg_address_in(reg_address),
	.data_in(custom_data_in),
	.data_out(paula_data_out),
	.txd(txd),
	.rxd(rxd),
	.ntsc(ntsc),
	.sof(sof),
	.strhor(strhor_paula),
	.vblint(vbl_int),
	.int2(int2|(ide_fast ? ide_ext_irq : gayle_irq)),
	.int3(int3),
	.int6(int6 | int6_toccata),
	._ipl(_iplx),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.disk_dmal(disk_dmal),
	.disk_dmas(disk_dmas),
	._step(_step),
	.direc(direc),
	._sel({_sel3,_sel2,_sel1,_sel0}),
	.side(side),
	._motor(_motor),
	._track0(_track0),
	._change(_change),
	._ready(_ready),
	._wprot(_wprot),
	.index(index),
	.fdd_led(fdd_led),
	.IO_ENA(IO_FPGA),
	.IO_STROBE(IO_STROBE),
	.IO_WAIT(IO_WAIT_PAULA),
	.IO_DIN(IO_DIN),
	.IO_DOUT(IO_DOUT_PAULA),
	.ldata(ldata),
	.rdata(rdata),
	.ldata_okk(ldata_okk),
	.rdata_okk(rdata_okk),
 
        // sd card interface for floppy disk emulation
        .sdc_image_mounted(sdc_img_mounted),
        .sdc_image_size(sdc_img_size),           // length of image file
        .sdc_rd(sdc_rd),
        .sdc_sector(sdc_sector),
        .sdc_busy(sdc_busy),
        .sdc_done(sdc_done),
	.sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),

	.floppy_wrprot(floppy_config[1]),
	.floppy_drives(floppy_config[3:2])
);

wire [2:0] cachecfg_pre;
//instantiate user IO
userio USERIO1 
(	
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(reset),
	.reg_address_in(reg_address),
	.data_in(custom_data_in),
	.data_out(user_data_out),
	.pot_cnt_en(sol & ~c1 & ~c3),
	._fire0(_fire0),
	._fire1(_fire1),
	._fire0_dat(_fire0_dat),
	._fire1_dat(_fire1_dat),
	._joy1(_joy1),
	._joy2(_joy2),
	.joy_ana1(joya1),
	.joy_ana2(joya2),
	.mouse_btn(mouse_btn),
	.kbd_mouse_type(kbd_mouse_type),
	.kms_level(kms_level),
	.kbd_mouse_data(kbd_mouse_data)
`ifdef ENABLE_USERIO_SPI
        ,
	.aud_mix(aud_mix),
	.IO_ENA(IO_UIO),
	.IO_STROBE(IO_STROBE),
	.IO_WAIT(IO_WAIT_OSD),
	.IO_DIN(IO_DIN),
	.memory_config(memory_config),
	.chipset_config(chipset_config),
	.floppy_config(floppy_config),
	.scanline(scanline),
	.ar(ar),
	.blver(blver),
	.ide_config(ide_config),
	.cpu_config(cpucfg),
	.cache_config(cachecfg_pre),
	.usrrst(usrrst),
	.cpurst(cpurst),
	.cpuhlt(cpuhlt),
	.bootrom(bootrom),
	.host_cs(host_cs),
	.host_adr(host_adr),
	.host_we(host_we),
	.host_bs(host_bs),
	.host_wdat(host_wdat),
	.host_rdat(host_rdat),
	.host_ack(host_ack)
`endif
);
   
wire shres;
assign ce_pix = (shres & |chipset_config[4:3]) | (hires & clk7n_en) | clk7_en;
assign res = {shres & |chipset_config[4:3], hires};

//instantiate Denise
denise DENISE1
(		
	.clk(clk),
	.clk7_en(clk7_en),
	.c1(c1),
	.c3(c3),
	.cck(cck),
	.reset(reset),
	.strhor(strhor_denise),
	.reg_address_in(reg_address),
	.data_in(custom_data_in),
	.chip48(chip48),
	.data_out(denise_data_out),
	.blank(~_hsync|vblank),
	.red(red),
	.green(green),
	.blue(blue),
	.a1k(chipset_config[2]),
	.ecs(|chipset_config[4:3]),
	.aga(chipset_config[4]),
	.hires(hires),
	.shres(shres)
);

//instantiate cia A
wire [3:0] porta_out;
assign {_fire1_dat,_fire0_dat,_led} = porta_out[3:1];

ciaa CIAA1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.clk7n_en(clk7n_en),
	.aen(sel_cia_a),
	.rd(cpu_rd),
	.wr(cpu_lwr|cpu_hwr),
	.reset(reset),
	.rs(cpu_address_out[11:8]),
	.data_in(cpu_data_out[7:0]),
	.data_out(cia_data_out[7:0]),
	.tick(_vsync),
	.eclk(eclk[8]),
	.irq(int2),
	.porta_in({_fire1,_fire0,_ready,_track0,_wprot,_change}),
	.porta_out(porta_out),
	.portb_in({_joy4[0],_joy4[1],_joy4[2],_joy4[3],_joy3[0],_joy3[1],_joy3[2],_joy3[3]}),
	.kbd_mouse_type(kbd_mouse_type),
	.kms_level(kms_level),
	.kbd_mouse_data(kbd_mouse_data), 
	.freeze(freeze),
	.hrtmon_en (memory_config[6])
);

//instantiate cia B
ciab CIAB1 
(
	.clk(clk),
	.clk7_en(clk7_en),
	.aen(sel_cia_b),
	.rd(cpu_rd),
	.wr(cpu_hwr|cpu_lwr),
	.reset(reset),
	.rs(cpu_address_out[11:8]),
	.data_in(cpu_data_out[15:8]),
	.data_out(cia_data_out[15:8]),
	.tick(_hsync),
	.eclk(eclk[8]),
	.irq(int6),
	.flag(index),
	.porta_in({cd,cts,dsr,ri&_joy3[4],1'b1,_joy4[4]}),
	.porta_out({dtr,rts}),
	.portb_out({_motor,_sel3,_sel2,_sel1,_sel0,side,direc,_step})
);

//instantiate cpu bridge
minimig_m68k_bridge CPU1 
(
	.clk(clk),
	.clk7_en(clk7_en),
	.clk7n_en(clk7n_en),
	.c1(c1),
	.c3(c3),
	.cck(cck),
	.eclk(eclk),
	.vpa(sel_cia),
	.dbr(dbr),
	.dbs(dbs),
	.xbs(xbs),
	.nrdy(gayle_nrdy & rd_cyc),
	.bls(bls),
	.memory_config(memory_config[3:0]),
	._as(_cpu_as),
	._lds(_cpu_lds),
	._uds(_cpu_uds),
	.r_w(cpu_r_w),
	._dtack(_cpu_dtack),
	.rd(cpu_rd),
	.rd_cyc(rd_cyc),
	.hwr(cpu_hwr),
	.lwr(cpu_lwr),
	.address(cpu_address),
	.address_out(cpu_address_out),
	.cpudatain(cpudata_in),
	.data(cpu_data),
	.data_out(cpu_data_out),
	.data_in(cpu_data_in),
	._cpu_reset (_cpu_reset),
	.cpu_halt (cpuhlt),
	.host_cs (host_cs),
	.host_adr (host_adr[23:1]),
	.host_we (host_we),
	.host_bs (host_bs),
	.host_wdat (host_wdat),
	.host_rdat (host_rdat),
	.host_ack (host_ack)
);

//instantiate RAM banks mapper
minimig_bankmapper BMAP1
(
	.chip0((~ovr|~cpu_rd|dbr|cpuhlt) & sel_chip[0]),
	.chip1(sel_chip[1]),
	.chip2(sel_chip[2]),
	.chip3(sel_chip[3]),	
	.slow0(sel_slow[0]),
	.slow1(sel_slow[1]),
	.slow2(sel_slow[2]),
	.kick(sel_kick),
	.kick1mb(sel_kick1mb),
	.kick256kmirror(sel_kick256kmirror),
 	.cart(sel_cart),
	.memory_config(memory_config[3:0]),
	.bank(bank)
);

//instantiate sram bridge
minimig_sram_bridge RAM1 
(
	.clk(clk),
	.c1(c1),
	.c3(c3),	
	.bank(bank),
	.address_in(ram_address_out),
	.data_in(ram_data_in),
	.data_out(ram_data_out),
	.rd(ram_rd),
	.hwr(ram_hwr),
	.lwr(ram_lwr),
	._bhe(_ram_bhe),
	._ble(_ram_ble),
	._we(_ram_we),
	._oe(_ram_oe),
	.address(ram_address),
	.data(ram_data),	
	.ramdata_in(ramdata_in)	
);

`ifdef ENABLE_CART
cart CART1
(
  .clk(clk),
  .clk7_en(clk7_en),
  .clk7n_en(clk7n_en),
  .cpu_rst(!_cpu_reset),
  .cpu_address_in(cpu_address_out),
  ._cpu_as(_cpu_as),
  .cpu_rd(cpu_rd),
  .cpu_hwr(cpu_hwr),
  .cpu_lwr(cpu_lwr),
  .nmi_addr(nmi_addr),
  .reg_address_in(reg_address),
  .reg_data_in(custom_data_in),
  .dbr(dbr),
  .ovl(ovl),
  .freeze(freeze),
  .cart_data_out(cart_data_out),
  .int7(int7),
  .sel_cart(sel_cart),
  .ovr(ovr),
  .cpuhlt(cpuhlt)
);
`else
assign int7 = 1'b0;
assign ovr =  1'b0;
assign sel_cart =  1'b0;
`endif
   
//level 7 interrupt for CPU
assign _cpu_ipl = int7 ? 3'b000 : _iplx;	//m68k interrupt request

//instantiate gary
gary GARY1 
(
	.cpu_address_in(cpu_address_out),
	.dma_address_in(dma_address_out),
	.ram_address_out(ram_address_out),
	.cpu_data_out(cpu_data_out),
	.cpu_data_in(gary_data_out),
	.custom_data_out(custom_data_out),
	.custom_data_in(custom_data_in),
	.ram_data_out(ram_data_out),
	.ram_data_in(ram_data_in),
	.cpu_rd(cpu_rd),
	.cpu_hwr(cpu_hwr),
	.cpu_lwr(cpu_lwr),
	.cpu_hlt(cpuhlt),
	.ovl(ovl),
	.dbr(dbr),
	.dbwe(dbwe),
	.dbs(dbs),
	.xbs(xbs),
	.memory_config(memory_config[3:0]),
	.hdc_ena(ide_ena & ~ide_fast), // Gayle decoding enable	
`ifdef ENABLE_TOCCATA
	.toccata_ena(toccata_ena),
	.toccata_base(toccata_base),
`endif
	.ram_rd(ram_rd),
	.ram_hwr(ram_hwr),
	.ram_lwr(ram_lwr),
	.ecs(|chipset_config[4:3]),
	.a1k(chipset_config[2]),
	.sel_chip(sel_chip),
	.sel_slow(sel_slow),
	.sel_kick(sel_kick),
	.sel_kick1mb(sel_kick1mb),
	.sel_kick256kmirror(sel_kick256kmirror),
	.sel_cia(sel_cia),
	.sel_reg(sel_reg),
	.sel_cia_a(sel_cia_a),
	.sel_cia_b(sel_cia_b),
	.sel_ide(sel_ide),
	.sel_gayle(sel_gayle),
	.sel_rtc(sel_rtc),
`ifdef ENABLE_TOCCATA
	.sel_toccata(sel_toccata),
`endif
	.reset(reset),
	.clk(clk),
	.rom_readonly(rom_readonly),
	.bootrom(bootrom)
);

gayle GAYLE1
(
	.clk(clk),
	.reset(reset),
	.addr(cpu_address_out),
	.data_in(cpu_data_out),
	.data_out(gayle_data_out),
	.rd(cpu_rd),
	.wr(cpu_hwr),
	.sel_ide(sel_ide),
	.sel_gayle(sel_gayle),
	.irq(gayle_irq),
	.nrdy(gayle_nrdy),

	.ide_req(ide_req),
	.ide_address(ide_address),
	.ide_write(ide_write),
	.ide_writedata(ide_writedata),
	.ide_read(ide_read),
	.ide_readdata(ide_readdata),

	.led(hdd_led)
);
   
//instantiate system control
minimig_syscontrol CONTROL1 
(	
	.clk(clk),
	.clk7_en(clk7_en),
	.cnt(sof),
	.mrst(usrrst | rst_ext),
	.reset(sys_reset)
);

always @(posedge clk) begin
	if(~_cpu_reset | ~_cpu_reset_in)       ovl <= 1;
	else if(sel_cia_a & (cpu_lwr|cpu_hwr)) ovl <= 0;
end

//-------------------------------------------------------------------------------------

`ifdef ENABLE_RTC
wire [15:0] rtc_out = (sel_rtc && cpu_rd) ? {12'h000, rtc_reg[{cpu_address_out[5:2], 2'b00} +:4]} : 16'h0000;

reg [63:0] rtc_reg;
always @(posedge clk) begin
	reg old_flg;
	reg [31:0] cnt;
	
	old_flg <= rtc[64];
	if(old_flg ^ rtc[64]) begin
		rtc_reg <= {rtc[63:8], 8'd0};
		cnt <= 0;
	end
	else if(cnt < 28375159) cnt <= cnt + 1;
	else begin
		cnt <= 0;
		if(rtc_reg[3:0] < 9) rtc_reg[3:0] <= rtc_reg[3:0] + 1'd1;
		else if(rtc_reg[7:4] < 5) rtc_reg[7:0] <= {rtc_reg[7:4] + 1'd1, 4'b0000};
	end
end
`endif

// Toccata soundcard

`ifdef ENABLE_TOCCATA
wire [15:0] toccata_out;
toccata #(
  .CLK_FREQUENCY(28_359_380)
) toccata_board (
	.clk(clk),
	.rst(reset),
	.hsync(_hsync),
	.data_in(cpu_data_out),
	.data_out(toccata_out),
	.addr(cpu_address_out[15:1]),
	.rd(cpu_rd),
	.hwr(cpu_hwr),
	.lwr(cpu_lwr),
	.sel(sel_toccata),
	.toc_int(int6_toccata),
	.out_left(toccata_aud_left),
	.out_right(toccata_aud_right)
);
`else
assign int6_toccata = 1'b0; 
`endif
   
//-------------------------------------------------------------------------------------

//data multiplexer
assign cpu_data_in[15:0]= gary_data_out[15:0]
							 | cia_data_out[15:0]
							 | gayle_data_out[15:0]
`ifdef ENABLE_CART
							 | cart_data_out[15:0]
`endif
`ifdef ENABLE_RTC
							 | rtc_out
`endif
`ifdef ENABLE_TOCCATA
							 | toccata_out
`endif
;

assign custom_data_out[15:0] = agnus_data_out[15:0]
							 | paula_data_out[15:0]
							 | denise_data_out[15:0]
							 | user_data_out[15:0];

//--------------------------------------------------------------------------------------

assign _cpu_reset = _rst;

reg _rst;
always @(posedge clk) begin
	reg r;
	r <= ~(cpurst || sys_reset);
	_rst <= r;
end

//--------------------------------------------------------------------------------------

// minimig reset status
assign rst_out = reset;


endmodule

