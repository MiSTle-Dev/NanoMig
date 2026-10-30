// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns / 1ps

module tb_chipset_bus_trace;

initial begin
	#500000 $fatal(1, "tb_chipset_bus_trace: watchdog timeout");
end

logic clk = 0;
initial forever #5 clk = ~clk;

logic reset = 1;
initial begin
	@(posedge clk); @(posedge clk);
	reset = 0;
end

logic        write_strobe = 0;
logic [7:0]  reg_addr     = 0;
logic [15:0] data         = 0;
logic [2:0]  src          = 0;
logic [10:0] vpos         = 0;
logic [8:0]  hpos         = 0;
logic        dbwe         = 0;

logic        uio_cs_trace = 0;
logic        uio_rd       = 0;
wire  [7:0]  uio_dout;

chipset_bus_trace dut (
	.clk          (clk),
	.reset        (reset),
	.write_strobe (write_strobe),
	.reg_addr     (reg_addr),
	.data         (data),
	.src          (src),
	.vpos         (vpos),
	.hpos         (hpos),
	.dbwe         (dbwe),
	.uio_cs_trace (uio_cs_trace),
	.uio_rd       (uio_rd),
	.uio_dout     (uio_dout)
);

int errs  = 0;
int tests = 0;

task automatic check (input string name, input [7:0] got, input [7:0] want);
	tests++;
	if (got !== want) begin
		$display("FAIL [%s]: got 0x%02h, want 0x%02h", name, got, want);
		errs++;
	end else begin
		$display("PASS [%s]: 0x%02h", name, got);
	end
endtask

task automatic push (
	input [7:0]  ra,
	input [15:0] d,
	input [2:0]  s,
	input [10:0] v,
	input [8:0]  h,
	input        dw
);
	@(negedge clk);
	reg_addr     = ra;
	data         = d;
	src          = s;
	vpos         = v;
	hpos         = h;
	dbwe         = dw;
	write_strobe = 1'b1;
	@(posedge clk);
	@(negedge clk);
	write_strobe = 1'b0;
endtask

task automatic drain_byte (output [7:0] v);
	@(negedge clk);
	uio_cs_trace = 1'b1;
	uio_rd       = 1'b1;
	@(posedge clk);
	v = uio_dout;
	@(negedge clk);
	uio_rd       = 1'b0;
	uio_cs_trace = 1'b0;
endtask

task automatic drain_entry (output logic [7:0] bytes [8]);
	@(negedge clk);
	uio_cs_trace = 1'b1;
	for (int i = 0; i < 8; i++) begin
		uio_rd = 1'b1;
		@(posedge clk);
		bytes[i] = uio_dout;
		@(negedge clk);
		uio_rd = 1'b0;
	end
	uio_cs_trace = 1'b0;
endtask

initial begin
	logic [7:0] b;
	logic [7:0] entry [8];

	@(negedge reset);
	repeat (4) @(posedge clk);

	$display("=== Test 1: single entry round-trip ===");
	push(8'h70, 16'hBEEF, 3'b000, 11'h5A3, 9'h142, 1'b1);
	repeat (2) @(posedge clk);
	drain_entry(entry);
	check("t1.byte0_data_lo", entry[0], 8'hEF);
	check("t1.byte1_data_hi", entry[1], 8'hBE);
	check("t1.byte2_regaddr", entry[2], 8'h70);
	check("t1.byte3_ctxhi",  entry[3], 8'h85);
	check("t1.byte4_vpos_lo",entry[4], 8'hA3);
	check("t1.byte5_hpos_lo",entry[5], 8'h42);
	check("t1.byte6_hpos_hi",entry[6], 8'h01);
	check("t1.byte7_valid",  entry[7], 8'hFF);

	drain_byte(b);
	check("t1.empty_after_drain", b, 8'h00);

	repeat (4) @(posedge clk);

	$display("=== Test 2: 3-entry FIFO order ===");
	push(8'h7A, 16'h1111, 3'b000, 11'h001, 9'h010, 1'b0);
	push(8'h7A, 16'h2222, 3'b001, 11'h002, 9'h020, 1'b0);
	push(8'h7A, 16'h3333, 3'b010, 11'h003, 9'h030, 1'b1);

	drain_entry(entry);
	check("t2.e1.data_lo", entry[0], 8'h11);
	check("t2.e1.data_hi", entry[1], 8'h11);
	check("t2.e1.regaddr", entry[2], 8'h7A);
	check("t2.e1.ctxhi",   entry[3], 8'h00);
	check("t2.e1.valid",   entry[7], 8'hFF);

	drain_entry(entry);
	check("t2.e2.data_lo", entry[0], 8'h22);
	check("t2.e2.ctxhi",   entry[3], 8'h10);
	check("t2.e2.valid",   entry[7], 8'hFF);

	drain_entry(entry);
	check("t2.e3.data_lo", entry[0], 8'h33);
	check("t2.e3.ctxhi",   entry[3], 8'hA0);
	check("t2.e3.valid",   entry[7], 8'hFF);

	drain_byte(b);
	check("t2.empty", b, 8'h00);

	repeat (4) @(posedge clk);

	$display("=== Test 3: empty-ring sentinel ===");
	for (int i = 0; i < 12; i++) begin
		drain_byte(b);
		if (b !== 8'h00) begin
			$display("FAIL [t3.empty_byte%0d]: got 0x%02h, want 0x00", i, b);
			errs++;
		end
		tests++;
	end

	repeat (4) @(posedge clk);

	$display("=== Test 4: partial-drain byte_idx reset ===");
	push(8'h80, 16'hCAFE, 3'b011, 11'h0FE, 9'h0FE, 1'b0);
	repeat (2) @(posedge clk);

	@(negedge clk);
	uio_cs_trace = 1'b1;
	for (int i = 0; i < 3; i++) begin
		uio_rd = 1'b1;
		@(posedge clk);
		@(negedge clk);
		uio_rd = 1'b0;
	end
	uio_cs_trace = 1'b0;
	@(posedge clk);
	@(posedge clk);

	drain_entry(entry);
	check("t4.byte0_redrain_data_lo", entry[0], 8'hFE);
	check("t4.byte1_redrain_data_hi", entry[1], 8'hCA);
	check("t4.byte7_redrain_valid",   entry[7], 8'hFF);

	drain_byte(b);
	check("t4.empty_after", b, 8'h00);

	repeat (4) @(posedge clk);

	$display("=== Test 5: 500-entry FIFO (no overflow) ===");
	for (int i = 0; i < 500; i++) begin
		push(8'h70 + i[2:0], 16'(i), 3'b000, 11'(i), 9'(i), 1'b0);
	end

	drain_entry(entry);
	check("t5.first.data_lo", entry[0], 8'd0);
	check("t5.first.regaddr", entry[2], 8'h70);
	check("t5.first.valid",   entry[7], 8'hFF);

	for (int i = 0; i < 498; i++) drain_entry(entry);

	drain_entry(entry);
	check("t5.last.data_lo",  entry[0], 8'hF3);
	check("t5.last.data_hi",  entry[1], 8'h01);
	check("t5.last.regaddr",  entry[2], 8'h70 + 8'(8'd499 & 8'h07));
	check("t5.last.valid",    entry[7], 8'hFF);

	drain_byte(b);
	check("t5.empty_after_500", b, 8'h00);

	repeat (4) @(posedge clk);

	$display("=================================================");
	$display("tb_chipset_bus_trace: %0d tests, %0d errors", tests, errs);
	$display("=================================================");
	$finish;
end

endmodule
