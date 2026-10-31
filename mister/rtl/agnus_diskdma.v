//disk dma engine
//DMA cycle allocation is as specified in the HRM
//optionally 4 refresh slots are used for higher transfer speed

module agnus_diskdma
(
	input 	clk,		    		//bus clock
  input clk7_en,
	output	dma,					//true if disk dma engine uses it's cycle
	input	dmal,					//Paula requests dma
	input	dmas,					//Paula special dma
	input	speed,
	input	[8:0] hpos,				//horizontal beam counter (advanced by 4 CCKs)
	output	wr,						//write (disk dma writes to memory)
	input 	[8:1] reg_address_in,	//register address inputs
	output 	[8:1] reg_address_out,	//register address outputs
	input	[15:0] data_in,			//bus data in
	output	reg [20:1] address_out	//chip address out current disk dma pointer
);
//register names and adresses
parameter DSKPTH  = 9'h020;
parameter DSKPTL  = 9'h022;
parameter DSKDAT  = 9'h026;
parameter DSKDATR = 9'h008;

//local signals
wire	[20:1] address_outnew;	//new disk dma pointer
reg		dmaslot;				//indicates if the current slot can be used to transfer data

//--------------------------------------------------------------------------------------

//dma cycle allocation
//nominally disk DMA uses 3 slots: 08, 0A and 0C
//refresh slots: 00, 02, 04 and 06 are used for higher transfer speed
//hint: Agnus hpos counter is advanced by 4 CCK cycles
always @(*)
	case (hpos[8:1])
		8'h04:	 dmaslot = speed;
		8'h06:	 dmaslot = speed;
		8'h08:	 dmaslot = speed;
		8'h0A:	 dmaslot = speed;
		8'h0C:	 dmaslot = 1;
		8'h0E:	 dmaslot = 1;
		8'h10:	 dmaslot = 1;
		default: dmaslot = 0;
	endcase

//dma request
assign dma = dmal & dmaslot & hpos[0];
//write signal
assign wr = ~dmas;

//--------------------------------------------------------------------------------------

//address_out input multiplexer and ALU
assign address_outnew[20:1] = dma ? address_out[20:1]+1'b1 : {data_in[4:0],data_in[15:1]};

//disk pointer control
always @(posedge clk)
  if (clk7_en) begin
  	if (dma || (reg_address_in[8:1] == DSKPTH[8:1]))
  		address_out[20:16] <= address_outnew[20:16];//high 5 bits
  end

always @(posedge clk)
  if (clk7_en) begin
  	if (dma || (reg_address_in[8:1] == DSKPTL[8:1]))
  		address_out[15:1] <= address_outnew[15:1];//low 15 bits
  end

//--------------------------------------------------------------------------------------

//register address output
assign reg_address_out[8:1] = wr ? DSKDATR[8:1] : DSKDAT[8:1];

//--------------------------------------------------------------------------------------


endmodule

