// SPDX-License-Identifier: GPL-3.0-or-later
// 16-Channel 2nd-Order Biquad IIR Filter Engine with Hardware Block RAM (DPB) Ringbuffer State & Single-DSP Sharing.
// Supports independent Left/Right channel filtering (AUDxCTRL bits 8..7: 00=off, 01=R, 10=L, 11=both).

module biquad_iir_ringbuffer (
    input wire clk,
    input wire reset,

    // CPU Configuration Interface (off 8..12 -> b0, b1, b2, a1, a2)
    input wire        reg_cs,
    input wire        reg_wr,
    input wire [6:0]  reg_addr, // ch [6:3], coeff_idx [2:0]
    input wire [1:0]  reg_be,
    input wire [15:0] reg_wdata,
    output wire [15:0] reg_rdata,

    // Audio TDM Interface
    input wire [3:0]          cur_voice,
    input wire                filter_en_l, // from v_ctrl[8]
    input wire                filter_en_r, // from v_ctrl[7]
    input wire                is_stereo,   // from v_ctrl[2]
    input wire                req_strobe,  // do_decode pulse
    input wire signed [15:0]  in_pcm_l,    // new_pcm Left
    input wire signed [15:0]  in_pcm_r,    // new_pcm Right
    output wire signed [15:0] out_pcm_l,   // filtered Left
    output wire signed [15:0] out_pcm_r    // filtered Right
);

    wire [3:0] ch = reg_addr[6:3];
    wire [2:0] coeff_idx = reg_addr[2:0];
    wire [7:0] cpu_addr = {ch, coeff_idx, 1'b0};

    // Sequential Biquad FSM (Port B)
    reg [3:0] state;
    reg [3:0] proc_ch;
    reg       proc_side;     // 0 = Left (or Mono), 1 = Right
    reg       proc_stereo;
    reg       proc_flt_r;
    reg signed [15:0] proc_x;
    reg signed [15:0] proc_x_r;
    reg signed [33:0] acc;

    // Linear FSM offset: States 0..8 map directly to addresses 0..8
    wire [3:0] fsm_offset = (state <= 4'd8)  ? state :
                            (state == 4'd10) ? 4'd3 :
                            (state == 4'd11) ? 4'd1 :
                            (state == 4'd12) ? 4'd7 :
                            (state == 4'd13) ? 4'd5 : 4'd0;

    // Bit 8 of DPB word address: 0 for shared coeffs (even offset), proc_side for state history (odd offset)
    wire side_bit = fsm_offset[0] ? proc_side : 1'b0;
    wire [8:0] fsm_addr = {side_bit, (state == 4'd0 ? cur_voice : proc_ch), fsm_offset};
    wire fsm_we = (state >= 4'd10 && state <= 4'd13);
    wire [15:0] fsm_rdata;

    // Latches for state pipeline
    reg signed [15:0] lat_x1, lat_y1;

    // Saturation logic for Biquad output (Q2.14)
    wire signed [19:0] y_sc = acc[33:14];
    wire signed [15:0] y_sat = (!y_sc[19] && |y_sc[18:15]) ? 16'sh7FFF :
                               ( y_sc[19] && !(&y_sc[18:15])) ? 16'sh8000 : y_sc[15:0];

    wire [15:0] fsm_wdata = (state == 4'd10) ? lat_x1 :
                            (state == 4'd11) ? proc_x  :
                            (state == 4'd12) ? lat_y1  :
                                               y_sat;

    // 16 Output values stored in Distributed RAM (SSRAM)
    reg signed [15:0] y_held_l [0:15];
    reg signed [15:0] y_held_r [0:15];

    wire we_l = (state == 4'd13) && (proc_side == 1'b0);
    wire we_r = (state == 4'd13) && (proc_side == 1'b1 || !proc_stereo);

    always @(posedge clk) begin
        if (we_l) y_held_l[proc_ch] <= y_sat;
        if (we_r) y_held_r[proc_ch] <= y_sat;
    end

    // Single Hardware MULT18X18 DSP
    reg signed [15:0] dsp_a;
    reg signed [15:0] dsp_b;
    wire [35:0] dsp_out;

    MULT18X18 biquad_mult (
        .DOUT(dsp_out), .SOA(), .SOB(),
        .A({{2{dsp_a[15]}}, dsp_a}), .B({{2{dsp_b[15]}}, dsp_b}),
        .SIA(18'd0), .SIB(18'd0), .ASEL(1'b0), .BSEL(1'b0),
        .ASIGN(1'b1), .BSIGN(1'b1), .CLK(clk), .CE(1'b1), .RESET(1'b0)
    );
    defparam biquad_mult.AREG = 1'b0;
    defparam biquad_mult.BREG = 1'b0;
    defparam biquad_mult.OUT_REG = 1'b0;

    wire signed [31:0] mul_prod = dsp_out[31:0];
    wire signed [33:0] prod_ext = {{2{mul_prod[31]}}, mul_prod};

    // True Dual Port Block RAM (DPB) for all Biquad Ringbuffer States & Coeffs (512 words of 1024 used)
    wire [31:0] doa_full, dob_full;
    wire [15:0] cpu_rdata_raw = doa_full[15:0];
    assign fsm_rdata = dob_full[15:0];

    DPB biquad_bram (
        .DOA(doa_full),
        .DOB(dob_full),
        .CLKA(clk), .OCEA(1'b0), .CEA(reg_cs), .RESETA(1'b0), .WREA(reg_wr),
        .CLKB(clk), .OCEB(1'b0), .CEB(1'b1),   .RESETB(1'b0), .WREB(fsm_we),
        .BLKSELA(3'b000), .BLKSELB(3'b000),
        .ADA({2'd0, cpu_addr, 2'b00, reg_be}),
        .ADB({1'b0, fsm_addr, 4'b0000}),
        .DIA(reg_wdata),
        .DIB(fsm_wdata)
    );
    defparam biquad_bram.READ_MODE0 = 1'b0;
    defparam biquad_bram.READ_MODE1 = 1'b0;
    defparam biquad_bram.WRITE_MODE0 = 2'b00;
    defparam biquad_bram.WRITE_MODE1 = 2'b00;
    defparam biquad_bram.BIT_WIDTH_0 = 16;
    defparam biquad_bram.BIT_WIDTH_1 = 16;
    defparam biquad_bram.RESET_MODE = "SYNC";

    assign reg_rdata = cpu_rdata_raw;

    // DSP Inputs: Compact enable-based mux
    always @(posedge clk) begin
        if (state == 4'd1) dsp_a <= proc_x;
        else if (!state[0] && (state <= 4'd8) && (state != 4'd0)) dsp_a <= fsm_rdata;

        if (state[0] && (state <= 4'd9)) dsp_b <= fsm_rdata;
    end

    // Accumulator: Only 3 active states
    always @(posedge clk) begin
        if (reset) acc <= 34'd0;
        else case (state)
            4'd2: acc <= prod_ext;
            4'd4, 4'd6: acc <= acc + prod_ext;
            4'd8, 4'd10: acc <= acc - prod_ext;
            default: ;
        endcase
    end

    // FSM State Transition: 4-bit Counter with dual-pass for Stereo
    always @(posedge clk) begin
        if (reset) begin
            state       <= 4'd0;
            proc_ch     <= 4'd0;
            proc_side   <= 1'b0;
            proc_stereo <= 1'b0;
            proc_flt_r  <= 1'b0;
            proc_x      <= 16'd0;
            proc_x_r    <= 16'd0;
            lat_x1      <= 16'd0;
            lat_y1      <= 16'd0;
        end else begin
            case (state)
                4'd0: begin
                    if (req_strobe && (filter_en_l || filter_en_r)) begin
                        proc_ch     <= cur_voice;
                        proc_stereo <= is_stereo;
                        proc_flt_r  <= filter_en_r;
                        proc_x_r    <= in_pcm_r;
                        if (filter_en_l) begin
                            proc_side <= 1'b0;
                            proc_x    <= in_pcm_l;
                            state     <= 4'd1;
                        end else begin
                            proc_side <= 1'b1;
                            proc_x    <= in_pcm_r;
                            state     <= 4'd1;
                        end
                    end
                end
                4'd2: begin
                    lat_x1 <= fsm_rdata;
                    state  <= 4'd3;
                end
                4'd6: begin
                    lat_y1 <= fsm_rdata;
                    state  <= 4'd7;
                end
                4'd14: begin
                    if (proc_side == 1'b0 && proc_stereo && proc_flt_r) begin
                        proc_side <= 1'b1;
                        proc_x    <= proc_x_r;
                        state     <= 4'd1;
                    end else begin
                        state     <= 4'd0;
                    end
                end
                default: state <= state + 1'b1;
            endcase
        end
    end

    // Output Selection: 0-cycle combinatorial multiplexer from y_held
    assign out_pcm_l = filter_en_l ? y_held_l[cur_voice] : in_pcm_l;
    assign out_pcm_r = filter_en_r ? y_held_r[cur_voice] : in_pcm_r;

endmodule
