// ADPX generalized IMA decoder. All shifts round individually, matching the
// integer software reference. One code is accepted on each enabled clock.
module adpcm_decoder (
    input wire clk,
    input wire rst,
    input wire load_state,
    input wire signed [15:0] initial_pcm,
    input wire [6:0] initial_index,
    input wire code_valid,
    input wire [4:0] code,
    input wire [2:0] bits_per_code,
    output reg sample_valid,
    output reg signed [15:0] sample,
    output wire signed [15:0] state_pcm,
    output wire [6:0] state_index,
    output reg code_error
);
    reg signed [15:0] predictor;
    reg [6:0] index;
    reg [15:0] step;
    reg [16:0] delta;
    reg negative;
    reg legal_mode;
    reg signed [5:0] index_delta;
    reg signed [8:0] next_index;
    reg signed [17:0] next_pcm;

    assign state_pcm = predictor;
    assign state_index = index;

    // Constant ROM, 89 unsigned 16-bit step sizes.
    always @* begin
        case (index)
             0: step=7;      1: step=8;      2: step=9;
             3: step=10;     4: step=11;     5: step=12;
             6: step=13;     7: step=14;     8: step=16;
             9: step=17;    10: step=19;    11: step=21;
            12: step=23;    13: step=25;    14: step=28;
            15: step=31;    16: step=34;    17: step=37;
            18: step=41;    19: step=45;    20: step=50;
            21: step=55;    22: step=60;    23: step=66;
            24: step=73;    25: step=80;    26: step=88;
            27: step=97;    28: step=107;   29: step=118;
            30: step=130;   31: step=143;   32: step=157;
            33: step=173;   34: step=190;   35: step=209;
            36: step=230;   37: step=253;   38: step=279;
            39: step=307;   40: step=337;   41: step=371;
            42: step=408;   43: step=449;   44: step=494;
            45: step=544;   46: step=598;   47: step=658;
            48: step=724;   49: step=796;   50: step=876;
            51: step=963;   52: step=1060;  53: step=1166;
            54: step=1282;  55: step=1411;  56: step=1552;
            57: step=1707;  58: step=1878;  59: step=2066;
            60: step=2272;  61: step=2499;  62: step=2749;
            63: step=3024;  64: step=3327;  65: step=3660;
            66: step=4026;  67: step=4428;  68: step=4871;
            69: step=5358;  70: step=5894;  71: step=6484;
            72: step=7132;  73: step=7845;  74: step=8630;
            75: step=9493;  76: step=10442; 77: step=11487;
            78: step=12635; 79: step=13899; 80: step=15289;
            81: step=16818; 82: step=18500; 83: step=20350;
            84: step=22385; 85: step=24623; 86: step=27086;
            87: step=29794; 88: step=32767;
            default: step=32767;
        endcase
    end

    always @* begin
        legal_mode = 1'b1;
        delta = 0;
        negative = 0;
        index_delta = -1;
        case (bits_per_code)
            3'd2: begin
                negative = code[1];
                delta = {1'b0,step} >> 1;
                if (code[0]) begin
                    delta = delta + {1'b0,step};
                    index_delta = 2;
                end
            end
            3'd3: begin
                negative = code[2];
                delta = {1'b0,step} >> 2;
                if (code[0]) delta = delta + ({1'b0,step} >> 1);
                if (code[1]) delta = delta + {1'b0,step};
                case (code[1:0])
                    2: index_delta = 1;
                    3: index_delta = 2;
                    default: index_delta = -1;
                endcase
            end
            3'd4: begin
                negative = code[3];
                delta = {1'b0,step} >> 3;
                if (code[0]) delta = delta + ({1'b0,step} >> 2);
                if (code[1]) delta = delta + ({1'b0,step} >> 1);
                if (code[2]) delta = delta + {1'b0,step};
                case (code[2:0])
                    4: index_delta = 2;
                    5: index_delta = 4;
                    6: index_delta = 6;
                    7: index_delta = 8;
                    default: index_delta = -1;
                endcase
            end
            3'd5: begin
                negative = code[4];
                delta = {1'b0,step} >> 4;
                if (code[0]) delta = delta + ({1'b0,step} >> 3);
                if (code[1]) delta = delta + ({1'b0,step} >> 2);
                if (code[2]) delta = delta + ({1'b0,step} >> 1);
                if (code[3]) delta = delta + {1'b0,step};
                case (code[3:0])
                     8: index_delta = 1;
                     9: index_delta = 2;
                    10: index_delta = 4;
                    11: index_delta = 6;
                    12: index_delta = 8;
                    13: index_delta = 10;
                    14: index_delta = 13;
                    15: index_delta = 16;
                    default: index_delta = -1;
                endcase
            end
            default: legal_mode = 1'b0;
        endcase
        next_index = $signed({2'b00,index}) + index_delta;
        if (negative)
            next_pcm = $signed({{2{predictor[15]}},predictor}) - $signed({1'b0,delta});
        else
            next_pcm = $signed({{2{predictor[15]}},predictor}) + $signed({1'b0,delta});
    end

    always @(posedge clk) begin
        sample_valid <= 1'b0;
        code_error <= 1'b0;
        if (rst) begin
            predictor <= 0;
            index <= 0;
            sample <= 0;
        end else if (load_state) begin
            predictor <= initial_pcm;
            index <= (initial_index > 88) ? 7'd88 : initial_index;
        end else if (code_valid) begin
            if (!legal_mode) begin
                code_error <= 1'b1;
            end else begin
                sample_valid <= 1'b1;
                if (next_pcm > 18'sd32767) begin
                    predictor <= 16'sh7fff;
                    sample <= 16'sh7fff;
                end else if (next_pcm < -18'sd32768) begin
                    predictor <= 16'sh8000;
                    sample <= 16'sh8000;
                end else begin
                    predictor <= next_pcm[15:0];
                    sample <= next_pcm[15:0];
                end
                if (next_index < 0) index <= 0;
                else if (next_index > 88) index <= 88;
                else index <= next_index[6:0];
            end
        end
    end
endmodule
