
`timescale 1ns/1ps

module tb_cache_snoop;

  reg         clk = 0;
  reg         rst = 1;

  reg  [3:0]  cpu_cache_ctrl = 4'b0001;
  reg         dcache_sw_en   = 1'b1;
  reg         cache_inhibit  = 1'b0;
  reg         cpu_cs = 0;
  reg  [28:1] cpu_adr = 0;
  reg  [1:0]  cpu_bs = 2'b11;
  reg         cpu_we = 0;
  reg         cpu_ir = 0;
  reg         cpu_dr = 0;
  reg  [15:0] cpu_dat_w = 0;
  wire [15:0] cpu_dat_r;
  wire        cpu_ack;
  wire        wb_en;

  wire [15:0] sdr_dat_r;
  wire        sdr_read_req;
  reg         sdr_read_ack = 0;
  reg  [15:0] sdr_dat_r_r  = 0;
  assign sdr_dat_r = sdr_dat_r_r;

  reg         snoop_act = 0;
  reg  [28:1] snoop_adr = 0;
  reg  [15:0] snoop_dat_w = 0;
  reg  [1:0]  snoop_bs = 2'b11;

  integer errs       = 0;
  integer race_fails = 0;

  localparam [15:0] OLD = 16'h1111;
  localparam [15:0] NEW = 16'h2222;

  always #5 clk = ~clk;

  cpu_cache_new dut (
    .clk            (clk),
    .rst            (rst),
    .cpu_cache_ctrl (cpu_cache_ctrl),
    .dcache_sw_en   (dcache_sw_en),
    .cache_inhibit  (cache_inhibit),
    .cpu_cs         (cpu_cs),
    .cpu_adr        (cpu_adr),
    .cpu_bs         (cpu_bs),
    .cpu_we         (cpu_we),
    .cpu_ir         (cpu_ir),
    .cpu_dr         (cpu_dr),
    .cpu_dat_w      (cpu_dat_w),
    .cpu_dat_r      (cpu_dat_r),
    .cpu_ack        (cpu_ack),
    .wb_en          (wb_en),
    .sdr_dat_r      (sdr_dat_r),
    .sdr_read_req   (sdr_read_req),
    .sdr_read_ack   (sdr_read_ack),
    .snoop_act      (snoop_act),
    .snoop_adr      (snoop_adr),
    .snoop_dat_w    (snoop_dat_w),
    .snoop_bs       (snoop_bs)
  );

  reg [15:0] backing [0:65535];

  reg        bursting = 0;
  reg [2:0]  beat = 0;
  reg [15:0] snap [0:3];

  always @(posedge clk) begin
    sdr_read_ack <= 1'b0;
    if (rst) begin
      bursting <= 0;
      beat     <= 0;
    end else begin
      if (sdr_read_req && !bursting) begin
        bursting  <= 1'b1;
        beat      <= 3'd0;
        snap[0]   <= backing[{cpu_adr[16:3], 2'd0}];
        snap[1]   <= backing[{cpu_adr[16:3], 2'd1}];
        snap[2]   <= backing[{cpu_adr[16:3], 2'd2}];
        snap[3]   <= backing[{cpu_adr[16:3], 2'd3}];
      end
      if (bursting) begin
        sdr_dat_r_r  <= snap[cpu_adr[2:1] + beat[1:0]];
        sdr_read_ack <= 1'b1;
        beat         <= beat + 3'd1;
        if (beat == 3'd3) bursting <= 1'b0;
      end
    end
  end

  function [28:1] mkadr(input [7:0] idx, input [1:0] blk);
    mkadr = {18'd0, idx, blk};
  endfunction

  task automatic cpu_data_read(input [28:1] adr, output [15:0] data);
    begin
      @(posedge clk);
      cpu_adr <= adr;
      cpu_bs  <= 2'b11;
      cpu_we  <= 1'b0;
      cpu_ir  <= 1'b0;
      cpu_dr  <= 1'b1;
      cpu_cs  <= 1'b1;
      while (!cpu_ack) @(posedge clk);
      data = cpu_dat_r;
      @(posedge clk);
      cpu_cs <= 1'b0;
      cpu_dr <= 1'b0;
      @(posedge clk);
    end
  endtask

  task automatic do_snoop(input [28:1] adr, input [15:0] data);
    begin
      @(posedge clk);
      snoop_adr <= adr; snoop_dat_w <= data; snoop_bs <= 2'b11; snoop_act <= 1'b1;
      @(posedge clk);
      snoop_act <= 1'b0;
      repeat (4) @(posedge clk);
    end
  endtask

  task automatic do_byte_snoop(input [28:1] adr, input [15:0] data,
                               input [1:0] bs, input integer hold,
                               input integer gap);
    integer h;
    begin
      @(posedge clk);
      snoop_adr <= adr; snoop_dat_w <= data; snoop_bs <= bs; snoop_act <= 1'b1;
      for (h = 0; h < hold; h = h + 1) @(posedge clk);
      @(posedge clk);
      snoop_act <= 1'b0;
      for (h = 0; h < gap; h = h + 1) @(posedge clk);
    end
  endtask

  task automatic check(input [15:0] got, input [15:0] exp, input [255:0] msg);
    begin
      if (got !== exp) begin
        errs = errs + 1;
        $display("[FAIL] %0s: got %04x exp %04x @%0t", msg, got, exp, $time);
      end else begin
        $display("[ ok ] %0s: %04x", msg, got);
      end
    end
  endtask

  task automatic race_iter(input integer d, input [1:0] sblk, input [7:0] idx,
                           output integer failed);
    reg [15:0] rd;
    integer k;
    begin
      failed = 0;
      backing[{idx,2'd0}] = 16'h00B0;
      backing[{idx,2'd1}] = 16'h00B1;
      backing[{idx,2'd2}] = 16'h00B2;
      backing[{idx,2'd3}] = 16'h00B3;
      backing[{idx,sblk}] = OLD;

      @(posedge clk);
      cpu_adr <= mkadr(idx, 2'd0);
      cpu_bs  <= 2'b11; cpu_we <= 0; cpu_ir <= 0; cpu_dr <= 1; cpu_cs <= 1;

      for (k = 0; k < d; k = k + 1) @(posedge clk);
      backing[{idx,sblk}] = NEW;
      snoop_adr   <= mkadr(idx, sblk);
      snoop_dat_w <= NEW;
      snoop_bs    <= 2'b11;
      snoop_act   <= 1'b1;
      @(posedge clk);
      snoop_act   <= 1'b0;
      repeat (4) @(posedge clk);

      k = 0;
      while (!cpu_ack && k < 40) begin @(posedge clk); k = k + 1; end
      @(posedge clk);
      cpu_cs <= 1'b0; cpu_dr <= 1'b0;
      repeat (8) @(posedge clk);

      cpu_data_read(mkadr(idx, sblk), rd);
      if (rd !== NEW) begin
        failed = 1;
        $display("  [RACE d=%0d blk=%0d idx=%02x] STALE: re-read got %04x exp %04x",
                 d, sblk, idx, rd, NEW);
      end
    end
  endtask

  reg [15:0] rd;
  integer i;
  integer sb;
  integer f;
  integer idx_ctr;

  initial begin
    for (i = 0; i < 65536; i = i + 1) backing[i] = 16'hDEAD;
    backing[16'h0100] = 16'h1111;
    backing[16'h0101] = 16'h2222;
    backing[16'h0102] = 16'h3333;
    backing[16'h0103] = 16'h4444;

    rst = 1;
    repeat (8) @(posedge clk);
    rst = 0;
    repeat (400) @(posedge clk);

    cpu_data_read(28'h0100, rd);
    check(rd, 16'h1111, "read word 0x100 (miss->fill)");
    cpu_data_read(28'h0101, rd);
    check(rd, 16'h2222, "read word 0x101 (same line)");
    cpu_data_read(28'h0100, rd);
    check(rd, 16'h1111, "read word 0x100 again (hit)");

    backing[{8'hA0,2'd0}] = 16'h3333;
    cpu_data_read(mkadr(8'hA0,2'd0), rd);
    check(rd, 16'h3333, "1b: fill line A0");
    do_snoop(mkadr(8'hA0,2'd0), 16'h4444);
    cpu_data_read(mkadr(8'hA0,2'd0), rd);
    check(rd, 16'h4444, "1b: snoop-updated valid line (write-through intact)");

    backing[{8'hB0,2'd0}] = 16'h5555;
    backing[{8'hB0,2'd1}] = 16'h00C1;
    backing[{8'hB0,2'd2}] = 16'h00C2;
    backing[{8'hB0,2'd3}] = 16'h00C3;
    @(posedge clk);
    cpu_adr <= mkadr(8'hB0, 2'd0);
    cpu_bs <= 2'b11; cpu_we<=0; cpu_ir<=0; cpu_dr<=1; cpu_cs<=1;
    for (i = 0; i < 4; i = i + 1) @(posedge clk);
    snoop_adr <= mkadr(8'hB1, 2'd0);
    snoop_dat_w <= 16'h6666; snoop_bs<=2'b11; snoop_act<=1'b1;
    @(posedge clk); snoop_act<=1'b0;
    repeat (4) @(posedge clk);
    i = 0; while (!cpu_ack && i < 40) begin @(posedge clk); i = i + 1; end
    @(posedge clk); cpu_cs<=0; cpu_dr<=0;
    repeat (8) @(posedge clk);
    backing[{8'hB0,2'd0}] = 16'h7777;
    cpu_data_read(mkadr(8'hB0,2'd0), rd);
    check(rd, 16'h5555, "1c: fill line NOT evicted by snoop to other line (hit)");

    $display("---- race sweep (D-Cache ON): chip write of NEW lands +d into fill ----");
    idx_ctr = 8'h50;
    for (sb = 0; sb < 4; sb = sb + 1) begin
      for (i = 0; i <= 18; i = i + 1) begin
        race_iter(i, sb[1:0], idx_ctr[7:0], f);
        race_fails = race_fails + f;
        idx_ctr = idx_ctr + 1;
      end
    end
    $display("RACE: %0d of 76 (block,offset) cases returned STALE data (cache incoherent)", race_fails);

    $display("---- Stage 3: byte-write snoop on valid cached line ----");
    backing[{8'hC0,2'd0}] = 16'hAABB;
    cpu_data_read(mkadr(8'hC0,2'd0), rd);
    check(rd, 16'hAABB, "3: fill word C0:0 = AABB");
    do_byte_snoop(mkadr(8'hC0,2'd0), 16'h00CC, 2'b01, 0, 6);
    cpu_data_read(mkadr(8'hC0,2'd0), rd);
    check(rd, 16'hAACC, "3: lower-byte snoop -> AACC (upper preserved)");
    do_byte_snoop(mkadr(8'hC0,2'd0), 16'hDD00, 2'b10, 0, 6);
    cpu_data_read(mkadr(8'hC0,2'd0), rd);
    check(rd, 16'hDDCC, "3: upper-byte snoop -> DDCC (lower preserved)");

    $display("---- Stage 4: byte-stream snoop over a cached line ----");
    for (i = 0; i < 4; i = i + 1) backing[{8'hC4,i[1:0]}] = 16'h0000;
    for (i = 0; i < 4; i = i + 1) cpu_data_read(mkadr(8'hC4,i[1:0]), rd);
    for (i = 0; i < 4; i = i + 1) begin
      do_byte_snoop(mkadr(8'hC4,i[1:0]), {8'h00, 8'h10 + i[7:0]}, 2'b01, 0, 5);
      do_byte_snoop(mkadr(8'hC4,i[1:0]), {8'h20 + i[7:0], 8'h00}, 2'b10, 0, 5);
    end
    for (i = 0; i < 4; i = i + 1) begin
      cpu_data_read(mkadr(8'hC4,i[1:0]), rd);
      check(rd, {8'h20 + i[7:0], 8'h10 + i[7:0]},
            "4: byte-stream word coherent");
    end

    $display("---- Stage 5: snoop-then-read window (permanent-staleness probe) ----");
    for (sb = 1; sb <= 3; sb = sb + 1) begin
      backing[{8'hD0,2'd0}] = 16'h5500;
      cpu_data_read(mkadr(8'hD0,2'd0), rd);
      @(posedge clk);
      snoop_adr <= mkadr(8'hD0,2'd0); snoop_dat_w <= 16'h66AA;
      snoop_bs <= 2'b11; snoop_act <= 1'b1;
      @(posedge clk); snoop_act <= 1'b0;
      for (i = 0; i < sb; i = i + 1) @(posedge clk);
      cpu_data_read(mkadr(8'hD0,2'd0), rd);
      repeat (12) @(posedge clk);
      cpu_data_read(mkadr(8'hD0,2'd0), rd);
      check(rd, 16'h66AA, "5: line coherent after snoop-read race (settled)");
    end

    $display("---- Stage 6: byte-write-during-fill race ----");
    idx_ctr = 8'hE0;
    for (i = 0; i <= 10; i = i + 1) begin
      backing[{idx_ctr[7:0],2'd0}] = 16'h00B0;
      backing[{idx_ctr[7:0],2'd1}] = 16'h00B1;
      backing[{idx_ctr[7:0],2'd2}] = 16'h11B2;
      backing[{idx_ctr[7:0],2'd3}] = 16'h00B3;
      @(posedge clk);
      cpu_adr <= mkadr(idx_ctr[7:0], 2'd0);
      cpu_bs <= 2'b11; cpu_we<=0; cpu_ir<=0; cpu_dr<=1; cpu_cs<=1;
      for (sb = 0; sb < i; sb = sb + 1) @(posedge clk);
      backing[{idx_ctr[7:0],2'd2}] = 16'h99B2;
      snoop_adr <= mkadr(idx_ctr[7:0],2'd2); snoop_dat_w <= 16'h9900;
      snoop_bs <= 2'b10; snoop_act <= 1'b1;
      @(posedge clk); snoop_act <= 1'b0;
      repeat (4) @(posedge clk);
      f = 0; while (!cpu_ack && f < 40) begin @(posedge clk); f = f + 1; end
      @(posedge clk); cpu_cs<=0; cpu_dr<=0;
      repeat (8) @(posedge clk);
      cpu_data_read(mkadr(idx_ctr[7:0],2'd2), rd);
      if (rd !== 16'h99B2) begin
        race_fails = race_fails + 1;
        $display("  [BYTE-RACE off=%0d idx=%02x] STALE: got %04x exp 99B2", i, idx_ctr[7:0], rd);
      end
      idx_ctr = idx_ctr + 1;
    end
    $display("Stage 6 done (byte-write-during-fill).");

    if (errs == 0) $display("RUN: PASS (basic checks)");
    else           $display("RUN: FAIL (%0d basic errors)", errs);
    $finish;
  end

  initial begin
    #500000;
    $display("RUN: FAIL (timeout)");
    errs = errs + 1;
    $finish;
  end

endmodule
