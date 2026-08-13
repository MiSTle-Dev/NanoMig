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

assign doutb = {mem0[addrb_r], mem1[addrb_r]};

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
