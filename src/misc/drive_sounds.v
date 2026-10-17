// drive_sounds.v
// Generates drive activity sounds as a PWM tone on the buzzer output.
//
// FDD : 250 Hz tone,  10 ms burst / 200 ms gap  (head step click)
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
//  200 ms  = 28,375,160 × 0.200 = 5,675,032   (FDD: gap between steps)
//   20 ms  = 28,375,160 × 0.020 =   567,503   (HDD: burst)
//   60 ms  = 28,375,160 × 0.060 = 1,702,510   (HDD: gap)
//
// localparam FDD_HALF = 28'd94_584;
// localparam FDD_BURST = 28'd283_752;
// localparam FDD_GAP   = 28'd5_675_032;

localparam HDD_HALF  = 14'd11823;
localparam HDD_BURST = 28'd567_503;
localparam HDD_GAP   = 28'd1_702_510;

localparam FDD_HALF  = 16'd56_750;    // 250 Hz
localparam FDD_BURST = 19'd283_752;   // 10 ms click per head step

// ─── FDD ─────────────────────────────────────────────────────────────────────
/*
reg [27:0] fdd_pat_cnt  = 28'd0;   // pattern timer
reg        fdd_pat_on   = 1'b0;    // 1 = burst phase active
reg [15:0] fdd_tone_cnt = 16'd0;   // tone half-period counter
reg        fdd_tone     = 1'b0;

always @(posedge clk) begin
    if (!fdd_led) begin
        fdd_pat_cnt  <= 28'd0;
        fdd_pat_on   <= 1'b0;
        fdd_tone_cnt <= 16'd0;
        fdd_tone     <= 1'b0;
    end else begin
        // pattern sequencer: burst <-> gap
        if (fdd_pat_cnt == 28'd0) begin
            fdd_pat_on  <= ~fdd_pat_on;
            fdd_pat_cnt <= fdd_pat_on ? FDD_GAP : FDD_BURST;
        end else
            fdd_pat_cnt <= fdd_pat_cnt - 28'd1;

        // tone oscillator (active during burst only)
        if (fdd_pat_on) begin
            if (fdd_tone_cnt == 16'd0) begin
                fdd_tone     <= ~fdd_tone;
                fdd_tone_cnt <= FDD_HALF - 16'd1;
            end else
                fdd_tone_cnt <= fdd_tone_cnt - 16'd1;
        end else
            fdd_tone <= 1'b0;
    end
end
*/
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

// assign buzzer = enable & (fdd_tone | hdd_tone);
assign buzzer = enable & (fdd_tone | hdd_tone);
    
endmodule

// ─────────────────────────────────────────────────────────────────────────────
// drive_sounds_hdmi: same sounds as above, but for the HDMI audio path.
// Runs in the clk_pixel domain and advances once per 48 kHz audio sample (tick),
// so all counters are narrow:
//   FDD click : 10 ms burst = 480 samples, 250 Hz  = 96 samples per half period
//   HDD click : 20 ms burst, 60 ms gap = 960 / 2880 samples, 1200 Hz = 20 samples
//
// Sound shaping: the buzzer's transducer mostly radiates the sharp edges and upper
// harmonics of the 1 bit signal, while a plain 250 Hz square wave is dull and quiet on
// small speakers. So every edge of the tone becomes a short pulse (6 samples, +-8192,
// rising edge positive, falling edge negative -> no DC), same timing as the buzzer.
// click = 1 means "add 8192 to the audio sample", click_neg = 1 "subtract" (done in top.sv).
// ─────────────────────────────────────────────────────────────────────────────

module drive_sounds_hdmi (
    input  wire clk,         // clk_pixel
    input  wire tick,        // one clk_pixel cycle per 48 kHz sample (aclk_tick)
    input  wire enable,      // 1 = drive sounds enabled (osd, clk_28m domain)
    input  wire hdd_led,     // high = HDD active (clk_28m domain)
    input  wire fdd_step_n,  // floppy head step, active low, rising edge = step (clk_28m domain)
    output wire click,
    output wire click_neg
);

// clk_pixel is generated by a second PLL, so bring the inputs over first
reg [2:0] step_sync = 3'b111;  // [1:0] synchronizer, [2] previous value
reg [1:0] hdd_sync  = 2'b00;
reg [1:0] en_sync   = 2'b00;
always @(posedge clk) begin
    step_sync <= {step_sync[1:0], fdd_step_n};
    hdd_sync  <= {hdd_sync[0],  hdd_led};
    en_sync   <= {en_sync[0],   enable};
end
wire step_edge = step_sync[1] & ~step_sync[2];

reg        step_pend = 1'b0;   // step seen, waiting for the next sample tick
reg [8:0]  fdd_burst = 9'd0;   // remaining burst samples
reg [6:0]  fdd_cnt   = 7'd0;   // tone half-period counter
reg        fdd_tone  = 1'b0;
reg [11:0] hdd_pat   = 12'd0;  // 80 ms pattern: 960 samples on, 2880 off
reg [4:0]  hdd_cnt   = 5'd0;   // tone half-period counter
reg        hdd_tone  = 1'b0;

wire       tone      = fdd_tone | hdd_tone;
reg        tone_d    = 1'b0;   // tone one sample ago
reg [2:0]  pulse_cnt = 3'd0;   // remaining samples of the current edge pulse
reg        pulse_neg = 1'b0;   // 1 = falling edge

always @(posedge clk) begin
    if (tick) step_pend <= 1'b0;
    if (step_edge) step_pend <= 1'b1;

    if (tick) begin
        // FDD
        if (step_pend)
            fdd_burst <= 9'd480;
        else if (fdd_burst != 9'd0)
            fdd_burst <= fdd_burst - 9'd1;

        if (fdd_burst != 9'd0) begin
            if (fdd_cnt == 7'd0) begin
                fdd_tone <= ~fdd_tone;
                fdd_cnt  <= 7'd95;
            end else
                fdd_cnt <= fdd_cnt - 7'd1;
        end else begin
            fdd_tone <= 1'b0;
            fdd_cnt  <= 7'd0;
        end

        // HDD
        if (!hdd_sync[1]) begin
            hdd_pat  <= 12'd0;
            hdd_cnt  <= 5'd0;
            hdd_tone <= 1'b0;
        end else begin
            hdd_pat <= (hdd_pat == 12'd3839) ? 12'd0 : hdd_pat + 12'd1;
            if (hdd_pat < 12'd960) begin
                if (hdd_cnt == 5'd0) begin
                    hdd_tone <= ~hdd_tone;
                    hdd_cnt  <= 5'd19;
                end else
                    hdd_cnt <= hdd_cnt - 5'd1;
            end else begin
                hdd_tone <= 1'b0;
                hdd_cnt  <= 5'd0;
            end
        end

        // edge pulses
        tone_d <= tone;
        if (tone != tone_d) begin
            pulse_cnt <= 3'd6;
            pulse_neg <= tone_d;
        end else if (pulse_cnt != 3'd0)
            pulse_cnt <= pulse_cnt - 3'd1;
    end
end

wire pulse_on = en_sync[1] & (pulse_cnt != 3'd0);
assign click     = pulse_on;
assign click_neg = pulse_on & pulse_neg;

endmodule

`default_nettype wire
