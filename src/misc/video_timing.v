//
// video_timing.v
//
// Measures the raw Amiga video timing before the scandoubler, for the 31 kHz
// pass-through (see docs/amiga-31khz-passthrough.md):
//
//   fast      raw line shorter than 1400 clocks, i.e. a 31 kHz mode
//   act_*     picture geometry taken from the Amiga's own blanking:
//             act_start  one clock at the first visible pixel of the frame
//             act_w      width of the display window in clocks
//             act_off    clocks from the end of blanking to the display window
//             act_h      visible lines per frame
//             act_ok     the last frame gave a usable frame start
//
// clk is the 28.37 MHz system clock. hs, vs, hbl, vbl and hde are active low
// for hs/vs and active high for the blanking and display window.
//

module video_timing (
  input  clk,
  input  hs,        // active low
  input  vs,        // active low
  output reg fast,  // raw line is shorter than 1400 clocks: not a 15 kHz mode

  input  hbl,       // horizontal blanking, active high
  input  vbl,       // vertical blanking, active high
  input  hde,       // horizontal display window, active high
  output reg        act_start,
  output reg [10:0] act_w,
  output reg [10:0] act_off,
  output reg [9:0]  act_h,
  output reg        act_ok
);

reg hsD = 1'b1, vsD = 1'b1;

// ---- picture geometry from the blanking ----
reg hblD = 1'b1, vblD = 1'b1;
reg hdeD = 1'b0;
reg [10:0] wcnt = 0, ocnt = 0;
reg [9:0]  lcnt = 0;
reg act_first = 1'b1, act_seen = 1'b0;

always @(posedge clk) begin
  hblD <= hbl;
  vblD <= vbl;
  act_start <= 1'b0;

  // where the display window sits in the line: offset from the end of
  // blanking, and its width. hbl itself is not centred on the picture.
  hdeD <= hde;
  ocnt <= ocnt + 11'd1;
  if(!hbl && hblD) ocnt <= 11'd0;
  if(hde && !hdeD && !vbl) act_off <= ocnt;

  if(hde) wcnt <= wcnt + 11'd1;
  if(!hde && hdeD) begin
    if(!vbl) act_w <= wcnt;
    wcnt <= 11'd0;
  end

  // visible lines, and the first visible pixel of the frame
  if(vbl && !vblD) act_h <= lcnt;
  if(vbl) begin
    lcnt <= 10'd0;
    act_first <= 1'b1;
  end else if(!hbl && hblD) begin
    lcnt <= lcnt + 10'd1;
    if(act_first) begin
      act_start <= 1'b1;
      act_first <= 1'b0;
      act_seen  <= 1'b1;
    end
  end

  // once per frame: did the blanking give a frame start?
  if(!vs && vsD) begin
    act_ok   <= act_seen;
    act_seen <= 1'b0;
  end
end

// ---- line length ----
reg [15:0] hcnt = 0;
reg [15:0] L = 0;

always @(posedge clk) begin
  hsD <= hs;
  vsD <= vs;
  hcnt <= hcnt + 16'd1;

  if(!hs && hsD) begin           // hs falling edge: new line
    L <= hcnt;
    hcnt <= 16'd1;
  end
end

always @(posedge clk) fast <= (L != 16'd0) && (L < 16'd1400);

endmodule
