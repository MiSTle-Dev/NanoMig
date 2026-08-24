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

reg [15:0] mem [0:7];

reg [3:0] addrb_r;

assign doutb = addrb_r[0] ? mem[addrb_r[3:1]][15:8] :
                            mem[addrb_r[3:1]][ 7:0];

always @(posedge clk) begin
  if (wea)
    mem[addra] <= dina;
end

always @(posedge clk) begin
  addrb_r <= addrb;
end

endmodule
