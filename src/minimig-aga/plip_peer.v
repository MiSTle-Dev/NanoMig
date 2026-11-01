// plip_peer.v - Gegenstelle des plipbox-Protokolls (Burst) fuer den Amiga-Parallelport
//
// Gegenseite von plipbox.device (hwburstsend/hwburstrecv). Ablauf siehe
// parallelport-analyse.md, Abschnitt 10. Alles synchron zu clk (CIA-Domaene).
//
// Virtueller Port (alle Signale kommen direkt aus ciaa.v/ciab.v):
//   sel_o/sel_oe   CIA-B PRA Bit 2 (SEL) und DDRA Bit 2
//   req_o/req_oe   CIA-B PRA Bit 1 (POUT=REQ) und DDRA Bit 1
//   prb_o          CIA-A PRB Ausgaberegister, ddrb_out = DDRB==$FF (Amiga treibt)
//   prb_rd         1 Takt: Lesezugriff der CPU auf PRB ist beendet
//   rak            -> CIA-B PRA Bit 0 (BUSY) als Eingang
//   bus/bus_oe     -> CIA-A PRB Eingang, wenn DDRB==0
//   flag_n         -> CIA-A FLAG (/ACK), Low-Puls
//
// Host (Companion ueber SPI, spaeter): zwei 2-KiB-Puffer.
//   Amiga->Host: rx-Puffer, rx_valid/rx_len, Freigabe mit h_release.
//   Host->Amiga: tx-Puffer ueber h_we/h_waddr/h_wdata schreiben, h_commit mit h_len.
// Nur SEND_BURST ($33) und RECV_BURST ($44). Andere Befehle werden ignoriert.
module plip_peer #(
    parameter PULSE_CLKS   = 64,   // /ACK-Low-Puls in Takten
    parameter REPULSE_BITS = 22    // Wiederholung des Pulses nach 2^N Takten, falls der Amiga nicht reagiert
) (
    input  wire        clk,
    input  wire        rst,

    // virtueller Parallelport
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

    // Host-Seite
    input  wire        h_we,
    input  wire [10:0] h_waddr,
    input  wire [7:0]  h_wdata,
    input  wire        h_commit,
    input  wire [10:0] h_len,
    output reg         tx_valid,
    input  wire [10:0] h_raddr,
    output wire [7:0]  h_rdata,      // 1 Takt nach h_raddr
    output reg         rx_valid,
    output reg  [10:0] rx_len,
    input  wire        h_release,

    // Test und Status
    input  wire        loop_en,      // Rahmen mit Ethertype $FFFD gehen ohne Host zurueck
    output wire [31:0] stat_rx,      // Rahmen vom Amiga (16 Bit, laeuft ueber)
    output wire [31:0] stat_tx,      // Rahmen zum Amiga (16 Bit, laeuft ueber)
    output wire [31:0] rt_clks       // Takte zwischen den letzten zwei RECV-Befehlen (20 Bit, saettigt)
);

    // ---------------------------------------------------------------- Eingaenge
    wire sel = sel_o & sel_oe;       // ohne Treiber (DDRA-Bit 0) gilt 0 = Leerlauf
    wire req = req_o & req_oe;
    reg  req_q;
    always @(posedge clk) req_q <= req;
    wire req_edge = (req != req_q);

    // ---------------------------------------------------------------- Zustaende
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
    reg  [11:0] tot;               // uebertragene Bytes = size aufgerundet auf gerade
    reg  [11:0] cnt;
    reg  [10:0] wr_addr, rd_addr;
    reg  [1:0]  bsel;
`ifndef PLIP_LITE
    reg  [7:0]  et_hi, et_lo;
`endif
    reg         done_ok;           // WSEL0 wurde regulaer erreicht
    reg         pulsed;
    reg  [6:0]  pcnt;
    reg  [REPULSE_BITS-1:0] rcnt;
`ifdef PLIP_LITE
    // PLIP_LITE: ohne Statistik und ohne Loopback-Test (spart Logik im GW2AR-18)
    assign stat_rx = 32'd0;
    assign stat_tx = 32'd0;
    assign rt_clks = 32'd0;
`else
    reg  [15:0] c_rx, c_tx;        // Zaehler klein gehalten: Platz im GW2AR-18
    reg  [19:0] since, rt;
    assign stat_rx = {16'd0, c_rx};
    assign stat_tx = {16'd0, c_tx};
    assign rt_clks = {12'd0, rt};
`endif

    // Puffer
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
        for (i = 0; i < 1024; i = i + 1) begin    // Gowin: max. 2000 Schleifendurchlaeufe
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
    wire        size_bad  = (size == 16'd0) || (size > 16'd2048);

    // ---------------------------------------------------------------- Automat
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
            // ----- Host
            if (h_release) rx_valid <= 1'b0;
            if (h_commit && !tx_valid) begin
                tx_len <= h_len; tx_valid <= 1'b1; pulsed <= 1'b0;
            end

            // ----- /ACK-Puls: nur im Leerlauf, nur wenn ein Rahmen wartet
            if (pcnt != 7'd0) begin
                pcnt <= pcnt - 7'd1;
                if (pcnt == 7'd1) flag_n <= 1'b1;
            end
            if (tx_valid && st == IDLE && !sel) begin
                if (!pulsed) begin
                    flag_n <= 1'b0; pcnt <= PULSE_CLKS[6:0]; pulsed <= 1'b1; rcnt <= {REPULSE_BITS{1'b0}};
                end else begin
                    rcnt <= rcnt + 1'b1;
                    if (&rcnt) pulsed <= 1'b0;      // Puls ging vermutlich verloren: wiederholen
                end
            end

            // ----- Abbruch: SEL faellt mitten im Transfer
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

                // ---- Amiga sendet
                SB_HI: if (req) begin
                    size[15:8] <= prb_o; rak <= 1'b0; st <= SB_LO;
                end
                SB_LO: if (!req) begin
                    size[7:0] <= prb_o; st <= SB_GO;
                end
                SB_GO: begin
                    tot <= size_even;
                    if (!size_bad && !rx_valid) begin     // Puffer frei: Burst freigeben
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

                // ---- Amiga empfaengt
                RB_1: if (req) begin
                    bus_oe <= 1'b1; bsel <= 2'd0; rak <= 1'b0; st <= RB_0;
                end
                RB_0: if (!req) begin
                    bsel <= 2'd1; rak <= 1'b1; tot <= size_even; st <= RB_1b;
                end
                RB_1b: if (req) begin
                    if (size == 16'd0) begin
                        done_ok <= 1'b1; st <= WSEL0;     // leere Antwort, Amiga beendet selbst
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

                // ---- Ende: Amiga nimmt SEL weg
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
                        if (done_ok && cmd == 8'h44 && size != 16'd0) begin   // Rahmen wurde geliefert
                            tx_valid <= 1'b0; pulsed <= 1'b0;
`ifndef PLIP_LITE
                            c_tx <= c_tx + 16'd1;
`endif
                        end
                        st <= IDLE;
                    end
                end

`ifndef PLIP_LITE
                // ---- Loopback-Test: rx -> tx kopieren (2 Takte je Byte)
                COPY: begin
                    if (!cp_ph) begin
                        cp_ph <= 1'b1;                     // rxq folgt cp_a im naechsten Takt
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
