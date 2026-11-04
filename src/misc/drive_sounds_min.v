// drive_sounds_min.v
// Minimal drive click: one short buzzer pulse per FDD head step / HDD activity start.
// Same ports as drive_sounds, only the module name differs.
//
// Pulse length = 2^(W-1) aclk ticks (W=7: 64 ticks = ~0.67 ms @ 96 kHz).

`default_nettype none

module drive_sounds_min #(
    parameter W = 7
) (
    input  wire clk,
    input  wire aclk_tick,  // clock enable, approximately 96 kHz
    input  wire enable,     // 1 = drive sounds enabled
    input  wire hdd_led,    // high = HDD active
    input  wire fdd_step_n, // floppy head step, active low
    output wire buzzer
);

    // Any drive activity: HDD on or FDD step pulse. One click per rising edge.
    wire act = hdd_led | ~fdd_step_n;

    reg act_d = 1'b1;                      // 1 = no false click after config
    reg [W-1:0] cnt = {1'b0, {W-1{1'b1}}}; // idle: MSB = 0, counter stopped

    always @(posedge clk) begin
        act_d <= act;
        if (enable & act & ~act_d)
            cnt <= {W{1'b1}};              // start pulse (MSB = 1)
        else if (aclk_tick & cnt[W-1])
            cnt <= cnt - 1'b1;             // MSB falls after 2^(W-1) ticks
    end

    assign buzzer = cnt[W-1];

endmodule

`default_nettype wire
