//Blitter minterm function generator
//The minterm function generator takes <ain>,<bin> and <cin> 
//and checks every logic combination against the LF control byte.
//If a combination is marked as 1 in the LF byte,the ouput will
//also be 1,else the output is 0.

module agnus_blitter_minterm
(
	input	[7:0] lf,	//LF control byte
	input	[15:0] ain,	//A channel in
	input	[15:0] bin,	//B channel in
	input	[15:0] cin,	//C channel in
	output	[15:0] out	//function generator output
);

reg		[15:0] mt0;		//minterm 0
reg		[15:0] mt1;		//minterm 1
reg		[15:0] mt2;		//minterm 2
reg		[15:0] mt3;		//minterm 3
reg		[15:0] mt4;		//minterm 4
reg		[15:0] mt5;		//minterm 5
reg		[15:0] mt6;		//minterm 6
reg		[15:0] mt7;		//minterm 7

//Minterm generator for each bit. The code inside the loop 
//describes one bit. The loop is 'unrolled' by the 
//synthesizer to cover all 16 bits in the word.
integer j;
always @(ain or bin or cin or lf)
	for (j=15; j>=0; j=j-1)
	begin
		mt0[j] = ~ain[j] & ~bin[j] & ~cin[j] & lf[0];
		mt1[j] = ~ain[j] & ~bin[j] &  cin[j] & lf[1];
		mt2[j] = ~ain[j] &  bin[j] & ~cin[j] & lf[2];
		mt3[j] = ~ain[j] &  bin[j] &  cin[j] & lf[3];
		mt4[j] =  ain[j] & ~bin[j] & ~cin[j] & lf[4];
		mt5[j] =  ain[j] & ~bin[j] &  cin[j] & lf[5];
		mt6[j] =  ain[j] &  bin[j] & ~cin[j] & lf[6];
		mt7[j] =  ain[j] &  bin[j] &  cin[j] & lf[7];
	end

//Generate function generator output by or-ing all
//minterms together.
assign out = mt0 | mt1 | mt2 | mt3 | mt4 | mt5 | mt6 | mt7;


endmodule		

