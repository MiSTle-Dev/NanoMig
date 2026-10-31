//syscontrol handles the startup of the FGPA,
//after fpga config, it automatically does a global system reset and asserts boot.
//the boot signal puts gary in a special mode so that the bootrom
//is mapped into the system memory map.	The firmware in the bootrom
//then loads the kickstart via the diskcontroller into the kickstart ram area.
//When kickstart has been loaded, the bootrom asserts bootdone by selecting both cia's at once. 
//This resets the system for a second time but it also de-asserts boot.
//Thus, the system now boots as a regular amiga.
//Subsequent resets by asserting mrst will not assert boot again.
//
// JB:
// 2008-07-11	- reset to bootloader
// 2009-03-13	- shorter reset
// 2009-08-17	- reset generator modification


module minimig_syscontrol
(
	input	 clk,     //bus clock
	input  clk7_en,
	input	 cnt,     //pulses for counting
	input	 mrst,    //master/user reset input
	output reg reset    //global synchronous system reset
);

reg [2:0] rst_cnt = 0; //reset timer SHOULD BE CLEARED BY CONFIG

//reset timer and mrst control
always @(posedge clk) begin
	if (clk7_en) begin
		if (mrst) rst_cnt <= 0;
		else if (~rst_cnt[2] && cnt) rst_cnt <= rst_cnt + 3'd1;
		reset <= ~rst_cnt[2];
	end
end

endmodule
