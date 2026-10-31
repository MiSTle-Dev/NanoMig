// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns / 1ps

module tb_akiko_pbx_dma;

initial begin
	#5000000 $fatal(1, "tb_akiko_pbx_dma: watchdog timeout");
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
logic       dma_arm;

wire        hps_sec_req;
wire  [7:0] hps_sec_status;
logic       hps_sec_push = 0;
logic [15:0] hps_sec_word = 0;
logic       hps_sec_done = 0;


akiko #(.NATIVE_CD32(1)) u_dut (
	.clk(clk), .reset(reset),
	.cs(cs), .rd(rd), .wr(wr),
	.lds(lds), .uds(uds),
	.addr(addr), .din(din), .dout(dout),
	.akiko_irq(irq),
	.dma_req(dma_req), .dma_we(dma_we),
	.dma_baddr(dma_baddr), .dma_wbyte(dma_wbyte),
	.dma_rbyte(dma_rbyte), .dma_ack(dma_ack), .dma_arm(dma_arm),
	.hps_cmd_pending(), .hps_cmd_byte(),
	.hps_cmd_pop(1'b0), .hps_cmd_done(1'b0),
	.hps_result_push(1'b0), .hps_result_byte(8'h00), .hps_result_done(1'b0),
	.hps_sec_req(hps_sec_req),
	.hps_sec_status(hps_sec_status),
	.hps_sec_push(hps_sec_push),
	.hps_sec_word(hps_sec_word),
	.hps_sec_done(hps_sec_done),
	.hps_rx_busy(),
	.hps_nvr_addr(10'd0),
	.hps_nvr_dout(), .hps_nvr_clear_dirty(1'b0), .hps_nvr_dirty(),
	.nvr_load_addr(10'd0), .nvr_load_din(8'h00), .nvr_load_we(1'b0),
	.hps_subcode_push(1'b0), .hps_subcode_byte(8'h00), .hps_subcode_done(1'b0)
);

localparam [31:0] CDINT_PBX       = 32'h04000000;
localparam [31:0] CDINT_RXDMADONE = 32'h10000000;
localparam [31:0] CDINT_TXDMADONE = 32'h08000000;

localparam [31:0] CFG_TXD    = 32'h40000000;
localparam [31:0] CFG_RXD    = 32'h20000000;
localparam [31:0] CFG_PBX    = 32'h08000000;
localparam [31:0] CFG_ENABLE = 32'h04000000;

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

task automatic set_addressdata(input [23:0] base);
	bus_write_long(5'b01000, {8'h00, base});
endtask

task automatic set_misc_base(input [23:0] base);
	bus_write_long(5'b01010, {8'h00, base});
endtask

task automatic set_config(input [31:0] flags);
	bus_write_long(5'b10010, flags);
endtask

task automatic write_pbx(input [15:0] mask);
	bus_write_word(5'b10000, mask);
endtask

task automatic write_rxcmp(input [7:0] v);
	bus_write_byte_lo(5'b01111, v);
endtask

logic [7:0] mem [262144];
logic       bfm_in_xfer = 1'b0;

initial begin
	dma_ack   = 0;
	dma_arm   = 0;
	dma_rbyte = 8'h00;
	for (int i = 0; i < 262144; i++) mem[i] = 8'h55;
end

always @(posedge clk) begin
	dma_ack <= 0;
	dma_arm <= 0;
	if (bfm_in_xfer) begin
		if (dma_we) mem[dma_baddr[17:0]] <= dma_wbyte;
		else        dma_rbyte <= mem[dma_baddr[17:0]];
		dma_ack     <= 1'b1;
		bfm_in_xfer <= 1'b0;
	end else if (dma_req && !dma_ack) begin
		bfm_in_xfer <= 1'b1;
		dma_arm     <= 1'b1;
	end
end

task automatic push_sector(input [7:0] seed);
	@(posedge clk);
	for (int i = 0; i < 1176; i++) begin
		automatic int lo = 2*i;
		automatic int hi = 2*i + 1;
		hps_sec_word <= {seed + hi[7:0], seed + lo[7:0]};
		hps_sec_push <= 1'b1;
		@(posedge clk);
	end
	hps_sec_push <= 1'b0;
	hps_sec_word <= 16'h0000;
	@(posedge clk);
	hps_sec_done <= 1'b1;
	@(posedge clk);
	hps_sec_done <= 1'b0;
	@(posedge clk);
endtask

task automatic wait_sector_inc(input [7:0] before_counter,
                                input int max_cycles,
                                output int cycles);
	int n;
begin
	n = 0;
	@(posedge clk);
	while (u_dut.g_cd.cdrom_sector_counter == before_counter && n < max_cycles) begin
		@(posedge clk);
		n = n + 1;
	end
	cycles = n;
end
endtask

task automatic wait_pbx_clear(input int max_cycles, output int cycles);
	int n;
begin
	n = 0;
	@(posedge clk);
	while (u_dut.g_cd.cdrom_pbx != 16'h0 && n < max_cycles) begin
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

task automatic check_slot(string tag,
                          input int slot_base_addr,
                          input [7:0] seed,
                          input [7:0] counter);
	logic [7:0] expected;
	int errs0 = errs;
	begin
		check8({tag, ".byte0"}, 8'h00, mem[slot_base_addr + 0]);
		check8({tag, ".byte1"}, 8'h00, mem[slot_base_addr + 1]);
		check8({tag, ".byte2"}, 8'h00, mem[slot_base_addr + 2]);
		check8({tag, ".byte3"}, counter & 8'h1f, mem[slot_base_addr + 3]);
		check8({tag, ".byte4"},     seed + 8'd4,   mem[slot_base_addr + 4]);
		check8({tag, ".byte100"},   seed + 8'd100, mem[slot_base_addr + 100]);
		check8({tag, ".byte1000"},  seed + 8'd232, mem[slot_base_addr + 1000]);
		check8({tag, ".byte2000"},  seed + 8'd208, mem[slot_base_addr + 2000]);
		check8({tag, ".byte2351"},  seed + 8'd47,  mem[slot_base_addr + 2351]);
		check8({tag, ".zero0"},     8'h00, mem[slot_base_addr + 'h0c00]);
		check8({tag, ".zero1"},     8'h00, mem[slot_base_addr + 'h0c45]);
		check8({tag, ".zero2"},     8'h00, mem[slot_base_addr + 'h0c91]);
		check8({tag, ".gap_lo"},    8'h55, mem[slot_base_addr + 'h0931]);
		check8({tag, ".gap_hi"},    8'h55, mem[slot_base_addr + 'h0c92]);
		check8({tag, ".gap_end"},   8'h55, mem[slot_base_addr + 'h0fff]);
	end
endtask

initial begin
	int cyc;

	$display("tb_akiko_pbx_dma starting");
	@(posedge clk);
	do_reset();
	bus_write_long(5'b00100, 32'hFF000000);

	$display("--- Test A: single sector to slot 0 ---");
	set_addressdata(24'h010000);
	set_config(CFG_ENABLE | CFG_PBX);
	check8("A.counter_init", 8'd0, u_dut.g_cd.cdrom_sector_counter);
	check_bit("A.sec_req_no_pbx", 1'b0, hps_sec_req);
	push_sector(8'h10);
	check_bit("A.ready_after_push", 1'b1, u_dut.g_cd.sector_ready);
	write_pbx(16'h0001);
	check_bit("A.sec_req_low",  1'b0, hps_sec_req);
	wait_pbx_clear(20000, cyc);
	$display("    A: pbx clear in %0d cycles", cyc);
	check_slot("A", 'h10000, 8'h10, 8'd0);
	check8 ("A.pbx_clear", 8'h00, u_dut.g_cd.cdrom_pbx[7:0]);
	check_bit("A.intpbx", 1'b1, u_dut.g_cd.cdrom_intreq[26]);
	check8 ("A.counter1", 8'd1, u_dut.g_cd.cdrom_sector_counter);
	check_bit("A.ready_clear", 1'b0, u_dut.g_cd.sector_ready);

	$display("--- Test B: highest-slot-first ---");
	do_reset();
	bus_write_long(5'b00100, 32'hFF000000);
	for (int i = 'h10000; i < 'h20000; i++) mem[i] = 8'h55;
	set_addressdata(24'h010000);
	set_config(CFG_ENABLE | CFG_PBX);
	push_sector(8'h20);
	write_pbx(16'h8001);
	wait_sector_inc(8'd0, 20000, cyc);
	$display("    B: slot15 done in %0d cycles, pbx=%04h", cyc, u_dut.g_cd.cdrom_pbx);
	check8 ("B.pbx_after_slot15", 8'h01, u_dut.g_cd.cdrom_pbx[7:0]);
	check8 ("B.pbx_hi_clear",     8'h00, u_dut.g_cd.cdrom_pbx[15:8]);
	check_slot("B.slot15", 'h10000 + 15*4096, 8'h20, 8'd0);
	check8 ("B.counter_after_one", 8'd1, u_dut.g_cd.cdrom_sector_counter);
	check_bit("B.sec_req_for_slot0", 1'b1, hps_sec_req);
	push_sector(8'h30);
	wait_pbx_clear(20000, cyc);
	$display("    B: slot0 done in %0d cycles", cyc);
	check_slot("B.slot0", 'h10000, 8'h30, 8'd1);
	check8 ("B.pbx_all_clear", 8'h00, u_dut.g_cd.cdrom_pbx[7:0]);
	check8 ("B.counter2", 8'd2, u_dut.g_cd.cdrom_sector_counter);

	$display("--- Test C: 4 slots, highest-first ---");
	do_reset();
	bus_write_long(5'b00100, 32'hFF000000);
	for (int i = 'h10000; i < 'h20000; i++) mem[i] = 8'h55;
	set_addressdata(24'h010000);
	set_config(CFG_ENABLE | CFG_PBX);
	push_sector(8'h40);
	write_pbx(16'h4112);
	wait_sector_inc(8'd0, 20000, cyc);
	$display("    C: slot14 done in %0d cycles, pbx=%04h", cyc, u_dut.g_cd.cdrom_pbx);
	check_slot("C.slot14", 'h10000 + 14*4096, 8'h40, 8'd0);
	check8("C.pbx_after14_lo", 8'h12, u_dut.g_cd.cdrom_pbx[7:0]);
	check8("C.pbx_after14_hi", 8'h01, u_dut.g_cd.cdrom_pbx[15:8]);
	push_sector(8'h50);
	wait_sector_inc(8'd1, 20000, cyc);
	$display("    C: slot8  done in %0d cycles, pbx=%04h", cyc, u_dut.g_cd.cdrom_pbx);
	check_slot("C.slot8",  'h10000 + 8*4096,  8'h50, 8'd1);
	check8("C.pbx_after8",  8'h12, u_dut.g_cd.cdrom_pbx[7:0]);
	push_sector(8'h60);
	wait_sector_inc(8'd2, 20000, cyc);
	$display("    C: slot4  done in %0d cycles, pbx=%04h", cyc, u_dut.g_cd.cdrom_pbx);
	check_slot("C.slot4",  'h10000 + 4*4096,  8'h60, 8'd2);
	check8("C.pbx_after4",  8'h02, u_dut.g_cd.cdrom_pbx[7:0]);
	push_sector(8'h70);
	wait_pbx_clear(20000, cyc);
	$display("    C: slot1  done in %0d cycles", cyc);
	check_slot("C.slot1",  'h10000 + 1*4096,  8'h70, 8'd3);
	check8("C.counter4", 8'd4, u_dut.g_cd.cdrom_sector_counter);

	$display("--- Test D: ENABLE rising resets counter ---");
	check8("D.counter_pre", 8'd4, u_dut.g_cd.cdrom_sector_counter);
	set_config(CFG_PBX);
	@(posedge clk); @(posedge clk);
	check8("D.counter_after_disable", 8'd4, u_dut.g_cd.cdrom_sector_counter);
	set_config(CFG_ENABLE | CFG_PBX);
	@(posedge clk); @(posedge clk);
	check8("D.counter_after_enable", 8'd0, u_dut.g_cd.cdrom_sector_counter);

	$display("--- Test E: sec_req protocol ---");
	check_bit("E.sec_req_idle", 1'b0, hps_sec_req);
	write_pbx(16'h0008);
	@(posedge clk); @(posedge clk);
	check_bit("E.sec_req_pending", 1'b1, hps_sec_req);
	push_sector(8'h80);
	check_bit("E.sec_req_after_push", 1'b0, hps_sec_req);
	wait_pbx_clear(20000, cyc);
	$display("    E: slot3 done in %0d cycles", cyc);
	check_slot("E.slot3", 'h10000 + 3*4096, 8'h80, 8'd0);
	check_bit("E.sec_req_after_done", 1'b0, hps_sec_req);
	check8("E.counter5", 8'd1, u_dut.g_cd.cdrom_sector_counter);

	$display("--- Test F: RX preempts PBX ---");
	do_reset();
	bus_write_long(5'b00100, 32'hFF000000);
	for (int i = 'h10000; i < 'h20000; i++) mem[i] = 8'h55;
	for (int i = 'h02000; i < 'h02010; i++) mem[i] = 8'h00;
	set_addressdata(24'h010000);
	set_misc_base(24'h002000);
	set_config(CFG_ENABLE | CFG_PBX | CFG_RXD);
	u_dut.g_cd.cdrom_result_buffer[0] = 8'hCA;
	u_dut.g_cd.cdrom_result_buffer[1] = 8'hFE;
	u_dut.g_cd.cdrom_result_buffer[2] = 8'hBA;
	u_dut.g_cd.cdrom_result_buffer[3] = 8'hBE;
	u_dut.g_cd.cdcomrxinx           = 8'd0;
	push_sector(8'hA0);
	write_pbx(16'h0001);
	repeat (300) @(posedge clk);
	check_bit("F.pbx_busy_pre", 1'b1, u_dut.g_cd.pbx_busy);
	$display("    F.pre: rb[0]=%02h rb[1]=%02h reclen=%0d rxinx=%0d rxcmp=%0d flags=%08h",
	         u_dut.g_cd.cdrom_result_buffer[0], u_dut.g_cd.cdrom_result_buffer[1],
	         u_dut.g_cd.cdrom_receive_length, u_dut.g_cd.cdcomrxinx,
	         u_dut.g_cd.cdcomrxcmp, u_dut.g_cd.cdrom_flags);
	u_dut.g_cd.cdrom_receive_length = 6'd4;
	write_rxcmp(8'd4);
	$display("    F.post-rxcmp: reclen=%0d rxcmp=%0d delay=%0d",
	         u_dut.g_cd.cdrom_receive_length, u_dut.g_cd.cdcomrxcmp,
	         u_dut.g_cd.rx_dma_delay);
	wait_rx_done(2000, cyc);
	$display("    F: RX done in %0d cycles  rxinx=%0d reclen=%0d mem2000=%02h",
	         cyc, u_dut.g_cd.cdcomrxinx, u_dut.g_cd.cdrom_receive_length, mem['h02000]);
	check8("F.mem_rx0", 8'hCA, mem['h02000]);
	check8("F.mem_rx1", 8'hFE, mem['h02001]);
	check8("F.mem_rx2", 8'hBA, mem['h02002]);
	check8("F.mem_rx3", 8'hBE, mem['h02003]);
	wait_pbx_clear(20000, cyc);
	$display("    F: pbx clear in %0d cycles", cyc);
	check_slot("F.slot0", 'h10000, 8'hA0, 8'd0);

	$display("--- Test G: TX gated off during PBX ---");
	do_reset();
	bus_write_long(5'b00100, 32'hFF000000);
	for (int i = 'h10000; i < 'h20000; i++) mem[i] = 8'h55;
	set_addressdata(24'h010000);
	set_misc_base(24'h003000);
	mem['h03200] = 8'h99;
	mem['h03201] = 8'h66;
	set_config(CFG_ENABLE | CFG_PBX | CFG_TXD);
	bus_write_byte_lo(5'b01110, 8'd2);
	push_sector(8'hB0);
	write_pbx(16'h0001);
	wait_pbx_clear(20000, cyc);
	$display("    G: pbx clear in %0d cycles", cyc);
	check8("G.cmdlen_zero", 8'd0, {2'h0, u_dut.g_cd.cdrom_command_length});
	check8("G.txinx_zero",  8'd0, u_dut.g_cd.cdcomtxinx);
	check_slot("G.slot0", 'h10000, 8'hB0, 8'd0);

	$display("------------------------------------");
	$display("checks=%0d errors=%0d", checks, errs);
	if (errs == 0) $display("tb_akiko_pbx_dma PASS");
	else           $display("tb_akiko_pbx_dma FAIL");
	$finish(errs == 0 ? 0 : 1);
end

endmodule
