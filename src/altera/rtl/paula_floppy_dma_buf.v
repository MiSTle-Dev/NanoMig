module paula_floppy_dma_buf (
    input clk,
    input wrena,
    input wrenb,
    input [7:0] addra,
    input [15:0] dina,
    input [1:0] bsa,
    input [7:0] addrb,
    input [15:0] dinb,
    input [1:0] bsb,
    output [15:0] douta,
    output [15:0] doutb
);

dma_buf_ram
(
    .clock       ( clk ),

    .address_a   ( addra ),
    .data_a      ( dina ),
    .wren_a      ( wrena ),
    .byteena_a   ( bsa ),

    .q_a         ( douta ),

    .address_b   ( addrb ),
    .data_b      ( dinb ),
    .wren_b      ( wrenb ),
    .byteena_b   ( bsa ),
    .q_b         ( doutb )
);

endmodule
