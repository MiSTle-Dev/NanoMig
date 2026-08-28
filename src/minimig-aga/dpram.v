// dpram.v
//
// Generic true dual port ram with synchronous (registered) reads on both
// ports, replacing the altera_mf based bram.vhd of Minimig-AGA_MiSTer for
// the cpu cache. Both ports may write. The read data register keeps its
// value during a write on the same port ("normal" write mode of the Gowin
// DPB block ram, which is the template Gowin's synthesis infers). The cache
// never reads and writes through the same port in the same cycle.

module dpram #(
	parameter addr_width = 8,
	parameter data_width = 8
) (
	input                       clock,

	input      [addr_width-1:0] address_a,
	input      [data_width-1:0] data_a,
	input                       wren_a,
	output reg [data_width-1:0] q_a,

	input      [addr_width-1:0] address_b,
	input      [data_width-1:0] data_b,
	input                       wren_b,
	output reg [data_width-1:0] q_b
);

reg [data_width-1:0] mem [0:(1<<addr_width)-1];

always @(posedge clock) begin
	if (wren_a)
		mem[address_a] <= data_a;
	else
		q_a <= mem[address_a];
end

always @(posedge clock) begin
	if (wren_b)
		mem[address_b] <= data_b;
	else
		q_b <= mem[address_b];
end

endmodule
