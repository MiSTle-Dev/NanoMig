
`timescale 1ns/1ps
module tb_sdram_fwd;

  integer errs = 0;

  reg sysclk = 0;
  always #5 sysclk = ~sysclk;

  reg [3:0] clkdiv = 0;
  reg c_7m = 0;
  always @(posedge sysclk) begin
    clkdiv <= clkdiv + 1'b1;
    c_7m   <= clkdiv[3];
  end

  reg reset_n = 0;

  reg  [24:1] chipAddr = 0;
  reg         chipL = 1, chipU = 1;
  reg         chipRW = 1;
  reg         chipDMA = 0;
  reg  [15:0] chipWR = 0;
  wire [15:0] chipRD;
  wire [47:0] chip48;

  reg  [24:1] cpuAddr = 0;
  reg         cpuCS = 0;
  reg  [1:0]  cpustate = 2'b01;
  reg         cpuL = 1, cpuU = 1;
  reg  [15:0] cpuWR = 0;
  wire [15:0] cpuRD;
  wire        ramready;

  wire [12:0] sd_addr;
  wire [1:0]  sd_ba;
  wire        sd_cs, sd_we, sd_ras, sd_cas, sd_clk, sd_cke;
  wire [1:0]  sd_dqm;
  wire [15:0] sd_data;

  wire [3:0] st = dut.sdram_state;
  reg drive = 1;
  assign sd_data = drive ? (16'hBB00 + {12'd0, st}) : 16'hzzzz;

  sdram_ctrl dut (
    .sysclk(sysclk), .c_7m(c_7m), .reset_n(reset_n),
    .cache_rst(1'b1), .cache_inhibit(1'b0),
    .cpu_cache_ctrl(4'b1111), .dcache_sw_en(1'b1),
    .sd_addr(sd_addr), .sd_ba(sd_ba), .sd_cs(sd_cs), .sd_we(sd_we),
    .sd_ras(sd_ras), .sd_cas(sd_cas), .sd_dqm(sd_dqm), .sd_data(sd_data),
    .sd_clk(sd_clk), .sd_cke(sd_cke),
    .chipAddr(chipAddr), .chipL(chipL), .chipU(chipU), .chipRW(chipRW),
    .chipDMA(chipDMA), .chipWR(chipWR), .chipRD(chipRD), .chip48(chip48),
    .cpuAddr(cpuAddr), .cpuCS(cpuCS), .cpustate(cpustate),
    .cpuL(cpuL), .cpuU(cpuU), .cpuWR(cpuWR), .cpuRD(cpuRD), .ramready(ramready)
  );

  function [15:0] raw_word(input [1:0] idx);
    raw_word = 16'hBB00 + (7 + 2*idx);
  endfunction

  task post_cpu_write(input [24:1] a, input [15:0] d, input bU, input bL);
    begin
      @(posedge sysclk);
      cpuAddr  <= a;
      cpuWR    <= d;
      cpuU     <= bU;
      cpuL     <= bL;
      cpustate <= 2'b11;
      cpuCS    <= 1'b1;
      repeat (4) @(posedge sysclk);
      cpuCS    <= 1'b0;
      cpustate <= 2'b01;
      cpuU     <= 1'b1;
      cpuL     <= 1'b1;
    end
  endtask

  task capture_burst(output [15:0] w0, output [15:0] w1, output [15:0] w2, output [15:0] w3);
    begin
      @(posedge sysclk);
      wait (dut.sdram_state == 4'd0);
      @(posedge sysclk);
      wait (dut.sdram_state == 4'd15);
      @(posedge sysclk);
      @(posedge sysclk);
      w0 = chipRD; w1 = chip48[47:32]; w2 = chip48[31:16]; w3 = chip48[15:0];
    end
  endtask

  reg probed = 0;
  always @(posedge sysclk)
    if (!probed && dut.init_done && dut.sdram_state==4'd1 && dut.write_req) begin
      $display("PROBE @frame: write_req=%b writeAddr=%h chipAddr=%h fwd_en=%b fwd_pos=%0d",
               dut.write_req, dut.writeAddr, chipAddr, dut.fwd_en, dut.fwd_pos);
      probed <= 1;
    end

  task check(input [255:0] name, input [15:0] got, input [15:0] exp);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %04h exp %04h", name, got, exp);
        errs = errs + 1;
      end
    end
  endtask

  reg [15:0] g0,g1,g2,g3;
  reg [15:0] ctl0,ctl1,ctl2,ctl3;
  integer p;
  reg [24:1] blk;
  reg [15:0] wd;

  function [15:0] base(input [1:0] idx);
    base = (idx==0)?ctl0 : (idx==1)?ctl1 : (idx==2)?ctl2 : ctl3;
  endfunction

  task reinit;
    begin
      reset_n = 0;
      cpuCS = 0; cpustate = 2'b01; cpuU = 1; cpuL = 1;
      repeat (20) @(posedge sysclk);
      reset_n = 1;
      wait (dut.init_done == 1'b1);
      repeat (32) @(posedge sysclk);
    end
  endtask

  initial begin
    blk = 24'h001000;

    reinit;
    chipAddr <= blk;
    capture_burst(ctl0,ctl1,ctl2,ctl3);
    $display("CTRL baseline: w0=%04h w1=%04h w2=%04h w3=%04h", ctl0,ctl1,ctl2,ctl3);

    for (p = 0; p < 4; p = p + 1) begin
      reinit;
      wd = 16'hDEAD + p[15:0];
      post_cpu_write({blk[24:3], p[1:0]}, wd, 1'b0, 1'b0);
      chipAddr <= blk;
      capture_burst(g0,g1,g2,g3);
      check("fullw.match", (p==0?g0:p==1?g1:p==2?g2:g3), wd);
      if (p!=0) check("fullw.w0raw", g0, base(0));
      if (p!=1) check("fullw.w1raw", g1, base(1));
      if (p!=2) check("fullw.w2raw", g2, base(2));
      if (p!=3) check("fullw.w3raw", g3, base(3));
    end

    reinit;
    wd = 16'h1234;
    post_cpu_write({blk[24:3], 2'd1}, wd, 1'b1, 1'b0);
    chipAddr <= blk;
    capture_burst(g0,g1,g2,g3);
    check("lob.merge", g1, {base(1)[15:8], wd[7:0]});
    check("lob.w0raw", g0, base(0));

    reinit;
    wd = 16'hABCD;
    post_cpu_write({blk[24:3], 2'd3}, wd, 1'b0, 1'b1);
    chipAddr <= blk;
    capture_burst(g0,g1,g2,g3);
    check("hib.merge", g3, {wd[15:8], base(3)[7:0]});

    reinit;
    post_cpu_write({(blk[24:3]+4'd1), 2'd0}, 16'hFFFF, 1'b0, 1'b0);
    chipAddr <= blk;
    capture_burst(g0,g1,g2,g3);
    check("nomatch.w0", g0, base(0));
    check("nomatch.w1", g1, base(1));
    check("nomatch.w2", g2, base(2));
    check("nomatch.w3", g3, base(3));

    if (errs == 0) $display("RUN: PASS (forwarding correct)");
    else           $display("RUN: FAIL (%0d errors)", errs);
    $finish;
  end

  initial begin
    #2000000;
    $display("RUN: FAIL (timeout)");
    errs = errs + 1;
    $finish;
  end

endmodule
