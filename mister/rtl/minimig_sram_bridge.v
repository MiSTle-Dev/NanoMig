// This module interfaces the minimig's synchronous bus to the asynchronous sram
// on the Minimig rev1.0 board
//
// JB:
// 2008-09-23	- generation of write strobes moved to clk28m clock domain


module minimig_sram_bridge
(
	//clocks
	input         clk,			// 28 MHz system clock
	input         c1,				// clock enable signal
	input         c3,				// clock enable signal	

	//chipset internal port
	input	  [7:0] bank,			// memory bank select (512KB)
	input	 [23:1] address_in,	// bus address
	input	 [15:0] data_in,		// bus data in
	output [15:0] data_out,		// bus data out
	input         rd,			   // bus read
	input         hwr,			// bus high byte write
	input         lwr,			// bus low byte write

	//RAM external signals
	output        _bhe,			// sram upper byte
	output        _ble,   		// sram lower byte
	output        _we,			// sram write enable
	output        _oe,			// sram output enable
	output [22:1] address,		// sram address bus
	output [15:0] data,	  		// sram data das
	input  [15:0] ramdata_in	// sram data das in
);	 

/* basic timing diagram

phase          : Q0  : Q1  : Q2  : Q3  : Q0  : Q1  : Q2  : Q3  : Q0  : Q1  :
               :     :     :     :     :     :     :     :     :     :     :
                ___________             ___________             ___________
clk         ___/           \___________/           \___________/           \_____ (7.09 MHz - dedicated clock)

               :     :     :     :     :     :     :     :     :     :     :
                __    __    __    __    __    __    __    __    __    __    __
clk28m      ___/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__ (28.36 MHz - dedicated clock)
               :     :     :     :     :     :     :     :     :     :     :
             ___________             ___________             ___________
c1       ___/           \___________/           \___________/           \_____ (7.09 MHz)
               :     :     :     :     :     :     :     :     :     :     :
                   ___________             ___________             ___________
c3       _________/           \___________/           \___________/            (7.09 MHz)
               :     :     :     :     :     :     :     :     :     :     :
            _________                   _____                   _____   
_ce                  \_________________/     \_________________/     \___________ (ram chip enable)
               :     :     :     :     :     :     :     :     :     :     :
            _______________             ___________             ___________   
_we                        \___________/           \___________/           \_____ (ram write strobe)
               :     :     :     :     :     :     :     :     :     :     :
            _________                   _____                   _____
_oe                  \_________________/     \_________________/     \___________ (ram output enable)
               :     :     :     :     :     :     :     :     :     :     :
*/

// generate enable signal if any of the banks is selected
wire	enable = |bank[7:0]; // indicates memory access cycle

assign _we   = (!hwr && !lwr) | !enable;
assign _oe   = !rd  | !enable; 
assign _bhe  = !hwr | !enable;
assign _ble  = !lwr | !enable;

assign address[17:1]  = address_in[17:1];
assign address[22:18] = bank[6] ? 5'b111_11 : //access f8-fb and !ovl and !halt, map to fc-ff
                       (bank[7] ? {4'b111_1, address_in[18]} : //access to f8-ff or ovl 
                       (bank[5] ? {2'b0, bank[3]|bank[2], bank[3]|bank[1],address_in[18]} :
                        address_in[22:18])); //chipram access

assign data_out[15:0] = (enable && rd) ? ramdata_in[15:0] : 16'b0000000000000000;
assign data[15:0]     = data_in[15:0];

endmodule
