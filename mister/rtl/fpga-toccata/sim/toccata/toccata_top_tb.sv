`timescale 1ns / 1ps

module toccata_top_tb;

localparam real PI = 3.141592654;

// count clock cycles
int clk_cycles = 0;

// Test bench signals
logic clk, rst;
logic hsync;
logic [15:0] data_in, data_out;
logic [15:0] addr;
logic rd, hwr, lwr, sel;
logic toc_int;
logic [15:0] out_left, out_right;

// Instantiate the Unit Under Test (UUT)
toccata uut (
    .clk(clk),
    .rst(rst),
    .hsync(hsync),
    .data_in(data_in),
    .data_out(data_out),
    .addr(addr[15:1]),
    .rd(rd),
    .hwr(hwr),
    .lwr(lwr),
    .sel(sel),
    .toc_int(toc_int),
    .out_left(out_left),
    .out_right(out_right)
);

// Clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk; // Define clock period
end

// Back stop to stop simulation in case of hanging process
initial begin
    #2000000 $fatal(1, "Simulation took too long, failing");
end

// State and step variables
typedef enum int {
    // Dump registers
    IDLE,
    WRITE,
    READ_STATUS,
    READ,
    CHECK,
    // Check autocallibration
    SET_ACAL_IDX,
    ENABLE_ACAL_WR,
    SET_ACI_IDX,
    CHECK_ACI_HIGH,
    CHECK_ACI_LOW,
    SET_ACAL_LOW_IDX,
    CHECK_ACAL_LOW,
    // Audio playback tests
    UNMUTE_LEFT_DAC_1,
    UNMUTE_LEFT_DAC_2,
    UNMUTE_RIGHT_DAC_1,
    UNMUTE_RIGHT_DAC_2,
    // 8-bit mono
    SET_PLAYBACK_BUFFER,
    SET_PLAYBACK_FORMAT_IDX,
    SET_PLAYBACK_FORMAT,
    START_PLAYBACK,
    LOAD_SAMPLES_8BIT_MONO,
    SET_PLAYBACK_TO_START,
    WAIT_PLAYBACK,
    STOP_PLAYBACK,
    // 8-bit stereo
    SET_PLAYBACK_FORMAT_IDX_8BIT_ST,
    SET_PLAYBACK_FORMAT_8BIT_ST,
    START_PLAYBACK_8BIT_ST,
    LOAD_SAMPLES_8BIT_ST_L,
    LOAD_SAMPLES_8BIT_ST_R,
    STOP_PLAYBACK_8BIT_ST,
    // 16-bit mono
    SET_PLAYBACK_FORMAT_IDX_16BIT_MONO,
    SET_PLAYBACK_FORMAT_16BIT_MONO,
    START_PLAYBACK_16BIT_MONO,
    LOAD_SAMPLES_16BIT_MONO,
    STOP_PLAYBACK_16BIT_MONO,
    // 16-bit stereo
    SET_PLAYBACK_FORMAT_IDX_16BIT_ST,
    SET_PLAYBACK_FORMAT_16BIT_ST,
    START_PLAYBACK_16BIT_ST,
    LOAD_SAMPLES_16BIT_ST_L,
    LOAD_SAMPLES_16BIT_ST_R,
    STOP_PLAYBACK_16BIT_ST,
    // Done
    FINISH
} state_t;
state_t state;
int step;

// Reset pulse
initial begin
    rst = 1;
    // ... Initialize other signals
    #20 rst = 0;
end

int hsync_cnt = 0;
wire [7:0] data_out_high;
// Convenient way to get the higher byte of the 16-interface
assign data_out_high = data_out[15:8];

// Test sinus wave generation
wire signed [15:0] audio_in_16_l;
wire signed [15:0] audio_in_16_r;
wire signed [7:0] audio_in_8_l;
wire signed [7:0] audio_in_8_r;
int        pos_counter, pos_counter_next, wait_reg;
assign audio_in_16_l = $rtoi($sin(2 * PI * (pos_counter / 64.0)) * 32767);
assign audio_in_16_r = $rtoi($cos(2 * PI * (pos_counter / 64.0)) * 32767);
assign audio_in_8_l = $rtoi($sin(2 * PI * (pos_counter / 64.0)) * 127) + 128;
assign audio_in_8_r = $rtoi($cos(2 * PI * (pos_counter / 64.0)) * 127) + 128;
assign pos_counter_next = pos_counter + 1;

// Synchronous test logic
always_ff @(posedge clk) begin
    rd <= 1'b0;
    hwr <= 1'b0;
    lwr <= 1'b0;

    // Measure time in clock cycles
    clk_cycles = clk_cycles + 1;

    // Main test body
    if (rst) begin
        state <= IDLE;
        step <= 0;
        addr <= 16'h0000;
        sel <= 1'b0;
        data_in <= 16'h0000;
        hsync <= 1'b0;
        pos_counter <= 0;
        wait_reg <= 0;
    end else begin

        // Generate hsync signal for simulation
        hsync <= 1'b0;
        if (hsync_cnt < 10) begin
            hsync_cnt <= hsync_cnt + 1;
        end else begin
            hsync_cnt <= 0;
        end
        if (hsync_cnt > 6) begin
            hsync <= 1'b1;
        end

        case (state)
            IDLE: begin
                sel <= 1'b1;
                if (step < 16) begin
                    state <= WRITE;
                end else begin
                    state <= SET_ACAL_IDX;
                end
            end
            WRITE: begin
                addr <= 16'h6700;
                data_in <= {8'h00, step[7:0]};
                lwr <= 1'b0;
                hwr <= 1'b1;
                state <= READ_STATUS;
            end
            READ_STATUS : begin
                addr <= 16'h0000;
                rd <= 1'b1;
                if (rd == 1'b1) begin
                    state <= READ;
                end
            end
            READ: begin
                addr <= 16'h6800;
                rd <= 1'b1;
                if (rd == 1'b1) begin
                    state <= CHECK;
                end
            end
            CHECK: begin
                $display("Addr: %1h, Read Value: %2h", step, data_out_high);
                step <= step + 1;
                state <= IDLE;
            end
            SET_ACAL_IDX : begin
                // Set the index to the interface config register
                addr <= 16'h6700;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h00, 8'h09};
                state <= ENABLE_ACAL_WR;
            end
            ENABLE_ACAL_WR : begin
                // Write one to the ACAl register to trigger a autocallibration
                addr <= 16'h6800;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h00, 8'b0000_1100}; // SDC, ACAL
                state <= SET_ACI_IDX;
            end
            SET_ACI_IDX : begin
                // Set the index to the Test and initialization register
                addr <= 16'h6700;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h00, 8'h0B}; // Reg nr 11
                state <= CHECK_ACI_HIGH;
                $display("%d - ACI bit set", clk_cycles);
            end
            CHECK_ACI_HIGH : begin
                addr <= 16'h6800;
                hwr <= 1'b0;
                lwr <= 1'b0;
                rd <= 1'b1;
                if (data_out[5] == 1'b1 && rd == 1'b1) begin
                    $display("%d - ACAL found to be high", clk_cycles);
                    rd <= 1'b0;
                    state <= CHECK_ACI_LOW;
                end
            end
            CHECK_ACI_LOW : begin
                addr <= 16'h6800;
                hwr <= 1'b0;
                lwr <= 1'b0;
                rd <= 1'b1;
                if (data_out_high[5] == 1'b0 && rd == 1'b1) begin
                    state <= SET_ACAL_LOW_IDX;
                    rd <= 1'b0;
                    $display("%d - ACAL found to be low", clk_cycles);
                end
            end
            SET_ACAL_LOW_IDX : begin
                // Set the index to the interface config register
                addr <= 16'h6700;
                data_in <= {8'h09, 8'h00};
                hwr <= 1'b1;
                lwr <= 1'b0;
                state <= CHECK_ACAL_LOW;
            end
            CHECK_ACAL_LOW : begin
                // Check if the ACAL bit is low after auto callibration completed
                addr <= 16'h6800;
                hwr <= 1'b0;
                lwr <= 1'b0;
                rd <= 1'b1;
                if (data_out_high[3] == 1'b0) begin
                    $display("%d - ACAL found to be low", clk_cycles);
                    state <= UNMUTE_LEFT_DAC_1;
                    rd <= 1'b0;
                end
            end
            // ----------------------------------------------------------------
            // Start the audio playback tests
            // ----------------------------------------------------------------
            UNMUTE_LEFT_DAC_1 : begin
                addr <= 16'h6700;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h06, 8'h00};
                if (hwr == 1'b1) begin
                    state <= UNMUTE_LEFT_DAC_2;
                    hwr <= 1'b0;
                end
            end
            UNMUTE_LEFT_DAC_2 : begin
                addr <= 16'h6800;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h00, 8'h00}; // Unmute lef dac
                if (hwr == 1'b1) begin
                    state <= UNMUTE_RIGHT_DAC_1;
                    hwr <= 1'b0;
                end
            end
            UNMUTE_RIGHT_DAC_1 : begin
                addr <= 16'h6700;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h07, 8'h00};
                if (hwr == 1'b1) begin
                    state <= UNMUTE_RIGHT_DAC_2;
                    hwr <= 1'b0;
                end
            end
            UNMUTE_RIGHT_DAC_2 : begin
                addr <= 16'h6800;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h00, 8'h00}; // Unmute lef dac
                if (hwr == 1'b1) begin
                    state <= SET_PLAYBACK_BUFFER;
                    hwr <= 1'b0;
                end
            end
            SET_PLAYBACK_BUFFER : begin
                // Start buffering but do not start playback yet
                addr <= 16'h0000;
                hwr <= 1'b0;
                lwr <= 1'b1;
                data_in <= 16'h0011;
                if (lwr == 1'b1) begin
                    state <= SET_PLAYBACK_FORMAT_IDX;
                    lwr <= 1'b0;
                end
            end
            SET_PLAYBACK_FORMAT_IDX : begin
                addr <= 16'h6700;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h08, 8'h00};
                if (hwr == 1'b1) begin
                    state <= SET_PLAYBACK_FORMAT;
                    hwr <= 1'b0;
                end
            end
            SET_PLAYBACK_FORMAT : begin
                addr <= 16'h6800;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h08, 8'h00}; // 24 MHz clock, 8kHz, mono, 8-bit
                if (hwr == 1'b1) begin
                    state <= START_PLAYBACK;
                    hwr <= 1'b0;
                end
            end
            START_PLAYBACK : begin
                // Set the bit to start playback to one
                addr <= 16'h0000; // Status register
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= 16'h0011; // Card active, Enable Codec, Start playback, play intena
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    state <= LOAD_SAMPLES_8BIT_MONO;
                end
            end
            LOAD_SAMPLES_8BIT_MONO : begin
                // Load a sequence of samples
                addr <= 16'h2000;
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= {8'h00, audio_in_8_l};
                if (lwr == 1'b1) begin
                    pos_counter <= pos_counter_next;
                    lwr <= 1'b0;
                end
                if (pos_counter > 1024) begin
                    // Buffer is full we are done
                    state <= SET_PLAYBACK_TO_START;
                    lwr <= 1'b0;
                end
            end
            SET_PLAYBACK_TO_START: begin
                // Set playback to start after buffering
                addr <= 16'h0000; // Status register
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= 16'h0095; // Card active, Enable + interrupt
                if (lwr == 1'b1) begin
                    wait_reg <= 4000;
                    lwr <= 1'b0;
                    state <= WAIT_PLAYBACK;
                end
            end
            WAIT_PLAYBACK: begin
                // Wait for a 100 cycles, to observe playback
                wait_reg <= wait_reg - 1;
                if (wait_reg == 0) begin
                    state <= STOP_PLAYBACK;
                end
            end
            STOP_PLAYBACK : begin
                // Stop playback and see if buffer is resetted
                addr <= 16'h0000; // Status register
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= 16'h0001; // Card active, Enable
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    state <= SET_PLAYBACK_FORMAT_IDX_8BIT_ST;
                end
            end
            // ----------------------------------------------------------------
            // 8-bit stereo audio
            // ----------------------------------------------------------------
            SET_PLAYBACK_FORMAT_IDX_8BIT_ST : begin
                addr <= 16'h6700;
                hwr <= 1'b1;
                lwr <= 1'b0;
                rd <= 1'b0;
                data_in <= {8'h08, 8'h00};
                if (hwr == 1'b1) begin
                    state <= SET_PLAYBACK_FORMAT_8BIT_ST;
                    hwr <= 1'b0;
                end
            end
            SET_PLAYBACK_FORMAT_8BIT_ST : begin
                addr <= 16'h6800;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h18, 8'h00}; // 24 MHz clock, 8kHz, stereo, 8-bit
                if (hwr == 1'b1) begin
                    state <= START_PLAYBACK_8BIT_ST;
                    hwr <= 1'b0;
                end
            end
            START_PLAYBACK_8BIT_ST : begin
                // Set the bit to start playback to one
                addr <= 16'h0000; // Status register
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= 16'h0095; // Card active, Enable Codec, Start playback, play intena
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    pos_counter <= 0;
                    state <= LOAD_SAMPLES_8BIT_ST_L;
                end
            end
            LOAD_SAMPLES_8BIT_ST_L : begin
                // Load a sequence of samples
                addr <= 16'h2000;
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= {8'h00, audio_in_8_l};
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    state <= LOAD_SAMPLES_8BIT_ST_R;
                end
            end
            LOAD_SAMPLES_8BIT_ST_R : begin
                // Load a sequence of samples
                addr <= 16'h2000;
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= {8'h00, audio_in_8_r};
                if (lwr == 1'b1) begin
                    pos_counter <= pos_counter_next;
                    lwr <= 1'b0;
                    state <= LOAD_SAMPLES_8BIT_ST_L;
                end
                if (pos_counter > 512) begin
                    // Buffer is full we are done
                    state <= SET_PLAYBACK_FORMAT_IDX_16BIT_MONO;
                    lwr <= 1'b0;
                end
            end
            // ----------------------------------------------------------------
            // 16-bit mono test
            // ----------------------------------------------------------------
            SET_PLAYBACK_FORMAT_IDX_16BIT_MONO: begin
                addr <= 16'h6700;
                hwr <= 1'b1;
                lwr <= 1'b0;
                rd <= 1'b0;
                data_in <= {8'h08, 8'h00};
                if (hwr == 1'b1) begin
                    state <= SET_PLAYBACK_FORMAT_16BIT_MONO;
                    hwr <= 1'b0;
                end
            end
            SET_PLAYBACK_FORMAT_16BIT_MONO: begin
                addr <= 16'h6800;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h48, 8'h00}; // 24 MHz clock, 8kHz, mono, 16-bit
                if (hwr == 1'b1) begin
                    state <= START_PLAYBACK_16BIT_MONO;
                    hwr <= 1'b0;
                end
            end
            START_PLAYBACK_16BIT_MONO: begin
                // Set the bit to start playback to one
                addr <= 16'h0000; // Status register
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= 16'h0095; // Card active, Enable Codec, Start playback, play intena
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    pos_counter <= 0;
                    state <= LOAD_SAMPLES_16BIT_MONO;
                end
            end
            LOAD_SAMPLES_16BIT_MONO: begin
                // Load a sequence of samples
                addr <= 16'h2000;
                hwr <= 1'b1;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= audio_in_16_l;
                // if (lwr == 1'b1) begin
                //     pos_counter <= pos_counter_next;
                //     lwr <= 1'b0;
                //     state <= LOAD_SAMPLES_16BIT_MONO_LSB;
                // end
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    hwr <= 1'b0;
                    pos_counter <= pos_counter_next;
                end
                if (pos_counter > 512) begin
                    // Buffer is full we are done
                    state <= STOP_PLAYBACK_16BIT_MONO;
                    lwr <= 1'b0;
                    hwr <= 1'b0;
                end
            end
            STOP_PLAYBACK_16BIT_MONO: begin
                // Stop playback
                addr <= 16'h0000; // Status register
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= 16'h0001; // Card active, Enable
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    state <= SET_PLAYBACK_FORMAT_IDX_16BIT_ST;
                end
            end
            // ----------------------------------------------------------------
            // 16-bit stereo
            // ----------------------------------------------------------------
            SET_PLAYBACK_FORMAT_IDX_16BIT_ST: begin
                addr <= 16'h6700;
                hwr <= 1'b1;
                lwr <= 1'b0;
                rd <= 1'b0;
                data_in <= {8'h08, 8'h00};
                if (hwr == 1'b1) begin
                    state <= SET_PLAYBACK_FORMAT_16BIT_ST;
                    hwr <= 1'b0;
                end
            end
            SET_PLAYBACK_FORMAT_16BIT_ST: begin
                addr <= 16'h6800;
                hwr <= 1'b1;
                lwr <= 1'b0;
                data_in <= {8'h58, 8'h00}; // 24 MHz clock, 8kHz, stereo, 16-bit
                if (hwr == 1'b1) begin
                    state <= START_PLAYBACK_16BIT_ST;
                    hwr <= 1'b0;
                end
            end
            START_PLAYBACK_16BIT_ST: begin
                // Set the bit to start playback to one
                addr <= 16'h0000; // Status register
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= 16'h0095; // Card active, Enable Codec, Start playback, play intena
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    pos_counter <= 0;
                    state <= LOAD_SAMPLES_16BIT_ST_L;
                end
            end
            LOAD_SAMPLES_16BIT_ST_L: begin
                // Load a sequence of samples
                addr <= 16'h2000;
                hwr <= 1'b1;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= audio_in_16_l;
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    state <= LOAD_SAMPLES_16BIT_ST_R;
                end
            end
            LOAD_SAMPLES_16BIT_ST_R: begin
                // Load a sequence of samples
                addr <= 16'h2000;
                hwr <= 1'b1;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= audio_in_16_r;
                if (lwr == 1'b1) begin
                    pos_counter <= pos_counter_next;
                    lwr <= 1'b0;
                    hwr <= 1'b0;
                    state <= LOAD_SAMPLES_16BIT_ST_L;
                end
                if (pos_counter > 256) begin
                    // Buffer is full we are done
                    state <= STOP_PLAYBACK_16BIT_ST;
                    lwr <= 1'b0;
                    hwr <= 1'b0;
                end
            end
            STOP_PLAYBACK_16BIT_ST: begin
                // Stop playback
                addr <= 16'h0000; // Status register
                hwr <= 1'b0;
                lwr <= 1'b1;
                rd <= 1'b0;
                data_in <= 16'h0001; // Card active, Enable
                if (lwr == 1'b1) begin
                    lwr <= 1'b0;
                    state <= FINISH;
                end
            end
            // 16 bit Stereo audio test
            FINISH: begin
                `ifdef DEBUG
                $display("%d - Finished", clk_cycles);
                `endif
                $finish;
            end
        endcase
    end
end

endmodule
