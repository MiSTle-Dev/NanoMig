// drive_sounds.v
// Generates drive activity sounds as a PWM tone on the buzzer output.
//
// FDD : 250 Hz tone,  10 ms burst per head step  (head step click)
// HDD : 1200 Hz tone, 20 ms burst /  60 ms gap  (short seek click)
//
// Clock: clk_28m ≈ 28,375,160 Hz (Tang Nano 20K / NanoMig)
// Output: buzzer → pin 53 (passive buzzer via NPN transistor)

`default_nettype none

module drive_sounds (
    input  wire clk,        // 28,375,160 MHz
    input  wire enable,     // 1 = drive sounds enabled, 0 = disabled
    // input  wire fdd_led,    // high = FDD active
    input  wire hdd_led,    // high = HDD active
    input  wire fdd_step_n, // floppy head step, active low (rising edge = step)
    output wire buzzer      // PWM output, pin 53
);

// ─── Timing constants @ 28,375,160 Hz ────────────────────────────────────────
//
//  FDD 250 Hz  → half-period = 28,375,160 / 250 / 2 = 56,750 cycles
//  HDD 1200 Hz → half-period = 28,375,160 / 1200 / 2 = 11,823 cycles
//
//  Burst / gap in cycles:
//   10 ms  = 28,375,160 × 0.010 =   283,752   (FDD: short click)
//   20 ms  = 28,375,160 × 0.020 =   567,503   (HDD: burst)
//   60 ms  = 28,375,160 × 0.060 = 1,702,510   (HDD: gap)
//
localparam HDD_HALF  = 14'd11823;
localparam HDD_BURST = 28'd567_503;
localparam HDD_GAP   = 28'd1_702_510;

localparam FDD_HALF  = 16'd56_750;    // 250 Hz
localparam FDD_BURST = 19'd283_752;   // 10 ms click per head step

// ─── FDD head step click ─────────────────────────────────────────────────────
// fdd_step_n is active low; a head step is the rising edge (same as paula_floppy).
// Every step (re)starts a 10 ms burst of the 250 Hz tone.

reg        step_del      = 1'b1;   // 1 = idle level, avoids a false edge after config
reg [18:0] fdd_burst_cnt = 19'd0;  // remaining burst cycles
reg [15:0] fdd_tone_cnt  = 16'd0;  // tone half-period counter
reg        fdd_tone      = 1'b0;

always @(posedge clk) begin
    step_del <= fdd_step_n;

    if (fdd_step_n && !step_del)
        fdd_burst_cnt <= FDD_BURST;
    else if (fdd_burst_cnt != 19'd0)
        fdd_burst_cnt <= fdd_burst_cnt - 19'd1;

    if (fdd_burst_cnt != 19'd0) begin
        if (fdd_tone_cnt == 16'd0) begin
            fdd_tone     <= ~fdd_tone;
            fdd_tone_cnt <= FDD_HALF - 16'd1;
        end else
            fdd_tone_cnt <= fdd_tone_cnt - 16'd1;
    end else begin
        fdd_tone     <= 1'b0;
        fdd_tone_cnt <= 16'd0;
    end
end

// ─── HDD ─────────────────────────────────────────────────────────────────────

reg [27:0] hdd_pat_cnt  = 28'd0;   // pattern timer
reg        hdd_pat_on   = 1'b0;    // 1 = burst phase active
reg [13:0] hdd_tone_cnt = 14'd0;   // tone half-period counter
reg        hdd_tone     = 1'b0;

always @(posedge clk) begin
    if (!hdd_led) begin
        hdd_pat_cnt  <= 28'd0;
        hdd_pat_on   <= 1'b0;
        hdd_tone_cnt <= 14'd0;
        hdd_tone     <= 1'b0;
    end else begin
        // pattern sequencer: burst <-> gap
        if (hdd_pat_cnt == 28'd0) begin
            hdd_pat_on  <= ~hdd_pat_on;
            hdd_pat_cnt <= hdd_pat_on ? HDD_GAP : HDD_BURST;
        end else
            hdd_pat_cnt <= hdd_pat_cnt - 28'd1;

        // tone oscillator (active during burst only)
        if (hdd_pat_on) begin
            if (hdd_tone_cnt == 14'd0) begin
                hdd_tone     <= ~hdd_tone;
                hdd_tone_cnt <= HDD_HALF - 14'd1;
            end else
                hdd_tone_cnt <= hdd_tone_cnt - 14'd1;
        end else
            hdd_tone <= 1'b0;
    end
end

// ─── Output ──────────────────────────────────────────────────────────────────

assign buzzer = enable & (fdd_tone | hdd_tone);
    
endmodule

`default_nettype wire
