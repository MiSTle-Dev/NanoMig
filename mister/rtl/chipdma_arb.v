// SPDX-License-Identifier: GPL-3.0-or-later

module chipdma_arb
(
	input             clk,
	input             reset,
	input             c_7m,

	input      [24:1] chip_in_addr,
	input             chip_in_l,
	input             chip_in_u,
	input             chip_in_rw,
	input             chip_in_dma,
	input      [15:0] chip_in_wr,
	input             chip_in_long,
	input      [15:0] chip_in_wr2,

	input             akiko_dma_req,
	input             akiko_dma_we,
	input      [23:0] akiko_dma_baddr,
	input       [7:0] akiko_dma_wbyte,
	output      [7:0] akiko_dma_rbyte,
	output            akiko_dma_ack,
	output            akiko_arm,

	input             cdtv_dma_req,
	input             cdtv_dma_we,
	input      [31:0] cdtv_dma_baddr,
	input       [7:0] cdtv_dma_wbyte,
	output      [7:0] cdtv_dma_rbyte,
	output            cdtv_dma_ack,

	// Four-voice audio extension: held request, aligned big-endian word read.
	input             audio_dma_req,
	input      [31:0] audio_dma_addr,
	output reg [15:0] audio_dma_data,
	output reg        audio_dma_ack,
	output reg        audio_dma_error,

	output     [24:1] chip_out_addr,
	output [24:1] sdram_addon_addr,
	output sdram_addon_claim,
	output            chip_out_l,
	output            chip_out_u,
	output            chip_out_rw,
	output            chip_out_dma,
	output     [15:0] chip_out_wr,
	output            chip_out_long,
	output     [15:0] chip_out_wr2,
	input      [15:0] chip_in_rd,

	input             z2ram_ena,
	input       [4:0] z3ram_base0,
	input             z3ram_ena0,
	input       [3:0] z3ram_base1,
	input             z3ram_ena1,

	output     [28:1] ddr_out_addr,
	output            ddr_out_l,
	output            ddr_out_u,
	output            ddr_out_we,
	output            ddr_out_cs,
	output     [15:0] ddr_out_wr,
	input             ddr_in_ack,
	input      [15:0] ddr_in_rd
);

reg c_7m_d;
always @(posedge clk) c_7m_d <= c_7m;
wire c_7m_rise = c_7m & ~c_7m_d;

reg akiko_dma_req_q;
reg cdtv_dma_req_q;
always @(posedge clk) begin
	if (reset) begin
		akiko_dma_req_q <= 1'b0;
		cdtv_dma_req_q  <= 1'b0;
	end else begin
		akiko_dma_req_q <= akiko_dma_req;
		cdtv_dma_req_q  <= cdtv_dma_req;
	end
end

reg [2:0] slot_cnt;

reg [24:1] ak_addr;
reg        ak_l;
reg        ak_u;
reg        ak_rw;
reg [15:0] ak_wr_data;
reg        ak_we;
reg        ak_baddr0;

reg        ak_is_ddr;

reg        dma_ddr_cs_r;
reg [28:1] dma_ddr_addr_r;
reg        dma_ddr_l_r;
reg        dma_ddr_u_r;
reg [15:0] dma_ddr_wr_r;
reg        dma_ddr_we_r;

reg ddr_in_ack_sync1;
reg ddr_in_ack_sync2;
always @(posedge clk) begin
    if (reset) begin
        ddr_in_ack_sync1 <= 1'b0;
        ddr_in_ack_sync2 <= 1'b0;
    end else begin
        ddr_in_ack_sync1 <= ddr_in_ack;
        ddr_in_ack_sync2 <= ddr_in_ack_sync1;
    end
end
wire ddr_ack_safe = ddr_in_ack_sync2;

localparam [2:0]
	S_IDLE     = 3'd0,
	S_DRIVE    = 3'd1,
	S_ACK      = 3'd2,
	S_COOLDOWN = 3'd3,
	S_ARM      = 3'd4,
	S_DRAIN    = 3'd5;

reg [2:0] state;

reg [7:0] ak_rbyte_r;
reg       ak_ack_r;
reg       cdtv_ack_r;

reg active_is_cdtv;
reg active_is_audio;
reg [1:0] last_owner;
reg [1:0] owner;
always @* begin
	// Round robin, preserving service for Akiko and CDTV under audio load.
	case (last_owner)
	2'd0: owner = cdtv_dma_req_q ? 2'd1 : audio_dma_req ? 2'd2 : 2'd0;
	2'd1: owner = audio_dma_req ? 2'd2 : akiko_dma_req_q ? 2'd0 : 2'd1;
	default: owner = akiko_dma_req_q ? 2'd0 : cdtv_dma_req_q ? 2'd1 : 2'd2;
	endcase
end

assign akiko_dma_rbyte = ak_rbyte_r;
assign akiko_dma_ack   = ak_ack_r;
assign cdtv_dma_rbyte  = 8'h00;
assign cdtv_dma_ack    = cdtv_ack_r;

wire minimig_idle = chip_in_dma & chip_in_rw;

wire any_req       = akiko_dma_req_q | cdtv_dma_req_q | audio_dma_req;
wire arming_is_cdtv = owner == 2'd1;
wire arming_is_audio = owner == 2'd2;

wire        live_we     = arming_is_audio ? 1'b0 : arming_is_cdtv ? cdtv_dma_we : akiko_dma_we;
wire [31:0] live_baddr  = arming_is_audio ? audio_dma_addr : arming_is_cdtv ? cdtv_dma_baddr : {8'h00, akiko_dma_baddr};
wire  [7:0] live_wbyte  = arming_is_cdtv ? cdtv_dma_wbyte : akiko_dma_wbyte;

// Capture the complete selected transaction before the chip-memory slot.
// Request arbitration and address translation end at these system-clock
// registers; they must not feed the faster SDRAM address path combinationally.
wire claim_now = (state == S_IDLE) & any_req;
wire start_candidate = (state == S_ARM) & c_7m_rise;
wire arm_now = start_candidate & minimig_idle;

// Akiko freezes its internal response owner at claim, matching the packet
// captured here even if another Akiko subrequest arrives while waiting.
assign akiko_arm = claim_now & ~arming_is_cdtv & ~arming_is_audio;

wire [28:1] router_ramaddr;
wire        router_zram_sel = |router_ramaddr[28:26];

memory_router u_router
(
	.cpu_addr      (live_baddr),
	.cchip         (1'b0),
	.ckick         (1'b0),
	.wr            (1'b0),
	.bootrom       (1'b0),
	.cdtv_mode     (1'b0),
	.z2ram_ena     (z2ram_ena),
	.z3ram_base0   (z3ram_base0),
	.z3ram_ena0    (z3ram_ena0),
	.z3ram_base1   (z3ram_base1),
	.z3ram_ena1    (z3ram_ena1),
	.ramaddr       (router_ramaddr)
);

wire        addr_unmapped   = arming_is_audio ? (live_baddr[0] | ((|live_baddr[31:21]) & ~router_zram_sel)) : (|live_baddr[31:24] & ~router_zram_sel);
reg         ak_unmapped;
wire        start_chip = start_candidate & ~ak_is_ddr & ~ak_unmapped;
wire        held_chip  = (state == S_DRIVE) & ~ak_is_ddr & ~ak_unmapped;
wire        arb_drive_chip = minimig_idle & (start_chip | held_chip);
// Export the registered candidate before the late idle/address mux.
assign sdram_addon_addr = ak_addr;
assign sdram_addon_claim = start_chip | held_chip;

assign chip_out_addr = arb_drive_chip ? ak_addr    : chip_in_addr;
assign chip_out_l    = arb_drive_chip ? ak_l       : chip_in_l;
assign chip_out_u    = arb_drive_chip ? ak_u       : chip_in_u;
assign chip_out_rw   = arb_drive_chip ? ak_rw      : chip_in_rw;
assign chip_out_dma  = arb_drive_chip ? 1'b0         : chip_in_dma;
assign chip_out_wr   = arb_drive_chip ? ak_wr_data : chip_in_wr;
assign chip_out_long = ~arb_drive_chip & chip_in_long;
assign chip_out_wr2  = chip_in_wr2;

assign ddr_out_cs   = dma_ddr_cs_r;
assign ddr_out_addr = dma_ddr_addr_r;
assign ddr_out_l    = dma_ddr_l_r;
assign ddr_out_u    = dma_ddr_u_r;
assign ddr_out_we   = dma_ddr_we_r;
assign ddr_out_wr   = dma_ddr_wr_r;

always @(posedge clk) begin
	if (reset) begin
		state          <= S_IDLE;
		slot_cnt       <= 3'd0;
		ak_ack_r       <= 1'b0;
		cdtv_ack_r     <= 1'b0;
		ak_rbyte_r     <= 8'h00;
		active_is_cdtv <= 1'b0;
		active_is_audio <= 1'b0;
		last_owner <= 2'd2;
		audio_dma_ack <= 1'b0;
		audio_dma_error <= 1'b0;
		audio_dma_data <= 16'd0;
		ak_is_ddr      <= 1'b0;
		ak_unmapped    <= 1'b0;
		dma_ddr_cs_r   <= 1'b0;
		dma_ddr_we_r   <= 1'b1;
	end else begin
		ak_ack_r   <= 1'b0;
		cdtv_ack_r <= 1'b0;
		audio_dma_ack <= 1'b0;
		audio_dma_error <= 1'b0;

		case (state)
		S_IDLE: begin
			if (claim_now) begin
				ak_addr        <= {1'b0, live_baddr[23:1]};
				ak_u           <= arming_is_audio ? 1'b0 : live_baddr[0];
				ak_l           <= arming_is_audio ? 1'b0 : ~live_baddr[0];
				ak_rw          <= ~live_we;
				ak_wr_data     <= {live_wbyte, live_wbyte};
				ak_we          <= live_we;
				ak_baddr0      <= live_baddr[0];
				ak_is_ddr      <= router_zram_sel && !addr_unmapped;
				ak_unmapped    <= addr_unmapped;
				slot_cnt       <= 3'd0;
				active_is_cdtv <= arming_is_cdtv;
				active_is_audio <= arming_is_audio;
				last_owner <= owner;
				if (router_zram_sel && !addr_unmapped) begin
					dma_ddr_addr_r <= router_ramaddr;
					dma_ddr_l_r    <= arming_is_audio ? 1'b0 : ~live_baddr[0];
					dma_ddr_u_r    <= arming_is_audio ? 1'b0 : live_baddr[0];
					dma_ddr_wr_r   <= {live_wbyte, live_wbyte};
					dma_ddr_we_r   <= live_we;
				end
				state          <= S_ARM;
			end
		end

		S_ARM: begin
			if (arm_now) begin
				if (ak_is_ddr) dma_ddr_cs_r <= 1'b1;
				state <= S_DRIVE;
			end
		end

		S_DRIVE: begin
			if (ak_unmapped && active_is_audio) begin
				audio_dma_data <= 16'd0;
				state <= S_ACK;
			end else if (ak_is_ddr) begin
				if (ddr_ack_safe) begin
					if (!ak_we) begin
						audio_dma_data <= ddr_in_rd;
						ak_rbyte_r <= ak_baddr0 ? ddr_in_rd[7:0]
						                        : ddr_in_rd[15:8];
					end
					state <= S_ACK;
				end
			end else begin
				slot_cnt <= slot_cnt + 3'd1;
				if (slot_cnt == 3'd3) begin
					if (!ak_we) begin
						audio_dma_data <= chip_in_rd;
						ak_rbyte_r <= ak_baddr0 ? chip_in_rd[7:0]
						                        : chip_in_rd[15:8];
					end
					state <= S_ACK;
				end
			end
		end

		S_ACK: begin
			if (active_is_audio) begin
				audio_dma_ack <= 1'b1;
				audio_dma_error <= ak_unmapped;
			end else if (active_is_cdtv) cdtv_ack_r <= 1'b1;
			else                ak_ack_r   <= 1'b1;
			dma_ddr_cs_r <= 1'b0;
			state <= S_COOLDOWN;
		end

		S_COOLDOWN: begin
			if (~ak_is_ddr | ~ddr_ack_safe)
			state <= S_DRAIN;
		end

		S_DRAIN: begin
			// Upstream consumes our registered ACK on the previous edge.
			// Allow its registered request and req_q to settle before a new
			// claim, avoiding a duplicate of the just-completed transaction.
			state <= S_IDLE;
		end
		endcase
	end
end

endmodule
