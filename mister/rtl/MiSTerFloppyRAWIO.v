//////////////////////////////////////////////////////////////////////////////
// MiSTer Floppy                                                            //
// Copyright (C) RobSmithDev 2022-2026                                      //
// https://mister.robsmithdev.co.uk                                         //
//////////////////////////////////////////////////////////////////////////////
//
// This module provides direct access to the pins on the MiSTer Floppy board
// via the user port.  This should not be used directly,
// instead, use MiSTerFloppyIBM, MiSTerFloppySHUGART
// NOTE: On the MiSTer Floppy port, the pin names are all as if a crossover cable was connected
//       meaning from the MiSTer, a crosseed cable looks like a straight one.
//
// IO  | USB Name | Signal Name         | CROSSED  | STRAIGHT 
// ----+----------+---------------------+----------+-----------
// 0   | D+       | I/O I2C_SDA         |   3      |   3
// 1   | D-       | O   Write Data      |   2      |   2
// 3   | GND_d    | O   I2C_SCL         |   7      |   7  
// 2   | TX-      | I   Index           |   8      |   5
// 5   | RX-      | O   HEAD/SIDE       |   5      |   8
// 4   | RX+      | I   Read Data       |   6      |   9
// 6   | TX+      | O   Write Gate IO6  |   9      |   6


/* The above cable pin choice was great when I was using a Type B style connector on the PCB end, but I switched it to a type A
   to match the MT32-Pi and discovered theres two types of cable. This means with some cables the following pairs can swap:
	Pins 5 <-> 8
	Pins 6 <-> 9
	
	Cable detect is simple. I added a connection between the original HEAD/SIDE pin and one of the spare inputs on the port expander
	During startup I pull the head line low and see if it does on the port expander. If it does its wired straight, if not, its wired swapped
	Note: The Type-A PCB is designed to take swapped cables by default because I didnt realise this was an issue.
	
	
The port expander can operate in Byte Mode or Sequential Mode
With byte mode you can set an address and keep reading/writing without ending for very fast writing or polling.

However after every write I've found I need to read so making this mode less useful. Instead I'm using Sequential mode on Bank A, and 
Byte Mode on Bank B, so after a write the chip is already setup to read byte B, but stays on byte B after each read.
You can't just keep reading bytes unfortunatly in this mode as due to the setup this causes the chip to toggle between
Bank A and Bank B, but if you stop and start a read it stays at the same register.

Speed:
 Obviously using a port expander not all operations happen as quickly as they would on a native machine.
 If that machine is slow enough it doesn't matter.  If you're writing a drive controller you can account for it too.
 The biggest issue comes from changes to the drive selected. It doesnt happen instantly! I didnt imagine this to be an issue
 but became clear it could be in some limited situations.  
 To help combat this theres a single extra parameter
 o_queueBusy:    This is set to 1 while the the internal queue is still processing requests and theres a its possible the output doesnt
					  match the request. This only really matters for writing tbh, so on the Amiga core I prevent the DMA writing to the disk until its clear
					  Typically, on a floppy drive, select should respond within 0.5uS. 
					  With the port expander, that turns out to be more like ~70-80uS (76uS measured) 					  					  					  
*/


module MiSTerFloppyRAWIO (
	input i_core_cpu_clk,			// Clock (make sure CLK_Freq is set correctly)
	
	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,
	
	output	o_queueBusy,			// Set when the output on the port expander doesn't reflect the request
	
	
	input i_nWriteData,				// nWDATA
	input i_nWriteGate,				// nWGATE
	input i_nHeadSelect,				// nSIDE1
	output o_nReadData,				// nRDATA
	output o_nIndex,					// nINDEX
	
	output o_nTrk00,					// nTRK00
	output o_nWriteProtected,		// nWPT
	output o_nPin34,					// nRDY/DSKCHG
	output o_nPin2,					// nREDWC/nCDC - TODO, this should be inout for IBM density select
	output o_PinIBMDrive,			// 0 if the jumper is set to Shugart, and 1 if set to IBM	
	
	input i_nPin12,						
	input i_nPin14,
	input i_nPin16,
	input i_nDir,						// nDIR
	input i_nStep,						// nSTEP
	input i_nPin10,
	input i_nPin6,
	input i_nPin4InUse, 				// Controls PIN 4 and the IN USE LED on the board, has a 100MS DELAY before being set
	
	input i_nMTR123,					// nMTR123 Pin on the expansion header
	
	input i_reset,						// Reset the interface
	
	output o_detected,				// Set to '1' when MiSTer Floppy has been detected
	output o_error, 					// Set to '1' when for 200ms during I2C reset if an error occurs
	output o_nSwappedCable			// Which type of cable in use
);

parameter CLK_Freq = 50_000_000;	//	default 50 MHz
	
localparam MCP2301X_CTRL_ID 	= 7'h20;
localparam REGISTER_IODIR0 	= 7'h00;
localparam REGISTER_IPOL0 		= 7'h02;
localparam REGISTER_IOCON 		= 7'h0A;
localparam REGISTER_GPPU0 		= 7'h0C;
localparam REGISTER_GPIO0 		= 7'h12;
                                      //                           IBMPC           	   AMIGA              Normal SHUGART
localparam IOEXP_PIN12      =  4'h0;  // Output         			    Drive Select (B)    Select 1           Select 1     
localparam IOEXP_PIN14      =  4'h1;  // Output         			    Drive Select (A)    Select 2           Select 2     
localparam IOEXP_PIN16      =  4'h2;  // Output         			    Motor Enable (B)    MTR0               MTRON          
localparam IOEXP_DIR        =  4'h3;  // Output         			    Direction           Direction          Direction    
localparam IOEXP_STEP       =  4'h4;  // Output         			    Step                Step               Step         
localparam IOEXP_PIN10      =  4'h5;  // Output         			    Motor Enable (A)    Select 0           Select 0     
localparam IOEXP_MTR123     =  4'h6;  // Output         			    Motor Enable (B)    MTRX               MTRON          
localparam IOEXP_PIN6       =  4'h7;  // Output         			    n/c                 Select 3           Select 3     

// The -4'h8 is so these can be read-back in for single reads      IBMPC               AMIGA           	 Normal Shugart
localparam IOEXP_WPT        =  4'h8-4'h8;  // Input                Write Protect       Write Protect      Write Protect
localparam IOEXP_PIN34      =  4'h9-4'h8;  // Input                Disk Change         Ready              Ready
localparam IOEXP_CABLEDETECT=  4'hA-4'h8;  // Input                
localparam IOEXP_PIN2       =  4'hB-4'h8;  // Input                DS (output!)        Disk Change        Disk Change
localparam IOEXP_PIN4INUSE  =  4'hC-4'h8;  // Output               ********* Activity LED/Pin 4/Expansion Header ************
localparam IOEXP_RESET      =  4'hD-4'h8;  // Output               ************** Reset on Expansion Header *****************
localparam IOEXP_TRK00      =  4'hE-4'h8;  // Input                Track0              Track0             Track0
localparam IOEXP_IBMPC      =  4'hF-4'h8;  // Input                HIGH                LOW                LOW

localparam S_REGISTER_RESET_DELAY 	= 4'h0;
localparam S_REGISTER_RESET 		 	= 4'h1;
localparam S_WRITE_SETUP	 			= 4'h2;
localparam S_WRITE_START	 			= 4'h3;
localparam S_WRITE_STOP	    			= 4'h4;
localparam S_WRITE_CHECK	 			= 4'h5;
localparam S_READ_WRITE_START 		= 4'h6;
localparam S_READ_WRITE_CHECK 		= 4'h7;
localparam S_READ_WRITE_END   		= 4'h8;
localparam S_READ_START	 	 			= 4'h9;
localparam S_READ_STOP	    			= 4'hA;
localparam S_READ_CHECK	 	 			= 4'hB;

localparam SW_IOCON			   =  4'h0;
localparam SW_IPOL0			   =  4'h1;
localparam SW_GPPU0			   =  4'h2;
localparam SW_IODIR0			   =  4'h3;
localparam SW_GPIO0           =  4'h4;
localparam SW_DRIVE_RESET1    =  4'h5;
localparam SW_DRIVE_RESET2    =  4'h6;
localparam SW_DRIVE_READ      =  4'h7;
localparam SW_CABLESENSE      =  4'h8;
localparam SW_RUNNING         =  4'h9;	

localparam	I2CFrequency		= 32'd400_000;   // works at 500000 doesn't work any faster than this. 

reg [31:0]  i2cResetCounter = 0;      // for the 100ms delay before restart after reset
reg [31:0]  activityLEDCounter = 0;

reg [3:0] 	currentWriteMode;
reg [3:0] 	progCounter 					= S_REGISTER_RESET_DELAY;

reg _o_nTrk00;
reg _o_nWriteProtected;
reg _o_nPin34;
reg _o_nPin2;

reg _o_PinIBMDrive = 1;
reg _o_error = 0;

// NOTE: queueRead and queueWrite bit size must match COMMAND_QUEUE_SIZE-1 bits or overflow won't work
localparam			COMMAND_QUEUE_SIZE	= 64;

reg [8:0]         commandQueue[COMMAND_QUEUE_SIZE-1:0];
reg [5:0]			queueRead				= 0;
reg [5:0]			queueWrite				= 0;

reg m_queueBusy = 0;
assign o_queueBusy = m_queueBusy;  
wire _selectChanging;
assign _selectChanging = actualActiveDrive != idealActiveDrive;

localparam        IO_SDA					= 0;
localparam 			IO_WRITEDATA			= 1;
localparam			IO_SCL					= 3;
localparam			IO_PIN8              = 5;
localparam			IO_PIN9				   = 4;
localparam        IO_PIN5				   = 2;
localparam			IO_PIN6					= 6;

// Cable type detect
reg nSwappedCable = 0;    // 0 for Swapped, 1 for straight
assign o_nSwappedCable = nSwappedCable;

// OUTPUT Wires
wire wWriteGate;
assign wWriteGate = _selectChanging ? 1'b1 : i_nWriteGate;

// Output or enable reading on those pins based on cable swap
assign USER_OUT[IO_PIN6] 				= 															   nSwappedCable ? 1'b1 			: wWriteGate              ;
assign USER_OUT[IO_PIN8] 				= (currentWriteMode == SW_CABLESENSE) ? 1'b0 : (nSwappedCable ? 1'b1 			: i_nHeadSelect            );
assign USER_OUT[IO_PIN5] 				= 																nSwappedCable ? i_nHeadSelect : 1'b1;
assign USER_OUT[IO_PIN9] 				= 																nSwappedCable ? wWriteGate 	: 1'b1;


// Handle input pins
assign o_nReadData 						= _selectChanging ? 1'b1 : (nSwappedCable ? USER_IN[IO_PIN6] : USER_IN[IO_PIN9]);
assign o_nIndex 							= _selectChanging ? 1'b1 : (nSwappedCable ? USER_IN[IO_PIN8] : USER_IN[IO_PIN5]);

// Setup other I/O
assign USER_OUT[IO_WRITEDATA] 		= _selectChanging ? 1'b1 : i_nWriteData;


  
assign o_PinIBMDrive		= _o_PinIBMDrive;
assign o_error 			= _o_error;

reg [3:0]   drive0Values = 4'b1111;
reg [3:0]   drive1Values = 4'b1111;
reg [3:0]   drive2Values = 4'b1111;
reg [3:0]   drive3Values = 4'b1111;

reg 			i2cStart = 0;
reg 			i2cReadMode;    
wire 			i2cError;
wire 			i2cReady;

reg [7:0]	i2cRegAddress;
wire [7:0]  i2cDataRead;

reg [7:0] 	i2cDataWrite8Bit1;
reg [7:0] 	i2cDataWrite8Bit2;
reg  			i2cWrite2Bytes;

// Used to track changes in the incomming signals
reg [9:0] 	outLineMask;

reg 			i2cReadWriteBytes;
reg			lastActivityLED;
reg			outputActivityLED;
reg 			detected;
assign 		o_detected = detected;

initial begin
	progCounter = S_REGISTER_RESET_DELAY;
	i2cResetCounter = 0;
end


MiSTerFloppyi2c #(CLK_Freq, I2CFrequency) i2c
(
	.CLK(i_core_cpu_clk),
	.START(i2cStart),
	.READ(i2cReadMode),
	.I2C_ADDR(MCP2301X_CTRL_ID),
	.I2C_WLEN(i2cReadWriteBytes),
	.I2C_WDATA1(i2cRegAddress),
	.I2C_WDATA2(i2cDataWrite8Bit1),
	.I2C_RDATA(i2cDataRead),
	.END(i2cReady),
	.ACK(i2cError),
	.I2C_SCL(USER_OUT[IO_SCL]),
	.I2C_SDA(USER_IN[IO_SDA]),
	.I2C_enableRead(USER_OUT[IO_SDA]),
	.i_reset(i_reset)
);


reg lastWasReading = 0;

assign o_nTrk00 = _o_nTrk00;
assign o_nWriteProtected = _o_nWriteProtected;
assign o_nPin34 = _o_nPin34;
assign o_nPin2 = _o_nPin2;

wire [2:0]	liveSelectedDrive;
assign liveSelectedDrive = _o_PinIBMDrive ?	((~i_nPin14)?3'd1:((~i_nPin12)?3'd2:3'd0)) : ((~i_nPin10)?3'd1:((~i_nPin12)?3'd2:((~i_nPin14)?3'd3:((~i_nPin6)?3'd4:3'd0))));

									
reg [2:0]   actualActiveDrive = 0;    // The drive that is currently selected on the expander
reg [2:0]   selectedDriveRead = 0;    // The drive that *will* be selected after the next write to I2C
reg [2:0]   idealActiveDrive = 0;     // The drive the OS thinks is selected but might not be yet
	
reg 			errorRetry = 0;			  // Allow one retry if an error occurs
	
			
always@(posedge i_core_cpu_clk)begin
	idealActiveDrive <= liveSelectedDrive;
	
	case (liveSelectedDrive)				
		3'd0:  { _o_nTrk00, _o_nWriteProtected, _o_nPin34, _o_nPin2} <= 4'b1111;
		3'd1:  { _o_nTrk00, _o_nWriteProtected, _o_nPin34, _o_nPin2} <= drive0Values;
		3'd2:  { _o_nTrk00, _o_nWriteProtected, _o_nPin34, _o_nPin2} <= drive1Values;
		3'd3:  { _o_nTrk00, _o_nWriteProtected, _o_nPin34, _o_nPin2} <= drive2Values;
		3'd4:  { _o_nTrk00, _o_nWriteProtected, _o_nPin34, _o_nPin2} <= drive3Values;
	endcase

	// This is very low priority so delay changing this for ~100ms after it changes state
	if ((lastActivityLED != i_nPin4InUse) && (queueRead == queueWrite) && (lastWasReading)) begin
		activityLEDCounter <= 0;
		lastActivityLED <= i_nPin4InUse;
	end else
	begin
		if (activityLEDCounter != CLK_Freq/128) begin
			activityLEDCounter <= activityLEDCounter + 32'h1; 
		end else 
		begin
			outputActivityLED <= i_nPin4InUse;
		end
	end;	
		
	if (i_reset) begin
		progCounter 	 <= S_REGISTER_RESET_DELAY;
		i2cStart 		 <= 0;
		_o_error 		 <= 0;
		i2cResetCounter <= 0;
		queueRead		 <= 0;
		errorRetry      <= 0;
		queueWrite		 <= 0;
		lastActivityLED <= i_nPin4InUse;
		activityLEDCounter <= 0;
		drive0Values 	<= 4'b1111;
		drive1Values 	<= 4'b1111;
		drive2Values 	<= 4'b1111;
		drive3Values 	<= 4'b1111;
		selectedDriveRead <= 0;		
		nSwappedCable  <= 0;
		m_queueBusy 	<= 0;
		lastWasReading <= 0;
		detected 		<= 0;
		actualActiveDrive <= 0;    // The drive that is currently selected on the expander		
	end else begin
		// Compute a reg of all of the lines that may have critical timings that we can't quite meet on I2C
		outLineMask <= {  i_nPin6, i_nPin10, i_nPin12, i_nPin14, i_nPin16, i_nDir, i_nStep, i_nMTR123, outputActivityLED };

		// Has the state changed? (can't read and write in the same clock cycle)
		if ((outLineMask != {  i_nPin6, i_nPin10, i_nPin12, i_nPin14, i_nPin16, i_nDir, i_nStep, i_nMTR123, outputActivityLED })) begin
			 // Need to queue it.	
			 commandQueue[queueWrite] <= {  i_nPin6, i_nPin10, i_nPin12, i_nPin14, i_nPin16, i_nDir, i_nStep, i_nMTR123, outputActivityLED };
			 queueWrite <= queueWrite + 5'h1;
			 m_queueBusy <= 1;
		end else begin			
			// State machine
			case (progCounter)
				// Reset delay to allow for I2C timeout
				S_REGISTER_RESET_DELAY: begin			
						detected 		<= 0;	
						i2cStart 						<= 0;						
						i2cResetCounter <= i2cResetCounter + 31'h01;
						// Reset Timeout of 200ms - plenty of time for the I2C bus finish / timeout
						if (i2cResetCounter >= CLK_Freq/5) begin
							progCounter <= S_REGISTER_RESET;
							_o_error <= 0;   // turn off error indicator
						end
					end
				
				// Reset everything and start again
				S_REGISTER_RESET: begin
							// Reset I2C
							i2cStart 						<= 0;																												
							selectedDriveRead 			<= 0;
							
							drive0Values 					<= 4'b1111;
							drive1Values 					<= 4'b1111;
							drive2Values 					<= 4'b1111;
							drive3Values 					<= 4'b1111;
							
							outLineMask						<= 9'B111111111;

							progCounter 					<= S_WRITE_SETUP;
							currentWriteMode 				<= SW_IOCON;
							lastActivityLED 				<= 1;
							nSwappedCable					<= 0;
														
							lastWasReading					<= 0;							
					 end	
				
				// Program the port expander to how we're using it
				S_WRITE_SETUP: begin
						i2cReadMode <= 0;	
						i2cReadWriteBytes 	<= 1;
						case (currentWriteMode)
							SW_IOCON: begin
									i2cRegAddress <= REGISTER_IOCON;
									i2cDataWrite8Bit1 	<= 8'b00000000;   // enable sequential mode to jump to Bank B after we write
									i2cDataWrite8Bit2 	<= 8'b00100000;   // Disable sequential mode to stay on bank B (this kind of works)
									i2cWrite2Bytes 		<= 1;
									
									progCounter <= S_WRITE_START;	// Next step is the WRITE
									currentWriteMode <= SW_IPOL0;	// Next time do pullups
								end	
							SW_IPOL0: begin // Set input polarity 
									i2cRegAddress <= REGISTER_IPOL0;
									i2cDataWrite8Bit1 	<= 0;
									i2cDataWrite8Bit2 	<= 0;
									i2cWrite2Bytes 		<= 1;

									progCounter <= S_WRITE_START;	// Next step is the WRITE
									currentWriteMode <= SW_GPPU0;	// Next time do i/o directions
								end								
							SW_GPPU0: begin // Set pullups 
									i2cRegAddress <= REGISTER_GPPU0;
									i2cDataWrite8Bit1 	<= 8'hFF;
									i2cDataWrite8Bit2 	<= 8'hFF;
									i2cWrite2Bytes 		<= 1;

									progCounter <= S_WRITE_START;	// Next step is the WRITE
									currentWriteMode <= SW_IODIR0;	// Next time do i/o directions
								end	
							SW_IODIR0: begin    // Set input/output directions
									i2cRegAddress <= REGISTER_IODIR0;
									i2cDataWrite8Bit1 <= 8'b00000000;   // All outputs
									i2cDataWrite8Bit2 <= 8'b11001111;	// Input,Input,Output,Output,Input,Input,Input,Input
									                                    // Todo: To use Density Select on IBMPC drives would need to be 8'b11000111;
									i2cWrite2Bytes 		<= 1;

									progCounter <= S_WRITE_START;	// Next step is the WRITE
									currentWriteMode <= SW_GPIO0;	// Next time do output default state					
								end		
							SW_GPIO0: begin // Default to HIGH (outputs)
									i2cRegAddress <= REGISTER_GPIO0;
									i2cDataWrite8Bit1 <= 8'hFF;
									i2cDataWrite8Bit2 <= 8'hFF;	
									i2cWrite2Bytes 		<= 1;

									progCounter <= S_WRITE_START;	// Next step is the WRITE
									currentWriteMode <= SW_DRIVE_RESET1;	//	Next do a drive reset sequence for external drives
								end
							SW_DRIVE_RESET1: begin
									// Everything is already HIGH when we get here
									i2cDataWrite8Bit1[IOEXP_RESET] = 0;
									i2cRegAddress <= REGISTER_GPIO0+8'h1;
									i2cWrite2Bytes 		<= 0;
									
									progCounter <= S_WRITE_START;	// Next step is the WRITE
									currentWriteMode <= SW_DRIVE_RESET2;	//	Next finish the drive reset sequence for external drives
								end
							SW_DRIVE_RESET2: begin
									i2cRegAddress <= REGISTER_GPIO0+8'h1;
									i2cDataWrite8Bit1 <= 8'hFF;
									i2cDataWrite8Bit2 <= 8'hFF;     // Switch everything off so compare later on works
									i2cWrite2Bytes 		<= 0;      // Maybe set to 1
									
									// Address for writing will be correct at this point given the reset we've just done!
									progCounter <= S_WRITE_START;//S_READ_START;	// Next step to perform a read so we know if this is in PC/Shugart mode
									currentWriteMode <= SW_DRIVE_READ;	//	Afterwards, prepare for a read
								end
							SW_DRIVE_READ: begin
									// This is an important step. It identifies if we're using an PC/Shugart drive based on the jumper
									// but also performs a USER PORT cable test to see if the cable is a straight or cross over type
									// It does this by pulling the HEAD line low, and then seeing if IOEXP_CABLEDETECT follows
									i2cRegAddress <= REGISTER_GPIO0+8'h1;
									progCounter <= S_READ_WRITE_START;     // Next step to perform a read so we know if this is in PC/Shugart mode
									currentWriteMode <= SW_CABLESENSE;	   //	Afterwards, note we're in cable sense mode
									queueRead		 				<= 0;
									queueWrite		 				<= 0;
									i2cDataWrite8Bit2				<= 8'hFF;   
							   end
							SW_CABLESENSE: begin
									// If we get here, then cable sense has finished 
									nSwappedCable  <= i2cDataRead[IOEXP_CABLEDETECT];									
									currentWriteMode <= SW_RUNNING;
									detected <= 1; // working!
								end
							SW_RUNNING: begin
									i2cRegAddress 			<= REGISTER_GPIO0;	

									// Is the queue empty? - Just poll for data
									if (queueRead == queueWrite) begin
										m_queueBusy <= 0;
										if (selectedDriveRead>0) begin
											if (lastWasReading)
												progCounter <= S_READ_START;  
											else progCounter <= S_READ_WRITE_START;  										
										end
									end else								
									begin
										//     8         7        6         5           4      3      2           1           0
										// i_nPin6, i_nPin10, i_nPin12, i_nPin14, i_nPin16, i_nDir, i_nStep, i_nMTR123, i_nPin4InUse 
										queueRead <= queueRead + 5'h1;
										
										i2cDataWrite8Bit1[IOEXP_PIN6] 	<= commandQueue[queueRead][8];									
										i2cDataWrite8Bit1[IOEXP_PIN10] 	<= commandQueue[queueRead][7];
										i2cDataWrite8Bit1[IOEXP_PIN12] 	<= commandQueue[queueRead][6];
										i2cDataWrite8Bit1[IOEXP_PIN14] 	<= commandQueue[queueRead][5];
										i2cDataWrite8Bit1[IOEXP_PIN16] 	<= commandQueue[queueRead][4];
										i2cDataWrite8Bit1[IOEXP_DIR] 		<= commandQueue[queueRead][3];
										i2cDataWrite8Bit1[IOEXP_STEP] 	<= commandQueue[queueRead][2];
										i2cDataWrite8Bit1[IOEXP_MTR123] 	<= commandQueue[queueRead][1];
										i2cDataWrite8Bit2[IOEXP_PIN4INUSE]<=	commandQueue[queueRead][0];		
										i2cDataWrite8Bit2[IOEXP_RESET]	<= 1;
										
										// This will be whats selected at the end of the write
										selectedDriveRead 	<= _o_PinIBMDrive ?
																				((~commandQueue[queueRead][5])?3'd1:((~commandQueue[queueRead][6])?3'd2:3'd0))
																								:
																				((~commandQueue[queueRead][7])?3'd1:((~commandQueue[queueRead][6])?3'd2:((~commandQueue[queueRead][5])?3'd3:((~commandQueue[queueRead][8])?3'd4:3'd0))));
																				
										// Did IOEXP_ACTIVITY change?
										if (i2cDataWrite8Bit2[IOEXP_PIN4INUSE] != commandQueue[queueRead][0]) begin
											// Need to send both bytes
											i2cWrite2Bytes <= 1;
											// After its complete we will need to reset the address
											lastWasReading <= 0;
										end else
										begin
											// Only need to send one byte
											i2cWrite2Bytes <= 0;
											// After complete it'll be in the 'read' address position
											lastWasReading <= 1;
										end;
																				
										// We're skipping a step to save a clock cycle
										i2cStart <= 1;					
										progCounter <= S_WRITE_STOP;		
									end
								end
						endcase	
					end
					
					// Wait for Write
				S_WRITE_START: begin
						i2cStart <= 1;		
						progCounter <= S_WRITE_STOP;
					end
					
					// Complete the write
				S_WRITE_STOP: if (~i2cReady) progCounter <= S_WRITE_CHECK;					
				// Wait and check result
				S_WRITE_CHECK: begin
						i2cStart <= 0;
						if (i2cReady) begin
							if (!i2cError) begin
								
								if (i2cWrite2Bytes) begin
									// Do the second bit - this doesn't happen often but we could optimise here
									i2cDataWrite8Bit1 <= i2cDataWrite8Bit2;
									i2cRegAddress <= i2cRegAddress + 8'h01;
									i2cWrite2Bytes <= 0;
									progCounter <= S_WRITE_START;										
								end else
								begin
									if (currentWriteMode == SW_RUNNING) begin  // Normal operation mode?
										actualActiveDrive <= selectedDriveRead;
										if (selectedDriveRead>0) 
											  progCounter <= lastWasReading ? S_READ_START : S_READ_WRITE_START;  
										else progCounter <= S_WRITE_SETUP;				
									end else 
									begin
										// Repeat for other operations (always WRITE)
										progCounter <= S_WRITE_SETUP;										
									end
								end
								errorRetry <= 0;
							end else begin
								if (errorRetry) begin
									// If it fails, re-start the entire sequence														
									progCounter <= S_REGISTER_RESET_DELAY;
									i2cResetCounter <= 0;
									_o_error <= 1;
								end else
								begin
									// ONE retry
									errorRetry <= 1;
									progCounter <= S_WRITE_START;		
								end
							end
						end
					end	
					
				// Start read by writing the address we want
				S_READ_WRITE_START:begin
						i2cStart <= 1;
						i2cReadMode <= 0;	
						i2cReadWriteBytes <= 0;
						i2cRegAddress <= REGISTER_GPIO0 + 8'h01;	
						progCounter <= S_READ_WRITE_CHECK;											
					end
					
				// Wait for completion
				S_READ_WRITE_CHECK: if (~i2cReady) progCounter <= S_READ_WRITE_END;			
			
				  // Start read
				S_READ_WRITE_END:begin
						i2cStart <= 0;
						
						if (i2cReady) begin	
							if (!i2cError) begin
								progCounter <= S_READ_START;
								errorRetry <= 0;
							end else
							begin
							   if (errorRetry) begin
									progCounter <= S_REGISTER_RESET_DELAY;
									i2cResetCounter <= 0;
									_o_error <= 1;
								end else
								begin
									errorRetry <= 1;
									progCounter <= S_READ_WRITE_START;
								end
							end
						end
					end
					
				S_READ_START: begin
						i2cReadMode <= 1;	  // we want reading now
						i2cStart <= 1;
						i2cReadWriteBytes <= 0;
						progCounter <= S_READ_STOP;
					end
							
					
					// Wait for read
				S_READ_STOP: if (~i2cReady) progCounter <= S_READ_CHECK;
					
					// Read complete check
				S_READ_CHECK: begin
						i2cStart <= 0;
						if (i2cReady) begin	
							if (!i2cError) begin
								
								// Drive type does actually hot-swap, but not recommended
								_o_PinIBMDrive 		<= i2cDataRead[IOEXP_IBMPC];
								
								case (selectedDriveRead)
									1:drive0Values <= {i2cDataRead[IOEXP_TRK00], i2cDataRead[IOEXP_WPT], i2cDataRead[IOEXP_PIN34], i2cDataRead[IOEXP_PIN2]};
									2:drive1Values <= {i2cDataRead[IOEXP_TRK00], i2cDataRead[IOEXP_WPT], i2cDataRead[IOEXP_PIN34], i2cDataRead[IOEXP_PIN2]};
									3:drive2Values <= {i2cDataRead[IOEXP_TRK00], i2cDataRead[IOEXP_WPT], i2cDataRead[IOEXP_PIN34], i2cDataRead[IOEXP_PIN2]};
									4:drive3Values <= {i2cDataRead[IOEXP_TRK00], i2cDataRead[IOEXP_WPT], i2cDataRead[IOEXP_PIN34], i2cDataRead[IOEXP_PIN2]};
								endcase
								
								// Switch back to writing, but just our data, not reset
								progCounter <= S_WRITE_SETUP;
								
								lastWasReading <= 1;		
								errorRetry <= 0;
							end else begin
								if (errorRetry) begin
									// If it fails, Reset and start again
									progCounter <= S_REGISTER_RESET_DELAY;
									i2cResetCounter <= 0;								
									_o_error <= 1;
								end else
								begin
									// Allow ONE retry
									errorRetry <= 1;
									progCounter <= S_READ_WRITE_START;
								end
							end
						end
					end	
			endcase	  
		end
	end
end		
	
endmodule