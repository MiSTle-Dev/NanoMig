// SPDX-License-Identifier: GPL-3.0-or-later
// 16-Channel 2nd-Order Biquad IIR Filter Engine with Simple Dual-Port RAM Architecture & Single-DSP Sharing.
// Supports independent Left/Right channel filtering (AUDxCTRL bits 8..7: 00=off, 01=R, 10=L, 11=both).
// Portable Standard Verilog implementation for Altera/Intel Cyclone V (MiSTer).

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

    // CPU word address for coefficients: 16 voices x 8 words (0..4 used) = 128 words
    wire [6:0] cpu_coeff_addr = {ch, coeff_idx[2:0]};

    // Sequential Biquad FSM
    reg [3:0] state;
    reg [3:0] proc_ch;
    reg       proc_side;     // 0 = Left (or Mono), 1 = Right
    reg       proc_stereo;
    reg       proc_flt_r;
    reg signed [15:0] proc_x;
    reg signed [15:0] proc_x_r;
    reg signed [33:0] acc;

    // Latches for state pipeline
    reg signed [15:0] lat_x1, lat_y1;

    // Saturation logic for Biquad output (Q2.14)
    wire signed [19:0] y_sc = acc[33:14];
    wire signed [15:0] y_sat = (!y_sc[19] && |y_sc[18:15]) ? 16'sh7FFF :
                               ( y_sc[19] && !(&y_sc[18:15])) ? 16'sh8000 : y_sc[15:0];

    // 16 Output values stored in register array
    reg signed [15:0] y_held_l [0:15];
    reg signed [15:0] y_held_r [0:15];

    wire we_l = (state == 4'd13) && (proc_side == 1'b0);
    wire we_r = (state == 4'd13) && (proc_side == 1'b1 || !proc_stereo);

    always @(posedge clk) begin
        if (we_l) y_held_l[proc_ch] <= y_sat;
        if (we_r) y_held_r[proc_ch] <= y_sat;
    end

    // --- 1. Coefficient RAM (Simple Dual-Port: CPU writes, FSM reads) ---
    // 128 entries of 16-bit
    reg [15:0] coeff_ram [0:127];
    reg [15:0] cpu_rdata_raw;
    reg [15:0] fsm_coeff_rdata;

    wire [6:0] fsm_coeff_addr = {(state == 4'd0 ? cur_voice : proc_ch), state[3:1]};

    always @(posedge clk) begin
        if (reg_cs && reg_wr) begin
            if (reg_be[1]) coeff_ram[cpu_coeff_addr][15:8] <= reg_wdata[15:8];
            if (reg_be[0]) coeff_ram[cpu_coeff_addr][ 7:0] <= reg_wdata[ 7:0];
        end
        cpu_rdata_raw   <= coeff_ram[cpu_coeff_addr];
        fsm_coeff_rdata <= coeff_ram[fsm_coeff_addr];
    end
    assign reg_rdata = cpu_rdata_raw;

    // --- 2. State RAM (Simple Dual-Port: FSM writes, FSM reads) ---
    // 128 entries of 16-bit: {side, ch[3:0], var[1:0]}
    // var: 0=x1, 1=x2, 2=y1, 3=y2
    reg [15:0] state_ram [0:127];
    reg [15:0] fsm_state_rdata;

    wire [6:0] fsm_state_rd_addr = {proc_side, (state == 4'd1 ? cur_voice : proc_ch), state[2:1]};

    wire [1:0] fsm_wr_var = (state == 4'd10) ? 2'd1 : // x2 <= lat_x1
                            (state == 4'd11) ? 2'd0 : // x1 <= proc_x
                            (state == 4'd12) ? 2'd3 : // y2 <= lat_y1
                                               2'd2;  // y1 <= y_sat
    wire [6:0] fsm_state_wr_addr = {proc_side, proc_ch, fsm_wr_var};
    wire [15:0] fsm_state_wdata  = (state == 4'd10) ? lat_x1 :
                                   (state == 4'd11) ? proc_x  :
                                   (state == 4'd12) ? lat_y1  :
                                                      y_sat;
    wire fsm_state_we = (state >= 4'd10 && state <= 4'd13);

    always @(posedge clk) begin
        if (fsm_state_we) begin
            state_ram[fsm_state_wr_addr] <= fsm_state_wdata;
        end
        fsm_state_rdata <= state_ram[fsm_state_rd_addr];
    end

    // Mux between Coeff data (even states) and State data (odd states)
    wire [15:0] fsm_rdata = state[0] ? fsm_state_rdata : fsm_coeff_rdata;

    // --- 3. Single DSP Multiplier ---
    reg signed [15:0] dsp_a;
    reg signed [15:0] dsp_b;
    wire signed [31:0] mul_prod = dsp_a * dsp_b;
    wire signed [33:0] prod_ext = {{2{mul_prod[31]}}, mul_prod};

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

                4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8, 4'd9: begin
                    if (state == 4'd2) lat_x1 <= fsm_rdata;
                    if (state == 4'd6) lat_y1 <= fsm_rdata;
                    state <= state + 1'b1;
                end

                4'd10, 4'd11, 4'd12: begin
                    state <= state + 1'b1;
                end

                4'd13: begin
                    if (!proc_side && proc_stereo && proc_flt_r) begin
                        proc_side <= 1'b1;
                        proc_x    <= proc_x_r;
                        state     <= 4'd1; // Second pass for Right Stereo channel
                    end else begin
                        state <= 4'd0;     // Finished processing
                    end
                end

                default: state <= 4'd0;
            endcase
        end
    end

    // Direct bypass selection: If filter disabled, pass raw in_pcm directly
    assign out_pcm_l = filter_en_l ? y_held_l[cur_voice] : in_pcm_l;
    assign out_pcm_r = filter_en_r ? y_held_r[cur_voice] : in_pcm_r;

endmodule
