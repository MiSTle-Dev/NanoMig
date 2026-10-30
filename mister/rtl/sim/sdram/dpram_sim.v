
module dpram #(
  parameter addr_width    = 8,
  parameter data_width    = 8,
  parameter mem_init_file = " "
)(
  input                     clock,
  input  [addr_width-1:0]   address_a,
  input  [data_width-1:0]   data_a,
  input                     enable_a,
  input                     wren_a,
  output reg [data_width-1:0] q_a,
  input                     cs_a,
  input  [addr_width-1:0]   address_b,
  input  [data_width-1:0]   data_b,
  input                     enable_b,
  input                     wren_b,
  output reg [data_width-1:0] q_b,
  input                     cs_b
);

  reg [data_width-1:0] mem [0:(2**addr_width)-1];

  always @(posedge clock) begin
    if (wren_a) q_a <= data_a;
    else        q_a <= mem[address_a];

    if (wren_b) q_b <= data_b;
    else        q_b <= mem[address_b];

    if (wren_a) mem[address_a] <= data_a;
    if (wren_b) mem[address_b] <= data_b;
  end

endmodule
