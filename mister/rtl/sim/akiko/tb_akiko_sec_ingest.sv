// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns / 1ps

module tb_akiko_sec_ingest;

initial begin
	#5000000 $fatal(1, "tb_akiko_sec_ingest: watchdog timeout");
end

logic clk = 0;
initial forever #5 clk = ~clk;

logic reset = 1;

logic        uio_cs     = 0;
logic        uio_cs_sec = 0;
logic        uio_wr     = 0;
logic [15:0] uio_din    = 0;

wire        sec_push_w;
wire [15:0] sec_word_w;
wire        sec_done_w;

akiko #(.NATIVE_CD32(1)) u_dut (
	.clk(clk), .reset(reset),
	.cs(1'b0), .rd(1'b0), .wr(1'b0),
	.lds(1'b0), .uds(1'b0),
	.addr(5'd0), .din(16'h0000), .dout(),
	.akiko_irq(),
	.dma_req(), .dma_we(),
	.dma_baddr(), .dma_wbyte(),
	.dma_rbyte(8'h00), .dma_ack(1'b0), .dma_arm(1'b0),
	.hps_cmd_pending(), .hps_cmd_byte(),
	.hps_cmd_pop(1'b0), .hps_cmd_done(1'b0),
	.hps_result_push(1'b0), .hps_result_byte(8'h00), .hps_result_done(1'b0),
	.hps_sec_req(), .hps_sec_status(),
	.hps_sec_push(sec_push_w),
	.hps_sec_word(sec_word_w),
	.hps_sec_done(sec_done_w),
	.hps_rx_busy(),
	.hps_nvr_addr(10'd0),
	.hps_nvr_dout(), .hps_nvr_clear_dirty(1'b0), .hps_nvr_dirty(),
	.nvr_load_addr(10'd0), .nvr_load_din(8'h00), .nvr_load_we(1'b0),
	.hps_subcode_push(1'b0), .hps_subcode_byte(8'h00), .hps_subcode_done(1'b0)
);

akiko_hps_bridge u_bridge (
	.clk(clk), .reset(reset),
	.uio_cs(uio_cs), .uio_cs_sec(uio_cs_sec),
	.uio_cs_nvr(1'b0), .uio_cs_subcode(1'b0),
	.uio_wr(uio_wr), .uio_rd(1'b0),
	.uio_din(uio_din), .uio_dout(),
	.cmd_pending(1'b0), .cmd_byte(8'h00),
	.cmd_pop(), .cmd_done(),
	.result_push(), .result_byte(), .result_done(),
	.sec_req(1'b0), .sec_status(8'h00),
	.sec_push(sec_push_w), .sec_word(sec_word_w), .sec_done(sec_done_w),
	.subcode_push(), .subcode_byte(), .subcode_done(),
	.nvr_addr(), .nvr_dout(8'h00),
	.nvr_load_din(), .nvr_load_we(),
	.nvr_clear_dirty(), .nvr_done(),
	.nvr_dirty(1'b0), .nvr_dirty_out(),
	.rx_busy(1'b0),
	.req(), .sec_req_out(), .rx_busy_out()
);

int checks = 0;
int errs   = 0;

task automatic check_bit(string name, logic expected, logic actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected %0b got %0b (t=%0t)", name, expected, actual, $time);
		errs++;
	end
endtask

task automatic check8(string name, logic [7:0] expected, logic [7:0] actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected 0x%02h got 0x%02h (t=%0t)", name, expected, actual, $time);
		errs++;
	end
endtask

function automatic [7:0] buf_byte(input int j);
	buf_byte = j[0] ? u_dut.g_cd.sector_buffer[j>>1][15:8]
	                : u_dut.g_cd.sector_buffer[j>>1][7:0];
endfunction

task automatic push_sector(input [7:0] seed, input int gap);
	@(posedge clk);
	uio_cs     <= 1'b1;
	uio_cs_sec <= 1'b1;
	@(posedge clk);
	for (int i = 0; i < 1176; i++) begin
		automatic int lo = 2*i;
		automatic int hi = 2*i + 1;
		uio_din <= {seed + hi[7:0], seed + lo[7:0]};
		uio_wr  <= 1'b1;
		@(posedge clk);
		if (gap > 0) begin
			uio_wr <= 1'b0;
			repeat (gap) @(posedge clk);
		end
	end
	uio_wr  <= 1'b0;
	uio_din <= 16'h0000;
	@(posedge clk);
	uio_cs     <= 1'b0;
	uio_cs_sec <= 1'b0;
	@(posedge clk);
	@(posedge clk);
endtask

task automatic do_reset;
begin
	reset <= 1;
	@(posedge clk); @(posedge clk); @(posedge clk);
	reset <= 0;
	@(posedge clk);
end
endtask

task automatic check_contents(string tag, input [7:0] seed);
begin
	check8({tag, ".byte0"},    seed + 8'd0,   buf_byte(0));
	check8({tag, ".byte1"},    seed + 8'd1,   buf_byte(1));
	check8({tag, ".byte2"},    seed + 8'd2,   buf_byte(2));
	check8({tag, ".byte3"},    seed + 8'd3,   buf_byte(3));
	check8({tag, ".byte100"},  seed + 8'd100, buf_byte(100));
	check8({tag, ".byte101"},  seed + 8'd101, buf_byte(101));
	check8({tag, ".byte1000"}, seed + 8'd232, buf_byte(1000));
	check8({tag, ".byte2000"}, seed + 8'd208, buf_byte(2000));
	check8({tag, ".byte2350"}, seed + 8'd46,  buf_byte(2350));
	check8({tag, ".byte2351"}, seed + 8'd47,  buf_byte(2351));
end
endtask

initial begin
	$display("tb_akiko_sec_ingest starting");
	@(posedge clk);
	do_reset();

	$display("--- Test A: spaced strobes (gap=3) ---");
	push_sector(8'h10, 3);
	check_bit("A.sector_ready", 1'b1, u_dut.g_cd.sector_ready);
	check_contents("A", 8'h10);

	do_reset();

	$display("--- Test B: back-to-back strobes (gap=0) ---");
	push_sector(8'h20, 0);
	check_bit("B.sector_ready", 1'b1, u_dut.g_cd.sector_ready);
	check_contents("B", 8'h20);

	do_reset();

	$display("--- Test C: gap=1 ---");
	push_sector(8'h30, 1);
	check_bit("C.sector_ready", 1'b1, u_dut.g_cd.sector_ready);
	check_contents("C", 8'h30);

	$display("------------------------------------");
	$display("checks=%0d errors=%0d", checks, errs);
	if (errs == 0) $display("tb_akiko_sec_ingest PASS");
	else           $display("tb_akiko_sec_ingest FAIL");
	$finish;
end

endmodule
