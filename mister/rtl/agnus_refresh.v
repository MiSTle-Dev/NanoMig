// refresh dma channel (for compatibility)


module agnus_refresh
(
	input	[8:0] hpos,
	output	reg dma
);

//dma request
always @(hpos)
	case (hpos)
		9'b0000_0100_1 : dma = 1'b1;
		9'b0000_0110_1 : dma = 1'b1;
		9'b0000_1000_1 : dma = 1'b1;
		9'b0000_1010_1 : dma = 1'b1;
		default        : dma = 1'b0;
	endcase


endmodule

