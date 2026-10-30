// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns / 1ps

module tb_akiko_nvram;

initial begin
	#500000 $fatal(1, "tb_akiko_nvram: watchdog timeout");
end

logic clk = 0;
initial forever #5 clk = ~clk;

logic reset = 1;
initial begin
	@(posedge clk); @(posedge clk);
	reset = 0;
end

logic scl_master = 1;
logic sda_master = 1;
wire  sda_drive;
wire  bus_scl = scl_master;
wire  bus_sda = sda_master & ~sda_drive;

logic [9:0] host_addr        = 10'd0;
logic       host_clear_dirty = 1'b0;
wire  [7:0] host_dout;
wire        nvram_dirty;

logic [9:0] load_addr        = 10'd0;
logic [7:0] load_din         = 8'h00;
logic       load_we          = 1'b0;

akiko_nvram #(.INIT_FILE("../../init/nvram_init.mif")) dut (
	.clk              (clk),
	.reset            (reset),
	.scl_in           (bus_scl),
	.sda_in           (bus_sda),
	.sda_drive        (sda_drive),
	.host_addr        (host_addr),
	.host_dout        (host_dout),
	.host_clear_dirty (host_clear_dirty),
	.nvram_dirty      (nvram_dirty),
	.load_addr        (load_addr),
	.load_din         (load_din),
	.load_we          (load_we)
);

int errs = 0;
int tests = 0;

task automatic i2c_quarter;
	repeat (8) @(posedge clk);
endtask

task automatic i2c_start;
	scl_master = 1;
	sda_master = 1;
	i2c_quarter();
	sda_master = 0;
	i2c_quarter();
	scl_master = 0;
	i2c_quarter();
endtask

task automatic i2c_stop;
	scl_master = 0;
	sda_master = 0;
	i2c_quarter();
	scl_master = 1;
	i2c_quarter();
	sda_master = 1;
	i2c_quarter();
endtask

task automatic i2c_master_bit (input bit b);
	scl_master = 0;
	sda_master = b;
	i2c_quarter();
	scl_master = 1;
	i2c_quarter();
	scl_master = 0;
	i2c_quarter();
endtask

task automatic i2c_master_recv_bit (output bit b);
	scl_master = 0;
	sda_master = 1;
	i2c_quarter();
	scl_master = 1;
	i2c_quarter();
	b = bus_sda;
	scl_master = 0;
	i2c_quarter();
endtask

task automatic i2c_write (input [7:0] v, output bit ack);
	bit b;
	for (int i = 7; i >= 0; i--) begin
		i2c_master_bit(v[i]);
	end
	i2c_master_recv_bit(b);
	ack = ~b;
endtask

task automatic i2c_read (output [7:0] v, input bit ack);
	bit b;
	v = 0;
	for (int i = 7; i >= 0; i--) begin
		i2c_master_recv_bit(b);
		v[i] = b;
	end
	i2c_master_bit(ack ? 1'b0 : 1'b1);
endtask

task automatic check (input string name, input [7:0] got, input [7:0] want);
	tests++;
	if (got !== want) begin
		$display("FAIL [%s]: got 0x%02h, want 0x%02h", name, got, want);
		errs++;
	end else begin
		$display("PASS [%s]: 0x%02h", name, got);
	end
endtask

task automatic check_bit (input string name, input bit got, input bit want);
	tests++;
	if (got !== want) begin
		$display("FAIL [%s]: got %0d, want %0d", name, got, want);
		errs++;
	end else begin
		$display("PASS [%s]: %0d", name, got);
	end
endtask

initial begin
	bit ack;
	bit [7:0] data;

	@(negedge reset);
	repeat (8) @(posedge clk);

	$display("=== Test 1: single byte round trip @ 0x042 ===");
	i2c_start();
	i2c_write(8'hA0, ack);
	check_bit("dev_w_ack",   ack, 1);
	i2c_write(8'h42, ack);
	check_bit("waddr_ack",   ack, 1);
	i2c_write(8'hAB, ack);
	check_bit("data_w_ack",  ack, 1);
	i2c_stop();

	repeat (4) @(posedge clk);

	i2c_start();
	i2c_write(8'hA0, ack);
	check_bit("dev_w_ack2",  ack, 1);
	i2c_write(8'h42, ack);
	check_bit("waddr_ack2",  ack, 1);
	i2c_start();
	i2c_write(8'hA1, ack);
	check_bit("dev_r_ack",   ack, 1);
	i2c_read(data, 0);
	check ("readback",       data, 8'hAB);
	i2c_stop();

	repeat (4) @(posedge clk);

	$display("=== Test 2: 4-byte sequential @ 0x100 ===");
	i2c_start();
	i2c_write(8'hA2, ack);
	check_bit("seq_dev_ack", ack, 1);
	i2c_write(8'h00, ack);
	check_bit("seq_waddr_ack", ack, 1);
	i2c_write(8'h11, ack);
	i2c_write(8'h22, ack);
	i2c_write(8'h33, ack);
	i2c_write(8'h44, ack);
	i2c_stop();

	repeat (4) @(posedge clk);

	i2c_start();
	i2c_write(8'hA2, ack);
	i2c_write(8'h00, ack);
	i2c_start();
	i2c_write(8'hA3, ack);
	i2c_read(data, 1); check("seq[0]", data, 8'h11);
	i2c_read(data, 1); check("seq[1]", data, 8'h22);
	i2c_read(data, 1); check("seq[2]", data, 8'h33);
	i2c_read(data, 0); check("seq[3]", data, 8'h44);
	i2c_stop();

	repeat (4) @(posedge clk);

	$display("=== Test 3: NACK on bad devaddr 0xB0 ===");
	i2c_start();
	i2c_write(8'hB0, ack);
	check_bit("bad_dev_nack", ack, 0);
	i2c_stop();

	repeat (4) @(posedge clk);

	$display("=== Test 4: high page 0x300 via devaddr 0xA6 ===");
	i2c_start();
	i2c_write(8'hA6, ack);
	i2c_write(8'h00, ack);
	i2c_write(8'h5A, ack);
	i2c_stop();

	repeat (4) @(posedge clk);

	i2c_start();
	i2c_write(8'hA6, ack);
	i2c_write(8'h00, ack);
	i2c_start();
	i2c_write(8'hA7, ack);
	i2c_read(data, 0); check("hi_page",  data, 8'h5A);
	i2c_stop();

	repeat (8) @(posedge clk);

	begin
		bit [7:0] expected[16];
		expected = '{8'h00, 8'h56, 8'hA9, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
		             8'h02, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
		$display("=== Test 5: pre-initialized FlashFile magic @ 0x000 ===");
		i2c_start();
		i2c_write(8'hA0, ack);
		i2c_write(8'h00, ack);
		i2c_start();
		i2c_write(8'hA1, ack);
		for (int i = 0; i < 16; i++) begin
			i2c_read(data, i < 15 ? 1 : 0);
			check($sformatf("init[%0d]", i), data, expected[i]);
		end
		i2c_stop();
	end

	repeat (8) @(posedge clk);

	begin
		bit [7:0] hd;
		$display("=== Test 6: HPS host port + dirty flag ===");

		check_bit("dirty_set_after_i2c", nvram_dirty, 1);

		host_clear_dirty = 1'b1;
		@(posedge clk);
		host_clear_dirty = 1'b0;
		@(posedge clk);
		check_bit("dirty_cleared", nvram_dirty, 0);

		host_addr = 10'h042; @(posedge clk); @(posedge clk);
		check("host_rd_0x042 (Test 1)", host_dout, 8'hAB);

		host_addr = 10'h100; @(posedge clk); @(posedge clk);
		check("host_rd_0x100 (Test 2)", host_dout, 8'h11);
		host_addr = 10'h101; @(posedge clk); @(posedge clk);
		check("host_rd_0x101 (Test 2)", host_dout, 8'h22);
		host_addr = 10'h102; @(posedge clk); @(posedge clk);
		check("host_rd_0x102 (Test 2)", host_dout, 8'h33);
		host_addr = 10'h103; @(posedge clk); @(posedge clk);
		check("host_rd_0x103 (Test 2)", host_dout, 8'h44);

		host_addr = 10'h300; @(posedge clk); @(posedge clk);
		check("host_rd_0x300 (Test 4)", host_dout, 8'h5A);

		host_addr = 10'h000; @(posedge clk); @(posedge clk);
		check("host_rd_0x000 (init)",   host_dout, 8'h00);
		host_addr = 10'h001; @(posedge clk); @(posedge clk);
		check("host_rd_0x001 (init)",   host_dout, 8'h56);

		i2c_start();
		i2c_write(8'hA0, ack);
		i2c_write(8'h10, ack);
		i2c_write(8'hCD, ack);
		i2c_stop();
		repeat (4) @(posedge clk);
		check_bit("dirty_relatched", nvram_dirty, 1);

		host_addr = 10'h010; @(posedge clk); @(posedge clk);
		check("host_rd_0x010 (relatch)", host_dout, 8'hCD);
	end

	repeat (8) @(posedge clk);

	begin
		bit [7:0] hd;
		$display("=== Test 7: load write port (ioctl_download path) ===");

		host_clear_dirty = 1'b1; @(posedge clk);
		host_clear_dirty = 1'b0; @(posedge clk);
		check_bit("dirty_clean_pre_load", nvram_dirty, 0);

		load_addr = 10'h200; load_din = 8'hDE; load_we = 1'b1; @(posedge clk);
		load_addr = 10'h201; load_din = 8'hAD;                 @(posedge clk);
		load_addr = 10'h202; load_din = 8'hBE;                 @(posedge clk);
		load_addr = 10'h203; load_din = 8'hEF;                 @(posedge clk);
		load_we = 1'b0; @(posedge clk);

		host_addr = 10'h200; @(posedge clk); @(posedge clk);
		check("load_rd_0x200", host_dout, 8'hDE);
		host_addr = 10'h201; @(posedge clk); @(posedge clk);
		check("load_rd_0x201", host_dout, 8'hAD);
		host_addr = 10'h202; @(posedge clk); @(posedge clk);
		check("load_rd_0x202", host_dout, 8'hBE);
		host_addr = 10'h203; @(posedge clk); @(posedge clk);
		check("load_rd_0x203", host_dout, 8'hEF);

		check_bit("dirty_unset_after_load", nvram_dirty, 0);

		i2c_start();
		i2c_write(8'hA0, ack);
		i2c_write(8'h50, ack);
		i2c_write(8'h99, ack);
		i2c_stop();
		repeat (4) @(posedge clk);
		check_bit("dirty_set_after_i2c_post_load", nvram_dirty, 1);

		i2c_start();
		i2c_write(8'hA0, ack);
		i2c_write(8'h00, ack);
		i2c_stop();
		i2c_start();
		i2c_write(8'hA4, ack);
		i2c_write(8'h00, ack);
		i2c_start();
		i2c_write(8'hA5, ack);
		i2c_read(hd, 1); check("i2c_rd_0x200", hd, 8'hDE);
		i2c_read(hd, 1); check("i2c_rd_0x201", hd, 8'hAD);
		i2c_read(hd, 1); check("i2c_rd_0x202", hd, 8'hBE);
		i2c_read(hd, 0); check("i2c_rd_0x203", hd, 8'hEF);
		i2c_stop();
	end

	repeat (8) @(posedge clk);

	begin
		bit [7:0] hd;
		$display("=== Test 8: load while reset asserted (domain-decoupling) ===");

		reset = 1'b1;
		@(posedge clk);
		load_addr = 10'h280; load_din = 8'hCA; load_we = 1'b1; @(posedge clk);
		load_addr = 10'h281; load_din = 8'hFE;                 @(posedge clk);
		load_addr = 10'h282; load_din = 8'hBA;                 @(posedge clk);
		load_addr = 10'h283; load_din = 8'hBE;                 @(posedge clk);
		load_we = 1'b0; @(posedge clk);

		reset = 1'b0;
		repeat (8) @(posedge clk);

		host_addr = 10'h280; @(posedge clk); @(posedge clk);
		check("rst_load_rd_0x280", host_dout, 8'hCA);
		host_addr = 10'h281; @(posedge clk); @(posedge clk);
		check("rst_load_rd_0x281", host_dout, 8'hFE);
		host_addr = 10'h282; @(posedge clk); @(posedge clk);
		check("rst_load_rd_0x282", host_dout, 8'hBA);
		host_addr = 10'h283; @(posedge clk); @(posedge clk);
		check("rst_load_rd_0x283", host_dout, 8'hBE);

		i2c_start();
		i2c_write(8'hA4, ack);
		i2c_write(8'h80, ack);
		i2c_start();
		i2c_write(8'hA5, ack);
		i2c_read(hd, 1); check("rst_i2c_rd_0x280", hd, 8'hCA);
		i2c_read(hd, 1); check("rst_i2c_rd_0x281", hd, 8'hFE);
		i2c_read(hd, 1); check("rst_i2c_rd_0x282", hd, 8'hBA);
		i2c_read(hd, 0); check("rst_i2c_rd_0x283", hd, 8'hBE);
		i2c_stop();
	end

	repeat (8) @(posedge clk);

	begin
		bit [7:0] hd;
		bit [7:0] expected;
		int    miscount = 0;
		$display("=== Test 9: 1024-byte sequential load burst ===");

		for (int i = 0; i < 1024; i++) begin
			load_addr = i[9:0];
			load_din  = 8'(i ^ (i >> 3));
			load_we   = 1'b1;
			@(posedge clk);
		end
		load_we = 1'b0;
		@(posedge clk); @(posedge clk);

		for (int i = 0; i < 1024; i++) begin
			host_addr = i[9:0];
			@(posedge clk); @(posedge clk);
			expected = 8'(i ^ (i >> 3));
			if (host_dout !== expected) begin
				if (miscount < 8)
					$display("FAIL [burst @0x%03x]: got 0x%02h, want 0x%02h",
					         i, host_dout, expected);
				miscount++;
			end
		end
		tests++;
		if (miscount) begin
			$display("FAIL [burst_1024]: %0d/1024 mismatched", miscount);
			errs++;
		end else begin
			$display("PASS [burst_1024]: 1024 bytes round-trip");
		end
	end

	repeat (8) @(posedge clk);

	$display("=================================================");
	$display("tb_akiko_nvram: %0d tests, %0d errors", tests, errs);
	$display("=================================================");
	$finish;
end

endmodule
