//Blitter fill logic
//The fill logic module has 2 modes,inclusive fill and exclusive fill.
//Both share the same xor operation but in inclusive fill mode,
//the output of the xor-filler is or-ed with the input data.	


module agnus_blitter_fill
(
	input	ife,					//inclusive fill enable
	input	efe,					//exclusive fill enable
	input	fci,					//fill carry input
	output	fco,					//fill carry output
	input	[15:0]in,				//data in
	output	reg [15:0]out			//data out
);

//local signals
reg		[15:0]carry;

//generate all fill carry's
integer j;
always @(fci or in[0])//least significant bit
	carry[0] = fci ^ in[0];		
always @(in or carry)//rest of bits
	for (j=1;j<=15;j=j+1)
		carry[j] = carry[j-1] ^ in[j];

//fill carry output
assign fco = carry[15];

//fill data output
always @(ife or efe or carry or in)
	if (efe)//exclusive fill
		out[15:0] = carry[15:0];
	else if (ife)//inclusive fill
		out[15:0] = carry[15:0] | in[15:0];
	else//bypass,no filling
		out[15:0] = in[15:0];


endmodule

