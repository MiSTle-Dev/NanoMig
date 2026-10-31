// This module interfaces Minimig's synchronous bus to the 68SEC000 CPU
//
// cycle exact CIA interface:
// ECLK low for 6 cycles and high for 4
// data latched with falling edge of ECLK
// VPA sampled 3 CLKs before rising edge of ECLK
// VMA asserted one clock later if VPA recognized
// DTACK sampled one clock before ECLK falling edge
//
//             ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___
// CLK     ___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___
//         ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___
// CPU_CLK    \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/
//         ___ _______ _______ _______ _______ _______ _______ _______ _______ _______ _______ _______
//         ___X___0___X___1___X___2___X___3___X___4___X___5___X___6___X___7___X___8___X___9___X___0___
//         ___                                                 _______________________________
// ECLK       \_______________________________________________/                               \_______
//                                    |       |_VMA_asserted                          
//                                    |_VPA_sampled                   _______________           ______
//                                                                            \\\\\\\\_________/       DTACK asserted (7MHz)
//                                                                                    |__DTACK_sampled (7MHz) 
//                                                                    _____________________     ______
//                                                                                         \___/       DTACK asserted (28MHz)
//                                                                                          |__DTACK_sampled (28MHz)
//
// NOTE: in 28MHz mode this timing model is not (yet?) supported, CPU talks to CIAs with no waitstates
//


module minimig_m68k_bridge
(
	input	        clk,           // 28 MHz system clock
	input         clk7_en,
	input         clk7n_en,
	input	        c1,            // clock enable signal
	input	        c3,            // clock enable signal
	input	  [9:0] eclk,          // ECLK enable signal
	input	        vpa,           // valid peripheral address (CIAs)
	input	        dbr,           // data bus request, Gary keeps CPU off the bus (custom chips transfer data)
	input	        dbs,           // data bus slowdown (access to chip ram or custom registers)
	input	        xbs,           // cross bridge access (active dbr holds off CPU access)
	input         nrdy,          // target device is not ready
	output        bls,           // blitter slowdown, tells the blitter that CPU wants the bus
	input	        cck,           // colour clock enable, active when dma can access the memory bus
	input   [3:0] memory_config, // system memory config
	input	        _as,           // m68k adress strobe
	input	        _lds,          // m68k lower data strobe d0-d7
	input	        _uds,          // m68k upper data strobe d8-d15
	input	        r_w,           // m68k read / write
	input         cpu_long,
	output        long_en,
	output        _dtack,        // m68k data acknowledge to cpu
	output        rd,            // bus read 
	output        hwr,           // bus high write
	output        lwr,           // bus low write
	input	 [23:1] address,       // external cpu address bus
	output [23:1] address_out,   // internal cpu address bus output
	output [15:0] data,          // external cpu data bus
	input  [15:0] cpudatain,
	output [15:0] data_out,      // internal data bus output
	input  [15:0] data_in,       // internal data bus input
	output        rd_cyc,        // early rd signal can be used to delay DTACK

	// UserIO interface
	input         _cpu_reset,
	input         cpu_halt,
	input         host_cs,
	input  [23:1] host_adr,
	input         host_we,
	input   [1:0] host_bs,
	input  [15:0] host_wdat,
	output [15:0] host_rdat,
	output        host_ack
);

/*
68000 bus timing diagram

          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
        7 . 0 . 1 . 2 . 3 . 4 . 5 . 6 . 7 . 0 . 1 . 2 . 3 . 4 . 5 . 6 . 7 . 0 . 1
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
           ___     ___     ___     ___     ___     ___     ___     ___     ___
CLK    ___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _____________________________________________                         _____		  
R/W                 \_ _ _ _ _ _ _ _ _ _ _ _/       \_______________________/     
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _________ _______________________________ _______________________________ _		  
ADDR   _________X_______________________________X_______________________________X_
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _____________                     ___________                     _________
/AS                 \___________________/           \___________________/         
          .....   .   .   .       .   .   .....   .   .   .   .       .   .....
       _____________        READ         ___________________    WRITE    _________
/DS                 \___________________/                   \___________/         
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _____________________     ___________________________     _________________
/DTACK                      \___/                           \___/                 
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
                                     ___
DIN    -----------------------------<___>-----------------------------------------
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
                                                         ___________________
DOUT   -------------------------------------------------<___________________>-----
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
*/

// halt is enabled when halt request comes in and cpu bus is idle
reg halt=0;
always @ (posedge clk) begin
	if (clk7_en) begin
		if (_as && cpu_halt) halt <= #1 1'b1;
		else if (_as && !cpu_halt) halt <= #1 1'b0;
	end
end

//latched valid peripheral address
reg lvpa; // latched valid peripheral address (CIAs)
always @(posedge clk) if (clk7_en) lvpa <= vpa;

//vma output
reg vma; // valid memory address (synchronised VPA with ECLK)
always @(posedge clk) begin
	if (clk7_en) begin
		if (eclk[9]) vma <= 0;
		else if (eclk[3] && lvpa) vma <= 1;
	end
end

//latched CPU bus control signals
reg lr_w,l_as,l_dtack,l_long; // synchronised inputs
always @ (posedge clk) begin
	if (clk7_en) begin
		lr_w <= !halt ? r_w : !host_we;
		l_as <= !halt ? _as : !host_cs;
		l_dtack <= _dtack;
		l_long <= !halt & cpu_long;
	end
end

reg l_uds,l_lds;
always @(posedge clk) begin
  l_uds <= !halt ? _uds : !(host_bs[1]);
  l_lds <= !halt ? _lds : !(host_bs[0]);
end

wire _as_and_cs = !halt ? _as : !host_cs;

// data transfer acknowledge in normal mode
reg _ta_n; // transfer acknowledge
always @(posedge clk or posedge _as_and_cs) begin
	if (_as_and_cs) _ta_n <= 1;
	else if (clk7n_en) begin
		if (!l_as && cck && ((!vpa && !(dbr && dbs)) || (vpa && vma && eclk[8])) && !nrdy) _ta_n <= 0; 
	end
end

assign host_ack = !_ta_n;
assign _dtack   = _ta_n;

// synchronous control signals
wire   enable = ~l_as & ~l_dtack & ~cck;
assign rd = enable & lr_w;
assign hwr = enable & ~lr_w & ~l_uds;
assign lwr = enable & ~lr_w & ~l_lds;
assign long_en = enable & l_long;
assign rd_cyc = ~l_as & lr_w;

//blitter slow down signalling, asserted whenever CPU is missing bus access to chip ram, slow ram and custom registers 
assign bls = dbs & ~l_as & l_dtack;

reg [15:0] cpudatain_r;
always @(posedge clk) cpudatain_r <= cpudatain;

// data_out multiplexer and latch   
assign data_out = !halt ? cpudatain_r : host_wdat;

reg [15:0] ldata_in;	// latched data_in
always @(posedge clk) if (!c1 && c3 && enable) ldata_in <= data_in;

// --------------------------------------------------------------------------------------

// CPU data bus tristate buffers and output data multiplexer
assign data[15:0] = ldata_in;
assign host_rdat  = ldata_in;

reg [23:1] address_r;
always @(posedge clk) address_r <= address;

assign address_out[23:1] = !halt ? address_r : host_adr[23:1];

endmodule

