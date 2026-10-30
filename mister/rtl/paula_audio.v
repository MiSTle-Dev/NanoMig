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
// This is the audio part of Paula                                            //
// Paula requests data from Agnus using DMAL line (high active state)         //
// DMAL time slot allocation (relative to first refresh slot referenced       //
// as $00):                                                                   //
// $03,$05,$07 - all these slots are active when disk dma is inactive or      //
// write operation is in progress                                             //
// $04 - at least 3 words to read / at least 1 word  to write                 //
// (transfer in $08)                                                          //
// $06 - at least 2 words to read / at least 2 words to write                 //
// (transfer in $0A)                                                          //
// $08 - at least 1 word  to read / at least 3 words to write                 //
// (transfer in $0C)                                                          //
// $09 - audio channel #0 location pointer reload request                     //
// (active with data request)                                                 //
// $0A - audio channle #0 dma data request (data transfered in slot $0E)      //
// $0B - audio channel #1 location pointer reload request                     //
// (active with data request)                                                 //
// $0C - audio channle #1 dma data request (data transfered in slot $10)      //
// $0D - audio channel #2 location pointer reload request                     //
// (active with data request)                                                 //
// $0E - audio channle #2 dma data request (data transfered in slot $12)      //
// $0F - audio channel #3 location pointer reload request                     //
// (active with data request)                                                 //
// $10 - audio channle #3 dma data request (data transfered in slot $14)      //
// minimum sampling period for audio channels in CCKs (no length reload)      //
// #0 : 121 (120)                                                             //
// #1 : 122 (121)                                                             //
// #2 : 123 (122)                                                             //
// #3 : 124 (123)                                                             //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Changelog                                                                  //
// DvW:                                                                       //
// 2005-12-27 - started coding                                                //
// 2005-12-28 - done lots of work                                             //
// 2005-12-29 - done lots of work                                             //
// 2006-01-01 - we are having OK sound in dma mode now                        //
// 2006-01-02 - fixed last state                                              //
// 2006-01-03 - added dmas to avoid interference with copper cycles           //
// 2006-01-04 - experimented with DAC                                         //
// 2006-01-06 - experimented some more with DAC and decided to leave it as it //
//              is for now                                                    //
// 2006-01-07 - cleaned up code                                               //
// 2006-02-21 - improved audio state machine                                  //
// 2006-02-22 - fixed dma interrupt timing, Turrican-3 theme now plays        //
//              correct!                                                      //
//                                                                            //
// JB:                                                                        //
// 2008-10-12 - code clean-up                                                 //
// 2008-12-20 - changed DMA slot allocation                                   //
// 2009-03-08 - horbeam removed                                               //
//            - strhor signal added (cures problems with freezing of some     //
//              games)                                                        //
//            - corrupted Agony title song                                    //
// 2009-03-17 - audio FSM rewritten to comply more exactly with HRM state     //
//              diagram, Agony still has problems                             //
// 2009-03-26 - audio dma requests are latched and cleared at the start of    //
//              every scan line, seemd to cure Agony problem                  //
//            - Forgotten Worlds freezes at game intro screen due to missed   //
//              audio irq                                                     //
// 2009-05-24 - clean-up & renaming                                           //
// 2009-11-14 - modified audio state machine to be more cycle-exact with      //
//              its real counterpart                                          //
//            - sigma-delta modulator is clocked at 28 MHz                    //
// 2010-06-15 - updated description                                           //
//                                                                            //
// SB:                                                                        //
// 2011-01-18 - fixed sound output, no more high pitch noise at game Gods     //
//                                                                            //
// RK:                                                                        //
// 2012-11-11 - two-stage sigma-delta modulator added                         //
// 2013-02-10 - two stage sigma-delta updated:                                //
//            - used AMR's silence fix                                        //
//            - added interpolator at sigma-delta input                       //
//            - all bits of the x3/4 input signal are used, dithering         //
//              removed                                                       //
//            - two LFSR PRNGs are combined and high-pass filtered for a HP   //
//              triangular PDF noise                                          //
//            - random noise is applied directly in front of the quantizer,   //
//              which helps randomize the output stream                       //
//            - some noise shaping (filtering) added to the error feedback    //
//              signal                                                        //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


module paula_audio
(
  input  wire           clk,            // 28MHz clock
  input  wire           clk7_en,        // 7MHz clock enable
  input  wire           cck,            // colour clock enable
  input  wire           rst,            // reset
  input  wire           strhor,         // horizontal strobe
  input  wire [  9-1:1] reg_address_in, // register address input
  input  wire [ 16-1:0] data_in,        // bus data in
  input  wire [  4-1:0] dmaena,         // audio dma register input
  output wire [  4-1:0] audint,         // audio interrupt request
  input  wire [  4-1:0] audpen,         // audio interrupt pending
  output reg  [  4-1:0] dmal,           // dma request
  output reg  [  4-1:0] dmas,           // dma special
  output wire [ 15-1:0] ldata,          // left DAC data
  output wire [ 15-1:0] rdata,          // right DAC data
  output wire [  9-1:0] ldata_okk,      // left DAC data  (PWM volume)
  output wire [  9-1:0] rdata_okk       // right DAC data (PWM volume)
);


//register names and addresses
parameter  AUD0BASE = 9'h0a0;
parameter  AUD1BASE = 9'h0b0;
parameter  AUD2BASE = 9'h0c0;
parameter  AUD3BASE = 9'h0d0;

//local signals
wire  [  4-1:0] aen;      //address enable 0-3
wire  [  4-1:0] dmareq;   //dma request 0-3
wire  [  4-1:0] dmaspc;   //dma restart 0-3
wire  [  8-1:0] sample0;  //channel 0 audio sample
wire  [  8-1:0] sample1;  //channel 1 audio sample
wire  [  8-1:0] sample2;  //channel 2 audio sample
wire  [  8-1:0] sample3;  //channel 3 audio sample

wire  [  8-1:0] sample0_okk;  //channel 0 audio sample (PWM volume gated)
wire  [  8-1:0] sample1_okk;  //channel 1 audio sample (PWM volume gated)
wire  [  8-1:0] sample2_okk;  //channel 2 audio sample (PWM volume gated)
wire  [  8-1:0] sample3_okk;  //channel 3 audio sample (PWM volume gated)

wire  [  7-1:0] vol0;     //channel 0 volume
wire  [  7-1:0] vol1;     //channel 1 volume
wire  [  7-1:0] vol2;     //channel 2 volume
wire  [  7-1:0] vol3;     //channel 3 volume
wire  [ 16-1:0] ldatasum;
wire  [ 16-1:0] rdatasum;


//address decoder
assign aen[0] = (reg_address_in[8:4]==AUD0BASE[8:4]) ? 1'b1 : 1'b0;
assign aen[1] = (reg_address_in[8:4]==AUD1BASE[8:4]) ? 1'b1 : 1'b0;
assign aen[2] = (reg_address_in[8:4]==AUD2BASE[8:4]) ? 1'b1 : 1'b0;
assign aen[3] = (reg_address_in[8:4]==AUD3BASE[8:4]) ? 1'b1 : 1'b0;


//DMA slot allocation is managed by Agnus
//#0 : 0E
//#1 : 10
//#2 : 12
//#3 : 14

always @(posedge clk) begin
  if (clk7_en) begin
    if (strhor)
    begin
      dmal <= (dmareq);
      dmas <= (dmaspc);
    end
  end
end


//instantiate audio channel 0
paula_audio_channel ach0
(
  .clk(clk),
  .clk7_en (clk7_en),
  .reset(rst),
  .cck(cck),
  .aen(aen[0]),
  .dmaena(dmaena[0]),
  .reg_address_in(reg_address_in[3:1]),
  .data(data_in),
  .volume(vol0),
  .sample(sample0),
  .sample_okk(sample0_okk),
  .intreq(audint[0]),
  .intpen(audpen[0]),
  .dmareq(dmareq[0]),
  .dmas(dmaspc[0]),
  .strhor(strhor)
);

//instantiate audio channel 1
paula_audio_channel ach1
(
  .clk(clk),
  .clk7_en (clk7_en),
  .reset(rst),
  .cck(cck),
  .aen(aen[1]),
  .dmaena(dmaena[1]),
  .reg_address_in(reg_address_in[3:1]),
  .data(data_in),
  .volume(vol1),
  .sample(sample1),
  .sample_okk(sample1_okk),
  .intreq(audint[1]),
  .intpen(audpen[1]),
  .dmareq(dmareq[1]),
  .dmas(dmaspc[1]),
  .strhor(strhor)
);

//instantiate audio channel 2
paula_audio_channel ach2
(
  .clk(clk),
  .clk7_en (clk7_en),
  .reset(rst),
  .cck(cck),
  .aen(aen[2]),
  .dmaena(dmaena[2]),
  .reg_address_in(reg_address_in[3:1]),
  .data(data_in),
  .volume(vol2),
  .sample(sample2),
  .sample_okk(sample2_okk),
  .intreq(audint[2]),
  .intpen(audpen[2]),
  .dmareq(dmareq[2]),
  .dmas(dmaspc[2]),
  .strhor(strhor)
);

//instantiate audio channel 3
paula_audio_channel ach3
(
  .clk(clk),
  .clk7_en (clk7_en),
  .reset(rst),
  .cck(cck),
  .aen(aen[3]),
  .dmaena(dmaena[3]),
  .reg_address_in(reg_address_in[3:1]),
  .data(data_in),
  .volume(vol3),
  .sample(sample3),
  .sample_okk(sample3_okk),
  .intreq(audint[3]),
  .intpen(audpen[3]),
  .dmareq(dmareq[3]),
  .dmas(dmaspc[3]),
  .strhor(strhor)
);

// okk mixer
assign ldata_okk = {sample0_okk[7], sample0_okk[7:0]} + {sample3_okk[7], sample3_okk[7:0]};
assign rdata_okk = {sample1_okk[7], sample1_okk[7:0]} + {sample2_okk[7], sample2_okk[7:0]};

// instantiate mixer
paula_audio_mixer mix (
  .clk      (clk),
  .clk7_en  (clk7_en),
  .sample0  (sample0),
  .sample1  (sample1),
  .sample2  (sample2),
  .sample3  (sample3),
  .vol0     (vol0),
  .vol1     (vol1),
  .vol2     (vol2),
  .vol3     (vol3),
  .ldatasum (ldata),
  .rdatasum (rdata)
);

endmodule

