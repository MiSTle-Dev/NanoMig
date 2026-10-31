/*
 * tb_ddram_arbiter.v — checks a2065_ddram_arbiter.
 *
 * The failure this guards against: the previous arbiter latched its grant to
 * one master forever after a single-beat write, which on the core's DDR3 port
 * would starve the 68k fast-RAM path and hang the Amiga. So the tests care
 * mostly about the bus being released, and about m0 never being made to wait
 * behind m1.
 */
`timescale 1ns/1ps

module tb_ddram_arbiter;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [28:0] m0_address = 0,  m1_address = 0;
    reg  [7:0]  m0_burstcount = 0, m1_burstcount = 0;
    reg         m0_read = 0,    m1_read = 0;
    reg  [63:0] m0_writedata = 0, m1_writedata = 0;
    reg  [7:0]  m0_byteenable = 8'hFF, m1_byteenable = 8'hFF;
    reg         m0_write = 0,   m1_write = 0;
    wire [63:0] m0_readdata, m1_readdata;
    wire        m0_readdatavalid, m1_readdatavalid;
    wire        m0_waitrequest, m1_waitrequest;

    wire [28:0] s_address;
    wire [7:0]  s_burstcount, s_byteenable;
    wire        s_read, s_write;
    wire [63:0] s_writedata;
    reg  [63:0] s_readdata = 0;
    reg         s_readdatavalid = 0;
    reg         s_waitrequest = 0;

    integer pass = 0, fail = 0;

    task check(input cond, input [511:0] name);
        begin
            if (cond) begin pass = pass + 1; $display("  PASS  %0s", name); end
            else      begin fail = fail + 1; $display("  FAIL  %0s", name); end
        end
    endtask

    a2065_ddram_arbiter dut (
        .clk(clk), .rst(rst),
        .m0_address(m0_address), .m0_burstcount(m0_burstcount), .m0_read(m0_read),
        .m0_readdata(m0_readdata), .m0_readdatavalid(m0_readdatavalid),
        .m0_writedata(m0_writedata), .m0_byteenable(m0_byteenable),
        .m0_write(m0_write), .m0_waitrequest(m0_waitrequest),
        .m1_address(m1_address), .m1_burstcount(m1_burstcount), .m1_read(m1_read),
        .m1_readdata(m1_readdata), .m1_readdatavalid(m1_readdatavalid),
        .m1_writedata(m1_writedata), .m1_byteenable(m1_byteenable),
        .m1_write(m1_write), .m1_waitrequest(m1_waitrequest),
        .s_address(s_address), .s_burstcount(s_burstcount), .s_read(s_read),
        .s_readdata(s_readdata), .s_readdatavalid(s_readdatavalid),
        .s_writedata(s_writedata), .s_byteenable(s_byteenable),
        .s_write(s_write), .s_waitrequest(s_waitrequest)
    );

    // Single-beat write from m1, the case that wedged the old arbiter.
    task m1_single_write(input [28:0] addr);
        begin
            @(negedge clk);
            m1_address = addr; m1_burstcount = 1; m1_writedata = 64'hDEAD; m1_write = 1;
            @(negedge clk);
            while (m1_waitrequest) @(negedge clk);
            m1_write = 0;                       // master drops write once accepted
        end
    endtask

    task m0_single_write(input [28:0] addr);
        begin
            @(negedge clk);
            m0_address = addr; m0_burstcount = 1; m0_writedata = 64'hBEEF; m0_write = 1;
            @(negedge clk);
            while (m0_waitrequest) @(negedge clk);
            m0_write = 0;
        end
    endtask

    // ddram_ctrl only asserts a request while it sees ~DDRAM_BUSY, so an idle
    // master that is held off never asks for the bus at all. Model that here:
    // an arbiter that stalls idle masters deadlocks with this and the 68k never
    // reaches fast RAM. Times out rather than hanging the run.
    task m0_gated_write(input [28:0] addr, output ok);
        integer guard;
        begin
            ok = 0;
            guard = 0;
            @(negedge clk);
            while (!ok && guard < 40) begin
                if (!m0_waitrequest) begin          // only then may it request
                    m0_address = addr; m0_burstcount = 1;
                    m0_writedata = 64'hBEEF; m0_write = 1;
                    @(negedge clk);
                    if (!m0_waitrequest) begin m0_write = 0; ok = 1; end
                end
                else @(negedge clk);
                guard = guard + 1;
            end
            m0_write = 0;
        end
    endtask

    integer i;
    reg ok;

    initial begin
        $display("\n=== tb_ddram_arbiter ===");
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // 0. The regression that stopped the Amiga booting: a waitrequest-gated
        //    master must be able to start from a completely idle bus.
        m0_gated_write(29'h010, ok);
        check(ok, "waitrequest-gated m0 can start from idle bus");
        repeat (2) @(negedge clk);
        m0_gated_write(29'h018, ok);
        check(ok, "waitrequest-gated m0 can start again");
        repeat (2) @(negedge clk);

        // 1. m1 single write, then m0 must still get through. This is the exact
        //    sequence that left the old arbiter stuck granting m1.
        m1_single_write(29'h100);
        repeat (3) @(negedge clk);
        check(!dut.busy, "bus released after m1 single-beat write");

        fork : m0_after
            begin
                m0_single_write(29'h200);
                disable watchdog0;
            end
            begin : watchdog0
                repeat (20) @(negedge clk);
                check(1'b0, "m0 write completes after m1 (TIMED OUT)");
            end
        join
        check(1'b1, "m0 write completes after m1 single-beat write");

        // 2. Repeated m1 writes must not accumulate any lockup.
        for (i = 0; i < 4; i = i + 1) m1_single_write(29'h300 + i);
        repeat (3) @(negedge clk);
        check(!dut.busy, "bus released after repeated m1 writes");

        // 3. Priority: with both requesting from idle, m0 must win.
        @(negedge clk);
        m0_address = 29'h400; m0_burstcount = 1; m0_write = 1;
        m1_address = 29'h500; m1_burstcount = 1; m1_write = 1;
        @(negedge clk);
        check(s_address == 29'h400 && !m0_waitrequest && m1_waitrequest,
              "m0 wins arbitration against m1");
        m0_write = 0;
        @(negedge clk);
        while (m1_waitrequest) @(negedge clk);
        m1_write = 0;
        repeat (2) @(negedge clk);

        // 4. Burst write from m0 holds the bus for its whole burst.
        @(negedge clk);
        m0_address = 29'h600; m0_burstcount = 4; m0_write = 1; m0_writedata = 64'h11;
        @(negedge clk);                       // beat 1 accepted at grant
        m1_address = 29'h700; m1_burstcount = 1; m1_write = 1;   // m1 barges in
        check(m1_waitrequest, "m1 held off during m0 burst");
        repeat (3) @(negedge clk);            // beats 2..4
        m0_write = 0;
        @(negedge clk);
        check(!m1_waitrequest, "m1 granted once m0 burst completes");
        while (m1_waitrequest) @(negedge clk);
        m1_write = 0;
        repeat (2) @(negedge clk);

        // 5. Read data routes to the master that asked, and only to it.
        @(negedge clk);
        m1_address = 29'h800; m1_burstcount = 1; m1_read = 1;
        @(negedge clk);
        while (m1_waitrequest) @(negedge clk);
        m1_read = 0;
        @(negedge clk);
        s_readdata = 64'hCAFE; s_readdatavalid = 1;
        @(negedge clk);
        check(m1_readdatavalid && !m0_readdatavalid && m1_readdata == 64'hCAFE,
              "read data routed to m1 only");
        s_readdatavalid = 0;
        repeat (2) @(negedge clk);
        check(!dut.busy, "bus released after m1 read completes");

        // 6. A read must keep the bus until its data returns, not just its
        //    command being accepted.
        @(negedge clk);
        m0_address = 29'h900; m0_burstcount = 2; m0_read = 1;
        @(negedge clk);
        while (m0_waitrequest) @(negedge clk);
        m0_read = 0;
        @(negedge clk);
        check(dut.busy, "bus held while read data outstanding");
        s_readdata = 64'h1; s_readdatavalid = 1; @(negedge clk);
        s_readdata = 64'h2;                     @(negedge clk);
        s_readdatavalid = 0;
        repeat (2) @(negedge clk);
        check(!dut.busy, "bus released after 2-beat read returns");

        // 7. Slave back-pressure must not corrupt tracking.
        @(negedge clk);
        s_waitrequest = 1;
        m1_address = 29'hA00; m1_burstcount = 1; m1_write = 1;
        repeat (3) @(negedge clk);
        check(!dut.busy && m1_waitrequest, "no burst starts while slave stalls");
        s_waitrequest = 0;
        @(negedge clk);
        while (m1_waitrequest) @(negedge clk);
        m1_write = 0;
        repeat (2) @(negedge clk);
        check(!dut.busy, "bus released after stalled write completes");

        $display("=== %0d passed, %0d failed ===\n", pass, fail);
        if (fail) $fatal(1, "arbiter tests failed");
        $finish;
    end

    // Safety net: the whole run should never take this long.
    initial begin
        #20000;
        $display("GLOBAL TIMEOUT — arbiter likely wedged");
        $fatal(1, "timeout");
    end

endmodule
