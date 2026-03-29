//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.12.02
//IP Version: 1.0
//Part Number: GW3A-LV20LQ144C1/I0
//Device: GW3A-20
//Device Version: A
//Created Time: Sun Mar 29 17:28:11 2026

module pll_142m (lock, clkout0, clkout1, clkout2, clkin);

output lock;
output clkout0;
output clkout1;
output clkout2;
input clkin;

wire clkout3;
wire clkout4;
wire clkout5;
wire clkout6;
wire clkfbout;
wire [7:0] mdrdo;
wire gw_vcc;
wire gw_gnd;

assign gw_vcc = 1'b1;
assign gw_gnd = 1'b0;

PLLB PLLB_inst (
    .LOCK(lock),
    .CLKOUT0(clkout0),
    .CLKOUT1(clkout1),
    .CLKOUT2(clkout2),
    .CLKOUT3(clkout3),
    .CLKOUT4(clkout4),
    .CLKOUT5(clkout5),
    .CLKOUT6(clkout6),
    .CLKFBOUT(clkfbout),
    .MDRDO(mdrdo),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .RESET(gw_gnd),
    .PLLPWD(gw_gnd),
    .RESET_I(gw_gnd),
    .RESET_O(gw_gnd),
    .PSSEL({gw_gnd,gw_gnd,gw_gnd}),
    .PSDIR(gw_gnd),
    .PSPULSE(gw_gnd),
    .ENCLK0(gw_vcc),
    .ENCLK1(gw_vcc),
    .ENCLK2(gw_vcc),
    .ENCLK3(gw_vcc),
    .ENCLK4(gw_vcc),
    .ENCLK5(gw_vcc),
    .ENCLK6(gw_vcc),
    .SSCPOL(gw_gnd),
    .SSCON(gw_gnd),
    .SSCMDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .SSCMDSEL_FRAC({gw_gnd,gw_gnd,gw_gnd}),
    .MDCLK(gw_gnd),
    .MDOPC({gw_gnd,gw_gnd}),
    .MDAINC(gw_gnd),
    .MDWDI({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DISMDRP(gw_vcc)
);

defparam PLLB_inst.FCLKIN = "50";
defparam PLLB_inst.IDIV_SEL = 1;
defparam PLLB_inst.FBDIV_SEL = 1;
defparam PLLB_inst.ODIV0_SEL = 6;
defparam PLLB_inst.ODIV1_SEL = 10;
defparam PLLB_inst.ODIV2_SEL = 10;
defparam PLLB_inst.ODIV3_SEL = 8;
defparam PLLB_inst.ODIV4_SEL = 8;
defparam PLLB_inst.ODIV5_SEL = 8;
defparam PLLB_inst.ODIV6_SEL = 8;
defparam PLLB_inst.MDIV_SEL = 17;
defparam PLLB_inst.MDIV_FRAC_SEL = 0;
defparam PLLB_inst.ODIV0_FRAC_SEL = 0;
defparam PLLB_inst.CLKOUT0_EN = "TRUE";
defparam PLLB_inst.CLKOUT1_EN = "TRUE";
defparam PLLB_inst.CLKOUT2_EN = "TRUE";
defparam PLLB_inst.CLKOUT3_EN = "FALSE";
defparam PLLB_inst.CLKOUT4_EN = "FALSE";
defparam PLLB_inst.CLKOUT5_EN = "FALSE";
defparam PLLB_inst.CLKOUT6_EN = "FALSE";
defparam PLLB_inst.CLKFB_SEL = "INTERNAL";
defparam PLLB_inst.CLKOUT0_DT_DIR = 1'b1;
defparam PLLB_inst.CLKOUT1_DT_DIR = 1'b1;
defparam PLLB_inst.CLKOUT2_DT_DIR = 1'b1;
defparam PLLB_inst.CLKOUT3_DT_DIR = 1'b1;
defparam PLLB_inst.CLKOUT0_DT_STEP = 0;
defparam PLLB_inst.CLKOUT1_DT_STEP = 0;
defparam PLLB_inst.CLKOUT2_DT_STEP = 0;
defparam PLLB_inst.CLKOUT3_DT_STEP = 0;
defparam PLLB_inst.CLK0_IN_SEL = 1'b0;
defparam PLLB_inst.CLK0_OUT_SEL = 1'b0;
defparam PLLB_inst.CLK1_IN_SEL = 1'b0;
defparam PLLB_inst.CLK1_OUT_SEL = 1'b0;
defparam PLLB_inst.CLK2_IN_SEL = 1'b0;
defparam PLLB_inst.CLK2_OUT_SEL = 1'b0;
defparam PLLB_inst.CLK3_IN_SEL = 1'b0;
defparam PLLB_inst.CLK3_OUT_SEL = 1'b0;
defparam PLLB_inst.CLK4_IN_SEL = 2'b00;
defparam PLLB_inst.CLK4_OUT_SEL = 1'b0;
defparam PLLB_inst.CLK5_IN_SEL = 1'b0;
defparam PLLB_inst.CLK5_OUT_SEL = 1'b0;
defparam PLLB_inst.CLK6_IN_SEL = 1'b0;
defparam PLLB_inst.CLK6_OUT_SEL = 1'b0;
defparam PLLB_inst.DYN_DPA_EN = "FALSE";
defparam PLLB_inst.CLKOUT0_PE_COARSE = 0;
defparam PLLB_inst.CLKOUT0_PE_FINE = 0;
defparam PLLB_inst.CLKOUT1_PE_COARSE = 0;
defparam PLLB_inst.CLKOUT1_PE_FINE = 0;
defparam PLLB_inst.CLKOUT2_PE_COARSE = 7;
defparam PLLB_inst.CLKOUT2_PE_FINE = 4;
defparam PLLB_inst.CLKOUT3_PE_COARSE = 0;
defparam PLLB_inst.CLKOUT3_PE_FINE = 0;
defparam PLLB_inst.CLKOUT4_PE_COARSE = 0;
defparam PLLB_inst.CLKOUT4_PE_FINE = 0;
defparam PLLB_inst.CLKOUT5_PE_COARSE = 0;
defparam PLLB_inst.CLKOUT5_PE_FINE = 0;
defparam PLLB_inst.CLKOUT6_PE_COARSE = 0;
defparam PLLB_inst.CLKOUT6_PE_FINE = 0;
defparam PLLB_inst.DYN_PE0_SEL = "FALSE";
defparam PLLB_inst.DYN_PE1_SEL = "FALSE";
defparam PLLB_inst.DYN_PE2_SEL = "FALSE";
defparam PLLB_inst.DYN_PE3_SEL = "FALSE";
defparam PLLB_inst.DYN_PE4_SEL = "FALSE";
defparam PLLB_inst.DYN_PE5_SEL = "FALSE";
defparam PLLB_inst.DYN_PE6_SEL = "FALSE";
defparam PLLB_inst.DE0_EN = "FALSE";
defparam PLLB_inst.DE1_EN = "FALSE";
defparam PLLB_inst.DE2_EN = "FALSE";
defparam PLLB_inst.DE3_EN = "FALSE";
defparam PLLB_inst.DE4_EN = "FALSE";
defparam PLLB_inst.DE5_EN = "FALSE";
defparam PLLB_inst.DE6_EN = "FALSE";
defparam PLLB_inst.RESET_I_EN = "FALSE";
defparam PLLB_inst.RESET_O_EN = "FALSE";
defparam PLLB_inst.ICP_SEL = 6'bXXXXXX;
defparam PLLB_inst.LPF_RES = 3'b100;
defparam PLLB_inst.LPF_CAP = 2'b00;
defparam PLLB_inst.SSC_EN = "FALSE";
defparam PLLB_inst.BAND_WIDTH = "LOW";

endmodule //pll_142m
