`timescale  1ns/1ns


module PLL_INIT #
(   parameter       CLK_PERIOD  = 20       
,   parameter       MULTI_FAC   = 24
)
(   input           I_RST
,   input           I_MD_CLK

,   output          O_RST

,   output          O_MD_INC
,   output [1:0]    O_MD_OPC
,   output [7:0]    O_MD_WR_DATA
,   input  [7:0]    I_MD_RD_DATA

,   input           I_LOCK
,   output          O_LOCK

,   input PLL_INIT_BYPASS
,   output [7:0] MDRDO
,   input [1:0] MDOPC
,   input MDAINC
,   input [7:0] MDWDI


);

`ifdef SIM
`define     DL     #1
`else
`define     DL
`endif

`ifdef  SIM
localparam  WAIT_TIME   = 'd8_000;
localparam  LOCK_TIME   = 'd2_000;
`else
localparam  WAIT_TIME   = 'd800_000;
localparam  LOCK_TIME   = 'd200_000;
`endif
localparam  WAIT_CNT    = (WAIT_TIME + CLK_PERIOD - 1) / CLK_PERIOD;    //! 1ms
localparam  LOCK_CNT    = (LOCK_TIME + CLK_PERIOD - 1) / CLK_PERIOD;
localparam  WW          = $clog2(WAIT_CNT + 1);
localparam  LW          = $clog2(LOCK_CNT + 1);

localparam  INIT_STEP_0 = 4'd0
,           INIT_STEP_1 = 4'd1
,           INIT_STEP_2 = 4'd2
,           INIT_STEP_3 = 4'd3
,           INIT_STEP_4 = 4'd4
,           INIT_STEP_5 = 4'd5
,           INIT_STEP_6 = 4'd6
,           INIT_STEP_7 = 4'd7
,           INIT_STEP_8 = 4'd8
,           INIT_STEP_9 = 4'd9
;

reg  [   1:0]   rEnable     = 'b0;

reg             rRomRd      = 'b0;
reg  [   7:0]   rRomAddr    = 'b0;
reg  [  24:0]   rRomData    = 'b0;

reg  [   2:0]   rReqCnt     = 'b0;
reg  [   4:0]   rLoopCnt    = 'b0;

reg  [   3:0]   rChkOkCnt   = 'b0;
reg  [   5:0]   rChkStart   = 'b0;

reg  [   3:0]   rInitFsmC   = INIT_STEP_0   ;
reg  [   3:0]   rInitFsmN   = INIT_STEP_1   ;

reg  [   7:0]   rMdAddr     = 'b0;

reg             rMdInc      = 'b0;
reg  [   1:0]   rMdOpc      = 'b0;
reg  [   7:0]   rMdDOut     = 'b0;

reg  [   7:0]   rChkFlag    = 'b0;

reg             rLockReg    = 'b0;
reg  [LW-1:0]   rLockCnt    = 'b0;
reg             rLocked     = 'b0;
reg  [WW-1:0]   rWaitCnt    = 'b0;

reg             rLastStep   = 'b0;

reg             rLockOut    = 'b0;

reg             rChkVld     = 'b0;
reg  [   7:0]   rRomAddrVld = 'b0;

reg             rRstOut     = 1'b1;

wire            wEnable     = rEnable[1];
wire [   7:0]   wMdAddrNext = rMdAddr + 2'd1;
wire            wLocked     = (rLockCnt >= LOCK_CNT);

wire            wIsStep0    = (rInitFsmC == INIT_STEP_0);
wire            wIsStep1    = (rInitFsmC == INIT_STEP_1);
wire            wIsStep2    = (rInitFsmC == INIT_STEP_2);
wire            wIsStep3    = (rInitFsmC == INIT_STEP_3);
wire            wIsStep4    = (rInitFsmC == INIT_STEP_4);
wire            wIsStep5    = (rInitFsmC == INIT_STEP_5);
wire            wIsStep6    = (rInitFsmC == INIT_STEP_6);
wire            wIsStep7    = (rInitFsmC == INIT_STEP_7);
wire            wIsStep8    = (rInitFsmC == INIT_STEP_8);
wire            wIsStep9    = (rInitFsmC == INIT_STEP_9);

wire            wReqOver    = ~rRomData[24];
wire            wMdrpReq    = rRomData[24];
wire            wWaitLock   = rReqCnt[2];//(rReqCnt == 4);


wire [   7:0]   wReqAddr    = rRomData[16+:8];
wire [   7:0]   wReqMask    = rRomData[ 8+:8];
wire [   7:0]   wReqData    = rRomData[ 0+:8];


localparam  ROM_FILE = "";

reg  [  27:0]   rRomDReg    = 'b0;


reg    [27:0]  rRom    [63:0];


always @ (posedge PLL_INIT_BYPASS or posedge I_MD_CLK or posedge I_RST) begin
    if (PLL_INIT_BYPASS || I_RST)  rEnable <=`DL 2'b00;
    else        rEnable <=`DL {rEnable[0], 1'b1};
end

generate
if (ROM_FILE != "") begin: ram_init_file
    initial begin
        $readmemh (ROM_FILE, rRom);
    end

    always @ (posedge I_MD_CLK) begin
        rRomDReg    <=`DL rRom[rRomAddr[5:0]];
    end
end else begin : ram_init
    always @ (posedge I_MD_CLK) begin
        if (~rEnable[1]) begin
            rRomDReg    <=`DL 28'h000_0000;
//1
            rRom[00]    <=`DL (MULTI_FAC > 34)  ? 28'h10B_3F03
                         :    (MULTI_FAC > 16)  ? 28'h10B_3F01
                         :                        28'h10B_3F00;
            rRom[01]    <=`DL 28'h10C_E080;
            rRom[02]    <=`DL 28'h111_0701;
            rRom[03]    <=`DL 28'h112_0C08;
//2
            rRom[04]    <=`DL (MULTI_FAC > 34)  ? 28'h10B_3F03
                         :    (MULTI_FAC > 16)  ? 28'h10B_3F01
                         :                        28'h10B_3F00;
            rRom[05]    <=`DL 28'h10C_E080;
            rRom[06]    <=`DL 28'h111_0703;
            rRom[07]    <=`DL 28'h112_0C08;
//3
            rRom[08]    <=`DL (MULTI_FAC > 34)  ? 28'h10B_3F03
                         :    (MULTI_FAC > 16)  ? 28'h10B_3F01
                         :                        28'h10B_3F00;
            rRom[09]    <=`DL 28'h10C_E0A0;
            rRom[10]    <=`DL 28'h111_0703;
            rRom[11]    <=`DL 28'h112_0C08;
//4
            rRom[12]    <=`DL (MULTI_FAC > 34)  ? 28'h10B_3F03
                         :    (MULTI_FAC > 16)  ? 28'h10B_3F01
                         :                        28'h10B_3F00;
            rRom[13]    <=`DL 28'h10C_E0A0;
            rRom[14]    <=`DL 28'h111_0707;
            rRom[15]    <=`DL 28'h112_0C08;
//5
            rRom[16]    <=`DL (MULTI_FAC > 34)  ? 28'h10B_3F07
                         :    (MULTI_FAC > 16)  ? 28'h10B_3F03
                         :                        28'h10B_3F01;
            rRom[17]    <=`DL 28'h10C_E0A0;
            rRom[18]    <=`DL 28'h111_0707;
            rRom[19]    <=`DL 28'h112_0C08;
//6
            rRom[20]    <=`DL (MULTI_FAC > 34)  ? 28'h10B_3F05
                         :    (MULTI_FAC > 16)  ? 28'h10B_3F02
                         :                        28'h10B_3F01;
            rRom[21]    <=`DL 28'h10C_E0C0;
            rRom[22]    <=`DL 28'h111_0707;
            rRom[23]    <=`DL 28'h112_0C08;
//over
            rRom[24]    <=`DL 28'h000_0000;
            rRom[25]    <=`DL 28'h000_0000;
            rRom[26]    <=`DL 28'h000_0000;
            rRom[27]    <=`DL 28'h000_0000;
//1.5
            rRom[28]    <=`DL (MULTI_FAC > 34)  ? 28'h10B3F03
                         :    (MULTI_FAC > 16)  ? 28'h10B3F01
                         :                        28'h10B3F00;
            rRom[29]    <=`DL 28'h10CE080;
            rRom[30]    <=`DL 28'h1110702;
            rRom[31]    <=`DL 28'h1120C08;
//2.5
            rRom[32]    <=`DL (MULTI_FAC > 34)  ? 28'h10B3F05
                         :    (MULTI_FAC > 16)  ? 28'h10B3F02
                         :                        28'h10B3F00;
            rRom[33]    <=`DL 28'h10CE080;
            rRom[34]    <=`DL 28'h1110703;
            rRom[35]    <=`DL 28'h1120C08;
//3.5
            rRom[36]    <=`DL (MULTI_FAC > 34)  ? 28'h10B3F03
                         :    (MULTI_FAC > 16)  ? 28'h10B3F01
                         :                        28'h10B3F00;
            rRom[37]    <=`DL 28'h10CE0A0;
            rRom[38]    <=`DL 28'h1110704;
            rRom[39]    <=`DL 28'h112_0C08;

//4.5
            rRom[40]    <=`DL (MULTI_FAC > 34)  ? 28'h10B3F04
                         :    (MULTI_FAC > 16)  ? 28'h10B3F02
                         :                        28'h10B3F00;
            rRom[41]    <=`DL 28'h10CE0A0;
            rRom[42]    <=`DL 28'h1110707;
            rRom[43]    <=`DL 28'h1120C08;

//5.5
            rRom[44]    <=`DL (MULTI_FAC > 34)  ? 28'h10B3F03
                         :    (MULTI_FAC > 16)  ? 28'h10B3F01
                         :                        28'h10B3F00;
            rRom[45]    <=`DL 28'h10CE0C0;
            rRom[46]    <=`DL 28'h1110707;
            rRom[47]    <=`DL 28'h1120C08;

            rRom[48]    <=`DL 28'h000_0000;
            rRom[49]    <=`DL 28'h000_0000;
            rRom[50]    <=`DL 28'h000_0000;
            rRom[51]    <=`DL 28'h000_0000;
            rRom[52]    <=`DL 28'h000_0000;
            rRom[53]    <=`DL 28'h000_0000;
            rRom[54]    <=`DL 28'h000_0000;
            rRom[55]    <=`DL 28'h000_0000;
            rRom[56]    <=`DL 28'h000_0000;
            rRom[57]    <=`DL 28'h000_0000;
            rRom[58]    <=`DL 28'h000_0000;
            rRom[59]    <=`DL 28'h000_0000;
            rRom[60]    <=`DL 28'h000_0000;
            rRom[61]    <=`DL 28'h000_0000;
            rRom[62]    <=`DL 28'h000_0000;
            rRom[63]    <=`DL 28'h000_0000;


        end else
            rRomDReg    <=`DL rRom[rRomAddr[5:0]];
    end
end
endgenerate


always @ (*) begin
    casex (rChkFlag[5:0])
        6'b111_111  :   {rChkVld, rRomAddrVld} = 9'b1_0000_1000;
        6'b011_111  :   {rChkVld, rRomAddrVld} = 9'b1_0000_1000;
        6'b111_110  :   {rChkVld, rRomAddrVld} = 9'b1_0000_1100;
        6'b111_10x  :   {rChkVld, rRomAddrVld} = 9'b1_0000_1100;
        6'bx01_111  :   {rChkVld, rRomAddrVld} = 9'b1_0000_0100;
        6'b011_110  :   {rChkVld, rRomAddrVld} = 9'b1_0000_1000;
        6'bxx0_111  :   {rChkVld, rRomAddrVld} = 9'b1_0000_0100;
        6'bx01_110  :   {rChkVld, rRomAddrVld} = 9'b1_0000_1000;
        6'b011_10x  :   {rChkVld, rRomAddrVld} = 9'b1_0000_1100;
        6'b111_0xx  :   {rChkVld, rRomAddrVld} = 9'b1_0001_0000;

        6'bxxx_011  :   {rChkVld, rRomAddrVld} = 9'b1_0001_1100;
        6'bxx0_110  :   {rChkVld, rRomAddrVld} = 9'b1_0010_0000;
        6'bx01_100  :   {rChkVld, rRomAddrVld} = 9'b1_0010_0100;
        6'b011_000  :   {rChkVld, rRomAddrVld} = 9'b1_0010_1000;
        6'b110_000  :   {rChkVld, rRomAddrVld} = 9'b1_0010_1100;
        6'bxxx_x01  :   {rChkVld, rRomAddrVld} = 9'b1_0000_0000;
        6'bxxx_010  :   {rChkVld, rRomAddrVld} = 9'b1_0000_0100;
        6'bxx0_100  :   {rChkVld, rRomAddrVld} = 9'b1_0000_1000;
        6'bx01_000  :   {rChkVld, rRomAddrVld} = 9'b1_0000_1100;
        6'b010_000  :   {rChkVld, rRomAddrVld} = 9'b1_0001_0000;
        6'b100_000  :   {rChkVld, rRomAddrVld} = 9'b1_0001_0100;

        6'b000_000  :   {rChkVld, rRomAddrVld} = 9'b0_0000_0000;

        default     :   {rChkVld, rRomAddrVld} = 9'b0_0000_0000;
    endcase
end

always @ (posedge I_MD_CLK) begin
    rInitFsmC   <=`DL wEnable   ? rInitFsmN : INIT_STEP_0;
//!_____________________________________________________________________________
    rRomRd      <=`DL wEnable & (wIsStep1 | wIsStep6 & ~wWaitLock);
//!_____________________________________________________________________________
    rRomData    <=`DL rRomRd    ? rRomDReg[24:0] : rRomData;
//!_____________________________________________________________________________
    rRomAddr    <=`DL ~wEnable              ? 8'd0
                 :    (wIsStep3 & wReqOver) ? rRomAddrVld
                 :    rRomRd                ? rRomAddr + 1'd1
                 :                            rRomAddr;
//!_____________________________________________________________________________
    rLastStep   <=`DL wEnable & (wIsStep3 & wReqOver | rLastStep);
//!_____________________________________________________________________________
    rReqCnt     <=`DL ~wEnable              ? 3'd0
                 :    wIsStep7              ? 3'd0
                 :    wIsStep5              ? rReqCnt + 1'd1
                 :                            rReqCnt;
//!_____________________________________________________________________________
    rLoopCnt    <=`DL ~wEnable              ? 3'd0
                 :    wIsStep8              ? rLoopCnt + 1'd1
                 :                            rLoopCnt;
//!_____________________________________________________________________________
    rLockReg    <=`DL wEnable & I_LOCK;
//!_____________________________________________________________________________
    rLockCnt    <=`DL (~wEnable)            ? {LW{1'b0}}
                 :    (~wIsStep7&~wIsStep9) ? {LW{1'b0}}
                 :    (~rLockReg)           ? {LW{1'b0}}
                 :    (rLockCnt<LOCK_CNT)   ? rLockCnt + 1'd1
                 :                            rLockCnt;
//!_____________________________________________________________________________
    rLocked     <=`DL wLocked;
//!_____________________________________________________________________________
    rWaitCnt    <=`DL wIsStep3              ? WAIT_CNT[0+:WW]
                :     ~wIsStep7             ? rWaitCnt
                :     (|rWaitCnt)           ? rWaitCnt - 1'd1
                :                             {WW{1'b0}};
//!_____________________________________________________________________________
    if (~wEnable)                   rChkFlag                <=`DL 8'h00;
    else if (wIsStep7 & rLocked)    rChkFlag[rLoopCnt[2:0]] <=`DL 1'b1;
//!_____________________________________________________________________________
    rChkOkCnt   <=`DL ~wEnable              ? 4'd0
                 :    ~wIsStep7             ? rChkOkCnt
                 :    (rWaitCnt==0)         ? 4'd0
                 :    rLocked               ? rChkOkCnt + 1'd1
                 :                            rChkOkCnt;
end

always @(*) begin
    if (~wEnable)   rInitFsmN   =`DL INIT_STEP_1;
    else case (rInitFsmC) /* synthesis full_case */
        INIT_STEP_0 : rInitFsmN =`DL INIT_STEP_1;
        INIT_STEP_1 : rInitFsmN =`DL INIT_STEP_2;
        INIT_STEP_2 : rInitFsmN =`DL INIT_STEP_3;
        INIT_STEP_3 : rInitFsmN =`DL wWaitLock             ? INIT_STEP_7
                                : wReqOver & rLastStep  ? INIT_STEP_9
                                : wReqOver &~rLastStep  ? INIT_STEP_1
                                : (rMdAddr >= wReqAddr) ? INIT_STEP_4
                                :                         INIT_STEP_3;
        INIT_STEP_4 : rInitFsmN =`DL INIT_STEP_5;
        INIT_STEP_5 : rInitFsmN =`DL INIT_STEP_6;
        INIT_STEP_6 : rInitFsmN =`DL INIT_STEP_2;
        INIT_STEP_7 : rInitFsmN =`DL (rWaitCnt==0)         ? INIT_STEP_8
                                : ~rLocked              ? INIT_STEP_7
                                : rLastStep             ? INIT_STEP_9
                                :                         INIT_STEP_8;
        INIT_STEP_8 : rInitFsmN =`DL ~rLastStep            ? INIT_STEP_1
                                : rChkVld               ? INIT_STEP_1
                                :                         INIT_STEP_9;
        INIT_STEP_9 : rInitFsmN =`DL INIT_STEP_9;
        default     : rInitFsmN =`DL INIT_STEP_9;
    endcase
end

always @ (posedge I_MD_CLK) begin
    rMdOpc      <=`DL ~wEnable  ? 2'b00
                 :    wIsStep7  ? 2'b00
                 :    wIsStep5  ? 2'b01
                 :                2'b10;
//!_____________________________________________________________________________
    rMdInc      <=`DL wIsStep3 & (~rMdInc ? (rMdAddr<wReqAddr)
                                 :          (wMdAddrNext < wReqAddr)); 
//!_____________________________________________________________________________
    rMdAddr     <=`DL ~wEnable  ? 8'd0
                 :    wIsStep7  ? 8'd0
                 :    rMdInc    ? wMdAddrNext
                 :                rMdAddr;
//!_____________________________________________________________________________
    rMdDOut     <=`DL wIsStep5  ? (I_MD_RD_DATA&~wReqMask|wReqData) : rMdDOut;
//!_____________________________________________________________________________
     rRstOut     <=`DL ~wEnable | (~wIsStep7 & ~wIsStep9);
//!_____________________________________________________________________________
    rLockOut    <=`DL rLocked & wIsStep9 & rChkVld;
end


/////////////mdrp switch//////////////////////////
assign  O_LOCK      = (PLL_INIT_BYPASS == 1'b1) ? I_LOCK : rLockOut;
assign  O_RST       = (PLL_INIT_BYPASS == 1'b1) ? I_RST : rRstOut;
assign  O_MD_INC    = (PLL_INIT_BYPASS == 1'b1) ? MDAINC : rMdInc;
assign  O_MD_OPC    = (PLL_INIT_BYPASS == 1'b1) ? MDOPC : rMdOpc;
assign  O_MD_WR_DATA= (PLL_INIT_BYPASS == 1'b1) ? MDWDI : rMdDOut;
assign  MDRDO       = (PLL_INIT_BYPASS == 1'b1) ? I_MD_RD_DATA : 8'b0000_0000;


/////////////////////////////////////

endmodule//: PLL_INIT


