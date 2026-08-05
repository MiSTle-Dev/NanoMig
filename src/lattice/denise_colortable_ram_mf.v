// colortable ram

module denise_colortable_ram_mf (
  input  [1:0]  ena_a,
  input         clock,
  input  [11:0] data,
  input  [7:0]  rdaddress,
  input  [7:0]  wraddress,
  input         wren,
  output [23:0] q
);

wire [31:0] q_i;

colortable_ram colortable (
  .WrAddress(wraddress),
  .RdAddress(rdaddress),
  .Data({4'b0, data, 4'b0, data}),
  .ByteEn({ena_a[1], ena_a[1], ena_a[0], ena_a[0]}),
  .WE(wren),
  .RdClock(clock),
  .RdClockEn(1'b1),
  .Reset(1'b0),
  .WrClock(clock),
  .WrClockEn(1'b1),
  .Q(q_i)
);

assign q = {q_i[27:16], q_i[11:0]};

endmodule
