`timescale 1ns/100ps
// Integrationstest: echte ciaa/ciab/minimig_m68k_bridge/amiga_clk + plip_peer, Verdrahtung
// woertlich aus minimig.v (minimig_cia_glue.vh). Treiber nach hwpar.asm auf 68000-Buszyklen.
module tb_cia_plip;
    reg clk = 0;
    always #17.5 clk = ~clk;
    reg reset_n = 0, reset = 1;

    wire clk7_en, clk7n_en, c1, c3, cck;
    wire [9:0] eclk;
    amiga_clk ac (.clk_28(clk), .clk7_en(clk7_en), .clk7n_en(clk7n_en), .c1(c1), .c3(c3),
                  .cck(cck), .eclk(eclk), .reset_n(reset_n));

    // ---- CPU-Seite
    reg        _as = 1, _uds = 1, _lds = 1, r_w = 1;
    reg [23:1] cpu_addr = 0;
    reg [15:0] cpu_wdata = 0;
    wire       _dtack, cpu_rd, cpu_hwr, cpu_lwr, rd_cyc;
    wire [23:1] cpu_address_out;
    wire [15:0] cpu_data_out, cpu_dq;
    wire [15:0] cia_data_out;

    wire sel_cia   = cpu_address_out[23:16] == 8'hBF;
    wire sel_cia_a = sel_cia & ~cpu_address_out[12];
    wire sel_cia_b = sel_cia & ~cpu_address_out[13];

    minimig_m68k_bridge br (
        .clk(clk), .clk7_en(clk7_en), .clk7n_en(clk7n_en), .c1(c1), .c3(c3), .eclk(eclk),
        .vpa(sel_cia), .dbr(1'b0), .dbs(1'b0), .xbs(1'b0), .nrdy(1'b0), .bls(), .cck(cck),
        .memory_config(4'd0), ._as(_as), ._lds(_lds), ._uds(_uds), .r_w(r_w), ._dtack(_dtack),
        .rd(cpu_rd), .hwr(cpu_hwr), .lwr(cpu_lwr), .address(cpu_addr), .address_out(cpu_address_out),
        .data(cpu_dq), .cpudatain(cpu_wdata), .data_out(cpu_data_out), .data_in(cia_data_out),
        .rd_cyc(rd_cyc));

    // ---- Signale, die der Verdrahtungsblock aus minimig.v erwartet
    wire _vsync = 1'b1, _hsync = 1'b1, index = 1'b0;
    wire int2, int6, keyboard_ack, freeze;
    wire _fire1 = 1'b1, _fire0 = 1'b1, _ready = 1'b1, _track0 = 1'b1, _wprot = 1'b1, _change = 1'b1;
    wire [15:0] _joy3 = 16'hFFFF, _joy4 = 16'hFFFF;
    wire [1:0] kbd_mouse_type = 2'd0;
    wire kms_level = 1'b0;
    wire [7:0] kbd_mouse_data = 8'd0;
    wire [7:0] memory_config = 8'd0;
    wire cd = 1'b1, cts = 1'b1, dsr = 1'b1, ri = 1'b1;
    wire dtr, rts, _motor, _sel3, _sel2, _sel1, _sel0, side, direc, _step, fdd_step_n;
    wire _fire1_dat, _fire0_dat, _led;

    parameter DLY = 2;               // CPU uebernimmt die Daten DLY E7-Takte nach DTACK
    reg        plip_en = 1, plip_loop = 0;
    reg        plip_h_we = 0, plip_h_commit = 0, plip_h_release_r = 0, auto_rel = 0;
    wire       plip_h_release = plip_h_release_r | (auto_rel & plip_rx_valid);   // auto_rel: wie nanomig.v (kein Host)
    reg [10:0] plip_h_waddr = 0, plip_h_len = 0, plip_h_raddr = 0;
    reg [7:0]  plip_h_wdata = 0;
    wire [7:0] plip_h_rdata;
    wire       plip_tx_valid, plip_rx_valid;
    wire [10:0] plip_rx_len;
    wire [31:0] plip_stat_rx, plip_stat_tx, plip_rt_clks;

    // wie in minimig.v: cpu_rd bleibt wirksam fuer die CIAs
    `include "minimig_cia_glue.vh"

    // ---- Hilfen
    integer errors = 0;
    task fail(input [8*40-1:0] msg); begin errors = errors + 1; $display("FEHLER: %0s (t=%0t)", msg, $time); end endtask
    task clk1; begin @(posedge clk); #1; end endtask
    task clk7w; begin @(posedge clk); while (!clk7_en) @(posedge clk); #1; end endtask

    // 68000-Lese-/Schreibzyklus (Daten werden 2 Takte nach DTACK uebernommen, AS danach weg)
    reg [7:0] cv;
    integer n_rd_drv = 0, n_rd_pulse = 0, n_acc = 0;
    always @(posedge clk) if (plip_prb_rd) n_rd_pulse = n_rd_pulse + 1;
    task cyc(input [23:0] a, input rw, input [7:0] wd);
        integer t;
        begin
            clk7w; cpu_addr = a[23:1]; r_w = rw; cpu_wdata = {wd, wd};
            clk7w; _as = 0;
            if (rw) begin _uds = a[0]; _lds = ~a[0]; end
            else begin clk7w; _uds = a[0]; _lds = ~a[0]; end
            t = 0; clk7w;
            while (_dtack !== 1'b0 && t < 200) begin clk7w; t = t + 1; end
            if (t >= 200) fail("kein DTACK");
            repeat (DLY) clk7w;
            cv = a[0] ? cpu_dq[7:0] : cpu_dq[15:8];
            _as = 1; _uds = 1; _lds = 1;
            clk7w; r_w = 1;
            n_acc = n_acc + 1;
        end
    endtask

    localparam [23:0] PRB = 24'hBFE101, DDRB = 24'hBFE301, ICRA = 24'hBFED01,
                      PRA = 24'hBFD000, DDRA = 24'hBFD200;
    task wr(input [23:0] a, input [7:0] v); cyc(a, 0, v); endtask
    task rdb(input [23:0] a); begin cyc(a, 1, 0); if (a == PRB) n_rd_drv = n_rd_drv + 1; end endtask
    reg [7:0] t8;
    task bset(input [7:0] m); begin rdb(PRA); t8 = cv | m;  wr(PRA, t8); end endtask
    task bclr(input [7:0] m); begin rdb(PRA); t8 = cv & ~m; wr(PRA, t8); end endtask
    reg timeout;
    task wait_rak(input v);
        integer g; reg ok;
        begin ok = 0; g = 0;
            while (!ok) begin
                rdb(PRA); g = g + 1;
                if (cv[0] === v) ok = 1;
                else if (g > 3000) begin ok = 1; timeout = 1; end
            end
        end
    endtask

    // ---- Rahmen
    reg [7:0] ref_ [0:2051];
    reg [7:0] rf   [0:2051];
    reg [7:0] hrx  [0:2051];
    integer rsize;
    task make_frame(input integer n, input integer seed, input integer loopback);
        integer i;
        begin
            for (i = 0; i < 2052; i = i + 1) ref_[i] = 0;
            for (i = 0; i < n; i = i + 1) ref_[i] = (i * 7 + seed) & 8'h7F;
            if (loopback && n >= 14) begin ref_[12] = 8'hFF; ref_[13] = 8'hFD; end
        end
    endtask
    task host_write_tx(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin plip_h_we = 1; plip_h_waddr = k; plip_h_wdata = ref_[k]; clk1; end
            plip_h_we = 0; clk1;
            plip_h_len = n; plip_h_commit = 1; clk1; plip_h_commit = 0;
        end
    endtask
    task host_read_rx(input integer n);
        integer k;
        begin for (k = 0; k < n; k = k + 1) begin plip_h_raddr = k; clk1; hrx[k] = plip_h_rdata; end end
    endtask
    task wait_rx_valid; integer g; begin g = 0; while (!plip_rx_valid && g < 100000) begin clk1; g = g + 1; end if (!plip_rx_valid) fail("rx_valid fehlt"); end endtask
    task release_rx; begin plip_h_release_r = 1; clk1; plip_h_release_r = 0; end endtask

    // ---- Treiber (hwburstsend / hwburstrecv)
    reg send_ok;
    task burst_send(input integer n);
        integer w, words;
        begin
            timeout = 0; send_ok = 0; words = (n + 1) >> 1;
            begin : body
                wait_rak(0); if (timeout) disable body;
                wr(DDRB, 8'hFF); wr(PRB, 8'h33); bset(8'h04);
                wait_rak(1); if (timeout) disable body;
                wr(PRB, n >> 8); bset(8'h02);
                wait_rak(0); if (timeout) disable body;
                wr(PRB, n & 255); bclr(8'h02);
                wait_rak(1); if (timeout) disable body;
                for (w = 0; w < words; w = w + 1) begin
                    wr(PRB, ref_[2*w]);   bset(8'h02);
                    wr(PRB, ref_[2*w+1]); bclr(8'h02);
                end
                bset(8'h02);
                wait_rak(0); if (timeout) disable body;
                bclr(8'h02);
                wait_rak(1); if (timeout) disable body;
                wr(DDRB, 8'h00); bclr(8'h04);
                send_ok = 1;
            end
        end
    endtask
    reg recv_ok;
    task burst_recv;
        integer w, words; reg [7:0] hi, lo;
        begin
            timeout = 0; recv_ok = 0; rsize = -1;
            begin : body
                wait_rak(0); if (timeout) disable body;
                wr(DDRB, 8'hFF); wr(PRB, 8'h44); bset(8'h04);
                wait_rak(1); if (timeout) disable body;
                wr(DDRB, 8'h00); bset(8'h02);
                wait_rak(0); if (timeout) disable body;
                rdb(PRB); hi = cv; bclr(8'h02);
                wait_rak(1); if (timeout) disable body;
                rdb(PRB); lo = cv; bset(8'h02);
                rsize = {hi, lo};
                if (rsize == 0) begin bclr(8'h02); bclr(8'h04); end
                else begin
                    wait_rak(0); if (timeout) disable body;
                    words = (rsize + 1) >> 1;
                    for (w = 0; w < words; w = w + 1) begin
                        bclr(8'h02); rdb(PRB); rf[2*w] = cv;
                        bset(8'h02); rdb(PRB); rf[2*w+1] = cv;
                    end
                    bclr(8'h02);
                    wait_rak(1); if (timeout) disable body;
                    bset(8'h02);
                    wait_rak(0); if (timeout) disable body;
                    bclr(8'h02); bclr(8'h04);
                end
                recv_ok = 1;
            end
        end
    endtask

    // /ACK -> INT2 (ICR-Maske gesetzt)
    task wait_int2; integer g; begin g = 0; while (!int2 && g < 400000) begin clk1; g = g + 1; end if (!int2) fail("kein INT2"); end endtask
    task check_icr_clear;
        begin rdb(ICRA); if (!cv[4]) fail("ICR FLG nicht gesetzt"); repeat (8) clk7w; if (int2) fail("INT2 bleibt"); end
    endtask

    integer i, k, n, t0, t1;
    integer sizes [0:3];
    initial begin
        sizes[0] = 61; sizes[1] = 14; sizes[2] = 1514; sizes[3] = 2;
        repeat (10) clk1; reset_n = 1;
        repeat (20) clk1; reset = 0;
        repeat (20) clk7w;

        // serial.device: DTR/RTS als Ausgaenge, beide high; plipbox: SEL/REQ low, dann Ausgaenge
        wr(DDRA, 8'hC0); wr(PRA, 8'hC0);
        rdb(DDRA); t8 = cv | 8'h06; wr(DDRA, t8);
        rdb(PRA);  if (cv[2:1] !== 2'b00) fail("PRA Rueckleseweg SEL/REQ");
        wr(ICRA, 8'h90);                 // FLG-Interrupt freigeben
        if (plip_rx_valid || int2) fail("Startzustand");

        $display("C1 SEND ueber echte CIA/Bridge");
        for (k = 0; k < 4; k = k + 1) begin
            n = sizes[k];
            make_frame(n, 3 + k, 0);
            burst_send(n);
            if (!send_ok) fail("send");
            wait_rx_valid;
            if (plip_rx_len !== n) begin $display("  rx_len=%0d erwartet %0d", plip_rx_len, n); fail("rx_len"); end
            host_read_rx(n);
            for (i = 0; i < n; i = i + 1) if (hrx[i] !== ref_[i]) begin
                if (errors < 10) $display("  Byte %0d: %02x erwartet %02x", i, hrx[i], ref_[i]);
                errors = errors + 1;
            end
            release_rx;
            $display("  n=%0d ok", n);
        end

        $display("C2 /ACK -> INT2 und RECV");
        for (k = 0; k < 4; k = k + 1) begin
            n = sizes[k];
            make_frame(n, 11 + k, 0);
            host_write_tx(n);
            wait_int2;
            check_icr_clear;
            burst_recv;
            if (!recv_ok) fail("recv");
            if (rsize !== n) begin $display("  rsize=%0d erwartet %0d", rsize, n); fail("rsize"); end
            for (i = 0; i < n; i = i + 1) if (rf[i] !== ref_[i]) begin
                if (errors < 10) $display("  Byte %0d: %02x erwartet %02x", i, rf[i], ref_[i]);
                errors = errors + 1;
            end
            $display("  n=%0d ok", n);
        end
        burst_recv;                      // leere Antwort
        if (!recv_ok || rsize !== 0) fail("leerer RECV");

        $display("C3 Loopback (Ethertype $FFFD) ueber CIA");
        plip_loop = 1;
        for (k = 0; k < 2; k = k + 1) begin
            make_frame(1514, 5 + k, 1);
            t0 = $time;
            burst_send(1514);
            if (!send_ok) fail("loop send");
            wait_int2; check_icr_clear;
            burst_recv;
            t1 = $time;
            if (!recv_ok || rsize !== 1514) fail("loop recv");
            for (i = 0; i < 1514; i = i + 1) if (rf[i] !== ref_[i]) errors = errors + 1;
            $display("  Runde %0d: %0d us, %0d KiB/s (beide Richtungen zusammen)", k, (t1 - t0) / 1000,
                     (2.0 * 1514 * 1.0e9 / (t1 - t0)) / 1024.0);
        end
        plip_loop = 0;

        $display("C3b Loopback ohne Host: fremde Rahmen duerfen nicht blockieren");
        plip_loop = 1; auto_rel = 1;
        make_frame(61, 9, 0);                  // z.B. $FFFF-Online-Rahmen oder ARP: kein $FFFD
        burst_send(61);
        if (!send_ok) fail("fremder Rahmen: send");
        repeat (50) clk1;
        if (plip_rx_valid) fail("rx_valid bleibt ohne Host");
        make_frame(1514, 4, 1);
        burst_send(1514);
        if (!send_ok) fail("Loopback nach fremdem Rahmen: send");
        wait_int2; check_icr_clear;
        burst_recv;
        if (!recv_ok || rsize !== 1514) fail("Loopback nach fremdem Rahmen: recv");
        for (i = 0; i < 1514; i = i + 1) if (rf[i] !== ref_[i]) errors = errors + 1;
        plip_loop = 0; auto_rel = 0;

        $display("C4 Nebenwirkungen");
        if (dtr !== 1'b1 || rts !== 1'b1) fail("DTR/RTS veraendert");
        rdb(PRA);
        if (cv[7:6] !== 2'b11) fail("PRA Bit 7:6");
        if (n_rd_pulse !== n_rd_drv) begin $display("  Strobes %0d, PRB-Lesezugriffe %0d", n_rd_pulse, n_rd_drv); fail("prb_rd Zaehlung"); end
        $display("  prb_rd-Strobes %0d = PRB-Lesezugriffe %0d, CIA-Zugriffe %0d", n_rd_pulse, n_rd_drv, n_acc);

        if (errors == 0) $display("PASS"); else $display("FAIL: %0d Fehler", errors);
        $finish;
    end
    initial begin #3000000000; $display("FAIL: Zeitlimit"); $finish; end   // 3 s Simulationszeit
endmodule
