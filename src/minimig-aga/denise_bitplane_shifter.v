////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Copyright 2006, 2007 Dennis van Weeren                                     //
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
`ifdef DENISE_EBR
// Copyright 2026 Mateusz Nalewajski                                          //
// This is EBR refactor of bitplane parallel to serial converter & scroller   //
//                                                                            //
// The BRAM read pointer, shift index and shift/load timing are identical for //
// every plane, so they are generated once in denise_bitplanes and fed in     //
// here as shift / shifter_load / ram_addra / ram_addrb. This module keeps    //
// only the per-plane data path (its own BRAM, shifter, scroller and output). //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


module denise_bitplane_shifter
(
  input  wire           clk,          // 35ns pixel clock
  input  wire           clk7_en,      // 7MHz clock enable
  input  wire           aen,          // address enable
  input  wire           bpl1,
  input  wire           shift,        // shifter/scroller enable (shared)
  input  wire           shifter_load, // load next byte into shifter (shared)
  input  wire           ld_start,     // fetch start
  input  wire [  2-1:0] ram_addra,    // BRAM write address (shared)
  input  wire [  3-1:0] ram_addrb,    // BRAM read address  (shared)
  input  wire [ 16-1:0] bpl_dat,
  input  wire [  6-1:0] fmode_mask,   // fetchmode mask (shared)
  input  wire           hires,        // high resolution select
  input  wire           shres,        // super high resolution select (takes priority over hires)
  input  wire           aga,          // AGA enabled
  input  wire [  8-1:0] scroll,       // scrolling value
  output wire           out           // shift register output
);


// local signals
reg  [ 8-1:0] shifter;            // main shifter
reg  [64-1:0] scroller;           // scroller shifter
reg  [ 6-1:0] select;             // shifter pixel select
wire          scroller_out;       // scroller output
reg  [ 8-1:0] sh_scroller;        // superhires scroller
reg  [ 3-1:0] sh_select;          // superhires scroller pixel select


// interface with BRAM bitplane buffer
wire  [7:0] ram_doutb;
wire [15:0] ram_din;
reg         ram_wea;

// skip buffers for BPL1 as it triggers shifter reload anyway
reg         ram_bufa;             // BRAM write buffer select
reg         ram_bufb;             // BRAM read buffer select

bitplane_ram ram (
  .clk(clk),
  .wea(ram_wea),
  .addra({bpl1 ? 1'b0 : ram_bufa, ram_addra}),
  .dina(ram_din),
  .addrb({bpl1 ? 1'b0 : ram_bufb, ram_addrb}),
  .doutb(ram_doutb)
);

// BRAM writes are 16-bit, reads 8-bit
assign ram_din = bpl_dat;

// per-plane write enable: this plane's BRAM is written only when its own
// data register (aen) is addressed; the write window closes at the first bank
always @(posedge clk) begin
  if (clk7_en) begin
    // finish writing when we get next full 7MHz cycle
    ram_wea <= 0;

    // initiate data transfer and continue for the next 4 cycles
    if (aen) begin
      ram_wea  <= 1;

      // ensure we won't overwrite currently read data
      ram_bufa <= ~ram_bufb;
    end
  end
end

// update BRAM buffer select before actual shift starts
always @(posedge clk)
  if (ld_start)
    ram_bufb <= ram_bufa;

// shifter pixel select (scroll is per-plane, so this stays local)
always @ (*) begin
  if (shres)
    // super hires mode
    select[5:0] = scroll[5:0] & fmode_mask;
  else if (hires)
    // hires mode
    select[5:0] = scroll[6:1] & fmode_mask;
  else
    // lowres mode
    select[5:0] = scroll[7:2] & fmode_mask;
end

// main shifter
always @ (posedge clk) begin
  if (shifter_load)
    // load next byte into shifter
    shifter[7:0] <= ram_doutb[7:0];
  else if (shift)
    // shift already loaded data
    shifter[7:0] <= {shifter[6:0], 1'b0};
end

// main scroller
always @ (posedge clk) begin
  if (shift)
    // shift scroller data
    scroller[63:0] <= {scroller[62:0], shifter[7]};
end

// main scroller output
assign scroller_out = scroller[select];

// superhires scroller control
always @ (*) begin
  if (shres)
    sh_select = aga ? 3'b110 : 3'b011;
  else if (hires)
    sh_select = {aga, scroll[0], 1'b1};
  else
    sh_select = {1'b0, scroll[1:0]} + (aga ? 3'd3 : 3'b0);
end

// superhires scroller
always @ (posedge clk) begin
  sh_scroller[7:0] <= {sh_scroller[6:0], scroller_out};
end

// superhires scroller output
assign out = sh_scroller[sh_select];

endmodule

`else
// This is the bitplane parallel to serial converter & scroller               //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


module denise_bitplane_shifter
(
  input  wire           clk,      // 35ns pixel clock
  input  wire           clk7_en,  // 7MHz clock enable
  input  wire           c1,       // clock phase signals
  input  wire           c3,       // clock phase signals
  input  wire           load,     // load shift register signal
  input  wire           hires,    // high resolution select
  input  wire           shres,    // super high resolution select (takes priority over hires)
  input  wire [  2-1:0] fmode,    // AGA fetch mode
  input  wire           aga,
  input  wire [ 64-1:0] data_in,  // parallel load data input
  input  wire [  8-1:0] scroll,   // scrolling value
  output                out       // shift register output
);


// local signals
reg  [ 6-1:0] fmode_mask;         // fetchmode mask
reg  [64-1:0] shifter;            // main shifter
reg  [64-1:0] scroller;           // scroller shifter
reg           shift;              // shifter enable
reg  [ 6-1:0] select;             // shifter pixel select
wire          scroller_out;       // scroller output
reg  [ 8-1:0] sh_scroller;        // superhires scroller
reg  [ 3-1:0] sh_select;          // superhires scroller pixel select


// fetchmode mask
always @ (*) begin
  case(fmode[1:0])
    2'b00 : fmode_mask = 6'b00_1111;
    2'b01,
    2'b10 : fmode_mask = 6'b01_1111;
    2'b11 : fmode_mask = 6'b11_1111;
  endcase
end

// main shifter and scroller control
always @ (*) begin
  if (shres) begin
    // super hires mode
    shift = 1'b1; // shifter always enabled
    select[5:0] = scroll[5:0] & fmode_mask;
  end else if (hires) begin
    // hires mode
    shift = ~c1 ^ c3; // shifter enabled every other clock cycle
    select[5:0] = scroll[6:1] & fmode_mask;
  end else begin
    // lowres mode
    shift = ~c1 & ~c3; // shifter enabled once every 4 clock cycles
    select[5:0] = scroll[7:2] & fmode_mask;
  end
end


// main shifter
always @ (posedge clk) begin
  if (load && !c1 && !c3) begin
    // load new data into shifter
    shifter[63:0] <= data_in[63:0];
  end else if (shift) begin
    // shift already loaded data
    shifter[63:0] <= {shifter[62:0],1'b0};
  end
end


// main scroller
always @ (posedge clk) begin
  if (shift) begin
    // shift scroller data
    scroller[63:0] <= {scroller[62:0],shifter[63]};
  end
end


// main scroller output
assign scroller_out = scroller[select];


// superhires scroller control // TODO test if this is correct
always @ (*) begin
  if (shres) begin
    sh_select = aga ? 3'b110 : 3'b011;
  end else if (hires) begin
    sh_select = {aga, scroll[0], 1'b1}; // MSB bit should probably be 0, this is a hack for kickstart screen ...
  end else begin
    sh_select = {aga, scroll[1:0]};
  end
end


// superhires scroller
always @ (posedge clk) begin
  sh_scroller[7:0] <= {sh_scroller[6:0], scroller_out};
end


// superhires scroller output
assign out = sh_scroller[sh_select];


endmodule


`endif