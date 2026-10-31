// Copyright 2021 Alexey Melnikov
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
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http:// www.gnu.org/licenses/>.
//
//----------------------------------------------------------------------------------  

module fastchip
(
	input         clk,
	input         cyc,
	input         clk_sys,

	input         reset,

	input         sel,
	output        sel_ack, // 1 when fast chip is used instead of legacy chip
	output        ready,

	input  [23:0] addr,
	input  [15:0] din,
	output [15:0] dout,
	input         lds,
	input         uds,
	input         rnw,
	input         longword,

	//RTG framebuffer control
	output        rtg_ena,
	output [11:0] rtg_hsize,
	output [11:0] rtg_vsize,
	output [4:0]  rtg_format,
	output [31:0] rtg_base,
	output [13:0] rtg_stride,
	output        rtg_pal_clk,
	output [23:0] rtg_pal_dw,
	input  [23:0] rtg_pal_dr,
	output [7:0]  rtg_pal_a,
	output        rtg_pal_wr,

	input         ide_ena,
	output        ide_irq,
	output  [5:0] ide_req,
	input   [4:0] ide_address,
	input         ide_write,
	input  [15:0] ide_writedata,
	input         ide_read,
	output [15:0] ide_readdata,

	output        ide_led,

	output        akiko_irq,

	output        akiko_dma_req,
	output        akiko_dma_we,
	output [23:0] akiko_dma_baddr,
	output  [7:0] akiko_dma_wbyte,
	input   [7:0] akiko_dma_rbyte,
	input         akiko_dma_ack,
	input         akiko_dma_arm,

	input         akiko_uio_cs,
	input         akiko_uio_cs_sec,
	input         akiko_uio_cs_nvr,
	input         akiko_uio_cs_subcode,
	input         akiko_uio_wr,
	input         akiko_uio_rd,
	input  [15:0] akiko_uio_din,
	output [15:0] akiko_uio_dout,
	output        akiko_uio_req,
	output        akiko_uio_sec_req,
	output        akiko_uio_rx_busy,
	output        akiko_uio_nvr_dirty
);

localparam NATIVE_CD32 = 1;

assign sel_ack = sel_akiko  | sel_ide   | sel_rtg   | sel_gayle;
assign ready   = sel_akiko  | ide_ready | rtg_ready;
assign dout    = akiko_dout | ide_dout  | rtg_dout;

wire        sel_akiko = sel && (addr[23:8] == 'hB800);
wire [15:0] akiko_dout;

wire        akiko_hps_cmd_pending;
wire  [7:0] akiko_hps_cmd_byte;
wire        akiko_hps_cmd_pop;
wire        akiko_hps_cmd_done;
wire        akiko_hps_result_push;
wire  [7:0] akiko_hps_result_byte;
wire        akiko_hps_result_done;
wire        akiko_hps_sec_req;
wire  [7:0] akiko_hps_sec_status;
wire        akiko_hps_sec_push;
wire [15:0] akiko_hps_sec_word;
wire        akiko_hps_sec_done;
wire        akiko_hps_subcode_push;
wire  [7:0] akiko_hps_subcode_byte;
wire        akiko_hps_subcode_done;
wire        akiko_hps_rx_busy;
wire  [7:0] akiko_uio_dout_byte;

wire  [9:0] akiko_hps_nvr_addr;
wire  [7:0] akiko_hps_nvr_dout;
wire  [7:0] akiko_hps_nvr_load_din;
wire        akiko_hps_nvr_load_we;
wire        akiko_hps_nvr_clear_dirty;
wire        akiko_hps_nvr_dirty;
wire        akiko_hps_nvr_done;

assign akiko_uio_dout = {8'h0, akiko_uio_dout_byte};

akiko #(.NATIVE_CD32(NATIVE_CD32)) akiko
(
	.clk(clk_sys),
	.reset(reset),
	.cs(sel_akiko && !addr[7:6]),
	.rd(rnw),
	.wr(~rnw & (lds|uds)),
	.lds(lds),
	.uds(uds),
	.addr(addr[5:1]),
	.din(din),
	.dout(akiko_dout),
	.akiko_irq(akiko_irq),
	.dma_req(akiko_dma_req),
	.dma_we(akiko_dma_we),
	.dma_baddr(akiko_dma_baddr),
	.dma_wbyte(akiko_dma_wbyte),
	.dma_rbyte(akiko_dma_rbyte),
	.dma_ack(akiko_dma_ack),
	.dma_arm(akiko_dma_arm),
	.hps_cmd_pending(akiko_hps_cmd_pending),
	.hps_cmd_byte(akiko_hps_cmd_byte),
	.hps_cmd_pop(akiko_hps_cmd_pop),
	.hps_cmd_done(akiko_hps_cmd_done),
	.hps_result_push(akiko_hps_result_push),
	.hps_result_byte(akiko_hps_result_byte),
	.hps_result_done(akiko_hps_result_done),
	.hps_sec_req(akiko_hps_sec_req),
	.hps_sec_status(akiko_hps_sec_status),
	.hps_sec_push(akiko_hps_sec_push),
	.hps_sec_word(akiko_hps_sec_word),
	.hps_sec_done(akiko_hps_sec_done),
	.hps_rx_busy(akiko_hps_rx_busy),
	.hps_nvr_addr(akiko_hps_nvr_addr),
	.hps_nvr_dout(akiko_hps_nvr_dout),
	.hps_nvr_clear_dirty(akiko_hps_nvr_clear_dirty),
	.hps_nvr_dirty(akiko_hps_nvr_dirty),
	.nvr_load_addr(akiko_hps_nvr_addr),
	.nvr_load_din(akiko_hps_nvr_load_din),
	.nvr_load_we(akiko_hps_nvr_load_we),
	.hps_subcode_push(akiko_hps_subcode_push),
	.hps_subcode_byte(akiko_hps_subcode_byte),
	.hps_subcode_done(akiko_hps_subcode_done)
);

akiko_hps_bridge akiko_hps_bridge
(
	.clk(clk_sys),
	.reset(reset),
	.uio_cs(akiko_uio_cs),
	.uio_cs_sec(akiko_uio_cs_sec),
	.uio_cs_nvr(akiko_uio_cs_nvr),
	.uio_cs_subcode(akiko_uio_cs_subcode),
	.uio_wr(akiko_uio_wr),
	.uio_rd(akiko_uio_rd),
	.uio_din(akiko_uio_din),
	.uio_dout(akiko_uio_dout_byte),
	.cmd_pending(akiko_hps_cmd_pending),
	.cmd_byte(akiko_hps_cmd_byte),
	.cmd_pop(akiko_hps_cmd_pop),
	.cmd_done(akiko_hps_cmd_done),
	.result_push(akiko_hps_result_push),
	.result_byte(akiko_hps_result_byte),
	.result_done(akiko_hps_result_done),
	.sec_req(akiko_hps_sec_req),
	.sec_status(akiko_hps_sec_status),
	.sec_push(akiko_hps_sec_push),
	.sec_word(akiko_hps_sec_word),
	.sec_done(akiko_hps_sec_done),
	.subcode_push(akiko_hps_subcode_push),
	.subcode_byte(akiko_hps_subcode_byte),
	.subcode_done(akiko_hps_subcode_done),
	.nvr_addr(akiko_hps_nvr_addr),
	.nvr_dout(akiko_hps_nvr_dout),
	.nvr_load_din(akiko_hps_nvr_load_din),
	.nvr_load_we(akiko_hps_nvr_load_we),
	.nvr_clear_dirty(akiko_hps_nvr_clear_dirty),
	.nvr_done(akiko_hps_nvr_done),
	.nvr_dirty(akiko_hps_nvr_dirty),
	.rx_busy(akiko_hps_rx_busy),
	.req(akiko_uio_req),
	.sec_req_out(akiko_uio_sec_req),
	.rx_busy_out(akiko_uio_rx_busy),
	.nvr_dirty_out(akiko_uio_nvr_dirty)
);

wire sel_ide   = ide_ena && sel && addr[23:16] ==  8'b1101_1010;       //IDE registers at $DA0000 - $DAFFFF	
wire sel_gayle = ide_ena && sel && addr[23:12] == 12'b1101_1110_0001;  //GAYLE registers at $DE1000 - $DE1FFF

reg ide_ack;
always @(posedge clk_sys) ide_ack <= (sel_ide | sel_gayle);

wire ide_ready = ide_ack & (sel_ide | sel_gayle) & ~(ide_nrdy & rnw);

wire [15:0] ide_dout;
wire        ide_nrdy;

gayle gayle
(
	.clk(clk_sys),
	.reset(reset),

	.addr(addr[23:1]),
	.data_in(din),
	.data_out(ide_dout),
	.rd(rnw & uds),
	.wr(~rnw & uds),
	.sel_ide(sel_ide),
	.sel_gayle(sel_gayle),
	.irq(ide_irq),
	.nrdy(ide_nrdy),
	.longword(longword),

	.ide_req(ide_req),
	.ide_address(ide_address),
	.ide_write(ide_write),
	.ide_writedata(ide_writedata),
	.ide_read(ide_read),
	.ide_readdata(ide_readdata),
	
	.led(ide_led)
);

wire        sel_rtg = sel && !sel_akiko && (addr[23:12] == 'hB80);
wire [15:0] rtg_dout;
wire        rtg_ready;

rtg rtg
(
	.clk(clk_sys),
	.reset(reset),

	.aen(sel_rtg),
	.ready(rtg_ready),
	.rd(rnw),
	.wr(~rnw & (lds|uds)),
	.rs(addr[11:1]),
	.data_in(din),
	.data_out(rtg_dout),
	.ena(rtg_ena),
	.hsize(rtg_hsize),
	.vsize(rtg_vsize),
	.format(rtg_format),
	.base(rtg_base),
	.stride(rtg_stride),
	.pal_clk(rtg_pal_clk),
	.pal_dw(rtg_pal_dw),
	.pal_dr(rtg_pal_dr),
	.pal_a(rtg_pal_a),
	.pal_wr(rtg_pal_wr)
);

endmodule
