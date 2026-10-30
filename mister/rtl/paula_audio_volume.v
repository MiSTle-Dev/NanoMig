//this module multiplies a signed 8 bit sample with an unsigned 6 bit volume setting
//it produces a 14bit signed result


module paula_audio_volume
(
  input   [7:0] sample,    //signed sample input
  input  [5:0] volume,    //unsigned volume input
  output  [13:0] out      //signed product out
);

wire  [13:0] sesample;       //sign extended sample
wire  [13:0] sevolume;    //sign extended volume

//sign extend input parameters
assign   sesample[13:0] = {{6{sample[7]}},sample[7:0]};
assign  sevolume[13:0] = {8'b00000000,volume[5:0]};

//multiply, synthesizer should infer multiplier here
assign out[13:0] = {sesample[13:0] * sevolume[13:0]};


endmodule

