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

module cpu_wrapper
#(parameter FOLD_RAM_INPUT=0)
(
	input             reset,
	output reg        reset_out,

	input             clk,
	input             ph1,
	input             ph2,

	input       [4:0] cpucfg,
	input             ntsc,
	input       [2:0] fastramcfg,
	input       [2:0] cachecfg,
	input             bootrom,

	output reg [23:1] chip_addr,
	input      [15:0] chip_dout,
	output reg [15:0] chip_din,
	output reg        chip_as,
	output reg        chip_uds,
	output reg        chip_lds,
	output reg        chip_rw,
	input             chip_dtack,
	input       [2:0] chip_ipl,
	input             chip32_en,
	output reg        chip_long,
	output reg [15:0] chip_din2,
	input      [15:0] chip_dout2,

	input      [15:0] fastchip_dout,
	output reg        fastchip_sel,
	output            fastchip_lds,
	output            fastchip_uds,
	output            fastchip_rnw,
	output reg        fastchip_lw,
	input             fastchip_selack,
	input             fastchip_ready,

	output            ramsel,
	output     [28:1] ramaddr,
	output     [15:0] ramdin,
	input      [15:0] ramdout,
	input      [15:0] ramdout_sdram,ramdout_ddr,
	input             ram_select_ddr,
	input             ramready,
	output            ramlds,
	output            ramuds,
	output            ramshared,

	output            toccata_ena,
	output reg  [7:0] toccata_base,

	output            a2065_ena,
	output reg  [7:0] a2065_base,

	input             cdtv_mode,
	output reg  [7:0] cdtv_base,

	input      [15:0] cdtv_din,
	input             cdtv_selack,

	output reg  [1:0] cpustate,
	output reg  [3:0] cacr,
	output reg [31:0] nmi_addr,

	output reg        z2ram_ena,
	output reg  [4:0] z3ram_base0,
	output reg        z3ram_ena0,
	output reg  [3:0] z3ram_base1,
	output reg        z3ram_ena1,

	output            ramlong1,
	output     [15:0] ramdin_lo,
	input      [15:0] ramdout_hi,
	input             ramready_l,
	output            dcache_sw_en
);

assign dcache_sw_en = 1'b1;

wire        ec020      = (cpucfg[1:0] == 2'b11) & cpucfg[2];
wire [31:0] cpu_addr_m = ec020 ? {8'd0, cpu_addr_p[23:0]} : cpu_addr_p;

wire   ramsel_i     = cpu_req & ~sel_nmi_vector & (sel_zram | sel_chipram | sel_kickram | sel_dd | sel_rtg);
assign ramsel       = ramsel_i & ~req_gate;
assign ramshared    = sel_dd;

// NMI
always @(posedge clk) nmi_addr <= vbr + 32'h7c;
reg [31:0] nmi_addr2;
always @(posedge clk) nmi_addr2 <= vbr + 32'h7e;

wire sel_chipram;
wire sel_kickram;
wire sel_zram;
wire sel_dd;
wire sel_rtg;

memory_router u_memory_router
(
	.cpu_addr      (cpu_addr      ),
	.cchip         (cchip         ),
	.ckick         (ckick         ),
	.wr            (wr            ),
	.bootrom       (bootrom       ),
	.cdtv_mode     (cdtv_mode     ),
	.z2ram_ena     (z2ram_ena     ),
	.z3ram_base0   (z3ram_base0   ),
	.z3ram_ena0    (z3ram_ena0    ),
	.z3ram_base1   (z3ram_base1   ),
	.z3ram_ena1    (z3ram_ena1    ),
	.sel_chipram   (sel_chipram   ),
	.sel_kickram   (sel_kickram   ),
	.sel_zram      (sel_zram      ),
	.sel_dd        (sel_dd        ),
	.sel_rtg       (sel_rtg       ),
	.ramaddr       (ramaddr       )
);


// we route everything hrtmon related through cart.v (needs a couple of signals to
// decide what to do, would not be good style to replicate that here).
wire sel_nmi_vector = ((cpu_addr[31:1] == nmi_addr[31:1]) || (cpu_addr[31:1] == nmi_addr2[31:1])) && (cpustate == 2);



assign ramlds = sel_rtg ? uds_in : lds_in;
assign ramuds = sel_rtg ? lds_in : uds_in;
// RAM write selection is folded with CPU source below.


assign fastchip_lds = lds_in | req_gate;
assign fastchip_uds = uds_in | req_gate;
assign fastchip_rnw = wr;

reg  [31:0] cpu_addr;
reg  [15:0] cpu_dout;
// Decode RTG byte order with the winning source, keeping the RAM data
// path out of a separate serial byte-swap mux. No register or cycle added.
wire [15:0] cpu_din;
generate if(FOLD_RAM_INPUT)begin:folded_ram_read
wire [15:0] ram_word = ram_select_ddr ?
  (sel_rtg ? {ramdout_ddr[7:0],ramdout_ddr[15:8]} : ramdout_ddr) :
  (sel_rtg ? {ramdout_sdram[7:0],ramdout_sdram[15:8]} : ramdout_sdram);
wire [2:0] other_pick;
assign other_pick[0]=fastchip_selack;
assign other_pick[1]=!fastchip_selack & cdtv_selack;
assign other_pick[2]=!fastchip_selack & !cdtv_selack;
wire [15:0] nonram_word = ({16{other_pick[0]}} & fastchip_dout)
  | ({16{other_pick[1]}} & cdtv_din)
  | ({16{other_pick[2]}} & {sel_autoconfig ? autocfg_data : chip_data[15:12],chip_data[11:0]});
assign cpu_din = ramsel_i ? ram_word : nonram_word;
end else begin:legacy_ram_read
wire [4:0] input_pick;
assign input_pick[0] = ramsel_i & !sel_rtg;
assign input_pick[1] = ramsel_i & sel_rtg;
assign input_pick[2] = !ramsel_i & fastchip_selack;
assign input_pick[3] = !ramsel_i & !fastchip_selack & cdtv_selack;
assign input_pick[4] = !ramsel_i & !fastchip_selack & !cdtv_selack;
assign cpu_din = ({16{input_pick[0]}} & ramdout)
                   | ({16{input_pick[1]}} & {ramdout[7:0],ramdout[15:8]})
                   | ({16{input_pick[2]}} & fastchip_dout)
                   | ({16{input_pick[3]}} & cdtv_din)
                   | ({16{input_pick[4]}} & {sel_autoconfig ? autocfg_data : chip_data[15:12], chip_data[11:0]});
end endgenerate
reg         wr;
reg         uds_in;
reg         lds_in;
reg  [15:0] chip_data;
reg  [31:0] vbr;

always @* begin
	if(cpucfg[1:0]) begin
		cpu_dout     = cpu_dout_p;
		cpu_addr     = cpu_addr_m;
		cpustate     = cpustate_p;
		cacr         = cacr_m;
		vbr          = vbr_p;
		wr           = wr_p;
		uds_in       = uds_p;
		lds_in       = lds_p;
		reset_out    = reset_out_p;
		chip_as      = c_as;
		chip_rw      = c_rw;
		chip_uds     = c_uds;
		chip_lds     = c_lds;
		chip_addr    = ((c_long | w32_fl) & ~c_rw) ? {w32_adr, 1'b0} : cpu_addr_m[23:1];
		chip_din     = ((c_long | w32_fl) & ~c_rw) ? w32_hi : cpu_dout_p;
		chip_long    = c_long;
		chip_din2    = cpu_dout_p;
		chip_data    = chipdout_i;
		fastchip_sel = cpu_req & !cpu_addr_m[31:24] & ~req_gate;
		fastchip_lw  = longword;
	end
	else begin
		cpu_dout     = cpu_dout_o;
		cpu_addr     = {cpu_addr_o,1'b0};
		cpustate     = as_o ? 2'b01 : ~{wr_o,wr_o};
		cacr         = 1;
		vbr          = 0;
		wr           = wr_o;
		uds_in       = uds_o;
		lds_in       = lds_o;
		reset_out    = reset_out_o;
		chip_as      = ramsel | as_o;
		chip_rw      = wr_o;
		chip_uds     = uds_o;
		chip_lds     = lds_o;
		chip_addr    = cpu_addr_o[23:1];
		chip_din     = cpu_dout_o;
		chip_long    = 0;
		chip_din2    = 0;
		chip_data    = chip_dout;
		fastchip_sel = 0;
		fastchip_lw  = 0;
	end
end

wire [15:0] cpu_dout_p;
wire [31:0] cpu_addr_p;
wire  [1:0] cpustate_p;
wire  [3:0] cacr_p;
wire  [3:0] cacr_m = {cacr_p[3:1], cacr_p[0] | ec020 | (cpucfg[1:0] == 2'b10)};
wire [31:0] vbr_p;
wire        wr_p;
wire        uds_p;
wire        lds_p;
wire        reset_out_p;
wire        longword;
wire        opc_start;
wire [15:0] opc_out;
wire        opc_cond;
wire [15:0] opc_snd;
wire        opc_dbx;
wire [13:0] cacr_x;
wire        mmu_busy;
wire        s21_en;
wire        long_cand;
wire [15:0] cpu_dout_lo_p;
wire        long_ack;

TG68KdotC_Kernel
#(
	.sr_read(2),        // 0=>user,   1=>privileged,    2=>switchable with CPU(0)
	.vbr_stackframe(2), // 0=>no,     1=>yes/extended,  2=>switchable with CPU(0)
	.extaddr_mode(2),   // 0=>no,     1=>yes,           2=>switchable with CPU(1)
	.mul_mode(2),       // 0=>16Bit,  1=>32Bit,         2=>switchable with CPU(1),  3=>no MUL,
	.div_mode(2),       // 0=>16Bit,  1=>32Bit,         2=>switchable with CPU(1),  3=>no DIV,
	.bitfield(2)        // 0=>no,     1=>yes,           2=>switchable with CPU(1)
)
cpu_inst_p
(
  .clk(clk),
  .nreset(reset),
  .clkena_in(clkena_p_throttled),
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
  .s21_en(s21_en),
  .long_cand(long_cand),
  .long_ack(long_ack),
  .data_in_hi(ramdout_hi),
  .data_write_lo(cpu_dout_lo_p),
  
  .cpu({cpucfg[1], cpucfg[1] | cpucfg[0]}),
  .cpu030(cpu030),
  .opc_start(opc_start),
  .opc_out(opc_out),
  .opc_cond(opc_cond),
  .opc_snd(opc_snd),
  .opc_dbx(opc_dbx),
  .opc_cacr(cacr_x),
  .mmu_busy(mmu_busy),
  .busstate(cpustate_p),		// 0: fetch code, 1: no memaccess, 2: read data, 3: write data
  .cacr_out(cacr_p),
  .d_cache_out(),
  .vbr_out(vbr_p)
);

wire [15:0] cpu_dout_o;
reg [3:0] write_pick;
always @* begin
 write_pick=0;
 if(cpucfg[1:0]) begin
  if(sel_rtg)write_pick[3]=1;else write_pick[2]=1;
 end else begin
  if(sel_rtg)write_pick[1]=1;else write_pick[0]=1;
 end
end
assign ramdin = ({16{write_pick[0]}} & cpu_dout_o)
              | ({16{write_pick[1]}} & {cpu_dout_o[7:0],cpu_dout_o[15:8]})
              | ({16{write_pick[2]}} & cpu_dout_p)
              | ({16{write_pick[3]}} & {cpu_dout_p[7:0],cpu_dout_p[15:8]});
wire [23:1] cpu_addr_o;
wire  [2:0] fc_o;
wire        wr_o;
wire        as_o;
wire        uds_o;
wire        lds_o;
wire        reset_out_o;

fx68k cpu_inst_o
(
	.clk(clk),
	.enPhi1(ph1),
	.enPhi2(ph2),

	.extReset(~reset),
	.pwrUp(~reset),
	.oRESETn(reset_out_o),
	.HALTn(1),

	.eRWn(wr_o),
	.ASn(as_o),
	.LDSn(lds_o),
	.UDSn(uds_o),
	.DTACKn(ramsel ? ~ramready : chip_dtack),

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

wire cpu_req = (cpustate != 1);

wire cchip = turbochip_d & !cpustate;
wire ckick = turbokick_d & !cpustate;

reg turbochip_d;
reg turbokick_d;
always @(posedge clk) begin
	if (~reset | ~reset_out) begin
		turbochip_d <= 0;
		turbokick_d <= 0;
	end
	else if (~cpu_req) begin	// No mem access, so safe to switch chipram access mode
		turbochip_d <= cachecfg[0] & cpucfg[1];
		turbokick_d <= cachecfg[1] & cpucfg[1];
	end
end

wire cpu030        = (cpucfg[1:0] == 2'b10);
wire stock_speed   = cpucfg[2] & (cpucfg[1:0] == 2'b11);
wire clkena_p_base = ~cpu_req | chipready | ramready | fastchip_ready;

wire cyc_hold;
cpu_cycles cycles
(
	.clk(clk),
	.reset(reset),
	.ntsc(ntsc),
	.mode({cpu030 & |cpucfg[4:3], stock_speed | (cpu030 & cpucfg[4])}),
	.opc_start(opc_start),
	.opc(opc_out),
	.opc_cond(opc_cond),
	.opc_snd(opc_snd),
	.opc_dbx(opc_dbx),
	.cpu_ena(clkena_p_throttled & ~mmu_busy),
	.bus_ack(clkena_p_throttled & cpu_req),
	.bus_state(cpustate_p),
	.bus_addr(cpu_addr_m),
	.bus_long(longword),
	.bus_l1(clkena_p_throttled & long_ack),
	.cacr(cacr_x),
	.cacr_clr(cacr_p[3]),
	.hold(cyc_hold)
);

reg inflight;
always @(posedge clk) begin
	if (~reset)                   inflight <= 0;
	else if (clkena_p_throttled)  inflight <= cpu_req & longword & ~long_ack;
	else if (cpu_req & ~cyc_hold) inflight <= 1;
end

wire req_gate = cyc_hold & ~inflight;
wire clkena_p_throttled = (~cpu_req & ~cyc_hold) | (cpu_req & ~req_gate & (chipready | ramready | fastchip_ready));

assign s21_en    = cpu030;
assign ramlong1  = long_cand & s21_en & sel_zram & ~sel_rtg & ~sel_dd & ~req_gate;
assign ramdin_lo = cpu_dout_lo_p;
assign long_ack  = ramlong1 & ramready_l;

reg       chipreq;
reg [2:0] cpu_ipl;
always @(posedge clk) begin
	chipreq <= cpu_req & ~ramsel_i & ~fastchip_selack & ~req_gate;
	cpu_ipl <= ipl_i;
end

reg ph1n, ph2n;
always @(posedge clk) begin
	ph1n <= ph1;
	ph2n <= ph2;
end

wire c32 = chip32_en & longword & ~uds_in & ~lds_in & ~|cpu_addr_m[1:0] & ~|cpu_addr_m[31:21] &
           ~sel_nmi_vector & ~ramsel_i & ~fastchip_selack & ~cdtv_selack;

reg        chipready;
reg [15:0] chipdout_i;
reg  [2:0] ipl_i;
reg        c_as,c_rw,c_uds,c_lds;
reg        c_long;
reg        w32;
reg [23:2] w32_adr;
reg [15:0] w32_hi;
reg        w32_fl;
reg        r32;
reg [23:2] r32_adr;
reg [15:0] r32_lo;
reg [15:0] chip_dout2_p;
always @(posedge clk) chip_dout2_p <= chip_dout2;
always @(negedge clk, negedge reset) begin
	reg [1:0] stage;
	reg waitm;
	reg ready;
	reg now;

	if(~reset) begin
		stage <= 0;
		c_as <= 1;
		c_rw <= 1;
		c_uds <= 1;
		c_lds <= 1;
		c_long <= 0;
		ready <= 0;
		w32 <= 0;
		w32_fl <= 0;
		r32 <= 0;
	end
	else begin
		if (ph2n) begin
			waitm <= chip_dtack;
			if(~stage[0]) ipl_i <= chip_ipl;
		end

		now = 0;
		if (~|stage & cpu_req & ~req_gate) begin
			if (r32 & wr & (cpu_addr_m[23:2] == r32_adr) & cpu_addr_m[1]) begin
				chipdout_i <= r32_lo;
				r32 <= 0;
				now = 1;
			end
			else if (c32 & ~wr & ~w32) begin
				w32_adr <= cpu_addr_m[23:2];
				w32_hi  <= cpu_dout_p;
				w32 <= 1;
				now = 1;
			end
		end

		chipready <= now;
		if (ph1n) begin
			chipready <= now | ready;
			ready <= 0;
			case (stage)
				0: if (chipreq & ~now) begin
						c_as <= 0;
						if (w32 & (wr | (cpu_addr_m[23:2] != w32_adr) | ~cpu_addr_m[1] | uds_in | lds_in)) begin
							c_rw <= 0;
							c_uds <= 0;
							c_lds <= 0;
							c_long <= 0;
							w32_fl <= 1;
						end
						else begin
							c_rw <= wr;
							c_uds <= uds_in;
							c_lds <= lds_in;
							c_long <= w32 | (c32 & wr);
						end
						r32 <= 0;
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
							c_long <= 0;
							w32 <= 0;
							if (c_long & c_rw) begin
								r32     <= 1;
								r32_adr <= cpu_addr_m[23:2];
							end
							ready <= ~w32_fl;
							w32_fl <= 0;
							stage <= 3;
						end
					end
				3: begin
						r32_lo <= chip_dout2_p;
						stage <= 0;
					end
			endcase
		end
	end
end

///////////////////// AUTOCONFIG ////////////////////////////

reg       ac_toccata;
reg       ac_a2065;
reg       ac_cdtv;
reg [2:0] ac_memcard;
reg [3:0] autocfg_data;


always @(*) begin
	autocfg_data = 4'b1111;

	if (ac_cdtv) begin
		case (chip_addr[6:1])
			6'h00: autocfg_data = 4'b1100;
			6'h01: autocfg_data = 4'b0001;
			6'h03: autocfg_data = 4'b1100;
			6'h04: autocfg_data = 4'b1011;
			6'h09: autocfg_data = 4'b1101;
			6'h0B: autocfg_data = 4'b1101;
			default: autocfg_data = 4'b1111;
		endcase
	end
	// Zorro II RAM (Up to 8 meg at 0x200000). It has a fixed base, so it must be first in the chain.
	else if (~ac_memcard[2] && ac_memcard[1:0]) begin
		case (chip_addr[6:1])
			6'b000000: autocfg_data = 4'b1110;
			6'b000001:
				case (ac_memcard[1:0])
							1: autocfg_data = 4'b0110; // 2MB
							2: autocfg_data = 4'b0111; // 4MB
					default: autocfg_data = 4'b0000; // 8MB
				endcase
			6'b000010: autocfg_data = 4'b1010;
			6'b000011: autocfg_data = 4'b1110;
			6'b001000: autocfg_data = 4'b1111;
			6'b001001: autocfg_data = 4'b1000;
			6'b001010: autocfg_data = 4'b0010;
			6'b001011: autocfg_data = 4'b0100;
			6'b010011: autocfg_data = 4'b1110;
			  default:;
		endcase
	end
	// Zorro II other cards
	else if(ac_toccata) begin
		case (chip_addr[6:1])
			6'h0: autocfg_data = 4'b1100; // Zorro-II card, no link, no ROM
			6'h1: autocfg_data = 4'b0001; // Next board not related, size 'h64k
			// Inverted from here on
			6'h3: autocfg_data = 4'b0011; // Lower byte product number
			//6'h5: autocfg_data = 4'b1101; // logical size 64k -- commented out -> logical size == physical size. Issue with KS1.3?
			6'h8: autocfg_data = 4'b1011; // Manufacturer ID: 0x4754
			6'h9: autocfg_data = 4'b1000;
			6'ha: autocfg_data = 4'b1010;
			6'hb: autocfg_data = 4'b1011;
			default: ;
		endcase
	end
	// A2065 Ethernet (Commodore, mfr=0x0202, product=0x70)
	else if(ac_a2065) begin
		case (chip_addr[6:1])
			6'h0: autocfg_data = 4'b1100; // Zorro-II card, no link, no ROM
			6'h1: autocfg_data = 4'b0001; // size 64KB
			// Inverted from here on
			6'h2: autocfg_data = 4'b1000; // er_Product high nibble
			6'h3: autocfg_data = 4'b1111; // er_Product low nibble -> 0x70
			6'h4: autocfg_data = 4'b1111; // er_Flags high
			6'h5: autocfg_data = 4'b1111; // er_Flags low
			6'h8: autocfg_data = 4'b1111; // er_Manufacturer high high
			6'h9: autocfg_data = 4'b1101; // er_Manufacturer high low
			6'ha: autocfg_data = 4'b1111; // er_Manufacturer low high
			6'hb: autocfg_data = 4'b1101; // er_Manufacturer low low -> 0x0202
			// er_SerialNumber bytes 2..5 — the A2065 station address low
			// bytes, which AmigaOS reads as the card's MAC. Left at zero
			// (nibbles are inverted, so 4'b1111 reads as 0): the host side
			// rewrites the source address on the wire, so the card does not
			// need a unique serial here. Driving these from a register would
			// mean a real MAC arriving before autoconfig has run.
			6'hc:  autocfg_data = 4'b1111;
			6'hd:  autocfg_data = 4'b1111;
			6'he:  autocfg_data = 4'b1111;
			6'hf:  autocfg_data = 4'b1111;
			6'h10: autocfg_data = 4'b1111;
			6'h11: autocfg_data = 4'b1111;
			6'h12: autocfg_data = 4'b1111;
			6'h13: autocfg_data = 4'b1111;
			6'h14: autocfg_data = 4'b1111; // er_InitDiagVec
			6'h15: autocfg_data = 4'b1111; // er_InitDiagVec
			default: ;
		endcase
	end
	// Zorro III RAM 128MB/256MB/384MB
	else if(ac_memcard[2]) begin
		case (chip_addr[6:1])
			6'b000000: autocfg_data = 4'b1010;	// Zorro-III card, add mem, no ROM
			6'b000001: autocfg_data = ac_memcard[1] ? 4'b0011 : 4'b0100; // 128MB or 256MB, extended
			6'b000010: autocfg_data = 4'b1110;	// ProductID=0x10 (only setting upper nibble)
			6'b000100: autocfg_data = 4'b0000;	// Memory card, not silenceable, Extended size, reserved.
			6'b000101: autocfg_data = 4'b1111;	// 0000 - logical size matches physical size TODO change this to 0001, so it is autosized by the OS, WHEN it will be 24MB.
			6'b001000: autocfg_data = 4'b1110;	// Manufacturer ID: 0x139c
			6'b001001: autocfg_data = 4'b1100;
			6'b001010: autocfg_data = 4'b0110;
			6'b001011: autocfg_data = 4'b0011;
			6'b010011: autocfg_data = {2'b11, ~ac_memcard[1], ac_memcard[1]};	// serial=1/2
			  default:;
		endcase
	end
end

wire sel_autoconfig = (chip_addr[23:16] == 8'b11101000) && (ac_memcard || ac_toccata || ac_a2065 || ac_cdtv); //$E80000 - $E8FFFF

always @(posedge clk) begin
	reg old_uds;
	old_uds <= chip_uds;

	if (~reset | ~reset_out) begin
		ac_memcard  <= (cpucfg[1] & ~ec020) ? fastramcfg : fastramcfg[2] ? 3'd3 : {1'b0, fastramcfg[1:0]};
		ac_toccata  <= cdtv_mode ? 1'b0 : 1'b1;
		ac_a2065    <= 1;
		ac_cdtv     <= cdtv_mode;
		cdtv_base   <= 8'hE9;
		z2ram_ena   <= 0;
		z3ram_ena0  <= 0;
		z3ram_ena1  <= 0;
		z3ram_base0 <= 1;
		z3ram_base1 <= 1;
	end
	else if (sel_autoconfig && ~chip_rw && ~chip_uds && old_uds) begin
		if(ac_cdtv) begin
			if (chip_addr[6:1] == 6'b100100) begin
				cdtv_base <= cpu_dout[15:8];
				ac_cdtv   <= 0;
			end
			else if (chip_addr[6:1] == 6'b100110) begin
				ac_cdtv   <= 0;
			end
		end
		else if(~ac_memcard[2] && ac_memcard[1:0]) begin
			if (chip_addr[6:1] == 6'b100100) begin // Register 0x48 - config, ZII RAM
				z2ram_ena <= 1;
				ac_memcard <= 0;
			end
		end
		else if(ac_toccata) begin
			if (chip_addr[6:1] == 6'b100100) begin // Register 0x48 - config, Toccata card in ZII io space ($E90000)
				toccata_base <= cpu_dout[7:0];
				ac_toccata<=0;
			end
		end
		else if(ac_a2065) begin
			if (chip_addr[6:1] == 6'b100100) begin // Register 0x48 - config, A2065 Ethernet
				a2065_base <= cpu_dout[7:0];
				ac_a2065<=0;
			end
		end
		else if(ac_memcard[2]) begin
			if(chip_addr[6:1] == 6'b100010) begin // Register 0x44, assign base address to ZIII RAM.
				if(~ac_memcard[1]) begin
					z3ram_base1 <= cpu_dout[15:12]; //256MB chunk
					z3ram_ena1 <= 1;
					ac_memcard <= {ac_memcard[0], ac_memcard[0], 1'b0};
				end
				else begin
					z3ram_base0 <= cpu_dout[15:11]; //128MB chunk
					z3ram_ena0 <= 1;
					ac_memcard <= 0;
				end
			end
		end
	end
end

assign toccata_ena = ~ac_toccata & ~cdtv_mode;
assign a2065_ena   = ~ac_a2065;

endmodule
