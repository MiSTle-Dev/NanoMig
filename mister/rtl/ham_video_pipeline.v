// One-clock synchronous palette followed by the verified pixel engine.
// Input valid marks ONE unique pixel, never repeated clk28 samples.
module ham_video_pipeline(
 input wire clk,reset,frame_start,pixel_valid,
 input wire [3:0] planes,
 input wire [7:0] code,
 input wire [15:0] control,
 input wire clk7_en,
 input wire [8:1] reg_address_in,
 input wire [11:0] data_in,
 input wire [2:0] bank,
 input wire loct,rdram,
 output wire [23:0] rgb,
 output wire rgb_valid
);
reg [2:0] mode;
reg [7:0] index;
always @* begin
 mode=0;index=0;
 if(control[15])case(planes)
 3:begin mode=1;index={6'b0,code[1:0]};end
 4:begin mode=2;index={5'b0,code[2:0]};end
 5:begin mode=3;index={4'b0,code[3:0]};end
 6:begin mode=4;index={3'b0,code[4:0]};end
 8:begin mode=5;index={1'b0,code[6:0]};end
 default:begin mode=0;index=0;end
 endcase
end
wire [31:0] q;
denise_colortable_ram_mf palette(
 .clock(clk),.enable(1'b1),.wraddress({bank,reg_address_in[5:1]}),
 .wren(clk7_en && !rdram && reg_address_in[8:6]==3'b110),
 .byteena_a(loct?4'b0011:4'b1111),.data({4'b0,data_in,4'b0,data_in}),
 .rdaddress(index),.q(q));
wire [23:0] color={q[27:24],q[11:8],q[23:20],q[7:4],q[19:16],q[3:0]};
reg [7:0] code_d;
reg [2:0] mode_d;
reg [15:0] control_d;
reg valid_d,frame_d;
always @(posedge clk)begin
 if(reset)begin valid_d<=0;frame_d<=0;code_d<=0;mode_d<=0;control_d<=16'h1084;end
 else begin
  code_d<=code;mode_d<=mode;control_d<=control;
  valid_d<=pixel_valid && mode!=0;frame_d<=frame_start;
 end
end
wire [7:0] unused_index;
ham_pixel_decoder engine(.clk(clk),.reset_n(!reset),.frame_start(frame_d),
 .pixel_valid(valid_d),.mode(mode_d),.code(code_d),
 .step_r({3'b0,control_d[14:10]}),.step_g({3'b0,control_d[9:5]}),
 .step_b({3'b0,control_d[4:0]}),.palette_offset(8'b0),
 .palette_index(unused_index),.palette_data(color),.rgb(rgb),.rgb_valid(rgb_valid));
endmodule
