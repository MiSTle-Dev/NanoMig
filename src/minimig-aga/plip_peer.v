// plip_peer.v - peer of the plipbox burst protocol for the Amiga parallel port
//
// Counterpart of plipbox.device (hwburstsend/hwburstrecv). Everything is
// synchronous to clk (CIA domain).
//
// Virtual port (all signals come directly from ciaa.v/ciab.v):
//   sel_o/sel_oe   CIA-B PRA bit 2 (SEL) and DDRA bit 2
//   req_o/req_oe   CIA-B PRA bit 1 (POUT=REQ) and DDRA bit 1
//   prb_o          CIA-A PRB output register, ddrb_out = DDRB==$FF (the Amiga drives the bus)
//   prb_rd         1 clock: the CPU read access to PRB has finished
//   rak            -> CIA-B PRA bit 0 (BUSY) as input
//   bus/bus_oe     -> CIA-A PRB input, when DDRB==0
//   flag_n         -> CIA-A FLAG (/ACK), low pulse
//
// Host side (the FPGA Companion over SPI, see plip_host.v): two 2 KiB buffers.
//   Amiga->host: rx buffer, rx_valid/rx_len, released with h_release.
//   Host->Amiga: write the tx buffer through h_we/h_waddr/h_wdata, then h_commit with h_len.
// Only SEND_BURST ($33) and RECV_BURST ($44). Other commands are ignored.
module plip_peer #(
    parameter PULSE_CLKS   = 64,   // /ACK low pulse in clocks
    parameter REPULSE_BITS = 22    // repeat the pulse after 2^N clocks if the Amiga does not react
) (
    input  wire        clk,
    input  wire        rst,

    // virtual parallel port
    input  wire        sel_o,
    input  wire        sel_oe,
    input  wire        req_o,
    input  wire        req_oe,
    input  wire [7:0]  prb_o,
    input  wire        ddrb_out,
    input  wire        prb_rd,
    output reg         rak,
    output wire [7:0]  bus,
    output reg         bus_oe,
    output reg         flag_n,

    // host side
    input  wire        h_we,
    input  wire [10:0] h_waddr,
    input  wire [7:0]  h_wdata,
    input  wire        h_commit,
    input  wire [10:0] h_len,
    output reg         tx_valid,
    input  wire [10:0] h_raddr,
    output wire [7:0]  h_rdata,      // 1 clock after h_raddr
    output reg         rx_valid,
    output reg  [10:0] rx_len,
    input  wire        h_release,

    // test and status
    input  wire        loop_en,      // frames with ethertype $FFFD are echoed without the host
    output wire [31:0] stat_rx,      // frames from the Amiga (16 bit, wraps around)
    output wire [31:0] stat_tx,      // frames to the Amiga (16 bit, wraps around)
    output wire [31:0] rt_clks       // clocks between the last two RECV commands (20 bit, saturates)
);

    // ---------------------------------------------------------------- inputs
    wire sel = sel_o & sel_oe;       // without a driver (DDRA bit 0) 0 = idle
    wire req = req_o & req_oe;
    reg  req_q;
    always @(posedge clk) req_q <= req;
    wire req_edge = (req != req_q);

    // ---------------------------------------------------------------- states
    localparam [3:0]
        IDLE     = 4'd0,
        SB_HI    = 4'd1,
        SB_LO    = 4'd2,
        SB_GO    = 4'd3,
        SB_BURST = 4'd4,
        SB_X1    = 4'd5,
        SB_X0    = 4'd6,
        RB_1     = 4'd7,
        RB_0     = 4'd8,
        RB_1b    = 4'd9,
        RB_BURST = 4'd10,
        RB_E0    = 4'd11,
        RB_E1    = 4'd12,
        WSEL0    = 4'd13,
        COPY     = 4'd14;

    reg  [3:0]  st;
    reg  [7:0]  cmd;
    reg  [15:0] size;
    reg  [10:0] tx_len;
    reg  [11:0] tot;               // transferred bytes = size rounded up to even
    reg  [11:0] cnt;
    reg  [10:0] wr_addr, rd_addr;
    reg  [1:0]  bsel;
`ifndef PLIP_LITE
    reg  [7:0]  et_hi, et_lo;
`endif
    reg         done_ok;           // WSEL0 was reached regularly
    reg         pulsed;
    reg  [6:0]  pcnt;
    reg  [REPULSE_BITS-1:0] rcnt;
`ifdef PLIP_LITE
    // PLIP_LITE: no statistics and no loopback test (saves logic in the GW2AR-18)
    assign stat_rx = 32'd0;
    assign stat_tx = 32'd0;
    assign rt_clks = 32'd0;
`else
    reg  [15:0] c_rx, c_tx;        // counters kept small: room in the GW2AR-18
    reg  [19:0] since, rt;
    assign stat_rx = {16'd0, c_rx};
    assign stat_tx = {16'd0, c_tx};
    assign rt_clks = {12'd0, rt};
`endif

    // buffers
    reg  [7:0]  mem_rx [0:2047];
    reg  [7:0]  mem_tx [0:2047];
    reg  [7:0]  rxq, txq;
    reg         rx_we;
    reg  [10:0] rx_wa;
    reg  [7:0]  rx_wd;
`ifdef PLIP_LITE
    wire [10:0] rx_ra = h_raddr;
`else
    reg         cp_we;
    reg  [10:0] cp_a, cp_wa;
    reg         cp_ph;
    wire [10:0] rx_ra = (st == COPY) ? cp_a : h_raddr;
`endif

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin    // Gowin: at most 2000 loop iterations
            mem_rx[i] = 8'h00;  mem_rx[i + 1024] = 8'h00;
            mem_tx[i] = 8'h00;  mem_tx[i + 1024] = 8'h00;
        end
    end

    always @(posedge clk) begin
        if (rx_we) mem_rx[rx_wa] <= rx_wd;
        rxq <= mem_rx[rx_ra];
    end

    always @(posedge clk) begin
`ifdef PLIP_LITE
        if (h_we) mem_tx[h_waddr] <= h_wdata;
`else
        if (cp_we)     mem_tx[cp_wa] <= rxq;
        else if (h_we) mem_tx[h_waddr] <= h_wdata;
`endif
        txq <= mem_tx[rd_addr];
    end

    assign h_rdata = rxq;
    assign bus     = (bsel == 2'd0) ? size[15:8] :
                     (bsel == 2'd1) ? size[7:0]  : txq;

    wire [11:0] size_even = (size[11:0] + 12'd1) & 12'hFFE;
    wire        size_bad  = (size == 16'd0) || (size > 16'd2047);   // rx_len has 11 bits

    // ---------------------------------------------------------------- state machine
    always @(posedge clk) begin
`ifndef PLIP_LITE
        if (~&since) since <= since + 20'd1;
`endif
        rx_we   <= 1'b0;
`ifndef PLIP_LITE
        cp_we   <= 1'b0;
`endif

        if (rst) begin
            st <= IDLE; rak <= 1'b0; bus_oe <= 1'b0; bsel <= 2'd0;
            rx_valid <= 1'b0; tx_valid <= 1'b0; rx_len <= 11'd0; tx_len <= 11'd0;
            flag_n <= 1'b1; pulsed <= 1'b0; pcnt <= 7'd0; rcnt <= {REPULSE_BITS{1'b0}};
`ifndef PLIP_LITE
            c_rx <= 16'd0; c_tx <= 16'd0; rt <= 20'd0; since <= 20'd0;
`endif
            done_ok <= 1'b0;
            rd_addr <= 11'd0; wr_addr <= 11'd0; cnt <= 12'd0; size <= 16'd0;
        end else begin
            // ----- host
            if (h_release) rx_valid <= 1'b0;
            if (h_commit && !tx_valid) begin
                tx_len <= h_len; tx_valid <= 1'b1; pulsed <= 1'b0;
            end

            // ----- /ACK pulse: only when idle, only while a frame is waiting
            if (pcnt != 7'd0) begin
                pcnt <= pcnt - 7'd1;
                if (pcnt == 7'd1) flag_n <= 1'b1;
            end
            if (tx_valid && st == IDLE && !sel) begin
                if (!pulsed) begin
                    flag_n <= 1'b0; pcnt <= PULSE_CLKS[6:0]; pulsed <= 1'b1; rcnt <= {REPULSE_BITS{1'b0}};
                end else begin
                    rcnt <= rcnt + 1'b1;
                    if (&rcnt) pulsed <= 1'b0;      // the pulse was probably lost: repeat it
                end
            end

            // ----- abort: SEL falls in the middle of a transfer
            if (st != IDLE && st != WSEL0 && st != COPY && !sel) begin
                rak <= 1'b0; bus_oe <= 1'b0; bsel <= 2'd0; st <= IDLE;
            end else begin
                case (st)
                IDLE: begin
                    if (sel && !req && ddrb_out) begin
                        cmd <= prb_o;
                        if (prb_o == 8'h33) begin
                            rak <= 1'b1; st <= SB_HI;
                        end else if (prb_o == 8'h44) begin
                            size    <= tx_valid ? {5'd0, tx_len} : 16'd0;
                            rd_addr <= 11'd0;
`ifndef PLIP_LITE
                            rt <= since; since <= 20'd0;
`endif
                            rak <= 1'b1; st <= RB_1;
                        end
                    end
                end

                // ---- Amiga sends
                SB_HI: if (req) begin
                    size[15:8] <= prb_o; rak <= 1'b0; st <= SB_LO;
                end
                SB_LO: if (!req) begin
                    size[7:0] <= prb_o; st <= SB_GO;
                end
                SB_GO: begin
                    tot <= size_even;
                    if (!size_bad && !rx_valid) begin     // buffer free: release the burst
                        rak <= 1'b1; cnt <= 12'd0; wr_addr <= 11'd0; st <= SB_BURST;
                    end
                end
                SB_BURST: if (req_edge) begin
                    rx_we <= 1'b1; rx_wa <= wr_addr; rx_wd <= prb_o;
`ifndef PLIP_LITE
                    if (wr_addr == 11'd12) et_hi <= prb_o;
                    if (wr_addr == 11'd13) et_lo <= prb_o;
`endif
                    wr_addr <= wr_addr + 11'd1;
                    cnt     <= cnt + 12'd1;
                    if (cnt + 12'd1 == tot) st <= SB_X1;
                end
                SB_X1: if (req)  begin rak <= 1'b0; st <= SB_X0; end
                SB_X0: if (!req) begin rak <= 1'b1; done_ok <= 1'b1; st <= WSEL0; end

                // ---- Amiga receives
                RB_1: if (req) begin
                    bus_oe <= 1'b1; bsel <= 2'd0; rak <= 1'b0; st <= RB_0;
                end
                RB_0: if (!req) begin
                    bsel <= 2'd1; rak <= 1'b1; tot <= size_even; st <= RB_1b;
                end
                RB_1b: if (req) begin
                    if (size == 16'd0) begin
                        done_ok <= 1'b1; st <= WSEL0;     // empty reply, the Amiga ends it itself
                    end else begin
                        bsel <= 2'd2; rak <= 1'b0; cnt <= 12'd0; st <= RB_BURST;
                    end
                end
                RB_BURST: if (prb_rd) begin
                    rd_addr <= rd_addr + 11'd1;
                    cnt     <= cnt + 12'd1;
                    if (cnt + 12'd1 == tot) st <= RB_E0;
                end
                RB_E0: if (!req) begin rak <= 1'b1; st <= RB_E1; end
                RB_E1: if (req)  begin rak <= 1'b0; done_ok <= 1'b1; st <= WSEL0; end

                // ---- end: the Amiga releases SEL
                WSEL0: if (!sel) begin
                    rak <= 1'b0; bus_oe <= 1'b0; bsel <= 2'd0;
                    done_ok <= 1'b0;
                    if (done_ok && cmd == 8'h33) begin
`ifndef PLIP_LITE
                        c_rx <= c_rx + 16'd1;
                        if (loop_en && et_hi == 8'hFF && et_lo == 8'hFD && !tx_valid) begin
                            cnt <= 12'd0; cp_ph <= 1'b0; cp_a <= 11'd0; st <= COPY;
                        end else
`endif
                        begin
                            rx_len <= size[10:0]; rx_valid <= 1'b1; st <= IDLE;
                        end
                    end else begin
                        if (done_ok && cmd == 8'h44 && size != 16'd0) begin   // frame was delivered
                            tx_valid <= 1'b0; pulsed <= 1'b0;
`ifndef PLIP_LITE
                            c_tx <= c_tx + 16'd1;
`endif
                        end
                        st <= IDLE;
                    end
                end

`ifndef PLIP_LITE
                // ---- loopback test: copy rx -> tx (2 clocks per byte)
                COPY: begin
                    if (!cp_ph) begin
                        cp_ph <= 1'b1;                     // rxq follows cp_a in the next clock
                    end else begin
                        cp_we <= 1'b1; cp_wa <= cp_a; cp_ph <= 1'b0;
                        cnt   <= cnt + 12'd1;
                        if (cnt + 12'd1 == tot) begin
                            tx_len <= size[10:0]; tx_valid <= 1'b1; pulsed <= 1'b0; st <= IDLE;
                        end else cp_a <= cp_a + 11'd1;
                    end
                end
`endif
                default: st <= IDLE;
                endcase
            end
        end
    end
endmodule
