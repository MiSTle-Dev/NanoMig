// SPDX-License-Identifier: GPL-3.0-or-later
// 32-Voice High-Definition Audio Extension with Dual Biquad IIR Filter DSPs, Shared ADPCM & 32-bit DMA Engine for MiSTer.
// Features: 32 voices, 32-bit DMA lengths, dual parallel Biquad DSP cores, stereo routing,
//           pre/post-filter cascades, AM/tremolo & ring modulation, and 32.768 kHz hardware start-delay.
// Optimized for Altera/Intel Cyclone V (MiSTer DE10-Nano).

module audio_ext #(
    parameter NUM_VOICES = 32
)(
    input wire clk, reset, ntsc,
    input wire reg_cs, reg_wr,
    input wire [9:1] reg_addr,  // 512 words = 1024 bytes ($DFF400..$DFF7FF)
    input wire [1:0] reg_be,
    input wire [15:0] reg_wdata,
    output reg [15:0] reg_rdata,
    output wire irq,
    output wire dma_req,
    output wire [31:0] dma_addr,
    input wire dma_ack,
    input wire [15:0] dma_data,
    input wire dma_error,
    output reg signed [15:0] sample_l, sample_r
);

    wire [9:0] address = {reg_addr, 1'b0};
    wire [4:0] ch  = address[9:5]; // 32 channels (0..31), 32 bytes each
    wire [3:0] off = address[4:1]; // 16 words per channel
    wire is_ch31 = (ch == 5'd31);

    reg bus_held;
    reg [9:1] bus_last;
    wire write_once = reg_cs && reg_wr && (!bus_held || reg_addr != bus_last);
    always @(posedge clk) begin
        if (reset) begin bus_held <= 0; bus_last <= 0; end
        else begin bus_held <= reg_cs && reg_wr; bus_last <= reg_addr; end
    end

    // Virtual 50 MHz timebase
    reg [11:0] clock_phase;
    wire [13:0] phase_sum = {2'b00, clock_phase} + (ntsc ? 14'd7152 : 14'd7218);
    wire [1:0] virtual_ticks = phase_sum[13:12];
    always @(posedge clk) begin
        if (reset) clock_phase <= 12'd0;
        else clock_phase <= phase_sum[11:0];
    end

    // TDM slot counter (counts 0 to NUM_VOICES-1)
    reg [4:0] cur_voice;
    always @(posedge clk) begin
        if (reset) cur_voice <= 0;
        else cur_voice <= cur_voice + 1'b1;
    end
    wire [4:0] cur_voice_next = cur_voice + 1'b1;

    // 32.768 kHz Timebase for Start-Delay Engine (27 slots of 32 clocks = 864 clocks ~ 32.84 kHz)
    reg [4:0] delay_slot_cnt;
    reg delay_tick_flag;

    always @(posedge clk) begin
        if (reset) begin
            delay_slot_cnt  <= 5'd0;
            delay_tick_flag <= 1'b0;
        end else if (cur_voice == 5'd31) begin
            delay_tick_flag <= 1'b0;
            if (delay_slot_cnt == 5'd26) begin
                delay_slot_cnt  <= 5'd0;
                delay_tick_flag <= 1'b1;
            end else begin
                delay_slot_cnt <= delay_slot_cnt + 1'b1;
            end
        end
    end

    // Configuration registers (32-bit pointer & 32-bit length on MiSTer)
    reg [7:0]  cfg_ptr_hi [0:NUM_VOICES-1];
    reg [15:0] cfg_ptr_lo [0:NUM_VOICES-1];
    reg [15:0] cfg_len_hi [0:NUM_VOICES-1];
    reg [15:0] cfg_len_lo [0:NUM_VOICES-1];

    // Global 32-Bit Interrupt Registers (At Channel 31: $DFF7F8 / $DFF7FC)
    reg [NUM_VOICES-1:0] voice_irq_en;
    reg [NUM_VOICES-1:0] voice_pending;

    // CPU Configuration Register Write
    always @(posedge clk) begin
        if (reset) begin
            voice_irq_en <= {NUM_VOICES{1'b0}};
        end else if (write_once) begin
            case (off)
                4'd0: cfg_ptr_hi[ch] <= reg_wdata[7:0];
                4'd1: cfg_ptr_lo[ch] <= reg_wdata;
                4'd2: cfg_len_hi[ch] <= reg_wdata;
                4'd3: cfg_len_lo[ch] <= reg_wdata;
                // Channel 31 Global Interrupt Enable (32-bit across words 12 and 13)
                4'd12: if (is_ch31) voice_irq_en[31:16] <= reg_wdata; // $DFF7F8: INTENA HI
                4'd13: if (is_ch31) voice_irq_en[15:0]  <= reg_wdata; // $DFF7FA: INTENA LO
            endcase
        end
    end

    // Unified 2-bit Voice State: 2'b00 = IDLE, 2'b01 = DELAYING, 2'b10 = PREFILL, 2'b11 = PLAYING
    reg [1:0] voice_state [0:NUM_VOICES-1];
    reg [NUM_VOICES-1:0] dma_need_init, tdm_need_init;

    wire cmd_we = write_once && (off == 4'd13) && !is_ch31 && reg_be[0];

    // Runtime DMA voice state (23-bit word pointer, 32-bit length)
    reg [22:0] ram_ptr   [0:NUM_VOICES-1];
    reg [31:0] ram_len   [0:NUM_VOICES-1];
    reg [5:0]  ram_wrptr [0:NUM_VOICES-1];
    reg [5:0]  ram_rdptr [0:NUM_VOICES-1];

    // Shared DMA requester
    reg [4:0] dma_voice;
    reg dma_active;
    assign dma_req = dma_active;

    wire [23:0] dma_ptr   = {ram_ptr[dma_voice], 1'b0};
    wire [31:0] dma_len   = ram_len[dma_voice];
    wire [5:0]  dma_wrptr = ram_wrptr[dma_voice];
    assign dma_addr = {8'd0, dma_ptr};

    wire dma_push = dma_active && dma_ack;
    wire [22:0] next_dma_ptr = ram_ptr[dma_voice] + 1'b1;
    wire [31:0] next_dma_len = (|dma_len[31:1]) ? dma_len - 32'd2 : 32'd0;

    // FIFO RAM: 2048x16 -> 64 words per voice for 32 voices
    (* ramstyle = "no_rw_check" *) reg [15:0] fifo_ram [0:2047];
    reg [15:0] fifo_dout;
    wire [5:0] tdm_rdptr = ram_rdptr[cur_voice];

    always @(posedge clk) begin
        if (dma_push) fifo_ram[{dma_voice, dma_wrptr}] <= dma_data;
        fifo_dout <= fifo_ram[{cur_voice, tdm_rdptr}];
    end

    // Volume & Period RAM (Standard Dual-Port RAM)
    reg [15:0] ram_vol [0:NUM_VOICES-1];
    reg [15:0] ram_per [0:NUM_VOICES-1];
    reg [31:0] dout_vol_per;

    always @(posedge clk) begin
        if (write_once) begin
            if (off == 4'd4) begin
                if (reg_be[1]) ram_vol[ch][15:8] <= reg_wdata[15:8];
                if (reg_be[0]) ram_vol[ch][ 7:0] <= reg_wdata[ 7:0];
            end
            if (off == 4'd5) begin
                if (reg_be[1]) ram_per[ch][15:8] <= reg_wdata[15:8];
                if (reg_be[0]) ram_per[ch][ 7:0] <= reg_wdata[ 7:0];
            end
        end
        dout_vol_per <= {ram_vol[cur_voice_next], ram_per[cur_voice_next]};
    end

    wire [15:0] v_vol = dout_vol_per[31:16];
    wire [15:0] v_per = dout_vol_per[15:0];

    // Control & Combined Predictor/Index RAM
    reg [15:0] ram_ctrl  [0:NUM_VOICES-1];
    reg [15:0] ram_pred0 [0:NUM_VOICES-1];
    reg [31:0] dout_ctrl_pred0;

    always @(posedge clk) begin
        if (write_once) begin
            if (off == 4'd6) begin
                if (reg_be[1]) ram_ctrl[ch][15:8] <= reg_wdata[15:8];
                if (reg_be[0]) ram_ctrl[ch][ 7:0] <= reg_wdata[ 7:0];
            end
            if (off == 4'd7) begin
                if (reg_be[1]) ram_pred0[ch][15:8] <= reg_wdata[15:8];
                if (reg_be[0]) ram_pred0[ch][ 7:0] <= reg_wdata[ 7:0];
            end
        end
        dout_ctrl_pred0 <= {ram_ctrl[cur_voice_next], ram_pred0[cur_voice_next]};
    end

    wire [15:0] v_ctrl     = dout_ctrl_pred0[31:16];
    wire [15:0] v_pred_raw = dout_ctrl_pred0[15:0];
    wire signed [15:0] v_pred0   = {{7{v_pred_raw[15]}}, v_pred_raw[15:7]};
    wire [6:0]         v_init_idx = (v_pred_raw[6:0] > 7'd88) ? 7'd88 : v_pred_raw[6:0];
    wire               v_flt_r = v_ctrl[7];
    wire               v_flt_l = v_ctrl[8];
    wire [1:0]         v_input_src = v_ctrl[10:9];
    wire [1:0]         v_mod_mode  = v_ctrl[12:11];
    wire               v_mute_mix  = v_ctrl[13];

    // Selected TDM Voice signals
    wire [5:0]  tdm_fifo_fill = ram_wrptr[cur_voice] - tdm_rdptr;
    wire [31:0] v_cur_len = ram_len[cur_voice];

    // TDM State Dual-Port RAMs
    reg [31:0] sdpb_pcm_idx  [0:NUM_VOICES-1];
    reg [31:0] sdpb_timer_bc [0:NUM_VOICES-1];
    reg [31:0] sdpb_res      [0:NUM_VOICES-1];
    reg [31:0] dout_pcm_idx;
    reg [31:0] dout_timer_bc;
    reg [31:0] dout_res;

    wire signed [15:0] cur_pcm  = dout_pcm_idx[31:16];
    wire [6:0]         cur_idx  = dout_pcm_idx[15:9];
    wire [15:0]        v_timer  = dout_timer_bc[31:16];
    wire [4:0]         v_bc     = dout_timer_bc[15:11];
    wire [23:0]        v_res    = dout_res[31:8];

    wire        v_act    = voice_state[cur_voice][1]; // PREFILL (2'b10) or PLAYING (2'b11)
    wire        v_pref   = (voice_state[cur_voice] == 2'b10);

    wire v_stereo = v_ctrl[2];
    wire v_adpcm  = v_ctrl[3];
    wire v_hybrid = v_ctrl[5:4] == 2;
    wire [2:0] v_bps0 = v_hybrid ? 3'd5 : (v_ctrl[5:4] == 1 ? 3'd2 : 3'd4);
    wire [2:0] v_bps1 = v_hybrid ? 3'd3 : v_bps0;
    wire [5:0] v_frame_bits = v_adpcm ? ({3'd0, v_bps0} + (v_stereo ? {3'd0, v_bps1} : 6'd0)) :
                                        (v_ctrl[0] ? (v_stereo ? 6'd32 : 6'd16) : (v_stereo ? 6'd16 : 6'd8));

    wire [15:0] tick_step = {10'd0, virtual_ticks, 4'b0000};
    wire v_timer_exp = (v_timer[15:6] == 10'd0) && (v_timer[5:4] <= virtual_ticks);
    wire [15:0] timer_diff = v_timer - tick_step;

    wire do_decode = v_act && !v_pref && v_timer_exp && (v_bc >= v_frame_bits);
    wire do_refill = v_act && (v_bc <= 8) && (|tdm_fifo_fill) && !do_decode;

    wire [15:0] be_fifo = {fifo_dout[7:0], fifo_dout[15:8]};
    wire [31:0] merged_fill = {be_fifo, v_res[7:0], 8'd0} >> (4'd8 - v_bc[3:0]);
    wire [23:0] next_res_fill = (v_bc[3:0] == 4'd8) ? {be_fifo, v_res[7:0]} : merged_fill[23:0];

    reg [23:0] next_res_consume;
    always @* begin
        case (v_frame_bits)
            6'd2:    next_res_consume = {2'd0,  v_res[23:2]};
            6'd4:    next_res_consume = {4'd0,  v_res[23:4]};
            6'd5:    next_res_consume = {5'd0,  v_res[23:5]};
            6'd8:    next_res_consume = {8'd0,  v_res[23:8]};
            6'd16:   next_res_consume = {16'd0, v_res[23:16]};
            default: next_res_consume = 24'd0;
        endcase
    end

    wire signed [15:0] next_pcm_l = v_ctrl[0] ? {v_res[7:0], v_res[15:8]} : {v_res[7:0], 8'd0};

    // Shared Stateless ADPCM Decoder Core
    wire signed [15:0] dec_out_pcm;
    wire [6:0]         dec_out_idx;

    adpcm_decoder_shared shared_dec (
        .clk(clk),
        .rst(reset),
        .req_valid(do_decode && v_adpcm),
        .in_pcm(cur_pcm),
        .in_index(cur_idx),
        .code(v_res[4:0]),
        .bits_per_code(v_bps0),
        .out_pcm(dec_out_pcm),
        .out_index(dec_out_idx)
    );

    wire signed [15:0] new_pcm = (do_decode && v_adpcm) ? dec_out_pcm :
                                 (do_decode)            ? next_pcm_l :
                                 cur_pcm;
    wire [6:0] new_idx = (do_decode && v_adpcm) ? dec_out_idx :
                         (do_decode)            ? 7'd0 :
                         cur_idx;

    wire [15:0] next_timer = tdm_need_init[cur_voice] ? v_per :
        (v_act && !v_pref) ? (v_timer_exp ? ((v_bc >= v_frame_bits) ? (v_per + timer_diff) : 16'd0) : timer_diff) :
        (v_pref && (tdm_fifo_fill[5] || v_cur_len == 0)) ? v_per :
        v_timer;

    wire [4:0] next_bc = tdm_need_init[cur_voice] ? 5'd0 :
        do_refill ? {1'b1, v_bc[3:0]} :
        do_decode ? (v_bc - v_frame_bits[4:0]) :
        v_bc;

    wire [23:0] next_res_val = tdm_need_init[cur_voice] ? 24'd0 :
        do_refill ? next_res_fill :
        do_decode ? next_res_consume :
        v_res;

    wire [22:0] next_pcm_idx_val = tdm_need_init[cur_voice] ?
        {v_pred0, v_init_idx} :
        {new_pcm, new_idx};

    always @(posedge clk) begin
        sdpb_pcm_idx[cur_voice]  <= {next_pcm_idx_val, 9'd0};
        sdpb_timer_bc[cur_voice] <= {next_timer, next_bc, 11'd0};
        sdpb_res[cur_voice]      <= {next_res_val, 8'd0};
        dout_pcm_idx  <= sdpb_pcm_idx[cur_voice_next];
        dout_timer_bc <= sdpb_timer_bc[cur_voice_next];
        dout_res      <= sdpb_res[cur_voice_next];
    end

    // rdptr tracking
    always @(posedge clk) begin
        if (reset) begin
            tdm_need_init <= {NUM_VOICES{1'b0}};
        end else begin
            if (cmd_we && reg_wdata[0]) tdm_need_init[ch] <= 1'b1;
            if (loop_reload) tdm_need_init[cur_voice] <= 1'b1;
            if (tdm_need_init[cur_voice]) begin
                tdm_need_init[cur_voice] <= 1'b0;
                ram_rdptr[cur_voice] <= 6'd0;
            end else if (do_refill) begin
                ram_rdptr[cur_voice] <= ram_rdptr[cur_voice] + 1'b1;
            end
        end
    end

    // Channel Chaining & Cascade Logic (Pre/Post-Filter across all 32 channels)
    reg signed [15:0] prev_pre_sample;
    reg signed [15:0] prev_post_sample;
    reg prev_decode_reg;

    always @(posedge clk) begin
        if (reset) begin
            prev_pre_sample  <= 16'd0;
            prev_post_sample <= 16'd0;
            prev_decode_reg  <= 1'b0;
        end else begin
            prev_pre_sample  <= in_pcm_src_l;
            prev_post_sample <= biquad_pcm_l;
            prev_decode_reg  <= (v_input_src != 2'b00) ? prev_decode_reg : do_decode;
        end
    end

    wire signed [15:0] in_pcm_src_l = (v_input_src == 2'b01) ? prev_pre_sample :
                                      (v_input_src == 2'b10) ? prev_post_sample :
                                      new_pcm;
    wire signed [15:0] in_pcm_src_r = (v_input_src != 2'b00) ? in_pcm_src_l : new_pcm;

    wire biquad_strobe = (v_input_src != 2'b00) ? prev_decode_reg : do_decode;

    // Dual Parallel Biquad IIR Filter Engines (16 channels each for 100% throughput)
    // Core 0: Voices 0..15, Core 1: Voices 16..31
    wire signed [15:0] biquad0_pcm_l, biquad0_pcm_r;
    wire signed [15:0] biquad1_pcm_l, biquad1_pcm_r;
    wire [15:0] biquad0_rdata, biquad1_rdata;

    wire biquad_cs = write_once && (off >= 4'd8 && off <= 4'd12);

    biquad_iir_ringbuffer biquad_inst0 (
        .clk(clk),
        .reset(reset),
        .reg_cs(biquad_cs && !ch[4]),
        .reg_wr(reg_wr),
        .reg_addr({ch[3:0], off[2:0]}),
        .reg_be(reg_be),
        .reg_wdata(reg_wdata),
        .reg_rdata(biquad0_rdata),
        .cur_voice(cur_voice[3:0]),
        .filter_en_l(v_flt_l && !cur_voice[4]),
        .filter_en_r(v_flt_r && !cur_voice[4]),
        .is_stereo(v_stereo),
        .req_strobe(biquad_strobe && !cur_voice[4]),
        .in_pcm_l(in_pcm_src_l),
        .in_pcm_r(in_pcm_src_r),
        .out_pcm_l(biquad0_pcm_l),
        .out_pcm_r(biquad0_pcm_r)
    );

    biquad_iir_ringbuffer biquad_inst1 (
        .clk(clk),
        .reset(reset),
        .reg_cs(biquad_cs && ch[4]),
        .reg_wr(reg_wr),
        .reg_addr({ch[3:0], off[2:0]}),
        .reg_be(reg_be),
        .reg_wdata(reg_wdata),
        .reg_rdata(biquad1_rdata),
        .cur_voice(cur_voice[3:0]),
        .filter_en_l(v_flt_l && cur_voice[4]),
        .filter_en_r(v_flt_r && cur_voice[4]),
        .is_stereo(v_stereo),
        .req_strobe(biquad_strobe && cur_voice[4]),
        .in_pcm_l(in_pcm_src_l),
        .in_pcm_r(in_pcm_src_r),
        .out_pcm_l(biquad1_pcm_l),
        .out_pcm_r(biquad1_pcm_r)
    );

    wire signed [15:0] biquad_pcm_l = cur_voice[4] ? biquad1_pcm_l : biquad0_pcm_l;
    wire signed [15:0] biquad_pcm_r = cur_voice[4] ? biquad1_pcm_r : biquad0_pcm_r;
    wire [15:0] biquad_rdata = ch[4] ? biquad1_rdata : biquad0_rdata;

    // DSP Stereo Mixer with AM / Tremolo & Ringmodulation
    wire signed [15:0] mix_out_l = biquad_pcm_l;
    wire signed [15:0] mix_out_r = biquad_pcm_r;

    reg signed [15:0] prev_carrier_l;
    always @(posedge clk) begin
        if (reset) prev_carrier_l <= 16'd0;
        else prev_carrier_l <= mix_out_l;
    end

    wire is_mod = (v_mod_mode != 2'b00);
    wire [7:0] mod_u8 = (prev_carrier_l[15:8] ^ 8'h80);
    wire signed [8:0] mod_factor = (v_mod_mode == 2'b01) ? $signed({1'b0, mod_u8}) :
                                   (v_mod_mode == 2'b10) ? $signed(prev_carrier_l[15:7]) :
                                   $signed({1'b0, v_vol[15:8]});

    wire [7:0] raw_vol_l = v_mute_mix ? 8'd0 : v_vol[15:8];
    wire [7:0] raw_vol_r = v_mute_mix ? 8'd0 : v_vol[7:0];
    wire signed [8:0] vol_factor_l = is_mod ? mod_factor : $signed({1'b0, raw_vol_l});
    wire signed [8:0] vol_factor_r = is_mod ? mod_factor : $signed({1'b0, raw_vol_r});

    wire signed [24:0] mul_l = mix_out_l * vol_factor_l;
    wire signed [24:0] mul_r = mix_out_r * vol_factor_r;

    // 21-Bit Master Accumulator for 32 Voices (5 bits headroom)
    reg signed [20:0] acc_l, acc_r;

    always @(posedge clk) begin
        if (cur_voice == 0) begin
            acc_l <= mul_l[23:8];
            acc_r <= mul_r[23:8];
            sample_l <= (!acc_l[20] && |acc_l[19:15]) ? 16'sh7FFF : (acc_l[20] && !(&acc_l[19:15])) ? 16'sh8000 : acc_l[15:0];
            sample_r <= (!acc_r[20] && |acc_r[19:15]) ? 16'sh7FFF : (acc_r[20] && !(&acc_r[19:15])) ? 16'sh8000 : acc_r[15:0];
        end else begin
            acc_l <= acc_l + mul_l[23:8];
            acc_r <= acc_r + mul_r[23:8];
        end
    end

    // DMA FSM (32 voices round-robin)
    wire [5:0] dma_fifo_fill = dma_wrptr - ram_rdptr[dma_voice];
    wire dma_fifo_full = dma_fifo_fill[5] && dma_fifo_fill[4]; // >= 48 words

    always @(posedge clk) begin
        if (reset) begin
            dma_active <= 1'b0; dma_voice <= 0;
        end else begin
            if (dma_active) begin
                if (dma_ack) begin
                    dma_active <= 1'b0;
                    dma_voice <= dma_voice + 1'b1;
                end
            end else begin
                if (|dma_len && voice_state[dma_voice][1] && !dma_fifo_full) begin
                    dma_active <= 1'b1;
                end else begin
                    dma_voice <= dma_voice + 1'b1;
                end
            end
        end
    end

    // Voice Active tracking & Buffer Completion (Paula-compatible by 32-bit LEN)
    wire voice_done = (v_cur_len == 0) && (tdm_fifo_fill == 0) && (v_bc < v_frame_bits);
    wire loop_reload = v_act && !v_pref && voice_done && !v_ctrl[1];

    // Simple Dual-Port RAM for Start-Delay Counter (32 words x 16 bits)
    reg [15:0] del_cnt [0:NUM_VOICES-1];
    reg [NUM_VOICES-1:0] has_delay;

    wire del_active   = delay_tick_flag && (voice_state[cur_voice] == 2'b01);
    wire [15:0] cur_del_val = del_cnt[cur_voice];
    wire del_hits_one = (cur_del_val <= 16'd1);
    wire [15:0] next_del_val = cur_del_val - 1'b1;

    // Single write port to del_cnt (CPU write or TDM countdown decrement)
    wire cpu_del_we   = write_once && (off == 4'd14) && !is_ch31;
    wire wr_del_we    = cpu_del_we || del_active;
    wire [4:0] wr_del_addr  = cpu_del_we ? ch : cur_voice;
    wire [15:0] wr_del_data = cpu_del_we ? reg_wdata : next_del_val;

    always @(posedge clk) begin
        if (wr_del_we) del_cnt[wr_del_addr] <= wr_del_data;
    end

    // Synchronous write to DMA RAMs
    always @(posedge clk) begin
        if (reset) begin
            dma_need_init <= {NUM_VOICES{1'b0}};
        end else begin
            if (cmd_we && reg_wdata[0] && !has_delay[ch]) dma_need_init[ch] <= 1'b1;
            if ((del_active && del_hits_one) || loop_reload) dma_need_init[cur_voice] <= 1'b1;

            if (dma_need_init[dma_voice]) begin
                dma_need_init[dma_voice] <= 1'b0;
                ram_ptr[dma_voice] <= {cfg_ptr_hi[dma_voice], cfg_ptr_lo[dma_voice][15:1]};
                ram_len[dma_voice] <= {cfg_len_hi[dma_voice], cfg_len_lo[dma_voice]};
                ram_wrptr[dma_voice] <= 6'd0;
            end else if (dma_push) begin
                ram_ptr[dma_voice] <= next_dma_ptr;
                ram_len[dma_voice] <= next_dma_len;
                ram_wrptr[dma_voice] <= dma_wrptr + 1'b1;
            end
        end
    end

    // Voice State & Start-Delay FSM (TDM unified 2-bit state machine)
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            voice_pending <= {NUM_VOICES{1'b0}};
            has_delay     <= {NUM_VOICES{1'b0}};
            for (i = 0; i < NUM_VOICES; i = i + 1) voice_state[i] <= 2'b00;
        end else begin
            if (v_act && !v_pref && voice_done) begin
                if (v_ctrl[1]) voice_state[cur_voice] <= 2'b00; // One-shot stops -> IDLE
                voice_pending[cur_voice] <= 1'b1;
            end else if (v_pref && (tdm_fifo_fill[5] || v_cur_len == 0)) begin
                voice_state[cur_voice] <= 2'b11; // PREFILL -> PLAYING
            end else if (del_active && del_hits_one) begin
                voice_state[cur_voice] <= 2'b10; // DELAYING -> PREFILL
            end

            // CPU writes to delay register (single-driven write port)
            if (write_once && (off == 4'd14) && !is_ch31) begin
                has_delay[ch] <= (reg_wdata != 16'd0);
            end

            // CPU Command register handling
            if (cmd_we) begin
                if (reg_wdata[1]) begin
                    voice_state[ch] <= 2'b00; // STOP -> IDLE
                end else if (reg_wdata[0]) begin
                    voice_state[ch] <= has_delay[ch] ? 2'b01 : 2'b10; // START -> DELAYING or PREFILL
                end
            end else if (write_once && is_ch31) begin
                if (off == 4'd14) voice_pending[31:16] <= voice_pending[31:16] & ~reg_wdata; // W1C HI
                if (off == 4'd15) voice_pending[15:0]  <= voice_pending[15:0]  & ~reg_wdata; // W1C LO
            end
        end
    end

    // Flat CPU Register Read Mux (32-Voice Option A: Global INTENA/INTREQ at Channel 31)
    always @* begin
        case (off)
            4'd12:   reg_rdata = is_ch31 ? voice_irq_en[31:16] : 16'd0;
            4'd13:   reg_rdata = is_ch31 ? voice_irq_en[15:0]  : {13'd0, (voice_state[ch] == 2'b01), (voice_state[ch] == 2'b10), voice_state[ch][1]};
            4'd14:   reg_rdata = is_ch31 ? voice_pending[31:16]: {15'd0, (voice_state[ch] == 2'b01)};
            4'd15:   reg_rdata = is_ch31 ? voice_pending[15:0] : {15'd0, (voice_state[ch] == 2'b01)};
            4'd8, 4'd9, 4'd10, 4'd11: reg_rdata = biquad_rdata;
            default: reg_rdata = 16'd0;
        endcase
    end

    assign irq = |(voice_pending & voice_irq_en);

endmodule
