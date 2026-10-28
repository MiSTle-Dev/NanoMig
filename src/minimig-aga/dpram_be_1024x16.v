module dpram_be_1024x16
(
	input         clock,

	input	  [9:0] address_a,
	input	  [1:0] byteena_a,
	input	 [15:0] data_a,
	input         wren_a,
	output [15:0] q_a,

	input	  [9:0] address_b,
	input	  [1:0] byteena_b,
	input	 [15:0] data_b,
	input	        wren_b,
	output [15:0] q_b
);

DPB dpb_inst (
	.DOA(q_a),
	.DOB(q_b),
	.DIA(data_a),
	.DIB(data_b),
	.BLKSELA(3'b000),
	.BLKSELB(3'b000),
	.ADA({address_a, 2'b00, byteena_a}),
	.ADB({address_b, 2'b00, byteena_b}),
	.WREA(wren_a),
	.WREB(wren_b),
	.CLKA(clock),
	.CLKB(clock),
	.CEA(1'b1),
	.CEB(1'b1),
	.OCEA(1'b0),
	.OCEB(1'b0),
	.RESETA(1'b0),
	.RESETB(1'b0)
);
defparam dpb_inst.READ_MODE0 = 1'b0;
defparam dpb_inst.READ_MODE1 = 1'b0;
defparam dpb_inst.WRITE_MODE0 = 2'b00;
defparam dpb_inst.WRITE_MODE1 = 2'b00;
defparam dpb_inst.BIT_WIDTH_0 = 16;
defparam dpb_inst.BIT_WIDTH_1 = 16;
defparam dpb_inst.BLK_SEL_0 = 3'b000;
defparam dpb_inst.BLK_SEL_1 = 3'b000;
defparam dpb_inst.RESET_MODE = "SYNC";

endmodule
