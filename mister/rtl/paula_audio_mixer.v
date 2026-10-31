// stereo volume control
// channel 0&3 --> left
// channel 1&2 --> right


module paula_audio_mixer (
  input   clk,        //bus clock
  input clk7_en,
  input  [7:0] sample0,    //sample 0 input
  input  [7:0] sample1,    //sample 1 input
  input  [7:0] sample2,    //sample 2 input
  input  [7:0] sample3,    //sample 3 input
  input  [6:0] vol0,      //volume 0 input
  input  [6:0] vol1,      //volume 1 input
  input  [6:0] vol2,      //volume 2 input
  input  [6:0] vol3,      //volume 3 input
  output reg  [14:0]ldatasum,    //left DAC data
  output reg  [14:0]rdatasum    //right DAC data
);

// volume control
wire [14-1:0] msample0, msample1, msample2, msample3;
// when volume MSB is set, volume is always maximum
paula_audio_volume sv0
(
  .sample(sample0),
  .volume({  (vol0[6] | vol0[5]),
            (vol0[6] | vol0[4]),
            (vol0[6] | vol0[3]),
            (vol0[6] | vol0[2]),
            (vol0[6] | vol0[1]),
            (vol0[6] | vol0[0]) }),
  .out(msample0)
);

paula_audio_volume sv1
(
  .sample(sample1),
  .volume({  (vol1[6] | vol1[5]),
            (vol1[6] | vol1[4]),
            (vol1[6] | vol1[3]),
            (vol1[6] | vol1[2]),
            (vol1[6] | vol1[1]),
            (vol1[6] | vol1[0]) }),
  .out(msample1)
);

paula_audio_volume sv2
(
  .sample(sample2),
  .volume({  (vol2[6] | vol2[5]),
            (vol2[6] | vol2[4]),
            (vol2[6] | vol2[3]),
            (vol2[6] | vol2[2]),
            (vol2[6] | vol2[1]),
            (vol2[6] | vol2[0]) }),
  .out(msample2)
);

paula_audio_volume sv3
(
  .sample(sample3),
  .volume({  (vol3[6] | vol3[5]),
            (vol3[6] | vol3[4]),
            (vol3[6] | vol3[3]),
            (vol3[6] | vol3[2]),
            (vol3[6] | vol3[1]),
            (vol3[6] | vol3[0]) }),
  .out(msample3)
);


// channel muxing
// !!! this is 28MHz clock !!!
always @ (posedge clk) begin
  ldatasum <= #1 {msample0[13], msample0} + {msample3[13], msample3};
  rdatasum <= #1 {msample1[13], msample1} + {msample2[13], msample2};
end


endmodule

