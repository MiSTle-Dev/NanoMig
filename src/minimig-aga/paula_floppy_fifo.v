//2048 words deep, 16 bits wide, fifo
//data is written into the fifo when wr=1
//reading is more or less asynchronous if you read during the rising edge of clk
//because the output data is updated at the falling edge of the clk
//when rd=1, the next data word is selected 


module paula_floppy_fifo
(
	input		  clk, // bus clock
	input		  clk7_en,
	input		  reset, // reset 
	input [15:0]	  in, // data in
	output reg [15:0] out, // data out
	input		  rd, // read from fifo
	input		  wr, // write to fifo
	output		  empty, // fifo is empty
	output		  full  // fifo is full
);

//local signals and registers
reg 	[15:0] mem [2047:0];	// 2048 words by 16 bit wide fifo memory (for 2 MFM-encoded sectors)
reg	[11:0] in_ptr;		// fifo input pointer
reg	[11:0] out_ptr;		// fifo output pointer
wire	equal;			// lower 11 bits of in_ptr and out_ptr are equal

//fifo write pointer control
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		in_ptr[11:0] <= 0;
  	else if(wr) begin
  		mem[in_ptr[10:0]] <= in;
  		in_ptr[11:0] <= in_ptr[11:0] + 12'd1;
	end
  end
end

// fifo read pointer control
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		out_ptr[11:0] <= 0;
  	else if (rd) begin
  	        out <= mem[out_ptr[10:0]];
  		out_ptr[11:0] <= out_ptr[11:0] + 12'd1;
	end
  end
end

// check lower 11 bits of pointer to generate equal signal
assign equal = (in_ptr[10:0]==out_ptr[10:0]) ? 1'b1 : 1'b0;

assign empty = (equal && (in_ptr[11]==out_ptr[11])) ? 1'b1 : 1'b0;   		
assign full = (equal && (in_ptr[11]!=out_ptr[11])) ? 1'b1 : 1'b0;	

endmodule

