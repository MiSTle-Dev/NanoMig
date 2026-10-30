// Copyright 2021 Alexey Melnikov
// Copyright 2026 (CD32 native-mode register/IRQ extensions)
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

module akiko #(parameter NATIVE_CD32 = 0)
(
	input             clk,
	input             reset,
	input             cs,
	input             rd,
	input             wr,
	input             lds,
	input             uds,
	input       [5:1] addr,
	input      [15:0] din,
	output reg [15:0] dout,
	output            akiko_irq,

	output            dma_req,
	output            dma_we,
	output     [23:0] dma_baddr,
	output      [7:0] dma_wbyte,
	input       [7:0] dma_rbyte,
	input             dma_ack,
	input             dma_arm,

	output            hps_cmd_pending,
	output      [7:0] hps_cmd_byte,
	input             hps_cmd_pop,
	input             hps_cmd_done,
	input             hps_result_push,
	input       [7:0] hps_result_byte,
	input             hps_result_done,

	output            hps_sec_req,
	output      [7:0] hps_sec_status,
	input             hps_sec_push,
	input      [15:0] hps_sec_word,
	input             hps_sec_done,

	output            hps_rx_busy,

	input       [9:0] hps_nvr_addr,
	output      [7:0] hps_nvr_dout,
	input             hps_nvr_clear_dirty,
	output            hps_nvr_dirty,

	input       [9:0] nvr_load_addr,
	input       [7:0] nvr_load_din,
	input             nvr_load_we,

	input             hps_subcode_push,
	input       [7:0] hps_subcode_byte,
	input             hps_subcode_done
);

localparam [31:0] INTENA_MASK     = 32'hff000000;
localparam [31:0] CONFIG_MASK     = 32'hff800000;
localparam [31:0] ADDRDATA_MASK   = 32'h00fff000;
localparam [31:0] ADDRMISC_MASK   = 32'h00fffc00;

localparam [31:0] CDINT_SUBCODE   = 32'h80000000;
localparam [31:0] CDINT_DRIVEXMIT = 32'h40000000;
localparam [31:0] CDINT_DRIVERECV = 32'h20000000;
localparam [31:0] CDINT_RXDMADONE = 32'h10000000;
localparam [31:0] CDINT_TXDMADONE = 32'h08000000;
localparam [31:0] CDINT_PBX       = 32'h04000000;
localparam [31:0] CDINT_OVERFLOW  = 32'h02000000;

localparam        CDFLAG_TXD_BIT    = 30;
localparam        CDFLAG_RXD_BIT    = 29;
localparam        CDFLAG_PBX_BIT    = 27;
localparam        CDFLAG_ENABLE_BIT = 26;

wire c2p_sel = (addr[5:2] == 'b1110);

reg [7:0] buff[32];
reg [3:0] rptr = 0, wptr = 0;

always @(posedge clk) begin
	if((wr|rd) & cs & c2p_sel) begin
		if (wr) begin
			rptr <= 0;
			wptr <= wptr + 1'd1;
			{buff[{wptr,1'b0}],buff[{wptr,1'b1}]} <= din;
		end
		else begin
			wptr <= 0;
			rptr <= rptr + 1'd1;
		end
	end
end

reg [15:0] c2p_dout;
always @(*) begin : c2p_read
	reg [4:0] i;
	c2p_dout = 16'h0;
	for (i=0; i<16; i=i+1'd1)
		c2p_dout[i] = buff[{rptr[0],~i[3:0]}][rptr[3:1]];
end

wire [15:0] cd_dout;
wire        cd_irq;
wire        cd_dma_req;
wire        cd_dma_we;
wire [23:0] cd_dma_baddr;
wire  [7:0] cd_dma_wbyte;
wire        cd_hps_cmd_pending;
wire  [7:0] cd_hps_cmd_byte;
wire        cd_hps_sec_req;
wire  [7:0] cd_hps_sec_status;
wire        cd_hps_rx_busy;
wire  [7:0] cd_hps_nvr_dout;
wire        cd_hps_nvr_dirty;

generate
if (NATIVE_CD32) begin : g_cd

	reg [31:0] cdrom_intreq;
	reg [31:0] cdrom_intena;
	reg [31:0] cdrom_addressdata;
	reg [31:0] cdrom_addressmisc;
	reg [31:0] cdrom_flags;
	reg [15:0] cdrom_pbx;
	reg  [7:0] cdrom_subcodeoffset;
	reg  [7:0] cdcomtxinx;
	reg  [7:0] cdcomrxinx;
	reg  [7:0] cdcomtxcmp;
	reg  [7:0] cdcomrxcmp;
	reg  [7:0] pio_byte;
	reg  [7:0] nvram_io;
	reg  [7:0] nvram_dir;

	//
	wire       nvram_scl_master_drive = nvram_dir[7];
	wire       nvram_sda_master_drive = nvram_dir[6];
	wire       nvram_scl_bus = nvram_scl_master_drive ? nvram_io[7] : 1'b1;
	wire       nvram_sda_master_value =
	               nvram_sda_master_drive ? nvram_io[6] : 1'b1;
	wire       nvram_slave_sda_drive;
	wire       nvram_sda_bus = nvram_sda_master_value & ~nvram_slave_sda_drive;

	reg  [7:0] cdrom_command_buffer [32];
	reg  [5:0] cdrom_command_length;
	reg  [7:0] cdrom_result_buffer  [32];
	reg  [5:0] cdrom_receive_length;
	reg  [5:0] cdrom_receive_offset;
	reg  [1:0] tx_dma_delay;
	reg  [1:0] rx_dma_delay;
	reg        tx_busy;
	reg        rx_busy;
	reg        rx_inflight;
	reg        pio_wr_d;
	reg        pio_rd_d;

	localparam [1:0] OWN_RX = 2'd0, OWN_PBX = 2'd1, OWN_TX = 2'd2, OWN_SUB = 2'd3;
	reg        dma_owned;
	reg  [1:0] dma_owner;
	wire       own_rx  = dma_owned & (dma_owner == OWN_RX);
	wire       own_pbx = dma_owned & (dma_owner == OWN_PBX);
	wire       own_tx  = dma_owned & (dma_owner == OWN_TX);
	wire       own_sub = dma_owned & (dma_owner == OWN_SUB);

	reg  [5:0] hps_cmd_rd_ptr;
	reg  [5:0] hps_result_wr_ptr;

	//
	//
	reg [15:0] sector_buffer [1176];
	reg [10:0] sec_wr_ptr;
	reg        sector_ready;

	wire        sec_w_we   = hps_sec_push && sec_wr_ptr != 11'd1176;
	wire [10:0] sec_w_addr = sec_wr_ptr;
	wire [15:0] sec_w_din  = hps_sec_word;
	reg  [7:0] cdrom_sector_counter;
	reg        pbx_busy;
	reg  [1:0] pbx_state;
	localparam PBX_IDLE = 2'd0;
	localparam PBX_DATA = 2'd1;
	localparam PBX_ZERO = 2'd2;
	localparam PBX_FIN  = 2'd3;
	reg  [3:0] pbx_seccnt;
	reg [11:0] pbx_byte_idx;

	reg        pbx_ship_invalid;

	reg  [7:0] subbuf [96];
	reg  [6:0] sub_wr_ptr;
	reg        subcode_ready;
	reg        subcode_busy;
	reg        subcode_irq;
	reg  [1:0] subcode_state;
	localparam SUB_IDLE = 2'd0;
	localparam SUB_DATA = 2'd1;
	localparam SUB_FIN  = 2'd2;
	localparam CDFLAG_SUBCODE_BIT = 31;
	reg  [7:0] subcode_off;
	reg  [7:0] sub_idx;

	function [5:0] expected_total_len;
		input [3:0] op;
		case (op)
			4'h0: expected_total_len = 6'd2;
			4'h1: expected_total_len = 6'd3;
			4'h2: expected_total_len = 6'd2;
			4'h3: expected_total_len = 6'd2;
			4'h4: expected_total_len = 6'd13;
			4'h5: expected_total_len = 6'd3;
			4'h6: expected_total_len = 6'd2;
			4'h7: expected_total_len = 6'd2;
			4'h8: expected_total_len = 6'd5;
			4'h9: expected_total_len = 6'd2;
			4'ha: expected_total_len = 6'd3;
			default: expected_total_len = 6'd1;
		endcase
	endfunction

	wire [3:0] cmd_op       = cdrom_command_buffer[0][3:0];
	wire [7:0] cmd_arg1     = cdrom_command_buffer[1];
	wire [5:0] cmd_total    = expected_total_len(cmd_op);

	wire cmd_zero_result = ((cmd_op == 4'h5) && !cmd_arg1[7])
	                    ||  (cmd_op == 4'h8)
	                    ||  (cmd_op == 4'h9)
	                    ||  (cmd_op == 4'ha);
	wire       cmd_pending  = (cdrom_command_length != 6'd0)
	                       && ((cdrom_command_length >= cmd_total)
	                          || (cdrom_command_length == 6'd32));

	wire [23:0] cdrx_address = cdrom_addressmisc[23:0];
	wire [23:0] cdtx_address = cdrom_addressmisc[23:0] | 24'h000200;
	wire [23:0] subcode_address = cdrom_addressmisc[23:0] | 24'h000100;
	wire [23:0] subcode_dma_addr = subcode_address
	                             + {16'h0, subcode_off} + {16'h0, sub_idx};
	wire  [7:0] subcode_dma_byte = (sub_idx < 8'd96) ? subbuf[sub_idx[6:0]] :
	                              (sub_idx < 8'd98) ? 8'hff : 8'h00;

	wire tx_can_start =  cdrom_flags[CDFLAG_TXD_BIT]
	                  && !cdrom_flags[CDFLAG_ENABLE_BIT]
	                  && (cdcomtxinx != cdcomtxcmp)
	                  && (tx_dma_delay == 2'd0)
	                  && (cdrom_receive_length == 6'd0)
	                  && (cdrom_command_length != 6'd32)
	                  && !cmd_pending;

	wire rx_can_start =  cdrom_flags[CDFLAG_RXD_BIT]
	                  && (cdrom_receive_length != 6'd0)
	                  && (cdcomrxinx != cdcomrxcmp)
	                  && (rx_dma_delay == 2'd0);

	wire       pio_tx_allowed  = !cdrom_flags[CDFLAG_TXD_BIT] && !tx_busy;
	wire       pio_tx_can_send = (cdrom_receive_length == 6'd0)
	                          && (cdrom_command_length != 6'd32)
	                          && !cmd_pending;
	wire [3:0] pio_tx_op       = (cdrom_command_length == 6'd0) ? din[11:8] : cmd_op;
	wire [5:0] pio_tx_next_len = cdrom_command_length + 6'd1;
	wire       pio_tx_more     = (pio_tx_next_len < expected_total_len(pio_tx_op))
	                          && (pio_tx_next_len != 6'd32);

	wire       pio_rx_allowed  = !cdrom_flags[CDFLAG_RXD_BIT] && !rx_busy;
	wire       pio_rx_avail    = pio_rx_allowed
	                          && (cdrom_receive_offset < cdrom_receive_length);
	wire [7:0] pio_rx_data     = pio_rx_avail
	                          ? cdrom_result_buffer[cdrom_receive_offset]
	                          : pio_byte;
	wire       pio_rx_last     = (cdrom_receive_offset + 6'd1) == cdrom_receive_length;

	wire pbx_can_start =  (pbx_state == PBX_IDLE)
	                   && cdrom_flags[CDFLAG_ENABLE_BIT]
	                   && cdrom_flags[CDFLAG_PBX_BIT]
	                   && (cdrom_pbx != 16'h0)
	                   && sector_ready;
	wire others_busy     = rx_busy | pbx_busy | tx_busy;
	wire others_starting = rx_can_start | tx_can_start | pbx_can_start;

	wire [23:0] pbx_slot_base = cdrom_addressdata[23:0] + {8'h0, pbx_seccnt, 12'h0};
	wire [23:0] pbx_addr_c    = pbx_slot_base
	                          + ((pbx_state == PBX_DATA)
	                              ? {12'h0, pbx_byte_idx}
	                              : (24'h000c00 + {12'h0, pbx_byte_idx}));
	reg  [23:0] pbx_addr;
	always @(posedge clk) begin
		if (reset) pbx_addr <= 24'h0;
		else       pbx_addr <= pbx_addr_c;
	end
	reg [15:0] sector_rd_w;
	reg        sector_rd_hi;
	always @(posedge clk) begin
		sector_rd_w  <= sector_buffer[pbx_byte_idx[11:1]];
		sector_rd_hi <= pbx_byte_idx[0];
	end
	wire  [7:0] sector_rd_q = sector_rd_hi ? sector_rd_w[15:8] : sector_rd_w[7:0];
	wire [7:0]  sector_byte_at_idx = (pbx_byte_idx <  12'd3   ) ? 8'h00 :
	                                 (pbx_byte_idx == 12'd3   ) ? (cdrom_sector_counter & 8'h1f) :
	                                 (pbx_byte_idx <  12'd2352) ? sector_rd_q :
	                                                              8'h00;
	wire [7:0]  pbx_wbyte = (pbx_state == PBX_DATA) ? sector_byte_at_idx : 8'h00;

	function [3:0] highest_bit;
		input [15:0] m;
		integer i;
		begin
			highest_bit = 4'd0;
			for (i = 0; i < 16; i = i + 1)
				if (m[i]) highest_bit = i[3:0];
		end
	endfunction

	//
	wire sec_req_w =  cdrom_flags[CDFLAG_ENABLE_BIT]
	               && cdrom_flags[CDFLAG_PBX_BIT]
	               && (cdrom_pbx != 16'h0)
	               && !sector_ready
	               && !pbx_busy;

	wire write = wr & cs;
	wire read  = rd & cs;

	wire pio_wr_sel  = write && (addr == 5'b10100) && uds;
	wire pio_rd_sel  = read  && (addr == 5'b10100);
	wire pio_wr_edge = pio_wr_sel & ~pio_wr_d;
	wire pio_rd_edge = pio_rd_sel & ~pio_rd_d;

	wire enable_rising = write && (addr == 5'b10010) && uds && din[10]
	                  && !cdrom_flags[CDFLAG_ENABLE_BIT];

	wire pbx_starting = (pbx_state == PBX_IDLE)
	                 && cdrom_flags[CDFLAG_ENABLE_BIT]
	                 && cdrom_flags[CDFLAG_PBX_BIT]
	                 && (cdrom_pbx != 16'h0)
	                 && sector_ready && !subcode_busy;

	always @(posedge clk) begin
		if (reset) begin
			cdrom_intreq        <= CDINT_SUBCODE;
			cdrom_intena        <= 32'h0;
			cdrom_addressdata   <= 32'h0;
			cdrom_addressmisc   <= 32'h0;
			cdrom_flags         <= 32'h0;
			cdrom_pbx           <= 16'h0;
			cdrom_subcodeoffset <= 8'h0;
			cdcomtxinx          <= 8'h0;
			cdcomrxinx          <= 8'h0;
			cdcomtxcmp          <= 8'h0;
			cdcomrxcmp          <= 8'h0;
			pio_byte            <= 8'h0;
			pio_wr_d            <= 1'b0;
			pio_rd_d            <= 1'b0;
			nvram_io            <= 8'h0;
			nvram_dir           <= 8'h0;
			cdrom_command_length <= 6'h0;
			cdrom_receive_length <= 6'h0;
			cdrom_receive_offset <= 6'h0;
			tx_dma_delay         <= 2'h0;
			rx_dma_delay         <= 2'h0;
			tx_busy              <= 1'b0;
			rx_busy              <= 1'b0;
			rx_inflight          <= 1'b0;
			dma_owned            <= 1'b0;
			dma_owner            <= OWN_RX;
			hps_cmd_rd_ptr       <= 6'h0;
			hps_result_wr_ptr    <= 6'h0;
			sec_wr_ptr           <= 11'h0;
			sector_ready         <= 1'b0;
			sub_wr_ptr           <= 7'h0;
			subcode_ready        <= 1'b0;
			subcode_busy         <= 1'b0;
			subcode_irq          <= 1'b0;
			subcode_state        <= SUB_IDLE;
			subcode_off          <= 8'h0;
			sub_idx              <= 8'h0;
			cdrom_sector_counter <= 8'h0;
			pbx_busy             <= 1'b0;
			pbx_state            <= PBX_IDLE;
			pbx_seccnt           <= 4'h0;
			pbx_byte_idx         <= 12'h0;
			pbx_ship_invalid     <= 1'b0;
		end else begin
			if (tx_dma_delay != 2'd0) tx_dma_delay <= tx_dma_delay - 2'd1;
			if (rx_dma_delay != 2'd0) rx_dma_delay <= rx_dma_delay - 2'd1;

			pio_wr_d <= pio_wr_sel;
			pio_rd_d <= pio_rd_sel;

			if (dma_arm) begin
				dma_owned <= rx_busy | pbx_busy | tx_busy | subcode_busy;
				dma_owner <= rx_busy  ? OWN_RX  :
				             pbx_busy ? OWN_PBX :
				             tx_busy  ? OWN_TX  : OWN_SUB;
			end else if (dma_ack) begin
				dma_owned <= 1'b0;
			end

			if (write) begin
			case (addr)
				5'b00100: begin : intena_hi
					reg [31:0] tmp;
					tmp = cdrom_intena;
					if (uds) tmp[31:24] = din[15:8];
					if (lds) tmp[23:16] = din[7:0];
					cdrom_intena <= tmp & INTENA_MASK;
				end
				5'b00101: begin : intena_lo
					reg [31:0] tmp;
					tmp = cdrom_intena;
					if (uds) tmp[15:8] = din[15:8];
					if (lds) tmp[7:0]  = din[7:0];
					cdrom_intena <= tmp & INTENA_MASK;
				end
				5'b01000: begin : addrdata_hi
					reg [31:0] tmp;
					tmp = cdrom_addressdata;
					if (uds) tmp[31:24] = din[15:8];
					if (lds) tmp[23:16] = din[7:0];
					cdrom_addressdata <= tmp & ADDRDATA_MASK;
				end
				5'b01001: begin : addrdata_lo
					reg [31:0] tmp;
					tmp = cdrom_addressdata;
					if (uds) tmp[15:8] = din[15:8];
					if (lds) tmp[7:0]  = din[7:0];
					cdrom_addressdata <= tmp & ADDRDATA_MASK;
				end
				5'b01010: begin : addrmisc_hi
					reg [31:0] tmp;
					tmp = cdrom_addressmisc;
					if (uds) tmp[31:24] = din[15:8];
					if (lds) tmp[23:16] = din[7:0];
					cdrom_addressmisc <= tmp & ADDRMISC_MASK;
				end
				5'b01011: begin : addrmisc_lo
					reg [31:0] tmp;
					tmp = cdrom_addressmisc;
					if (uds) tmp[15:8] = din[15:8];
					if (lds) tmp[7:0]  = din[7:0];
					cdrom_addressmisc <= tmp & ADDRMISC_MASK;
				end
				5'b01100: begin
					if (uds) begin
						cdrom_intreq <= cdrom_intreq & ~CDINT_SUBCODE;
						subcode_irq  <= 1'b0;
					end
				end
				5'b01110: begin
					if (lds) begin
						cdcomtxcmp   <= din[7:0];
						cdrom_intreq <= cdrom_intreq & ~CDINT_TXDMADONE;
						tx_dma_delay <= 2'd3;
					end
				end
				5'b01111: begin
					if (lds) begin
						cdcomrxcmp   <= din[7:0];
						cdrom_intreq <= cdrom_intreq & ~CDINT_RXDMADONE;
						rx_dma_delay <= 2'd3;
					end
				end
				5'b10000: begin : pbx_w
					reg [15:0] tmp;
					tmp = cdrom_pbx;
					if (uds) tmp[15:8] = tmp[15:8] | din[15:8];
					if (lds) tmp[7:0]  = tmp[7:0]  | din[7:0];
					if (!cdrom_flags[CDFLAG_PBX_BIT]) tmp = 16'h0;
					cdrom_pbx    <= tmp;
					cdrom_intreq <= cdrom_intreq & ~CDINT_PBX;
				end
				5'b10010: begin : cfg_high
					reg [31:0] new_flags;
					new_flags = cdrom_flags;
					if (uds) new_flags[31:24] = din[15:8];
					if (lds) new_flags[23:16] = din[7:0];
					new_flags = new_flags & CONFIG_MASK;
					cdrom_flags <= new_flags;
					//
					if (new_flags[CDFLAG_ENABLE_BIT] && !cdrom_flags[CDFLAG_ENABLE_BIT]) begin
						cdrom_intreq         <= cdrom_intreq & ~CDINT_OVERFLOW;
						cdrom_sector_counter <= 8'h0;
						sector_ready         <= 1'b0;
						sec_wr_ptr           <= 11'h0;
					end
					if (!new_flags[CDFLAG_PBX_BIT]) cdrom_pbx <= 16'h0;
				end
				5'b10011: begin : cfg_low
					reg [31:0] new_flags;
					new_flags = cdrom_flags;
					if (uds) new_flags[15:8] = din[15:8];
					if (lds) new_flags[7:0]  = din[7:0];
					new_flags = new_flags & CONFIG_MASK;
					cdrom_flags <= new_flags;
				end
				5'b10100: begin
					if (pio_wr_edge && pio_tx_allowed) begin
						cdrom_intreq <= (cdrom_intreq & ~CDINT_DRIVEXMIT)
						              | ((pio_tx_can_send && pio_tx_more) ? CDINT_DRIVEXMIT : 32'h0);
						if (pio_tx_can_send) begin
							cdrom_command_buffer[cdrom_command_length] <= din[15:8];
							cdrom_command_length <= pio_tx_next_len;
						end
					end
				end
				5'b11000: begin
					if (uds) nvram_io  <= din[15:8];
					if (lds) ;
				end
				5'b11001: begin
					if (uds) nvram_dir <= din[15:8];
				end
				default: ;
			endcase
			end

			if (pio_rd_edge) begin
				pio_byte <= pio_rx_data;
				if (pio_rx_avail) begin
					cdrom_receive_offset <= cdrom_receive_offset + 6'd1;
					if (pio_rx_last) begin
						cdrom_receive_length <= 6'd0;
						cdrom_receive_offset <= 6'd0;
						cdrom_intreq <= (cdrom_intreq & ~CDINT_DRIVERECV) | CDINT_DRIVEXMIT;
					end
				end else begin
					cdrom_intreq <= cdrom_intreq & ~CDINT_DRIVERECV;
				end
			end

			if (tx_busy) begin
				if (dma_ack && own_tx) begin
					if (cdrom_command_length != 6'd32)
						cdrom_command_buffer[cdrom_command_length] <= dma_rbyte;
					cdrom_command_length <= cdrom_command_length + 6'd1;
					cdcomtxinx           <= cdcomtxinx + 8'd1;
					if ((cdcomtxinx + 8'd1) == cdcomtxcmp)
						cdrom_intreq <= cdrom_intreq | CDINT_TXDMADONE;
					tx_busy <= 1'b0;
				end
			end else if (!rx_busy && !pbx_busy && tx_can_start && !subcode_busy) begin
				tx_busy <= 1'b1;
			end

			//
			if (rx_busy) begin
				if (dma_ack && own_rx) begin
					cdcomrxinx           <= cdcomrxinx + 8'd1;
					cdrom_receive_offset <= cdrom_receive_offset + 6'd1;
					if ((cdrom_receive_offset + 6'd1) == cdrom_receive_length) begin
						cdrom_receive_length <= 6'd0;
						cdrom_receive_offset <= 6'd0;
						cdrom_intreq <= ((cdrom_intreq & ~CDINT_DRIVERECV) | CDINT_DRIVEXMIT)
						              | (((cdcomrxinx + 8'd1) == cdcomrxcmp) ? CDINT_RXDMADONE : 32'h0);
					end else if ((cdcomrxinx + 8'd1) == cdcomrxcmp) begin
						//
						cdrom_intreq <= cdrom_intreq | CDINT_RXDMADONE;
					end
					rx_busy     <= 1'b0;
					rx_inflight <= 1'b0;
				end else if (!rx_inflight && !dma_ack) begin
					rx_inflight <= 1'b1;
				end
			end else if (rx_can_start && !subcode_busy) begin
				rx_busy     <= 1'b1;
				rx_inflight <= 1'b0;
			end

			case (pbx_state)
				PBX_IDLE: begin
					if (cdrom_flags[CDFLAG_ENABLE_BIT]
					    && cdrom_flags[CDFLAG_PBX_BIT]
					    && (cdrom_pbx != 16'h0)
					    && sector_ready && !subcode_busy) begin
						pbx_seccnt   <= highest_bit(cdrom_pbx);
						pbx_byte_idx <= 12'h0;
						pbx_busy     <= 1'b1;
						pbx_state    <= PBX_DATA;
					end
				end
				PBX_DATA: begin
					if (dma_ack && own_pbx) begin
						if (pbx_byte_idx == 12'd2351) begin
							pbx_byte_idx <= 12'h0;
							pbx_state    <= PBX_ZERO;
						end else begin
							pbx_byte_idx <= pbx_byte_idx + 12'd1;
						end
					end
				end
				PBX_ZERO: begin
					if (dma_ack && own_pbx) begin
						if (pbx_byte_idx == 12'd145) begin
							pbx_byte_idx <= 12'h0;
							pbx_state    <= PBX_FIN;
						end else begin
							pbx_byte_idx <= pbx_byte_idx + 12'd1;
						end
					end
				end
				PBX_FIN: begin
					cdrom_pbx[pbx_seccnt] <= 1'b0;
					cdrom_intreq          <= cdrom_intreq | CDINT_PBX;
					if (!pbx_ship_invalid && !enable_rising)
						cdrom_sector_counter <= cdrom_sector_counter + 8'd1;
					sector_ready          <= 1'b0;
					pbx_busy              <= 1'b0;
					pbx_state             <= PBX_IDLE;
				end
			endcase

			if (enable_rising && (pbx_busy || pbx_starting))
				pbx_ship_invalid <= 1'b1;
			else if (pbx_starting)
				pbx_ship_invalid <= 1'b0;

			if (sec_w_we && !sector_ready && !enable_rising) begin
				sector_buffer[sec_w_addr] <= sec_w_din;
			end

			if (hps_sec_push && !sector_ready && sec_wr_ptr != 11'd1176
			    && !enable_rising) begin
				sec_wr_ptr <= sec_wr_ptr + 11'd1;
			end
			if (hps_sec_done) begin
				if (sec_wr_ptr == 11'd1176 && !enable_rising) sector_ready <= 1'b1;
				sec_wr_ptr <= 11'h0;
			end

			if (hps_subcode_push && !subcode_ready && !subcode_busy
			    && sub_wr_ptr != 7'd96) begin
				subbuf[sub_wr_ptr[6:0]] <= hps_subcode_byte;
				sub_wr_ptr <= sub_wr_ptr + 7'd1;
			end
			if (hps_subcode_done) begin
				if (sub_wr_ptr == 7'd96 && !subcode_busy) subcode_ready <= 1'b1;
				sub_wr_ptr <= 7'h0;
			end

			case (subcode_state)
				SUB_IDLE: begin
					if (subcode_ready) begin
						if (!cdrom_flags[CDFLAG_SUBCODE_BIT]) begin
							subcode_ready <= 1'b0;
						end else if (!others_busy && !others_starting) begin
							subcode_off   <= (cdrom_subcodeoffset >= 8'd128) ? 8'd0 : 8'd128;
							sub_idx       <= 8'h0;
							subcode_busy  <= 1'b1;
							subcode_state <= SUB_DATA;
						end
					end
				end
				SUB_DATA: begin
					if (dma_ack && own_sub) begin
						if (sub_idx == 8'd99) subcode_state <= SUB_FIN;
						else                  sub_idx <= sub_idx + 8'd1;
					end
				end
				SUB_FIN: begin
					cdrom_subcodeoffset <= subcode_off + 8'd100;
					subcode_irq         <= 1'b1;
					subcode_ready       <= 1'b0;
					subcode_busy        <= 1'b0;
					subcode_state       <= SUB_IDLE;
				end
			endcase

			if (hps_cmd_pop && (hps_cmd_rd_ptr != 6'd32))
				hps_cmd_rd_ptr <= hps_cmd_rd_ptr + 6'd1;
			if (hps_cmd_done) begin
				cdrom_command_length <= 6'd0;
				hps_cmd_rd_ptr       <= 6'd0;
			end

			if (hps_cmd_done && cmd_zero_result && !hps_result_done)
				cdrom_intreq <= cdrom_intreq | CDINT_DRIVEXMIT;

			if (hps_result_push && (hps_result_wr_ptr != 6'd32)) begin
				cdrom_result_buffer[hps_result_wr_ptr[4:0]] <= hps_result_byte;
				hps_result_wr_ptr <= hps_result_wr_ptr + 6'd1;
			end
			if (hps_result_done && (cdrom_receive_length == 6'd0)) begin
				cdrom_receive_length <= hps_result_wr_ptr;
				hps_result_wr_ptr    <= 6'd0;
				if (hps_result_wr_ptr != 6'd0)
					cdrom_intreq <= cdrom_intreq | CDINT_DRIVERECV;
			end
		end
	end

	wire [31:0] cdrom_intreq_eff = cdrom_intreq | (subcode_irq ? CDINT_SUBCODE : 32'h0);

	reg [15:0] cd_dout_r;
	always @(*) begin
		cd_dout_r = 16'h0;
		case (addr)
			5'b00010: cd_dout_r = cdrom_intreq_eff[31:16];
			5'b00011: cd_dout_r = cdrom_intreq_eff[15:0];
			5'b00100: cd_dout_r = cdrom_intena[31:16];
			5'b00101: cd_dout_r = cdrom_intena[15:0];
			5'b00110: cd_dout_r = cdrom_intena[31:16];
			5'b00111: cd_dout_r = cdrom_intena[15:0];
			5'b01000, 5'b01010, 5'b01100, 5'b01110:
				cd_dout_r = {cdrom_subcodeoffset, cdcomtxinx};
			5'b01001, 5'b01011, 5'b01101, 5'b01111:
				cd_dout_r = {cdcomrxinx, 8'h0};
			5'b10000: cd_dout_r = cdrom_pbx;
			5'b10010: cd_dout_r = cdrom_flags[31:16];
			5'b10011: cd_dout_r = cdrom_flags[15:0];
			5'b10100: cd_dout_r = {pio_rx_data, 8'h0};
			5'b11000: cd_dout_r = {nvram_scl_bus, nvram_sda_bus, 6'h0, 8'h0};
			5'b11001: cd_dout_r = {nvram_dir, 8'h0};
			default:  cd_dout_r = 16'h0;
		endcase
	end

	assign cd_dout = cs ? cd_dout_r : 16'h0;
	assign cd_irq  = |(cdrom_intreq_eff[31:25] & cdrom_intena[31:25]);

	wire subcode_grant  = subcode_busy & ~rx_busy & ~pbx_busy & ~tx_busy;
	assign cd_dma_req   = tx_busy | rx_busy | pbx_busy | subcode_busy;
	assign cd_dma_we    = rx_busy | pbx_busy | subcode_grant;
	assign cd_dma_baddr = rx_busy  ? (cdrx_address + {16'h0, cdcomrxinx}) :
	                      pbx_busy ? pbx_addr :
	                      tx_busy  ? (cdtx_address + {16'h0, cdcomtxinx}) :
	                                 subcode_dma_addr;
	assign cd_dma_wbyte = rx_busy  ? cdrom_result_buffer[cdrom_receive_offset] :
	                      pbx_busy ? pbx_wbyte :
	                                 subcode_dma_byte;

	assign cd_hps_cmd_pending = cmd_pending;
	assign cd_hps_cmd_byte    = cdrom_command_buffer[hps_cmd_rd_ptr[4:0]];

	assign cd_hps_sec_req     = sec_req_w;
	assign cd_hps_sec_status  = cdrom_sector_counter;

	assign cd_hps_rx_busy     = (cdrom_receive_length != 6'd0);

	akiko_nvram nvram_inst (
		.clk              (clk),
		.reset            (1'b0),
		.scl_in           (nvram_scl_bus),
		.sda_in           (nvram_sda_bus),
		.sda_drive        (nvram_slave_sda_drive),

		.host_addr        (hps_nvr_addr),
		.host_dout        (cd_hps_nvr_dout),
		.host_clear_dirty (hps_nvr_clear_dirty),
		.nvram_dirty      (cd_hps_nvr_dirty),

		.load_addr        (nvr_load_addr),
		.load_din         (nvr_load_din),
		.load_we          (nvr_load_we)
	);

end else begin : g_stub
	assign cd_dout            = 16'h0;
	assign cd_irq             = 1'b0;
	assign cd_dma_req         = 1'b0;
	assign cd_dma_we          = 1'b0;
	assign cd_dma_baddr       = 24'h0;
	assign cd_dma_wbyte       = 8'h0;
	assign cd_hps_cmd_pending = 1'b0;
	assign cd_hps_cmd_byte    = 8'h0;
	assign cd_hps_sec_req     = 1'b0;
	assign cd_hps_sec_status  = 8'h0;
	assign cd_hps_rx_busy     = 1'b0;
	assign cd_hps_nvr_dout    = 8'h0;
	assign cd_hps_nvr_dirty   = 1'b0;
end
endgenerate

always @(*) begin
	dout = 16'h0;
	if (cs) begin
		if (addr == 5'd0) dout = 16'hC0CA;
		if (addr == 5'd1) dout = 16'hCAFE;
		if (c2p_sel)      dout = c2p_dout;
	end
	dout = dout | cd_dout;
end

assign akiko_irq = cd_irq;

assign dma_req   = cd_dma_req;
assign dma_we    = cd_dma_we;
assign dma_baddr = cd_dma_baddr;
assign dma_wbyte = cd_dma_wbyte;

assign hps_cmd_pending = cd_hps_cmd_pending;
assign hps_cmd_byte    = cd_hps_cmd_byte;

assign hps_sec_req     = cd_hps_sec_req;
assign hps_sec_status  = cd_hps_sec_status;

assign hps_rx_busy     = cd_hps_rx_busy;

assign hps_nvr_dout    = cd_hps_nvr_dout;
assign hps_nvr_dirty   = cd_hps_nvr_dirty;

endmodule
