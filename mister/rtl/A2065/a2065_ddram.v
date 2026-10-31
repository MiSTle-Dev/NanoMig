/*
 * a2065_ddram.v
 *
 * 68k boardram DDR3 window — clk_sys interface module.
 *
 * Handles the 68k bus side of boardram access: address decode, request
 * latch, DTACK stretch, and CDC handshake with the DDRAM_CLK mailbox
 * FSM that performs the actual DDR3 read/write.
 *
 * Port A (68k bus, clk_sys):
 *   - sel + cpu_addr[15] selects boardram at card+0x8000
 *   - DTACK-stretched: nrdy asserted until DDR3 response arrives
 *   - cpu_data_out driven on read completion
 *
 * The DDRAM_CLK FSM (in a2065_ddr3_mailbox) sees the request via CDC,
 * performs DDR3 access, and signals completion back via CDC.
 */

module a2065_ddram (
    input  wire         clk_sys,
    input  wire         rst_n_sys,

    input  wire [23:1]  cpu_addr,
    input  wire [15:0]  cpu_data_in,
    output wire [15:0]  cpu_data_out,
    input  wire         cpu_rw,      // 68k R/W: 1=read, 0=write
    input  wire         cpu_as_n,    // address strobe (active low)
    input  wire         cpu_uds_n,   // upper data strobe (active low) — even byte D[15:8]
    input  wire         cpu_lds_n,   // lower data strobe (active low) — odd byte  D[7:0]
    input  wire         sel,
    output wire         nrdy,

    output reg          bram_req_valid,
    output reg  [13:0]  bram_req_addr,
    output reg  [15:0]  bram_req_wdata,
    output reg          bram_req_rw,
    output reg  [1:0]   bram_req_be,   // byte enables {high=UDS, low=LDS}

    input  wire         bram_req_ack_audio,
    input  wire         bram_resp_valid_audio,
    input  wire [15:0]  bram_resp_data_audio
);

    // Qualify the access with AS+DS like a2065_regfile does: only capture
    // when the strobes are asserted, so the direction (cpu_rw) and write
    // data (cpu_data_in) are valid.  Keying off raw sel during the address
    // phase captured before hwr/lwr/data were valid.  DS deasserts between
    // bus cycles, giving a clean NR_DONE->NR_IDLE separation (no edge detect).
    wire cpu_ds_n = cpu_uds_n & cpu_lds_n;   // any strobe asserted
    wire sel_br   = sel && cpu_addr[15] && !cpu_as_n && !cpu_ds_n;
    wire is_write = ~cpu_rw;
    wire [1:0] req_be = {~cpu_uds_n, ~cpu_lds_n};
    wire [13:0] word_idx = cpu_addr[14:1];

    reg  [15:0] rd_data;
    // Gate the read data onto the shared CPU data bus only while this card's
    // boardram is the read target, so the held value can't corrupt the OR-mux
    // for other peripherals' reads.
    assign cpu_data_out = (sel && cpu_addr[15] && cpu_rw) ? rd_data : 16'h0000;

    reg  sys_req;
    reg  sys_got_resp;

    reg  ack_sync0, ack_sync1;
    reg  rv_sync0, rv_sync1;
    reg [15:0] rd_sync0, rd_sync1;

    reg  [1:0] nrdy_state;
    localparam NR_IDLE  = 2'd0;
    localparam NR_WAIT  = 2'd1;
    localparam NR_DONE  = 2'd2;

    reg  [15:0] wd_cnt;
    wire        wd_timeout = &wd_cnt;

    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            sys_req       <= 1'b0;
            sys_got_resp  <= 1'b0;
            rd_data       <= 16'h0000;
            bram_req_valid <= 1'b0;
            bram_req_addr  <= 0;
            bram_req_wdata <= 0;
            bram_req_rw    <= 1'b0;
            bram_req_be    <= 2'b11;
            ack_sync0  <= 1'b0;
            ack_sync1  <= 1'b0;
            rv_sync0   <= 1'b0;
            rv_sync1   <= 1'b0;
            rd_sync0   <= 16'd0;
            rd_sync1   <= 16'd0;
        end else begin
            sys_got_resp <= 1'b0;

            ack_sync0 <= bram_req_ack_audio;
            ack_sync1 <= ack_sync0;

            rv_sync0 <= bram_resp_valid_audio;
            rv_sync1 <= rv_sync0;

            rd_sync0 <= bram_resp_data_audio;
            rd_sync1 <= rd_sync0;

            /* The request is withdrawn on the response, not on the capture
             * ack: the mailbox holds its reply lines until it sees the request
             * drop, so dropping it any earlier would retire the handshake
             * before the read data had been taken. bram_req_ack only reports
             * that the request was picked up. */
            if (sys_req && (rv_sync1 || wd_timeout)) begin
                sys_req        <= 1'b0;
                bram_req_valid <= 1'b0;
            end

            if (rv_sync1) begin
                sys_got_resp <= 1'b1;
                rd_data <= rd_sync1;
            end

            if (sel_br && !sys_req && !sys_got_resp && nrdy_state == NR_IDLE) begin
                bram_req_addr  <= word_idx;
                bram_req_wdata <= cpu_data_in;
                bram_req_rw    <= is_write;
                bram_req_be    <= req_be;
                bram_req_valid <= 1'b1;
                sys_req        <= 1'b1;
            end
        end
    end

    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            nrdy_state <= NR_IDLE;
            wd_cnt     <= 16'd0;
        end else begin
            case (nrdy_state)
            NR_IDLE: begin
                if (sel_br && !sys_req && !sys_got_resp) begin
                    nrdy_state <= NR_WAIT;
                    wd_cnt     <= 16'd0;
                end
            end
            NR_WAIT: begin
                if (rv_sync1 || wd_timeout)
                    nrdy_state <= NR_DONE;
                else
                    wd_cnt <= wd_cnt + 16'd1;
            end
            NR_DONE: begin
                if (!sel_br)
                    nrdy_state <= NR_IDLE;
            end
            default: nrdy_state <= NR_IDLE;
            endcase
        end
    end

    assign nrdy = (nrdy_state == NR_WAIT);

endmodule
