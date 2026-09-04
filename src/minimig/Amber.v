// Copyright 2006, 2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
//
// This is Amber 
// Amber is a scandoubler to allow connection to a VGA monitor. 
// In addition, it can overlay an OSD (on-screen-display) menu.
// Amber also has a pass-through mode in which
// the video output can be connected to an RGB SCART input.
// The meaning of _hsync_out and _vsync_out is then:
// _vsync_out is fixed high (for use as RGB enable on SCART input).
// _hsync_out is composite sync output.
//
// 10-01-2006	- first serious version
// 11-01-2006	- done lot's of work, Amber is now finished
// 29-12-2006	- added support for OSD overlay
// ----------
// JB:
// 2008-02-26	- synchronous 28 MHz version
// 2008-02-28	- horizontal and vertical interpolation
// 2008-02-02	- hfilter/vfilter inputs added, unused inputs removed
// 2008-12-12	- useless scanline effect implemented
// 2008-12-27	- clean-up
// 2009-05-24	- clean-up & renaming
// 2009-08-31	- scanlines synthesis option
// 2010-05-30	- htotal changed

`define SCANLINES

module Amber
(	
	input 	clk28m,
	input	[1:0] lr_filter,		//interpolation filters settings for low resolution
	input	[1:0] hr_filter,		//interpolation filters settings for high resolution
	input	[1:0] scanline,			//scanline effect enable
	input	[8:1] htotal,			//video line length
	input	hires,				//display is in hires mode (from bplcon0)
	input	dblscan,			//enable VGA output (enable scandoubler)
	input 	[3:0] red_in, 			//red componenent video in
	input 	[3:0] green_in,  		//green component video in
	input 	[3:0] blue_in,			//blue component video in
	input	_hsync_in,			//horizontal synchronisation in
	input	_vsync_in,			//vertical synchronisation in
	input	_csync_in,			//composite synchronization in
	output 	reg [3:0] red_out, 		//red componenent video out
	output 	reg [3:0] green_out,  	        //green component video out
	output 	reg [3:0] blue_out,		//blue component video out
	output	reg _hsync_out,			//horizontal synchronisation out
	output	reg _vsync_out			//vertical synchronisation out
);

//local signals
reg 	[3:0] t_red;
reg 	[3:0] t_green;
reg 	[3:0] t_blue;

reg 	[3:0] red_del;				//delayed by 70ns for horizontal interpolation
reg 	[3:0] green_del;			//delayed by 70ns for horizontal interpolation
reg 	[3:0] blue_del;				//delayed by 70ns for horizontal interpolation

wire 	[4:0] red;				//signal after horizontal interpolation
wire	[4:0] green;				//signal after horizontal interpolation
wire 	[4:0] blue;				//signal after horizontal interpolation

reg	_hsync_in_del;				//delayed horizontal synchronisation input
reg	hss;					//horizontal sync start
wire	eol;					//end of scan-doubled line

reg	hfilter;				//horizontal interpolation enable
reg	vfilter;				//vertical interpolation enable
	
reg	scanline_ena;				//signal active when the scan-doubled line is displayed

//-----------------------------------------------------------------------------//

// local horizontal counters for scan doubling
reg		[10:0] wr_ptr;				//line buffer write pointer
reg		[10:0] rd_ptr;				//line buffer read pointer

//delayed hsync for edge detection
always @(posedge clk28m)
	_hsync_in_del <= _hsync_in;

//horizontal sync start	(falling edge detection)
always @(posedge clk28m)
	hss <= ~_hsync_in & _hsync_in_del;

// pixels delayed by one hires pixel for horizontal interpolation
always @(posedge clk28m)
	if (wr_ptr[0]) begin	//sampled at 14MHz (hires clock rate)
		red_del <= red_in;
		green_del <= green_in;
		blue_del <= blue_in;
	end

//horizontal interpolation
assign red   = hfilter ?   red_in +   red_del :   red_in*2;
assign green = hfilter ? green_in + green_del : green_in*2;
assign blue  = hfilter ?  blue_in +  blue_del :  blue_in*2;

// line buffer write pointer
always @(posedge clk28m)
	if (hss)
		wr_ptr <= 0;
	else
		wr_ptr <= wr_ptr + 1;

//end of scan-doubled line
assign eol = rd_ptr=={htotal[8:1],2'b11} ? 1'b1 : 1'b0;

//line buffer read pointer
always @(posedge clk28m)
	if (hss || eol)
		rd_ptr <= 0;
	else
		rd_ptr <= rd_ptr + 1;

always @(posedge clk28m)
	if (hss)
		scanline_ena <= 0;
	else if (eol)
		scanline_ena <= 1;
		
//horizontal interpolation enable	
always @(posedge clk28m)
	if (hss)
		hfilter <= hires ? hr_filter[0] : lr_filter[0];		//horizontal interpolation enable

//vertical interpolation enable
always @(posedge clk28m)
	if (hss)
		vfilter <= hires ? hr_filter[1] : lr_filter[1];		//vertical interpolation enable

reg [15:0] lbf [1023:0]/*synthesis syn_ramstyle = "block_ram"*/;	// line buffer for scan doubling (there are 908/910 hires pixels in every line)
reg [15:0] lbfo;			// line buffer output register
reg [15:0] lbfo2;			// compensantion for one clock delay of the second line buffer
reg [15:0] lbfdo;			// delayed line buffer output register

// line buffer write and read
always @(posedge clk28m) begin
   lbf[wr_ptr[10:1]] <= { _hsync_in, red, green, blue };
   lbfo <= lbf[rd_ptr[9:0]];
end
   
reg [15:0] lbfd [1023:0]; // delayed line buffer for vertical interpolation

//delayed line buffer read/write
always @(posedge clk28m) begin
   reg [15:0] lbfdoD;   

   // this originally read and wrote the same cell at a time. But gowin (at least 1.9.11)
   // fails to synthesize this. We thus write one cell "earlier" and delay the output word to
   // compensate for that. This should cause the first pixel to be interpolated wrongly. But
   // that's not part of the visible area, anyway
   lbfd[rd_ptr[9:0]-10'd1] <= lbfo;
   lbfdoD <= lbfd[rd_ptr[9:0]];
   lbfdo <= lbfdoD;   
end
   
//delayed line buffer pixel by one clock cycle
always @(posedge clk28m)
   lbfo2 <= lbfo;
   
// output pixel generation - vertical interpolation
always @(posedge clk28m)
begin
		_hsync_out <= dblscan ? lbfo2[15] : _csync_in;
		_vsync_out <= dblscan ? _vsync_in : 1'b1;

		if (vfilter)
		begin //vertical interpolation
			t_red    <= ( lbfo2[14:10] + lbfdo[14:10] ) / 4;
			t_green  <= ( lbfo2[9:5] + lbfdo[9:5] ) / 4;
			t_blue   <= ( lbfo2[4:0] + lbfdo[4:0] ) / 4;
		end
		else
		begin //no vertical interpolation
			t_red    <= lbfo2[14:11];
			t_green  <= lbfo2[9:6];
			t_blue   <= lbfo2[4:1];
		end
end

//scanlines effect
`ifdef SCANLINES 
always @(posedge clk28m)
	if (dblscan && scanline_ena && scanline == 2'b10)       // Black, every second line is black
		{red_out,green_out,blue_out} <= 12'h000;
	else if (dblscan && scanline_ena && scanline == 2'b01)  // Dim, every second line is darker
		{red_out,green_out,blue_out} <= {1'b0,t_red[3:1],1'b0,t_green[3:1],1'b0,t_blue[3:1]};
	else if (dblscan && scanline == 2'b11) begin            // Balanced, see https://www.buffee.ca/scanlines/
	   if(scanline_ena)
	     {red_out,green_out,blue_out} <= { {   t_red[2:0], 1'b1 } & {4{  t_red[3]}},
					       { t_green[2:0], 1'b1 } & {4{t_green[3]}},
					       {  t_blue[2:0], 1'b1 } & {4{ t_blue[3]}} };	   
	   else
	     {red_out,green_out,blue_out} <= { {   t_red[2:0], 1'b0 } | {4{  t_red[3]}},
					       { t_green[2:0], 1'b0 } | {4{t_green[3]}},
					       {  t_blue[2:0], 1'b0 } | {4{ t_blue[3]}} }; 
	end else
		{red_out,green_out,blue_out} <= {t_red,t_green,t_blue};
`else
always @(t_red or t_green or t_blue)
	{red_out,green_out,blue_out} <= {t_red,t_green,t_blue};
`endif

endmodule
