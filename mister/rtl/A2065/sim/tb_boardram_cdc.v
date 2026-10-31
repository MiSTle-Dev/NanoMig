/*
 * tb_boardram_cdc.v — 68k boardram access across the clk_sys/DDRAM_CLK boundary.
 *
 * a2065_ddram runs in the Amiga's clock domain and stretches DTACK until the
 * mailbox, in the DDR3 clock domain, has completed the transfer. The two are
 * roughly 28 MHz and 114 MHz, so any reply the mailbox sends as a single-cycle
 * pulse (~9 ns) is far shorter than the ~35 ns sampling period on the other
 * side and can be missed entirely — which strands DTACK asserted and hangs the
 * 68k on its first boardram access.
 *
 * This drives real 68k-style bus cycles through both modules against a stub
 * DDR3 slave and requires each cycle to terminate, so a reply that cannot cross
 * the domain shows up as a failed test rather than a hung Amiga.
 */
`timescale 1ns/1ps

module tb_boardram_cdc;

    // 28.636 MHz Amiga side, 114.545 MHz DDR3 side — the real ratio.
    reg clk_sys = 0;  always #17.46 clk_sys = ~clk_sys;
    reg clk_ddr = 0;  always #4.364 clk_ddr = ~clk_ddr;

    reg rst_n = 0;

    reg  [23:1] cpu_addr = 0;
    reg  [15:0] cpu_data_in = 0;
    reg         cpu_rw = 1, cpu_as_n = 1, cpu_uds_n = 1, cpu_lds_n = 1, sel = 0;
    wire [15:0] cpu_data_out;
    wire        nrdy;

    wire        req_valid, req_rw, req_ack, resp_valid;
    wire [13:0] req_addr;
    wire [15:0] req_wdata, resp_data;
    wire [1:0]  req_be;

    integer pass = 0, fail = 0;
    task check(input cond, input [511:0] name);
        begin
            if (cond) begin pass = pass + 1; $display("  PASS  %0s", name); end
            else      begin fail = fail + 1; $display("  FAIL  %0s", name); end
        end
    endtask

    a2065_ddram ddram (
        .clk_sys(clk_sys), .rst_n_sys(rst_n),
        .cpu_addr(cpu_addr), .cpu_data_in(cpu_data_in), .cpu_data_out(cpu_data_out),
        .cpu_rw(cpu_rw), .cpu_as_n(cpu_as_n), .cpu_uds_n(cpu_uds_n), .cpu_lds_n(cpu_lds_n),
        .sel(sel), .nrdy(nrdy),
        .bram_req_valid(req_valid), .bram_req_addr(req_addr),
        .bram_req_wdata(req_wdata), .bram_req_rw(req_rw), .bram_req_be(req_be),
        .bram_req_ack_audio(req_ack),
        .bram_resp_valid_audio(resp_valid), .bram_resp_data_audio(resp_data)
    );

    wire [28:0] avl_address;
    wire [7:0]  avl_burstcount, avl_byteenable;
    wire        avl_read, avl_write;
    wire [63:0] avl_writedata;
    reg  [63:0] avl_readdata = 64'h3333_2222_1111_0000;
    reg         avl_readdatavalid = 0;
    wire        avl_waitrequest = 1'b0;      // stub slave, always ready

    a2065_ddr3_mailbox mailbox (
        .clk(clk_ddr), .rst_n(rst_n),
        .cmd_pending(1'b0), .cmd_rap(7'd0), .cmd_data(16'd0), .cmd_clear(),
        .csr0_out(), .csr1_out(), .csr2_out(), .csr3_out(), .a2065_int2(),
        .bram_req_valid(req_valid), .bram_req_addr(req_addr),
        .bram_req_wdata(req_wdata), .bram_req_rw(req_rw), .bram_req_be(req_be),
        .bram_req_ack(req_ack),
        .bram_resp_valid(resp_valid), .bram_resp_data(resp_data),
        .avl_address(avl_address), .avl_burstcount(avl_burstcount),
        .avl_read(avl_read), .avl_readdata(avl_readdata),
        .avl_readdatavalid(avl_readdatavalid),
        .avl_writedata(avl_writedata), .avl_byteenable(avl_byteenable),
        .avl_write(avl_write), .avl_waitrequest(avl_waitrequest)
    );

    // Stub DDR3: return data one cycle after any read is accepted.
    always @(posedge clk_ddr) avl_readdatavalid <= avl_read;

    // One 68k bus cycle, with a bound on how long DTACK may be stretched.
    // Returns done=0 if the cycle never terminated (the hang being guarded).
    task bus_cycle(input rw, input [23:1] addr, input [15:0] wdata, output done);
        integer guard;
        begin
            done = 0; guard = 0;
            @(negedge clk_sys);
            cpu_addr = addr; cpu_data_in = wdata; cpu_rw = rw; sel = 1;
            @(negedge clk_sys);
            cpu_as_n = 0; cpu_uds_n = 0; cpu_lds_n = 0;   // strobes assert
            while (guard < 400) begin
                @(negedge clk_sys);
                if (!nrdy) begin done = 1; guard = 400; end
                else guard = guard + 1;
            end
            cpu_as_n = 1; cpu_uds_n = 1; cpu_lds_n = 1; sel = 0;   // cycle ends
            repeat (4) @(negedge clk_sys);
        end
    endtask

    reg done;
    integer i;

    initial begin
        $display("\n=== tb_boardram_cdc ===");
        repeat (8) @(negedge clk_sys);
        rst_n = 1;
        repeat (4) @(negedge clk_sys);

        // A single write is what the buffer memory test does first.
        bus_cycle(1'b0, 23'h548000 >> 1, 16'hA5A5, done);
        check(done, "boardram write completes (DTACK released)");

        bus_cycle(1'b1, 23'h548000 >> 1, 16'h0000, done);
        check(done, "boardram read completes (DTACK released)");

        // The buffer test walks the whole window, so back-to-back cycles must
        // keep completing — a handshake that only works once still hangs.
        done = 1;
        for (i = 0; i < 8 && done; i = i + 1)
            bus_cycle(i[0], 23'h548000 >> 1, 16'h1234, done);
        check(done, "8 back-to-back boardram cycles all complete");

        $display("=== %0d passed, %0d failed ===\n", pass, fail);
        if (fail) $fatal(1, "boardram CDC tests failed");
        $finish;
    end

    initial begin
        #500000;
        $display("GLOBAL TIMEOUT — boardram handshake wedged");
        $fatal(1, "timeout");
    end

endmodule
