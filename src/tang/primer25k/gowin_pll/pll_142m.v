module pll_142m(
    clkin,
    clkout0,
    clkout1,
    clkout2,
    lock,
    mdclk
);


input clkin;
output clkout0;
output clkout1;
output clkout2;
output lock;
input mdclk;
wire [7:0] mdrdo;
wire [1:0] wMdOpc;
wire wMdAInc;
wire [7:0] wMdDIn;
wire [7:0] wMdQOut;
wire pll_lock;
wire pll_rst;


    pll_142m_MOD u_pll(
        .clkout1(clkout1),
        .clkout2(clkout2),
        .clkout0(clkout0),
        .lock(pll_lock),
        .mdrdo(wMdQOut),
        .clkin(clkin),
        .reset(pll_rst),
        .mdclk(mdclk),
        .mdopc(wMdOpc),
        .mdainc(wMdAInc),
        .mdwdi(wMdDIn)
    );


    PLL_INIT u_pll_init(
        .I_RST(1'b0),
        .O_RST(pll_rst),
        .I_LOCK(pll_lock),
        .O_LOCK(lock),
        .I_MD_CLK(mdclk),
        .O_MD_INC(wMdAInc),
        .O_MD_OPC(wMdOpc),
        .O_MD_WR_DATA(wMdDIn),
        .I_MD_RD_DATA(wMdQOut),
        .PLL_INIT_BYPASS(1'b0),
        .MDRDO(mdrdo),
        .MDOPC(2'b00),
        .MDAINC(1'b0),
        .MDWDI(8'h0)
    );
    defparam u_pll_init.CLK_PERIOD = 20;
    defparam u_pll_init.MULTI_FAC = 53;


endmodule
