module amigaclks (
        // System clocks
        input clk_in,
        output clk_7m,
        output clk_28m,
        output clk_85m,
        output clk_sdram,
        output locked,
        // video clocks
        input vidmode,  // 1: 28MHz pixel clock, 0: 56MHz pixel clock (RTG)
        output clk_tmds,
        output clk_pixel,
        output video_locked
);

// Clocks are derived from 50Mhz
// HDMI clock:  141.666 MHz
// Pixel clock: 28.333 MHz (HDMI/5)
// SDRAM and flash clock: 85 MHz
// Amiga clock: 7.08333 (Pixel/4)

// -> The resulting effective Amiga clock slightly below NTSC's 7.15909 and
// close to PAL's 7.09379 Mhz

`define PIXEL_CLOCK 28333333

wire clk_pixel_x5;
wire clk_85m;
wire clk_85m_shifted;
wire pll_lock;
pll_142m pll_hdmi (
    .clkout0(clk_tmds),
    .clkout1(clk_85m),
    .clkout2(clk_sdram),   // 270deg phase shifted
    .init_clk(clk_in),
    .lock(locked),
    .clkin(clk_in)
);

wire clk_pixel;
Gowin_CLKDIV clk_div_5 (
    .hclkin(clk_tmds), // input hclkin
    .resetn(locked),     // input resetn
    .clkout(clk_pixel)     // output clkout
);

assign clk_28m = clk_pixel;   

// WARNING: the following is unsed and thus untested   
// divide clk28m by 4 to get clk_7m
reg [1:0] clk_div;   
always @(posedge clk_28m)
  clk_div <= clk_div + 2'd1;

assign clk_7m = clk_div[1];      
assign video_locked = locked;   
   
endmodule
