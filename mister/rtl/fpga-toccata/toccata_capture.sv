
/********************************************/
/* toccata_record.v                         */
/* Toccata DUMMY sound record               */
/*                                          */
/* 2022-2023, ranzbak@gmail.com             */
/********************************************/


module toccata_capture #(
    parameter int CLK_FREQUENCY = 28_359_380,
    parameter int FIFO_SIZE = 1024
) (
    input  logic        clk,
    input  logic        rst,

    // Control parameters
    input  wire         cen,        // Capture, disable - 0, enable - 1
    input  wire  [2:0]  freq_sel,   // See table below
    input  wire         sm,         // 0 - Mono, 1 - Stereo
    input  wire         fmt,        // 0 - 8 bit unsigned, 1 - 16 bit 2 complement
    input  wire         css,        // 0 - 24.576, 1 - 16.9344

    // FIFO interface
    output logic [7:0]  data_out,   // Data output
    input  logic        rd,         // High when read is done
    output logic        empty,      // 1 - FIFO is empty
    output logic        half_full,  // 1 - FIFO is half full
    output logic        full,       // 1 - FIFO is full

    // Audio interface
    output logic        endata      // Strobe on new sample data
);

// FIFO dimensions
localparam int FIFO_FULL  = FIFO_SIZE;
localparam int FIFO_HALF  = FIFO_SIZE / 2;
localparam int FIFO_EMPTY = 0;


// Frequency and frequency deviders
// AD1848 = 24.576MHz
// Deviders :
// 3072 - 8kHz
// 1536 - 16kHz
// 896  - 27.43kHz
// 768  - 31.27kHz
// 448  - 54.86kHz // Net supported in hardware
// 384  - 64kHz    // Net supported in hardware
// 512  - 48kHz
// 2560 - 9.6kHz
// Deviders based on CLK_FREQUENCY 24.576MHz
localparam int DEV_0_8_KHZ = CLK_FREQUENCY / 8000;
localparam int DEV_0_16_KHZ = CLK_FREQUENCY / 16000;
localparam int DEV_0_27_43_KHZ = CLK_FREQUENCY / 27430;
localparam int DEV_0_31_27_KHZ = CLK_FREQUENCY / 31270;
localparam int DEV_0_54_86_KHZ = CLK_FREQUENCY / 54860;
localparam int DEV_0_64_KHZ = CLK_FREQUENCY / 64000;
localparam int DEV_0_48_KHZ = CLK_FREQUENCY / 48000;
localparam int DEV_0_9_6_KHZ = CLK_FREQUENCY / 9600;
// Deviders based on CLK_FREQUENCY 16.9344MHz
localparam int DEV_1_5_5125_KHZ = CLK_FREQUENCY / 5512;
localparam int DEV_1_11_025_KHZ = CLK_FREQUENCY / 11025;
localparam int DEV_1_18_9_KHZ = CLK_FREQUENCY / 18900;
localparam int DEV_1_22_05_KHZ = CLK_FREQUENCY / 22050;
localparam int DEV_1_37_8_KHZ = CLK_FREQUENCY / 37800;
localparam int DEV_1_44_1_KHZ = CLK_FREQUENCY / 44100;
localparam int DEV_1_33_075_KHZ = CLK_FREQUENCY / 33075;
localparam int DEV_1_6_615_KHZ = CLK_FREQUENCY / 6615;

// Frequency delay counter number of bits needed
// to contain the devider for the audio frequencies
localparam int DELAY_COUNTER_BITS = $clog2(DEV_1_5_5125_KHZ) - 1;

// Audio devider reg
logic [DELAY_COUNTER_BITS:0] audio_dev = DEV_1_5_5125_KHZ[DELAY_COUNTER_BITS:0];
logic [DELAY_COUNTER_BITS:0] audio_delay = 0;
always_ff @(posedge clk) begin
    // Sample frequency devider selection, by xtal and register
    case ({css, freq_sel})
        // CSS is 0, 24.576 MHz
        4'h0:
            audio_dev <= DEV_0_8_KHZ[DELAY_COUNTER_BITS:0];
        4'h1:
            audio_dev <= DEV_0_16_KHZ[DELAY_COUNTER_BITS:0];
        4'h2:
            audio_dev <= DEV_0_27_43_KHZ[DELAY_COUNTER_BITS:0];
        4'h3:
            audio_dev <= DEV_0_31_27_KHZ[DELAY_COUNTER_BITS:0];
        4'h4:
            audio_dev <= DEV_0_54_86_KHZ[DELAY_COUNTER_BITS:0]; // Not supported in real hardware
        4'h5:
            audio_dev <= DEV_0_64_KHZ[DELAY_COUNTER_BITS:0]; // Not supported in real hardwark
        4'h6:
            audio_dev <= DEV_0_48_KHZ[DELAY_COUNTER_BITS:0];
        4'h7:
            audio_dev <= DEV_0_9_6_KHZ[DELAY_COUNTER_BITS:0];
        // CSS is 1, 16.9344 MHz
        4'h8:
            audio_dev <= DEV_1_5_5125_KHZ[DELAY_COUNTER_BITS:0];
        4'h9:
            audio_dev <= DEV_1_11_025_KHZ[DELAY_COUNTER_BITS:0];
        4'ha:
            audio_dev <= DEV_1_18_9_KHZ[DELAY_COUNTER_BITS:0];
        4'hb:
            audio_dev <= DEV_1_22_05_KHZ[DELAY_COUNTER_BITS:0];
        4'hc:
            audio_dev <= DEV_1_37_8_KHZ[DELAY_COUNTER_BITS:0];
        4'hd:
            audio_dev <= DEV_1_44_1_KHZ[DELAY_COUNTER_BITS:0];
        4'he:
            audio_dev <= DEV_1_33_075_KHZ[DELAY_COUNTER_BITS:0];
        4'hf:
            audio_dev <= DEV_1_6_615_KHZ[DELAY_COUNTER_BITS:0];
    endcase

    `ifdef DEBUG
    // $display("audio_dev = %0d", audio_dev);
    // In order to not make the simulation too long,
    // We replace the delay with a value of 5 during simulations.
    audio_dev <= 20;
    `endif
end

localparam FIFO_BW = $clog2(FIFO_SIZE) + 1;
logic                       ca_en;            // Capture enable strobe
logic [FIFO_BW-1:0] fifo_counter;     // Fake fifo counter

always_comb begin
    // Generate the FIFO status signals
    empty = 1'b0;
    half_full = 1'b0;
    full = 1'b0;

    // Set the FIFO signals
    if (fifo_counter == FIFO_EMPTY) begin
        empty = 1'b1;
    end

    // FIFO half full
    if (fifo_counter > FIFO_HALF) begin
        half_full = 1'b1;
    end

    // FIFO full
    if (fifo_counter >= FIFO_FULL) begin
        full = 1'b1;
        half_full = 1'b0;
    end

    // endata is ca_en
    endata = ca_en;
end

always_ff @(posedge clk) begin
    ca_en <= 1'b0;

    if (rst == 1'b1) begin
        audio_delay <= audio_dev;
        fifo_counter <= 0;
    end else begin
        // Trigger fake sample strobe
        if (cen == 1'b0) begin
            // Just keep the counter ready
            audio_delay <= audio_dev;
        end else begin
            if (audio_delay == 0) begin
                // When 0 start sample FSM
                audio_delay <= audio_dev;
                ca_en <= 1'b1;
            end else begin
                // counting down to action gain
                audio_delay <= audio_delay - 1'd1;
            end
        end

        // Process to run when the FSM is triggered
        if (ca_en == 1'b1 && full == 1'b0) begin
            // Increment the fake FIFO counter
            if (sm == 1'b0) begin
                if (fmt == 1'b0) begin
                    // Mono 8-bit, 1 byte per sample
                    fifo_counter <= fifo_counter + 1'd1;
                end else begin
                    // Mono 16-bit, 2 bytes per sample
                    fifo_counter <= fifo_counter + 2'd2;
                end
            end else begin
                if (fmt == 1'b0) begin
                    // Stereo 8-bit, 2 byte per sample
                    fifo_counter <= fifo_counter + 2'd2;
                end else begin
                    // Stereo 16-bit, 4 byte per sample
                    fifo_counter <= fifo_counter + 3'd4;
                end
            end
        end

        // Read process
        if (rd == 1'b1 && empty == 1'b0) begin
            // Decrement the fake fifo counter
            fifo_counter <= fifo_counter - 1'd1;
        end

        // Prevent overflows that are over FIFO_SIZE
        if (fifo_counter > FIFO_SIZE) begin
            fifo_counter <= FIFO_BW'(FIFO_SIZE);
        end

        // Always present the same fake data
        data_out <= 8'h80;
    end
end


endmodule