`timescale 1ns/100ps
// Testbench fuer plip_peer: Treiber nach hwpar.asm (hwburstsend/hwburstrecv),
// 1 CIA-Zugriff = 1 E-Takt = 40 Takte (28,57 MHz Takt, E = 1,40 us), bset/bclr = 2 Zugriffe.
module tb_plip_peer;
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
    reg        h_we = 0, h_commit = 0, h_release = 0, loop_en = 0;
    reg [10:0] h_waddr = 0, h_len = 0, h_raddr = 0;
    reg [7:0]  h_wdata = 0;
    wire [7:0] h_rdata;
    wire       tx_valid, rx_valid;
    wire [10:0] rx_len;
    wire [31:0] stat_rx, stat_tx, rt_clks;

    plip_peer dut (
        .clk(clk), .rst(rst),
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

    // ---- Host
    task host_write_tx(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                h_we = 1; h_waddr = k; h_wdata = ref_[k]; clk1;
            end
            h_we = 0; clk1;
            h_len = n; h_commit = 1; clk1; h_commit = 0;
        end
    endtask

    task host_read_rx(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                h_raddr = k; clk1; hrx[k] = h_rdata;
            end
        end
    endtask

    task wait_rx_valid;
        integer g;
        begin g = 0; while (!rx_valid && g < 2000) begin clk1; g = g + 1; end end
    endtask

    task wait_flag;   // wartet auf fallende /ACK-Flanke
        integer g;
        begin g = 0; while (flag_n && g < 200000) begin clk1; g = g + 1; end if (flag_n) fail("kein /ACK-Puls"); end
    endtask

    // Pulsmessung
    integer fl_cnt = 0, fl_last = 0, fl_pulses = 0;
    always @(posedge clk) begin
        if (!flag_n) fl_cnt <= fl_cnt + 1;
        else if (fl_cnt != 0) begin fl_last <= fl_cnt; fl_cnt <= 0; end
    end
    always @(negedge flag_n) fl_pulses = fl_pulses + 1;

    task idle_check(input [8*24-1:0] where);
        begin
            repeat (50) clk1;
            if (dut.st !== 4'd0) begin $display("  Zustand %0d (%0s)", dut.st, where); fail("Automat nicht im Leerlauf"); end
            if (rak !== 1'b0)    fail("RAK nicht 0");
            if (bus_oe !== 1'b0) fail("Bus nicht frei");
        end
    endtask

    integer i, n, t, it;
    integer sizes_tx [0:4];
    integer sizes_rx [0:3];
    integer t0, t1;
    reg [7:0] etype_hi, etype_lo;

    initial begin
        $dumpfile("tb_plip_peer.vcd");
        $dumpvars(0, tb_plip_peer);
        sizes_tx[0] = 14; sizes_tx[1] = 60; sizes_tx[2] = 61; sizes_tx[3] = 1500; sizes_tx[4] = 1514;
        sizes_rx[0] = 14; sizes_rx[1] = 61; sizes_rx[2] = 1514; sizes_rx[3] = 1;

        repeat (5) clk1; rst = 0; repeat (5) clk1;
        attach;

        // ---------- T1: Amiga sendet
        $display("T1 SEND_BURST");
        for (t = 0; t < 5; t = t + 1) begin
            n = sizes_tx[t];
            make_frame(n, t * 13 + 1);
            t0 = $time;
            burst_send(0, 8'h33);
            t1 = $time;
            if (!send_ok) fail("send nicht ok");
            wait_rx_valid;
            if (!rx_valid) fail("rx_valid fehlt");
            if (rx_len !== n) begin $display("  rx_len=%0d erwartet %0d", rx_len, n); fail("rx_len falsch"); end
            host_read_rx(n);
            for (i = 0; i < n; i = i + 1)
                if (hrx[i] !== ref_[i]) begin
                    if (errors < 10) $display("  Byte %0d: %02x erwartet %02x", i, hrx[i], ref_[i]);
                    errors = errors + 1;
                end
            h_release = 1; clk1; h_release = 0;
            idle_check("nach SEND");
            $display("  n=%0d ok, %0d E-Takte", n, (t1 - t0) / 35 / SLOT);
        end

        // ---------- T2: Amiga empfaengt (mit /ACK-Puls)
        $display("T2 RECV_BURST");
        for (t = 0; t < 4; t = t + 1) begin
            n = sizes_rx[t];
            make_frame(n, t * 29 + 5);
            fl_pulses = 0;
            host_write_tx(n);
            wait_flag;
            repeat (100) clk1;
            if (fl_last !== 64) begin $display("  Pulsbreite %0d", fl_last); fail("Pulsbreite"); end
            if (fl_pulses !== 1) fail("mehr als ein Puls");
            burst_recv;
            if (!recv_ok) fail("recv nicht ok");
            if (rsize !== n) begin $display("  rsize=%0d erwartet %0d", rsize, n); fail("Groesse falsch"); end
            for (i = 0; i < n; i = i + 1)
                if (rcv[i] !== ref_[i]) begin
                    if (errors < 10) $display("  Byte %0d: %02x erwartet %02x", i, rcv[i], ref_[i]);
                    errors = errors + 1;
                end
            idle_check("nach RECV");
            if (tx_valid) fail("tx_valid nicht geloescht");
            $display("  n=%0d ok", n);
        end
        repeat (400) clk1;
        if (fl_pulses !== 1) begin $display("  Pulse nach letztem RECV %0d", fl_pulses); fail("Puls nach RECV"); end

        // ---------- T3: RECV ohne wartenden Rahmen -> Groesse 0
        $display("T3 RECV leer");
        burst_recv;
        if (!recv_ok || rsize !== 0) fail("leere Antwort");
        idle_check("nach leerem RECV");

        // ---------- T4: Abbruch mitten im Burst, danach normaler Transfer
        $display("T4 Abbruch");
        make_frame(300, 3);
        burst_send(40, 8'h33);
        idle_check("nach Abbruch");
        if (rx_valid) fail("rx_valid nach Abbruch");
        make_frame(61, 7);
        burst_send(0, 8'h33);
        wait_rx_valid; host_read_rx(61);
        for (i = 0; i < 61; i = i + 1) if (hrx[i] !== ref_[i]) errors = errors + 1;
        h_release = 1; clk1; h_release = 0;
        idle_check("nach Abbruch+Send");

        // ---------- T5: kein Treiber (DDRA-Bits 0), PRA-Bits trotzdem 1
        $display("T5 ohne Treiber");
        detach; pra_sel = 1; pra_req = 0; ddrb = 8'hFF; prb = 8'h33;
        repeat (500) clk1;
        if (dut.st !== 4'd0 || rak !== 1'b0) fail("reagiert ohne Treiber");
        pra_sel = 0; ddrb = 0; attach;

        // ---------- T6: Rueckstau (rx_valid nicht freigegeben)
        $display("T6 Rueckstau");
        make_frame(100, 11);
        burst_send(0, 8'h33);
        wait_rx_valid;
        make_frame(120, 17);
        fork
            burst_send(0, 8'h33);
            begin
                repeat (200 * SLOT) clk1;
                if (rak !== 1'b0 || dut.st !== 4'd3) fail("kein Rueckstau");
                host_read_rx(100);   // altes Paket noch intakt?
                h_release = 1; clk1; h_release = 0;
            end
        join
        if (!send_ok) fail("send nach Rueckstau");
        wait_rx_valid;
        if (rx_len !== 120) fail("zweiter Rahmen: Laenge");
        host_read_rx(120);
        for (i = 0; i < 120; i = i + 1) if (hrx[i] !== ref_[i]) errors = errors + 1;
        h_release = 1; clk1; h_release = 0;
        idle_check("nach Rueckstau");

        // ---------- T7: unbekannter Befehl ($11 = langsame Variante)
        $display("T7 Befehl $11");
        make_frame(60, 1);
        burst_send(0, 8'h11);           // RAK bleibt 0, Treiber laeuft in die Zeitueberschreitung
        if (send_ok) fail("Befehl $11 darf nicht quittiert werden");
        idle_check("nach $11");
        make_frame(60, 2);
        burst_send(0, 8'h33);
        if (!send_ok) fail("send nach $11");
        wait_rx_valid; h_release = 1; clk1; h_release = 0;
        idle_check("nach $11+Send");

        // ---------- T8: Loopback (Ethertype $FFFD), ohne Host, Ratenmessung
        $display("T8 Loopback");
        loop_en = 1;
        make_frame(1514, 23);
        ref_[12] = 8'hFF; ref_[13] = 8'hFD;
        host_write_tx(1514);
        for (it = 0; it < 4; it = it + 1) begin
            wait_flag;
            burst_recv;
            if (!recv_ok || rsize !== 1514) fail("loop recv");
            for (i = 0; i < 1514; i = i + 1)
                if (rcv[i] !== ref_[i]) begin
                    if (errors < 10) $display("  it %0d Byte %0d: %02x erwartet %02x", it, i, rcv[i], ref_[i]);
                    errors = errors + 1;
                end
            fr[0] = rsize >> 8; fr[1] = rsize & 255;
            for (i = 0; i < 1514; i = i + 1) fr[2 + i] = rcv[i];
            burst_send(0, 8'h33);
            if (!send_ok) fail("loop send");
            if (it > 0) $display("  Runde %0d: %0d Takte = %0.2f ms, %0.0f KiB/s (beide Richtungen zusammen)",
                                 it, rt_clks, rt_clks * 35.0 / 1.0e6, 2.0 * 1514 / (rt_clks * 35.0e-9) / 1024);
        end
        wait_flag;                       // der zuletzt zurueckgespielte Rahmen wartet noch
        burst_recv;
        if (!recv_ok || rsize !== 1514) fail("Loopback: Restrahmen");
        repeat (200) clk1;
        if (rx_valid) fail("Loopback hat den Host belastet");
        $display("  stat_rx=%0d stat_tx=%0d", stat_rx, stat_tx);
        if (stat_rx !== 13 || stat_tx !== 9) fail("Zaehler");
        loop_en = 0;

        // ---------- T9: Luecken zwischen den CIA-Zugriffen (DMA-Wartezyklen)
        $display("T9 Luecken im Burst");
        jitter = 1;
        for (t = 0; t < 3; t = t + 1) begin
            n = (t == 0) ? 1514 : (t == 1) ? 61 : 14;
            make_frame(n, t * 5 + 3);
            burst_send(0, 8'h33);
            if (!send_ok) fail("jitter send");
            wait_rx_valid; host_read_rx(n);
            for (i = 0; i < n; i = i + 1) if (hrx[i] !== ref_[i]) errors = errors + 1;
            h_release = 1; clk1; h_release = 0;
            host_write_tx(n);
            wait_flag;
            burst_recv;
            if (!recv_ok || rsize !== n) fail("jitter recv");
            for (i = 0; i < n; i = i + 1) if (rcv[i] !== ref_[i]) errors = errors + 1;
            idle_check("nach Luecken");
            $display("  n=%0d ok", n);
        end
        jitter = 0;

        $display("----");
        if (errors == 0) $display("PASS"); else $display("FAIL: %0d Fehler", errors);
        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("FAIL: Watchdog");
        $finish;
    end
endmodule
