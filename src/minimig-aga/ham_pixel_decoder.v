// Standalone reference-matched pixel engine, NOT a MiSTer integration.
// palette_data must belong to palette_index in the same input cycle.
// frame_start may coincide with the first valid pixel, or precede it.
// No state advance without pixel_valid; no reset at scanline boundaries.
module ham_pixel_decoder(
 input wire clk, reset_n, frame_start, pixel_valid,
 input wire [2:0] mode, // 1=HAM03, 2=HAM04, 3=HAM05, 4=HAM06, 5=HAM08
 input wire [7:0] code, step_r, step_g, step_b, palette_offset,
 output reg [7:0] palette_index,
 input wire [23:0] palette_data,
 output reg [23:0] rgb,
 output reg rgb_valid
);
reg [23:0] accumulator;
reg [23:0] base, next_rgb;
reg anchor, turbo, valid_mode;
reg signed [2:0] dr,dg,db;

function signed [2:0] two_delta;
 input [1:0] bits;
 begin case(bits)
  0:two_delta=-3'sd2; 1:two_delta=-3'sd1;
  2:two_delta=3'sd1; 3:two_delta=3'sd2;
 endcase end
endfunction

function [7:0] saturated;
 input [7:0] value, step;
 input signed [2:0] level;
 input turbo_on;
 reg signed [12:0] magnitude, delta, sum;
 begin
  magnitude=$signed({5'b0,step});
  if(turbo_on)magnitude=magnitude<<<2;
  case(level)
   -3'sd2:delta=-(magnitude<<<1);
   -3'sd1:delta=-magnitude;
   3'sd1:delta=magnitude;
   3'sd2:delta=magnitude<<<1;
   default:delta=0;
  endcase
  sum=$signed({5'b0,value})+delta;
  if(sum<0)saturated=0;
  else if(sum>255)saturated=255;
  else saturated=sum[7:0];
 end
endfunction

always @* begin
 anchor=0;turbo=0;valid_mode=1;dr=0;dg=0;db=0;palette_index=palette_offset;
 case(mode)
  1:begin
   anchor=~code[2];palette_index=palette_offset+{6'b0,code[1:0]};
   dr=code[1]?3'sd2:-3'sd2;dg=code[0]?3'sd2:-3'sd2;db=dr;
  end
  2:begin
   anchor=~code[3];palette_index=palette_offset+{5'b0,code[2:0]};
   dr=code[2]?3'sd2:-3'sd2;dg=code[1]?3'sd2:-3'sd2;db=code[0]?3'sd2:-3'sd2;
  end
  3:begin
   anchor=~code[4];turbo=code[3];palette_index=palette_offset+{4'b0,code[3:0]};
   dr=code[2]?3'sd1:-3'sd1;dg=code[1]?3'sd1:-3'sd1;db=code[0]?3'sd1:-3'sd1;
  end
  4:begin
   anchor=~code[5];turbo=code[4];palette_index=palette_offset+{3'b0,code[4:0]};
   dr=code[3]?3'sd1:-3'sd1;dg=two_delta(code[2:1]);db=code[0]?3'sd1:-3'sd1;
  end
  5:begin
   anchor=~code[7];turbo=code[6];palette_index=palette_offset+{1'b0,code[6:0]};
   dr=two_delta(code[5:4]);dg=two_delta(code[3:2]);db=two_delta(code[1:0]);
  end
  default:valid_mode=0;
 endcase
 base=frame_start?24'h7f7f7f:accumulator;
 if(anchor)next_rgb=palette_data;
 else next_rgb={saturated(base[23:16],step_r,dr,turbo),saturated(base[15:8],step_g,dg,turbo),saturated(base[7:0],step_b,db,turbo)};
end

always @(posedge clk or negedge reset_n)begin
 if(!reset_n)begin accumulator<=24'h7f7f7f;rgb<=0;rgb_valid<=0;end
 else begin
  rgb_valid<=pixel_valid&&valid_mode;
  if(frame_start)accumulator<=24'h7f7f7f;
  if(pixel_valid&&valid_mode)begin accumulator<=next_rgb;rgb<=next_rgb;end
 end
end
endmodule
