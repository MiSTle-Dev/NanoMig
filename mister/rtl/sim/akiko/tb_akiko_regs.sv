// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns / 1ps

module tb_akiko_regs;

initial begin
	#200000 $fatal(1, "tb_akiko_regs: watchdog timeout");
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

wire [15:0] dout_ref;
wire [15:0] dout_dut0;
wire [15:0] dout_dut1;
wire        irq_dut1;

akiko_legacy_ref u_ref (
	.clk(clk),
	.cs(cs), .rd(rd), .wr(wr),
	.addr(addr), .din(din), .dout(dout_ref)
);

akiko #(.NATIVE_CD32(0)) u_dut0 (
	.clk(clk), .reset(reset),
	.cs(cs), .rd(rd), .wr(wr),
	.lds(lds), .uds(uds),
	.addr(addr), .din(din), .dout(dout_dut0),
	.akiko_irq(),
	.dma_req(), .dma_we(), .dma_baddr(), .dma_wbyte(),
	.dma_rbyte(8'h00), .dma_ack(1'b0),
	.hps_cmd_pending(), .hps_cmd_byte(),
	.hps_cmd_pop(1'b0), .hps_cmd_done(1'b0),
	.hps_result_push(1'b0), .hps_result_byte(8'h00), .hps_result_done(1'b0),
	.hps_sec_req(), .hps_sec_status(),
	.hps_sec_push(1'b0), .hps_sec_word(16'h0000), .hps_sec_done(1'b0),
	.hps_rx_busy(),
	.hps_nvr_addr(10'd0),
	.hps_nvr_dout(), .hps_nvr_clear_dirty(1'b0), .hps_nvr_dirty(),
	.nvr_load_addr(10'd0), .nvr_load_din(8'h00), .nvr_load_we(1'b0)
);

akiko #(.NATIVE_CD32(1)) u_dut1 (
	.clk(clk), .reset(reset),
	.cs(cs), .rd(rd), .wr(wr),
	.lds(lds), .uds(uds),
	.addr(addr), .din(din), .dout(dout_dut1),
	.akiko_irq(irq_dut1),
	.dma_req(), .dma_we(), .dma_baddr(), .dma_wbyte(),
	.dma_rbyte(8'h00), .dma_ack(1'b0),
	.hps_cmd_pending(), .hps_cmd_byte(),
	.hps_cmd_pop(1'b0), .hps_cmd_done(1'b0),
	.hps_result_push(1'b0), .hps_result_byte(8'h00), .hps_result_done(1'b0),
	.hps_sec_req(), .hps_sec_status(),
	.hps_sec_push(1'b0), .hps_sec_word(16'h0000), .hps_sec_done(1'b0),
	.hps_rx_busy(),
	.hps_nvr_addr(10'd0),
	.hps_nvr_dout(), .hps_nvr_clear_dirty(1'b0), .hps_nvr_dirty(),
	.nvr_load_addr(10'd0), .nvr_load_din(8'h00), .nvr_load_we(1'b0)
);

localparam [31:0] CDINT_SUBCODE   = 32'h80000000;
localparam [31:0] CDINT_DRIVEXMIT = 32'h40000000;
localparam [31:0] CDINT_DRIVERECV = 32'h20000000;
localparam [31:0] CDINT_RXDMADONE = 32'h10000000;
localparam [31:0] CDINT_TXDMADONE = 32'h08000000;
localparam [31:0] CDINT_PBX       = 32'h04000000;
localparam [31:0] CDINT_OVERFLOW  = 32'h02000000;

localparam [31:0] CFG_PBX    = 32'h08000000;
localparam [31:0] CFG_ENABLE = 32'h04000000;

int checks = 0;
int errs   = 0;

task automatic check16(string name, logic [15:0] expected, logic [15:0] actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected 0x%04h got 0x%04h (t=%0t)", name, expected, actual, $time);
		errs++;
	end
endtask

task automatic check32(string name, logic [31:0] expected, logic [31:0] actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected 0x%08h got 0x%08h (t=%0t)", name, expected, actual, $time);
		errs++;
	end
endtask

task automatic check_b(string name, logic expected, logic actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected %0b got %0b (t=%0t)", name, expected, actual, $time);
		errs++;
	end
endtask

task automatic word_write(input [4:0] a, input [15:0] data);
	@(negedge clk);
	addr = a;
	din  = data;
	cs   = 1;
	rd   = 0;
	wr   = 1;
	uds  = 1;
	lds  = 1;
	@(posedge clk);
	@(negedge clk);
	cs = 0; wr = 0; uds = 0; lds = 0;
endtask

task automatic byte_write(input [5:0] ba, input [7:0] data);
	@(negedge clk);
	addr = ba[5:1];
	cs   = 1;
	rd   = 0;
	wr   = 1;
	if (ba[0] == 1'b0) begin
		uds = 1; lds = 0; din = {data, 8'h00};
	end else begin
		uds = 0; lds = 1; din = {8'h00, data};
	end
	@(posedge clk);
	@(negedge clk);
	cs = 0; wr = 0; uds = 0; lds = 0;
endtask

task automatic word_read(input [4:0] a, output [15:0] r_ref, output [15:0] r_dut0, output [15:0] r_dut1);
	@(negedge clk);
	addr = a;
	cs   = 1;
	rd   = 1;
	wr   = 0;
	uds  = 1;
	lds  = 1;
	#1;
	r_ref  = dout_ref;
	r_dut0 = dout_dut0;
	r_dut1 = dout_dut1;
	@(posedge clk);
	@(negedge clk);
	cs = 0; rd = 0; uds = 0; lds = 0;
endtask

task automatic read_dut1(input [4:0] a, output [15:0] r);
	logic [15:0] tmp_ref, tmp_dut0;
	word_read(a, tmp_ref, tmp_dut0, r);
endtask

logic [15:0] vr, v0, v1;

initial begin
	$display("tb_akiko_regs starting");

	reset = 1;
	repeat (4) @(posedge clk);
	@(negedge clk);
	reset = 0;
	repeat (2) @(posedge clk);

	word_read(5'd0, vr, v0, v1);
	check16("ID@$00 ref==C0CA", 16'hC0CA, vr);
	check16("ID@$00 dut0==ref", vr, v0);
	check16("ID@$00 dut1==ref", vr, v1);

	word_read(5'd1, vr, v0, v1);
	check16("ID@$02 ref==CAFE", 16'hCAFE, vr);
	check16("ID@$02 dut0==ref", vr, v0);
	check16("ID@$02 dut1==ref", vr, v1);

	for (int i = 0; i < 8; i++) begin
		word_write(5'b11100, 16'(i*16'h0101));
	end
	for (int i = 0; i < 16; i++) begin
		word_read(5'b11100, vr, v0, v1);
		check16($sformatf("C2P read[%0d] dut0==ref", i), vr, v0);
		check16($sformatf("C2P read[%0d] dut1==ref", i), vr, v1);
	end

	for (int a = 0; a < 32; a++) begin
		word_write(5'(a), 16'(a*16'h1111));
	end
	for (int a = 0; a < 32; a++) begin
		word_read(5'(a), vr, v0, v1);
		check16($sformatf("addr=%0d dut0==ref", a), vr, v0);
	end

	read_dut1(5'b00010, v1);
	check16("INTREQ hi initial", 16'h0000, v1);
	read_dut1(5'b00011, v1);
	check16("INTREQ lo initial", 16'h0000, v1);

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;

	word_write(5'b00100, 16'hF234);
	word_write(5'b00101, 16'h5678);
	read_dut1(5'b00100, v1);
	check16("INTENA hi after wr (only F2 survives)", 16'hF200, v1);
	read_dut1(5'b00101, v1);
	check16("INTENA lo after wr (masked to 0)", 16'h0000, v1);
	read_dut1(5'b00110, v1);
	check16("INTENA mirror $0C", 16'hF200, v1);
	read_dut1(5'b00111, v1);
	check16("INTENA mirror $0E", 16'h0000, v1);

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	word_write(5'b01000, 16'hABCD);
	word_write(5'b01001, 16'hEF12);
	check32("addressdata after long write", 32'h00CDE000, u_dut1.g_cd.cdrom_addressdata);

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	word_write(5'b01010, 16'hABCD);
	word_write(5'b01011, 16'hEF12);
	check32("addressmisc after long write", 32'h00CDEC00, u_dut1.g_cd.cdrom_addressmisc);

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	u_dut1.g_cd.cdrom_subcodeoffset = 8'hAA;
	u_dut1.g_cd.cdcomtxinx          = 8'hBB;
	u_dut1.g_cd.cdcomrxinx          = 8'hCC;
	@(negedge clk);
	for (int slot = 0; slot < 4; slot++) begin
		automatic logic [4:0] base = 5'(5'b01000 + slot * 2);
		read_dut1(base,        v1);
		check16($sformatf("mirror[%0d] {sub,tx}", slot), 16'hAABB, v1);
		read_dut1(base + 5'd1, v1);
		check16($sformatf("mirror[%0d] {rx,0}",  slot), 16'hCC00, v1);
	end

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	word_write(5'b10010, 16'hFFFF);
	word_write(5'b10011, 16'hFFFF);
	check32("CONFIG after all-ones write", 32'hFF800000, u_dut1.g_cd.cdrom_flags);

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	word_write(5'b10010, 16'h0800);
	check32("CONFIG with PBX enable", 32'h08000000, u_dut1.g_cd.cdrom_flags);

	word_write(5'b10000, 16'h000F);
	check32("PBX after wr 0x000F", 32'h0000000F, {16'h0, u_dut1.g_cd.cdrom_pbx});
	word_write(5'b10000, 16'h00F0);
	check32("PBX after wr 0x00F0 OR-only", 32'h000000FF, {16'h0, u_dut1.g_cd.cdrom_pbx});
	word_write(5'b10000, 16'h0000);
	check32("PBX after wr 0x0000", 32'h000000FF, {16'h0, u_dut1.g_cd.cdrom_pbx});
	word_write(5'b10010, 16'h0000);
	word_write(5'b10000, 16'h0000);
	check32("PBX cleared when CONFIG.PBX off", 32'h0, {16'h0, u_dut1.g_cd.cdrom_pbx});

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	u_dut1.g_cd.cdrom_intreq = CDINT_SUBCODE | CDINT_PBX | CDINT_OVERFLOW;
	@(negedge clk);
	byte_write(6'h18, 8'h00);
	check32("INTREQ SUBCODE cleared by $18 write",
	        CDINT_PBX | CDINT_OVERFLOW, u_dut1.g_cd.cdrom_intreq);

	u_dut1.g_cd.cdrom_intreq = CDINT_TXDMADONE | CDINT_RXDMADONE;
	@(negedge clk);
	byte_write(6'h1D, 8'h42);
	check32("INTREQ TXDMADONE cleared by $1D write",
	        CDINT_RXDMADONE, u_dut1.g_cd.cdrom_intreq);
	check32("txcmp latched", 32'h42, {24'h0, u_dut1.g_cd.cdcomtxcmp});

	u_dut1.g_cd.cdrom_intreq = CDINT_TXDMADONE | CDINT_RXDMADONE;
	@(negedge clk);
	byte_write(6'h1F, 8'h7E);
	check32("INTREQ RXDMADONE cleared by $1F write",
	        CDINT_TXDMADONE, u_dut1.g_cd.cdrom_intreq);
	check32("rxcmp latched", 32'h7E, {24'h0, u_dut1.g_cd.cdcomrxcmp});

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	word_write(5'b10010, 16'h0800);
	u_dut1.g_cd.cdrom_intreq = CDINT_PBX | CDINT_SUBCODE;
	@(negedge clk);
	word_write(5'b10000, 16'h0000);
	check32("INTREQ PBX cleared by $20 write",
	        CDINT_SUBCODE, u_dut1.g_cd.cdrom_intreq);

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	u_dut1.g_cd.cdrom_intreq = CDINT_DRIVEXMIT | CDINT_OVERFLOW;
	@(negedge clk);
	byte_write(6'h28, 8'h99);
	check32("INTREQ DRIVEXMIT cleared by $28 write",
	        CDINT_OVERFLOW, u_dut1.g_cd.cdrom_intreq);
	check32("pio_byte latched", 32'h99, {24'h0, u_dut1.g_cd.pio_byte});

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	u_dut1.g_cd.cdrom_intreq = CDINT_OVERFLOW | CDINT_SUBCODE;
	@(negedge clk);
	word_write(5'b10010, 16'h0400);
	check32("OVERFLOW cleared on ENABLE 0->1",
	        CDINT_SUBCODE, u_dut1.g_cd.cdrom_intreq);

	u_dut1.g_cd.cdrom_intreq = CDINT_OVERFLOW;
	@(negedge clk);
	word_write(5'b10010, 16'h0400);
	check32("OVERFLOW preserved on ENABLE held high",
	        CDINT_OVERFLOW, u_dut1.g_cd.cdrom_intreq);

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	byte_write(6'h28, 8'hA5);
	read_dut1(5'b10100, v1);
	check16("PIO read-back upper byte", 16'hA500, v1);

	byte_write(6'h32, 8'h00);
	byte_write(6'h30, 8'h5A);
	read_dut1(5'b11000, v1);
	check16("NVRAM I/O released bus high", 16'hC000, v1);

	byte_write(6'h32, 8'hC0);
	byte_write(6'h30, 8'h40);
	read_dut1(5'b11000, v1);
	check16("NVRAM I/O master-driven SCL=0 SDA=1", 16'h4000, v1);

	byte_write(6'h32, 8'h3C);
	read_dut1(5'b11001, v1);
	check16("NVRAM DIR read-back", 16'h3C00, v1);

	reset = 1; @(posedge clk); @(negedge clk); reset = 0;
	check_b("IRQ low after reset", 1'b0, irq_dut1);

	word_write(5'b00100, 16'hFF00);
	u_dut1.g_cd.cdrom_intreq = CDINT_SUBCODE;
	#1;
	check_b("IRQ high when intreq & intena set", 1'b1, irq_dut1);

	byte_write(6'h18, 8'h00);
	#1;
	check_b("IRQ low after SUBCODE cleared", 1'b0, irq_dut1);

	u_dut1.g_cd.cdrom_intreq = 32'h01000000;
	u_dut1.g_cd.cdrom_intena = 32'hFF000000;
	#1;
	check_b("IRQ low for out-of-range bit", 1'b0, irq_dut1);

	@(posedge clk);
	$display("============================================");
	if (errs == 0) begin
		$display("PASS: %0d checks", checks);
		$display("============================================");
		$finish;
	end else begin
		$display("FAIL: %0d checks, %0d errors", checks, errs);
		$display("============================================");
		$fatal(1);
	end
end

endmodule
