//
// Copyright 2008, 2009 by Jakub Bednarski
// Copyright 2021 Alexey Melnikov
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

module gayle
(
	input	        clk,
	input	        reset,

	input	 [23:1] addr,
	input	 [15:0] data_in,
	output [15:0] data_out,
	input         rd,
	input         wr,
	input         sel_ide,			// $DAxxxx
	input         sel_gayle,		// $DExxxx
	output        irq,
	output        nrdy,				// fifo is not ready for reading 
	input         longword,

	output  [5:0] ide_req,
	input   [4:0] ide_address,
	input         ide_write,
	input  [15:0] ide_writedata,
	input         ide_read,
	output [15:0] ide_readdata,

	output        led
);

/*
memory map:

$DA0000 - $DA0FFFF : CS1 16-bit speed
$DA1000 - $DA1FFFF : CS2 16-bit speed
$DA2000 - $DA2FFFF : CS1 8-bit speed
$DA3000 - $DA3FFFF : CS2 8-bit speed
$DA4000 - $DA7FFFF : reserved
$DA8000 - $DA8FFFF : IDE INTREQ state status register (not implemented as scsi.device doesn't use it)
$DA9000 - $DA9FFFF : IDE INTREQ change status register (writing zeros resets selected bits, writing ones doesn't change anything) 
$DAA000 - $DAAFFFF : IDE INTENA register (r/w, only MSB matters)
*/
 
// address decoding
wire sel_gayleid= (sel_gayle && addr[15:12]==4'b0001);  // GAYLEID, $DE1xxx
wire sel_tfr    = (sel_ide   && addr[15:14]==2'b00);    // $DA0xxx, $DA1xxx, $DA2xxx, $DA3xxx
wire sel_cs     = (sel_ide   && addr[15:12]==4'b1000);  // GAYLE_CS_1200,  $DA8xxx
wire sel_intreq = (sel_ide   && addr[15:12]==4'b1001);  // GAYLE_IRQ_1200, $DA9xxx
wire sel_intena = (sel_ide   && addr[15:12]==4'b1010);  // GAYLE_INT_1200, $DAAxxx
wire sel_cfg    = (sel_ide   && addr[15:12]==4'b1011);  // GAYLE_CFG_1200, $DABxxx

reg  old_wr;
wire wr_stb = ~old_wr & wr;
always @(posedge clk) old_wr <= wr;

//===============================================================================================//

reg old_reset = 0;
wire reset_stb = ~old_reset & reset;
always @(posedge clk) old_reset <= reset;

reg [1:0] cs;
reg [5:0] cs_mask;

// gayle cs
always @ (posedge clk) begin
	if (reset) begin
		cs_mask <= 0;
		cs      <= 0;
	end else if (wr_stb && sel_cs) begin
		cs_mask <= data_in[15:10];
		cs      <= data_in[9:8];
	end
end

// gayle cfg
reg [3:0] cfg;
always @ (posedge clk) begin
	if (reset) cfg <= 0;
	if (wr_stb && sel_cfg) cfg <= data_in[15:12];
end

// gayle id register: reads 1->1->0->1 on MSB
reg [1:0] gayleid_cnt;	// sequence counter
always @(posedge clk) begin
	reg old_rd;
	old_rd <= rd & sel_gayleid;

	if (wr_stb & sel_gayleid)         gayleid_cnt <= 0; // a write resets sequence counter
	if (old_rd & ~(rd & sel_gayleid)) gayleid_cnt <= gayleid_cnt + 1'd1;
end

// IDE interrupt enable register
reg intena;
always @(posedge clk) begin
	if (reset) intena <= 0;
	else if (sel_intena && wr_stb) intena <= data_in[15];
end

//===============================================================================================//

//0xda2000 Data
//0xda2004 Error | Feature
//0xda2008 SectorCount
//0xda200c SectorNumber
//0xda2010 CylinderLow
//0xda2014 CylinderHigh
//0xda2018 Device/Head
//0xda201c Status | Command
//0xda3018 Control (not used because of 4xIDE)

assign ide_readdata = ide_address[4] ? ide1_readdata : ide0_readdata;
assign led  = ide0_drq | ide1_drq;
assign nrdy = sel_tfr & !addr[4:2] & (port_num ? ide1_nodata : ide0_nodata);
assign irq  = intreq & intena;

reg longword_r;
//always @(posedge clk) longword_r <= rd && longword && !addr[4:1];
always @(posedge clk) begin
	if (!(rd & sel_tfr)) longword_r <= 0;
	else if (!addr[4:1]) longword_r <= longword;
end

wire port_num = addr[12];
wire data_wr  = wr_stb || ((addr[4:1] == 1) && wr);
wire io_32    = (longword_r | longword) && rd;

wire [31:0] ide0_data;
wire [15:0] ide0_readdata;
wire        ide0_intreq, ide0_drq, ide0_nodata;

ide ide0
(
	.clk(clk),
	.rst_n(~reset_stb),
	.irq(ide0_intreq),

	.io_address({1'b0,addr[4:2]}),
	.io_read(rd & sel_tfr & ~port_num),
	.io_write(data_wr & sel_tfr & ~port_num),
	.io_readdata({ide0_data[23:16],ide0_data[31:24],ide0_data[7:0],ide0_data[15:8]}),
	.io_writedata({16'd0,data_in[7:0],data_in[15:8]}),
	.io_32(io_32),

	.request(ide_req[2:0]),
	.drq(ide0_drq),

	.use_fast(1'b1),
	.no_data(ide0_nodata),

	.mgmt_address(ide_address[3:0]),
	.mgmt_write(ide_write & ~ide_address[4]),
	.mgmt_writedata(ide_writedata),
	.mgmt_read(ide_read & ~ide_address[4]),
	.mgmt_readdata(ide0_readdata)
);

wire [31:0] ide1_data;
wire [15:0] ide1_readdata;
wire        ide1_intreq, ide1_drq, ide1_nodata;

ide ide1
(
	.clk(clk),
	.rst_n(~reset_stb),
	.irq(ide1_intreq),

	.io_address({1'b0,addr[4:2]}),
	.io_read(rd & sel_tfr & port_num),
	.io_write(data_wr & sel_tfr & port_num),
	.io_readdata({ide1_data[23:16],ide1_data[31:24],ide1_data[7:0],ide1_data[15:8]}),
	.io_writedata({16'd0,data_in[7:0],data_in[15:8]}),
	.io_32(io_32),

	.request(ide_req[5:3]),
	.drq(ide1_drq),

	.use_fast(1'b1),
	.no_data(ide1_nodata),

	.mgmt_address(ide_address[3:0]),
	.mgmt_write(ide_write & ide_address[4]),
	.mgmt_writedata(ide_writedata),
	.mgmt_read(ide_read & ide_address[4]),
	.mgmt_readdata(ide1_readdata)
);

wire   intreq  = ide0_intreq | ide1_intreq;
wire   gayleid = ~gayleid_cnt[1] | gayleid_cnt[0];

wire [31:0] tfr= port_num ? ide1_data : ide0_data;

//data_out multiplexer
assign data_out = (sel_tfr     & rd ? ((longword_r & addr[1]) ? tfr[31:16] : tfr[15:0]) : 16'h0000)
                | (sel_cs      & rd ? {(cs_mask[5] || intreq), cs_mask[4:0], cs, 8'h0}  : 16'h0000)
                | (sel_intreq  & rd ? {intreq, 15'b000_0000_0000_0000}                  : 16'h0000)
                | (sel_intena  & rd ? {intena, 15'b000_0000_0000_0000}                  : 16'h0000)
                | (sel_gayleid & rd ? {gayleid,15'b000_0000_0000_0000}                  : 16'h0000)
                | (sel_cfg     & rd ? {cfg,        12'b0000_0000_0000}                  : 16'h0000);


endmodule

