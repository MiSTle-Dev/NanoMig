
module akiko_legacy_ref
(
	input             clk,
	input             cs,
	input             rd,
	input             wr,
	input       [5:1] addr,
	input      [15:0] din,
	output reg [15:0] dout
);

wire c2p_sel = (addr[5:2] == 'b1110);

reg [7:0] buff[32];
reg [3:0] rptr = 0, wptr = 0;

always @(posedge clk) begin
	if((wr|rd) & cs & c2p_sel) begin
		if (wr) begin
			rptr <= 0;
			wptr <= wptr + 1'd1;
			{buff[{wptr,1'b0}],buff[{wptr,1'b1}]} <= din;
		end
		else begin
			wptr <= 0;
			rptr <= rptr + 1'd1;
		end
	end
end

always @* begin
	reg [4:0] i;

   dout = 0;
	if(cs) begin
		if (addr == 0) dout = 16'hC0CA;
		if (addr == 1) dout = 16'hCAFE;
		if (c2p_sel)   for(i=0;i<16;i=i+1'd1) dout[i] = buff[{rptr[0],~i[3:0]}][rptr[3:1]];
	end
end

endmodule
