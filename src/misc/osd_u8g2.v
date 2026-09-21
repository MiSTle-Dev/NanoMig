/*
    osd_u8g2.v
 
    on-screen-display using a memory layout that matches the 
    one of 128x64 OLED displays and is thus supported by u8g2
  */

module osd_u8g2 (
  input        clk,
  input        reset,

  input        data_in_strobe,
  input        data_in_start,
  input [7:0]  data_in,
	    
  input        hs,
  input        vs, 
  input [5:0]  r_in,
  input [5:0]  g_in,
  input [5:0]  b_in,

  output [5:0] r_out,
  output [5:0] g_out,
  output [5:0] b_out
);

// the OSD is inserted behind the scan doubler and thus deals with
// the higher pixel clock and twice the lines
localparam HCNT_BITS = 12;   
localparam VCNT_BITS = 10;      

// OSD is enabled and visible
reg enabled;

// -------------------------- OSD painting -------------------------------

reg vsD, hsD;
reg [HCNT_BITS-1:0] hcnt;       // signal ranges 0..1023
reg [HCNT_BITS-1:0] scr_width;
reg [VCNT_BITS-1:0] vcnt;       // signal ranges 0..626
reg [VCNT_BITS-1:0] scr_height;

// OSD is active on current pixel, the shadow is active or the text area is active
reg  active, tactive;

// disabling the shadow saves some LUTs
`ifndef OSD_NO_SHADOW   
reg sactive;
`else
wire sactive = 1'b0;
`endif   

wire	   osd_pix;  
wire [5:0] osd_pix_col;

// background shines through less where "shadow" is active
wire [5:0] osd_r = (tactive && osd_pix)?osd_pix_col:sactive?{4'b0000, r_in[5:4]}:{3'b000, r_in[5:3]};
wire [5:0] osd_g = (tactive && osd_pix)?osd_pix_col:sactive?{4'b0000, g_in[5:4]}:{3'b000, g_in[5:3]};
wire [5:0] osd_b = (tactive && osd_pix)?osd_pix_col:sactive?{4'b0100, b_in[5:4]}:{3'b010, b_in[5:3]};  
   
// draw active osd, add some shadow to those parts outside osd
// that are covered by shadow
assign r_out = !enabled?r_in:active?osd_r:sactive?{1'b0, r_in[5:1]}:r_in;
assign g_out = !enabled?g_in:active?osd_g:sactive?{1'b0, g_in[5:1]}:g_in;
assign b_out = !enabled?b_in:active?osd_b:sactive?{1'b0, b_in[5:1]}:b_in;   

`define BORDER 2
`define SHADOW 4
`define SCALE  2
`define WIDTH 16   // OSD width in 8 pixel wide characters
`define HEIGHT 8   // OSD height in 8 pixel tall characters

// make sure OSD is centered
wire [HCNT_BITS-1:0] hstart = {1'b0, scr_width[HCNT_BITS-1:1]}-8*`WIDTH*`SCALE/2;
wire [VCNT_BITS-1:0] vstart = {1'b0, scr_height[VCNT_BITS-1:1]}-8*`HEIGHT*`SCALE/2;

always @(posedge clk) begin
   // entire OSD area incl border
   active <= hcnt >= hstart-`SCALE*`BORDER-1 && 
	     hcnt < hstart+`SCALE*`BORDER+8*`WIDTH*`SCALE-1 &&
	     vcnt >= vstart-`SCALE*`BORDER && 
	     vcnt < vstart+`SCALE*`BORDER+8*`HEIGHT*`SCALE;
   
   // text area of OSD
   tactive <= hcnt >= hstart-1 && 
	      hcnt < hstart+8*`WIDTH*`SCALE-1 &&
	      vcnt >= vstart && 
	      vcnt < vstart+8*`HEIGHT*`SCALE;

`ifndef OSD_NO_SHADOW   
   // shadow area of OSD
   sactive <= hcnt >= hstart-`SCALE*`BORDER+`SCALE*`SHADOW-1 &&
	      hcnt < hstart+`SCALE*`BORDER+`SCALE*`SHADOW+8*`WIDTH*`SCALE-1 &&
	      vcnt >= vstart-`SCALE*`BORDER+`SCALE*`SHADOW &&
	      vcnt < vstart+`SCALE*`BORDER+`SCALE*`SHADOW+8*`HEIGHT*`SCALE;
`endif
end
   
// 1024 bytes = 8192 pixels = 128 x 64 pixels
reg [7:0] buffer [1024];  

// external data interface to write to buffer
reg [9:0] data_cnt;
reg [7:0] command;
reg data_addr_state;
   
always @(posedge clk) begin
    if(reset) begin
        enabled <= 1'b0;

    end else begin

      if(data_in_strobe) begin
        if(data_in_start) begin
            command <= data_in;
            data_addr_state <= 1'b1;
            data_cnt <= 10'd0;
        end else begin
            data_addr_state <= 1'b0;

            // OSD command 1: enabled (show) or disable (hide) OSD
            if((command == 8'd1) && data_addr_state)
                enabled <= data_in[0];   // en/disable

            // OSD command 2: display data for give tile
            if(command == 8'd2) begin
                if(data_addr_state)
                    data_cnt <= { data_in[6:0], 3'b000 };
                else begin	 
                    buffer[data_cnt] <= data_in;
                    data_cnt <= data_cnt + 10'd1;
                end
            end
         end
      end
   end
end
   
wire [7:0] hpix  = hcnt-hstart;  // horizontal pixel position inside OSD   
wire [7:0] hpixD = hpix+1;       // latch byte one pixel in advance
wire [6:0] vpix  = vcnt-vstart;  // vertical pixel position inside OSD   

reg [7:0] buffer_byte;
assign osd_pix = buffer_byte[vpix[3:1]];
always @(posedge clk)
    buffer_byte <= buffer[{ vpix[6:4], hpixD[7:1] }];
   
assign osd_pix_col = 6'd63;

// -------------------------- video signal analysis -------------------------
   
// analyze video timing to determine center of screen
always @(posedge clk) begin
   // ---- hsync processing -----
   hsD <= hs;

   // end of hsync, rising edge
   if(hs && !hsD) begin
      scr_width <= hcnt;
      hcnt <= 0;
   end else
     hcnt <= hcnt + 12'd1;
   
   if(hs && !hsD) begin
      // ---- vsync processing -----
      vsD <= vs;
      // begin of vsync, falling edge
      if(!vs && vsD) begin
         scr_height <= vcnt;
         vcnt <= 0;
      end else
        vcnt <= vcnt + 10'd1;
   end
end
   
endmodule
