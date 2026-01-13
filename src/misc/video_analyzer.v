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
 input		  wide_screen, // wide screen jailbars enabled
 output reg       pal,         // pal mode detected
 output reg       short_frame, // short frame has two lines less
 output reg       interlace,   // interlace modes have one line less
 output reg	  vreset
);
   

// generate a reset signal in the upper left corner of active video used
// to synchonize the HDMI video generation to the Amiga
reg wide_screenD;
reg vsD, hsD;
reg [12:0] hcnt;    // signal ranges 0..2047
reg [12:0] hcntL;
reg [10:0] vcnt;    // signal ranges 0..625
reg [10:0] vcntL;
reg changed;

always @(posedge clk) begin
    // resync HDMI whenever wide screen setting changes
    wide_screenD <= wide_screen;   
    if(wide_screenD != wide_screen)
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
        hcnt <= hcnt + 13'd1;

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
    // HDMI frame
    if( hcnt == (120-(wide_screen?32:0)) && vcnt == 36 && changed) begin
        vreset <= 1'b1;
        changed <= 1'b0;
    end
end

endmodule
