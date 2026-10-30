////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Copyright 2013, 2014 Rok Krajnc                                            //
//                                                                            //
// This file is part of Minimig                                               //
//                                                                            //
// Minimig is free software; you can redistribute it and/or modify            //
// it under the terms of the GNU General Public License as published by       //
// the Free Software Foundation; either version 3 of the License, or          //
// (at your option) any later version.                                        //
//                                                                            //
// Minimig is distributed in the hope that it will be useful,                 //
// but WITHOUT ANY WARRANTY; without even the implied warranty of             //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              //
// GNU General Public License for more details.                               //
//                                                                            //
// You should have received a copy of the GNU General Public License          //
// along with this program.  If not, see <http://www.gnu.org/licenses/>.      //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// This is Cart module with support for HRTmon monitor.                       //
// This module is based on existing ActionReplay.v module by Jakub Bednarski  //
// and code from WinUAE ar.cpp file. The module requires the ctrl firmware    //
// to load the special hrtmon.rom file to address 0xa10000. The module        //
// requires one 512KB RAM bank. The start address (entry point) is 0xa1000c.  //
// TODO : custom registers and CIA registers shadow implemented as in WinUAE. //
//                                                                            //
//                                                                            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Changelog                                                                  //
// RK:                                                                        //
// 2013-11-27  - initial version                                              //
// 2014-09-27  - cleanup, clock enable added                                  //
// 2015-05-03  - added custom registers mirror                                //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module cart
(
	input         clk,
	input         clk7_en,
	input         clk7n_en,
	input         cpu_rst,
	input  [23:1] cpu_address_in,
	input         _cpu_as,
	input         cpu_rd,
	input         cpu_hwr,
	input         cpu_lwr,
	input  [31:0] nmi_addr,
	input   [8:1] reg_address_in,
	input  [15:0] reg_data_in,
	input         dbr,
	input         ovl,
	input         freeze, 
	input         cpuhlt,
	output [15:0] cart_data_out,
	output reg    int7 = 1'b0,
	output        sel_cart,
	output        ovr
);


//  cart selected, is in stealth mode until first freeze, has to be available during halt to allow userio 
assign sel_cart = ~dbr && (cpu_address_in[23:19]==5'b1010_0) && (stealth | cpuhlt); // $A00000
   

// latch VBR + NMI vector offset
reg [31:0] nmi_vec_adr=0;
reg [23:1] nmi_vec_adr2=0;
always @ (posedge clk) if (clk7_en) nmi_vec_adr <= nmi_addr; // $7C = NMI vector offset
always @ (posedge clk) if (clk7_en) nmi_vec_adr2 <= nmi_addr[23:1] + 1'd1;
wire nmi_vec_hi = (cpu_address_in[23:1] == nmi_vec_adr[23:1]);

// override decoding of NMI
assign ovr = active && ~dbr && ~ovl && cpu_rd && (nmi_vec_hi || (cpu_address_in[23:1] == nmi_vec_adr2));

// custom NMI vector address output $a1000c
wire [15:0] nmi_adr_out = ovr ? (nmi_vec_hi ? 16'h00a1 : 16'h000c) : 16'h0000;

// freeze button
reg freeze_d=0;
always @ (posedge clk) if (clk7_en) freeze_d <= freeze;

wire freeze_req = freeze && ~freeze_d;

// int7 request
wire int7_req = freeze_req;

// level7 interrupt ack cycle, on Amiga interrupt vector number is read from kickstart rom
wire int7_ack = &cpu_address_in && ~_cpu_as;

// level 7 interrupt request logic
// interrupt request lines are sampled during S4->S5 transition (falling cpu clock edge)
always @ (posedge clk) begin
	if (clk7_en) begin
		     if (cpu_rst)  int7 <= 0;
		else if (int7_req) int7 <= 1;
		else if (int7_ack) int7 <= 0;
	end
end

// latches
reg l_int7_req=0;
reg l_int7_ack=0;
always @ (posedge clk) begin
	if (clk7_en) begin
		l_int7_req <= int7_req;
		l_int7_ack <= int7_ack;
	end
end

reg l_int7=0;
always @ (posedge clk) begin
	if (clk7_en) begin
		     if (cpu_rst)              l_int7 <= 0;
		else if (l_int7_req)           l_int7 <= 1;
		else if (l_int7_ack && cpu_rd) l_int7 <= 0;
	end
end

// overlay active
reg active=0;
reg stealth; //hide till first freeze request   
always @ (posedge clk) begin
	if (clk7_en) begin
		if (cpu_rst) begin
			active <= 0;
			stealth <= 0;
		end
		else if (l_int7 && l_int7_ack && cpu_rd) begin
			active <= 1;
			stealth <= 1;
		end
		else if (sel_cart && cpu_rd) begin
			active <= 0;
		end
	end
end

// custom registers mirror memory
wire sel_custom_mirror = ~dbr && cpu_rd && (cpu_address_in[23:12]==12'b1010_1001_1111) && stealth; // $A9F000

reg [15:0] custom_mirror_q;
reg [15:0] custom_mirror[256];
always @ (posedge clk) begin
	if (clk7_en) begin
		custom_mirror[reg_address_in] <= reg_data_in;
	end
	custom_mirror_q <= custom_mirror[cpu_address_in[8:1]];
end

wire [15:0] custom_mirror_out = sel_custom_mirror ? custom_mirror_q : 16'h0000;

// cart data output
assign cart_data_out = custom_mirror_out | nmi_adr_out;


endmodule

