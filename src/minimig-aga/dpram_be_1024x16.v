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

dpram #(10,8) ram_l
(
	.clock(clock),
	.address_a(address_a),
	.data_a(data_a[7:0]),
	.wren_a(byteena_a[0] & wren_a),
	.q_a(q_a[7:0]),
	.address_b(address_b),
	.data_b(data_b[7:0]),
	.wren_b(byteena_b[0] & wren_b),
	.q_b(q_b[7:0])
);

dpram #(10,8) ram_u
(
	.clock(clock),
	.address_a(address_a),
	.data_a(data_a[15:8]),
	.wren_a(byteena_a[1] & wren_a),
	.q_a(q_a[15:8]),
	.address_b(address_b),
	.data_b(data_b[15:8]),
	.wren_b(byteena_b[1] & wren_b),
	.q_b(q_b[15:8])
);

endmodule
