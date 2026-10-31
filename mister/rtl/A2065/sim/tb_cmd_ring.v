/*
 * tb_cmd_ring.v — 68k register writes must complete without the host.
 *
 * The deadlock this guards against: Main is single-threaded, and while it sits
 * in its IDE handler waiting on the Amiga, the Amiga must not be sitting on a
 * stretched DTACK waiting on Main. Register writes therefore have to retire on
 * FPGA progress alone — the entry reaching DDR3 — and never on the host having
 * read it.
 *
 * The host is deliberately absent here: nothing in this bench ever reads the
 * ring or writes anything back. If a write still needs the host, the bus never
 * releases and the test fails.
 *
 * The same holds for acknowledging CSR0. The level 2 server of a2065.device
 * writes the interrupt bits back and loops until they read clear, at
 * interrupt level, so a CSR0 acknowledge must show in the next 68k read
 * without the host. The bench's host model only publishes the CSR and
 * INT_STATE words the mailbox polls, as Main does.
 */
`timescale 1ns/1ps

module tb_cmd_ring;

    reg clk_sys = 0; always #17.46 clk_sys = ~clk_sys;   // 28.6 MHz, Amiga side
    reg clk_ddr = 0; always #4.364 clk_ddr = ~clk_ddr;   // 114.5 MHz, DDR3 side
    reg rst_n = 0;

    reg  [23:0] cpu_addr = 0;
    reg         cpu_rw = 1, cpu_as_n = 1, cpu_ds_n = 1;
    reg  [15:0] cpu_data_in = 0;
    wire [15:0] cpu_data_out;
    wire        regs_nrdy;

    wire        cmd_pending, cmd_clear;
    wire [15:0] csr0_mb;
    wire        int2_mb;
    wire [6:0]  cmd_rap;
    wire [15:0] cmd_data;

    integer pass = 0, fail = 0;
    task check(input cond, input [511:0] name);
        begin
            if (cond) begin pass = pass + 1; $display("  PASS  %0s", name); end
            else      begin fail = fail + 1; $display("  FAIL  %0s", name); end
        end
    endtask

    a2065_regfile regfile (
        .clk(clk_sys), .rst_n(rst_n),
        .cpu_addr(cpu_addr), .cpu_rw(cpu_rw), .cpu_as_n(cpu_as_n),
        .cpu_ds_n(cpu_ds_n), .cpu_data_in(cpu_data_in),
        .cpu_data_out(cpu_data_out), .regs_nrdy(regs_nrdy),
        .card_base(8'hEA), .card_configured(1'b1),
        .cmd_pending(cmd_pending), .cmd_rap(cmd_rap), .cmd_data(cmd_data),
        .cmd_clear(cmd_clear),
        .csr0_in(csr0_mb), .csr1_in(16'd0), .csr2_in(16'd0), .csr3_in(16'd0)
    );

    wire [28:0] avl_address;
    wire [7:0]  avl_burstcount, avl_byteenable;
    wire        avl_read, avl_write;
    wire [63:0] avl_writedata;
    reg  [63:0] avl_readdata = 0;
    reg         avl_readdatavalid = 0;
    wire        avl_waitrequest = 1'b0;

    a2065_ddr3_mailbox mailbox (
        .clk(clk_ddr), .rst_n(rst_n),
        .cmd_pending(cmd_pending), .cmd_rap(cmd_rap), .cmd_data(cmd_data),
        .cmd_clear(cmd_clear),
        .csr0_out(csr0_mb), .csr1_out(), .csr2_out(), .csr3_out(), .a2065_int2(int2_mb),
        .bram_req_valid(1'b0), .bram_req_addr(14'd0), .bram_req_wdata(16'd0),
        .bram_req_rw(1'b0), .bram_req_be(2'b11),
        .bram_req_ack(), .bram_resp_valid(), .bram_resp_data(),
        .avl_address(avl_address), .avl_burstcount(avl_burstcount),
        .avl_read(avl_read), .avl_readdata(avl_readdata),
        .avl_readdatavalid(avl_readdatavalid),
        .avl_writedata(avl_writedata), .avl_byteenable(avl_byteenable),
        .avl_write(avl_write), .avl_waitrequest(avl_waitrequest)
    );

    // Host model: the CSR and INT_STATE words Main writes to DDR3
    localparam AV_CSR = 29'h03FE0000 + 29'h1002;
    localparam AV_INT = 29'h03FE0000 + 29'h1003;
    reg [15:0] host_csr0 = 16'd0;
    reg        host_int  = 1'b0;
    reg        host_pub  = 1'b0;     // publishes its read index (INT bit 1)
    reg [31:0] host_rd   = 32'd0;
    // A host drain landing inside one poll: armed, it is applied (CSR, then
    // INT, as Main writes them) right after the poll's first read is served,
    // so that read sees the old words and the second read the new ones.
    reg        drain_arm = 1'b0;
    reg [15:0] drain_csr0;
    reg        drain_int;
    reg [31:0] drain_rd;
    always @(posedge clk_ddr) begin
        avl_readdatavalid <= avl_read;
        if (avl_read) begin
            avl_readdata <= (avl_address == AV_CSR) ? {48'd0, host_csr0} :
                            (avl_address == AV_INT) ? {host_rd, 30'd0, host_pub, host_int} : 64'd0;
            if (drain_arm) begin
                host_csr0 <= drain_csr0;
                host_int  <= drain_int;
                host_rd   <= drain_rd;
                drain_arm <= 1'b0;
            end
        end
    end

    // Any instant the 68k could read RINT back in CSR0
    reg rint_seen = 1'b0;
    always @(posedge clk_sys) if (csr0_mb[10]) rint_seen <= 1'b1;

    // Watch what the mailbox posts, so the bench can tell a ring entry from
    // the index publication that follows it.
    localparam RING = 29'h03FE0000 + 29'h1100;
    localparam WPTR = 29'h03FE0000 + 29'h1001;
    integer ring_writes = 0;
    reg [63:0] last_entry = 0;
    reg [31:0] last_wptr = 32'hFFFFFFFF;
    always @(posedge clk_ddr) begin
        if (avl_write && !avl_waitrequest) begin
            if (avl_address >= RING && avl_address < RING + 256) begin
                ring_writes <= ring_writes + 1;
                last_entry  <= avl_writedata;
            end
            else if (avl_address == WPTR) last_wptr <= avl_writedata[31:0];
        end
    end

    // A 68k write to RDP, with a bound on the DTACK stretch.
    task rdp_write(input [15:0] val, output done);
        integer guard;
        begin
            done = 0; guard = 0;
            @(negedge clk_sys);
            cpu_addr = 24'hEA4000; cpu_data_in = val; cpu_rw = 0;
            @(negedge clk_sys);
            cpu_as_n = 0; cpu_ds_n = 0;
            while (guard < 300) begin
                @(negedge clk_sys);
                if (!regs_nrdy) begin done = 1; guard = 300; end
                else guard = guard + 1;
            end
            cpu_as_n = 1; cpu_ds_n = 1; cpu_rw = 1;
            repeat (3) @(negedge clk_sys);
        end
    endtask

    // A 68k read of RDP (RAP is 0 throughout: CSR0)
    task rdp_read(output [15:0] val);
        begin
            @(negedge clk_sys);
            cpu_addr = 24'hEA4000; cpu_rw = 1;
            @(negedge clk_sys);
            cpu_as_n = 0; cpu_ds_n = 0;
            @(negedge clk_sys);
            val = cpu_data_out;
            cpu_as_n = 1; cpu_ds_n = 1;
            repeat (3) @(negedge clk_sys);
        end
    endtask

    // Long enough for several CSR/INT polls (one per 64 DDR clocks)
    task polls;
        begin
            repeat (60) @(negedge clk_sys);
        end
    endtask

    reg done;
    reg [15:0] rv;
    integer i, before;

    initial begin
        $display("\\n=== tb_cmd_ring (no host present) ===");
        repeat (10) @(negedge clk_sys);
        rst_n = 1;
        repeat (20) @(negedge clk_sys);

        check(last_wptr == 32'd0, "index published at reset");

        before = ring_writes;
        rdp_write(16'h0004, done);
        check(done, "register write completes with no host to drain it");
        check(ring_writes == before + 1, "one ring entry posted");
        check(last_entry[0] == 1'b1 &&
              last_entry[23:8] == 16'h0004, "entry carries the written data");
        check(last_wptr == 32'd1, "write index advanced");

        // The LANCE init sequence is a burst of back-to-back writes; every one
        // must retire, which a single un-drained slot could not manage.
        done = 1;
        for (i = 0; i < 12 && done; i = i + 1)
            rdp_write(16'h0040 + i[15:0], done);
        check(done, "12 back-to-back register writes all complete");
        check(last_wptr == 32'd13, "index advanced once per write");

        // ---- CSR0 acknowledge, older host (no read index published) ----
        // Unchanged behaviour: the shadow follows the host.
        host_csr0 = 16'h04F3; host_int = 1; host_pub = 0; host_rd = 32'd13;
        polls;
        rdp_read(rv);
        check(rv == 16'h04F3 && int2_mb, "RINT pending is seen: CSR0 04F3, INT2 set");
        rdp_write(16'h0440, done);
        polls;
        rdp_read(rv);
        check(done && rv == 16'h04F3, "older host: shadow still follows the host");

        // ---- host publishing its read index, but stalled ----
        // Main is blocked (its IDE handler waits on the Amiga): the ring is
        // never drained and the DDR3 words never change after this.
        host_pub = 1; host_rd = last_wptr;
        polls;
        before = last_wptr;
        rdp_write(16'h0440, done);
        check(done, "acknowledge write completes with the host stalled");
        rdp_read(rv);
        check(rv == 16'h0073, "acknowledge shows in the very next read: CSR0 0073");
        check(!int2_mb, "interrupt line drops with the last cause cleared");
        polls; polls;
        rdp_read(rv);
        check(rv == 16'h0073 && !int2_mb, "polls of the stale host value keep RINT cleared");

        // the handler's loop terminates: one more read, no further writes
        check(last_wptr == before + 1, "exactly one ring entry for the acknowledge");

        // ---- host catches up, then a new frame arrives ----
        host_csr0 = 16'h0073; host_int = 0; host_rd = last_wptr;
        polls;
        rdp_read(rv);
        check(rv == 16'h0073 && !int2_mb, "host consumed the acknowledge: values agree");
        host_csr0 = 16'h04F3; host_int = 1;
        polls;
        rdp_read(rv);
        check(rv == 16'h04F3 && int2_mb, "a later RINT from the host is not masked");

        // ---- only the acknowledged bits are held ----
        // TINT pending too; the driver acknowledges RINT alone.
        host_csr0 = 16'h06F3; host_int = 1;
        polls;
        rdp_write(16'h0440, done);
        rdp_read(rv);
        check(rv == 16'h02F3 && int2_mb, "RINT cleared, TINT and INTR stay, line stays up");
        polls;
        rdp_read(rv);
        check(rv == 16'h02F3, "stale host value: only RINT masked");

        // ---- host drains the acknowledge in the middle of a poll ----
        // The poll must not pair a CSR value from before the drain with a
        // read index from after it: that unmasks RINT on the stale value.
        host_csr0 = 16'h0073; host_int = 0; host_rd = last_wptr;
        polls;
        host_csr0 = 16'h04F3; host_int = 1;
        polls;
        rdp_read(rv);
        check(rv == 16'h04F3 && int2_mb, "new RINT seen before the race");
        rdp_write(16'h0440, done);
        drain_csr0 = 16'h0073; drain_int = 0; drain_rd = last_wptr;
        rint_seen = 1'b0;
        drain_arm = 1'b1;
        polls; polls;
        check(!drain_arm, "the drain landed inside a poll");
        check(!rint_seen, "RINT never reappears across the drain");
        rdp_read(rv);
        check(rv == 16'h0073 && !int2_mb, "settles on the host's value: CSR0 0073, INT2 low");

        // ---- no-op CSR0 writes (INEA alone, repeated) take no ring entry ----
        host_csr0 = 16'h0073; host_int = 0; host_rd = last_wptr;
        polls;
        rdp_write(16'h0040, done);
        before = last_wptr;
        rdp_write(16'h0040, done); rdp_write(16'h0040, done);
        check(done && last_wptr == before, "repeated INEA-only writes post no entry");

        // ---- an INEA change still in the ring: the next INEA write counts ----
        // Host shadow still shows INEA (it has not applied 0000 yet).
        before = last_wptr;
        rdp_write(16'h0000, done);
        rdp_write(16'h0040, done);
        check(last_wptr == before + 2, "0000 then 0040 with the host behind: both posted");
        check(last_entry[23:8] == 16'h0040, "the last entry re-enables INEA");

        $display("=== %0d passed, %0d failed ===\\n", pass, fail);
        if (fail) $fatal(1, "cmd ring tests failed");
        $finish;
    end

    initial begin
        #400000;
        $display("GLOBAL TIMEOUT — register write never retired");
        $fatal(1, "timeout");
    end

endmodule
