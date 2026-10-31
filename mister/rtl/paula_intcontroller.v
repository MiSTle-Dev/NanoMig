// interrupt controller //


module paula_intcontroller
(
	input 	clk,		    	//bus clock
  input clk7_en,
	input 	reset,			   	//reset 
	input 	[8:1] reg_address_in,	//register address inputs
	input	[15:0] data_in,		//bus data in
	output	[15:0] data_out,		//bus data out
	input	rxint,				//uart receive interrupt
	input	txint,				//uart transmit interrupt
  input vblint,         // start of video frame
	input	int2,				//level 2 interrupt
	input	int3,				//level 3 interrupt
	input	int6,				//level 6 interrupt
	input	blckint,			//disk block finished interrupt
	input	syncint,			//disk syncword match interrupt
	input	[3:0] audint,		//audio channels 0,1,2,3 interrupts
	output	[3:0] audpen,		//mirror of audio interrupts for audio controller
	output	rbfmirror,			//mirror of serial receive interrupt for uart SERDATR register
	output	reg [2:0] _ipl		//m68k interrupt request
);

//register names and addresses		
parameter INTENAR = 9'h01c;
parameter INTREQR = 9'h01e;
parameter INTENA  = 9'h09a;
parameter INTREQ  = 9'h09c;

//local signals
reg		[14:0] intena;			//int enable write register
reg 	[15:0] intenar;			//int enable read register
reg		[14:0] intreq;			//int request register
reg		[15:0] intreqr;			//int request readback

//rbf mirror out
assign rbfmirror = intreq[11];

//audio mirror out
assign audpen[3:0] = intreq[10:7];

//data_out	multiplexer
assign data_out = intenar | intreqr;

//intena register
always @(posedge clk) begin
  if (clk7_en) begin
  	if (reset)
  		intena <= 0;
  	else if (reg_address_in[8:1]==INTENA[8:1])
  	begin
  		if (data_in[15])
  			intena[14:0] <= intena[14:0] | data_in[14:0];
  		else
  			intena[14:0] <= intena[14:0] & (~data_in[14:0]);	
  	end
  end
end

//intenar register
always @(*) begin
	if (reg_address_in[8:1]==INTENAR[8:1])
		intenar[15:0] = {1'b0,intena[14:0]};
	else if (reg_address_in[8:1]==INTENA[8:1])
		intenar = 16'hffff;
	else
		intenar = 16'd0;
end

//intreqr register
always @(*) begin
	if (reg_address_in[8:1]==INTREQR[8:1])
		intreqr[15:0] = {1'b0,intreq[14:0]};
	else if (reg_address_in[8:1]==INTREQ[8:1])
		intreqr = 16'hffff;
	else
		intreqr = 16'd0;
end

// control all interrupts, intterupts are registered at the rising edge of clk
reg [14:0]tmp;

always @(*) begin
	//check if we are addressed and some bits must change
	//(generate mask tmp[13:0])
	if (reg_address_in[8:1]==INTREQ[8:1])
	begin
		if (data_in[15])
			tmp[14:0] = intreq[14:0] | data_in[14:0];
		else
			tmp[14:0] = intreq[14:0] & (~data_in[14:0]);	
 	end
	else
		tmp[14:0] = intreq[14:0];
end
		
always @(posedge clk) begin
  if (clk7_en) begin
	  if (reset)//synchronous reset
	  	intreq <= 0;
	  else 
	  begin
	  	//transmit buffer empty interrupt
	  	intreq[0] <= tmp[0] | txint;
	  	//diskblock finished
	  	intreq[1] <= tmp[1] | blckint;
	  	//software interrupt
	  	intreq[2] <= tmp[2];
	  	//I/O ports and timers
	  	intreq[3] <= tmp[3] | int2;
	  	//Copper
	  	intreq[4] <= tmp[4];
	  	//start of vertical blank
	  	intreq[5] <= tmp[5] | vblint;
	  	//blitter finished
	  	intreq[6] <= tmp[6] | int3;
	  	//audio channel 0
	  	intreq[7] <= tmp[7] | audint[0];
	  	//audio channel 1
	  	intreq[8] <= tmp[8] | audint[1];
	  	//audio channel 2
	  	intreq[9] <= tmp[9] | audint[2];
	  	//audio channel 3
	  	intreq[10] <= tmp[10] | audint[3];
	  	//serial port receive interrupt
	  	intreq[11] <= tmp[11] | rxint;
	  	//disk sync register matches disk data
	  	intreq[12] <= tmp[12] | syncint;
	  	//external interrupt
	  	intreq[13] <= tmp[13] | int6;
	  	//undocumented interrupt
	  	intreq[14] <= tmp[14];
	  end
  end
end						  

//create m68k interrupt request signals
reg	[14:0]intreqena;
always @(*) begin
	//and int enable and request signals together
	if (intena[14])
		intreqena[14:0] = intreq[14:0] & intena[14:0];
	else
		intreqena[14:0] = 15'b000_0000_0000_0000;	
end

//interrupt priority encoder
always @(posedge clk) begin
  if (clk7_en) begin
	  casez (intreqena[14:0])
	  	15'b1?????????????? : _ipl <= 1;
	  	15'b01????????????? : _ipl <= 1;
	  	15'b001???????????? : _ipl <= 2;
	  	15'b0001??????????? : _ipl <= 2;
	  	15'b00001?????????? : _ipl <= 3;
	  	15'b000001????????? : _ipl <= 3;
	  	15'b0000001???????? : _ipl <= 3;
	  	15'b00000001??????? : _ipl <= 3;
	  	15'b000000001?????? : _ipl <= 4;
	  	15'b0000000001????? : _ipl <= 4;
	  	15'b00000000001???? : _ipl <= 4;
	  	15'b000000000001??? : _ipl <= 5;
	  	15'b0000000000001?? : _ipl <= 6;
	  	15'b00000000000001? : _ipl <= 6;
	  	15'b000000000000001 : _ipl <= 6;
	  	15'b000000000000000 : _ipl <= 7;
	  	default:			  _ipl <= 7;
	  endcase
  end
end


endmodule

