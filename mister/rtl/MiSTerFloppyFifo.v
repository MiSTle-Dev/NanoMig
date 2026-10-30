// Based on the paula_floppy_fifo, but only 4 words in size. Ideally it should be 3 to be 100% perfect, but 4 is easier :-p

module MiSTerFloppyFifo
(
	input 	clk,		    	//bus clock
  input clk7_en,
	input 	reset,			   	//reset 
	input	[15:0] in,			//data in
	output	reg [15:0] out,	//data out
	input	rd,					//read from fifo
	input	wr,					//write to fifo
	output	reg empty,			//fifo is empty
	output	full				//fifo is full
	//,output	[2:0] cnt       // number of entries in FIFO
);

//local signals and registers
reg 	[15:0] mem [3:0];		// 4 words (should be 3 really)
reg		[2:0] in_ptr;		//fifo input pointer
reg		[2:0] out_ptr;		//fifo output pointer
wire	equal;					//lower 2 bits of in_ptr and out_ptr are equal


// count of FIFO entries
//assign cnt = in_ptr - out_ptr;

//main fifo memory (implemented using synchronous block ram)
always @(posedge clk) begin
  if (clk7_en) begin
  	if (wr)
  		mem[in_ptr[1:0]] <= in;
  end
end

always @(posedge clk) begin
  if (clk7_en) begin
  	out=mem[out_ptr[1:0]];
  end
end

//fifo write pointer control
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		in_ptr[2:0] <= 0;
  	else if(wr)
  		in_ptr[2:0] <= in_ptr[2:0] + 3'd1;
  end
end

// fifo read pointer control
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		out_ptr[2:0] <= 0;
  	else if (rd)
  		out_ptr[2:0] <= out_ptr[2:0] + 3'd1;
  end
end

// check lower 2 bits of pointer to generate equal signal
assign equal = (in_ptr[1:0]==out_ptr[1:0]) ? 1'b1 : 1'b0;

// assign output flags, empty is delayed by one clock to handle ram delay
always @(posedge clk) begin
  if (clk7_en) begin
  	if (equal && (in_ptr[2]==out_ptr[2]))
  		empty <= 1'b1;
  	else
  		empty <= 1'b0;
  end
end
		
assign full = (equal && (in_ptr[2]!=out_ptr[2])) ? 1'b1 : 1'b0;	


endmodule
