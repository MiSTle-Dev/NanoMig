/********************************************/
/* toccata_playback.v                       */
/* Toccata sound playback                   */
/*                                          */
/* 2022-2023, ranzbak@gmail.com             */
/********************************************/


module toccata_playback #(
    parameter int CLK_FREQUENCY = 28_359_380
) (
    input  logic        clk,
    input  logic        rst,

    // Control parameters
    input  wire         pen,        // Playback, disable - 0, enable - 1
    input  wire  [2:0]  freq_sel,   // See table below
    input  wire         sm,         // 0 - Mono, 1 - Stereo
    input  wire         lc,         // 0 - Linear, 1 - companded (not supported)
    input  wire         fmt,        // 0 - 8 bit unsigned, 1 - 16 bit 2 complement
    input  wire         css,        // 0 - 24.576, 1 - 16.9344

    // FIFO interface
    output logic        rst_fifo,   // Reset FIFO if sm, lc, fmt change
    output logic        rd_en,      // Enable read from FIFO
    input  wire  [7:0]  data_in,    // Data from the FIFO
    input  wire         empty,      // 1 - FIFO is empty

    // Audio interface
    (* KEEP = "true" *)
    output logic [15:0] ldata,      // Left DAC data
    (* KEEP = "true" *)
    output logic [15:0] rdata,      // Right DAC data
    (* KEEP = "true" *)
    output logic        endata      // Strobe on new sample data
);


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

// Byte ordering in playback modes
// 8bit  - mono   : 0 - n bytes in order
// 8bit  - stereo : sample 1 - left, sample 1 - right ...n
// 16bit - mona   : sample 1 - byte 1, 2 ...n
// 16bit - stereo : sample 1 - byte 1, 2 left byte 3, 4 right byte ...n
logic signed [15:0] tmp_16bit_left;
logic signed [15:0] tmp_16bit_right;
logic signed [7:0]  tmp_8bit_left;
logic signed [7:0]  tmp_8bit_right;
logic               pb_en;            // Playback enable strobe
// Change detection registers
logic               _sm;
logic               _lc;
logic               _fmt;

typedef enum { idle,
    STEP_0_MONO,
    STEP_1_MONO,
    STEP_2_MONO,
    STEP_0_STEREO,
    STEP_1_STEREO,
    STEP_2_STEREO,
    STEP_3_STEREO,
    STEP_4_STEREO
} pbStateType;
pbStateType pb_state = idle;
always_ff @(posedge clk) begin
    pb_en <= 1'b0;
    rd_en <= 1'b0;
    endata <= 1'b0;
    rst_fifo <= 1'b0;

    // Sync prev regs
    _sm <= sm;
    _lc <= lc;
    _fmt <= fmt;

    if (rst) begin
        rst_fifo <= 1'b1;
        pb_state <= idle;
        tmp_8bit_left <= 8'sh80;
        tmp_8bit_right <= 8'sh80;
        tmp_16bit_left <= 16'h0000;
        tmp_16bit_right <= 16'h0000;
        ldata <= 16'h0000;
        rdata <= 16'h0000;
    end else begin
        // Detect changes between previous and current
        if (sm != _sm || lc != _lc || _fmt != _fmt) begin
            // Reset FIFO
            rst_fifo <= 1'b1;
            // Reset FSM
            pb_state <= idle;
        end

        // Trigger sample playback at the correct delay
        if (pen == 1'b0) begin
            // Just keep the counter ready
            audio_delay <= audio_dev;
        end else begin
            if (audio_delay == 0) begin
                // When 0 start sample FSM
                audio_delay <= audio_dev;
                pb_en <= 1'b1;
            end else begin
                // counting down to action gain
                audio_delay <= audio_delay - 1'd1;
            end
        end

        // FSM to handle different sample modes
        //
        // LC == 1'b1 is for Companded audio, because we don't implement it
        // we treat it like a normal 8-bit audio stream.
        case (pb_state)
            idle: begin
                // Don't start playing if the buffer is empty
                if (pb_en == 1'b1 && empty == 1'b0) begin
                    endata <= 1'b1; // signal new data is available
                    if (sm == 1'b0) begin
                        pb_state <= STEP_0_MONO;
                    end else begin
                        pb_state <= STEP_0_STEREO;
                    end
                end
            end
            // Handle mono decoding
            STEP_0_MONO: begin
                // Pulse read enable to get new byte
                rd_en <= 1'b1;
                if (rd_en == 1'b1) begin
                    pb_state <= pb_state.next();
                    rd_en <= 1'b0;
                end
            end
            STEP_1_MONO: begin
                if (fmt == 1'b0 || lc == 1'b1) begin // 8-bit
                    // Make 8-bit unsigned to 8 bits signed
                    tmp_8bit_left <= data_in - 8'sh80;
                    pb_state <= pb_state.next();
                end else begin // 16 bit
                    // Store the LSB first
                    tmp_8bit_left <= data_in;
                    rd_en <= 1'b1; // Get the MSB
                    if (rd_en == 1'b1) begin
                        pb_state <= pb_state.next();
                        rd_en <= 1'b0;
                    end
                end
            end
            STEP_2_MONO: begin
                if (fmt == 1'b0 || lc == 1'b1) begin // 8-bit
                    // Output the 8-bit signed data on both left and right channels
                    ldata <= {tmp_8bit_left, 8'h00};
                    rdata <= {tmp_8bit_left, 8'h00};
                end else begin // 16 bit
                    // Output the 16-bit mono on both left and right channels
                    ldata <= {data_in, tmp_8bit_left};
                    rdata <= {data_in, tmp_8bit_left};
                end
                pb_state <= idle;
            end
            // Handle stereo decoding
            STEP_0_STEREO: begin
                // Start by initiating the first read
                rd_en <= 1'b1;
                if (rd_en == 1'b1) begin
                    pb_state <= pb_state.next();
                    rd_en <= 1'b0;
                end
            end
            STEP_1_STEREO: begin
                if (fmt == 1'b0 || lc == 1'b1) begin // 8-bit
                    // Make 8-bit unsigned to 8 bits signed
                    tmp_8bit_left <= data_in - 8'sh80;
                end else begin // 16 bit
                    // Get left channel lsb first
                    tmp_16bit_left[7:0] <= data_in;
                end
                rd_en <= 1'b1; // read next byte
                if (rd_en == 1'b1) begin
                    pb_state <= pb_state.next();
                    rd_en <= 1'b0;
                end
            end
            STEP_2_STEREO: begin
                if (fmt == 1'b0 || lc == 1'b1) begin // 8-bit
                    // Make 8-bit unsigned to 8 bits signed
                    tmp_8bit_right <= data_in - 8'sh80;
                    pb_state <= pb_state.next();
                end else begin // 16-bit
                    // Get left chonnel msb
                    tmp_16bit_left[15:8] <= data_in;
                    rd_en <= 1'b1; // read next byte
                    if (rd_en == 1'b1) begin
                        pb_state <= pb_state.next();
                        rd_en <= 1'b0;
                    end
                end
            end
            STEP_3_STEREO: begin
                if (fmt == 1'b0 || lc == 1'b1) begin // 8-bit
                    // Output received data
                    ldata <= {tmp_8bit_left, 8'h00};
                    rdata <= {tmp_8bit_right, 8'h00};
                    pb_state <= idle;
                end else begin // 16-bit
                    // Get right channel lsb first
                    tmp_16bit_right[7:0] <= data_in;
                    rd_en <= 1'b1; // read next byte
                    if (rd_en == 1'b1) begin
                        pb_state <= pb_state.next();
                        rd_en <= 1'b0;
                    end
                end
            end
            STEP_4_STEREO: begin
                // Output received data on both channels 16-bit
                ldata <= tmp_16bit_left;
                rdata <= {data_in, tmp_16bit_right[7:0]};
                pb_state <= idle;
            end
        endcase
    end
end
endmodule
