//
// sdram.sv
//
// sdram controller implementation for the MiSTer SDRAM, the TN20k etc
//
// Copyright (c) 2024 Till Harbaum <till@harbaum.org>
// Copyright (c) 2026 Mateusz Nalewajski <mateusz@nalewajski.pl>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

// This should work for various RAM sized in 16 or 32 data widths.
//
// Example 1: TN20k internal sdram
// 32 data, 4 dqm, 11 RAS, 2 bank, 8 CAS
//     -> 2^(11+2+8)*(32/8) = 8388608 = 8MB
// address map:  BA:21..20 RAS:19..9 CAS:8..1  data mux: 0
//
// Example 2: MiSTer RAM module
// 16 data, 2 dqm, 13 RAS, 2 bank, 9 CAS
//     -> 2^(13+2+9)*(16/8) = 33554432 = 32MB
// address map:  BA:--  RAS:21..9 CAS:8..0  no data mux

`ifdef YOSYS
`define ITOR(x) $itor(x)
`define RTOI(x) $rtoi(x)
`else
`define ITOR(x) (real'(int'(x)))
`define RTOI(x) (int'(real'(x)))
`endif

`define CEIL(x) `RTOI($ceil(x))

`default_nettype none

module sdram #(
  parameter DATA_WIDTH = 16,
  parameter RAS_WIDTH  = 13,
  parameter CAS_WIDTH  =  9,
  parameter RAM_CLOCK_SPEED  = 85_000_000,
  parameter SYNC_CLOCK_SPEED =  7_080_000
) (
  input  wire clk,
  input  wire reset_n,  // init signal after FPGA config to initialize RAM
  output wire ready,    // ram is ready and has been initialized

  inout  wire [DATA_WIDTH-1:0]   sd_data, // 16/32 bit bidirectional data bus
  output reg  [RAS_WIDTH-1:0]    sd_addr, // multiplexed address bus
  output reg  [DATA_WIDTH/8-1:0] sd_dqm,  // two/four byte masks
  output reg  [1:0]              sd_ba,   // four banks

  output reg  sd_cke,  // clock enable
  output wire sd_cs,   // single chip select
  output wire sd_we,   // write enable
  output wire sd_ras,  // row address select
  output wire sd_cas,  // columns address select

  // chipset interface
  input  wire sync,     // chipset synchronization
  input  wire refresh,  // chipset requests a refresh cycle

  input  wire [15:0] din,     // data input from chipset
  output reg  [15:0] dout,    // data output for chipset
  output reg  [47:0] dout48,  // 64-bit read data output for chipset

  input wire [21:0] addr,  // 22 bit word address for 8MB
  input wire  [1:0] ds,    // upper/lower data strobe
  input wire        cs,    // chipset requests read/write
  input wire        we,    // chipset requests write
  output reg        ack,

  // cpu interface
  input  wire [15:0] p2_din,   // data input from cpu
  output reg  [15:0] p2_dout,  // data output to cpu

  input  wire [22:0] p2_addr,  // 23 bit word address
  input  wire  [1:0] p2_ds,    // upper/lower data strobe
  input  wire        p2_cs,    // cpu requests read/wrie
  input  wire        p2_we,    // cpu requests write
  output reg         p2_ack
);

localparam WIDTH32 = (DATA_WIDTH == 32);

localparam BURST_LENGTH   = 3'b010;  // 000 = 1, 001 = 2, 010 = 4, 011 = 8
localparam ACCESS_TYPE    = 1'b0;    // 0 = sequential, 1 = interleaved
localparam CAS_LATENCY    = 3'd2;    // 2/3 allowed
localparam OP_MODE        = 2'b00;   // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;    // 0 = write burst enabled, 1 = only single access write

localparam MODE = {3'b0, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

// expand to from 22 to 32 address bits internally to be able to drive bigger rams as well
// and shift one bit for 32 bit data bus as addr[0] is used to multiplex between
// both 16 bit data words
localparam ADDR_BASE = WIDTH32 ? 1 : 0;

wire [31:0]    addr32 = { {(10+ADDR_BASE){1'b0}},    addr[21:ADDR_BASE]};
wire [31:0] p2_addr32 = { {( 9+ADDR_BASE){1'b0}}, p2_addr[22:ADDR_BASE]};

reg addr_0;

localparam real CLOCK_PERIOD_NANO_SEC = 1.0e9 / `ITOR(RAM_CLOCK_SPEED);
localparam real SYNC_PERIOD_NANO_SEC  = 1.0e9 / `ITOR(SYNC_CLOCK_SPEED);

localparam real SETTING_INHIBIT_DELAY_MICRO_SEC = 100;

// tRFC - Min autorefresh period
localparam real SETTING_T_RFC_MIN_AUTOREFRESH_PERIOD_NANO_SEC = 60;

// tRP - Min precharge command period
localparam real SETTING_T_RP_MIN_PRECHARGE_CMD_PERIOD_NANO_SEC = 15;

// 8,192 refresh commands every 64ms = 7.8125us, which we round to 7500ns to make sure we hit them all
localparam real SETTING_REFRESH_TIMER_NANO_SEC = 7500;

// Number of cycles for autorefresh duration
localparam CLOCK_CYCLES_FOR_AUTOREFRESH =
    `CEIL(SETTING_T_RFC_MIN_AUTOREFRESH_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

// Number of cycles after reset until we clear command inhibit and start operation
// We add 100 cycles for good measure
localparam CLOCK_CYCLES_UNTIL_INIT_PRECHARGE = 100 +
    `CEIL(SETTING_INHIBIT_DELAY_MICRO_SEC * 1000.0 / CLOCK_PERIOD_NANO_SEC);

// Number of cycles after reset until we are done with precharge
// We add 10 cycles for good measure
localparam CLOCK_CYCLES_UNTIL_INIT_PRECHARGE_END = 10 + CLOCK_CYCLES_UNTIL_INIT_PRECHARGE +
    `CEIL(SETTING_T_RP_MIN_PRECHARGE_CMD_PERIOD_NANO_SEC / CLOCK_PERIOD_NANO_SEC);

localparam CLOCK_CYCLES_UNTIL_REFRESH1_END = CLOCK_CYCLES_UNTIL_INIT_PRECHARGE_END + CLOCK_CYCLES_FOR_AUTOREFRESH;
localparam CLOCK_CYCLES_UNTIL_REFRESH2_END = CLOCK_CYCLES_UNTIL_REFRESH1_END + CLOCK_CYCLES_FOR_AUTOREFRESH;

// tMRD = 2 - Min number of clock cycles between mode set and normal usage
localparam CLOCK_CYCLES_UNTIL_INIT_DONE = CLOCK_CYCLES_UNTIL_REFRESH2_END + 2;

localparam INIT_COUNTER_MAX   = CLOCK_CYCLES_UNTIL_INIT_DONE;
localparam INIT_COUNTER_WIDTH = $clog2(INIT_COUNTER_MAX + 1);

reg [INIT_COUNTER_WIDTH-1:0] init_counter = 0;

// Number of sync cycles between each autorefresh command
localparam SYNC_CYCLES_PER_REFRESH =
    `CEIL(SETTING_REFRESH_TIMER_NANO_SEC / SYNC_PERIOD_NANO_SEC);

localparam REFRESHCNT_MAX       = SYNC_CYCLES_PER_REFRESH;
localparam REFRESHCNT_MAX_WIDTH = $clog2(REFRESHCNT_MAX + 1);

reg [REFRESHCNT_MAX_WIDTH-1:0] refreshcnt;

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

localparam STATE_INIT       = 0;
localparam STATE_RAS        = 1;  // first state in cycle
localparam STATE_RAS_WAIT_0 = 2;
localparam STATE_CAS        = 3;
localparam STATE_CAS_WAIT_0 = 4;
localparam STATE_CAS_WAIT_1 = 5;
localparam STATE_READ_0     = 6;
localparam STATE_READ_1     = 7;
localparam STATE_READ_2     = 8;
localparam STATE_READ_3     = 9;
localparam STATE_LAST       = STATE_READ_3;

localparam STATE_WIDTH = $clog2(STATE_LAST + 1);

reg [STATE_WIDTH-1:0] state;

wire       sync_i;
reg  [1:0] sync_d;

always @(posedge clk, negedge reset_n) begin
  if (!reset_n)
    sync_d <= 0;
  else
    sync_d <= {sync_d[0], sync};
end

assign sync_i = sync_d[1] && !sync_d[0];
assign ready  = (state != STATE_INIT);

always @(posedge clk, negedge reset_n) begin
  if (!reset_n) begin
    init_counter <= 0;
    state        <= STATE_INIT;

  end else begin
    case (state)
      STATE_INIT: begin
        init_counter <= init_counter + 1;

        if (init_counter == CLOCK_CYCLES_UNTIL_INIT_DONE[INIT_COUNTER_WIDTH-1:0])
          state <= STATE_RAS;
      end
      STATE_RAS:
        if (sync_i) state <= STATE_RAS_WAIT_0;
      STATE_RAS_WAIT_0:
        state <= STATE_CAS;
      STATE_CAS:
        state <= STATE_CAS_WAIT_0;
      STATE_CAS_WAIT_0:
        state <= STATE_CAS_WAIT_1;
      STATE_CAS_WAIT_1:
        state <= STATE_READ_0;
      STATE_READ_0:
        state <= STATE_READ_1;
      STATE_READ_1:
        state <= STATE_READ_2;
      STATE_READ_2:
        state <= STATE_READ_3;
      STATE_READ_3:
        state <= STATE_RAS;
    endcase
  end
end

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_NOP             = 3'b111;
localparam CMD_ACTIVE          = 3'b011;
localparam CMD_READ            = 3'b101;
localparam CMD_WRITE           = 3'b100;
localparam CMD_BURST_TERMINATE = 3'b110;
localparam CMD_PRECHARGE       = 3'b010;
localparam CMD_AUTO_REFRESH    = 3'b001;
localparam CMD_LOAD_MODE       = 3'b000;

reg [2:0] sd_cmd;   // current command sent to sd ram

// drive control signals according to current command
assign sd_cs  = 1'b0;
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];

reg  [15:0] ram_din;

wire [15:0] ram_dout_lo;
wire [15:0] ram_dout_hi;
wire [15:0] ram_dout;

reg                 sd_dq;
reg [RAS_WIDTH-1:0] sd_addr_cas;

generate
  if (WIDTH32) begin
    assign ram_dout_lo = sd_data[15: 0];
    assign ram_dout_hi = sd_data[31:16];
    assign ram_dout    = (addr_0 ? ram_dout_lo : ram_dout_hi);
    assign sd_data     = sd_dq ? {ram_din, ram_din} : {DATA_WIDTH{1'bz}};

  end else begin
    assign ram_dout_lo = sd_data;
    assign ram_dout_hi = sd_data;
    assign ram_dout    = sd_data;
    assign sd_data     = sd_dq ? ram_din : {DATA_WIDTH{1'bz}};
  end
endgenerate

localparam PORT_1       = 2'd0;
localparam PORT_2       = 2'd1;
localparam PORT_REFRESH = 2'd2;
localparam PORT_IDLE    = 2'd3;

reg [1:0] sdram_port;

always @(posedge clk, negedge reset_n) begin
  if (!reset_n)
    sd_cke <= 0;
  else
    sd_cke <= 1;
end

always @(posedge clk) begin
  sd_cmd <= CMD_NOP;
  sd_dq  <= 0;

  case (state)
    STATE_INIT: begin
      sdram_port <= PORT_IDLE;
      refreshcnt <= SYNC_CYCLES_PER_REFRESH[REFRESHCNT_MAX_WIDTH-1:0];

      if (init_counter == CLOCK_CYCLES_UNTIL_INIT_PRECHARGE[INIT_COUNTER_WIDTH-1:0]) begin
        sd_cmd <= CMD_PRECHARGE;
        sd_addr[10] <= 1'b1;
      end else if (init_counter == CLOCK_CYCLES_UNTIL_INIT_PRECHARGE_END[INIT_COUNTER_WIDTH-1:0]) begin
        sd_cmd <= CMD_AUTO_REFRESH;
      end else if (init_counter == CLOCK_CYCLES_UNTIL_REFRESH1_END[INIT_COUNTER_WIDTH-1:0]) begin
        sd_cmd <= CMD_AUTO_REFRESH;
      end else if (init_counter == CLOCK_CYCLES_UNTIL_REFRESH2_END[INIT_COUNTER_WIDTH-1:0]) begin
        sd_cmd  <= CMD_LOAD_MODE;
        sd_addr <= MODE;
      end
    end
    STATE_RAS: begin
      if (cs) begin
        sd_addr <= addr32[RAS_WIDTH+CAS_WIDTH-1:CAS_WIDTH];

        sd_addr_cas[RAS_WIDTH-1:0] <= {RAS_WIDTH{1'b0}};
        sd_addr_cas[CAS_WIDTH-1:0] <= addr32[CAS_WIDTH-1:0];
        sd_addr_cas[10] <= 1'b1;  // precharge

        sd_ba   <= addr32[RAS_WIDTH+CAS_WIDTH+1:RAS_WIDTH+CAS_WIDTH];
        addr_0  <= addr[0];

      end else if (p2_cs) begin
        sd_addr <= p2_addr32[RAS_WIDTH+CAS_WIDTH-1:CAS_WIDTH];

        sd_addr_cas[RAS_WIDTH-1:0] <= {RAS_WIDTH{1'b0}};
        sd_addr_cas[CAS_WIDTH-1:0] <= p2_addr32[CAS_WIDTH-1:0];
        sd_addr_cas[10] <= 1'b1;  // precharge

        sd_ba   <= p2_addr32[RAS_WIDTH+CAS_WIDTH+1:RAS_WIDTH+CAS_WIDTH];
        addr_0  <= p2_addr[0];
      end

      if (sync_i) begin
        if (refreshcnt != 0)
          refreshcnt <= refreshcnt - 1;

        if (cs && !refresh) begin
          sdram_port <= PORT_1;
          sd_cmd <= CMD_ACTIVE;

        end else if (refreshcnt == 0 || (cs && refresh)) begin
          sdram_port <= PORT_REFRESH;
          sd_cmd <= CMD_AUTO_REFRESH;

          refreshcnt <= SYNC_CYCLES_PER_REFRESH[REFRESHCNT_MAX_WIDTH-1:0];

        end else if (p2_cs) begin
          sdram_port <= PORT_2;
          sd_cmd <= CMD_ACTIVE;
        end
      end
    end
    STATE_CAS: begin
      sd_addr <= sd_addr_cas;

      case (sdram_port)
        PORT_1: begin
          sd_cmd <= we ? CMD_WRITE : CMD_READ;
          ram_din <= din;
          if (we) begin
            sd_dq <= 1;
            ack   <= ~ack;
          end
        end
        PORT_2: begin
          sd_cmd <= p2_we ? CMD_WRITE : CMD_READ;
          ram_din <= p2_din;
          if (p2_we) begin
            sd_dq  <= 1;
            p2_ack <= ~p2_ack;
          end
        end
        default: ;
      endcase
    end
    STATE_READ_0: begin
      case (sdram_port)
        PORT_1 : begin
          dout <= ram_dout;
          if (!we) ack <= ~ack;
        end
        PORT_2 : begin
          p2_dout <= ram_dout;
          if (!p2_we) p2_ack <= ~p2_ack;
        end
        default: ;
      endcase
    end
    STATE_LAST: begin
      sdram_port <= PORT_IDLE;
    end
    default: ;
  endcase
end

generate
  if (WIDTH32) begin
    always @(posedge clk) begin
      sd_dqm <= 0;

      case (state)
        STATE_CAS: begin
          case (sdram_port)
            PORT_1: if (we)    sd_dqm <= (addr_0 ? {2'b11,    ds} : {ds,    2'b11});
            PORT_2: if (p2_we) sd_dqm <= (addr_0 ? {2'b11, p2_ds} : {p2_ds, 2'b11});
            default: ;
          endcase
        end
        STATE_READ_0: begin
          case (sdram_port)
            PORT_1: dout48[47:32] <= ram_dout_lo;
            default: ;
          endcase
        end
        STATE_READ_1: begin
          case (sdram_port)
            PORT_1: begin
              if (addr_0)
                dout48[47:16] <= {ram_dout_hi, ram_dout_lo};
              else
                dout48[31: 0] <= {ram_dout_hi, ram_dout_lo};
            end
            default: ;
          endcase
        end
        STATE_READ_2: begin
          case (sdram_port)
            PORT_1: begin
              if (addr_0)
                dout48[15:0] <= {ram_dout_hi};
              else
                /* no-op */;
            end
            default: ;
          endcase
        end
        default: ;
      endcase
    end

  end else begin
    always @(posedge clk) begin
      sd_dqm <= 0;

      case (state)
        STATE_CAS: begin
          case (sdram_port)
            PORT_1: if (we)    sd_dqm <= ds;
            PORT_2: if (p2_we) sd_dqm <= p2_ds;
            default: ;
          endcase
        end
        STATE_READ_1: begin
          case (sdram_port)
            PORT_1: dout48[47:32] <= ram_dout;
            default: ;
          endcase
        end
        STATE_READ_2: begin
          case (sdram_port)
            PORT_1: dout48[31:16] <= ram_dout;
            default: ;
          endcase
        end
        STATE_READ_3: begin
          case (sdram_port)
            PORT_1: dout48[15: 0] <= ram_dout;
            default: ;
          endcase
        end
        default: ;
      endcase
    end
  end
endgenerate

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
