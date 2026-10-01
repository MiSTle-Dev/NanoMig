module ide_dpram (
    output [15:0] douta,
    output [15:0] doutb,
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
    input [11:0] ada,
    input [15:0] dina,
    input [11:0] adb,
    input [15:0] dinb
);

dpram #(12,16)
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