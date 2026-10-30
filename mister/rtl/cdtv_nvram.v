// Copyright 2026 (CDTV native-mode bridge)
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

module cdtv_nvram
#(
	parameter ADDR_W = 14
)
(
	input             clk,
	input             reset,

	input             sel,
	input      [23:1] addr,
	input      [15:0] din,
	output     [15:0] dout,
	input             rd,
	input             hwr,
	input             lwr,

	input  [ADDR_W-1:0] hps_load_addr,
	input         [7:0] hps_load_din,
	input               hps_load_we,

	input  [ADDR_W-1:0] hps_save_addr,
	output        [7:0] hps_save_dout,

	output reg        dirty = 1'b0,
	input             clear_dirty
);

localparam WORD_W = ADDR_W - 1;

wire [WORD_W-1:0] cpu_addr    = addr[ADDR_W-1:1];

wire              hps_byte    = hps_load_addr[0];
wire [WORD_W-1:0] hps_addr    = hps_load_we ? hps_load_addr[ADDR_W-1:1] : hps_save_addr[ADDR_W-1:1];

wire [7:0] save_q_hi, save_q_lo;

dpram #(WORD_W,8) nvram_hi (
	.clock    (clk),
	.address_a(cpu_addr),
	.data_a   (din[15:8]),
	.wren_a   (sel & hwr),
	.q_a      (dout[15:8]),
	.address_b(hps_addr),
	.data_b   (hps_load_din),
	.wren_b   (hps_load_we & ~hps_byte),
	.q_b      (save_q_hi)
);

dpram #(WORD_W,8) nvram_lo (
	.clock    (clk),
	.address_a(cpu_addr),
	.data_a   (din[7:0]),
	.wren_a   (sel & lwr),
	.q_a      (dout[7:0]),
	.address_b(hps_addr),
	.data_b   (hps_load_din),
	.wren_b   (hps_load_we & hps_byte),
	.q_b      (save_q_lo)
);

assign hps_save_dout = hps_save_addr[0] ? save_q_lo : save_q_hi;

always @(posedge clk) begin
	if (sel & (hwr | lwr)) dirty <= 1'b1;
	else if (clear_dirty)  dirty <= 1'b0;
end

endmodule
