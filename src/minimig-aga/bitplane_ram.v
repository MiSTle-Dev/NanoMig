module bitplane_ram (
  // Port write
  input  wire        clk,
  input  wire        wea,
  input  wire  [2:0] addra,
  input  wire [15:0] dina,

  // Port read
  input  wire  [3:0] addrb,
  output wire  [7:0] doutb
);

`ifndef BITPLANE_SSRAM
wire [23:0] do_unused;
SDPB sdpb_inst (
  .DO({do_unused, doutb}),
  .DI({16'h0000, dina[7:0], dina[15:8]}),
  .BLKSELA(3'b000),
  .BLKSELB(3'b000),
  .ADA({7'b0000000, addra, 2'b00, 2'b11}),
  .ADB({7'b0000000, addrb, 3'b000}),
  .CLKA(clk),
  .CLKB(clk),
  .CEA(wea),
  .CEB(1'b1),
  .OCE(1'b0),
  .RESETA(1'b0),
  .RESETB(1'b0)
);
defparam sdpb_inst.BIT_WIDTH_0 = 16;
defparam sdpb_inst.BIT_WIDTH_1 = 8;
defparam sdpb_inst.READ_MODE = 1'b0;
defparam sdpb_inst.RESET_MODE = "SYNC";
defparam sdpb_inst.BLK_SEL_0 = 3'b000;
defparam sdpb_inst.BLK_SEL_1 = 3'b000;
`else
reg [15:0] mem [0:7];

reg [3:0] addrb_r;

// bitplane words are shifted out msb first, so the first (even) byte column
// of a word is its upper byte
assign doutb = addrb_r[0] ? mem[addrb_r[3:1]][ 7:0] :
                            mem[addrb_r[3:1]][15:8];

always @(posedge clk) begin
  if (wea)
    mem[addra] <= dina;
end

always @(posedge clk) begin
  addrb_r <= addrb;
end

`endif
endmodule
