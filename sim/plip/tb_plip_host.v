`timescale 1ns/100ps
// Testbench fuer plip_peer: Treiber nach hwpar.asm (hwburstsend/hwburstrecv),
// 1 CIA-Zugriff = 1 E-Takt = 40 Takte (28,57 MHz Takt, E = 1,40 us), bset/bclr = 2 Zugriffe.
module tb_plip_host;
    parameter SLOT = 40;
    localparam TMO_SLOTS = 20000;     // Treiber-Zeitueberschreitung (real 500 ms)

    reg clk = 0, rst = 1;
    always #17.5 clk = ~clk;

    // ---- Amiga-Seite (CIA-Register)
    reg        pra_sel = 0, pra_req = 0, ddra_sel = 0, ddra_req = 0;
    reg [7:0]  prb = 0, ddrb = 0;
    reg        prb_rd = 0;
    wire       rak, bus_oe, flag_n;
    wire [7:0] bus;
    // ---- Host-Seite
    wire       h_we, h_commit, h_release, plip_en, loop_en;
    wire [10:0] h_waddr, h_len, h_raddr;
    wire [7:0]  h_wdata;
    wire [7:0] h_rdata;
    wire       tx_valid, rx_valid;
    wire [10:0] rx_len;
    wire [31:0] stat_rx, stat_tx, rt_clks;

    plip_peer dut (
        .clk(clk), .rst(rst | ~plip_en),
        .sel_o(pra_sel), .sel_oe(ddra_sel), .req_o(pra_req), .req_oe(ddra_req),
        .prb_o(prb), .ddrb_out(ddrb == 8'hFF), .prb_rd(prb_rd),
        .rak(rak), .bus(bus), .bus_oe(bus_oe), .flag_n(flag_n),
        .h_we(h_we), .h_waddr(h_waddr), .h_wdata(h_wdata), .h_commit(h_commit), .h_len(h_len),
        .tx_valid(tx_valid), .h_raddr(h_raddr), .h_rdata(h_rdata),
        .rx_valid(rx_valid), .rx_len(rx_len), .h_release(h_release),
        .loop_en(loop_en), .stat_rx(stat_rx), .stat_tx(stat_tx), .rt_clks(rt_clks)
    );

    integer errors = 0;
    task fail(input [8*40-1:0] msg); begin errors = errors + 1; $display("FEHLER: %0s (t=%0t)", msg, $time); end endtask

    // ---- Zeit
    task clk1; begin @(posedge clk); #1; end endtask
    task slot; integer k; begin for (k = 0; k < SLOT; k = k + 1) clk1; end endtask

    function [7:0] pins(input dummy);
        pins = (ddrb == 8'hFF) ? prb : (bus_oe ? bus : 8'hEE);
    endfunction

    // ---- Treiberbausteine
    reg jitter = 0;
    task gap; integer k; begin if (jitter) for (k = {$random} % 3; k > 0; k = k - 1) slot; end endtask
    reg timeout;
    task wait_rak(input v);
        integer g; reg ok;
        begin
            ok = 0; g = 0;
            while (!ok) begin
                slot; g = g + 1;
                if (rak === v) ok = 1;
                else if (g > TMO_SLOTS) begin ok = 1; timeout = 1; end
            end
        end
    endtask

    reg [7:0] rv;
    task rd_prb;   // Lesezugriff auf PRB, danach prb_rd-Impuls
        begin
            repeat (SLOT - 1) clk1;
            rv = pins(0);
            prb_rd = 1; clk1; prb_rd = 0;
        end
    endtask

    task attach;  begin ddra_sel = 1; ddra_req = 1; pra_sel = 0; pra_req = 0; ddrb = 0; end endtask
    task detach;  begin ddra_sel = 0; ddra_req = 0; pra_sel = 0; pra_req = 0; ddrb = 0; end endtask
    task exit_seq; begin slot; ddrb = 0; slot; slot; pra_req = 0; slot; slot; pra_sel = 0; end endtask

    // Rahmen: fr[0..1] = Groesse, fr[2..] = Daten
    reg [7:0] fr  [0:2051];
    reg [7:0] rcv [0:2051];
    reg [7:0] ref_ [0:2051];
    reg [7:0] hrx [0:2051];
    integer   rsize;

    task make_frame(input integer n, input integer seed);
        integer i;
        begin
            for (i = 0; i < 2052; i = i + 1) begin fr[i] = 0; ref_[i] = 0; end
            fr[0] = n >> 8; fr[1] = n & 255;
            for (i = 0; i < n; i = i + 1) begin
                ref_[i] = (i * 7 + seed) & 8'h7F;      // $FF-Bytes vermeiden, Ethertype wird extra gesetzt
                fr[2 + i] = ref_[i];
            end
        end
    endtask

    // SEND_BURST; abort_w > 0: Treiber bricht nach abort_w Worten ab (SEL weg)
    reg send_ok;
    task burst_send(input integer abort_w, input [7:0] cmd);
        integer w, n, words;
        begin
            timeout = 0; send_ok = 0;
            n = {fr[0], fr[1]}; words = (n + 1) >> 1;
            begin : body
                wait_rak(0); if (timeout) disable body;
                slot; ddrb = 8'hFF;
                slot; prb = cmd;
                slot; slot; pra_sel = 1;
                wait_rak(1); if (timeout) disable body;
                slot; prb = fr[0];
                slot; slot; pra_req = 1;
                wait_rak(0); if (timeout) disable body;
                slot; prb = fr[1];
                slot; slot; pra_req = 0;
                wait_rak(1); if (timeout) disable body;
                for (w = 0; w < words; w = w + 1) begin
                    if (abort_w != 0 && w == abort_w) disable body;
                    gap;
                    slot; prb = fr[2 + 2*w];
                    slot; slot; pra_req = 1;
                    gap;
                    slot; prb = fr[3 + 2*w];
                    slot; slot; pra_req = 0;
                end
                slot; slot; pra_req = 1;
                wait_rak(0); if (timeout) disable body;
                slot; slot; pra_req = 0;
                wait_rak(1); if (timeout) disable body;
                send_ok = 1;
            end
            exit_seq;
        end
    endtask

    reg recv_ok;
    task burst_recv;
        integer w, words;
        reg [7:0] hi, lo;
        begin
            timeout = 0; recv_ok = 0; rsize = -1;
            begin : body
                wait_rak(0); if (timeout) disable body;
                slot; ddrb = 8'hFF;
                slot; prb = 8'h44;
                slot; slot; pra_sel = 1;
                wait_rak(1); if (timeout) disable body;
                slot; ddrb = 0;
                slot; slot; pra_req = 1;
                wait_rak(0); if (timeout) disable body;
                rd_prb; hi = rv;
                slot; slot; pra_req = 0;
                wait_rak(1); if (timeout) disable body;
                rd_prb; lo = rv;
                slot; slot; pra_req = 1;
                rsize = {hi, lo};
                if (rsize != 0) begin
                    words = (rsize + 1) >> 1;
                    wait_rak(0); if (timeout) disable body;
                    for (w = 0; w < words; w = w + 1) begin
                        gap;
                        slot; slot; pra_req = 0;
                        gap;
                        rd_prb; rcv[2*w] = rv;
                        gap;
                        slot; slot; pra_req = 1;
                        gap;
                        rd_prb; rcv[2*w + 1] = rv;
                    end
                    slot; slot; pra_req = 0;
                    wait_rak(1); if (timeout) disable body;
                    slot; slot; pra_req = 1;
                    wait_rak(0); if (timeout) disable body;
                end
                recv_ok = 1;
            end
            exit_seq;
        end
    endtask

    // ---- SPI-Seite (Ziel 5), Bytes wie mcu_spi.v sie liefert: je Byte ein Strobe, das erste
    //      Byte nach dem Ziel traegt data_start; die Antwort steht erst nach dem Strobe an
    reg        sp_strobe = 0, sp_start = 0, iack = 0;
    reg  [7:0] sp_din = 0;
    wire [7:0] sp_dout;
    wire       irq;
    plip_host host (
        .clk(clk), .reset(rst),
        .data_strobe(sp_strobe), .data_start(sp_start), .data_in(sp_din), .data_out(sp_dout),
        .irq(irq), .iack(iack), .plip_en(plip_en), .plip_loop(loop_en),
        .h_we(h_we), .h_waddr(h_waddr), .h_wdata(h_wdata), .h_commit(h_commit), .h_len(h_len),
        .tx_valid(tx_valid), .h_raddr(h_raddr), .h_rdata(h_rdata),
        .rx_valid(rx_valid), .rx_len(rx_len), .h_release(h_release),
        .stat_rx(stat_rx), .stat_tx(stat_tx), .rt_clks(rt_clks)
    );

    integer sp_gap = 14;        // Takte zwischen zwei Bytes (19,2 MHz SPI ohne Pause: 12 Takte je Byte)
    reg [7:0] rep;
    task xfer(input [7:0] b, input first);
        begin
            rep = sp_dout;                            // was waehrend dieses Bytes ausgeschoben wird
            sp_din = b; sp_start = first; sp_strobe = 1; clk1; sp_strobe = 0; sp_start = 0;
            repeat (sp_gap - 1 + (jitter ? ({$random} % 20) : 0)) clk1;
        end
    endtask

    reg [7:0] st_b;
    integer   st_len;
    task spi_status;
        begin
            xfer(8'd0, 1); xfer(0, 0); st_b = rep;
            xfer(0, 0); st_len = rep << 8; xfer(0, 0); st_len = st_len | rep;
        end
    endtask
    task spi_read(input integer n);
        integer k;
        begin
            xfer(8'd1, 1); xfer(0, 0); st_b = rep;
            xfer(0, 0); if (rep !== 8'h00) fail("READ nicht bereit");
            for (k = 0; k < n; k = k + 1) begin xfer(0, 0); hrx[k] = rep; end
        end
    endtask
    task spi_release; begin xfer(8'd2, 1); xfer(0, 0); end endtask
    task spi_write(input integer n);
        integer k;
        begin xfer(8'd3, 1); for (k = 0; k < n; k = k + 1) xfer(ref_[k], 0); end
    endtask
    task spi_commit(input integer n); begin xfer(8'd4, 1); xfer(n >> 8, 0); xfer(n & 255, 0); end endtask
    task spi_config(input [1:0] v); begin xfer(8'd5, 1); xfer({6'b0, v}, 0); end endtask
    reg [95:0] sstats;
    task spi_stats;
        integer k;
        begin
            xfer(8'd6, 1); xfer(0, 0); xfer(0, 0);    // status, 0
            for (k = 0; k < 12; k = k + 1) begin xfer(0, 0); sstats = {sstats[87:0], rep}; end
        end
    endtask
    task do_iack; begin iack = 1; clk1; iack = 0; end endtask

    task wait_irq;
        integer g;
        begin g = 0; while (!irq && g < 400000) begin clk1; g = g + 1; end if (!irq) fail("kein IRQ"); end
    endtask
    task wait_flag;
        integer g;
        begin g = 0; while (flag_n && g < 400000) begin clk1; g = g + 1; end if (flag_n) fail("kein /ACK-Puls"); end
    endtask
    task idle_check(input [8*24-1:0] where);
        begin
            repeat (50) clk1;
            if (dut.st !== 4'd0) begin $display("  Zustand %0d (%0s)", dut.st, where); fail("Automat nicht im Leerlauf"); end
            if (rak !== 1'b0)    fail("RAK nicht 0");
            if (bus_oe !== 1'b0) fail("Bus nicht frei");
        end
    endtask

    integer i, n, k;
    integer sizes_rx [0:3];
    integer sizes_tx [0:3];
    initial begin
        sizes_rx[0] = 61; sizes_rx[1] = 14; sizes_rx[2] = 1514; sizes_rx[3] = 2;
        sizes_tx[0] = 61; sizes_tx[1] = 1; sizes_tx[2] = 1514; sizes_tx[3] = 14;

        repeat (5) clk1; rst = 0; repeat (20) clk1;
        attach;

        $display("H1 ohne Freigabe");
        spi_status;
        if (st_b !== 8'h00) begin $display("  Status %02x", st_b); fail("Status nach Reset"); end
        pra_sel = 1; ddrb = 8'hFF; prb = 8'h33;
        repeat (500) clk1;
        if (rak !== 1'b0) fail("Gegenstelle reagiert ohne Freigabe");
        pra_sel = 0; ddrb = 0;
        spi_config(2'b01); repeat (10) clk1;
        spi_status;
        if (st_b !== 8'h04) begin $display("  Status %02x", st_b); fail("Status nach CONFIG"); end

        $display("H2 Amiga -> Host");
        for (k = 0; k < 4; k = k + 1) begin
            n = sizes_rx[k];
            make_frame(n, 3 + k);
            burst_send(0, 8'h33);
            if (!send_ok) fail("send");
            wait_irq;
            do_iack;
            repeat (3) clk1;
            if (irq) fail("IRQ nach Quittung");
            spi_status;
            if (st_b !== 8'h05 || st_len !== n) begin $display("  Status %02x len %0d erwartet %0d", st_b, st_len, n); fail("Status/Laenge"); end
            spi_read(n);
            for (i = 0; i < n; i = i + 1) if (hrx[i] !== ref_[i]) begin
                if (errors < 10) $display("  Byte %0d: %02x erwartet %02x", i, hrx[i], ref_[i]);
                errors = errors + 1;
            end
            spi_release; repeat (5) clk1;
            if (rx_valid) fail("rx_valid nach RELEASE");
            idle_check("nach H2");
            $display("  n=%0d ok", n);
        end

        $display("H3 Host -> Amiga");
        for (k = 0; k < 4; k = k + 1) begin
            n = sizes_tx[k];
            make_frame(n, 11 + k);
            do_iack;
            spi_status;
            if (st_b[1] !== 1'b0) fail("tx belegt vor Schreiben");
            spi_write(n);
            spi_commit(n);
            wait_flag;
            burst_recv;
            if (!recv_ok) fail("recv");
            if (rsize !== n) begin $display("  rsize=%0d erwartet %0d", rsize, n); fail("Groesse"); end
            for (i = 0; i < n; i = i + 1) if (rcv[i] !== ref_[i]) begin
                if (errors < 10) $display("  Byte %0d: %02x erwartet %02x", i, rcv[i], ref_[i]);
                errors = errors + 1;
            end
            repeat (5) clk1;
            if (!irq) fail("kein IRQ nach Abholen");
            do_iack;
            idle_check("nach H3");
            $display("  n=%0d ok", n);
        end

        $display("H4 COMMIT bei belegtem Puffer, Laenge 0");
        make_frame(40, 21);
        spi_write(40); spi_commit(0); repeat (20) clk1;
        if (tx_valid) fail("COMMIT mit Laenge 0 angenommen");
        spi_commit(40); wait_flag;
        make_frame(40, 22);
        spi_write(40); spi_commit(25); repeat (20) clk1;     // darf weder schreiben noch commiten
        make_frame(40, 21);
        burst_recv;
        if (!recv_ok || rsize !== 40) fail("H4: Groesse");
        for (i = 0; i < 40; i = i + 1) if (rcv[i] !== ref_[i]) errors = errors + 1;
        do_iack;

`ifdef PLIP_LITE
        $display("H5/H6 entfallen (PLIP_LITE): keine Statistik, kein Loopback");
        spi_stats;
        if (sstats !== 96'd0) fail("STATS bei PLIP_LITE nicht 0");
`else
        $display("H5 Zaehler");
        spi_stats;
        $display("  stat_rx=%0d stat_tx=%0d rt_clks=%0d", sstats[95:64], sstats[63:32], sstats[31:0]);
        if (sstats[95:64] !== stat_rx || sstats[63:32] !== stat_tx || sstats[31:0] !== rt_clks) fail("STATS");

        $display("H6 Loopback ueber CONFIG");
        spi_config(2'b11);
        make_frame(1514, 5); fr[2+12] = 8'hFF; fr[2+13] = 8'hFD; ref_[12] = 8'hFF; ref_[13] = 8'hFD;
        burst_send(0, 8'h33);
        if (!send_ok) fail("loop send");
        wait_flag;
        burst_recv;
        if (!recv_ok || rsize !== 1514) fail("loop recv");
        for (i = 0; i < 1514; i = i + 1) if (rcv[i] !== ref_[i]) errors = errors + 1;
        if (rx_valid) fail("Loopback belastet den Host");
        do_iack;
        spi_config(2'b01);
`endif

        $display("H7 Abschalten");
        spi_config(2'b00); repeat (10) clk1;
        pra_sel = 1; ddrb = 8'hFF; prb = 8'h33;
        repeat (300) clk1;
        if (rak !== 1'b0) fail("Gegenstelle reagiert nach Abschalten");
        pra_sel = 0; ddrb = 0;

        if (errors == 0) $display("PASS"); else $display("FAIL: %0d Fehler", errors);
        $finish;
    end
    initial begin #3000000000; $display("FAIL: Zeitlimit"); $finish; end
endmodule
