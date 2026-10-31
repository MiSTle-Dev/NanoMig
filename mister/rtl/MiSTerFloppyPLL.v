//////////////////////////////////////////////////////////////////////////////
// MiSTer Floppy                                                            //
// Copyright (C) RobSmithDev 2022-2026                                      //
// https://mister.robsmithdev.co.uk                                         //
//////////////////////////////////////////////////////////////////////////////
// The majority of this file was originally created by Lukage               //
// Updated to provide enough information for DSKBYR register to be correct  // 
// And to resolve the over-aggressive clock search                          //
//////////////////////////////////////////////////////////////////////////////

// TODO: GCR

module MiSTerFloppyPLL (
	input clk,                     			  // 28Mhz
	input clk7_en,
	input reset,
	input trackrd,
	input _dskrd,                				  // Actual status of "live" MFM bitstream 
	input selected,
	input trackwr,
	input [1:0] precomp,

	input fifo_empty,
		
	output [15:0] ext_floppy_rx,             // MFM WORD of data received from the Floppy drive.  ext_floppy_wr is set to indicate it's valid
	output ext_floppy_wr,                    // Set when a new WORD is ready to be read into the FIFO
	
	input  [15:0] ext_floppy_tx,             // MFM Word of data from the Amiga to be written to disk
	
	output ext_floppy_rd,                    // Set to 1 when ext_floppy_tx has been read
	output ext_floppy_rd_del,                // this is delayed by 16 bits to ensure everything is written to disk
	output ext_floppy_sync,                  // Set when SYNC word is detected
	
	output [7:0] diskByte,							// Current byte read
	output diskByteReady,                     // Set when diskByte has changed
	input  resetDiskByteReady,						// Used to reset the disk byte ready bit
	output syncWordNOW,								// Set to 1 if theres a wordsync literally right now (use for dskbytr)
	
	input wordsyncEnabled,                    // Enable/disable wordsync
	input [15:0] ext_floppy_syncword,         // SYNC Word to Search For
	
	output bitdetected,
	
	input pause,										// Set to 1 to 'pause' any actions. 
	output _writeData,								// Output MFM writing (WRITE_DATA)
	output _writeGate									// Output ENABLE (WRITE_GATE)
);


reg _dkwd;
wire _dkweDelay;
assign _writeData = _dkwd;
reg _dkwe;
assign _writeGate = _dkwe & _dkweDelay;


reg         _dskrd_reg = 1'b1;
reg         _dskrd_dly = 1'b1;
wire        dskrd_edge;

reg [7:0]   up_down_ctr = 8'd146;

reg [10:0]  adder = 11'd0;

wire        roll_over;
reg         roll_over_dly;
wire        roll_over_edge; 

reg [2:0]   add_rem = 3'd0;

reg [1:0]   leadlag = 2'b0;

reg [3:0]   preg_rem = 4'd0;
reg [3:0]   preg_add = 4'd0;
wire        phase_rem;
wire        phase_add;

reg         dsk_bit = 1'b0;
reg [15:0]  dsk_data = 16'd0;

reg [3:0]	bit_ctr = 4'd0;
reg [3:0]	bit_ptr = 4'd0;
reg [2:0]   bit_ctr8 = 3'd0;

reg [3:0]	creg_rem = 4'd0;
reg [3:0]	creg_add = 4'd0;

wire			ctr_add;
wire			ctr_rem;

reg [15:0]	write_shift = 16'd0;
reg [3:0]	write_ctr = 4'd0;
reg [3:0]   write_ptr = 4'd0;
reg			prev_bit;

wire			write_stb;
reg [3:0]	write_dly = 3'd0;
reg [3:0]	write_tail = 3'd0;
reg			write_bit = 1'd0;
reg			dma_rd;

reg[7:0] _diskByte;
					
assign diskByte = _diskByte;

assign dskrd_edge = _dskrd_dly & ~_dskrd_reg;

assign roll_over = adder[10] & adder[9] & adder[8];
assign roll_over_edge = roll_over_dly & ~roll_over;

assign phase_add = preg_add[0] | preg_add[1] | preg_add[2] | preg_add[3];
assign phase_rem = preg_rem[0] | preg_rem[1] | preg_rem[2] | preg_rem[3];

assign ctr_add = creg_add[0] | creg_add[1] | creg_add[2] | creg_add[3];
assign ctr_rem = creg_rem[0] | creg_rem[1] | creg_rem[2] | creg_rem[3];

reg _diskByteReady;
assign diskByteReady = _diskByteReady; 

reg word_ready = 0;
reg [15:0] word_read;

assign bitdetected = dsk_bit;

// 28mhz version of edge finder, just incase, shouldn't be needed
reg [3:0] read28mhz;


always @(posedge clk)
begin		
	 read28mhz <= {read28mhz[2:0], _dskrd};
	 
	 if (clk7_en) begin
		word_ready <= 0;

		if (reset) begin
			up_down_ctr <= 8'd146;
			_dkwe <= 1'b1;
		end;

				
		if (resetDiskByteReady | reset) _diskByteReady <= 0;
		
		if (selected) begin   // Selected means NOT writing, and selected
			_dkwe <= 1'b1;     // Ensure writing is turned off
			
			// Pause while interface is busy (doesnt seem to be required, but it "sits better" with me)
			if (~pause) begin
				_dskrd_reg <= ~(&read28mhz);
				_dskrd_dly <= _dskrd_reg;

				roll_over_dly <= roll_over;     // adder[10] & adder[9] & adder[8];

				if (dskrd_edge) dsk_bit <= 1'b1;

				if (roll_over_edge)  // roll_over_dly & ~roll_over;
				begin  
				   dsk_bit <= 1'b0;    // reset after this clock
					dsk_data <= dsk_data << 1;
					dsk_data[0] <= dsk_bit;
					bit_ctr <= bit_ctr + 4'h1;
					bit_ctr8 <= bit_ctr8 + 3'h1;
									
					// Output disk word if sync matches and its enabled, or our 16-bit counter overflows
					if ((((dsk_data == ext_floppy_syncword) && (wordsyncEnabled)) || (bit_ptr == bit_ctr)) && (trackrd))
					begin
						word_read <= dsk_data;						
						word_ready <= 1;
					end 

					// Monitor the last byte and push it out to DSKBYTR every 8 bits 
					if (bit_ctr8 == 3'h7)
					begin
						_diskByte <= dsk_data[7:0];
						_diskByteReady <= 1;
					end

					// Re-sync the bit-stream and the DSKBYTR byte if wordsync is enabled and it matches
					if ((dsk_data == ext_floppy_syncword) && (wordsyncEnabled))
					begin
						bit_ptr <= bit_ctr;	
						bit_ctr8 <= 3'h0;	 
					end

					add_rem <= 3'd4;
				end else begin
					add_rem <= 3'd0;
				end

				/*if (phase_rem)
					adder <= adder + 11'd34 + add_rem;
				else if (phase_add)
					adder <= adder + 11'd258 + add_rem;
				else
					adder <= adder + up_down_ctr + add_rem; */
					
				// The original values here were too agressive and caused the weak-bit code in Dungeon Master to fail
				// I suspect they came from the Amiga Replacement Project which came from Patent #4,780,844.
				// As this is an 11-bit adder this makes sense.
				if (phase_rem)
					adder <= adder + 11'd90 + add_rem;
				else if (phase_add)
					adder <= adder + 11'd202 + add_rem;
				else
					adder <= adder + up_down_ctr + add_rem;
					

				// 146 (average) is approx 2.05uS.  133 is approx 1.87us and 159 is approx 2.24us
				// This allows the disk speed to vary between 267 and 320 RPM for PAL (300 is the spec)
				//                                        and 270 and 323 RPM for NTSC
				// +/- 10% rpm is allowed which is roughly these values 
				if ((up_down_ctr != 8'd159) && (ctr_add)) up_down_ctr <= up_down_ctr + 8'd1;
				if ((up_down_ctr != 8'd133) && (ctr_rem)) up_down_ctr <= up_down_ctr - 8'd1;
				if (dskrd_edge) begin
					leadlag[0] <= adder[10];
					case ({leadlag[1:0],adder[10:8]})
						5'b00000: begin creg_add <= 4'b1111; preg_add <= 4'b1111; end
						5'b00001: begin creg_add <= 4'b0111; preg_add <= 4'b0111; end
						5'b00010: begin creg_add <= 4'b0011; preg_add <= 4'b0011; end
						5'b00011: begin creg_add <= 4'b0001; preg_add <= 4'b0001; end

						5'b10000: begin creg_add <= 4'b0111; preg_add <= 4'b1111; end
						5'b10001: begin creg_add <= 4'b0011; preg_add <= 4'b0111; end
						5'b10010: begin creg_add <= 4'b0001; preg_add <= 4'b0011; end
						5'b10011: begin creg_add <= 4'b0000; preg_add <= 4'b0001; end

						5'b01000: begin creg_add <= 4'b0000; preg_add <= 4'b1111; end
						5'b01001: begin creg_add <= 4'b0000; preg_add <= 4'b0111; end
						5'b01010: begin creg_add <= 4'b0000; preg_add <= 4'b0011; end
						5'b01011: begin creg_add <= 4'b0000; preg_add <= 4'b0001; end

						5'b11000: begin creg_add <= 4'b0000; preg_add <= 4'b1111; end
						5'b11001: begin creg_add <= 4'b0000; preg_add <= 4'b0111; end
						5'b11010: begin creg_add <= 4'b0000; preg_add <= 4'b0011; end
						5'b11011: begin creg_add <= 4'b0000; preg_add <= 4'b0001; end


						5'b11100: begin creg_rem <= 4'b0001; preg_rem <= 4'b0001; end
						5'b11101: begin creg_rem <= 4'b0011; preg_rem <= 4'b0011; end
						5'b11110: begin creg_rem <= 4'b0111; preg_rem <= 4'b0111; end
						5'b11111: begin creg_rem <= 4'b1111; preg_rem <= 4'b1111; end

						5'b01100: begin creg_rem <= 4'b0000; preg_rem <= 4'b0001; end
						5'b01101: begin creg_rem <= 4'b0001; preg_rem <= 4'b0011; end
						5'b01110: begin creg_rem <= 4'b0011; preg_rem <= 4'b0111; end
						5'b01111: begin creg_rem <= 4'b0111; preg_rem <= 4'b1111; end

						5'b00100: begin creg_rem <= 4'b0000; preg_rem <= 4'b0001; end
						5'b00101: begin creg_rem <= 4'b0000; preg_rem <= 4'b0011; end
						5'b00110: begin creg_rem <= 4'b0000; preg_rem <= 4'b0111; end
						5'b00111: begin creg_rem <= 4'b0000; preg_rem <= 4'b1111; end

						5'b10100: begin creg_rem <= 4'b0000; preg_rem <= 4'b0001; end
						5'b10101: begin creg_rem <= 4'b0000; preg_rem <= 4'b0011; end
						5'b10110: begin creg_rem <= 4'b0000; preg_rem <= 4'b0111; end
						5'b10111: begin creg_rem <= 4'b0000; preg_rem <= 4'b1111; end
					endcase				
				end else begin
					preg_add <= preg_add >> 1;
					preg_rem <= preg_rem >> 1;
					creg_add <= creg_add >> 1;
					creg_rem <= creg_rem >> 1;
					preg_add[3] <= 1'b0;
					preg_rem[3] <= 1'b0;
					creg_add[3] <= 1'b0;
					creg_rem[3] <= 1'b0;
				end
			end
		end else if (trackwr) begin
			// Prevent write start until the drive interface is ready
			if ((~pause) && (~fifo_empty)) begin
				_dkwe <= 1'b0;				
			end			
		end else if ((_dkwe == 1'b0) && (trackwr == 1'b0) && (ext_floppy_rd_del)) begin
			_dkwe <= 1'b1;   // Turn OFF Writing
		end 
	end // clk7_en
end


/* This EXACTLY matches what paula does when it outputs the floppy data, I measured it!
   Paula does something a little weird. When Write Gate goes low, theres ~5.6us before it starts sending any data. I suspect an internal 3-bit fifo	
	This causes the data to actually lag by three bits, meaning the final three bits get written out AFTER write gate is de-aserted meaning they're always lost.
*/	

reg lastWriting;
reg [6:0] extraBits;
assign _dkweDelay = (extraBits < 7) && (_dkwe && lastWriting);

always @(posedge clk) begin
	if (clk7_en) begin   // 14 clocks is 2uS
	
		lastWriting <= _dkwe;
		
		if (reset) begin
			extraBits <= 0;			
		end else			
		if  (_dkwe && ~lastWriting) begin
			// When _dkwe is deasserted, Paula still has an entire word that needs writing, although to match actual hardware, 
			// the last three don't get written, and _dkwe is de-aserted half way between the remaining 3rd and 4th pulse
			extraBits <= 6'd33;
		end else
		if (_dkwe && extraBits && (write_ctr == 4'd0 || write_ctr == 4'd5)) extraBits<= extraBits-6'd1;   

		if (~_dkwe || extraBits || (_dkwe && ~lastWriting)) begin			

			if (write_ctr == 4'd0) begin
				if (write_ptr == 4'd0) begin
					dma_rd <= 1'b1;
					write_shift <= ext_floppy_tx;    // Copy 16-bits of MFM
				end else begin
					write_shift <= write_shift << 1; // Shift 1 bit left to get to the next bit
				end				
				write_ptr <= write_ptr + 4'd1;      // Inc counter - this is to track each of the 16 
				prev_bit <= write_shift[15];
			
				if (write_shift[15] == 1'b1) begin   
					if (prev_bit == 1'b1) begin       
						case (precomp[1:0])
							2'b00: write_dly <= 3'd0;	//0 ns
							2'b01: write_dly <= 3'd1;	//140 ns
							2'b10: write_dly <= 3'd2;	//280 ns
							2'b11: write_dly <= 3'd4;	//560 ns
						endcase
					end else begin
						write_dly <= 3'd0;
					end
					write_bit <= 1'b1;
				end
			end else
			begin
				dma_rd <= 1'b0;
			end
			
			if (write_bit) begin			
				if (write_dly) begin
					write_dly <= write_dly - 3'd1;
				end else
				begin
					_dkwd <= 0;
					write_tail <= 3'd1;   
					write_bit <= 0;
				end
			end else
			if (write_tail) begin
				write_tail <= write_tail - 3'd1;				 
			end else 
			begin
				_dkwd <= 1;
			end
						
			if (write_ctr == 4'd0) begin
				write_ctr <= 4'd13;
			end else begin
				write_ctr <= write_ctr - 4'd1;
			end
			
		end else begin
		   write_shift[15:13] <= 3'b0;
			write_ctr <= 4'd10;    
			write_ptr <= 4'd15;     
			write_dly <= 3'd0;
			prev_bit <= 0;
			write_tail <= 3'd0;
			dma_rd <= 1'b0;
			_dkwd <= 1'b1;			
		end
	end
end


assign ext_floppy_rx = word_read;		 
assign ext_floppy_wr = word_ready;
assign ext_floppy_sync = word_read == ext_floppy_syncword;

assign syncWordNOW = dsk_data == ext_floppy_syncword;


assign ext_floppy_rd = dma_rd;
assign ext_floppy_rd_del = (write_ptr == 4'd0) && (fifo_empty) && (~_dkwe);   // ensure the last word is written before confirming fifo read complete

endmodule