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
// This is the floppy disk controller (part of Paula)
//
// 23-10-2005	-started coding
// 24-10-2005	-done lots of work
// 13-11-2005	-modified fifo to use block ram
//				-done lots of work
// 14-11-2005	-done more work
// 19-11-2005	-added wordsync logic
// 20-11-2005	-finished core floppy disk interface
//				-added disk interrupts
//				-added floppy control signal emulation
// 21-11-2005	-cleaned up code a bit
// 27-11-2005	-den and sden are now active low (_den and _sden)
//				-fixed bug in parallel/serial converter
//				-fixed more bugs
// 02-12-2005	-removed dma abort function
// 04-12-2005	-fixed bug in fifo empty signalling
// 09-12-2005	-fixed dsksync handling	
//				-added protection against stepping beyond track limits
// 10-12-2005	-fixed some more bugs
// 11-12-2005	-added dout output enable to allow SPI bus multiplexing
// 12-12-2005	-fixed major bug, due error in statemachine, multiple interrupts were requested
//				 after a DMA transfer, this could lock up the whole machine
// 				-enable line disconnected  --> this module still needs a lot of work
// 27-12-2005	-cleaned up code, this is it for now
// 07-01-2005	-added dmas
// 15-01-2006	-added support for track 80-127 (used for loading kickstart)
// 22-01-2006	-removed support for track 80-127 again
// 06-02-2006	-added user disk control input
// 28-12-2006	-spi data out is now low when not addressed to allow multiplexing with multiple spi devices		
//
// JB:
// 2008-07-17	- modified floppy interface for better read handling and write support
//				- spi interface clocked by SPI clock
// 2008-09-24	- incompatibility found: _READY signal should respond to _SELx even when the motor is off
//				- added logic for four floppy drives
// 2008-10-07	- ide command request implementation
// 2008-10-28	- further hdd implementation
// 2009-04-05	- code clean-up
// 2009-05-24	- clean-up & renaming
// 2009-07-21	- WORDEQUAL in DSKBYTR register is always set now
// 2009-11-14 - changed DSKSYNC reset value (Kick 1.3 doesn't initialize this register after reset)
//        - reduced FIFO size (to save some block rams)
// 2009-12-26 - step enable
// 2010-04-12 - implemented work-around for dsksync interrupt request
// 2010-08-14 - set BYTEREADY of DSKBYTR (required by Kick Off 2 loader)
// 2023-2026 - added support for external floppy drives with copy protection (improved DSKBYTR register)

module paula_floppy
(
	// system bus interface
	input         clk,		    	// bus clock
	input         clk7_en,
	input         clk7n_en,
	input         reset,			   // reset 
	input         ntsc,         	// ntsc mode
	input         sof,          	// start of frame
	input	        enable,			// dma enable
	input   [8:1] reg_address_in,	// register address inputs
	input  [15:0] data_in,			// bus data in
	output [15:0] data_out,			// bus data out
	output        dmal,				// dma request output
	output        dmas,				// dma special output

	//disk control signals from cia and user
	input	        _step,				// step heads of disk
	input	        direc,				// step heads direction
	input   [3:0] _sel,				// disk select 	
	input	        side,				// upper/lower disk head
	input	        _motor,			// disk motor control
	output        _track0,			// track zero detect
	output        _change,			// disk has been removed from drive
	output        _ready,			// disk is ready
	output        _wprot,			// disk is write-protected
	output        index,          // disk index pulse

	//interrupt request and misc. control
	output reg    blckint,			// disk dma has finished interrupt
	output        syncint,			// disk syncword found
	input         wordsync,			// wordsync enable

	//HPS I/O interface
	input         IO_ENA,
	input         IO_STROBE,
	output reg    IO_WAIT,
	input  [15:0] IO_DIN,
	output reg [15:0] IO_DOUT,

	output        fdd_led,			//disk activity LED, active when DMA is on
	input	[1:0]   floppy_drives,	//floppy drive number
	input         floppy_zero_active,
	input [11:0]  floppy_ext_drive,   // external drive number to use AAABBBCCCDDD
	input floppy_speed_allowed,
	output floppy_speed,
	input enable_mister_floppy,
	
	// fifo / track display
	output  [7:0] trackdisp,
	output [13:0] secdisp,
	output        floppy_fwr,
	output        floppy_frd,
	
	input   [1:0] precomp,

	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,
	
	output	[2:0]  mister_floppy_status,  // bit 0=Detected, Bit1= running in IBM Drive mode (compared to Shuggart), Bit2=Swapped Cable

	output reg [8:0] drive_snd
);



//register names and addresses
parameter DSKBYTR = 9'h01a;
parameter DSKDAT  = 9'h026;		
parameter DSKDATR = 9'h008;
parameter DSKSYNC = 9'h07e;
parameter DSKLEN  = 9'h024;

//local signals
reg  [15:0] dsksync;			//disk sync register
reg  [15:0] dsklen;			//disk dma length, direction and enable 
reg   [6:0] dsktrack[3:0];	//track select
wire  [7:0] track;

reg         dmaon;			//disk dma read/write enabled
wire        lenzero;			//disk length counter is zero
reg         trackwr;			//write track (command to host)
reg         trackrd;			//read track (command to host)

wire        _dsktrack0;		//disk heads are over track 0
wire        dsktrack79;    //disk heads are over track 0

wire [15:0] fifo_in;			//fifo data in
wire [15:0] fifo_out; 		//fifo data out
wire [15:0] flux_fifo_in; //fifo data in
wire [15:0] flux_fifo_out; //fifo data out

wire 			output_fifo_write;  // Combined special version when virtual floppy is enabled
reg         fifo_wr_del;	//fifo write enable delayed
wire        fifo_empty;		//fifo is empty
wire        fifo_full;		//fifo is full
wire [11:0] fifo_cnt;

wire [15:0] dskbytr;			
wire [15:0] dskdatr;

// JB:
wire        fifo_reset;
reg         dmaen;			//dsklen dma enable
reg  [15:0] wr_fifo_status;

reg   [3:0] disk_present;	//disk present status
reg   [3:0] disk_writable;	//disk write access status
reg   [3:0] disk_fluxmode; // disk data isn't MFM, its raw flux, encoded at 50ns resolution. 0=INDEX, 255=12.7uS/254, 2 Flux per WORD. 
reg   [3:0] disk_fluxdensitymode; // disk data is MFM + speed for those 8 bits (similar to IPF format and a bit like how Winuae works)

wire        _selx;			//active whenever any drive is selected
wire  [1:0] sel;				//selected drive number

reg   [1:0] drives;			//number of currently connected floppy drives (1-4)

reg   [3:0] _disk_change;
reg         _step_del;
reg   [8:0] step_ena_cnt;
wire        step_ena;

// drive motor control
reg  [3:0] _sel_del;       // deleyed drive select signals for edge detection
reg  [3:0] motor_on;       // drive motor on

wire _ready_ext;				// RDY signal from external drive
wire _track0_ext;				// TRK0 signal from external drive
wire _wprot_ext;				// WRPROT signal from external drive
wire _change_ext;				// DSKCHG signal from external drive
wire _index_ext;				// raw INDEX from external drive (needs processing)

wire [15:0] ext_floppy_rx;				// Receive WORD FROM floppy drive
wire        ext_floppy_wr;				// When set to 1 indicates a valid WORD is available at ext_floppy_rx
wire        ext_floppy_rd;				// Set to 1 to indicate a WORD was READ from the fifo
wire			ext_floppy_rd_del;      // Delay of the above to ensure last WORD is written
wire        ext_floppy_sync;			// If daya should be sync'ed to the current word sync
wire [15:0] ext_floppy_syncword;		// The Word Match Sync currently active (eg: 4489)


//active drive number (priority encoder)
assign sel = !_sel[0] ? 2'd0 : !_sel[1] ? 2'd1 : !_sel[2] ? 2'd2 : !_sel[3] ? 2'd3 : 2'd0;

// floppy_ext_drive
wire [3:0] _exsel;								// Selection status of external drives only (low is selected)
wire     virtualFloppyMode;			 // Set to 1 means we're emulating a floppy drive at flux level
wire     sel_external;			    // Set to 1 if a real drive is selected
wire     flux_inuse;				    // Means the PLL is in use (real drive or flux data)

reg [3:0] exsel_map[0:3];
reg [3:0] exsel_any;
always @(posedge clk) begin : exsel_decode
	integer k, i;
	reg [3:0] taken, first, any;
	any = 4'b0000;
	for (k = 0; k < 4; k = k + 1) begin
		taken = 4'b0000;
		for (i = 0; i < 4; i = i + 1) begin
			first[i] = (floppy_ext_drive[3*i +: 3] == k + 1) & ~|taken;
			taken[i] = (floppy_ext_drive[3*i +: 3] == k + 1);
		end
		exsel_map[k] <= first;
		any = any | first;
	end
	exsel_any <= enable_mister_floppy ? any : 4'b0000;
end

assign _exsel[0] = &(~exsel_map[0] | _sel);
assign _exsel[1] = &(~exsel_map[1] | _sel);
assign _exsel[2] = &(~exsel_map[2] | _sel);
assign _exsel[3] = &(~exsel_map[3] | _sel);

assign sel_external    = |(exsel_any & ~_sel);
assign flux_inuse      = sel_external | ((disk_fluxmode[sel]|disk_fluxdensitymode[sel]) & ~_selx);
assign virtualFloppyMode = (disk_fluxmode[sel]|disk_fluxdensitymode[sel]) & ~sel_external & ~_selx;
assign floppy_speed   = (reset | ~flux_inuse) ? floppy_speed_allowed : 1'b0;

wire _virtReadData;
wire virtualFluxDataRead;
wire _virtualFluxIndex;
wire _virtualFluxDataReady;
wire virtualFloppyRequestsData;

// A virtual floppy drive, used for FLUX data, NOT mfm. The large FIFO buffer is used to store flux instead
MiSTerFloppyVirtualFluxDrive virtualFloppy (
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(reset),
	
	.enabled(virtualFloppyMode),
	.drivesSelect( disk_fluxmode & ~_sel),   // note its NOT inverted
	.densityMode(disk_fluxdensitymode),
	.driveSelected( sel),							// Index of selected drive
	.nMotorEnabled(_motor),
	.o_nReady(_virtualFluxDataReady),
	.floppyBit(_virtReadData),
	.oRequestData(virtualFloppyRequestsData),
	
	.fifo_empty(fifo_empty),
	.fifo_reset(paula_fifo_reset),
	.fluxDataIn(fifo_out[15:0]),             // Flux data received from the core FIFO
	.fluxDataRead(virtualFluxDataRead),
	._Index(_virtualFluxIndex)
);


// Special signals used by the DSKBYTR register
wire diskByteReady;						// A signal (1) that a new BYTE is available at diskByte
wire[7:0] diskByte;						// The last BYTE read in from the disk
reg resetDiskByteReady = 1'b0;		// Set to 1 to reset the diskByteReady status
wire syncWordNOW;						   // Set to 1 if the DISKSYNC is actually valid literally right now!
wire bitdetected;							//
wire _dskrd;								// Flux data OUT from real floppy drive
wire interfaceBusy;
wire _dkwd;
wire _dkwe;


MiSTerFloppyPLL PaulaFloppyPLL (
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(reset),
	.trackrd(trackrd | _virtualFluxDataReady),
	.selected(flux_inuse & ~trackwr),
	.trackwr(trackwr & flux_inuse & ~virtualFloppyMode),
	.precomp(precomp),	
	.fifo_empty(flux_fifo_empty),
	
	.ext_floppy_rx(ext_floppy_rx),              // Received FROM disk
	.ext_floppy_wr(ext_floppy_wr),				  // 1 when above WORD is valid
	
	.ext_floppy_tx(flux_fifo_out),              // to be written TO disk
	.ext_floppy_rd(ext_floppy_rd),				  // Signals the above word was written
	.ext_floppy_rd_del(ext_floppy_rd_del),		  // Delay version of the above
	
	.ext_floppy_sync(ext_floppy_sync),
	.ext_floppy_syncword(dsksync),
	
	.wordsyncEnabled(wordsync),
	.syncWordNOW(syncWordNOW),
	
	.bitdetected(bitdetected),
	
	.diskByte(diskByte),
	.diskByteReady(diskByteReady),
	.resetDiskByteReady(resetDiskByteReady),	
	
	._dskrd(virtualFloppyMode ? _virtReadData : _dskrd), // Actual status of "live" MFM bitstream 
	.pause(interfaceBusy & ~virtualFloppyMode),									// Set to 1 to 'pause' any actions. 
	._writeData(_dkwd),										// Output MFM writing (WRITE_DATA)
	._writeGate(_dkwe) 			// Output ENABLE (WRITE_GATE)
);

// NTSC Amigas had 28.63636 clock whereas PAL Amigas had 28.37516Mhz clocks
// The Minimig core is actually set to 28.687500MHz - not sure why!
MiSTerFloppySHUGART #(28687500, 1) db(
	.i_core_cpu_clk(clk),
	.USER_IN(USER_IN),
	.USER_OUT(USER_OUT),	
	
	.o_queueBusy(interfaceBusy),
	
	.i_nWriteData(_dkwd),
	.i_nWriteGate(_dkwe),
	.i_nHeadSelect(side),
	
	.o_nReadData(_dskrd),
	.o_nIndex(_index_ext),
	.o_nTrk00(_track0_ext),
	.o_nWriteProtected(_wprot_ext),
	.o_nDiskChange(_change_ext),
	.o_nReady(_ready_ext),	
	
	.i_nDriveSelect0(_exsel[0]),
	.i_nDriveSelect1(_exsel[1]),
	.i_nDriveSelect2(_exsel[2]),
	.i_nDriveSelect3(_exsel[3]),
	.i_nMotorEnable(_motor),	
	.i_nDir(direc),
	.i_nStep(_step),	
	.i_reset(reset | ~enable_mister_floppy),
	.o_detected(mister_floppy_status[0]),
	.o_PinIBMDrive(mister_floppy_status[1]),
	.o_nSwappedCable(mister_floppy_status[2])
);


//decoded commands
reg        cmd_fdd;			//HPS accesses floppy drive buffer

assign     trackdisp = track;
assign     secdisp = dsklen[13:0];

assign     floppy_fwr = paula_fifo_wr;
assign     floppy_frd = paula_fifo_rd;

reg  [1:0] cmd_cnt;

reg stb7;
always @(posedge clk or negedge IO_ENA) begin
	if(~IO_ENA) {IO_WAIT,stb7} <= 0;
	else begin
		if(IO_STROBE) begin
			IO_WAIT <= 1;
		end
		if(clk7_en & IO_WAIT) begin
			if(~stb7) begin
				rx_data <=IO_DIN;
				stb7    <=1;
			end
			if(stb7) begin
				stb7    <=0;
				IO_WAIT <=0;
				IO_DOUT <=tx_data;
			end
		end
	end
end

reg [15:0] rx_data;	//received data from HPS
reg [15:0] tx_data;	//data to be send to HPS

always @(posedge clk or negedge IO_ENA) begin
	if (~IO_ENA) cmd_cnt <= 0;
	else if (clk7_en & stb7 & ~&cmd_cnt) cmd_cnt <= cmd_cnt + 1'd1;
end

//---------------------------------------------------------------------------------------------------------------------

always @(posedge clk) begin
	if (clk7_en) begin
		if (reset | ~IO_ENA)       cmd_fdd <= 0;
		else if (stb7 && !cmd_cnt) cmd_fdd <= (rx_data[15:13]==3'b000 );
	end
end



// Virtual floppy head settling timer (~12ms at clk7_en rate)
// When the head moves, according to Commodore spec, upto 15ms of head settling time is allowed. We use this to prevent the core streaming data to us when not needed during step operations
reg [16:0] vfloppy_settle_cnt;
wire vfloppy_settling = virtualFloppyMode & (vfloppy_settle_cnt != 17'd0);
always @(posedge clk) begin
    if (clk7_en) begin
        if (virtualFloppyMode && _step && !_step_del)
            vfloppy_settle_cnt <= 17'd107550;     // 15ms
        else if (vfloppy_settle_cnt != 15'd0)
            vfloppy_settle_cnt <= vfloppy_settle_cnt - 17'd1;
    end
end

wire hostRead = sel_external ? 1'b0 : (((trackrd | virtualFloppyRequestsData) & ~vfloppy_settling) & ~fifo_cnt[10]);

//transmit data multiplexer
always @(*) begin
	casex ({cmd_cnt, cmd_fdd, hostRead,  sel_external ? 1'b0 : trackwr })
		
		// fdd request status - To simulate a virtual drive properly, while its 'READY' it needs to be constantly outputting data, it just doesnt get written
		'b00xxx: tx_data = {sel[1:0], drives[1:0], 1'b1, floppy_zero_active, sel_external ? 1'b0 : trackwr, hostRead, track[7:0]};

		// fdd data
		'b01xxx: tx_data = dsksync[15:0];
		'b10x1x: tx_data = {dmaen,dsklen[14:0]};
		'b10x01: tx_data = wr_fifo_status;
		'b1111x: tx_data = {dmaen,dsklen[14:0]};
		'b11101: tx_data = fifo_out;
		
		// no data
		 default: tx_data = 0;
	endcase
end

//floppy disk write fifo status is latched when transmision of the previous word begins 
//it guarantees that when latching the status data into transmit register setup and hold times are met
always @(posedge clk) begin
  if (clk7_en) begin
  	if (stb7)
  		wr_fifo_status <= {dmaen&dsklen[14],3'b000,fifo_cnt[11:0]};
  end
end

//-----------------------------------------------------------------------------------------------//
//active floppy drive number, updated during reset
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		drives <= floppy_drives;
  end
end

//-----------------------------------------------------------------------------------------------//

// External index needs converting to a single pulse, not the long pulse from the drive
reg last_ext_index;
reg index_ext_pulse;
wire _externalIndex;
assign _externalIndex = virtualFloppyMode ? _virtualFluxIndex : _index_ext;

// 300 RPM floppy disk rotation signal
reg [3:0] rpm_pulse_cnt;
always @(posedge clk) begin
  if (clk7_en) begin
	 // Looking for falling edge 
	 last_ext_index <= _externalIndex;
	 index_ext_pulse <= ~_externalIndex && last_ext_index;  

    if (sof) begin
      if (rpm_pulse_cnt==11 || !ntsc && rpm_pulse_cnt==9)
        rpm_pulse_cnt <= 0;
      else
        rpm_pulse_cnt <= rpm_pulse_cnt + 4'd1;
    end
  end
end

    
// disk index pulses output
wire index_adf;
assign index_adf = |(~_sel & motor_on) & ~|rpm_pulse_cnt & sof;
assign index = flux_inuse ? index_ext_pulse : index_adf;

//--------------------------------------------------------------------------------------
//data out multiplexer
assign data_out = dskbytr | dskdatr;

//--------------------------------------------------------------------------------------

//active whenever any drive is selected
assign _selx = &_sel[3:0];

// delayed step signal for detection of its rising edge 
always @(posedge clk) begin
  if (clk7_en) begin
    _step_del <= _step;	 
  end
end

always @(posedge clk) begin
  if (clk7_en) begin
    if (!step_ena)
      step_ena_cnt <= step_ena_cnt + 9'd1;
    else if (_step && !_step_del)
      step_ena_cnt <= 0;
  end
end

assign step_ena = step_ena_cnt[8];

// disk change latch
// set by reset or when the disk is removed form the drive
// reset when the disk is present and step pulse is received for selected drive
always @(posedge clk) begin
  if (clk7_en) begin
    _disk_change <= (_disk_change | ~_sel & {4{_step}} & ~{4{_step_del}} & disk_present) & ~({4{reset}} | ~disk_present);
  end
end
 
//delayed drive select signals
always @(posedge clk) begin
  if (clk7_en) begin
    _sel_del <= _sel;
  end
end

//drive motor control
always @(posedge clk) begin
  if (clk7_en) begin
    if (reset)
      motor_on[0] <= 0;
    else if (!_sel[0] && _sel_del[0])
      motor_on[0] <= ~_motor;
  end
end

always @(posedge clk) begin
  if (clk7_en) begin
    if (reset)
      motor_on[1] <= 0;
    else if (!_sel[1] && _sel_del[1])
      motor_on[1] <= ~_motor;
  end
end

always @(posedge clk) begin
  if (clk7_en) begin
    if (reset)
      motor_on[2] <= 0;
    else if (!_sel[2] && _sel_del[2])
      motor_on[2] <= ~_motor;
  end
end

always @(posedge clk) begin
  if (clk7_en) begin
    if (reset)
      motor_on[3] <= 0;
    else if (!_sel[3] && _sel_del[3])
      motor_on[3] <= ~_motor;
  end
end

wire _change_adf, _wprot_adf, _track0_adf; //original ADF emulation signals
//_ready,_track0 and _change signals
assign _change_adf = &(_sel | _disk_change);
assign _wprot_adf = &(_sel | disk_writable);
assign  _track0_adf =&(_selx | _dsktrack0);

assign _change = (flux_inuse & ~virtualFloppyMode) ? _change_ext : _change_adf;
assign _wprot =  virtualFloppyMode ? 1'b0 : (flux_inuse ? _wprot_ext : _wprot_adf);   // Virtual floppy is read only
assign _track0 = (flux_inuse & ~virtualFloppyMode) ? _track0_ext : _track0_adf;

//track control
assign track = {dsktrack[sel],~side};

always @(posedge clk) begin
  if (clk7_en) begin
    if (!_selx && _step && !_step_del && step_ena) begin // track increment (direc=0) or decrement (direc=1) at rising edge of _step
      if (!dsktrack79 && !direc)
        dsktrack[sel] <= dsktrack[sel] + 7'd1;
      else if (_dsktrack0 && direc)
        dsktrack[sel] <= dsktrack[sel] - 7'd1;	
    end
  end
end

wire [3:0] drive_emu = {drives == 2'd3, drives[1], |drives, 1'b1} & ~exsel_any & {4{~floppy_zero_active}};
always @(posedge clk) begin
  drive_snd[8:1] <= {reset, disk_present & drive_emu, |(motor_on[3:1] & drive_emu[3:1]), motor_on[0] & drive_emu[0], |sel};
  drive_snd[0]   <= clk7_en & !_selx & _step & !_step_del & step_ena & (!direc | _dsktrack0) & drive_emu[sel];
end

// _dsktrack0 detect
assign _dsktrack0 = ~(dsktrack[sel]==0);

// dsktrack79 detect
assign dsktrack79 = dsktrack[sel]==82;

// drive _ready signal control
// Amiga DD drive activates _ready whenever _sel is active and motor is off
// or whenever _sel is active, motor is on and there is a disk inserted (not implemented - _ready is active when _sel is active)
wire _ready_adf;
assign _ready_adf   = (_sel[3] | ~(drives[1] & drives[0])) 
         & (_sel[2] | ~drives[1]) 
         & (_sel[1] | ~(drives[1] | drives[0])) 
         & (_sel[0]);
assign _ready = flux_inuse ? (virtualFloppyMode ? _virtualFluxDataReady : _ready_ext) : _ready_adf;

//--------------------------------------------------------------------------------------

// For real disks this register is now more accurate, supports DSKBYT and associated bit properly
assign dskbytr = (reg_address_in[8:1]==DSKBYTR[8:1]) ? {
	flux_inuse ? diskByteReady : 1'b1,
	(trackrd|trackwr),
	dsklen[14],
	flux_inuse ? syncWordNOW : 1'b1,
	4'b0000,
	flux_inuse ? diskByte : 8'h00
} : 16'h00_00;

//disk data byte and status read
always @(posedge clk) begin
    if (clk7_en) begin	  
		if (reg_address_in[8:1]==DSKBYTR[8:1]) begin			
			if (diskByteReady) begin
				resetDiskByteReady <= 1;				
			end
		end else
		begin
			resetDiskByteReady <= 0;	
		end
  end
end

//disk sync register
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset) 
  		dsksync[15:0] <= 16'h4489;
  	else if (reg_address_in[8:1]==DSKSYNC[8:1])
  		dsksync[15:0] <= data_in[15:0];
  end
end

//disk length register
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		dsklen[14:0] <= 0;
  	else if (reg_address_in[8:1]==DSKLEN[8:1])
  		dsklen[14:0] <= data_in[14:0];
  	else if (output_fifo_write) //decrement length register
  		dsklen[13:0] <= dsklen[13:0] - 14'd1;
  end
end

//disk length register DMAEN
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		dsklen[15] <= 0;
  	else if (blckint)
  		dsklen[15] <= 0;
  	else if (reg_address_in[8:1]==DSKLEN[8:1])
  		dsklen[15] <= data_in[15];
  end
end

//dmaen - disk dma enable signal
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		dmaen <= 0;
  	else if (blckint)
  		dmaen <= 0;
  	else if (reg_address_in[8:1]==DSKLEN[8:1])
  		dmaen <= data_in[15] & dsklen[15];//start disk dma if second write in a row with dsklen[15] set
  end
end

//dsklen zero detect
assign lenzero = (dsklen[13:0]==0);


// This generates fake data when no disk is selected to ensure DMA completes when NO drive is selected
reg [7:0] no_sel_ctr;
wire no_sel_word_clk = (no_sel_ctr == 8'd223);
always @(posedge clk) begin
    if (clk7_en) begin
        if (_selx & trackrd & dmaon) begin
            if (no_sel_word_clk)
                no_sel_ctr <= 8'd0;
            else
                no_sel_ctr <= no_sel_ctr + 8'd1;
        end else
            no_sel_ctr <= 8'd0;
    end
end



//--------------------------------------------------------------------------------------
//disk data read path
wire	busrd;				//bus read
wire	buswr;				//bus write
reg	trackrdok;			//track read enable


//disk buffer bus read address decode
assign busrd = (reg_address_in[8:1]==DSKDATR[8:1]);

//disk buffer bus write address decode
assign buswr = (reg_address_in[8:1]==DSKDAT[8:1]);

//data word transfer strobe
wire stbdat = cmd_fdd && stb7 && &cmd_cnt;


// fifo data input multiplexer  (rx_data=from mister, data_in=from bus)
assign fifo_in[15:0] = _selx ? 16'h0000 : ((trackrd|virtualFloppyMode) ? rx_data[15:0] : data_in[15:0]);
assign flux_fifo_in[15:0] = trackrd ? ext_floppy_rx[15:0] : data_in[15:0];

wire paula_fifo_wr;
assign paula_fifo_wr = virtualFloppyMode ? stbdat : 
                       (flux_inuse ? 1'b0 :
                       (_selx & trackrdok & no_sel_word_clk & ~lenzero) |   // this makes DMA complete properly if it was triggered and nothing is selected
                       (trackrdok & stbdat & ~lenzero) | 
                       (buswr & dmaon));

//fifo read control (read a WORD FROM the FIFO)
wire paula_fifo_rd;
assign paula_fifo_rd = virtualFloppyMode ? virtualFluxDataRead : (flux_inuse ? 1'b0 : (busrd & dmaon) | (trackwr & stbdat));								 

// FLUX - the small fifo is only used for reading, not writing
wire flux_fifo_wr   = flux_inuse ? (trackrdok & ext_floppy_wr & ~lenzero) | (buswr & dmaon) : 1'b0;   // write into
wire flux_fifo_rd   = flux_inuse ? (busrd & dmaon) | ext_floppy_rd : 1'b0;             					// read back out


// This is used to decrement the dma length left
wire selected_fifo_empty;
wire selected_fifo_full;
reg  flux_inuse_dma;
always @(posedge clk) flux_inuse_dma <= flux_inuse;
assign selected_fifo_empty = flux_inuse_dma ? flux_fifo_empty : fifo_empty;
assign selected_fifo_full =  flux_inuse_dma ? flux_fifo_full : fifo_full;
assign output_fifo_write = flux_inuse ? flux_fifo_wr : paula_fifo_wr;

// OK: disk data read output gate
assign dskdatr[15:0] = busrd ? (flux_inuse ? flux_fifo_out[15:0] : fifo_out[15:0]) : 16'h00_00;		
		
reg virtualFloppyFifoReset;
reg [3:0] _virtualFloppyFifoResetLastSel;
reg lastVirtualFloppyMode;
		
always @(posedge clk) begin
	if (clk7_en) begin
		_virtualFloppyFifoResetLastSel <= _sel;
		lastVirtualFloppyMode <= virtualFloppyMode;		
		virtualFloppyFifoReset = (((_virtualFloppyFifoResetLastSel != _sel) && (virtualFloppyMode | lastVirtualFloppyMode))) | (_step && !_step_del);
	end
end
		

wire flux_fifo_reset;
assign flux_fifo_reset = reset | ~dmaen;
wire paula_fifo_reset;
assign paula_fifo_reset = reset | (~dmaen & ~virtualFloppyMode) | virtualFloppyFifoReset;
	

// delayed version to allow writing of the last word to empty fifo (While true holds back DMA blckint)
always @(posedge clk) begin
  if (clk7_en) begin
  	fifo_wr_del <= output_fifo_write;
  end
end



//DSKSYNC interrupt
wire sync_match;
assign sync_match = dsksync[15:0]==rx_data[15:0] && stbdat && trackrd;

wire syncint_adf;
assign syncint_adf = sync_match | ~dmaen & |(~_sel & motor_on & disk_present) & sof;
assign syncint = flux_inuse ? (~dmaen & ext_floppy_sync) : syncint_adf;

//track read enable / wait for syncword logic
always @(posedge clk) begin
  if (clk7_en) begin
  	if (!trackrd)//reset
  		trackrdok <= 0;
  	else//wordsync is enabled, wait with reading until syncword is found
  		trackrdok <= ~wordsync | (flux_inuse ? ext_floppy_sync : sync_match) | trackrdok;
  end
end


//disk fifo / trackbuffer
paula_floppy_fifo db1
(
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(paula_fifo_reset),
	.in(fifo_in),
	.out(fifo_out),	
	.rd(paula_fifo_rd & ~fifo_empty),
	.wr(paula_fifo_wr & ~fifo_full),
	.empty(fifo_empty),
	.full(fifo_full),
	.cnt(fifo_cnt)
);


wire flux_fifo_full;
wire flux_fifo_empty;

// Small fifo for the flux based stuff
MiSTerFloppyFifo fluxfifo 
(
	.clk(clk),
	.clk7_en(clk7_en),
	.reset(flux_fifo_reset),
	.in(flux_fifo_in[15:0]),   
	.out(flux_fifo_out),	
	.rd(flux_fifo_rd & ~flux_fifo_empty),
	.wr(flux_fifo_wr & ~flux_fifo_full),
	.empty(flux_fifo_empty),
	.full(flux_fifo_full)
);


//--------------------------------------------------------------------------------------


//dma request logic
assign dmal = dmaon & (~dsklen[14] & ~selected_fifo_empty | dsklen[14] & ~selected_fifo_full);

//dmas is active during writes
assign dmas = dmaon & dsklen[14] & ~selected_fifo_full;

//--------------------------------------------------------------------------------------
//main disk controller
reg		[1:0] dskstate;		//current state of disk
reg		[1:0] nextstate; 	//next state of state

//disk states
parameter DISKDMA_IDLE   = 2'b00;
parameter DISKDMA_ACTIVE = 2'b10;
parameter DISKDMA_INT    = 2'b11;

//disk present and write protect status
always @(posedge clk) begin
  if (clk7_en) begin
  	if(reset)
  		{disk_fluxdensitymode[3:0], disk_fluxmode[3:0], disk_writable[3:0],disk_present[3:0]} <= 16'b0000_0000_0000_0000;
  	else if (rx_data[15:12]==4'b0001 && stb7 && !cmd_cnt)
		{disk_fluxmode[3:0], disk_writable[3:0],disk_present[3:0]} <= rx_data[11:0];		
	else if (rx_data[15:12]==4'b0010 && stb7 && !cmd_cnt)
		{disk_fluxdensitymode[3:0]} <= rx_data[3:0];		
  end
end

//disk activity LED
assign fdd_led =  (dskstate!=DISKDMA_IDLE);

//main disk state machine
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		dskstate <= DISKDMA_IDLE;		
  	else
  		dskstate <= nextstate;
  end
end




wire fifo_wr_delay;
assign fifo_wr_delay = flux_inuse ? ext_floppy_rd_del : fifo_wr_del;

always @(*) begin
	case(dskstate)
		DISKDMA_IDLE://disk is present in flash drive
		begin
			trackrd = 0;
			trackwr = 0;
			dmaon = 0;
			blckint = 0;
			// This shouldnt check lenzero. Its valid to start DMA with lenzero, and is done with some variants of Rob Northen Copylock. Without this, the check fails.
			if (((cmd_fdd && stb7 && cmd_cnt==1) || (flux_inuse)) && dmaen && enable)			
			//if (((cmd_fdd && stb7 && cmd_cnt==1) || (flux_inuse)) && dmaen && (!lenzero || flux_inuse) && enable)
				nextstate = DISKDMA_ACTIVE; 
			else
				nextstate = DISKDMA_IDLE;			
		end
		DISKDMA_ACTIVE://do disk dma operation
		begin
			trackrd = ~lenzero & ~dsklen[14]; // track read (disk->ram)
			trackwr = dsklen[14]; // track write (ram->disk)
			dmaon = ~lenzero | ~dsklen[14];
			blckint=0;
			if (!dmaen || !enable)
				nextstate = DISKDMA_IDLE;
			else if (lenzero && selected_fifo_empty && !fifo_wr_delay) //complete dma cycle done
				nextstate = DISKDMA_INT;
			else
				nextstate = DISKDMA_ACTIVE;			
		end
		DISKDMA_INT://generate disk dma completed (DSKBLK) interrupt
		begin
			trackrd = 0;
			trackwr = 0;
			dmaon = 0;
			blckint = 1;
			nextstate = DISKDMA_IDLE;			
		end
		default://we should never come here
		begin
			trackrd = 1'bx;
			trackwr = 1'bx;
			dmaon = 1'bx;
			blckint = 1'bx;
			nextstate = DISKDMA_IDLE;			
		end
	endcase
end


endmodule

