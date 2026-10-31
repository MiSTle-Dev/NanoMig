/********************************************/
/* toccata_volume.v                         */
/* Toccata sound volume attenuation         */
/*                                          */
/* 2022-2023, ranzbak@gmail.com             */
/********************************************/

module toccata_volume (
    input  wire                clk,
    input  wire                rst,
    input  wire signed  [15:0] audio_in_left,
    input  wire signed  [15:0] audio_in_right,
    input  wire         [5:0]  attenuation_left,
    input  wire                mute_left,
    input  wire         [5:0]  attenuation_right,
    input  wire                mute_right,
    output logic signed [15:0] audio_out_left,
    output logic signed [15:0] audio_out_right
);

// Fixed-point representation of the attenuation factor
parameter FIXED_ATTEN_FACTOR   = 16'sd27553; // Fixed-point representation of 0.8409
parameter FIXED_ONE            = 32'sd32768; // Fixed-point representation of 1.0 or 2^15

parameter integer ATTEN_LEVELS = 64; // 6 bits for attenuation level

// LUT for attenuation factors
logic signed [31:0] attenuation_factors[ATTEN_LEVELS];

// Initialize the LUT
initial begin
    attenuation_factors[0] = FIXED_ONE; // 0 dB attenuation
    for (int i = 1; i < ATTEN_LEVELS; i++) begin
        attenuation_factors[i] = (attenuation_factors[i - 1] * FIXED_ATTEN_FACTOR) >>> 15;
    end
end

// Apply volume control using LUT and clock
always_ff @(posedge clk) begin
    if (rst) begin
        // Hold the output nutral during reset
        audio_out_left <= 'h0000;
        audio_out_right <= 'h0000;
    end else begin
        // Using inferred DSP blocks to do volume calculations
        if (mute_left) begin
            audio_out_left <= 'h0000;
        end else begin
            audio_out_left <= 16'(($signed(audio_in_left) * attenuation_factors[attenuation_left]) >>> 15);
        end
        if (mute_right) begin
            audio_out_right <= 'h0000;
        end else begin
            audio_out_right <= 16'(($signed(audio_in_right) * attenuation_factors[attenuation_right]) >>> 15);
        end
    end
end

endmodule
