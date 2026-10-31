//This module maps physical 512KB blocks of every memory chip to different memory ranges in Amiga
//
// Since we currently have 8M for non-fastram, this was simplified to
// use the full address for mapping.  We only use this part to signal
// that ram access should occur and to emulate the mirroring behaviour
// of the lower 2M when less than 2M chipram is selected. Moreover we
// use sel_kick downstream, because there is no boot overlay
// information in the address alone.

module minimig_bankmapper
(
	input        chip0,          // chip ram select: 1st 512 KB block
	input        chip1,          // chip ram select: 2nd 512 KB block
	input        chip2,          // chip ram select: 3rd 512 KB block
	input        chip3,          // chip ram select: 4th 512 KB block
	input        slow0,          // slow ram select: 1st 512 KB block 
	input        slow1,          // slow ram select: 2nd 512 KB block 
	input        slow2,          // slow ram select: 3rd 512 KB block 
	input        kick,           // Kickstart ROM address range select
	input        kick1mb,        // 1MB Kickstart 'upper' half
	input        kick256kmirror, // mirror f8-fb to fc-ff in a1k mode
	input        cart,           // Action Reply memory range select
	input  [1:0] memory_config,  // memory configuration
	output [7:0] bank            // bank select
);

assign bank = bank_r;

reg [7:0] bank_r;

always @(*) begin
	bank_r[7:4] = { kick,kick256kmirror , chip3 | chip2 | chip1 | chip0,  kick1mb  | slow0 | slow1 | slow2 | cart} ;
	case (memory_config)
		0: bank_r[3:0] = {    1'b0,  1'b0,          1'b0, chip3 | chip2 | chip1 | chip0 }; // 0.5M CHIP
		1: bank_r[3:0] = {    1'b0,  1'b0, chip3 | chip1,                 chip2 | chip0 }; // 1.0M CHIP
		2: bank_r[3:0] = {    1'b0, chip2,         chip1,                         chip0 }; // 1.5M CHIP
		3: bank_r[3:0] = {   chip3, chip2,         chip1,                         chip0 }; // 2.0M CHIP
	endcase
end

endmodule

