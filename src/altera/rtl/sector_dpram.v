module sector_dpram (
    output [7:0] douta,
    output [7:0] doutb,
    input clka,
    input ocea,
    input cea,
    input reseta,
    input wrea,
    input clkb,
    input oceb,
    input ceb,
    input resetb,
    input wreb,
    input [8:0] ada,
    input [7:0] dina,
    input [8:0] adb,
    input [7:0] dinb
);

dpram #(9,8)
(
    .clock       ( clka ),

    .address_a   ( ada ),
    .data_a      ( dina ),
    .wren_a      ( wrea ),
    .q_a         ( douta ),

    .address_b   ( adb ),
    .data_b      ( dinb ),
    .wren_b      ( wreb ),
    .q_b         ( doutb )
);

endmodule