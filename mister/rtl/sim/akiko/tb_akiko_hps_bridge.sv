// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns / 1ps

module tb_akiko_hps_bridge;

initial begin
	#500000 $fatal(1, "tb_akiko_hps_bridge: watchdog timeout");
end

logic clk = 0;
initial forever #5 clk = ~clk;

logic        reset = 1;
logic        cs    = 0;
logic        rd    = 0;
logic        wr    = 0;
logic        lds   = 0;
logic        uds   = 0;
logic [5:1]  addr  = 0;
logic [15:0] din   = 0;
wire  [15:0] dout;
wire         irq;

wire        dma_req;
wire        dma_we;
wire [23:0] dma_baddr;
wire  [7:0] dma_wbyte;
logic [7:0] dma_rbyte;
logic       dma_ack;

wire        hps_cmd_pending;
wire  [7:0] hps_cmd_byte;
wire        hps_cmd_pop;
wire        hps_cmd_done;
wire        hps_result_push;
wire  [7:0] hps_result_byte;
wire        hps_result_done;

logic       uio_cs     = 0;
logic       uio_cs_nvr = 0;
logic       uio_wr     = 0;
logic       uio_rd     = 0;
logic [15:0] uio_din   = 0;
wire  [7:0] uio_dout;
wire        uio_req;

wire  [9:0] nvr_addr_w;
wire  [7:0] nvr_din_w;
wire        nvr_we_w;
wire        nvr_clear_dirty_w;
wire        nvr_done_w;
logic [7:0] nvr_dout_drv  = 8'h00;
logic       nvr_dirty_drv = 1'b0;

logic       nvr_done_seen        = 1'b0;
logic       nvr_clear_dirty_seen = 1'b0;
always @(posedge clk) begin
	if (nvr_done_w)        nvr_done_seen        <= 1'b1;
	if (nvr_clear_dirty_w) nvr_clear_dirty_seen <= 1'b1;
end

akiko #(.NATIVE_CD32(1)) u_dut (
	.clk(clk), .reset(reset),
	.cs(cs), .rd(rd), .wr(wr),
	.lds(lds), .uds(uds),
	.addr(addr), .din(din), .dout(dout),
	.akiko_irq(irq),
	.dma_req(dma_req), .dma_we(dma_we),
	.dma_baddr(dma_baddr), .dma_wbyte(dma_wbyte),
	.dma_rbyte(dma_rbyte), .dma_ack(dma_ack),
	.hps_cmd_pending(hps_cmd_pending),
	.hps_cmd_byte(hps_cmd_byte),
	.hps_cmd_pop(hps_cmd_pop),
	.hps_cmd_done(hps_cmd_done),
	.hps_result_push(hps_result_push),
	.hps_result_byte(hps_result_byte),
	.hps_result_done(hps_result_done),
	.hps_sec_req(), .hps_sec_status(),
	.hps_sec_push(1'b0), .hps_sec_word(16'h0000), .hps_sec_done(1'b0),
	.hps_rx_busy(),
	.hps_nvr_addr(10'd0),
	.hps_nvr_dout(), .hps_nvr_clear_dirty(1'b0), .hps_nvr_dirty(),
	.nvr_load_addr(10'd0), .nvr_load_din(8'h00), .nvr_load_we(1'b0)
);

akiko_hps_bridge u_bridge (
	.clk(clk), .reset(reset),
	.uio_cs(uio_cs), .uio_cs_sec(1'b0), .uio_cs_nvr(uio_cs_nvr),
	.uio_wr(uio_wr), .uio_rd(uio_rd),
	.uio_din(uio_din), .uio_dout(uio_dout),
	.cmd_pending(hps_cmd_pending), .cmd_byte(hps_cmd_byte),
	.cmd_pop(hps_cmd_pop), .cmd_done(hps_cmd_done),
	.result_push(hps_result_push), .result_byte(hps_result_byte),
	.result_done(hps_result_done),
	.sec_req(1'b0), .sec_status(8'h00),
	.sec_push(), .sec_word(), .sec_done(),
	.nvr_addr(nvr_addr_w), .nvr_dout(nvr_dout_drv),
	.nvr_load_din(nvr_din_w), .nvr_load_we(nvr_we_w),
	.nvr_clear_dirty(nvr_clear_dirty_w), .nvr_done(nvr_done_w),
	.nvr_dirty(nvr_dirty_drv), .nvr_dirty_out(),
	.rx_busy(1'b0),
	.req(uio_req), .sec_req_out(), .rx_busy_out()
);

localparam [31:0] CDINT_DRIVEXMIT = 32'h40000000;
localparam [31:0] CDINT_RXDMADONE = 32'h10000000;
localparam [31:0] CDINT_TXDMADONE = 32'h08000000;

localparam [31:0] CFG_TXD = 32'h40000000;
localparam [31:0] CFG_RXD = 32'h20000000;

int checks = 0;
int errs   = 0;

task automatic check8(string name, logic [7:0] expected, logic [7:0] actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected 0x%02h got 0x%02h (t=%0t)", name, expected, actual, $time);
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

task automatic bus_write_word(input [5:1] a, input [15:0] data);
	@(posedge clk);
	cs <= 1; wr <= 1; rd <= 0; addr <= a; din <= data; lds <= 1; uds <= 1;
	@(posedge clk);
	cs <= 0; wr <= 0; addr <= 0; din <= 0; lds <= 0; uds <= 0;
endtask

task automatic bus_write_byte_lo(input [5:1] a, input [7:0] data);
	@(posedge clk);
	cs <= 1; wr <= 1; rd <= 0; addr <= a; din <= {8'h0, data}; lds <= 1; uds <= 0;
	@(posedge clk);
	cs <= 0; wr <= 0; addr <= 0; din <= 0; lds <= 0; uds <= 0;
endtask

task automatic bus_write_long(input [5:1] a_hi, input [31:0] data);
	bus_write_word(a_hi,        data[31:16]);
	bus_write_word(a_hi + 5'd1, data[15:0]);
endtask

task automatic set_misc_base(input [23:0] base);
	bus_write_long(5'b01010, {8'h00, base});
endtask

task automatic set_config(input [31:0] flags);
	bus_write_long(5'b10010, flags);
endtask

task automatic write_txcmp(input [7:0] v);
	bus_write_byte_lo(5'b01110, v);
endtask

task automatic write_rxcmp(input [7:0] v);
	bus_write_byte_lo(5'b01111, v);
endtask

logic [7:0] mem [65536];
logic       bfm_in_xfer = 1'b0;

initial begin
	dma_ack   = 0;
	dma_rbyte = 8'h00;
	for (int i = 0; i < 65536; i++) mem[i] = 8'h00;
end

always @(posedge clk) begin
	dma_ack <= 0;
	if (bfm_in_xfer) begin
		if (dma_we) mem[dma_baddr[15:0]] <= dma_wbyte;
		else        dma_rbyte <= mem[dma_baddr[15:0]];
		dma_ack     <= 1'b1;
		bfm_in_xfer <= 1'b0;
	end else if (dma_req && !dma_ack) begin
		bfm_in_xfer <= 1'b1;
	end
end

task automatic uio_begin_read;
	@(posedge clk);
	uio_cs <= 1;
	uio_rd <= 0;
	uio_wr <= 0;
	uio_din <= 0;
	@(posedge clk);
endtask

task automatic uio_begin_write;
	@(posedge clk);
	uio_cs <= 1;
	uio_rd <= 0;
	uio_wr <= 0;
	uio_din <= 0;
	@(posedge clk);
endtask

task automatic uio_end;
	@(posedge clk);
	uio_cs <= 0;
	uio_rd <= 0;
	uio_wr <= 0;
	@(posedge clk);
	@(posedge clk);
endtask

task automatic uio_read_byte(output logic [7:0] b);
	b = uio_dout;
	uio_rd <= 1;
	@(posedge clk);
	uio_rd <= 0;
	@(posedge clk);
endtask

task automatic uio_write_byte(input logic [7:0] b);
	uio_din <= b;
	uio_wr  <= 1;
	@(posedge clk);
	uio_wr  <= 0;
	uio_din <= 0;
endtask

task automatic wait_cmd_pending(input int max_cycles, output int cycles);
	int n;
begin
	n = 0;
	@(posedge clk);
	while (!hps_cmd_pending && n < max_cycles) begin
		@(posedge clk);
		n = n + 1;
	end
	cycles = n;
end
endtask

task automatic wait_rx_done(input int max_cycles, output int cycles);
	int n;
begin
	n = 0;
	@(posedge clk);
	while ((u_dut.g_cd.rx_busy || u_dut.g_cd.cdrom_receive_length != 0) && n < max_cycles) begin
		@(posedge clk);
		n = n + 1;
	end
	cycles = n;
end
endtask

task automatic do_reset;
begin
	reset <= 1;
	@(posedge clk); @(posedge clk); @(posedge clk);
	reset <= 0;
	@(posedge clk);
end
endtask

initial begin
	int cyc;
	logic [7:0] b;

	$display("tb_akiko_hps_bridge starting");
	@(posedge clk);
	do_reset();
	bus_write_long(5'b00100, 32'hFF000000);

	$display("--- Test A: cmd 0x05 LED frames as 3 bytes ---");
	set_misc_base(24'h010000);
	mem[16'h0200] = 8'h05;
	mem[16'h0201] = 8'h80;
	mem[16'h0202] = 8'h7A;
	u_dut.g_cd.cdrom_command_length = 6'd0;
	u_dut.g_cd.cdcomtxinx           = 8'd0;
	set_config(CFG_TXD);
	write_txcmp(8'd3);
	wait_cmd_pending(200, cyc);
	check8 ("A.cmdlen",    8'd3, {2'h0, u_dut.g_cd.cdrom_command_length});
	check_bit("A.pending", 1'b1, hps_cmd_pending);
	check_bit("A.uio_req", 1'b1, uio_req);
	check8 ("A.buf[0]",    8'h05, u_dut.g_cd.cdrom_command_buffer[0]);
	check8 ("A.buf[1]",    8'h80, u_dut.g_cd.cdrom_command_buffer[1]);
	check8 ("A.buf[2]",    8'h7A, u_dut.g_cd.cdrom_command_buffer[2]);

	$display("--- Test B: read command via bridge ---");
	uio_begin_read();
	uio_read_byte(b); check8("B.byte[0]", 8'h05, b);
	uio_read_byte(b); check8("B.byte[1]", 8'h80, b);
	uio_read_byte(b); check8("B.byte[2]", 8'h7A, b);
	uio_end();
	check8 ("B.cmdlen_clear", 8'd0, {2'h0, u_dut.g_cd.cdrom_command_length});
	check_bit("B.pending_clear", 1'b0, hps_cmd_pending);

	$display("--- Test C: write response via bridge ---");
	set_misc_base(24'h020000);
	for (int i = 0; i < 16; i++) mem[16'h0000 + i] = 8'h00;
	u_dut.g_cd.cdcomrxinx = 8'd0;
	set_config(CFG_RXD);
	write_rxcmp(8'd4);
	uio_begin_write();
	uio_write_byte(8'hDE);
	uio_write_byte(8'hAD);
	uio_write_byte(8'hBE);
	uio_write_byte(8'hEF);
	uio_end();
	check8("C.recvlen", 8'd4, {2'h0, u_dut.g_cd.cdrom_receive_length});
	check8("C.buf[0]",  8'hDE, u_dut.g_cd.cdrom_result_buffer[0]);
	check8("C.buf[1]",  8'hAD, u_dut.g_cd.cdrom_result_buffer[1]);
	check8("C.buf[2]",  8'hBE, u_dut.g_cd.cdrom_result_buffer[2]);
	check8("C.buf[3]",  8'hEF, u_dut.g_cd.cdrom_result_buffer[3]);

	$display("--- Test D: RX engine drains response ---");
	wait_rx_done(200, cyc);
	check8("D.mem[0]", 8'hDE, mem[16'h0000]);
	check8("D.mem[1]", 8'hAD, mem[16'h0001]);
	check8("D.mem[2]", 8'hBE, mem[16'h0002]);
	check8("D.mem[3]", 8'hEF, mem[16'h0003]);
	check8("D.rxinx",  8'd4,  u_dut.g_cd.cdcomrxinx);
	check_bit("D.drivexmit", 1'b1, u_dut.g_cd.cdrom_intreq[30]);
	check_bit("D.rxdone",    1'b1, u_dut.g_cd.cdrom_intreq[28]);

	$display("--- Test E: cmd 0x04 frames at 13 bytes ---");
	do_reset();
	bus_write_long(5'b00100, 32'hFF000000);
	set_misc_base(24'h030000);
	mem[16'h0200] = 8'h04;
	for (int i = 1; i <= 11; i++) mem[16'h0200 + i] = i[7:0];
	mem[16'h020C] = 8'hAA;
	u_dut.g_cd.cdrom_command_length = 6'd0;
	u_dut.g_cd.cdcomtxinx           = 8'd0;
	set_config(CFG_TXD);
	write_txcmp(8'd6);
	repeat (60) @(posedge clk);
	check8 ("E1.cmdlen_partial", 8'd6, {2'h0, u_dut.g_cd.cdrom_command_length});
	check_bit("E1.pending_low",  1'b0, hps_cmd_pending);
	write_txcmp(8'd13);
	wait_cmd_pending(200, cyc);
	check8 ("E2.cmdlen_full", 8'd13, {2'h0, u_dut.g_cd.cdrom_command_length});
	check_bit("E2.pending",   1'b1, hps_cmd_pending);

	$display("--- Test F: cmd 0x07 INFO frames at 2 bytes ---");
	do_reset();
	bus_write_long(5'b00100, 32'hFF000000);
	set_misc_base(24'h040000);
	mem[16'h0200] = 8'h07;
	mem[16'h0201] = 8'hF8;
	u_dut.g_cd.cdrom_command_length = 6'd0;
	u_dut.g_cd.cdcomtxinx           = 8'd0;
	set_config(CFG_TXD);
	write_txcmp(8'd2);
	wait_cmd_pending(200, cyc);
	check8 ("F.cmdlen", 8'd2, {2'h0, u_dut.g_cd.cdrom_command_length});
	check_bit("F.pending", 1'b1, hps_cmd_pending);

	$display("--- Test G: back-to-back commands ---");
	uio_begin_read();
	uio_read_byte(b); check8("G.f.byte[0]", 8'h07, b);
	uio_read_byte(b); check8("G.f.byte[1]", 8'hF8, b);
	uio_end();
	check_bit("G.f.pending_clear", 1'b0, hps_cmd_pending);
	mem[16'h0202] = 8'h07;
	mem[16'h0203] = 8'hF8;
	write_txcmp(8'd4);
	wait_cmd_pending(200, cyc);
	check8 ("G.cmdlen2", 8'd2, {2'h0, u_dut.g_cd.cdrom_command_length});
	check_bit("G.pending2", 1'b1, hps_cmd_pending);
	uio_begin_read();
	uio_read_byte(b); check8("G.s.byte[0]", 8'h07, b);
	uio_read_byte(b); check8("G.s.byte[1]", 8'hF8, b);
	uio_end();
	check_bit("G.s.pending_clear", 1'b0, hps_cmd_pending);

	$display("--- Test H: unknown opcode frames at buffer-full ---");
	do_reset();
	bus_write_long(5'b00100, 32'hFF000000);
	set_misc_base(24'h050000);
	for (int i = 0; i < 32; i++) mem[16'h0200 + i] = 8'h0B;
	u_dut.g_cd.cdrom_command_length = 6'd0;
	u_dut.g_cd.cdcomtxinx           = 8'd0;
	set_config(CFG_TXD);
	write_txcmp(8'd16);
	repeat (250) @(posedge clk);
	check_bit("H.pending_partial", 1'b0, hps_cmd_pending);
	check8 ("H.cmdlen_partial", 8'd16, {2'h0, u_dut.g_cd.cdrom_command_length});
	write_txcmp(8'd32);
	wait_cmd_pending(2000, cyc);
	check_bit("H.pending_full", 1'b1, hps_cmd_pending);
	check8 ("H.cmdlen_full", 8'd32, {2'h0, u_dut.g_cd.cdrom_command_length});

	$display("--- Test I: Phase 32.5 NVR sub-channel — write burst protocol ---");
	begin
		nvr_dirty_drv = 1'b1;
		nvr_done_seen        <= 1'b0;
		nvr_clear_dirty_seen <= 1'b0;
		@(posedge clk);

		@(posedge clk); uio_cs <= 1; uio_cs_nvr <= 1;
		@(posedge clk);
		@(posedge clk);
		check_bit("I.nvr_addr_reset_pre", 1'b0, |nvr_addr_w);

		@(posedge clk); uio_wr <= 1; uio_din <= 16'hADDE;
		check_bit("I.nvr_lo_we",   1'b1, nvr_we_w);
		check8   ("I.nvr_lo_din",  8'hDE, nvr_din_w);
		@(posedge clk); uio_wr <= 0;
		check_bit("I.nvr_hi_we",   1'b1, nvr_we_w);
		check8   ("I.nvr_hi_din",  8'hAD, nvr_din_w);
		@(posedge clk);
		check_bit("I.nvr_addr_post0", 1'b1, nvr_addr_w == 10'd2);

		@(posedge clk); uio_wr <= 1; uio_din <= 16'hEFBE;
		@(posedge clk); uio_wr <= 0;
		@(posedge clk);
		check_bit("I.nvr_addr_post1", 1'b1, nvr_addr_w == 10'd4);

		check_bit("I.no_clear_during_write", 1'b0, nvr_clear_dirty_seen);

		@(posedge clk); uio_cs <= 0; uio_cs_nvr <= 0;
		@(posedge clk);
		@(posedge clk);
		check_bit("I.nvr_done_after_write", 1'b1, nvr_done_seen);
		check_bit("I.no_clear_after_write", 1'b0, nvr_clear_dirty_seen);
	end

	$display("--- Test J: Phase 32 NVR sub-channel — read burst auto-clears dirty ---");
	begin
		nvr_dout_drv = 8'h11; nvr_dirty_drv = 1'b1;
		nvr_done_seen        <= 1'b0;
		nvr_clear_dirty_seen <= 1'b0;
		@(posedge clk);

		@(posedge clk); uio_cs <= 1; uio_cs_nvr <= 1;
		@(posedge clk);
		@(posedge clk);

		@(posedge clk); uio_rd <= 1; @(posedge clk); uio_rd <= 0; @(posedge clk);
		@(posedge clk); uio_rd <= 1; @(posedge clk); uio_rd <= 0; @(posedge clk);
		@(posedge clk); uio_rd <= 1; @(posedge clk); uio_rd <= 0; @(posedge clk);
		@(posedge clk); uio_rd <= 1; @(posedge clk); uio_rd <= 0; @(posedge clk);
		check_bit("J.nvr_addr_after_4rd", 1'b1, nvr_addr_w == 10'd4);

		check_bit("J.no_clear_mid_read", 1'b0, nvr_clear_dirty_seen);

		@(posedge clk); uio_cs <= 0; uio_cs_nvr <= 0;
		@(posedge clk);
		@(posedge clk);
		check_bit("J.clear_dirty_at_end", 1'b1, nvr_clear_dirty_seen);
		check_bit("J.nvr_done_after_read", 1'b1, nvr_done_seen);
	end

	$display("------------------------------------");
	$display("checks=%0d errors=%0d", checks, errs);
	if (errs == 0) $display("tb_akiko_hps_bridge PASS");
	else           $display("tb_akiko_hps_bridge FAIL");
	$finish(errs == 0 ? 0 : 1);
end

endmodule
