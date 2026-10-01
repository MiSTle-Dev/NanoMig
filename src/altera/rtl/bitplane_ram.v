module bitplane_ram (
    input clk,
    input wea,
    input [2:0] addra,
    input [15:0] dina,
    input [3:0] addrb,
    output [7:0] doutb
);

dpram_dif #(3,16,4,8)
(
    .clock       ( clk ),

    .address_a   ( addra ),
    .data_a      ( {dina[7:0],dina[15:8]} ),
    .wren_a      ( wea ),

    .address_b   ( addrb ),
    .q_b         ( doutb )
);

endmodule
