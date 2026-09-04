//--------------------------------------------------------------------------//
//--------------------------------------------------------------------------//
//                                                                          //
// Copyright (c) 2009-2011 Tobias Gubener                                   //
// Copyright (c) 2017-2019 Alexey Melnikov                                  //
// Subdesign fAMpIGA by TobiFlex                                            //
//                                                                          //
// This is the cpu wrapper to generate 68K Bus signals                      //
// and configure Zorro cards                                                //
//                                                                          //
// This source file is free software: you can redistribute it and/or modify //
// it under the terms of the GNU General Public License as published        //
// by the Free Software Foundation, either version 3 of the License, or     //
// (at your option) any later version.                                      //
//                                                                          //
// This source file is distributed in the hope that it will be useful,      //
// but WITHOUT ANY WARRANTY; without even the implied warranty of           //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            //
// GNU General Public License for more details.                             //
//                                                                          //
// You should have received a copy of the GNU General Public License        //
// along with this program.  If not, see <http://www.gnu.org/licenses/>.    //
//                                                                          //
//--------------------------------------------------------------------------//
//--------------------------------------------------------------------------//

// if no CPU has explicitely been enabled, then only the fx68k is being used
`ifndef ENABLE_TG68K
  `ifndef ENABLE_FX68K
    `define ENABLE_FX68K
  `endif
`endif

`define TG68K_A24      // limit address space of TG68K to 24 bit

// if only one CPU is enabled, then this is being used for all
// configurations. This e.g. allows the tg68k to be used in plain 68000 mode as well
`ifdef ENABLE_TG68K
  `ifdef ENABLE_FX68K
    `define CPU_SWITCHABLE
   `endif
`endif

module cpu_wrapper
(
	input		  reset,
	output reg	  reset_out,

	input		  clk,
	input		  ph1,
	input		  ph2,

	input [1:0]	  cpucfg,
	input [2:0]	  fastramcfg,
	input [1:0]	  chipramcfg,
	input [1:0]	  slowramcfg,
	input [2:0]	  turbocfg,
	input		  bootrom,

	output reg [23:1] chip_addr,
	input [15:0]	  chip_dout,
	output reg [15:0] chip_din,
	output reg	  chip_as,
	output reg	  chip_uds,
	output reg	  chip_lds,
	output reg	  chip_rw,
	input		  chip_dtack,
	input [2:0]	  chip_ipl,

`ifdef FASTCHIP_DEPRECATED
	input [15:0]	  fastchip_dout,
	output reg	  fastchip_sel,
	output		  fastchip_lds,
	output		  fastchip_uds,
	output		  fastchip_rnw,
	output reg	  fastchip_lw,
	input		  fastchip_selack,
	input		  fastchip_ready,
`endif

	output		  ramreq,
	output [28:1]	  ramaddr,
	output [15:0]	  ramdin,
	input [15:0]	  ramdout,
	input		  ramready,
	output		  ramlds,
	output		  ramuds,
	output		  ramshared,

`ifdef ENABLE_TOCCATA
	output reg	  toccata_ena,
	output reg [7:0]  toccata_base,
`endif

	output reg [1:0]  cpustate,
	output reg [3:0]  cacr,
	output reg [31:0] nmi_addr,
	output		  cpu_clkena  // the tg68k advances on this enable (bus handshake consumption)
);

wire cpu_req = cpustate != 2'b01 && !skip_fetch;

reg  [31:0] cpu_addr;
reg  [15:0] cpu_dout;
reg         wr;
reg         uds_in;
reg         lds_in;

reg       z2ram_ena;
reg [4:0] z3ram_base0;
reg [3:0] z3ram_base1;
reg       z3ram_ena0;
reg       z3ram_ena1;

wire sel_z3ram0 = (cpu_addr[31:27] == z3ram_base0) && z3ram_ena0;
wire sel_z3ram1 = (cpu_addr[31:28] == z3ram_base1) && z3ram_ena1;
wire sel_z2ram  = (cpu_addr[31:24] == 8'h00) && (cpu_addr[23] ^ |cpu_addr[22:21]) && z2ram_ena; // addr[23:21] = 1..4
wire sel_zram   = sel_z3ram0 | sel_z3ram1 | sel_z2ram;

`ifdef MISTER_DEPRECATED
wire sel_dd  = (cpu_addr[31:16] == 16'h00DD) && (cpu_addr[15:13] == 'b010);
wire sel_rtg = (cpu_addr[31:24] == 8'h02);
`else
wire sel_dd  = 1'b0;
wire sel_rtg = 1'b0;
`endif

// don't sel_kickram when writing
wire cchip;
wire ckick;
wire cslow;

reg [2:0] fastramcfg_d;
reg [1:0] chipramcfg_d;
reg [1:0] slowramcfg_d;

always @(posedge clk) begin
    if (~reset | ~reset_out) begin
        fastramcfg_d <= fastramcfg;
        chipramcfg_d <= chipramcfg;
        slowramcfg_d <= slowramcfg;
    end
end

// NanoMig: only the real $f8xxxx kickstart range is served from sdram in
// turbo kick mode. The $e0xxxx extended rom area of the MiSTer mapping is
// NOT initialized in sdram here, so those reads must keep going to the
// chip bus (which returns zeros = no extension rom) instead of reading
// random uninitialized sdram content.
wire sel_kick    = cpu_addr[31:24] == 8'h00 && (&cpu_addr[23:19]);  // $F8xxxx
wire sel_kickram = sel_kick && ckick && wr;

wire sel_chip    = cpu_addr[31:24] == 8'h00 && (cpu_addr[23:21] == 3'b000) &&
                   ((chipramcfg_d != 2'b00) || (cpu_addr[20:19] == 2'b00)) &&
                   ((chipramcfg_d != 2'b01) || (cpu_addr[20] == 1'b0)) &&
                   ((chipramcfg_d != 2'b10) || (cpu_addr[20:19] != 2'b11));  // $000000 - $1FFFFF
wire sel_chipram = sel_chip && cchip;

wire sel_slow    = cpu_addr[31:24] == 8'h00 &&
                   ((cpu_addr[23:20] == 4'b1100 && ((cpu_addr[19] == 1'b0 && slowramcfg_d != 2'b00) || (cpu_addr[19] == 1'b1 && slowramcfg_d[1] == 1'b1))) ||
                    (cpu_addr[23:20] == 4'b1101 &&  (cpu_addr[19] == 1'b0 && slowramcfg_d == 2'b11)));  // $C00000 - $D7FFFF
wire sel_slowram = sel_slow && cslow;

wire sel_nmi_vector;

reg    ram_dtack = 1'b1;
wire   ramsel    = cpu_req & ~sel_nmi_vector & (sel_zram | sel_chipram | sel_kickram | sel_slowram | sel_dd | sel_rtg);
assign ramreq    = ramsel & ram_dtack;
assign ramshared = sel_dd;

// NMI
reg  [31:0] vbr;
always @(posedge clk) nmi_addr <= vbr + 32'h7c;

`ifdef ENABLE_CART
// we route everything hrtmon related through cart.v (needs a couple of signals to
// decide what to do, would not be good style to replicate that here).
assign sel_nmi_vector = (cpu_addr[31:2] == nmi_addr[31:2]) && (cpustate == 2'b10);
`else
assign sel_nmi_vector = 1'b0;
`endif

wire [15:0] ramdat;

assign ramlds = sel_rtg ? uds_in : lds_in;
assign ramuds = sel_rtg ? lds_in : uds_in;
assign ramdin = sel_rtg ? {cpu_dout[7:0],cpu_dout[15:8]} : cpu_dout;
assign ramdat = sel_rtg ? {ramdout[7:0], ramdout[15:8]}  : ramdout;

//       Main  DDx  RTG  8M  128M  256M
//       ----  ---  ---  --  ----  ----
//        SDR  DDR  RTG  Z2  Z3_0  Z3_1
// 28      0    0    0   1    0     1
// 27      0    0    0   1    1     X
// 26      0    1    1   0    X     X
// 25-23   0   111  110  0    X     X
// supported configs: SDR + (Z2, Z3_1, Z3_0+Z3_1)

// Mapping for TangNano 20k
// Chip RAM,      00-1f => 00-1f
// 4MiB Fast RAM, 20-5f => 20-5f;
// Slow RAM,      c0-d7 => 60-77;
// Kick ROM,      f8-ff => 78-7f;
// 2MiB Fast RAM  60-7f => a0-bf;
// 2MiB Fast RAM  80-9f => 80-9f;
// All other bits passed through unmodified.

assign ramaddr[28:24] = 5'b0;

`ifdef ENABLE_RAM32
assign ramaddr[23:21] = (cpu_addr[23:21] == 3'b011) ? 3'b101 :	// $600000-$7FFFFF -> $A00000-$BFFFFF
			(cpu_addr[23:21] == 3'b100) ? 3'b100 :	// $800000-$9FFFFF -> $800000-$9FFFFF
			{1'b0, cpu_addr[22], cpu_addr[21] | cpu_addr[23]};	// $000000-$FFFFFF -> $000000-$7FFFFF
`else
// save logic for devices without 32MiB RAM
assign ramaddr[23:21] = {1'b0, cpu_addr[22], cpu_addr[21] | cpu_addr[23]};
`endif

assign ramaddr[20:1] = cpu_addr[20:1];

`ifdef FASTCHIP_DEPRECATED
assign fastchip_lds = lds_in;
assign fastchip_uds = uds_in;
assign fastchip_rnw = wr;
`endif

wire	  sel_autoconfig;
reg [1:0] autocfg_card;
reg [3:0] autocfg_data;

wire [15:0] cpu_din = ramsel ? ramdat :
`ifdef FASTCHIP_DEPRECATED
	    fastchip_selack ? fastchip_dout :
`endif
	    {sel_autoconfig ? autocfg_data : chip_data[15:12], chip_data[11:0]};

reg         skip_fetch;
wire        skip_fetch_i;
reg  [15:0] chip_data;

wire [15:0] cpu_dout_o;
wire [23:1] cpu_addr_o;
wire  [2:0] fc_o;
wire        wr_o;
wire        as_o;
wire        uds_o;
wire        lds_o;
wire        reset_out_o;

always @* begin
`ifdef CPU_SWITCHABLE
	if( cpucfg[1] ) begin
`endif
`ifdef ENABLE_TG68K
		cpu_dout     = cpu_dout_p;
		cpustate     = cpustate_p;
		cacr         = cacr_p;
`ifdef ENABLE_ENABLE
`ifndef CHIPRAM_CACHE
		// prevent chipram access through cache
		cacr[0]      |= sel_chipram;
`endif
`endif
		vbr          = vbr_p;
		wr           = wr_p;
		uds_in       = uds_p;
		lds_in       = lds_p;
		reset_out    = reset_out_p;
		chip_as      = c_as;
		chip_rw      = c_rw;
		chip_uds     = c_uds;
		chip_lds     = c_lds;
		chip_addr    = cpu_addr_p[23:1];
		chip_din     = cpu_dout_p;
		chip_data    = chipdout_i;
		skip_fetch   = skip_fetch_i;
`ifdef TG68K_A24
		cpu_addr     = { 8'h00, cpu_addr_p[23:0] };
`ifdef FASTCHIP_DEPRECATED
		fastchip_sel = 0;
		fastchip_lw  = 0;
`endif
`else
		cpu_addr     = cpu_addr_p;
`ifdef FASTCHIP_DEPRECATED
		fastchip_sel = cpu_req & !cpu_addr_p[31:24];
		fastchip_lw  = longword;
`endif
`endif
`endif
`ifdef CPU_SWITCHABLE
	end
	else begin
`endif
 `ifdef ENABLE_FX68K
		cpu_dout     = cpu_dout_o;
		cpu_addr     = {8'b0, cpu_addr_o, 1'b0};
		casez ({as_o, fc_o[1], fc_o[0], wr_o})
			4'b0101: cpustate = 2'b00;  // fetch
			4'b0011: cpustate = 2'b10;  // data read
			4'b0zz0: cpustate = 2'b11;  // write
			default: cpustate = 2'b01;  // internal
		endcase
		cacr         = 1;
		vbr          = 0;
		wr           = wr_o;
		uds_in       = uds_o;
		lds_in       = lds_o;
		reset_out    = reset_out_o;
		// ramsel here prevents fastram
		// access to be routed through chipset
		chip_as      = ramsel | as_o;
		chip_rw      = wr_o;
		chip_uds     = uds_o;
		chip_lds     = lds_o;
		chip_addr    = cpu_addr_o[23:1];
		chip_din     = cpu_dout_o;
		chip_data    = chip_dout;
`ifdef FASTCHIP_DEPRECATED
		fastchip_sel = 0;
		fastchip_lw  = 0;
`endif
		skip_fetch   = 0;
`endif
`ifdef CPU_SWITCHABLE
	end
`endif
end

// ramready pulses at ph1, but
// fx68k latches DTACKn at ph2;
// so we need to keep DTACKn value
// until it can be ready by fx68k
always @(posedge clk) begin
	if (~reset | ~reset_out)
		ram_dtack <= 1'b1;
	else begin
`ifdef CPU_SWITCHABLE
		if( !cpucfg[1] ) begin
`endif
`ifdef ENABLE_FX68K
			if (ph2)
				ram_dtack <= ramsel;
			if (ramready)
				ram_dtack <= 1'b0;
`endif
`ifdef CPU_SWITCHABLE
		end else
			ram_dtack <= 1'b1;  // ignored for TG68
`endif
	end
end

wire [15:0] cpu_dout_p;
wire [31:0] cpu_addr_p;
wire  [1:0] cpustate_p;
wire  [3:0] cacr_p;
wire [31:0] vbr_p;
wire        wr_p;
wire        uds_p;
wire        lds_p;
wire        reset_out_p;
wire        longword;
reg [2:0]   cpu_ipl;
reg         chipready;

// tg68_armed keeps the cpu from being clocked before the reset has been
// released for at least one cycle, otherwise the TG68K can hang on startup
reg  tg68_armed;
always @(posedge clk) tg68_armed <= reset;

`ifdef CPU_SLOW14
// Advance the TG68K at most every second clk cycle (14MHz effective on a
// 28MHz clock, matching the 14MHz 68EC020 of a real A1200). This makes all
// TG68K internal register-to-register paths true two-cycle paths which is
// required for timing closure on slow devices. The single cycle ready
// strobes of the bus interfaces are latched so no handshake is ever lost.
// Instead of a fixed phase enable only a minimum gap of one idle cycle
// after every advance is enforced, so memory handshakes are consumed at
// the earliest opportunity and no average alignment latency is added.
reg  gap;       // previous clk cycle advanced the cpu
reg  readyhold;
wire ready_now = chipready | ramready
`ifdef FASTCHIP_DEPRECATED
     | fastchip_ready
`endif
     ;
wire clkena_slow = ~gap & ((~cpu_req & tg68_armed) | ready_now | readyhold);
assign cpu_clkena = clkena_slow;
always @(posedge clk) begin
	gap <= clkena_slow;
	if (clkena_slow)               readyhold <= 1'b0;
	else if (ready_now & cpu_req)  readyhold <= 1'b1;
end
`else
assign cpu_clkena = (~cpu_req & tg68_armed) | chipready | ramready
`ifdef FASTCHIP_DEPRECATED
		    | fastchip_ready
`endif
;
`endif

`ifdef ENABLE_TG68K
TG68KdotC_Kernel
`ifndef VERILATOR
// verilator runs the verilog translated variant which doesn't support configuration but
// is hard coded for full configurability (all configs set to 2)
#(
	.SR_Read(2),        // 0=>user,   1=>privileged,    2=>switchable with CPU(0)
	.VBR_Stackframe(2), // 0=>no,     1=>yes/extended,  2=>switchable with CPU(0)
	.extAddr_Mode(2),   // 0=>no,     1=>yes,           2=>switchable with CPU(1)
	.MUL_Mode(2),       // 0=>16Bit,  1=>32Bit,         2=>switchable with CPU(1),  3=>no MUL,
	.DIV_Mode(2),       // 0=>16Bit,  1=>32Bit,         2=>switchable with CPU(1),  3=>no DIV,
	.BitField(2),       // 0=>no,     1=>yes,           2=>switchable with CPU(1)
	.MUL_Hardware(1)    // 0=>no,  	  1=>yes,
)
`endif
cpu_inst_p
(
`ifdef VERILATOR
  // the verilog translation of the kernel used for simulation has
  // all-lowercase port names
  .clk(clk),
  .nreset(reset),
  .clkena_in(cpu_clkena),
  .data_in(cpu_din),
  .ipl(cpu_ipl),
  .ipl_autovector(1),
  .regin_out(),
  .addr_out(cpu_addr_p),
  .data_write(cpu_dout_p),
  .nwr(wr_p),
  .nuds(uds_p),
  .nlds(lds_p),
  .nresetout(reset_out_p),
  .longword(longword),
  .cpu(cpucfg),
  .busstate(cpustate_p),		// 0: fetch code, 1: no memaccess, 2: read data, 3: write data
  .cacr_out(cacr_p),
  .vbr_out(vbr_p)
`else
  .clk(clk),
 `ifdef ENABLE_FX68K
  .nReset(reset && cpucfg[1]),
 `else
  .nReset(reset),
 `endif
  .clkena_in(cpu_clkena),
  .data_in(cpu_din),
  .IPL(cpu_ipl),
  .IPL_autovector(1'b1),
  .berr(1'b0),
  .CPU(cpucfg),
  .addr_out(cpu_addr_p),
  .data_write(cpu_dout_p),
  .nWr(wr_p),
  .nUDS(uds_p),
  .nLDS(lds_p),
  .busstate(cpustate_p),		// 0: fetch code, 1: no memaccess, 2: read data, 3: write data
  .longword(longword),
  .nResetOut(reset_out_p),
  .FC(),
  .clr_berr(),
  .skipFetch(skip_fetch_i),
  .regin_out(),
  .CACR_out(cacr_p),
  .VBR_out(vbr_p)
`endif
);
`endif

`ifdef ENABLE_FX68K
fx68k cpu_inst_o
(
	.clk(clk),
	.enPhi1( ph1 ),
	.enPhi2( ph2 ),
`ifdef ENABLE_TG68K
	.extReset(~reset && ~cpucfg[1]),
	.pwrUp(~reset && ~cpucfg[1]),
`else
	.extReset( ~reset ),
	.pwrUp( ~reset ),
`endif
	.oRESETn(reset_out_o),
	.HALTn(1),
	.eRWn(wr_o),
	.ASn(as_o),
	.LDSn(lds_o),
	.UDSn(uds_o),
	.DTACKn(ramsel ? ram_dtack : chip_dtack),

	.FC0(fc_o[0]),
	.FC1(fc_o[1]),
	.FC2(fc_o[2]),

	.VPAn(~&fc_o),
	.BERRn(1),
	.BRn(1),
	.BGACKn(1),
	.IPL0n(chip_ipl[0]),
	.IPL1n(chip_ipl[1]),
	.IPL2n(chip_ipl[2]),
	.iEdb(cpu_din),
	.oEdb(cpu_dout_o),
	.eab(cpu_addr_o)
);
`endif

reg turbochip_d;
reg turbokick_d;
reg turbodata_d;

assign cchip = turbochip_d && (turbodata_d || cpustate == 2'b00);
assign ckick = turbokick_d && (turbodata_d || cpustate == 2'b00);

// enable turboslow either when
// 1) turbochip is enabled
// 2) turbodata is enabled
assign cslow = turbochip_d | turbodata_d;

always @(posedge clk) begin
	if (~reset | ~reset_out) begin
		turbochip_d <= 0;
		turbokick_d <= 0;
		turbodata_d <= 0;
	end
	else if (~cpu_req) begin	// No mem access, so safe to switch chipram access mode
		turbochip_d <= turbocfg[0];
		turbokick_d <= turbocfg[1];
		turbodata_d <= turbocfg[2];
	end
end

wire cfg_z3 = fastramcfg_d[2] & cpucfg[1];
`ifdef ENABLE_TOCCATA
reg       ac_toccata;
`endif

always @(*) begin
	autocfg_data = 4'b1111;

`ifdef ENABLE_TOCCATA
	if (~ac_toccata) begin
		case (chip_addr[6:1])
			6'h0: autocfg_data = 4'b1100; // Zorro-II card, no link, no ROM
			6'h1: autocfg_data = 4'b0001; // Next board not related, size 'h64k
			// Inverted from here on
			6'h3: autocfg_data = 4'b0011; // Lower byte product number
			6'h5: autocfg_data = 4'b1101; // logical size 64k
			6'h8: autocfg_data = 4'b1011; // Manufacturer ID: 0x4754
			6'h9: autocfg_data = 4'b1000;
			6'ha: autocfg_data = 4'b1010;
			6'hb: autocfg_data = 4'b1011;
			default: ;
		endcase
	end else
`endif
	if (autocfg_card) begin
		if (~cfg_z3) begin
			// Zorro II RAM (Up to 8 meg at 0x200000)
			case (chip_addr[6:1])
				6'b000000: autocfg_data = 4'b1110;	// Zorro-II card, add mem, no ROM
				6'b000001:
					case (fastramcfg_d)
							   1: autocfg_data = 4'b0110; // 2MB
							   2: autocfg_data = 4'b0111; // 4MB
`ifdef ENABLE_RAM32
						default: autocfg_data = 4'b0000; // 8MB
`else
						default: autocfg_data = 4'b0111; // 4MB
`endif
					endcase
				6'b001000: autocfg_data = 4'b1110;	// Manufacturer ID: 0x139c
				6'b001001: autocfg_data = 4'b1100;
				6'b001010: autocfg_data = 4'b0110;
				6'b001011: autocfg_data = 4'b0011;
				6'b010011: autocfg_data = 4'b1110; //serial=1
				  default:;
			endcase
		end
		else begin
			// Zorro III RAM 128MB/256MB
			case (chip_addr[6:1])
				6'b000000: autocfg_data = 4'b1010;	// Zorro-III card, add mem, no ROM
				6'b000001: autocfg_data = autocfg_card[1] ? 4'b0011 : 4'b0100;	// 128MB or 256MB, extended
				6'b000010: autocfg_data = 4'b1110;	// ProductID=0x10 (only setting upper nibble)
				6'b000100: autocfg_data = 4'b0000;	// Memory card, not silenceable, Extended size, reserved.
				6'b000101: autocfg_data = 4'b1111;	// 0000 - logical size matches physical size TODO change this to 0001, so it is autosized by the OS, WHEN it will be 24MB.
				6'b001000: autocfg_data = 4'b1110;	// Manufacturer ID: 0x139c
				6'b001001: autocfg_data = 4'b1100;
				6'b001010: autocfg_data = 4'b0110;
				6'b001011: autocfg_data = 4'b0011;
				6'b010011: autocfg_data = {2'b11, ~autocfg_card};	// serial=1/2
				  default:;
			endcase
		end
	end
end

assign sel_autoconfig = fastramcfg_d && chip_addr[23:16] == 8'b11101000 && autocfg_card; //$E80000 - $E8FFFF

always @(posedge clk) begin
	reg old_uds;
	old_uds <= chip_uds;

	if (~reset | ~reset_out) begin
		autocfg_card <= 1;		//autoconfig on
		z2ram_ena <= 0;
		z3ram_ena0 <= 0;
		z3ram_ena1 <= 0;
		z3ram_base0 <= 1;
		z3ram_base1 <= 1;
`ifdef ENABLE_TOCCATA
		ac_toccata<=1'b0;
		toccata_ena<=1'b0;
`endif
	end
	else if (sel_autoconfig && ~chip_rw && ~chip_uds && old_uds) begin
`ifdef ENABLE_TOCCATA
		if (~ac_toccata) begin
			if (chip_addr[6:1] == 6'b100100) begin // Register 0x48 - config, Toccata card in ZII io space ($E90000)
				toccata_ena <= 1;
				toccata_base <= cpu_dout[7:0];
				ac_toccata<=1'b1;
			end
		end else
`endif
	if (~cfg_z3) begin
			if (chip_addr[6:1] == 6'b100100) begin // Register 0x48 - config, ZII RAM
				z2ram_ena <= 1;
				autocfg_card <= 0;
			end
		end else if (chip_addr[6:1] == 6'b100010)	begin // Register 0x44, assign base address to ZIII RAM.
			if (autocfg_card == 1) begin
				z3ram_base1 <= cpu_dout[15:12];
				z3ram_ena1 <= 1;
				autocfg_card <= {fastramcfg_d[0], 1'b0};
			end
			else begin
				z3ram_base0 <= cpu_dout[15:11];
				z3ram_ena0 <= 1;
				autocfg_card <= 0;
			end
		end
	end
end

wire chipreq = cpu_req & ~ramsel
`ifdef FASTCHIP_DEPRECATED
     & ~fastchip_selack
`endif
;

reg [15:0] chipdout_i;
reg        c_as,c_rw,c_uds,c_lds;

always @(posedge clk, negedge reset) begin
	reg [1:0] stage;
	reg waitm;
	reg ready;

	if(~reset) begin
		stage <= 0;
		c_as <= 1;
		c_rw <= 1;
		c_uds <= 1;
		c_lds <= 1;
		chipready <= 0;
		ready <= 0;
	end else begin
		if (ph2) begin
			waitm <= chip_dtack;
			if(~stage[0]) cpu_ipl <= chip_ipl;
		end
		chipready <= 0;
		if (ph1) begin
			chipready <= ready;
			ready <= 0;
			case (stage)
				0: if (chipreq) begin
						c_as <= 0;
						c_rw <= wr;
						c_uds <= uds_in;
						c_lds <= lds_in;
						stage <= 1;
					end
				1: stage <= 2;
				2: begin
						chipdout_i <= chip_dout;
						if (~waitm) begin
							c_as <= 1;
							c_rw <= 1;
							c_uds <= 1;
							c_lds <= 1;
							ready <= 1;
							stage <= 3;
						end
					end
				3: stage <= 0;
			endcase
		end
	end
end

endmodule
