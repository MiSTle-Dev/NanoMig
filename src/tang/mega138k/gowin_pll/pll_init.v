`timescale 1ns/1ns

module PLL_INIT
#(
parameter CLK_PERIOD = 50,
parameter MULTI_FAC  = 30
)
(
input CLKIN,
input I_RST,
input PLLLOCK,
output O_RST,
output [5:0] ICPSEL,
output [2:0] LPFRES,
output O_LOCK

);

localparam WAIT_TIME = 'd2000_000;      
localparam WAIT_CNT = (WAIT_TIME + CLK_PERIOD - 1) / CLK_PERIOD; 
localparam WAIT_WIDTH = $clog2(WAIT_CNT + 1);

reg [WAIT_WIDTH-1:0] waitcnt = 'd0;
reg [3:0] RomAddr = 'd0;
reg [15:0] Rom [15:0];
reg [15:0] RomDreg ='d0;
wire [5:0] Regicp = RomDreg[5:0];
wire [2:0] Regres = RomDreg[10:8];
reg Waitlock = 'd0;
reg [7:0] locksig = 8'b0000_0000;
reg laststep = 1'b0;

wire validsig = RomDreg[12];
reg [1:0]enable_r = 2'b00;

wire Enable = enable_r[1];
always @(posedge CLKIN or posedge I_RST)
begin
    if (I_RST)
        enable_r <= 2'b00;
    else
        begin
            enable_r <= {enable_r[0], 1'b1};
        end
end 

always @(posedge CLKIN or negedge Enable)
begin
    if (Enable == 1'b0)
        begin
            RomDreg <= 16'h0000;
            
            Rom[00] <= 16'h1400;    //1
            Rom[01] <= (MULTI_FAC > 34) ? 16'h1401
                    :  (MULTI_FAC > 16) ? 16'h1400
                    :                     16'h1400;    //2
            Rom[02] <= (MULTI_FAC > 34) ? 16'h1501
                    :  (MULTI_FAC > 16) ? 16'h1500
                    :                     16'h1500;    //3
            Rom[03] <= (MULTI_FAC > 34) ? 16'h1503
                    :  (MULTI_FAC > 16) ? 16'h1501
                    :                     16'h1500;    //4
            Rom[04] <= (MULTI_FAC > 34) ? 16'h1507
                    :  (MULTI_FAC > 16) ? 16'h1503
                    :                     16'h1501;    //5
            Rom[05] <= (MULTI_FAC > 34) ? 16'h0605
                    :  (MULTI_FAC > 16) ? 16'h0602
                    :                     16'h0601;    //6
            Rom[06] <= 16'h0000;    //over
                        
            Rom[07] <= (MULTI_FAC > 34) ? 16'h1402
                    :  (MULTI_FAC > 16) ? 16'h1401
                    :                     16'h1400;    //2.5
            Rom[08] <= (MULTI_FAC > 34) ? 16'h1502
                    :  (MULTI_FAC > 16) ? 16'h1501
                    :                     16'h1500;    //3.5
            Rom[09] <= (MULTI_FAC > 34) ? 16'h1504
                    :  (MULTI_FAC > 16) ? 16'h1502
                    :                     16'h1501;    //4.5
            Rom[10] <= (MULTI_FAC > 34) ? 16'h1603
                    :  (MULTI_FAC > 16) ? 16'h1601
                    :                     16'h1600;    //5.5
            Rom[11] <= 16'h1400;    //1.5
            Rom[12] <= 16'h0000;
            Rom[13] <= 16'h0000;
            Rom[14] <= 16'h0000;
            Rom[15] <= 16'h0000;
        end
    else
        RomDreg <= Rom[RomAddr[3:0]];
end

reg [3:0]RomAddrVld = 'd0;
always @ (*) begin
    casex (locksig[5:0])
        6'b111_111  :   RomAddrVld = 4'd8;
        6'b011_111  :   RomAddrVld = 4'd8;
        6'b111_110  :   RomAddrVld = 4'd8;
        6'b111_10x  :   RomAddrVld = 4'd9;
        6'bx01_111  :   RomAddrVld = 4'd7;
        6'b011_110  :   RomAddrVld = 4'd8;
        6'bxx0_111  :   RomAddrVld = 4'd1;
        6'bx01_110  :   RomAddrVld = 4'd2;
        6'b011_10x  :   RomAddrVld = 4'd3;
        6'b111_0xx  :   RomAddrVld = 4'd4;
                                     
        6'bxxx_011  :   RomAddrVld = 4'd1;
        6'bxx0_110  :   RomAddrVld = 4'd7;
        6'bx01_100  :   RomAddrVld = 4'd8;
        6'b011_000  :   RomAddrVld = 4'd9;
        6'b110_000  :   RomAddrVld = 4'd10;
        6'bxxx_x01  :   RomAddrVld = 4'd0;
        6'bxxx_010  :   RomAddrVld = 4'd1;
        6'bxx0_100  :   RomAddrVld = 4'd2;
        6'bx01_000  :   RomAddrVld = 4'd3;
        6'b010_000  :   RomAddrVld = 4'd4;
        6'b100_000  :   RomAddrVld = 4'd5;
                                     
        6'b000_000  :   RomAddrVld = 4'd8;
                                     
        default     :   RomAddrVld = 4'd8;
    endcase                          
end


reg [3:0]state='d0;
localparam IDLE  = 4'd0;
localparam STATE1 = 4'd1;
localparam STATE2 = 4'd2;
localparam STATE3 = 4'd3;
localparam STATE4 = 4'd4;
localparam STATE5 = 4'd5;
localparam STATE6 = 4'd6;
localparam STATE7 = 4'd7;



always @(posedge CLKIN or negedge Enable)
begin
    if (Enable == 1'b0)
        begin
        state <= IDLE;
        RomAddr<=4'b0000;
        laststep <= 1'b0;
        end
    else
        begin
            case (state)
                IDLE: 
                    begin
                    state<=STATE1;
                    end
                STATE1:
                    begin
                    state<=STATE2;
                    end
                STATE2:
                    begin
                    if (laststep==1'b1)
                        state<=STATE7;
                    else
                        state<=STATE3;
                    end
                STATE3:
                    begin
                    if (Waitlock==1'b1)
                        state<=STATE4;
                    else
                        state<= STATE3;
                    end
                STATE4:
                    begin
                    state<=STATE5;               
                    end
                STATE5:
                    begin
                    if (validsig==1'b1)
                        begin
                            RomAddr <= RomAddr + 1;
                            state <= STATE1;
                        end
                    else if (validsig==1'b0 && laststep==1'b0)
                            state <= STATE6;
                    end
                STATE6:
                    begin
                    RomAddr <= RomAddrVld;
                    laststep <= 1'b1;
                    state <= STATE1;
                    end
                STATE7:
                    begin
                    state<=STATE7;
                    end

                default: state<=IDLE;
            endcase
        end
end

always @(posedge CLKIN)
begin


    Waitlock <= (&waitcnt == 1'b1) ? 1'b1 : 1'b0; 
    
    waitcnt <= (state==STATE3) ? (waitcnt+1) : 'd0;
    
    if (~Enable)    locksig <= 8'b0000_0000;
    else    if (state==STATE4)   locksig[RomAddr[3:0]] <= PLLLOCK;


end

assign ICPSEL = Regicp;
assign LPFRES = Regres;
assign O_RST = (~Enable) || (state==STATE2) ? 1'b1 : 1'b0;
assign O_LOCK = (state==STATE7) ? PLLLOCK : 1'b0;

endmodule



