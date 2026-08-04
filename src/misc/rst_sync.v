// synchronizer to generate reset signals for different
// clock domains; additionally we keep everything in reset
// until SDRAM initialization finishes
module rst_sync (
  input wire clk_28m,
  input wire clk_85m,

  input wire pll_lock,
  input wire sdram_ready,

  output wire rst_28m,
  output wire rst_28m_n,

  output wire rst_85m,
  output wire rst_85m_n,

  output wire rst_sdram,
  output wire rst_sdram_n
);

reg [2:0] rst_sync_28m /* synthesis syn_keep=1 */ /* synthesis syn_dont_touch=1 */ /* synthesis syn_preserve=1 */;
reg [2:0] rst_sync_85m /* synthesis syn_keep=1 */ /* synthesis syn_dont_touch=1 */ /* synthesis syn_preserve=1 */;
reg [2:0] rst_sync_sdram /* synthesis syn_keep=1 */ /* synthesis syn_dont_touch=1 */ /* synthesis syn_preserve=1 */;

always @(posedge clk_28m or negedge pll_lock) begin
  if (!pll_lock || !sdram_ready)
    rst_sync_28m <= 3'b000;
  else
    rst_sync_28m <= {rst_sync_28m[1:0], 1'b1};
end

always @(posedge clk_85m or negedge pll_lock) begin
  if (!pll_lock || !sdram_ready)
    rst_sync_85m <= 3'b000;
  else
    rst_sync_85m <= {rst_sync_85m[1:0], 1'b1};
end

always @(posedge clk_85m or negedge pll_lock) begin
  if (!pll_lock)
    rst_sync_sdram <= 3'b000;
  else
    rst_sync_sdram <= {rst_sync_sdram[1:0], 1'b1};
end

assign rst_28m   = ~rst_sync_28m[2];
assign rst_28m_n = rst_sync_28m[2];

assign rst_85m   = ~rst_sync_85m[2];
assign rst_85m_n = rst_sync_85m[2];

assign rst_sdram   = ~rst_sync_sdram[2];
assign rst_sdram_n = rst_sync_sdram[2];

endmodule
// vim:ts=2 sw=2 tw=120 et
