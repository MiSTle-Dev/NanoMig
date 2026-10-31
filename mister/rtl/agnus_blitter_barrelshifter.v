//Blitter barrel shifter
//This module can shift 0-15 positions to the right (normal mode) or to the left (descending mode).
//Multipliers are used to save logic.


module agnus_blitter_barrelshifter
(
	input	desc,			// select descending mode (shift to the left)
	input	[3:0] shift,	// shift value (0 to 15)
	input 	[15:0] new_val,		// barrel shifter data in
	input 	[15:0] old_val,		// barrel shifter data in
	output	[15:0] out		// barrel shifter data out
);

wire [35:0] shifted_new;	// shifted new data
wire [35:0] shifted_old;	// shifted old data
reg  [17:0] shift_onehot;	// one-hot shift value for multipliers

//one-hot shift value encoding
always @(desc or shift)
	case ({desc,shift[3:0]})
		5'h00 : shift_onehot = 18'h10000;
		5'h01 : shift_onehot = 18'h08000;
		5'h02 : shift_onehot = 18'h04000;
		5'h03 : shift_onehot = 18'h02000;
		5'h04 : shift_onehot = 18'h01000;
		5'h05 : shift_onehot = 18'h00800;
		5'h06 : shift_onehot = 18'h00400;
		5'h07 : shift_onehot = 18'h00200;
		5'h08 : shift_onehot = 18'h00100;
		5'h09 : shift_onehot = 18'h00080;
		5'h0A : shift_onehot = 18'h00040;
		5'h0B : shift_onehot = 18'h00020;
		5'h0C : shift_onehot = 18'h00010;
		5'h0D : shift_onehot = 18'h00008;
		5'h0E : shift_onehot = 18'h00004;
		5'h0F : shift_onehot = 18'h00002;
		5'h10 : shift_onehot = 18'h00001;
		5'h11 : shift_onehot = 18'h00002;
		5'h12 : shift_onehot = 18'h00004;
		5'h13 : shift_onehot = 18'h00008;
		5'h14 : shift_onehot = 18'h00010;
		5'h15 : shift_onehot = 18'h00020;
		5'h16 : shift_onehot = 18'h00040;
		5'h17 : shift_onehot = 18'h00080;
		5'h18 : shift_onehot = 18'h00100;
		5'h19 : shift_onehot = 18'h00200;
		5'h1A : shift_onehot = 18'h00400;
		5'h1B : shift_onehot = 18'h00800;
		5'h1C : shift_onehot = 18'h01000;
		5'h1D : shift_onehot = 18'h02000;
		5'h1E : shift_onehot = 18'h04000;
		5'h1F : shift_onehot = 18'h08000;
 	endcase

/*
MULT18X18 multiplier_1
(
	.dataa({2'b00,new_val[15:0]}),  // 18-bit multiplier input
	.datab(shift_onehot),     	// 18-bit multiplier input
	.result(shifted_new)			// 36-bit multiplier output
);
*/
assign shifted_new = ({2'b00,new_val[15:0]})*shift_onehot;

/*
MULT18X18 multiplier_2
(
	.dataa({2'b00,old_val[15:0]}),	// 18-bit multiplier input
	.datab(shift_onehot),		// 18-bit multiplier input
	.result(shifted_old)			// 36-bit multiplier output
);
*/
assign shifted_old = ({2'b00,old_val[15:0]})*shift_onehot;

assign out = desc ? shifted_new[15:0] | shifted_old[31:16] : shifted_new[31:16] | shifted_old[15:0];


endmodule

