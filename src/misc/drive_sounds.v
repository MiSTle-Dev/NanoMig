// drive_sounds.v
// Generates drive activity sounds as a PWM tone on the buzzer output.
//
// FDD : 250 Hz tone,  10 ms burst per head step  (head step click)
// HDD : 1200 Hz tone, 20 ms burst /  60 ms gap  (short seek click)
//
// Timing: approximately 96 kHz tick, synchronous to clk
// Output: buzzer → pin 53 (passive buzzer via NPN transistor)

`default_nettype none

module drive_sounds (
    input  wire clk,        // system clock
    input  wire aclk_tick,  // clock enable, approximately 96 kHz
    input  wire enable,     // 1 = drive sounds enabled, 0 = disabled
    // input  wire fdd_led,    // high = FDD active
    input  wire hdd_led,    // high = HDD active
    input  wire fdd_step_n, // floppy head step, active low (rising edge = step)
    output wire buzzer      // PWM output, pin 53
);

// ─── Timing constants @ approximately 96 kHz ────────────────────────────────
// Tone frequencies and burst lengths are approximate; all timers count ticks.
localparam HDD_HALF  = 6'd40;    // 1200 Hz
localparam HDD_BURST = 13'd1920;  // 20 ms
localparam HDD_GAP   = 13'd5760; // 60 ms

localparam FDD_HALF  = 8'd192;    // 250 Hz
localparam FDD_BURST = 10'd960;   // 10 ms click per head step

// ─── FDD head step click ─────────────────────────────────────────────────────
// fdd_step_n is active low; a head step is the rising edge (same as paula_floppy).
// Every step (re)starts a 10 ms burst of the 250 Hz tone.

reg        step_del      = 1'b1;   // 1 = idle level, avoids a false edge after config
reg [9:0] fdd_burst_cnt = 10'd0;  // remaining burst ticks
reg [7:0] fdd_tone_cnt  = 8'd0;  // tone half-period counter
reg        fdd_tone      = 1'b0;

always @(posedge clk) begin
    // Detect every step, including pulses entirely between audio ticks.
    step_del <= fdd_step_n;

    if (fdd_step_n && !step_del)
        fdd_burst_cnt <= FDD_BURST;
    else if (aclk_tick && fdd_burst_cnt != 10'd0)
        fdd_burst_cnt <= fdd_burst_cnt - 10'd1;

    if (aclk_tick) begin
        if (fdd_burst_cnt != 10'd0) begin
            if (fdd_tone_cnt == 8'd0) begin
                fdd_tone     <= ~fdd_tone;
                fdd_tone_cnt <= FDD_HALF - 8'd1;
            end else
                fdd_tone_cnt <= fdd_tone_cnt - 8'd1;
        end else begin
            fdd_tone     <= 1'b0;
            fdd_tone_cnt <= 8'd0;
        end
    end
end

// ─── HDD ─────────────────────────────────────────────────────────────────────

reg [12:0] hdd_pat_cnt  = 13'd0;   // pattern timer
reg        hdd_pat_on   = 1'b0;    // 1 = burst phase active
reg [5:0] hdd_tone_cnt = 6'd0;   // tone half-period counter
reg        hdd_tone     = 1'b0;

always @(posedge clk) begin
    if (!hdd_led) begin
        hdd_pat_cnt  <= 13'd0;
        hdd_pat_on   <= 1'b0;
        hdd_tone_cnt <= 6'd0;
        hdd_tone     <= 1'b0;
    end else if (aclk_tick) begin
        // pattern sequencer: burst <-> gap
        if (hdd_pat_cnt == 13'd0) begin
            hdd_pat_on  <= ~hdd_pat_on;
            hdd_pat_cnt <= hdd_pat_on ? HDD_GAP : HDD_BURST;
        end else
            hdd_pat_cnt <= hdd_pat_cnt - 13'd1;

        // tone oscillator (active during burst only)
        if (hdd_pat_on) begin
            if (hdd_tone_cnt == 6'd0) begin
                hdd_tone     <= ~hdd_tone;
                hdd_tone_cnt <= HDD_HALF - 6'd1;
            end else
                hdd_tone_cnt <= hdd_tone_cnt - 6'd1;
        end else
            hdd_tone <= 1'b0;
    end
end

// ─── Output ──────────────────────────────────────────────────────────────────

assign buzzer = enable & (fdd_tone | hdd_tone);

endmodule

`default_nettype wire
