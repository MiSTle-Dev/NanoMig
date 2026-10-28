// colortable ram

module denise_colortable_ram_mf (
        input [1:0]	  ena_a,
	input		  clock,
	input [11:0]	  data,
	input [7:0]	  rdaddress,
	input [7:0]	  wraddress,
	input		  wren,
	output reg [23:0] q
);

wire [31:0] do_w;
always @(*) q = {do_w[27:16], do_w[11:0]};
SDPB sdpb_inst (
   .DO(do_w),
   .DI({4'b0000, data, 4'b0000, data}),
   .BLKSELA(3'b000),
   .BLKSELB(3'b000),
   .ADA({1'b0, wraddress, 1'b0, ena_a[1], ena_a[1], ena_a[0], ena_a[0]}),
   .ADB({1'b0, rdaddress, 5'b00000}),
   .CLKA(clock),
   .CLKB(clock),
   .CEA(wren),
   .CEB(1'b1),
   .OCE(1'b0),
   .RESETA(1'b0),
   .RESETB(1'b0)
);
defparam sdpb_inst.BIT_WIDTH_0 = 32;
defparam sdpb_inst.BIT_WIDTH_1 = 32;
defparam sdpb_inst.READ_MODE = 1'b0;
defparam sdpb_inst.RESET_MODE = "SYNC";
defparam sdpb_inst.BLK_SEL_0 = 3'b000;
defparam sdpb_inst.BLK_SEL_1 = 3'b000;
/*
reg [11:0] ram0[255:0];
reg [11:0] ram1[255:0];
   
always @(posedge clock) begin
   if(wren) begin
      if(ena_a[0]) ram0[wraddress] <= data;
      if(ena_a[1]) ram1[wraddress] <= data;
   end

   q <= { ram1[rdaddress], ram0[rdaddress] }; 
/*
end
   
*/
endmodule
