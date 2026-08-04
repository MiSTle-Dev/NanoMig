// this is a generialized version of EBR primitive with
// byte-enables; most synthesis tools won't properly map it,
// so it should be replaced with a dedicated modules for a given
// vendor; this file should be mainly used for simulation
// when EBR variant of paula_floppy module is in use
`timescale 1 ns / 1 ps

module paula_floppy_dma_buf (
  input  wire [15:0] dina,
  input  wire [15:0] dinb,
  input  wire [1:0]  bsa,
  input  wire [1:0]  bsb,
  input  wire [7:0]  addra,
  input  wire [7:0]  addrb,
  input  wire        clk,
  input  wire        wrena,
  input  wire        wrenb,
  output reg  [15:0] douta,
  output reg  [15:0] doutb
);

// 256 x 16-bit RAM
reg [15:0] mem [0:255];

always @(posedge clk) begin
  douta <= mem[addra];
  doutb <= mem[addrb];

  // Port A write
  if (wrena) begin
     if (bsa[0])
      mem[addra][7:0] <= dina[7:0];
    if (bsa[1])
      mem[addra][15:8] <= dina[15:8];
  end

  // Port B write
  if (wrenb) begin
    if (bsb[0])
      mem[addrb][7:0] <= dinb[7:0];
    if (bsb[1])
      mem[addrb][15:8] <= dinb[15:8];
  end
end

endmodule
