module sprite_ram (
    input clk,
    input wea,
    input [3:0] addra,
    input [15:0] dina,
    input [2:0] addrb,
    output [31:0] doutb
);

dpram_dif #(4,16,3,32)
(
    .clock       ( clk ),

    .address_a   ( addra ),
    .data_a      ( dina ),
    .wren_a      ( wea ),

    .address_b   ( addrb ),
    .q_b         ( {doutb[15:0],doutb[31:16]} )
);

endmodule
