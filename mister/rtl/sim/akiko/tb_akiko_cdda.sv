// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns / 1ps

module tb_akiko_cdda;

initial begin
	#5000000 $fatal(1, "tb_akiko_cdda: watchdog timeout");
end

logic clk = 0;
initial forever #5 clk = ~clk;

logic        reset_n = 0;

logic        write_pulse = 0;
logic [15:0] din         = 16'h0000;
wire         write_req;
wire         audio_ce;
wire  [15:0] audio_l;
wire  [15:0] audio_r;

cdda #(.CLK_RATE(441000)) dut (
	.CLK    (clk),
	.nRESET (reset_n),
	.WRITE_REQ (write_req),
	.WRITE  (write_pulse),
	.DIN    (din),
	.AUDIO_CE (audio_ce),
	.AUDIO_L (audio_l),
	.AUDIO_R (audio_r)
);

int checks = 0;
int errs   = 0;

task automatic check_eq16(string name, logic [15:0] expected, logic [15:0] actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected 0x%04h got 0x%04h (t=%0t)", name, expected, actual, $time);
		errs++;
	end
endtask

task automatic check_bit(string name, logic expected, logic actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected %0b got %0b (t=%0t)", name, expected, actual, $time);
		errs++;
	end
endtask

task automatic push_half(input [15:0] sample);
	@(posedge clk);
	din         <= sample;
	write_pulse <= 1'b1;
	@(posedge clk);
	write_pulse <= 1'b0;
endtask

task automatic push_pair(input [15:0] left, input [15:0] right);
	push_half(left);
	push_half(right);
endtask

task automatic wait_for_ce_and_capture(output [15:0] cap_l, output [15:0] cap_r);
	@(posedge clk);
	while (!audio_ce) @(posedge clk);
	cap_l = audio_l;
	cap_r = audio_r;
endtask

task automatic count_ce_for(input int cycles, output int n);
	int i;
	n = 0;
	for (i = 0; i < cycles; i++) begin
		@(posedge clk);
		if (audio_ce) n++;
	end
endtask

initial begin
	$display("==== tb_akiko_cdda begin ====");
	force dut.cen_44100_cnt = 32'd0;
	force dut.cen_44100     = 1'b0;
	force dut.AUDIO_CE      = 1'b0;
	force dut.AUDIO_L       = 16'h0000;
	force dut.AUDIO_R       = 16'h0000;
	force dut.DATA          = 16'h0000;

	reset_n = 0;
	repeat (4) @(posedge clk);
	reset_n = 1;
	release dut.cen_44100_cnt;
	release dut.cen_44100;
	release dut.AUDIO_CE;
	release dut.AUDIO_L;
	release dut.AUDIO_R;
	release dut.DATA;

	@(posedge clk);
	@(posedge clk);

	$display("[A] reset state");
	check_bit ("A.write_req asserted after reset", 1'b1, write_req);
	check_eq16("A.audio_l silent after reset",     16'h0000, audio_l);
	check_eq16("A.audio_r silent after reset",     16'h0000, audio_r);

	$display("[B] empty-buffer underflow");
	begin
		int n_ce;
		int n_silent_ce = 0;
		int i;
		for (i = 0; i < 200; i++) begin
			@(posedge clk);
			if (audio_ce) begin
				if (audio_l === 16'h0000 && audio_r === 16'h0000) n_silent_ce++;
				n_ce++;
			end
		end
		check_bit("B.saw multiple CE pulses while empty", 1'b1, (n_ce >= 15));
		check_bit("B.all empty CE pulses silent",         1'b1, (n_silent_ce == n_ce));
	end

	$display("[C] single L/R pair drain");
	push_pair(16'hAAAA, 16'h5555);
	begin
		logic [15:0] cap_l, cap_r;
		wait_for_ce_and_capture(cap_l, cap_r);
		check_eq16("C.audio_l = 0xAAAA",  16'hAAAA, cap_l);
		check_eq16("C.audio_r = 0x5555",  16'h5555, cap_r);
	end
	begin
		logic [15:0] cap_l, cap_r;
		wait_for_ce_and_capture(cap_l, cap_r);
		check_eq16("C.silent after drain (L)", 16'h0000, cap_l);
		check_eq16("C.silent after drain (R)", 16'h0000, cap_r);
	end

	$display("[D] full-sector drain (588 pairs)");
	force dut.cen_44100 = 1'b0;
	begin
		int i;
		for (i = 0; i < 588; i++) begin
			push_pair(16'(i), ~16'(i));
		end
		check_bit("D.write_req still asserted after 1 sector pushed", 1'b1, write_req);
	end
	release dut.cen_44100;

	begin
		int i;
		for (i = 0; i < 588; i++) begin
			logic [15:0] cap_l, cap_r;
			wait_for_ce_and_capture(cap_l, cap_r);
			if (cap_l !== 16'(i) || cap_r !== ~16'(i)) begin
				$display("FAIL D.pair[%0d]: expected (0x%04h,0x%04h) got (0x%04h,0x%04h) (t=%0t)",
					i, 16'(i), ~16'(i), cap_l, cap_r, $time);
				errs++;
				if (errs > 8) i = 588;
			end
			checks++;
		end
	end

	$display("[E] backpressure");
	force dut.cen_44100 = 1'b0;
	begin
		int i;
		for (i = 0; i < 1800; i++) begin
			push_pair(16'h1000 + 16'(i[11:0]), 16'h2000 + 16'(i[11:0]));
		end
		check_bit("E.write_req deasserted when buffer near-full", 1'b0, write_req);
	end
	release dut.cen_44100;

	begin
		int i;
		for (i = 0; i < 600; i++) begin
			logic [15:0] cap_l, cap_r;
			wait_for_ce_and_capture(cap_l, cap_r);
		end
		check_bit("E.write_req reasserted after one-sector drain", 1'b1, write_req);
	end

	$display("==== tb_akiko_cdda end: checks=%0d errs=%0d ====", checks, errs);
	$finish;
end

endmodule
