//////////////////////////////////////////////////////////////////////////////
// MiSTer Floppy Virtual Floppy Drive                                       //
// Copyright (C) RobSmithDev 2022-2026                                      //
// https://mister.robsmithdev.co.uk                                         //
//////////////////////////////////////////////////////////////////////////////

/*

This simulates a virtual Amiga DD floppy drive, like the main part of the core, except this works at a flux level
It preteneds to be the read-data line of a floppy drive and provides no synchronisation at all, which should be perfect.
The output should be fed into MiSTerFloppyPLL 

Data format is WORDS, each BYTE in the word is: 
	0=INDEX
	1=Simple delay of 1/28mhz
	2=Disable actual flux transition on next byte
	>2 Time until flux transition at 28mhz clock 
	
If densityMode is enabled, the data format changes to MFM+density mode. Each WORD consists of:
	High byte: 8 MFM bits, MSB first, where a 1 indicates a flux transition
	Low byte:  Bit clock period in 28MHz ticks per bit cell (0=INDEX marker, ~54=fast, ~57=normal, ~60=slow)
	
*/

module MiSTerFloppyVirtualFluxDrive (
	input clk,   
	input clk7_en,
	input reset,
	input enabled,

	input [3:0] drivesSelect,   				  // Selected when set to 0, hence the 'n'	
	input [3:0] densityMode,					  // Density vs Flux mode
	input [1:0] driveSelected,					  // drive NUMBER selected
	
	input nMotorEnabled,							  // If the motor is enabled
	output o_nReady,  							  // If the motor is at speed - ~500ms
	output oRequestData,						     // Set to '1' when the virtual drive wants data to be pumped in ~450ms
		
	output floppyBit,             			  // Pretends to be the floppy drive read head, so no flags are needed
	
	input fifo_empty,								  // If the core FIFO is empty
	input fifo_reset,								  // set to 1 if the fifo was reset
	input  [15:0] fluxDataIn,                // Flux data received from the core FIFO
	output fluxDataRead,							  // Set when the flux data was read
	output _Index									  // Index pulse	
);


reg[21:0] motorTimer[3:0];

reg[3:0] mtrReady;
reg[3:0] nDriveLatched;
reg[3:0] delayDrivesSelect;
reg[7:0] ticksUntilNextFlux;    // Ticks until next flux
reg[7:0] nextFluxByte;
reg usingNextByte;
reg triggerFlux;

reg _o_nReady;
assign o_nReady = _o_nReady;
reg oRequestDataReg;
assign oRequestData = oRequestDataReg;

// This should remain LOW for around 400ns +/- 20% (320-480ns, 2.24-3.36 ticks, we'll go with 3). It's detected on falling edge, this is just for completeness
reg[1:0] floppyDriveBitCounter;
assign floppyBit = floppyDriveBitCounter == 2'h3;

reg fluxDataReadOut = 0;
assign fluxDataRead = fluxDataReadOut;

// the index pulse can last around 1-8ms! Theres 7 clock ticks below in 1us, so, 1000us is 7000 clock ticks
reg[12:0] indexCounter;
assign _Index = indexCounter == 13'h1FFF;



// for density mode
reg [7:0] current_mfm;
reg [7:0] current_density;
reg [7:0] staged_mfm;
reg [7:0] staged_density;
reg staged_valid;
reg [2:0] bit_pos;          // 0-7, which bit of current_mfm
reg [7:0] bit_counter;      // 28MHz counter

// This is for double density only. 
always@(posedge clk) begin

	if (~_o_nReady & ~nDriveLatched[driveSelected]) begin
	
		if (densityMode[driveSelected]) begin
	
			// Density mode works at the 28mhz domain
			if (bit_counter == 0) begin
				  bit_counter <= current_density;
				  
				  if (current_mfm[bit_pos]) floppyDriveBitCounter <= 2'h0;
							 
				  bit_pos <= bit_pos - 3'h1;
				  if (bit_pos == 0) begin
						// swap in staged
						staged_valid <= 0;  // signal 7MHz to fetch next
						
						if (staged_density == 0) begin
							indexCounter <= 0; 
							current_mfm <= 0;
							current_density <= 8'd57;
							bit_pos <= 1; // re-rigger
						end else begin
							 current_density <= staged_density;
							 current_mfm <= staged_mfm;
						end
				  end
			 end else begin
				  bit_counter <= bit_counter - 8'h1;
			 end
		end else begin
			// Pure flux mode
			if (ticksUntilNextFlux == 0) begin
				triggerFlux <= 1;									// Future transitions should trigger flux events unless overridden	
				if (usingNextByte) begin
					if (staged_valid) begin
						ticksUntilNextFlux  <= staged_density;
						nextFluxByte <= staged_mfm;
						staged_valid <= 0;
						usingNextByte <= 0;	
						case (staged_density)
							8'd0: indexCounter <= 0;  			// trigger index marker
							8'd1: ticksUntilNextFlux <= 0; 	// Delay by 1 clock
							8'd2: begin
										triggerFlux <= 0;   			// Next timing, DON'T trigger a flux transition, its just a delay
										ticksUntilNextFlux <= 0;
								end
							default: begin
											if (triggerFlux) floppyDriveBitCounter <= 2'h0;
										end
						endcase
					end else
					begin
						ticksUntilNextFlux <= 8'hFF;  // shouldn't happen
					end
				end else
				begin
					ticksUntilNextFlux <= nextFluxByte;						
					case (nextFluxByte)
							8'd0: indexCounter <= 0;  			// trigger index marker
							8'd1: ticksUntilNextFlux <= 0; 	// Delay by 1 clock
							8'd2: begin
										triggerFlux <= 0;   			// Next timing, DON'T trigger a flux transition, its just a delay
										ticksUntilNextFlux <= 0;
								end
							default: begin
											if (triggerFlux) floppyDriveBitCounter <= 2'h0;													
										end
					endcase
					usingNextByte <= 1;				
				end
			end else
			begin
				ticksUntilNextFlux <= ticksUntilNextFlux - 8'h01;
			end			
		end
	end

	if (clk7_en) begin  // 14 clocks is 2uS
		delayDrivesSelect <= drivesSelect;

		if (reset) begin	
			integer id;
			for (id = 0; id<4; id=id+1) begin	
				mtrReady[id] <= 0;
				nDriveLatched[id] <= 0;
				motorTimer[id] <= 22'b0;
			end
			fluxDataReadOut <= 0;
			_o_nReady <= 1;			
			ticksUntilNextFlux <= 0;
			nextFluxByte <= 8'h1C;   // kind of a 4us pulse
			indexCounter <= 13'h1FFF;
			floppyDriveBitCounter <= 2'h3;
			usingNextByte <= 1;
			triggerFlux <= 1;	
			staged_valid <= 0;
			bit_pos <= 3'd7;
			staged_valid <= 1'b0;
			current_density <= 8'd57;  // nominal 2us at 28MHz
			bit_counter <= 8'd0;
			current_mfm <= 8'd0;
		end else begin							
			integer id;
			// This isn't quite right, as driveId is faster than 7mhz, but it works for what we need.
			for (id = 0; id<4; id=id+1) begin
				if (drivesSelect[id] && ~delayDrivesSelect[id]) nDriveLatched[id] <= nMotorEnabled;	
			
				// Ready is a little more complex as we have to simulate it.  It's HIGH until ready
				if (~nDriveLatched[id]) begin
					if (motorTimer[id] != 3_500_000) begin    // that's 500ms, standard spinup time
						motorTimer[id] <= motorTimer[id] + 22'h1;
						mtrReady[id] <= 1'b1;
					end else begin 
						mtrReady[id] <= ~drivesSelect[id]; 
					end
				end else
				begin 
					mtrReady[id] <= ~drivesSelect[id];  
					motorTimer[id] <= 2'd0; 
				end
			end	
			
			fluxDataReadOut <= 1'b0;
			
			// Handle a fifo reset
			if (fifo_reset) begin
				ticksUntilNextFlux <= 0;
				nextFluxByte <= 8'h1C;   // kind of a 4us pulse
				indexCounter <= 13'h1FFF;
				floppyDriveBitCounter <= 2'h3;
				usingNextByte <= 1;
			end
			
			if (!staged_valid) begin
				// fetch from FIFO
				staged_mfm <= fluxDataIn[15:8];
				staged_density <= fluxDataIn[7:0];
				staged_valid <= 1;
				fluxDataReadOut <= 1'b1;
			end
									
			// which drive is selected?
			_o_nReady <= (enabled & drivesSelect[driveSelected]) ? mtrReady[driveSelected] : 1'b1;
			// Special flag if this is ready to start receiving data (~50ms before READY is set)
			oRequestDataReg <= enabled & drivesSelect[driveSelected] & ~nDriveLatched[driveSelected] & (motorTimer[driveSelected][21:20]==2'b11);
					
			// Index counter!
			if (!_Index) indexCounter <= indexCounter + 13'h1;			
			if (~floppyBit) floppyDriveBitCounter <= floppyDriveBitCounter + 2'h1;				
		end
	end
end



endmodule