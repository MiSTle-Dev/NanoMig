//
// video_analyzer.v
//
// try to derive video parameters from hs/vs/de
//

module video_analyzer 
(
 // system interface
 input		  clk,
 input		  hs,
 input		  vs,
 input [1:0]      screen, // standard, overscan or wide screen jailbars enabled
`ifdef VID31_PASSTHROUGH
 input            fast,   // 31 kHz pass-through: hs/vs are the raw Amiga sync
 input            geo,        // pass-through placed by the Amiga's blanking
 input            geo_start,  // one clock: first visible pixel of the frame
 input [31:0]     geo_size,   // measured picture geometry, only compared
 output reg [10:0] hlen,       // measured clocks per line
 output reg [9:0]  vlen,       // measured lines per frame
`endif
 output reg       pal,         // pal mode detected
 output reg       short_frame, // short frame has two lines less
 output reg       interlace,   // interlace modes have one line less
 output reg	  vreset
);
   

// generate a reset signal in the upper left corner of active video used
// to synchonize the HDMI video generation to the Amiga
reg [1:0] screenD;
reg vsD, hsD;
reg [12:0] hcnt;    // signal ranges 0..2047
reg [12:0] hcntL;
reg [10:0] vcnt;    // signal ranges 0..625
reg [10:0] vcntL;
reg changed;
reg [31:0] geo_sizeL;
reg geoD;

// where the HDMI frame starts, counted from the Amiga sync edges.
// 31 kHz pass-through (fast): estimated from two photos of DblPAL on 2026-11-13,
// 127 clocks later and 31 lines earlier than the scandoubled PAL values.
`ifndef VID31_PASSTHROUGH
// no pass-through in this build: the inputs are tied off
wire        fast = 1'b0;
wire        geo = 1'b0;
wire        geo_start = 1'b0;
wire [31:0] geo_size = 32'd0;
`endif
wire [12:0] hstart = fast ? ((screen==2'd2)?13'd215:(screen==2'd1)?13'd247:13'd289)
                          : ((screen==2'd2)?13'd88 :(screen==2'd1)?13'd120:13'd162);
wire [10:0] vstart = fast ? 11'd15 : 11'd46;

always @(posedge clk) begin
    // resync HDMI whenever screen setting changes
    screenD <= screen;   
    if(screenD != screen)
        changed <= 1'b1;   
   
    // ---- hsync processing -----
    hsD <= hs;

    // begin of hsync, falling edge
    if(!hs && hsD) begin
        // check if line length has changed during last cycle
        hcntL <= hcnt;
`ifdef VID31_PASSTHROUGH
        hlen <= hcnt[10:0] + 11'd1;
`endif
        if(hcntL != hcnt)
            changed <= 1'b1;

        hcnt <= 0;
    end else
        hcnt <= hcnt + 13'd1;

    if(!hs && hsD) begin
        // ---- vsync processing -----
        vsD <= vs;
        // begin of vsync, falling edge
        if(!vs && vsD) begin
            // check if image height has changed during last cycle
            vcntL <= vcnt;
`ifdef VID31_PASSTHROUGH
            vlen <= vcnt[9:0] + 10'd1;
`endif
            if(vcntL != vcnt) begin
                if(vcnt == 11'd523) begin
                    pal <= 1'b0; // NTSC
                    short_frame <= 1'b1;
                end
                if(vcnt == 11'd524 || vcnt == 11'd525) begin
                    pal <= 1'b0; // NTSC
                    short_frame <= 1'b0;
                end
                if(vcnt == 11'd623) begin
                    pal <= 1'b1; // PAL
                    short_frame <= 1'b1;
                end
                if(vcnt == 11'd624 || vcnt == 11'd625) begin
                    pal <= 1'b1; // PAL
                    short_frame <= 1'b0;
                end

                interlace <= !vcnt[0];

                changed <= 1'b1;
            end

            vcnt <= 0;
        end else
            vcnt <= vcnt + 11'd1;
    end

    // the reset signal is sent to the HDMI generator. On reset the
    // HDMI re-adjusts its counters to the start of the visible screen
    // area
   
    vreset <= 1'b0;
    // account for back porches to adjust image position within the
    // HDMI frame. Center screen according to screen type standard (0),
    // overscan (1) or wide (2)
    if(geo) begin
        // start the HDMI frame on the first visible Amiga pixel, once the
        // measured picture size is the same two frames in a row
        if(geo_start) begin
            geo_sizeL <= geo_size;
            if(geo_sizeL != geo_size)
                changed <= 1'b1;
            else if(changed) begin
                vreset <= 1'b1;
                changed <= 1'b0;
            end
        end
    end else if( hcnt == hstart && vcnt == vstart && changed) begin
        vreset <= 1'b1;
        changed <= 1'b0;
    end

    // resync when the placement method changes
    geoD <= geo;
    if(geoD != geo)
        changed <= 1'b1;
end

endmodule
