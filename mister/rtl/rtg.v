// Copyright 2020
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
// along with this program.  If not, see <http:// www.gnu.org/licenses/>.
//
//
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------  
// REGISTER MAP
// B80100:B80101 :  8:0 : ADDR[24:16]
// B80102:B80103 : 15:0 : ADDR[15:0]
// B80104:B80105 : 5:0  : FORMAT[5:0]
// B80106:B80107 :    0 : ENABLE
// B80108:B80109 : 11:0 : HSIZE
// B8010A:B8010B : 11:0 : VSIZE
// B8010C:B8010D : 13:0 : STRIDE
// B8010E:B8010F :  7:0 : ID = 50 / VERSION = 01

// B80400..B807FF CLUT : 256 * 32bits 00 / RR / GG / BB

module rtg
(
	input             clk,           // clock
	input             aen,           // adress enable
	input             rd,            // read enable
	input             wr,            // write enable
	input             reset,         // reset
	input      [11:1] rs,            // register select (address)
	output            ready,

	input      [15:0] data_in,       // bus data in
	output     [15:0] data_out,      // bus data out

	output reg        ena,
	output reg [11:0] hsize,
	output reg [11:0] vsize,
	output reg [4:0]  format,
	output reg [31:0] base,
	output reg [13:0] stride,
	output            pal_clk,
	output     [23:0] pal_dw,
	input      [23:0] pal_dr,
	output     [7:0]  pal_a,
	output            pal_wr
);

reg [23:0] rpal;

wire r_en  = aen && (rs[11:4]  == 'h10);
wire r_pal = aen && (rs[11:10] == 1);

// writing of output port
always @(posedge clk) begin
	if (reset) ena<=0;
	else if(wr) begin
		if(r_en) begin
			case(rs[3:1])
				0: base[31:16] <= data_in;
				1: base[15:0]  <= data_in;
				2: format      <= data_in[4:0];
				3: ena         <= data_in[0];
				4: hsize       <= data_in[11:0];
				5: vsize       <= data_in[11:0];
				6: stride      <= data_in[13:0];
			endcase
		end
		else if(r_pal) begin
			if (!rs[1]) rpal[23:16] <= data_in[7:0];
			       else rpal[15:0]  <= data_in;
		end
	end
end

reg [15:0] dout;
always @(posedge clk) begin
	dout <= 16'h0000;
	if(r_en) begin
		case(rs[3:1])
			0: dout <= base[31:16];
			1: dout <= base[15:0];
			2: dout <= format;
			3: dout <= ena;
			4: dout <= hsize;
			5: dout <= vsize;
			6: dout <= stride;
			7: dout <= 16'h5001;
		endcase
	end
	if (r_pal) dout <= rs[1] ? pal_dr[15:0] : pal_dr[23:16];
end

reg [2:0] rd_r;
always @(posedge clk) rd_r <= rd_ready ? 3'd0 : {rd_r[1:0],aen & rd};
wire rd_ready = r_pal ? rd_r[2] : rd_r[0];

assign pal_clk  = clk;
assign pal_a    = rs[9:2];
assign pal_wr   = wr & r_pal;
assign pal_dw   = rs[1] ? {rpal[23:16],data_in} : {data_in[7:0],rpal[15:0]};

assign data_out = aen ? dout : 16'h0000;
assign ready    = aen & (wr | rd_ready);

endmodule
