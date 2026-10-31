module sprite_ram (
  // Port write
  input  wire        clk,
  input  wire        wea,
  input  wire  [3:0] addra,
  input  wire [15:0] dina,

  // Port read
  input  wire  [2:0] addrb,
  output wire [31:0] doutb
);

`ifndef SPRITE_SSRAM
SDPB sdpb_inst (
  .DO(doutb),
  .DI({16'h0000, dina}),
  .BLKSELA(3'b000),
  .BLKSELB(3'b000),
  .ADA({6'b000000, addra, 2'b00, 2'b11}),
  .ADB({6'b000000, addrb, 5'b00000}),
  .CLKA(clk),
  .CLKB(clk),
  .CEA(wea),
  .CEB(1'b1),
  .OCE(1'b0),
  .RESETA(1'b0),
  .RESETB(1'b0)
);
defparam sdpb_inst.BIT_WIDTH_0 = 16;
defparam sdpb_inst.BIT_WIDTH_1 = 32;
defparam sdpb_inst.READ_MODE = 1'b0;
defparam sdpb_inst.RESET_MODE = "SYNC";
defparam sdpb_inst.BLK_SEL_0 = 3'b000;
defparam sdpb_inst.BLK_SEL_1 = 3'b000;
`else
reg [15:0] mem0 [0:7];
reg [15:0] mem1 [0:7];

reg [2:0] addrb_r;

// mem0 holds the DATA (A) words, mem1 the DATB (B) words. The shifter loads
// shifta (A) from doutb[15:0] and shiftb (B) from doutb[31:16], so A has to
// be in the low half
assign doutb = {mem1[addrb_r], mem0[addrb_r]};

always @(posedge clk) begin
  if (wea && !addra[0])
    mem0[addra[3:1]] <= dina;
  if (wea &&  addra[0])
    mem1[addra[3:1]] <= dina;
end

always @(posedge clk) begin
  addrb_r <= addrb;
end
`endif

endmodule
