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

endmodule
