// SPDX-License-Identifier: GPL-3.0-or-later
// Streamlined Pipelined ADPCM Engine for NanoMig Ringbuffer Architecture.
// Takes {in_pcm, in_index, code, bps} -> outputs {out_pcm, out_index} in 1 clock cycle.
// Uses 1 BSRAM block for the 89-entry step table. 0 internal channel RAMs!

module adpcm_decoder_shared (
    input  wire               clk,
    input  wire               rst,
    
    // Cycle 0 Input
    input  wire               req_valid,
    input  wire signed [15:0] in_pcm,
    input  wire [6:0]         in_index,
    input  wire [4:0]         code,
    input  wire [2:0]         bits_per_code,

    // Cycle 1 Output (directly into DSP mixer and back into ringbuffer)
    output reg  signed [15:0] out_pcm,
    output reg  [6:0]         out_index
);

    // Constant ROM in BSRAM: 89 unsigned 16-bit step sizes
    (* syn_ramstyle = "block_ram" *) reg [15:0] step_rom [0:127];
    initial begin
        step_rom[0]=7; step_rom[1]=8; step_rom[2]=9; step_rom[3]=10; step_rom[4]=11; step_rom[5]=12; step_rom[6]=13; step_rom[7]=14; step_rom[8]=16;
        step_rom[9]=17; step_rom[10]=19; step_rom[11]=21; step_rom[12]=23; step_rom[13]=25; step_rom[14]=28; step_rom[15]=31; step_rom[16]=34;
        step_rom[17]=37; step_rom[18]=41; step_rom[19]=45; step_rom[20]=50; step_rom[21]=55; step_rom[22]=60; step_rom[23]=66; step_rom[24]=73;
        step_rom[25]=80; step_rom[26]=88; step_rom[27]=97; step_rom[28]=107; step_rom[29]=118; step_rom[30]=130; step_rom[31]=143; step_rom[32]=157;
        step_rom[33]=173; step_rom[34]=190; step_rom[35]=209; step_rom[36]=230; step_rom[37]=253; step_rom[38]=279; step_rom[39]=307; step_rom[40]=337;
        step_rom[41]=371; step_rom[42]=408; step_rom[43]=449; step_rom[44]=494; step_rom[45]=544; step_rom[46]=598; step_rom[47]=658; step_rom[48]=724;
        step_rom[49]=796; step_rom[50]=876; step_rom[51]=963; step_rom[52]=1060; step_rom[53]=1166; step_rom[54]=1282; step_rom[55]=1411; step_rom[56]=1552;
        step_rom[57]=1707; step_rom[58]=1878; step_rom[59]=2066; step_rom[60]=2272; step_rom[61]=2499; step_rom[62]=2749; step_rom[63]=3024; step_rom[64]=3327;
        step_rom[65]=3660; step_rom[66]=4026; step_rom[67]=4428; step_rom[68]=4871; step_rom[69]=5358; step_rom[70]=5894; step_rom[71]=6484; step_rom[72]=7132;
        step_rom[73]=7845; step_rom[74]=8630; step_rom[75]=9493; step_rom[76]=10442; step_rom[77]=11487; step_rom[78]=12635; step_rom[79]=13899; step_rom[80]=15289;
        step_rom[81]=16818; step_rom[82]=18500; step_rom[83]=20350; step_rom[84]=22385; step_rom[85]=24623; step_rom[86]=27086; step_rom[87]=29794; step_rom[88]=32767;
    end

    // Pipeline Stage 1 registers
    reg p1_valid;
    reg [4:0] p1_code;
    reg [2:0] p1_bps;
    reg signed [15:0] p1_pred;
    reg [6:0] p1_index;
    reg [15:0] p1_step;

    always @(posedge clk) begin
        p1_step <= (in_index <= 7'd88) ? step_rom[in_index] : 16'd32767;
        p1_valid <= req_valid && !rst;
        p1_code <= code;
        p1_bps <= bits_per_code;
        p1_pred <= in_pcm;
        p1_index <= in_index;
    end

    // Pipeline Stage 2: Arithmetic
    wire [2:0] sh = (p1_bps == 3'd2) ? 3'd1 :
                    (p1_bps == 3'd3) ? 3'd2 :
                    (p1_bps == 3'd4) ? 3'd3 : 3'd4;
    wire negative = (p1_bps == 3'd2) ? p1_code[1] :
                    (p1_bps == 3'd3) ? p1_code[2] :
                    (p1_bps == 3'd4) ? p1_code[3] : p1_code[4];
    wire [3:0] mag = (p1_bps == 3'd2) ? {3'b0, p1_code[0]} :
                     (p1_bps == 3'd3) ? {2'b0, p1_code[1:0]} :
                     (p1_bps == 3'd4) ? {1'b0, p1_code[2:0]} : p1_code[3:0];

    // DSP multiplier for exact delta: delta = (p1_step * ((mag << 1) | 1)) >> sh
    wire [20:0] mult_val = p1_step * {mag, 1'b1};
    wire [16:0] delta = mult_val >> sh;

    reg signed [5:0] index_delta;
    always @* begin
        case (p1_bps)
            3'd2: index_delta = p1_code[0] ? 6'sd2 : -6'sd1;
            3'd3: case (p1_code[1:0])
                2: index_delta = 6'sd1;
                3: index_delta = 6'sd2;
                default: index_delta = -6'sd1;
            endcase
            3'd4: case (p1_code[2:0])
                4: index_delta = 6'sd2;
                5: index_delta = 6'sd4;
                6: index_delta = 6'sd6;
                7: index_delta = 6'sd8;
                default: index_delta = -6'sd1;
            endcase
            3'd5: case (p1_code[3:0])
                8:  index_delta = 6'sd1;
                9:  index_delta = 6'sd2;
                10: index_delta = 6'sd4;
                11: index_delta = 6'sd6;
                12: index_delta = 6'sd8;
                13: index_delta = 6'sd10;
                14: index_delta = 6'sd13;
                15: index_delta = 6'sd16;
                default: index_delta = -6'sd1;
            endcase
            default: index_delta = -6'sd1;
        endcase
    end

    wire signed [8:0] next_index = $signed({2'b00, p1_index}) + index_delta;
    wire signed [17:0] next_pcm = negative ?
        ($signed({{2{p1_pred[15]}}, p1_pred}) - $signed({1'b0, delta})) :
        ($signed({{2{p1_pred[15]}}, p1_pred}) + $signed({1'b0, delta}));

    wire pos_ovf = !next_pcm[17] && (|next_pcm[16:15]);
    wire neg_ovf =  next_pcm[17] && (!(&next_pcm[16:15]));
    wire signed [15:0] sat_pcm = pos_ovf ? 16'sh7fff : (neg_ovf ? 16'sh8000 : next_pcm[15:0]);

    reg [6:0] sat_index;
    always @* begin
        if (next_index[8]) sat_index = 7'd0;
        else if (next_index > 88) sat_index = 7'd88;
        else sat_index = next_index[6:0];
    end

    always @(posedge clk) begin
        if (rst) begin
            out_pcm <= 16'd0;
            out_index <= 7'd0;
        end else if (p1_valid) begin
            out_pcm <= sat_pcm;
            out_index <= sat_index;
        end
    end

endmodule
