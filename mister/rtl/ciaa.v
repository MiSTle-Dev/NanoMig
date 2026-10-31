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
// along with this program.  If not, see <http:// www.gnu.org/licenses/>.
//
//
//
// These are the cia's
// Note that these are simplified implementation of both CIA's, just enough
// to get Minimig going
// NOT implemented is:
// serial data register for CIA B(but keyboard input for CIA A is supported)
// port B for CIA A
// counter inputs for timer A and B other then 'E' clock
// toggling of PB6/PB7 by timer A/B
//
// 30-03-2005  -started coding
//         -intterupt description finished
// 03-04-2005  -added timers A,B and D
// 05-04-2005  -simplified state machine of timerab
//         -improved timing of timer-reload of timerab
//         -cleaned up timer d
//         -moved intterupt part to seperate module
//         -created nice central address decoder
// 06-04-2005  -added I/O ports
//         -fixed small bug in timerab state machine
// 10-04-2005  -added clock synchronisation latch on input ports
//         -added rd (read) input to detect valid bus states
// 11-04-2005  -removed rd again due to change in address decoder
//         -better reset behaviour for timer D
// 17-04-2005  -even better reset behaviour for timer D and timers A and B
// 17-07-2005  -added pull-up simulation on I/O ports
// 21-12-2005  -added rd input
// 21-11-2006  -splitted in seperate ciaa and ciab
//         -added ps2 keyboard module to ciaa
// 22-11-2006  -added keyboard reset
// 05-12-2006  -added keyboard acknowledge
// 11-12-2006  -ciaa cleanup
// 27-12-2006  -ciab cleanup
// 01-01-2007  -osd_ctrl[] is now 4 bits/keys


// JB:
// 2008-03-25  - osd_ctrl[] is 6 bits/keys (Ctrl+Break and PrtScr keys added)
//         - verilog 2001 style declaration
// 2008-04-02  - separate Timer A and Timer B descriptions (they differ a little)
//         - one-shot mode of Timer A/B sets START bit in control register
//         - implemented Timer B counting mode of Timer A underflows
// 2008-04-25  - added transmit interrupt for serial port
// 2008-07-28  - scroll lock led as disk activity led
// 2008-12-29  - more sophisticated implementation of serial port transmit interrupt (fixes problem with keyboard in Citadel)
//         - fixed reloading of Timer A/B when writing THI in stop mode
// 2009-02-01  - osd_ctrl[] is 8 bit wide
// 2009-05-24  - clean-up & renaming
// 2009-06-12  - sdr returns written value
// 2009-06-17  - timer A&B reset to 0xFFFF
// 2009-07-09  - reading of port B of CIA A ($BFE101) returns all ones ($FF)
// 2009-12-28  - added serial port register to CIA B
// 2010-08-15  - added joystick emulation
//
// SB:
// 2011-04-02 - added ciaa port b (parallel) register to let Unreal game work and some trainer store data
// 2011-04-24 - fixed TOD read
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

// CIA A (Complex Interface Adapter A)
// MOS 8520 CIA implementation for Amiga computers
//
// CIA A handles:
// - Keyboard interface (serial port)
// - Mouse/Joystick port control
// - Disk drive control signals
// - Parallel port (Centronics printer interface)
// - Two 16-bit timers with various modes
// - Time-of-day clock with alarm
// - Interrupt generation and control
//
// Memory mapped at $BFE001-$BFEF01 (odd addresses only)

module ciaa
(
	input        clk,           // System clock
	input        clk7_en,       // 7MHz clock enable (positive edge)
	input        clk7n_en,      // 7MHz clock enable (negative edge)
	input        aen,           // Address enable (chip select)
	input        rd,            // Read enable
	input        wr,            // Write enable
	input        reset,         // System reset
	input  [3:0] rs,            // Register select (address bits)
	input  [7:0] data_in,       // CPU data bus input
	output [7:0] data_out,      // CPU data bus output
	input        tick,          // TOD tick input (50/60 Hz)
	input        eclk,          // E clock (system clock / 10)
	input        cnt_in,        // CNT pin input
	output       irq,           // Interrupt request to CPU

	// Port A connections (disk and game port control)
	input  [7:2] porta_in,      // Port A inputs
	output [3:0] porta_out,     // Port A outputs
	// Bit 0: /OVL - Overlay ROM control (output)
	// Bit 1: /LED - Power LED control (output)
	// Bit 2: /CHNG - Disk change signal (input)
	// Bit 3: /WPRO - Disk write protect (input)
	// Bit 4: /TK0 - Track 0 signal (input)
	// Bit 5: /RDY - Disk ready (input)
	// Bit 6: /FIR0 - Joystick/Mouse button (input)
	// Bit 7: /FIR1 - Joystick/Mouse button (input)

	// Port B - Parallel port data (Centronics printer interface)
	input  [7:0] portb_in,      // Port B inputs (not used in Amiga)

	// Keyboard interface signals
	input        kms_level,     // Keyboard/mouse serial data level
	input  [1:0] kbd_mouse_type, // 2 = keyboard data
	input  [7:0] kbd_mouse_data, // Keyboard scan code
	output       freeze,        // Action Replay freeze button
	input        hrtmon_en      // HRTMon debugger enable
);

// Internal signal declarations
wire [7:0] icr_out;         // Interrupt control register output
wire [7:0] tmra_out;        // Timer A data output
wire [7:0] tmrb_out;        // Timer B data output
wire [7:0] tmrd_out;        // Timer D (TOD) data output
wire [7:0] sdr_out;         // Serial data register output
reg  [7:0] pa_out;          // Port A data output
reg  [7:0] pb_out;          // Port B data output
wire [7:0] portb_out;       // Port B output (unused)
wire       alrm;            // TOD alarm interrupt
wire       ta;              // Timer A interrupt
wire       tb;              // Timer B interrupt
wire       tmra_ovf;        // Timer A underflow signal

wire       spmode;          // Serial port mode (0=input, 1=output)
wire       ser_tx_irq;      // Serial transmit complete interrupt
reg  [3:0] ser_tx_cnt;      // Serial transmit bit counter
reg        ser_tx_run;      // Serial transmission in progress

reg        tick_del;        // Delayed tick for edge detection

//----------------------------------------------------------------------------------
// Address decoder for CIA registers
//----------------------------------------------------------------------------------
wire  pra,prb,ddra,ddrb,cra,talo,tahi,crb,tblo,tbhi,tdlo,tdme,tdhi,icrs,sdr;
wire  enable;

assign enable = aen & (rd | wr);

// CIA A Register Map:
// $BFE001 - PRA   - Port A data
// $BFE101 - PRB   - Port B data (parallel port)
// $BFE201 - DDRA  - Port A direction (0=input, 1=output)
// $BFE301 - DDRB  - Port B direction
// $BFE401 - TALO  - Timer A low byte
// $BFE501 - TAHI  - Timer A high byte
// $BFE601 - TBLO  - Timer B low byte
// $BFE701 - TBHI  - Timer B high byte
// $BFE801 - TDLO  - TOD low byte (1/10 seconds)
// $BFE901 - TDME  - TOD middle byte (seconds)
// $BFEA01 - TDHI  - TOD high byte (minutes)
// $BFEC01 - SDR   - Serial data register (keyboard)
// $BFED01 - ICR   - Interrupt control register
// $BFEE01 - CRA   - Control register A
// $BFEF01 - CRB   - Control register B

assign  pra  = enable && rs==4'h0;
assign  prb  = enable && rs==4'h1;
assign  ddra = enable && rs==4'h2;
assign  ddrb = enable && rs==4'h3;
assign  talo = enable && rs==4'h4;
assign  tahi = enable && rs==4'h5;
assign  tblo = enable && rs==4'h6;
assign  tbhi = enable && rs==4'h7;
assign  tdlo = enable && rs==4'h8;
assign  tdme = enable && rs==4'h9;
assign  tdhi = enable && rs==4'hA;
assign  sdr  = enable && rs==4'hC;
assign  icrs = enable && rs==4'hD;
assign  cra  = enable && rs==4'hE;
assign  crb  = enable && rs==4'hF;

// Data output multiplexer - OR together all module outputs
assign data_out = icr_out | tmra_out | tmrb_out | tmrd_out | sdr_out | pb_out | pa_out;

//----------------------------------------------------------------------------------
// Keyboard Interface
//----------------------------------------------------------------------------------
reg        keystrobe;       // Keyboard data strobe
wire [7:0] keydat;         // Keyboard data (unused)
reg  [7:0] sdr_latch;      // Serial data register latch

reg    freeze_reg=0;       // Action Replay freeze signal
assign freeze = freeze_reg;

// Generate single-cycle keyboard strobe on data change
always @(posedge clk) begin
	reg kms_levelD;
	if (clk7n_en) begin
		kms_levelD <= kms_level;
		keystrobe <= (kms_level ^ kms_levelD) && (kbd_mouse_type == 2);
	end
end

// Serial Data Register (SDR)
// Keyboard sends data serially, one bit at a time
// Data arrives ROTATED RIGHT by one bit and INVERTED
always @(posedge clk) begin
	if (reset) begin
		sdr_latch[7:0] <= 0;
		freeze_reg <= 0;
	end
	else if (clk7_en) begin
		if (keystrobe) begin
			// Rotate and invert incoming keyboard data
			sdr_latch[7:0] <= ~{kbd_mouse_data[6:0],kbd_mouse_data[7]};
			// Check for freeze key (Help key, scan code $5F)
			if (hrtmon_en && (kbd_mouse_data == 8'h5f)) freeze_reg <= 1;
			else freeze_reg <= 0;
		end
		else if (wr & sdr) 
			sdr_latch[7:0] <= data_in[7:0];  // CPU write to SDR
	end
end

// SDR read
assign sdr_out = (!wr && sdr) ? sdr_latch[7:0] : 8'h00;

// Serial port transmission control (output mode)
// Used for keyboard handshake and other serial communication
always @(posedge clk)
  if (clk7_en) begin
    if (reset || !spmode)     // Reset or input mode
      ser_tx_run <= 0;
    else if (sdr && wr)       // Start transmission on SDR write
      ser_tx_run <= 1;
    else if (ser_tx_irq)      // Stop after last bit sent
      ser_tx_run <= 0;
  end

// Count transmitted bits using Timer A underflows as baud clock
always @(posedge clk)
  if (clk7_en) begin
    if (!ser_tx_run)
      ser_tx_cnt <= 4'd0;
    else if (tmra_ovf)        // Count on Timer A underflow
      ser_tx_cnt <= ser_tx_cnt + 4'd1;
  end

// Generate interrupt after 8 bits transmitted
assign ser_tx_irq = &ser_tx_cnt & tmra_ovf;

//----------------------------------------------------------------------------------
// Port A - Game port and disk control
//----------------------------------------------------------------------------------
reg [7:2] porta_in2;        // Synchronized input data
reg [3:0] regporta;         // Port A output register
reg [7:0] ddrporta;         // Port A direction register

// Synchronize external inputs
always @(posedge clk)
  if (clk7_en) begin
    porta_in2[7:2] <= porta_in[7:2];
  end

// Port A output register (only bits 7,6,1,0 are outputs)
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      regporta[3:0] <= 4'd0;
    else if (wr && pra)
      regporta[3:0] <= {data_in[7:6], data_in[1:0]};
  end

// Port A direction register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      ddrporta[7:0] <= 8'd0;  // All inputs by default
    else if (wr && ddra)
       ddrporta[7:0] <= data_in[7:0];
  end

// Port A read multiplexer
always @(*)
begin
  if (!wr && pra)
    pa_out[7:0] = {porta_in2[7:2],porta_out[1:0]};  // Mix inputs and outputs
  else if (!wr && ddra)
    pa_out[7:0] = ddrporta[7:0];                    // Read direction register
  else
    pa_out[7:0] = 8'h00;
end

// Port A outputs with pull-up simulation
// Original 8520 has internal pull-ups, so undriven pins read as 1
assign porta_out[3:0] = {(~ddrporta[7:6] | regporta[3:2]), (~ddrporta[1:0] | regporta[1:0])};

//----------------------------------------------------------------------------------
// Port B - Parallel port (simplified, mostly unused in Amiga)
//----------------------------------------------------------------------------------
reg [7:0] ddrportb;         // Port B direction register

// Port B direction register
always @(posedge clk)
  if (clk7_en) begin
    if (reset)
      ddrportb[7:0] <= 8'd0;
    else if (wr && ddrb)
      ddrportb[7:0] <= (data_in[7:0]);
  end

// Port B read multiplexer
always @(*)
begin
  if (!wr && prb)
    pb_out[7:0] = portb_in[7:0];    // Read port pins
  else if (!wr && ddrb)
    pb_out[7:0] = (ddrportb[7:0]);  // Read direction register
  else
    pb_out[7:0] = 8'h00;
end

// Delayed tick for edge detection
always @(posedge clk)
  if (clk7_en) begin
    tick_del <= tick;
  end

//----------------------------------------------------------------------------------
// Instantiate sub-modules
//----------------------------------------------------------------------------------

// Interrupt controller
cia_int cnt
(
  .clk(clk),
  .clk7_en(clk7_en),
  .wr(wr),
  .reset(reset),
  .icrs(icrs),
  .ta(ta),
  .tb(tb),
  .alrm(alrm),
  .flag(1'b0),                      // FLAG pin not used on CIA A
  .ser(keystrobe | ser_tx_irq),    // Keyboard or serial transmit interrupt
  .data_in(data_in),
  .data_out(icr_out),
  .irq(irq)
);

// Timer A - General purpose timer, serial port baud rate
cia_timera tmra
(
  .clk(clk),
  .clk7_en(clk7_en),
  .wr(wr),
  .reset(reset),
  .tlo(talo),
  .thi(tahi),
  .tcr(cra),
  .data_in(data_in),
  .data_out(tmra_out),
  .eclk(eclk),
  .cnt(cnt_in),
  .spmode(spmode),
  .tmra_ovf(tmra_ovf),
  .irq(ta)
);

// Timer B - General purpose timer, can cascade with Timer A
cia_timerb tmrb
(
  .clk(clk),
  .clk7_en(clk7_en),
  .wr(wr),
  .reset(reset),
  .tlo(tblo),
  .thi(tbhi),
  .tcr(crb),
  .data_in(data_in),
  .data_out(tmrb_out),
  .eclk(eclk),
  .cnt(cnt_in),
  .tmra_ovf(tmra_ovf),
  .irq(tb)
);

// Timer D - Time of Day clock with alarm
cia_timerd tmrd
(
  .clk(clk),
  .clk7_en(clk7_en),
  .wr(wr),
  .reset(reset),
  .tlo(tdlo),
  .tme(tdme),
  .thi(tdhi),
  .tcr(crb),
  .data_in(data_in),
  .data_out(tmrd_out),
  .count(tick & ~tick_del),  // Count on rising edge of tick
  .irq(alrm)
);


endmodule