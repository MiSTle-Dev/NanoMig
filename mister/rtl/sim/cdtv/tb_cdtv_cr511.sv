// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns / 1ps

module tb_cdtv_cr511;

	initial begin
		#200000 $fatal(1, "tb_cdtv_cr511: watchdog timeout");
	end

	int errs = 0;

	logic clk = 1'b0;
	initial forever #5 clk = ~clk;

	logic        reset = 1'b1;
	logic        sel   = 1'b0;
	logic [23:1] addr  = '0;
	logic [15:0] din   = '0;
	wire  [15:0] dout;
	wire         selack;
	logic        rd  = 1'b0;
	logic        hwr = 1'b0;
	logic        lwr = 1'b0;

	logic  [7:0] ac_rom_byte = 8'h00;
	wire   [5:0] ac_rom_addr;
	wire         cdtv_irq;
	wire   [9:0] cdda_volume;

	wire         cmd_in_pending;
	wire   [7:0] cmd_in_byte;
	logic        cmd_in_pop = 1'b0;

	logic        cmd_out_push = 1'b0;
	logic  [7:0] cmd_out_data = 8'h00;

	logic        sec_byte_push = 1'b0;
	logic  [7:0] sec_byte_data = 8'h00;

	logic        subq_push    = 1'b0;
	logic  [7:0] subq_byte    = 8'h00;

	logic        stch_pulse     = 1'b0;
	logic        sten_pulse_ext = 1'b0;
	logic        scor_pulse     = 1'b0;
	logic        sbcp_pulse     = 1'b0;

	wire         trace_we;
	wire  [63:0] trace_data;

	wire         cdtv_dma_req;
	wire         cdtv_dma_we;
	wire  [31:0] cdtv_dma_baddr;
	wire   [7:0] cdtv_dma_wbyte;

	cdtv_bridge u_dut (
		.clk(clk), .reset(reset),
		.sel(sel), .selack(selack),
		.addr(addr), .din(din), .dout(dout),
		.rd(rd), .hwr(hwr), .lwr(lwr),
		.ac_rom_byte(ac_rom_byte), .ac_rom_addr(ac_rom_addr),
		.cdtv_irq(cdtv_irq), .cdda_volume(cdda_volume),
		.cmd_in_pending(cmd_in_pending),
		.cmd_in_byte(cmd_in_byte),
		.cmd_in_pop(cmd_in_pop),
		.cmd_out_push(cmd_out_push),
		.cmd_out_data(cmd_out_data),
		.sec_byte_push(sec_byte_push),
		.sec_byte_data(sec_byte_data),
		.subq_push(subq_push), .subq_byte(subq_byte),
		.stch_pulse(stch_pulse),
		.sten_pulse_ext(sten_pulse_ext),
		.scor_pulse(scor_pulse),
		.sbcp_pulse(sbcp_pulse),
		.cdtv_dma_req(cdtv_dma_req),
		.cdtv_dma_we(cdtv_dma_we),
		.cdtv_dma_baddr(cdtv_dma_baddr),
		.cdtv_dma_wbyte(cdtv_dma_wbyte),
		.cdtv_dma_ack(1'b0),
		.trace_we(trace_we), .trace_data(trace_data)
	);

	task automatic wait_clocks(input int n);
		begin
			for (int i = 0; i < n; i++) @(posedge clk);
		end
	endtask

	task automatic cpu_wr_byte(input [15:0] boff, input [7:0] data,
	                           input bit use_lds);
		begin
			@(posedge clk);
			sel  <= 1'b1;
			addr <= boff[15:1];
			if (use_lds) begin
				din <= {8'h00, data};
				lwr <= 1'b1; hwr <= 1'b0;
			end else begin
				din <= {data, 8'h00};
				lwr <= 1'b0; hwr <= 1'b1;
			end
			@(posedge clk);
			sel <= 1'b0; lwr <= 1'b0; hwr <= 1'b0;
			din <= '0;
			@(posedge clk);
		end
	endtask

	task automatic cpu_rd_word(input [15:0] boff, output [15:0] data);
		begin
			@(posedge clk);
			sel  <= 1'b1;
			addr <= boff[15:1];
			rd   <= 1'b1;
			@(posedge clk);
			data = dout;
			sel <= 1'b0; rd <= 1'b0;
			@(posedge clk);
		end
	endtask

	task automatic pulse_cmd_in_pop;
		begin
			@(posedge clk);
			cmd_in_pop <= 1'b1;
			@(posedge clk);
			cmd_in_pop <= 1'b0;
			@(posedge clk);
		end
	endtask

	task automatic pulse_stch;
		begin
			@(posedge clk);
			stch_pulse <= 1'b1;
			@(posedge clk);
			stch_pulse <= 1'b0;
			@(posedge clk);
		end
	endtask

	function automatic void check(input string label, input bit cond);
		begin
			if (!cond) begin
				$display("FAIL [%0t] %s", $time, label);
				errs++;
			end
		end
	endfunction

	function automatic void check_eq(input string label,
	                                  input [15:0] got, input [15:0] expected);
		begin
			if (got !== expected) begin
				$display("FAIL [%0t] %s: got=%0h expected=%0h", $time, label, got, expected);
				errs++;
			end
		end
	endfunction

	logic [15:0] rdval;

	initial begin
		reset <= 1'b1;
		wait_clocks(8);
		reset <= 1'b0;
		wait_clocks(4);

		check("T1: cmd_in_pending=0 after reset", cmd_in_pending == 1'b0);
		check("T1: cdtv_irq=0 after reset",       cdtv_irq == 1'b0);

		cpu_wr_byte(16'h00A1, 8'h80, 1'b1);
		cpu_wr_byte(16'h00A1, 8'h00, 1'b1);
		check("T2: cmd_in_pending=1 after 2 writes", cmd_in_pending == 1'b1);
		check_eq("T2: cmd_in_byte[0]=0x80", {8'h00, cmd_in_byte}, 16'h0080);

		pulse_cmd_in_pop();
		check_eq("T3: cmd_in_byte[1]=0x00", {8'h00, cmd_in_byte}, 16'h0000);
		pulse_cmd_in_pop();
		check("T3: cmd_in_pending=0 after drain", cmd_in_pending == 1'b0);

		@(posedge clk);
		cmd_out_data <= 8'hAA;
		cmd_out_push <= 1'b1;
		@(posedge clk);
		cmd_out_push <= 1'b0;
		wait_clocks(2);
		cpu_rd_word(16'h00B4, rdval);
		check_eq("T4: mode-0 Port C with reply pending = 0x07",
		         {8'h00, rdval[7:0]}, 16'h0007);

		cpu_rd_word(16'h00A0, rdval);
		check_eq("T5: $A1 read returns 0xAA", {8'h00, rdval[7:0]}, 16'h00AA);
		cpu_rd_word(16'h00A0, rdval);
		check_eq("T5: $A1 sticky returns last_out=0xAA",
		         {8'h00, rdval[7:0]}, 16'h00AA);

		reset <= 1'b1;
		wait_clocks(8);
		reset <= 1'b0;
		wait_clocks(4);
		cpu_wr_byte(16'h00BD, 8'h01, 1'b1);
		wait_clocks(2);
		pulse_stch();
		wait_clocks(2);
		cpu_rd_word(16'h00B4, rdval);
		check_eq("T6: mode-1 Port C after STCH (no mask) = 0x1B",
		         {8'h00, rdval[7:0]}, 16'h001B);

		reset <= 1'b1;
		wait_clocks(8);
		reset <= 1'b0;
		wait_clocks(4);
		cpu_rd_word(16'h00B4, rdval);
		check_eq("T7: mode-0 Port C idle = 0x1F",
		         {8'h00, rdval[7:0]}, 16'h001F);

		cpu_wr_byte(16'h00BD, 8'h01, 1'b1);
		wait_clocks(2);
		cpu_rd_word(16'h00B4, rdval);
		check_eq("T8: mode-1 Port C idle = 0x1F",
		         {8'h00, rdval[7:0]}, 16'h001F);

		cpu_wr_byte(16'h00B7, 8'h5A, 1'b1);
		wait_clocks(2);
		cpu_rd_word(16'h00B6, rdval);
		check_eq("T9: LDS write+read $B7 roundtrip = 0x5A on lower lane",
		         {8'h00, rdval[7:0]}, 16'h005A);
		check_eq("T9: TPI read mirrored on upper lane = 0x5A",
		         {8'h00, rdval[15:8]}, 16'h005A);

		reset <= 1'b1;
		wait_clocks(8);
		reset <= 1'b0;
		wait_clocks(4);
		cpu_wr_byte(16'h00BD, 8'h01, 1'b1);
		wait_clocks(2);
		cpu_wr_byte(16'h0043, 8'h40, 1'b1);
		wait_clocks(4);
		cpu_rd_word(16'h00B4, rdval);
		check_eq("T10: Port C after PREST shows STCH (bit2=0) = 0x1B",
		         {8'h00, rdval[7:0]}, 16'h001B);

		wait_clocks(4);
		if (errs == 0) $display("RUN: PASS (10/10 tests)");
		else           $display("RUN: FAIL (%0d errors)", errs);
		$finish;
	end

endmodule
