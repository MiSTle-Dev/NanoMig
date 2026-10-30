//////////////////////////////////////////////////////////////////////////////
// MiSTer Floppy                                                            //
// Copyright (C) RobSmithDev 2022-2026                                      //
// https://mister.robsmithdev.co.uk                                         //
//////////////////////////////////////////////////////////////////////////////
//
// This module provides an SHUGART compatiable interface to the the MiSTer Floppy board
// This module will automatically convert internally the signals
// depending on what type of drive is actually connected.
//
// Notes: The 'Amiga Mode' Flag enables a drive motor latch for drive 0, (and Drive A/B in IBM mode) motor
//			 In 'Amiga Mode' with Shuart Drives selected, drive 1, 2 and 3 motor signals are sent out via the MTR123 pin for external drives

module MiSTerFloppySHUGART(
	input i_core_cpu_clk,
	
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,	
	
	output	o_queueBusy,		     // Set when a different drive has been selected and the port expander hasn't finished updated yet
	
	input i_nWriteData,
	input i_nWriteGate,
	input i_nHeadSelect,
	output o_nReadData,
	output o_nIndex,
	
	output o_nTrk00,
	output o_nWriteProtected,
	output o_nDiskChange,
	output o_nReady,
	
	input i_nDriveSelect0,       // Selected when set to 0, hence the 'n'
	input i_nDriveSelect1,
	input i_nDriveSelect2,
	input i_nDriveSelect3,
	
	input i_nMotorEnable,  
	
	input i_nDir,
	input i_nStep,
	
	input i_reset,
	
	output o_detected,
	output o_PinIBMDrive,
	output o_nSwappedCable
);

parameter CLK_Freq = 50_000_000;	//	50 MHz
parameter AmigaMode = 0;		// Set to 1 if using on Minimig etc

wire o_nPin34;
wire o_nPin2;
wire o_nMTR123;

wire i_nPin12;
wire i_nPin14;
wire i_nPin16;
wire i_nPin10;
wire i_nPin6;
wire nActivityLED;

reg[31:0] motorTimerA;
reg[31:0] motorTimerB;
reg[31:0] spinupTime;
reg[31:0] mtrDelayCounter;
reg mtrAReady;
reg mtrBReady;
reg nDriveLatchedA = 1;
reg nDriveLatchedB = 1;
reg nDriveLatched2 = 1;
reg nDriveLatched3 = 1;
reg _o_nReady;
assign o_nReady = _o_nReady;


reg i_delaynDriveSelect0;
reg i_delaynDriveSelect1;
reg i_delaynDriveSelect2;
reg i_delaynDriveSelect3;

reg _nDir;
reg _nStep;

wire o_error;

	
MiSTerFloppyRAWIO #(CLK_Freq) dbRaw(	
	.i_core_cpu_clk(i_core_cpu_clk),
	.USER_IN(USER_IN),
	.USER_OUT(USER_OUT),
	
	.o_queueBusy(o_queueBusy),
	
	.i_nWriteData(i_nWriteData),
	.i_nWriteGate(i_nWriteGate),
	.i_nHeadSelect(i_nHeadSelect),
	.o_nReadData(o_nReadData),
	.o_nIndex(o_nIndex),

	.o_nTrk00(o_nTrk00),
	.o_nWriteProtected(o_nWriteProtected),
	.o_nPin34(o_nPin34),
	.o_nPin2(o_nPin2),
	.o_PinIBMDrive(o_PinIBMDrive),

	.i_nPin12(i_nPin12),
	.i_nPin14(i_nPin14),
	.i_nPin16(i_nPin16),		
	.i_nDir(_nDir),
	.i_nStep(_nStep),
	.i_nPin10(i_nPin10),
	.i_nPin6(i_nPin6),
	.i_nPin4InUse(nActivityLED),		
	.i_nMTR123(o_nMTR123),
	.i_reset(i_reset),
	.o_detected(o_detected),
	.o_error(o_error),
	.o_nSwappedCable(o_nSwappedCable)
);
	
reg _mtr123;
reg _pendingmtr123;
assign o_nMTR123 = _mtr123;
reg[31:0] mtr123Counter;
reg [1:0] step_prev;
reg [1:0] nDiskChange_r;
reg [1:0] nIndexesDetected;


assign o_nDiskChange = o_PinIBMDrive ? ((~i_nDriveSelect0) ? nDiskChange_r[0] : (~i_nDriveSelect1) ? nDiskChange_r[1] : 1'b1) : o_nPin2;
assign i_nPin14 = i_reset ? 1'b1 :  (o_PinIBMDrive ?      i_nDriveSelect0      :    i_nDriveSelect2   );
assign i_nPin12 = i_reset ? 1'b1 :            i_nDriveSelect1;
assign i_nPin10 = i_reset ? 1'b1 :  (o_PinIBMDrive ?      nDriveLatchedA       :    i_nDriveSelect0   );
assign i_nPin16 = i_reset ? 1'b1 :  (o_PinIBMDrive ?      nDriveLatchedB       :    nDriveLatchedA    );
assign i_nPin6 =                     o_PinIBMDrive ?      1'b1                    :    i_nDriveSelect3   ;

assign nActivityLED = AmigaMode ? nDriveLatchedA : i_nMotorEnable;
		
always@(posedge i_core_cpu_clk)begin
	i_delaynDriveSelect0 <= i_nDriveSelect0;
	i_delaynDriveSelect1 <= i_nDriveSelect1;
	i_delaynDriveSelect2 <= i_nDriveSelect2;
	i_delaynDriveSelect3 <= i_nDriveSelect3;

	_nDir <= i_nDir;
	
	// COMPATABILITY HACK
	if (AmigaMode && o_PinIBMDrive) begin
		// kickstart 1.3 changes direction as it changes step and some PC drives dont like this! 
		// So, I make it behave like Kickstart 2.0, and make sure DIR and STEP can't change at the same time
		if (_nDir == i_nDir) _nStep <= i_nStep;
	end else begin
		_nStep <= i_nStep;
	end
	
	if (i_reset) begin
		step_prev <= 2'b11;
		nDiskChange_r <= 2'b11;
		nDriveLatchedA <= 1;
		nDriveLatchedB <= 1;
		nDriveLatched2 <= 1;
		nDriveLatched3 <= 1;
		motorTimerA <= 32'h0;
		motorTimerB <= 32'h0;
		spinupTime <= CLK_Freq >> 1;   // so half the clock frequency
		//spinDnTime <= CLK_Freq >> 5;   // Its in the spec for floppy drives for this before 
		mtrDelayCounter = CLK_Freq / 128;
		_mtr123 <= 1;
		mtr123Counter <= 0;
		_pendingmtr123 <= 1;
		_nStep <= i_nStep;
		_nDir <= i_nDir;
		nIndexesDetected <= 2'h0;
	end else begin		
		
		if (o_PinIBMDrive) begin
			// TODO: Block DriveID from reaching DB interface
			// Sequence is:
			//  1. SELECT Drive
			//  2. Turn the motor on
			//  3. Turn the motor off (This resets the drive ID shift port)
			//  4. Deselect Drive
			//  5. Loop the following 32 times:
			//  5.1. SELECT DRive
			//  5.2. Read RDY
			//  5.3. DESELECT DRIVE
			//  DESELECT DRIVE
			//  Loop until all 32 bits received
			
			if (AmigaMode) begin
			   // Latch on select for DF0 and DF1
				if (~i_nDriveSelect0 && i_delaynDriveSelect0) nDriveLatchedA <= i_nMotorEnable;								
				if (~i_nDriveSelect1 && i_delaynDriveSelect1) nDriveLatchedB <= i_nMotorEnable;				
			end else begin
				nDriveLatchedA <= i_nMotorEnable;
				nDriveLatchedB <= i_nMotorEnable;
			end
						
			// DiskChange on PC drive triggers on FALLING edge of STEP, on Amiga drives its on RISING edge
			if (~i_nDriveSelect0) begin
				step_prev[0] <= i_nStep;
				if (~o_nPin34) nDiskChange_r[0] <= 0; else
					if (~step_prev[0] & i_nStep) nDiskChange_r[0] <= 1;				
			end
			if (~i_nDriveSelect1) begin
				step_prev[1] <= i_nStep;
				if (~o_nPin34) nDiskChange_r[1] <= 0; else
					if (~step_prev[1] & i_nStep) nDiskChange_r[1] <= 1;				
			end
			
			// Ready is a little more complex as we have to simulate it.  Its HIGH until ready
			if (~nDriveLatchedA) begin
				if (~i_nDriveSelect0 && ~o_nIndex) nIndexesDetected[0] <= 1;				

				if (motorTimerA != spinupTime) begin
					motorTimerA = motorTimerA + 32'h1;
					mtrAReady <= 1'b1;
				end else
				begin
					mtrAReady <= nIndexesDetected[0] ? i_nDriveSelect0 : ~o_nDiskChange; // RDY shouldnt signal if theres no disk, so we allow this if indexes detected OR dskchange is valid
				end
			end else
			begin
				mtrAReady <= AmigaMode ? i_nDriveSelect0 : 1'b1;
				motorTimerA <= 0;
				if (~i_nDriveSelect0) nIndexesDetected[0] <= 0;
			end
			
			if (~nDriveLatchedB) begin
				if (~i_nDriveSelect1 && ~o_nIndex) nIndexesDetected[1] <= 1;
				
				if (motorTimerB != spinupTime) begin
					motorTimerB = motorTimerB + 32'h1;
					mtrBReady <= 1'b1;
				end else
				begin					
					mtrBReady <= nIndexesDetected[1] ? i_nDriveSelect1 : ~o_nDiskChange; // RDY shouldnt signal if theres no disk, so we allow this if indexes detected OR dskchange is valid
				end
			end else
			begin
				mtrBReady <= AmigaMode ? i_nDriveSelect1 : 1'b1;
				motorTimerB <= 0;
				if (~i_nDriveSelect1) nIndexesDetected[1] <= 0;
			end
							
			_o_nReady <= ~((~mtrAReady) || (~mtrBReady));
			_mtr123 <= 1'b1;
		end else begin
			if (AmigaMode) begin
			   // Latch on deselect for DF0
				if (~i_nDriveSelect0 && i_delaynDriveSelect0) nDriveLatchedA <= i_nMotorEnable;	
				// Track the motor state for the other lines for internal use
				if (~i_nDriveSelect1 && i_delaynDriveSelect1) nDriveLatchedB <= i_nMotorEnable;	
				if (~i_nDriveSelect2 && i_delaynDriveSelect2) nDriveLatched2 <= i_nMotorEnable;	
				if (~i_nDriveSelect3 && i_delaynDriveSelect3) nDriveLatched3 <= i_nMotorEnable;	
				
				// Hack around drive ID. Force to DD
				if (~i_nDriveSelect0) _o_nReady <= (nDriveLatchedA ? 1'b0 : o_nPin34);  else			
				if (~i_nDriveSelect1) _o_nReady <= (nDriveLatchedB ? 1'b0 : o_nPin34);	else		
				if (~i_nDriveSelect2) _o_nReady <= (nDriveLatched2 ? 1'b0 : o_nPin34);	else	
				if (~i_nDriveSelect3) _o_nReady <= (nDriveLatched3 ? 1'b0 : o_nPin34);	else 	_o_nReady <= 1'b1;	
				
				// switch on mtr123
				if (~i_nMotorEnable && _mtr123) begin
					_mtr123 <= i_nMotorEnable;
					_pendingmtr123 <= i_nMotorEnable;
				end else
				if (i_nMotorEnable && ~_pendingmtr123) begin
					_pendingmtr123 <= i_nMotorEnable;
					mtr123Counter <= 0;
				end else
				if (_pendingmtr123 != _mtr123) begin
					mtr123Counter <= mtr123Counter + 1;
					if ((mtr123Counter == mtrDelayCounter) || (~i_nDriveSelect1) || (~i_nDriveSelect2) || (~i_nDriveSelect3)) begin
						_mtr123 <= _pendingmtr123;
					end
				end
				
			end else begin
				nDriveLatchedA <= i_nMotorEnable;
				_mtr123 <= 1;		
				_o_nReady <= o_nPin34;		
			end
		end
	end	
end
		
endmodule