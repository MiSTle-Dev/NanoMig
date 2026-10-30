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
// Audio DMA engine                                                           //
//                                                                            //
// 2 dma cycle types are defined:                                             //
// - restart pointer (go back to the beginning of the sample): dmas active    //
// - advance pointer to the next word of the sample: dmas inactive            //
//                                                                            //
// dma slot allocation:                                                       //
// channel #0 : $0E                                                           //
// channel #1 : $10                                                           //
// channel #2 : $12                                                           //
// channel #3 : $14                                                           //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


module agnus_audiodma
(
  input  wire           clk,              // bus clock
  input  wire           clk7_en,          // 7MHz clock enable
  output wire           dma,              // true if audio dma engine uses it's cycle
  input  wire [  4-1:0] audio_dmal,       // audio dma data transfer request (from Paula)
  input  wire [  4-1:0] audio_dmas,       // audio dma location pointer restart (from Paula)
  input  wire [  9-1:0] hpos,             // horizontal beam counter
  input  wire [  9-1:1] reg_address_in,   // register address inputs
  output reg  [  9-1:1] reg_address_out,  // register address outputs
  input  wire [ 16-1:0] data_in,          // bus data in
  output wire [ 21-1:1] address_out       // chip address out
);


// register names and adresses
parameter AUD0DAT_REG = 9'h0AA;
parameter AUD1DAT_REG = 9'h0BA;
parameter AUD2DAT_REG = 9'h0CA;
parameter AUD3DAT_REG = 9'h0DA;

// local signals
wire          audlcena;     // audio dma location pointer register address enable
wire [  1: 0] audlcsel;     // audio dma location pointer select
reg  [ 20:16] audlch [3:0]; // audio dma location pointer bank (high word)
reg  [ 15: 1] audlcl [3:0]; // audio dma location pointer bank (low word)
wire [ 20: 1] audlcout;     // audio dma location pointer bank output
reg  [ 20: 1] audpt [3:0];  // audio dma pointer bank
wire [ 20: 1] audptout;     // audio dma pointer bank output
reg  [  1: 0] channel;      // audio dma channel select
reg           dmal;
reg           dmas;

// location registers address enable
// active when any of the location registers is addressed
// $A0-$A3, $B0-$B3, $C0-$C3, $D0-$D3,
assign audlcena = ~reg_address_in[8] & reg_address_in[7] & (reg_address_in[6]^reg_address_in[5]) & ~reg_address_in[3] & ~reg_address_in[2];

// location register channel select
assign audlcsel = {~reg_address_in[5],reg_address_in[4]};

// audio location register bank
always @ (posedge clk) begin
  if (clk7_en) begin
    if (audlcena & ~reg_address_in[1]) // AUDxLCH
      audlch[audlcsel] <= #1 data_in[4:0];
  end
end

always @ (posedge clk) begin
  if (clk7_en) begin
    if (audlcena & reg_address_in[1]) // AUDxLCL
      audlcl[audlcsel] <= #1 data_in[15:1];
  end
end

// get audio location pointer
assign audlcout = {audlch[channel],audlcl[channel]};

// dma cycle allocation
always @ (*) begin
  case (hpos)
    9'b0001_0010_1 : dmal = audio_dmal[0]; //$0E
    9'b0001_0100_1 : dmal = audio_dmal[1]; //$10
    9'b0001_0110_1 : dmal = audio_dmal[2]; //$12
    9'b0001_1000_1 : dmal = audio_dmal[3]; //$14
    default        : dmal = 0;
  endcase
end

// dma cycle request
assign dma = dmal;

// channel dmas encoding
always @ (*) begin
  case (hpos)
    9'b0001_0010_1 : dmas = audio_dmas[0]; //$0E
    9'b0001_0100_1 : dmas = audio_dmas[1]; //$10
    9'b0001_0110_1 : dmas = audio_dmas[2]; //$12
    9'b0001_1000_1 : dmas = audio_dmas[3]; //$14
    default        : dmas = 0;
  endcase
end

// dma channel select
always @ (*) begin
  case (hpos[3:2])
    2'b01 : channel = 0; //$0E
    2'b10 : channel = 1; //$10
    2'b11 : channel = 2; //$12
    2'b00 : channel = 3; //$14
  endcase
end

// memory address output
assign address_out[20:1] = audptout[20:1];

// audio pointers register bank (implemented using distributed ram) and ALU
always @ (posedge clk) begin
  if (clk7_en) begin
    if (dmal)
      audpt[channel] <= #1 dmas ? audlcout[20:1] : audptout[20:1] + 1'b1;
  end
end

// audio pointer output
assign audptout[20:1] = audpt[channel];

// register address output multiplexer
always @ (*) begin
  case (channel)
    0 : reg_address_out[8:1] = AUD0DAT_REG[8:1];
    1 : reg_address_out[8:1] = AUD1DAT_REG[8:1];
    2 : reg_address_out[8:1] = AUD2DAT_REG[8:1];
    3 : reg_address_out[8:1] = AUD3DAT_REG[8:1];
  endcase
end


endmodule

