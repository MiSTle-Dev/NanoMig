// SPDX-License-Identifier: GPL-3.0-or-later
// ==============================================================================
// MiSTer FPGA Minimig-AGA: Audio Capture & Double-Buffering Unit (Weg A)
// Dual 4 KB Ping-Pong Buffers ($DF8000..$DF9FFF) with Hardware Backpressure
// ==============================================================================

module audio_capture (
    input  wire        clk,            // System clock (28 MHz)
    input  wire        reset,          // System reset

    // Audio input stream
    input  wire        sample_strobe,  // 48 kHz 1-cycle pulse
    input  wire signed [15:0] in_l,   // 16-bit Left Sample
    input  wire signed [15:0] in_r,   // 16-bit Right Sample

    // 8 KB Memory Buffer Read Bus ($DF8000..$DF9FFF)
    input  wire        buf_cs,         // Chip select ($DF8000..$DF9FFF)
    input  wire [12:1] buf_addr,       // bit 12: 0=Block A, 1=Block B; bits 11..1: 2048 words
    output reg  [15:0] buf_rdata,

    // Control & Status Register Interface ($DFF802)
    input  wire        reg_cs,         // Chip select ($DFF802)
    input  wire        reg_wr,         // CPU write
    input  wire [1:0]  reg_be,         // Byte enables
    input  wire [15:0] reg_wdata,      // Write data
    output wire [15:0] reg_rdata,      // Read data

    // Interrupt output (Level-2 INT2)
    output reg         irq
);

    // ==========================================================================
    // Dual-Port RAM: 4096 words x 16-bit = 8192 Bytes (2x 4 KB)
    // Block A: 0..2047 words (4096 Bytes) -> $DF8000..$DF8FFF
    // Block B: 2048..4095 words (4096 Bytes) -> $DF9000..$DF9FFF
    // Samples stored as interleaved 16-bit stereo: Word 0 = L, Word 1 = R, etc.
    // ==========================================================================
    (* ramstyle = "no_rw_check, M10K" *) reg [15:0] cap_ram [0:4095];

    // CPU Read Port (Port B)
    always @(posedge clk) begin
        if (buf_cs) begin
            buf_rdata <= cap_ram[buf_addr[12:1]];
        end
    end

    // ==========================================================================
    // Control & Status Registers
    // ==========================================================================
    reg        capture_en;     // Bit 0: 1 = Capture active
    reg        flag_block_a;   // Bit 1: 1 = Block A full / ready (W1C by CPU)
    reg        flag_block_b;   // Bit 2: 1 = Block B full / ready (W1C by CPU)
    reg        active_block;   // Bit 3: 0 = Hardware writes Block A, 1 = Block B
    reg        overrun_flag;   // Bit 4: 1 = Hardware paused because target block flag was set
    reg        irq_en;         // Bit 5: 1 = Trigger INT2 on block completion
    reg [9:0]  sample_pos;     // Bits 15..6: Current write sample (0..1023)

    assign reg_rdata = {sample_pos, irq_en, overrun_flag, active_block, flag_block_b, flag_block_a, capture_en};

    // Hardware write state machine for interleaved L/R write
    reg wr_phase; // 0 = Write Left, 1 = Write Right

    // Target block backpressure check
    wire target_blocked = (active_block == 1'b0) ? flag_block_a : flag_block_b;

    always @(posedge clk) begin
        if (reset) begin
            capture_en   <= 1'b0;
            flag_block_a <= 1'b0;
            flag_block_b <= 1'b0;
            active_block <= 1'b0;
            overrun_flag <= 1'b0;
            irq_en       <= 1'b0;
            sample_pos   <= 10'd0;
            wr_phase     <= 1'b0;
            irq          <= 1'b0;
        end else begin
            irq <= 1'b0; // Default pulse

            // CPU Register Write ($DFF802)
            if (reg_cs && reg_wr) begin
                if (reg_be[0]) begin
                    capture_en <= reg_wdata[0];
                    if (reg_wdata[1]) flag_block_a <= 1'b0; // Quittierung Block A (W1C)
                    if (reg_wdata[2]) flag_block_b <= 1'b0; // Quittierung Block B (W1C)
                    if (reg_wdata[4]) overrun_flag <= 1'b0; // Clear Overrun
                    irq_en     <= reg_wdata[5];
                end
            end

            // Hardware Audio Recording
            if (capture_en) begin
                if (sample_strobe && !wr_phase) begin
                    // Check Hardware Backpressure: Can we write to current block?
                    if (target_blocked) begin
                        // Target block has not been read/cleared by CPU yet: PAUSE writing!
                        overrun_flag <= 1'b1;
                    end else begin
                        // Step 1: Write Left sample
                        cap_ram[{active_block, sample_pos, 1'b0}] <= in_l;
                        wr_phase <= 1'b1;
                    end
                end else if (wr_phase) begin
                    // Step 2: Write Right sample on immediately following cycle
                    cap_ram[{active_block, sample_pos, 1'b1}] <= in_r;
                    wr_phase <= 1'b0;

                    // Block completion check
                    if (sample_pos == 10'd1023) begin
                        sample_pos <= 10'd0;
                        if (active_block == 1'b0) begin
                            flag_block_a <= 1'b1; // Block A is now full
                            active_block <= 1'b1; // Switch to Block B
                        end else begin
                            flag_block_b <= 1'b1; // Block B is now full
                            active_block <= 1'b0; // Switch to Block A
                        end
                        if (irq_en) irq <= 1'b1; // Signal Level-2 interrupt
                    end else begin
                        sample_pos <= sample_pos + 1'b1;
                    end
                end
            end else begin
                // When capture is disabled, reset write pointer & phase
                sample_pos <= 10'd0;
                wr_phase   <= 1'b0;
            end
        end
    end

endmodule
