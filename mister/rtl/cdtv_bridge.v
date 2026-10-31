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

module cdtv_bridge
(
	input             clk,
	input             reset,

	input             sel,
	output            selack,
	input      [23:1] addr,
	input      [15:0] din,
	output     [15:0] dout,
	input             rd,
	input             hwr,
	input             lwr,

	output            cdtv_irq,

	output      [9:0] cdda_volume,
	output            cdda_volume_valid,

	input             uio_cs,
	input             uio_cs_sec,
	input             uio_cs_stch,
	input             uio_cs_nvr,
	input             uio_cs_card,
	input             uio_wr,
	input             uio_rd,
	input      [15:0] uio_din,
	output     [15:0] uio_dout,
	output            uio_req,

	output     [13:0] nvr_addr,
	input       [7:0] nvr_dout,
	output      [7:0] nvr_load_din,
	output            nvr_load_we,
	output            nvr_clear_dirty,

	output     [12:0] card_addr,
	input       [7:0] card_dout,
	output      [7:0] card_load_din,
	output            card_load_we,
	output            card_clear_dirty,

	input             subq_push,
	input       [7:0] subq_byte,

	input             sten_pulse_ext,
	input             scor_pulse,
	input             sbcp_pulse,

	output            cdtv_dma_req,
	output            cdtv_dma_we,
	output     [31:0] cdtv_dma_baddr,
	output      [7:0] cdtv_dma_wbyte,
	input             cdtv_dma_ack
);

localparam CNTR_TCEN_BIT  = 3'd7;
localparam CNTR_PREST_BIT = 3'd6;
localparam CNTR_PDMD_BIT  = 3'd5;
localparam CNTR_INTEN_BIT = 3'd4;
localparam CNTR_DDIR_BIT  = 3'd3;

localparam ISTR_INTS_BIT  = 3'd6;
localparam ISTR_E_INT_BIT = 3'd5;
localparam ISTR_INT_P_BIT = 3'd4;
localparam ISTR_FE_FLG_B  = 3'd0;

reg  [7:0] istr;
reg  [7:0] cntr;
reg [31:0] wtc;
reg [31:0] acr;
reg        dmac_dma;
reg        prst_pulse;
reg        dma_complete_pulse;
reg        dma_complete_armed;

localparam [2:0] DRAIN_IDLE   = 3'd0;
localparam [2:0] DRAIN_WAIT_U = 3'd1;
localparam [2:0] DRAIN_PUSH_U = 3'd2;
localparam [2:0] DRAIN_WAIT_L = 3'd3;
localparam [2:0] DRAIN_PUSH_L = 3'd4;
reg [2:0]  drain_state;
reg [31:0] drain_baddr;
reg  [7:0] drain_wbyte;
reg        drain_req_r;

reg [7:0] tp_b;
reg [7:0] tp_ad;
reg [7:0] tp_bd;
reg [7:0] tp_cd;
reg [7:0] tp_cr;
reg [4:0] tp_imask;
reg [7:0] tp_air;
reg [7:0] tp_ilatch;
reg [7:0] tp_ilatch2;

reg [11:0] dac_shift;
reg  [9:0] cd_volume;
reg        vol_latched;
reg        tp_b_prev_6, tp_b_prev_7;

reg [7:0] subq_head;
reg       sbcp_state;

reg  [7:0] tpi_rd;

reg        sten_pulse_int;

localparam [19:0] SCOR_PERIOD = 20'd382500;
reg [19:0] scor_count;
reg        scor_pulse_int;

reg [7:0] cmd_in_fifo  [0:31];
reg [4:0] cmd_in_wr_p, cmd_in_rd_p;
reg [7:0] cmd_out_fifo [0:31];
reg [4:0] cmd_out_wr_p, cmd_out_rd_p;
reg [7:0] last_out;

reg [12:0] sec_wr_p, sec_rd_p;
wire [7:0] sec_fifo_q;

reg [7:0] rd_byte_eb;
reg [7:0] rd_byte_ob;

wire        istr_any_set;
wire  [7:0] istr_rd;
wire        sten_any;
wire  [4:0] tpi_edges;
wire  [4:0] masked_active;
wire        cmd_in_empty;
wire        cmd_out_empty;
wire        dmac_int2;
wire        tpi_int2;
wire [15:0] byte_off;

assign byte_off = {addr[15:1], 1'b0};

wire sel_ac_rom_w   = sel && (byte_off < 16'h0040);
wire sel_istr_ob    = sel && (byte_off == 16'h0040);
wire sel_cntr_ob    = sel && (byte_off == 16'h0042);
wire sel_wtc_b0_eb  = sel && (byte_off == 16'h0080);
wire sel_wtc_b1_ob  = sel && (byte_off == 16'h0080);
wire sel_wtc_b2_eb  = sel && (byte_off == 16'h0082);
wire sel_wtc_b3_ob  = sel && (byte_off == 16'h0082);
wire sel_acr_b0_eb  = sel && (byte_off == 16'h0084);
wire sel_acr_b1_ob  = sel && (byte_off == 16'h0084);
wire sel_acr_b2_eb  = sel && (byte_off == 16'h0086);
wire sel_acr_b3_ob  = sel && (byte_off == 16'h0086);
wire sel_cmda_ob    = sel && (byte_off == 16'h00A0);
wire sel_xt_a3_ob   = sel && (byte_off == 16'h00A2);
wire sel_xt_a5_ob   = sel && (byte_off == 16'h00A4);
wire sel_xt_a7_ob   = sel && (byte_off == 16'h00A6);
wire in_tpi_range   = sel && (byte_off >= 16'h00B0) && (byte_off <= 16'h00BE);
wire  [2:0] tpi_reg = byte_off[3:1];
wire [7:0] tpi_data = hwr ? din[15:8] : din[7:0];
wire sel_dma_start  = sel && (byte_off == 16'h00E0);
wire sel_dma_stop   = sel && (byte_off == 16'h00E2);
wire sel_istr_clr   = sel && (byte_off == 16'h00E4);
wire sel_fifo_tog   = sel && (byte_off == 16'h00E8);

wire sel_xtfloor  = sel_xt_a3_ob | sel_xt_a5_ob | sel_xt_a7_ob;

wire [5:0] ac_rom_addr = byte_off[6:1];

reg [7:0] ac_rom_byte;
always @* begin
	ac_rom_byte = 8'hFF;
	case (ac_rom_addr)
		6'h00: ac_rom_byte = 8'hC0;
		6'h01: ac_rom_byte = 8'h10;
		6'h02: ac_rom_byte = 8'hF0;
		6'h03: ac_rom_byte = 8'hC0;
		6'h04: ac_rom_byte = 8'hB0;
		6'h05: ac_rom_byte = 8'hF0;
		6'h08: ac_rom_byte = 8'hF0;
		6'h09: ac_rom_byte = 8'hD0;
		6'h0A: ac_rom_byte = 8'hF0;
		6'h0B: ac_rom_byte = 8'hD0;
		6'h0C: ac_rom_byte = 8'hF0;
		6'h0D: ac_rom_byte = 8'hF0;
		6'h0E: ac_rom_byte = 8'hF0;
		6'h0F: ac_rom_byte = 8'hF0;
		6'h10: ac_rom_byte = 8'hF0;
		6'h11: ac_rom_byte = 8'hF0;
		6'h12: ac_rom_byte = 8'hF0;
		6'h13: ac_rom_byte = 8'hF0;
		default: ac_rom_byte = 8'hFF;
	endcase
end

assign istr_any_set = |istr[7:1];
assign istr_rd      = istr | (istr_any_set ? (8'h01 << ISTR_INT_P_BIT) : 8'h00);

assign sten_any  = sten_pulse_ext | sten_pulse_int;
assign masked_active = tp_ilatch[4:0] & tp_imask[4:0];

assign cmd_in_empty  = (cmd_in_wr_p  == cmd_in_rd_p);
assign cmd_out_empty = (cmd_out_wr_p == cmd_out_rd_p);

wire [12:0] sec_avail = sec_wr_p - sec_rd_p;

assign dmac_int2 = cntr[CNTR_INTEN_BIT] & (istr[ISTR_E_INT_BIT] | istr[ISTR_INTS_BIT]);
assign tpi_int2  = tp_ilatch[5];

assign cdtv_irq    = dmac_int2 | tpi_int2;
assign cdda_volume       = cd_volume;
assign cdda_volume_valid = vol_latched;

wire       cmd_in_pending = ~cmd_in_empty;
wire [7:0] cmd_in_byte    = cmd_in_fifo[cmd_in_rd_p];

wire       cmd_in_pop     = uio_rd & uio_cs;
wire       cmd_out_push   = uio_wr & uio_cs;
wire [7:0] cmd_out_data   = uio_din[7:0];
wire       sec_byte_push  = uio_wr & uio_cs_sec;
wire [7:0] sec_byte_data  = uio_din[7:0];
wire       stch_pulse     = uio_wr & uio_cs_stch;
wire       stch_ack_clr   = uio_rd & uio_cs_stch;
assign tpi_edges = {1'b0, sten_any, stch_pulse | prst_pulse, scor_pulse | scor_pulse_int, sbcp_pulse};

reg        stch_ack;

reg [13:0] nvr_addr_cnt;
reg        cs_nvr_d;
reg        hi_nvr;
reg        saw_nvr_read;
wire       wr_nvr = uio_wr & uio_cs_nvr;

always @(posedge clk) begin
	if (reset) begin
		nvr_addr_cnt <= 14'd0;
		cs_nvr_d     <= 1'b0;
		hi_nvr       <= 1'b0;
		saw_nvr_read <= 1'b0;
	end else begin
		hi_nvr   <= wr_nvr;
		cs_nvr_d <= uio_cs_nvr;
		if (uio_cs_nvr & ~cs_nvr_d) begin
			nvr_addr_cnt <= 14'd0;
			saw_nvr_read <= 1'b0;
		end else if ((uio_rd & uio_cs_nvr) | wr_nvr | hi_nvr) begin
			nvr_addr_cnt <= nvr_addr_cnt + 14'd1;
		end
		if (uio_rd & uio_cs_nvr) saw_nvr_read <= 1'b1;
	end
end

assign nvr_addr        = nvr_addr_cnt;
assign nvr_load_we     = wr_nvr | hi_nvr;
assign nvr_load_din    = hi_nvr ? uio_din[15:8] : uio_din[7:0];
assign nvr_clear_dirty = cs_nvr_d & ~uio_cs_nvr & saw_nvr_read;

reg [12:0] card_addr_cnt;
reg        cs_card_d;
reg        hi_card;
reg        saw_card_read;
wire       wr_card = uio_wr & uio_cs_card;

always @(posedge clk) begin
	if (reset) begin
		card_addr_cnt <= 13'd0;
		cs_card_d     <= 1'b0;
		hi_card       <= 1'b0;
		saw_card_read <= 1'b0;
	end else begin
		hi_card   <= wr_card;
		cs_card_d <= uio_cs_card;
		if (uio_cs_card & ~cs_card_d) begin
			card_addr_cnt <= 13'd0;
			saw_card_read <= 1'b0;
		end else if ((uio_rd & uio_cs_card) | wr_card | hi_card) begin
			card_addr_cnt <= card_addr_cnt + 13'd1;
		end
		if (uio_rd & uio_cs_card) saw_card_read <= 1'b1;
	end
end

assign card_addr        = card_addr_cnt;
assign card_load_we     = wr_card | hi_card;
assign card_load_din    = hi_card ? uio_din[15:8] : uio_din[7:0];
assign card_clear_dirty = cs_card_d & ~uio_cs_card & saw_card_read;

assign uio_dout = uio_cs_nvr  ? {8'h00, nvr_dout} :
                  uio_cs_card ? {8'h00, card_dout} :
                  uio_cs_stch ? {15'h0000, stch_ack} : {8'h00, cmd_in_byte};
assign uio_req  = cmd_in_pending;

assign cdtv_dma_req   = drain_req_r;
assign cdtv_dma_we    = 1'b1;
assign cdtv_dma_baddr = drain_baddr;
assign cdtv_dma_wbyte = drain_wbyte;

wire drain_ack_u    = (drain_state == DRAIN_PUSH_U) && cdtv_dma_ack;
wire drain_ack_l    = (drain_state == DRAIN_PUSH_L) && cdtv_dma_ack;
wire drain_ack_pop  = drain_ack_u | drain_ack_l;
wire drain_ack_word = drain_ack_l;

assign selack = sel;

wire rd_active = sel && rd;
reg  rd_active_d;
reg [15:0] dout_hold;
always @(posedge clk) begin
	if (reset) begin
		rd_active_d <= 1'b0;
		dout_hold   <= 16'h0000;
	end else begin
		rd_active_d <= rd_active;
		if (rd_active && !rd_active_d) dout_hold <= {rd_byte_eb, rd_byte_ob};
	end
end

assign dout   = rd_active ? {rd_byte_eb, rd_byte_ob} : dout_hold;

always @(posedge clk) begin
	if (reset) begin
		scor_count     <= 20'd0;
		scor_pulse_int <= 1'b0;
	end else begin
		scor_pulse_int <= 1'b0;
		if (scor_count == SCOR_PERIOD - 20'd1) begin
			scor_count     <= 20'd0;
			scor_pulse_int <= 1'b1;
		end else begin
			scor_count <= scor_count + 20'd1;
		end
	end
end

reg sel_istr_ob_rd_d;
wire istr_rd_falling = !(sel_istr_ob && rd) && sel_istr_ob_rd_d;

always @(posedge clk) begin
	if (reset) begin
		istr               <= 8'h00;
		cntr               <= 8'h00;
		wtc                <= 32'h0;
		acr                <= 32'h0;
		dmac_dma           <= 1'b0;
		prst_pulse         <= 1'b0;
		dma_complete_pulse <= 1'b0;
		dma_complete_armed <= 1'b0;
		sel_istr_ob_rd_d   <= 1'b0;
	end else begin
		prst_pulse         <= 1'b0;
		dma_complete_pulse <= 1'b0;
		sel_istr_ob_rd_d   <= sel_istr_ob && rd;

		if (sel_cntr_ob && lwr) begin
			cntr <= din[7:0];
			if (din[CNTR_PREST_BIT]) prst_pulse <= 1'b1;
		end

		if (istr_rd_falling) istr <= istr & 8'hF0;

		if (sel_istr_clr && (hwr || lwr)) istr <= 8'h00;

		if (sel_fifo_tog && (rd || hwr || lwr)) begin
			istr       <= istr | (8'h01 << ISTR_FE_FLG_B);
		end

		if (sel_wtc_b0_eb && hwr) wtc[31:24] <= din[15:8];
		if (sel_wtc_b1_ob && lwr) wtc[23:16] <= din[7:0];
		if (sel_wtc_b2_eb && hwr) wtc[15:8]  <= din[15:8];
		if (sel_wtc_b3_ob && lwr) wtc[7:0]   <= din[7:0];

		if (sel_acr_b0_eb && hwr) acr[31:24] <= din[15:8];
		if (sel_acr_b1_ob && lwr) acr[23:16] <= din[7:0];
		if (sel_acr_b2_eb && hwr) acr[15:8]  <= din[15:8];
		if (sel_acr_b3_ob && lwr) acr[7:1]   <= din[7:1];


		if (sel_dma_start && (hwr || lwr)) begin
			dmac_dma           <= 1'b1;
			dma_complete_armed <= 1'b1;
		end
		if (sel_dma_stop  && (hwr || lwr)) begin
			dmac_dma           <= 1'b0;
			dma_complete_armed <= 1'b0;
		end

		if (drain_ack_word) begin
			acr <= acr + 32'd2;
			wtc <= wtc - 32'd1;
		end

		if (dmac_dma && dma_complete_armed && (wtc == 32'h0)) begin
			dma_complete_pulse <= 1'b1;
			dma_complete_armed <= 1'b0;
			dmac_dma           <= 1'b0;
		end
		if (dma_complete_pulse && cntr[CNTR_INTEN_BIT] && cntr[CNTR_TCEN_BIT]) begin
			istr         <= istr | (8'h01 << ISTR_E_INT_BIT)
			                     | (8'h01 << ISTR_INT_P_BIT);
		end
	end
end

wire sec_fifo_wren = sec_byte_push && (sec_avail != 13'h1FFF);

dpram #(13,8) sec_fifo_ram (
	.clock    (clk),
	.address_a(sec_wr_p),
	.data_a   (sec_byte_data),
	.wren_a   (sec_fifo_wren),
	.address_b(sec_rd_p),
	.wren_b   (1'b0),
	.q_b      (sec_fifo_q)
);

always @(posedge clk) begin
	if (reset) begin
		drain_state <= DRAIN_IDLE;
		drain_req_r <= 1'b0;
		drain_baddr <= 32'h0;
		drain_wbyte <= 8'h00;
	end else begin
		if (!dmac_dma || prst_pulse) begin
			drain_state <= DRAIN_IDLE;
			drain_req_r <= 1'b0;
		end else begin
			case (drain_state)
				DRAIN_IDLE: begin
					drain_req_r <= 1'b0;
					if ((wtc != 32'h0) && (sec_avail >= 13'd2)) begin
						drain_state <= DRAIN_WAIT_U;
					end
				end
				DRAIN_WAIT_U: begin
					drain_state <= DRAIN_PUSH_U;
				end
				DRAIN_PUSH_U: begin
					drain_baddr <= acr;
					drain_wbyte <= sec_fifo_q;
					drain_req_r <= 1'b1;
					if (cdtv_dma_ack) begin
						drain_req_r <= 1'b0;
						drain_state <= DRAIN_WAIT_L;
					end
				end
				DRAIN_WAIT_L: begin
					drain_state <= DRAIN_PUSH_L;
				end
				DRAIN_PUSH_L: begin
					drain_baddr <= acr + 32'd1;
					drain_wbyte <= sec_fifo_q;
					drain_req_r <= 1'b1;
					if (cdtv_dma_ack) begin
						drain_req_r <= 1'b0;
						drain_state <= DRAIN_IDLE;
					end
				end
				default: drain_state <= DRAIN_IDLE;
			endcase
		end
	end
end

always @* begin
	tpi_rd = 8'h00;
	case (tpi_reg)
		3'd0: begin
			tpi_rd[0] = subq_head[7];
			tpi_rd[1] = subq_head[6];
			tpi_rd[2] = subq_head[5];
			tpi_rd[3] = subq_head[4];
			tpi_rd[4] = subq_head[3];
			tpi_rd[5] = subq_head[2];
			tpi_rd[6] = subq_head[1];
			tpi_rd[7] = subq_head[0];
		end
		3'd1: tpi_rd = tp_b;
		3'd2: begin
			if (tp_cr[0])
				tpi_rd = {tp_ilatch[7:5], ~(tp_ilatch[4:0] | tp_ilatch2[4:0])};
			else
				tpi_rd = {3'h0, cmd_out_empty, cmd_out_empty, 1'b1, 1'b1, ~sbcp_state};
		end
		3'd3: tpi_rd = tp_ad;
		3'd4: tpi_rd = tp_bd;
		3'd5: tpi_rd = tp_cr[0] ? {3'h0, tp_imask} : tp_cd;
		3'd6: tpi_rd = tp_cr;
		3'd7: tpi_rd = tp_air;
	endcase
end

wire   in_air_rd      = in_tpi_range && rd && (tpi_reg == 3'd7) && tp_cr[0];
reg    in_air_rd_d;
wire   air_rd_falling = !in_air_rd && in_air_rd_d;

always @(posedge clk) begin
	if (reset) begin
		tp_b        <= 8'h00;
		tp_ad       <= 8'h00;
		tp_bd       <= 8'h00;
		tp_cd       <= 8'h00;
		tp_cr       <= 8'h00;
		tp_imask    <= 5'h00;
		tp_air      <= 8'h00;
		tp_ilatch   <= 8'h00;
		tp_ilatch2  <= 8'h00;
		dac_shift   <= 12'h0;
		cd_volume   <= 10'h0;
		vol_latched <= 1'b0;
		tp_b_prev_6 <= 1'b0;
		tp_b_prev_7 <= 1'b0;
		subq_head   <= 8'h00;
		sbcp_state  <= 1'b0;
		in_air_rd_d <= 1'b0;
		stch_ack    <= 1'b0;
	end else begin
		if (stch_ack_clr) stch_ack <= 1'b0;

		tp_ilatch[4:0] <= tp_ilatch[4:0] | tpi_edges;
		in_air_rd_d    <= in_air_rd;

		if (subq_push) begin
			subq_head  <= subq_byte;
			sbcp_state <= 1'b1;
		end

		if (in_tpi_range && rd && (tpi_reg == 3'd0)) begin
			sbcp_state <= 1'b0;
		end

		if (in_tpi_range && (hwr || lwr)) begin
			case (tpi_reg)
				3'd1: begin
					tp_b <= tpi_data;
					if (tpi_data[6] && !tp_b_prev_6)
						dac_shift <= {tpi_data[5], dac_shift[11:1]};
					if (tpi_data[7] && !tp_b_prev_7) begin
						cd_volume   <= dac_shift[9:0];
						vol_latched <= 1'b1;
					end
					tp_b_prev_6 <= tpi_data[6];
					tp_b_prev_7 <= tpi_data[7];
				end
				3'd2: begin
					if (tp_cr[0])
						tp_ilatch[4:0] <= tp_ilatch[4:0] & tpi_data[4:0];
				end
				3'd3: tp_ad <= tpi_data;
				3'd4: tp_bd <= tpi_data;
				3'd5: begin
					if (tp_cr[0]) tp_imask <= tpi_data[4:0];
					else          tp_cd    <= tpi_data;
				end
				3'd6: tp_cr  <= tpi_data;
				3'd7: tp_air <= tpi_data;
			endcase
		end

		if (tp_cr[0] && !tp_ilatch[5] && |masked_active) begin
			casex (masked_active)
				5'b1xxxx: begin
					tp_air       <= 8'h10;
					tp_ilatch[4] <= 1'b0;
					tp_ilatch[5] <= 1'b1;
					tp_ilatch2   <= 8'h10;
				end
				5'b01xxx: begin
					tp_air       <= 8'h08;
					tp_ilatch[3] <= 1'b0;
					tp_ilatch[5] <= 1'b1;
					tp_ilatch2   <= 8'h08;
				end
				5'b001xx: begin
					tp_air       <= 8'h04;
					tp_ilatch[2] <= 1'b0;
					tp_ilatch[5] <= 1'b1;
					tp_ilatch2   <= 8'h04;
				end
				5'b0001x: begin
					tp_air       <= 8'h02;
					tp_ilatch[1] <= 1'b0;
					tp_ilatch[5] <= 1'b1;
					tp_ilatch2   <= 8'h02;
				end
				5'b00001: begin
					tp_air       <= 8'h01;
					tp_ilatch[0] <= 1'b0;
					tp_ilatch[5] <= 1'b1;
					tp_ilatch2   <= 8'h01;
				end
			endcase
		end

		if (air_rd_falling && tp_ilatch[5]) begin
			tp_ilatch[5] <= 1'b0;
			tp_ilatch2   <= 8'h00;
			tp_air       <= 8'h00;
			if (tp_air == 8'h04) stch_ack <= 1'b1;
		end
	end
end

reg sel_cmda_ob_lwr_d, sel_cmda_ob_rd_d;
wire cmda_wr_edge     =  (sel_cmda_ob && lwr) && !sel_cmda_ob_lwr_d;
wire cmda_rd_falling  = !(sel_cmda_ob && rd ) &&  sel_cmda_ob_rd_d;

always @(posedge clk) begin
	if (reset) begin
		cmd_in_wr_p    <= 5'h0;
		cmd_in_rd_p    <= 5'h0;
		cmd_out_wr_p   <= 5'h0;
		cmd_out_rd_p   <= 5'h0;
		last_out       <= 8'h00;
		sec_wr_p       <= 13'h0;
		sec_rd_p       <= 13'h0;
		sten_pulse_int <= 1'b0;
		sel_cmda_ob_lwr_d <= 1'b0;
		sel_cmda_ob_rd_d  <= 1'b0;
	end else begin
		sten_pulse_int <= 1'b0;
		sel_cmda_ob_lwr_d <= sel_cmda_ob && lwr;
		sel_cmda_ob_rd_d  <= sel_cmda_ob && rd;

		if (prst_pulse) begin
			cmd_in_wr_p  <= 5'h0;
			cmd_in_rd_p  <= 5'h0;
			cmd_out_wr_p <= 5'h0;
			cmd_out_rd_p <= 5'h0;
			sec_wr_p     <= 13'h0;
			sec_rd_p     <= 13'h0;
		end

		if (cmda_wr_edge) begin
			cmd_in_fifo[cmd_in_wr_p] <= din[7:0];
			cmd_in_wr_p              <= cmd_in_wr_p + 5'd1;
		end

		if (cmd_in_pop && !cmd_in_empty) begin
			cmd_in_rd_p <= cmd_in_rd_p + 5'd1;
		end

		if (cmd_out_push) begin
			cmd_out_fifo[cmd_out_wr_p] <= cmd_out_data;
			cmd_out_wr_p               <= cmd_out_wr_p + 5'd1;
			sten_pulse_int             <= 1'b1;
		end

		if (cmda_rd_falling) begin
			if (!cmd_out_empty) begin
				last_out     <= cmd_out_fifo[cmd_out_rd_p];
				cmd_out_rd_p <= cmd_out_rd_p + 5'd1;
				if ((cmd_out_wr_p - (cmd_out_rd_p + 5'd1)) != 5'd0)
					sten_pulse_int <= 1'b1;
			end
		end

		if (sec_fifo_wren) begin
			sec_wr_p <= sec_wr_p + 13'd1;
		end

		if (drain_ack_pop) sec_rd_p <= sec_rd_p + 13'd1;
	end
end

always @* begin
	rd_byte_eb = 8'h00;
	if      (sel_ac_rom_w) rd_byte_eb = ac_rom_byte;
	else if (in_tpi_range) rd_byte_eb = tpi_rd;
end

always @* begin
	rd_byte_ob = 8'h00;
	if      (sel_ac_rom_w) rd_byte_ob = 8'hFF;
	else if (sel_istr_ob)  rd_byte_ob = istr_rd;
	else if (sel_cntr_ob)  rd_byte_ob = cntr;
	else if (sel_xtfloor)  rd_byte_ob = 8'hFF;
	else if (sel_cmda_ob)  rd_byte_ob = cmd_out_empty ? last_out
	                                                  : cmd_out_fifo[cmd_out_rd_p];
	else if (in_tpi_range) rd_byte_ob = tpi_rd;
end

endmodule
