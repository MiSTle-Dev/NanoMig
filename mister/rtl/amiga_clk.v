/* amiga_clk.v */
/* 2012, rok.krajnc@gmail.com */

module amiga_clk
(
  input        clk_28,     // 28MHz output clock ( 28.375160MHz)
  output       clk7_en,    // 7MHz output clock enable (on 28MHz clock domain)
  output       clk7n_en,   // 7MHz negedge output clock enable (on 28MHz clock domain)
  output reg   c1,         // clk28m clock domain signal synchronous with clk signal
  output reg   c3,         // clk28m clock domain signal synchronous with clk signal delayed by 90 degrees
  output reg   cck,        // colour clock output (3.54 MHz)
  output [9:0] eclk,       // 0.709379 MHz clock enable output (clk domain pulse)
  input        reset_n
);

//// generated clocks ////

// 7MHz
reg [1:0] clk7_cnt = 2'b10;
reg       clk7_en_reg = 1'b1;
reg       clk7n_en_reg = 1'b1;
reg [9:0] shifter;
always @ (posedge clk_28, negedge reset_n) begin
	if (!reset_n) begin
		clk7_cnt     <= 2'b10;
		clk7_en_reg  <= 1'b1;
		clk7n_en_reg <= 1'b1;
		cck          <= 1;
		shifter      <= 1;
	end else begin
		clk7_cnt     <= clk7_cnt + 2'b01;
		clk7_en_reg  <= (clk7_cnt == 2'b00);
		clk7n_en_reg <= (clk7_cnt == 2'b10);
		if(clk7_cnt == 2'b01) begin
			cck <= ~cck;
			shifter <= {shifter[8:0],shifter[9]};
			if(!shifter) shifter <= 1;
		end
	end
end

wire   clk_7 = clk7_cnt[1];
assign clk7_en = clk7_en_reg;
assign clk7n_en = clk7n_en_reg;

// amiga clocks & clock enables
//            __    __    __    __    __
// clk_28  __/  \__/  \__/  \__/  \__/  
//            ___________             __
// clk_7   __/           \___________/  
//            ___________             __
// c1      __/           \___________/   <- clk28m domain
//                  ___________
// c3      ________/           \________ <- clk28m domain
//

// clk_28 clock domain signal synchronous with clk signal delayed by 90 degrees
always @(posedge clk_28) c3 <= clk_7;

// clk28m clock domain signal synchronous with clk signal
always @(posedge clk_28) c1 <= ~c3;

// 0.709379 MHz clock enable output (clk domain pulse)
assign eclk = shifter;

endmodule
