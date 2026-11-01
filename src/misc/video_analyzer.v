//
// video_analyzer.v
//
// try to derive video parameters from hs/vs/de
//
// It also generates the control signals for the on-screen-display (osd_u8g2.v),
// so the OSD does not need to measure the video timing itself. The OSD window
// is placed at fixed positions that are derived from the PAL timing (908 x 626)
//

module video_analyzer
(
 // system interface
 input		  clk,
 input		  hs,
 input		  vs,
 input [1:0]      screen, // standard, overscan or wide screen jailbars enabled
 output reg       pal,         // pal mode detected
 output reg       short_frame, // short frame has two lines less
 output reg       interlace,   // interlace modes have one line less
 output reg	  vreset,

 // OSD control signals
 output reg       osd_active,  // inside OSD window incl. border
 output reg       osd_tactive, // inside text area of OSD
 output reg       osd_sactive, // inside shadow of OSD
 output [6:0]     osd_col,     // OSD bitmap column (2 pixels per column)
 output [5:0]     osd_row      // OSD bitmap row (2 lines per row)
);


// generate a reset signal in the upper left corner of active video used
// to synchonize the HDMI video generation to the Amiga
reg [1:0] screenD;
reg vsD, hsD;
reg [10:0] hcnt;    // signal ranges 0..2047
reg [10:0] hcntL;
reg [10:0] vcnt;    // signal ranges 0..625
reg [10:0] vcntL;
reg changed;

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
        if(hcntL != hcnt)
            changed <= 1'b1;

        hcnt <= 0;
    end else
        hcnt <= hcnt + 11'd1;

    if(!hs && hsD) begin
        // ---- vsync processing -----
        vsD <= vs;
        // begin of vsync, falling edge
        if(!vs && vsD) begin
            // check if image height has changed during last cycle
            vcntL <= vcnt;
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
    if( hcnt == ((screen==2'd2)?88:(screen==2'd1)?120:162) && vcnt == 46 && changed) begin
        vreset <= 1'b1;
        changed <= 1'b0;
    end
end

// ------------------------- OSD control signals ---------------------------

// The OSD is 128x64 pixels, shown with a scale of 2 (256 x 128 clk/lines) plus
// a border of 4 and a shadow offset of 8. It is placed at fixed positions
// derived from the PAL timing, the same positions are used for NTSC.
//
// All window edges are multiples of 4 and the OSD text area starts at
// hcnt 384 and vcnt 256, which are multiples of 128. The window limits thus
// only depend on hcnt[10:2] and vcnt[10:2] and the bitmap position inside
// the OSD can be taken directly from the lower bits of hcnt and vcnt.
//
// text area:   hcnt 384..639  vcnt 256..383
// border:      4 around the text area
// shadow:      text area + border moved by 8 (right/down)
//
// The OSD displays the pixel for hcnt one clock later (registered flags,
// registered bitmap byte), thus the horizontal column is that of hcnt+1.
// Subtracting 384 from hcnt+1 only inverts bit 7.

wire [8:0] hg = hcnt[10:2];
wire [8:0] vg = vcnt[10:2];

assign osd_col = { !hcnt[7], hcnt[6:1] };
assign osd_row = vcnt[6:1];

// vertical windows, change only once per line
reg vact, vsact;
wire vtact = vcnt[10:7] == 4'd2;

always @(posedge clk) begin
    if(vg == 9'd63)       vact  <= 1'b1;     // vcnt 252..387
    else if(vg == 9'd97)  vact  <= 1'b0;
    if(vg == 9'd65)       vsact <= 1'b1;     // vcnt 260..395
    else if(vg == 9'd99)  vsact <= 1'b0;
end

// horizontal windows, flags are only set inside the vertical window. The
// flags are registered, so they are active one clock after the hcnt that
// is compared here.
always @(posedge clk) begin
    if(hg == 9'd95)       osd_active  <= vact;   // hcnt 380..643
    else if(hg == 9'd161) osd_active  <= 1'b0;
    if(hg == 9'd96)       osd_tactive <= vtact;  // hcnt 384..639
    else if(hg == 9'd160) osd_tactive <= 1'b0;
    if(hg == 9'd97)       osd_sactive <= vsact;  // hcnt 388..651
    else if(hg == 9'd163) osd_sactive <= 1'b0;
end

endmodule
