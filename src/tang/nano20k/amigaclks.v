module amigaclks (
	// System clocks
	input clk_in,
	output clk_7m,
	output clk_28m,
	output clk_85m,
	output clk_sdram,
	output locked,
	// video clocks
	input vidmode,	// 1: 28MHz pixel clock, 0: 56MHz pixel clock (RTG)
	output clk_tmds,
	output clk_pixel,
	output video_locked
);


// Video clocks
wire clk_28_i;

assign clk_28m = clk_28_i;

rPLL sysclk_inst (
    .CLKOUT(clk_85m),
    .LOCK(locked),
    .CLKOUTP(clk_sdram),
    .CLKOUTD(clk_7m),
    .CLKOUTD3(clk_28_i),
    .RESET(1'b0),
    .RESET_P(1'b0),
    .CLKIN(clk_in),
    .CLKFB(1'b0),
    .FBDSEL(6'b0000000),
    .IDSEL(6'b0000000),
    .ODSEL(6'b0000000),
    .PSDA(4'b0000),
    .DUTYDA(4'b0000),
    .FDLY(4'b0000)
);

defparam sysclk_inst.FCLKIN = "27";
defparam sysclk_inst.DYN_IDIV_SEL = "false";
defparam sysclk_inst.IDIV_SEL = 5;
defparam sysclk_inst.DYN_FBDIV_SEL = "false";
defparam sysclk_inst.FBDIV_SEL = 18;
defparam sysclk_inst.DYN_ODIV_SEL = "false";
defparam sysclk_inst.ODIV_SEL = 8;
defparam sysclk_inst.PSDA_SEL = "1100";
defparam sysclk_inst.DYN_DA_EN = "false";
defparam sysclk_inst.DUTYDA_SEL = "1000";
defparam sysclk_inst.CLKOUT_FT_DIR = 1'b1;
defparam sysclk_inst.CLKOUTP_FT_DIR = 1'b1;
defparam sysclk_inst.CLKOUT_DLY_STEP = 0;
defparam sysclk_inst.CLKOUTP_DLY_STEP = 0;
defparam sysclk_inst.CLKFB_SEL = "internal";
defparam sysclk_inst.CLKOUT_BYPASS = "false";
defparam sysclk_inst.CLKOUTP_BYPASS = "false";
defparam sysclk_inst.CLKOUTD_BYPASS = "false";
defparam sysclk_inst.DYN_SDIV_SEL = 12;
defparam sysclk_inst.CLKOUTD_SRC = "CLKOUT";
defparam sysclk_inst.CLKOUTD3_SRC = "CLKOUT";
defparam sysclk_inst.DEVICE = "GW2AR-18C";


wire [5:0] fbdsel;
wire [5:0] odsel;

assign fbdsel = vidmode ? 6'b111011 : 6'b110110;
assign odsel = vidmode ? 6'b111110 : 6'b111111;

wire clk_tmds_i;

assign clk_tmds = clk_tmds_i;

CLKDIV clkdiv_inst (
    .CLKOUT(clk_pixel),
    .HCLKIN(clk_tmds_i),
    .RESETN(1'b1),
    .CALIB(1'b0)
);

defparam clkdiv_inst.DIV_MODE = "5";
defparam clkdiv_inst.GSREN = "false";

rPLL tmdsclk_inst (
    .CLKOUT(clk_tmds_i),
    .LOCK(video_locked),
    .CLKOUTP(),
    .CLKOUTD(),
    .CLKOUTD3(),
    .RESET(1'b0),
    .RESET_P(1'b0),
    .CLKIN(clk_28_i),
    .CLKFB(1'b0),
    .FBDSEL(fbdsel),
    .IDSEL(6'b0000000),
    .ODSEL(odsel),
    .PSDA(4'b0000),
    .DUTYDA(4'b0000),
    .FDLY(4'b0000)
);

defparam tmdsclk_inst.FCLKIN = "28.5";
defparam tmdsclk_inst.DYN_IDIV_SEL = "false";
defparam tmdsclk_inst.IDIV_SEL = 0;
defparam tmdsclk_inst.DYN_FBDIV_SEL = "true";
defparam tmdsclk_inst.FBDIV_SEL = 4;
defparam tmdsclk_inst.DYN_ODIV_SEL = "true";
defparam tmdsclk_inst.ODIV_SEL = 4;
defparam tmdsclk_inst.PSDA_SEL = "0000";
defparam tmdsclk_inst.DYN_DA_EN = "true";
defparam tmdsclk_inst.DUTYDA_SEL = "1000";
defparam tmdsclk_inst.CLKOUT_FT_DIR = 1'b1;
defparam tmdsclk_inst.CLKOUTP_FT_DIR = 1'b1;
defparam tmdsclk_inst.CLKOUT_DLY_STEP = 0;
defparam tmdsclk_inst.CLKOUTP_DLY_STEP = 0;
defparam tmdsclk_inst.CLKFB_SEL = "internal";
defparam tmdsclk_inst.CLKOUT_BYPASS = "false";
defparam tmdsclk_inst.CLKOUTP_BYPASS = "false";
defparam tmdsclk_inst.CLKOUTD_BYPASS = "false";
defparam tmdsclk_inst.DYN_SDIV_SEL = 2;
defparam tmdsclk_inst.CLKOUTD_SRC = "CLKOUT";
defparam tmdsclk_inst.CLKOUTD3_SRC = "CLKOUT";
defparam tmdsclk_inst.DEVICE = "GW2AR-18C";

endmodule

