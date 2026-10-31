/********************************************/
/* minimig.sv                               */
/* MiSTer glue logic                        */
/* 2017-2020 Alexey Melnikov                */
/********************************************/

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign BUTTONS = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

`include "build_id.v" 
localparam CONF_STR = {
	"Minimig;UART115200:230400,MIDI;",
	"J,Red(Fire),Blue,Yellow,Green,RT,LT,Pause;",
	"jn,A,B,X,Y,R,L,Start;",
	"jp,B,A,X,Y,R,L,Start;",
	"-;",
	"I,",
	"MT32-pi: SoundFont #0,",
	"MT32-pi: SoundFont #1,",
	"MT32-pi: SoundFont #2,",
	"MT32-pi: SoundFont #3,",
	"MT32-pi: SoundFont #4,",
	"MT32-pi: SoundFont #5,",
	"MT32-pi: SoundFont #6,",
	"MT32-pi: SoundFont #7,",
	"MT32-pi: MT-32 v1,",
	"MT32-pi: MT-32 v2,",
	"MT32-pi: CM-32L,",
	"MT32-pi: Unknown mode;",
	"V,v",`BUILD_DATE
};

wire [15:0] JOY0;
wire [15:0] JOY1;
wire [15:0] JOY2;
wire [15:0] JOY3;
wire [15:0] JOYA0;
wire [15:0] JOYA1;
wire  [7:0] kbd_mouse_data;
wire        kbd_mouse_level;
wire  [1:0] kbd_mouse_type;
wire  [2:0] mouse_buttons;
wire [64:0] RTC;

wire        ce_pix;
wire  [1:0] buttons;
wire [63:0] status;
wire        forced_scandoubler;

wire        io_strobe;
wire        io_wait;
wire        io_fpga;
wire        io_uio;
wire [15:0] io_din;
wire [15:0] fpga_dout;

wire [21:0] gamma_bus;

wire  [7:0] uart_mode;

reg [2:0] mister_floppy_status;

hps_io #(.CONF_STR(CONF_STR), .CONF_STR_BRAM(0)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS({HPS_BUS[45:42],ce_pix,HPS_BUS[40:0]}),

	.status(status),
	.status_menumask({mister_floppy_status, mt32_cfg, mt32_available}),
	.info_req(mt32_info_req),
	.info(mt32_info_disp),

	.joystick_0(JOY0),
	.joystick_1(JOY1),
	.joystick_2(JOY2),
	.joystick_3(JOY3),
	.joystick_l_analog_0(JOYA0),
	.joystick_l_analog_1(JOYA1),

	.ioctl_wait(io_wait),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),

	.uart_mode(uart_mode),

	.RTC(RTC),
	.gamma_bus(gamma_bus),

	.EXT_BUS(EXT_BUS)
);

wire [15:0] ide_din;
wire [15:0] ide_dout;
wire  [4:0] ide_addr;
wire        ide_rd;
wire        ide_wr;
wire  [5:0] ide_req;

wire [15:0] akiko_din;
wire [15:0] akiko_dout;
wire        akiko_wr;
wire        akiko_rd;
wire        akiko_cs;
wire        akiko_cs_sec;
wire        akiko_cs_nvr;
wire        akiko_cs_subcode;
wire        akiko_req;
wire        akiko_sec_req;
wire        akiko_rx_busy;
wire        akiko_nvr_dirty;

wire [15:0] cdtv_din;
wire [15:0] cdtv_dout;
wire        cdtv_wr;
wire        cdtv_rd;
wire        cdtv_cs;
wire        cdtv_cs_sec;
wire        cdtv_cs_stch;
wire        cdtv_cs_nvr;
wire        cdtv_cs_card;
wire        cdtv_nvr_dirty;
wire        cdtv_card_dirty;
wire        cdtv_req;

wire        akiko_dma_req;
wire        akiko_dma_we;
wire [23:0] akiko_dma_baddr;
wire  [7:0] akiko_dma_wbyte;
wire  [7:0] akiko_dma_rbyte;
wire        akiko_dma_ack;
wire        akiko_dma_arm;

wire [24:1] arb_chip_addr;
wire        arb_chip_l;
wire        arb_chip_u;
wire        arb_chip_rw;
wire        arb_chip_dma;
wire [15:0] arb_chip_wr;

wire [35:0] EXT_BUS;
hps_ext hps_ext(.*, .ide_req(ide_fast ? ide_f_req : ide_c_req),  .ide_din(ide_fast ? ide_f_readdata : ide_c_readdata));

assign LED_POWER[1] = 1;
assign LED_DISK     = {1'b0, ide_fast ? ide_f_led : ide_c_led};

assign VGA_SCALER   = FB_EN;

wire clk_114;
wire clk_sys;
wire locked;

pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk_114),
	.outclk_1(clk_sys),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

always @(posedge CLK_50M) begin
	reg ntscd = 0, ntscd2 = 0;
	reg [2:0] state = 0;
	reg ntsc_r;

	ntscd <= ntsc;
	ntscd2 <= ntscd;

	cfg_write <= 0;
	if(ntscd2 == ntscd && ntscd2 != ntsc_r) begin
		state <= 1;
		ntsc_r <= ntscd2;
	end

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			3: begin
					cfg_address <= 7;
					cfg_data <= ntsc_r ? 702807747 : 343817200;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

wire reset = ~locked | buttons[1] | RESET;

reg reset_d;
always @(posedge clk_sys, posedge reset) begin
	reg [7:0] reset_s;
	reg rs;
	
	if(reset) reset_s <= '1;
	else begin
		reset_s <= reset_s << 1;
		rs <= reset_s[7];
		reset_d <= rs;
	end
end

//// amiga clocks ////
wire       clk7_en;
wire       clk7n_en;
wire       c1;
wire       c3;
wire       cck;
wire [9:0] eclk;

amiga_clk amiga_clk
(
	.clk_28   ( clk_sys    ), // input  clock c1 ( 28.687500MHz)
	.clk7_en  ( clk7_en    ), // output clock 7 enable (on 28MHz clock domain)
	.clk7n_en ( clk7n_en   ), // 7MHz negedge output clock enable (on 28MHz clock domain)
	.c1       ( c1         ), // clk28m clock domain signal synchronous with clk signal
	.c3       ( c3         ), // clk28m clock domain signal synchronous with clk signal delayed by 90 degrees
	.cck      ( cck        ), // colour clock output (3.54 MHz)
	.eclk     ( eclk       ), // 0.709379 MHz clock enable output (clk domain pulse)
	.reset_n  ( ~reset     )
);


wire cpu_type = cpucfg[1];
reg  cpu_ph1;
reg  cpu_ph2;
reg  ram_cs;
reg  cyc;

always @(posedge clk_114) begin
	reg [3:0] div;
	reg       c1d;

	div <= div + 1'd1;
	 
	c1d <= c1;
	if (~c1d & c1) div <= 3;
	
	if (~cpu_rst) begin
		cyc <= 0;
		cpu_ph1 <= 0;
		cpu_ph2 <= 0;
	end
	else begin
		cyc <= !div[1:0];
		if (div[1] & ~div[0]) begin
			cpu_ph1 <= 0;
			cpu_ph2 <= 0;
			case (div[3:2])
				0: cpu_ph2 <= 1;
				2: cpu_ph1 <= 1;
			endcase
		end
	end

	ram_cs <= ~(ram_ready & cyc & cpu_type) & ram_sel;
end

wire  [1:0] cpu_state;
wire        cpu_nrst_out;
wire  [3:0] cpu_cacr;
wire [31:0] cpu_nmi_addr;
wire        cpu_rst;

wire  [2:0] chip_ipl;
wire        chip_dtack;
wire        chip_as;
wire        chip_uds;
wire        chip_lds;
wire        chip_rw;
wire [15:0] chip_dout;
wire [15:0] chip_din;
wire [23:1] chip_addr;
wire        chip32_en;
wire        chip_long;
wire [15:0] chip_din2;
wire [15:0] chip_rd2;
wire        ram_long;
wire        arb_chip_long;
wire [15:0] arb_chip_wr2;

wire [28:1] ram_addr;
wire        ram_sel;
wire        ram_lds;
wire        ram_uds;
wire [15:0] ram_din;
wire [15:0] ram_dout1;
wire [15:0] ram_dout2;
wire [15:0] ram_dout  = zram_sel ? ram_dout2  : ram_dout1;
wire        ram_ready = zram_sel ? ram_ready2 : ram_ready1;
wire        zram_sel  = |ram_addr[28:26];
wire        ram_l1;
wire [15:0] ram_din_lo;
wire [15:0] ram_dout2_hi;
wire        ram_ready2_l;
wire        ramshared;

wire [7:0] toccata_base;
wire toccata_ena;
wire a2065_ena;
wire [7:0] a2065_base;

wire        cdtv_mode;
wire  [7:0] cdtv_base;
wire [15:0] cdtv_din_w;
wire        cdtv_selack_w;
wire  [9:0] cdtv_cdda_volume;
wire        cdtv_cdda_volume_valid;
wire        cdtv_dma_req;
wire        cdtv_dma_we;
wire [31:0] cdtv_dma_baddr;
wire  [7:0] cdtv_dma_wbyte;
wire        cdtv_dma_ack;

cpu_wrapper #(.FOLD_RAM_INPUT(1)) cpu_wrapper
(
	.reset        (cpu_rst         ),
	.reset_out    (cpu_nrst_out    ),

	.clk          (clk_sys         ),
	.ph1          (cpu_ph1         ),
	.ph2          (cpu_ph2         ),

	.chip_addr    (chip_addr       ),
	.chip_dout    (chip_dout       ),
	.chip_din     (chip_din        ),
	.chip_as      (chip_as         ),
	.chip_uds     (chip_uds        ),
	.chip_lds     (chip_lds        ),
	.chip_rw      (chip_rw         ),
	.chip_dtack   (chip_dtack      ),
	.chip_ipl     (chip_ipl        ),
	.chip32_en    (chip32_en       ),
	.chip_long    (chip_long       ),
	.chip_din2    (chip_din2       ),
	.chip_dout2   (chip_rd2        ),

	.fastchip_dout   (fastchip_dout   ),
	.fastchip_sel    (fastchip_sel    ),
	.fastchip_lds    (fastchip_lds    ),
	.fastchip_uds    (fastchip_uds    ),
	.fastchip_rnw    (fastchip_rnw    ),
	.fastchip_selack (fastchip_selack ),
	.fastchip_ready  (fastchip_ready  ),
	.fastchip_lw     (fastchip_lw     ),

	.cpucfg       (cpucfg          ),
	.ntsc         (ntsc            ),
	.cachecfg     (cachecfg        ),
	.fastramcfg   (memcfg[6:4]     ),
	.bootrom      (bootrom         ),

	.toccata_ena  (toccata_ena     ),
	.a2065_ena    (a2065_ena       ),
	.a2065_base   (a2065_base      ),
	.toccata_base (toccata_base    ),
	.cdtv_base    (cdtv_base       ),
	.cdtv_mode    (cdtv_mode       ),

	.cdtv_din     (cdtv_din_w      ),
	.cdtv_selack  (cdtv_selack_w   ),

	.ramsel       (ram_sel         ),
	.ramaddr      (ram_addr        ),
	.ramlds       (ram_lds         ),
	.ramuds       (ram_uds         ),
	.ramdout      (ram_dout        ),
	.ramdout_sdram(ram_dout1       ),
	.ramdout_ddr  (ram_dout2       ),
	.ram_select_ddr(zram_sel       ),
	.ramdin       (ram_din         ),
	.ramready     (ram_ready       ),
	.ramshared    (ramshared       ),
	.ramlong1     (ram_l1          ),
	.ramdin_lo    (ram_din_lo      ),
	.ramdout_hi   (ram_dout2_hi    ),
	.ramready_l   (zram_sel & ram_ready2_l),

	//custom CPU signals
	.cpustate     (cpu_state       ),
	.cacr         (cpu_cacr        ),
	.nmi_addr     (cpu_nmi_addr    ),

	.z2ram_ena    (z2ram_ena       ),
	.z3ram_base0  (z3ram_base0     ),
	.z3ram_ena0   (z3ram_ena0      ),
	.z3ram_base1  (z3ram_base1     ),
	.z3ram_ena1   (z3ram_ena1      ),
	.dcache_sw_en (dcache_sw_en    )
);

wire        dcache_sw_en;

wire        z2ram_ena;
wire  [4:0] z3ram_base0;
wire        z3ram_ena0;
wire  [3:0] z3ram_base1;
wire        z3ram_ena1;

wire [28:1] dma_ddr_addr;
wire        dma_ddr_l;
wire        dma_ddr_u;
wire        dma_ddr_we;
wire        dma_ddr_cs;
wire [15:0] dma_ddr_wr;
wire        dma_ddr_ack;
wire [15:0] dma_ddr_rd;


wire        ram_ready1;

wire [24:1] sdram_addon_addr;
wire sdram_addon_claim;
sdram_ctrl #(.FOLD_CHIP_ARBITRATION(1)) ram1
(
	.sysclk       (clk_114         ),
	.reset_n      (~reset_d        ),
	.c_7m         (c1              ),

	.cache_rst    (cpu_rst         ),
	.cpu_cache_ctrl(cpu_cacr       ),
	.dcache_sw_en (dcache_sw_en    ),

	.sd_data      (SDRAM_DQ        ),
	.sd_addr      (SDRAM_A         ),
	.sd_dqm       ({SDRAM_DQMH, SDRAM_DQML}),
	.sd_cs        (SDRAM_nCS       ),
	.sd_ba        (SDRAM_BA        ),
	.sd_we        (SDRAM_nWE       ),
	.sd_ras       (SDRAM_nRAS      ),
	.sd_cas       (SDRAM_nCAS      ),
	.sd_cke       (SDRAM_CKE       ),
	.sd_clk       (SDRAM_CLK       ),

	.cpuWR        (ram_din         ),
	.cpuAddr      (ram_addr[22:1]  ),
	.cpuU         (ram_uds         ),
	.cpuL         (ram_lds         ),
	.cpustate     (cpu_state       ),
	.cpuCS        (~zram_sel&ram_cs),
	.cpuRD        (ram_dout1       ),
	.ramready     (ram_ready1      ),

	.chipWR       (arb_chip_wr     ),
	.chipAddr     (arb_chip_addr   ),
	.raw_chip_addr({1'b0, ram_address}),
	.raw_chip_dma (_ram_oe),
	.raw_chip_rw  (_ram_we),
	.addon_chip_addr(sdram_addon_addr),
	.addon_chip_claim(sdram_addon_claim),
	.chipU        (arb_chip_u      ),
	.chipL        (arb_chip_l      ),
	.chipRW       (arb_chip_rw     ),
	.chipDMA      (arb_chip_dma    ),
	.chipRD       (ramdata_in      ),
	.chip48       (chip48          ),
	.chip32       (arb_chip_long   ),
	.chipWR2      (arb_chip_wr2    ),
	.chipRD2      (chip_rd2        )
);

wire audio_dma_req, audio_dma_ack, audio_dma_error;
wire [31:0] audio_dma_addr;
wire [15:0] audio_dma_data;
wire [15:0] audio_ext_l, audio_ext_r;

chipdma_arb chipdma_arb
(
	.clk             (clk_sys              ),
	.reset           (reset_d              ),
	.c_7m            (c1                   ),

	.chip_in_addr    ({1'b0, ram_address}  ),
	.chip_in_l       (_ram_ble             ),
	.chip_in_u       (_ram_bhe             ),
	.chip_in_rw      (_ram_we              ),
	.chip_in_dma     (_ram_oe              ),
	.chip_in_wr      (ram_data             ),
	.chip_in_long    (ram_long             ),
	.chip_in_wr2     (chip_din2            ),

	.akiko_dma_req   (akiko_dma_req        ),
	.akiko_dma_we    (akiko_dma_we         ),
	.akiko_dma_baddr (akiko_dma_baddr      ),
	.akiko_dma_wbyte (akiko_dma_wbyte      ),
	.akiko_dma_rbyte (akiko_dma_rbyte      ),
	.akiko_dma_ack   (akiko_dma_ack        ),
	.akiko_arm       (akiko_dma_arm        ),

	.cdtv_dma_req    (cdtv_dma_req         ),
	.cdtv_dma_we     (cdtv_dma_we          ),
	.cdtv_dma_baddr  (cdtv_dma_baddr       ),
	.cdtv_dma_wbyte  (cdtv_dma_wbyte       ),
	.cdtv_dma_rbyte  (                     ),
	.cdtv_dma_ack    (cdtv_dma_ack         ),
	.audio_dma_req   (audio_dma_req        ),
	.audio_dma_addr  (audio_dma_addr       ),
	.audio_dma_ack   (audio_dma_ack        ),
	.audio_dma_data  (audio_dma_data       ),
	.audio_dma_error (audio_dma_error      ),

	.chip_out_addr   (arb_chip_addr        ),
	.sdram_addon_addr(sdram_addon_addr),
	.sdram_addon_claim(sdram_addon_claim),
	.chip_out_l      (arb_chip_l           ),
	.chip_out_u      (arb_chip_u           ),
	.chip_out_rw     (arb_chip_rw          ),
	.chip_out_dma    (arb_chip_dma         ),
	.chip_out_wr     (arb_chip_wr          ),
	.chip_out_long   (arb_chip_long        ),
	.chip_out_wr2    (arb_chip_wr2         ),
	.chip_in_rd      (ramdata_in           ),

	.z2ram_ena       (z2ram_ena            ),
	.z3ram_base0     (z3ram_base0          ),
	.z3ram_ena0      (z3ram_ena0           ),
	.z3ram_base1     (z3ram_base1          ),
	.z3ram_ena1      (z3ram_ena1           ),

	.ddr_out_addr    (dma_ddr_addr         ),
	.ddr_out_l       (dma_ddr_l            ),
	.ddr_out_u       (dma_ddr_u            ),
	.ddr_out_we      (dma_ddr_we           ),
	.ddr_out_cs      (dma_ddr_cs           ),
	.ddr_out_wr      (dma_ddr_wr           ),
	.ddr_in_ack      (dma_ddr_ack          ),
	.ddr_in_rd       (dma_ddr_rd           )
);


wire        ram_ready2;

ddram_ctrl ram2
(
	.sysclk       (clk_114         ),
	.reset_n      (~reset_d        ),

	.cache_rst    (cpu_rst         ),
	.cpu_cache_ctrl(cpu_cacr       ),
	.dcache_sw_en (dcache_sw_en    ),

	.DDRAM_CLK    (DDRAM_CLK       ),
	.DDRAM_BUSY   (DDRAM_BUSY      ),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT ),
	.DDRAM_ADDR   (DDRAM_ADDR      ),
	.DDRAM_DOUT   (DDRAM_DOUT      ),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD     (DDRAM_RD        ),
	.DDRAM_DIN    (DDRAM_DIN       ),
	.DDRAM_BE     (DDRAM_BE        ),
	.DDRAM_WE     (DDRAM_WE        ),

	.mem2_address      (mem2_address),
	.mem2_burstcount   (mem2_burstcount),
	.mem2_read         (mem2_read),
	.mem2_readdata     (mem2_readdata),
	.mem2_readdatavalid(mem2_readdatavalid),
	.mem2_writedata    (mem2_writedata),
	.mem2_byteenable   (mem2_byteenable),
	.mem2_write        (mem2_write),
	.mem2_waitrequest  (mem2_waitrequest),

	.cpuWR        (ram_din         ),
	.cpuAddr      (ram_addr        ),
	.cpuU         (ram_uds         ),
	.cpuL         (ram_lds         ),
	.cpustate     (cpu_state       ),
	.cpuCS        (zram_sel&ram_cs ),
	.cpuRD        (ram_dout2       ),
	.ramshared    (ramshared       ),
	.cpuLong      (fastchip_lw & ~ram_addr[1]),
	.ramready     (ram_ready2      ),
	.cpuLong1     (ram_l1 & zram_sel),
	.cpuWR_lo     (ram_din_lo      ),
	.cpuRD_hi     (ram_dout2_hi    ),
	.ramready_l   (ram_ready2_l    ),

	.dmaAddr      (dma_ddr_addr    ),
	.dmaCS        (dma_ddr_cs      ),
	.dmaWE        (dma_ddr_we      ),
	.dmaL         (dma_ddr_l       ),
	.dmaU         (dma_ddr_u       ),
	.dmaWR        (dma_ddr_wr      ),
	.dmaRD        (dma_ddr_rd      ),
	.dmaACK       (dma_ddr_ack     )
);

////////////////////////////  A2065 ETHERNET  ///////////////////////////////
//
// The card is self-contained inside minimig; all that surfaces here is its
// memory port, which shares the core's DDR3 interface with the fast-RAM
// controller above. Fast RAM has priority: it carries every 68k access to
// Zorro RAM, while the card touches DDR3 rarely and can wait.

wire [28:0] a2065_mem_address;
wire [7:0]  a2065_mem_burstcount, a2065_mem_byteenable;
wire        a2065_mem_read, a2065_mem_write;
wire [63:0] a2065_mem_writedata, a2065_mem_readdata;
wire        a2065_mem_readdatavalid, a2065_mem_waitrequest;

wire [28:0] mem2_address;
wire [7:0]  mem2_burstcount, mem2_byteenable;
wire        mem2_read, mem2_write;
wire [63:0] mem2_writedata, mem2_readdata;
wire        mem2_readdatavalid, mem2_waitrequest;

wire [28:0] dsnd_addr;
wire        dsnd_rd, dsnd_busy, dsnd_ready;

a2065_ddram_arbiter dsnd_arb
(
	.clk             (clk_114),
	.rst             (reset_d),

	.m0_address      (a2065_mem_address),
	.m0_burstcount   (a2065_mem_burstcount),
	.m0_read         (a2065_mem_read),
	.m0_readdata     (a2065_mem_readdata),
	.m0_readdatavalid(a2065_mem_readdatavalid),
	.m0_writedata    (a2065_mem_writedata),
	.m0_byteenable   (a2065_mem_byteenable),
	.m0_write        (a2065_mem_write),
	.m0_waitrequest  (a2065_mem_waitrequest),

	.m1_address      (dsnd_addr),
	.m1_burstcount   (8'd1),
	.m1_read         (dsnd_rd),
	.m1_readdata     (),
	.m1_readdatavalid(dsnd_ready),
	.m1_writedata    (64'd0),
	.m1_byteenable   (8'hFF),
	.m1_write        (1'b0),
	.m1_waitrequest  (dsnd_busy),

	.s_address       (mem2_address),
	.s_burstcount    (mem2_burstcount),
	.s_read          (mem2_read),
	.s_readdata      (mem2_readdata),
	.s_readdatavalid (mem2_readdatavalid),
	.s_writedata     (mem2_writedata),
	.s_byteenable    (mem2_byteenable),
	.s_write         (mem2_write),
	.s_waitrequest   (mem2_waitrequest)
);

wire [15:0] fastchip_dout;
wire        fastchip_sel;
wire        fastchip_lds;
wire        fastchip_uds;
wire        fastchip_rnw;
wire        fastchip_selack;
wire        fastchip_ready;
wire        fastchip_lw;

wire        ide_fast;
wire        ide_f_led;
wire        ide_f_irq;
wire        akiko_f_irq;
wire  [5:0] ide_f_req;
wire [15:0] ide_f_readdata;

// fastchip is working on CPU clock.
// Only high performance 68020 devices are inside
fastchip fastchip
(
	.clk          (clk_114           ),
	.cyc          (cyc               ),
	.clk_sys      (clk_sys           ),

	.reset        (~cpu_rst | ~cpu_nrst_out ),
	.sel          (fastchip_sel      ),
	.sel_ack      (fastchip_selack   ),
	.ready        (fastchip_ready    ),

	.addr         ({chip_addr,1'b0}  ),
	.din          (chip_din          ),
	.dout         (fastchip_dout     ),
	.lds          (~fastchip_lds     ),
	.uds          (~fastchip_uds     ),
	.rnw          (fastchip_rnw      ),
	.longword     (fastchip_lw       ),

	//RTG framebuffer control
	.rtg_ena      (FB_EN             ),
	.rtg_hsize    (FB_WIDTH          ),
	.rtg_vsize    (FB_HEIGHT         ),
	.rtg_format   (FB_FORMAT         ),
	.rtg_base     (FB_BASE           ),
	.rtg_stride   (FB_STRIDE         ),
	.rtg_pal_clk  (FB_PAL_CLK        ),
	.rtg_pal_dw   (FB_PAL_DOUT       ),
	.rtg_pal_dr   (FB_PAL_DIN        ),
	.rtg_pal_a    (FB_PAL_ADDR       ),
	.rtg_pal_wr   (FB_PAL_WR         ),

	.ide_ena      (ide_ena & ide_fast),
	.ide_irq      (ide_f_irq         ),
	.ide_req      (ide_f_req         ),
	.ide_address  (ide_addr          ),
	.ide_write    (ide_wr            ),
	.ide_writedata(ide_dout          ),
	.ide_read     (ide_rd            ),
	.ide_readdata (ide_f_readdata    ),
	.ide_led      (ide_f_led         ),

	.akiko_irq    (akiko_f_irq       ),

	.akiko_dma_req   (akiko_dma_req   ),
	.akiko_dma_we    (akiko_dma_we    ),
	.akiko_dma_baddr (akiko_dma_baddr ),
	.akiko_dma_wbyte (akiko_dma_wbyte ),
	.akiko_dma_rbyte (akiko_dma_rbyte ),
	.akiko_dma_ack   (akiko_dma_ack   ),
	.akiko_dma_arm   (akiko_dma_arm   ),

	.akiko_uio_cs        (akiko_cs        ),
	.akiko_uio_cs_sec    (akiko_cs_sec    ),
	.akiko_uio_cs_nvr    (akiko_cs_nvr    ),
	.akiko_uio_cs_subcode(akiko_cs_subcode),
	.akiko_uio_wr        (akiko_wr        ),
	.akiko_uio_rd        (akiko_rd        ),
	.akiko_uio_din       (akiko_dout      ),
	.akiko_uio_dout      (akiko_din       ),
	.akiko_uio_req       (akiko_req       ),
	.akiko_uio_sec_req   (akiko_sec_req   ),
	.akiko_uio_rx_busy   (akiko_rx_busy   ),
	.akiko_uio_nvr_dirty (akiko_nvr_dirty )
);


////////////////////////////  UART  //////////////////////////////////// 

wire uart_cts, uart_dsr, uart_rts, uart_dtr;
wire uart_tx, uart_rx;

wire hps_mpu = (uart_mode >= 3);

assign UART_RTS = ~hps_mpu & uart_rts;
assign UART_DTR = ~hps_mpu & uart_dtr;
assign uart_cts = ~hps_mpu & UART_CTS;
assign uart_dsr = ~hps_mpu & UART_DSR;
assign uart_rx  = uart_mode ? UART_RXD : midi_rx;
assign UART_TXD = (hps_mpu & mt32_use) | uart_tx;

///////////////////////////////////////////////////////////////////////

//// minimig top ////
wire  [4:0] cpucfg;
wire  [2:0] cachecfg;
wire  [6:0] memcfg;
wire        bootrom;   
wire [15:0] ram_data;      // sram data bus
wire [15:0] ramdata_in;    // sram data bus in
wire [47:0] chip48;        // big chip read
wire [23:1] ram_address;   // sram address bus
wire        _ram_bhe;      // sram upper byte select
wire        _ram_ble;      // sram lower byte select
wire        _ram_we;       // sram write enable
wire        _ram_oe;       // sram output enable
wire [14:0] ldata;         // left DAC data
wire [14:0] rdata;         // right DAC data
wire [9:0]  ldata_okk;     // left DAC data  (PWM vol version)
wire [9:0]  rdata_okk;     // right DAC data (PWM vol version)
wire        vs;
wire        hs;
wire  [1:0] ar;
wire        ntsc;

wire  [5:0] ide_c_req;
wire [15:0] ide_c_readdata;
wire        ide_c_led;
wire        ide_ena;

wire [15:0] toccata_aud_left;
wire [15:0] toccata_aud_right;

wire  [8:0] drive_snd;

wire [6:0]  IndirectUserOutmt32;
wire [6:0]  IndirectUserOutFlop;
wire        user_port_mode;
assign USER_OUT = user_port_mode ? IndirectUserOutFlop : IndirectUserOutmt32;


minimig minimig
(
	//m68k pins
	.cpu_address  (chip_addr        ), // M68K address bus
	.cpu_data     (chip_dout        ), // M68K data bus
	.cpudata_in   (chip_din         ), // M68K data in
	._cpu_ipl     (chip_ipl         ), // M68K interrupt request
	._cpu_as      (chip_as          ), // M68K address strobe
	._cpu_uds     (chip_uds         ), // M68K upper data strobe
	._cpu_lds     (chip_lds         ), // M68K lower data strobe
	.cpu_r_w      (chip_rw          ), // M68K read / write
	.cpu_long     (chip_long        ),
	.chip32_en    (chip32_en        ),
	.ram_long     (ram_long         ),
	._cpu_dtack   (chip_dtack       ), // M68K data acknowledge
	._cpu_reset   (cpu_rst          ), // M68K reset
	._cpu_reset_in(cpu_nrst_out     ), // M68K reset out
	.nmi_addr     (cpu_nmi_addr     ), // M68K NMI address

	//sram pins
	.ram_data     (ram_data         ), // SRAM data bus
	.ramdata_in   (ramdata_in       ), // SRAM data bus in
	.ram_address  (ram_address      ), // SRAM address bus
	._ram_bhe     (_ram_bhe         ), // SRAM upper byte select
	._ram_ble     (_ram_ble         ), // SRAM lower byte select
	._ram_we      (_ram_we          ), // SRAM write enable
	._ram_oe      (_ram_oe          ), // SRAM output enable
	.chip48       (chip48           ), // big chipram read

	//system  pins
	.rst_ext      (reset_d          ), // reset from ctrl block
	.rst_out      (                 ), // minimig reset status
	.clk          (clk_sys          ), // output clock c1 ( 28.687500MHz)
	.clk7_en      (clk7_en          ), // 7MHz clock enable
	.clk7n_en     (clk7n_en         ), // 7MHz negedge clock enable
	.c1           (c1               ), // clk28m clock domain signal synchronous with clk signal
	.c3           (c3               ), // clk28m clock domain signal synchronous with clk signal delayed by 90 degrees
	.cck          (cck              ), // colour clock output (3.54 MHz)
	.eclk         (eclk             ), // 0.709379 MHz clock enable output (clk domain pulse)

	//rs232 pins
	.rxd          (uart_rx          ), // RS232 receive
	.txd          (uart_tx          ), // RS232 send
	.cts          (uart_cts         ), // RS232 clear to send
	.rts          (uart_rts         ), // RS232 request to send
	.dtr          (uart_dtr         ), // RS232 Data Terminal Ready
	.dsr          (uart_dsr         ), // RS232 Data Set Ready
	.cd           (uart_dsr         ), // RS232 Carrier Detect
	.ri           (1                ), // RS232 Ring Indicator

	//I/O
	._joy1        (~JOY0            ), // joystick 1 [fire4,fire3,fire2,fire,up,down,left,right] (default mouse port)
	._joy2        (~JOY1            ), // joystick 2 [fire4,fire3,fire2,fire,up,down,left,right] (default joystick port)
	._joy3        (~JOY2            ), // joystick 1 [fire4,fire3,fire2,fire,up,down,left,right]
	._joy4        (~JOY3            ), // joystick 2 [fire4,fire3,fire2,fire,up,down,left,right]
	.joya1        (JOYA0            ),
	.joya2        (JOYA1            ),
	.mouse_btn    (mouse_buttons    ), // mouse buttons
	.kbd_mouse_data (kbd_mouse_data ), // mouse direction data, keycodes
	.kbd_mouse_type (kbd_mouse_type ), // type of data
	.kms_level    (kbd_mouse_level  ),
	.pwr_led      (pwr_led          ), // power led
	.fdd_led      (LED_USER         ),
	.hdd_led      (ide_c_led        ),
	.rtc          (RTC              ),

	//host controller interface (SPI)
	.IO_UIO       (io_uio           ),
	.IO_FPGA      (io_fpga          ),
	.IO_STROBE    (io_strobe        ),
	.IO_WAIT      (io_wait          ),
	.IO_DIN       (io_din           ),
	.IO_DOUT      (fpga_dout        ),

	//video
	._hsync       (hs               ), // horizontal sync
	._vsync       (vs               ), // vertical sync
	.field1       (field1           ),
	.lace         (lace             ),
	.red          (r                ), // red
	.green        (g                ), // green
	.blue         (b                ), // blue
	.hblank       (hblank           ),
	.vblank       (vbl              ),
	.ar           (ar               ),
	.scanline     (fx               ),
	//.ce_pix     (ce_pix           ),
	.res          (res              ),
	.ntsc         (ntsc             ),

	//audio
	.ldata        (ldata            ), // left DAC data
	.rdata        (rdata            ), // right DAC data
	.ldata_okk    (ldata_okk        ), // 9bit
	.rdata_okk    (rdata_okk        ), // 9bit

	.aud_mix      (AUDIO_MIX        ),
	.audio_ext_l  (audio_ext_l),
	.audio_ext_r  (audio_ext_r),
	.audio_dma_req(audio_dma_req),
	.audio_dma_addr(audio_dma_addr),
	.audio_dma_ack(audio_dma_ack),
	.audio_dma_data(audio_dma_data),
	.audio_dma_error(audio_dma_error),

	//toccata soundcard
	.toccata_ena  (toccata_ena),
	.toccata_base (toccata_base),
	.cdtv_base    (cdtv_base),
	.a2065_ena  (a2065_ena),
	.a2065_base (a2065_base),
	.toccata_aud_left (toccata_aud_left),
	.toccata_aud_right(toccata_aud_right),

	.cdtv_mode           (cdtv_mode            ),

	.cdtv_din            (cdtv_din_w           ),
	.cdtv_selack         (cdtv_selack_w        ),

	.cdtv_cs             (cdtv_cs              ),
	.cdtv_cs_sec         (cdtv_cs_sec          ),
	.cdtv_cs_stch        (cdtv_cs_stch         ),
	.cdtv_cs_nvr         (cdtv_cs_nvr          ),
	.cdtv_cs_card        (cdtv_cs_card         ),
	.cdtv_wr             (cdtv_wr              ),
	.cdtv_rd             (cdtv_rd              ),
	.cdtv_uio_din        (cdtv_dout            ),
	.cdtv_uio_dout       (cdtv_din             ),
	.cdtv_req            (cdtv_req             ),
	.cdtv_subq_push      (1'b0                 ),
	.cdtv_subq_byte      (8'h00                ),
	.cdtv_sten_pulse     (1'b0                 ),
	.cdtv_scor_pulse     (1'b0                 ),
	.cdtv_sbcp_pulse     (1'b0                 ),

	.cdtv_dma_req        (cdtv_dma_req         ),
	.cdtv_dma_we         (cdtv_dma_we          ),
	.cdtv_dma_baddr      (cdtv_dma_baddr       ),
	.cdtv_dma_wbyte      (cdtv_dma_wbyte       ),
	.cdtv_dma_ack        (cdtv_dma_ack         ),

	.cdtv_nvr_dirty      (cdtv_nvr_dirty       ),
	.cdtv_card_dirty     (cdtv_card_dirty      ),

	.cdtv_cdda_volume    (cdtv_cdda_volume     ),
	.cdtv_cdda_volume_valid(cdtv_cdda_volume_valid),

	//user i/o
	.cachecfg     (cachecfg         ), // Cache c
	.cpucfg       (cpucfg           ), // CPU config
	.memcfg       (memcfg           ), // memory config
	.bootrom      (bootrom          ), // bootrom mode. Needed here to tell tg68k to also mirror the 256k Kickstart 

	.ide_fast     (ide_fast         ),
	.ide_ext_irq  (ide_f_irq        ),
	.akiko_irq    (akiko_f_irq      ),
	.ide_ena      (ide_ena          ),
	.ide_req      (ide_c_req        ),
	.ide_address  (ide_addr         ),
	.ide_write    (ide_wr           ),
	.ide_writedata(ide_dout         ),
	.ide_read     (ide_rd           ),
	.ide_readdata (ide_c_readdata   ),

	.a2065_clk_ddr(DDRAM_CLK),
	.a2065_mem_address(a2065_mem_address),
	.a2065_mem_burstcount(a2065_mem_burstcount),
	.a2065_mem_read(a2065_mem_read),
	.a2065_mem_readdata(a2065_mem_readdata),
	.a2065_mem_readdatavalid(a2065_mem_readdatavalid),
	.a2065_mem_writedata(a2065_mem_writedata),
	.a2065_mem_byteenable(a2065_mem_byteenable),
	.a2065_mem_write(a2065_mem_write),
	.a2065_mem_waitrequest(a2065_mem_waitrequest),
	
	.USER_IN      			(USER_IN),
	.USER_OUT     			(IndirectUserOutFlop),
	.user_port_mode 		(user_port_mode),
	.mister_floppy_status	(mister_floppy_status),
	.drive_snd    			(drive_snd)
);

// power led control
wire pwr_led;
reg [5:0] led_cnt;
reg led_dim;

always @ (posedge clk_sys) begin
  led_cnt <= led_cnt + 1'd1;
  led_dim <= |led_cnt[5:2];
end

assign LED_POWER[0] = pwr_led | ~led_dim;

assign FB_FORCE_BLANK = 0;

reg ce_out = 0;
always @(posedge CLK_VIDEO) begin
	reg [3:0] div;
	reg [3:0] add;
	reg [1:0] fs_res;
	reg old_vs;
	
	div <= div + add;
	if(~hblank & ~vblank) fs_res <= fs_res | res;

	old_vs <= vs;
	if(old_vs & ~vs) begin
		fs_res <= 0;
		div <= 0;
		add <= 1; // 7MHz
		if(fs_res[0]) add <= 2; // 14MHz
		if(fs_res[1] | (~status[42] & ~scandoubler)) add <= 4; // 28MHz
	end

	ce_out <= div[3] & !div[2:0];
end

assign ce_pix = ce_out;

wire [2:0] fx;
wire       scandoubler = (fx || forced_scandoubler) & ~lace;
wire [7:0] R,G,B;

video_mixer #(.LINE_LENGTH(2000), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
	.*,
	.hq2x(fx==1),
	.ce_pix(ce_out),
	.freeze_sync(),

	.R(r),
	.G(g),
	.B(b),
	.HSync(~hs),
	.VSync(~vs),
	.HBlank(~hde),
	.VBlank(~vde),

	.VGA_R(R),
	.VGA_G(G),
	.VGA_B(B)
);

assign CLK_VIDEO = clk_114;
assign VGA_F1    = field1;
assign VGA_R     = mt32_lcd ? {{2{mt32_lcd_pix}},R[7:2]} : R;
assign VGA_G     = mt32_lcd ? {{2{mt32_lcd_pix}},G[7:2]} : G;
assign VGA_B     = mt32_lcd ? {{2{mt32_lcd_pix}},B[7:2]} : B;

wire [12:0] arx,ary;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.VIDEO_ARX(arx),
	.VIDEO_ARY(ary),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[45:43])
);

reg [11:0] fb_arx, fb_ary;
always @(posedge CLK_VIDEO) begin
	reg [11:0] x, y, x1, y1;
	reg [1:0] cnt;
	
	cnt <= cnt + 1'd1;
	case(cnt)
		0: begin
				x1 <= FB_WIDTH;
				y1 <= FB_HEIGHT;
				x  <= FB_WIDTH;
				y  <= FB_HEIGHT;
			end

		1: if(x && ((x+x1) <= HDMI_WIDTH) && y && ((y+y1) <= HDMI_HEIGHT)) begin
				x <= x+x1;
				y <= y+y1;
				cnt <= 1;
			end

		2: begin
				fb_arx <= x;
				fb_ary <= y;
			end
	endcase
end

assign VIDEO_ARX = FB_EN ? {status[46], fb_arx} : arx;
assign VIDEO_ARY = FB_EN ? {status[46], fb_ary} : ary;

wire [2:0] sl = fx ? fx - 1'd1 : 3'd0;
assign VGA_SL = sl[1:0];

reg  hde;
wire vde = ~(fvbl | svbl);

wire [7:0] red, green, blue, r,g,b;
wire lace, field1;
wire hblank, vbl;
wire vblank = vbl | ~vs;
reg  fhbl, fvbl, shbl, svbl;
wire hbl = fhbl | shbl | ~hs;

wire  [1:0] res;

wire sset;
wire [11:0] shbl_l, shbl_r;
wire [11:0] svbl_t, svbl_b;

reg  [11:0] hbl_l=0, hbl_r=0;
reg  [11:0] hsta, hend, hmax, hcnt;
reg  [11:0] hsize;
always @(posedge clk_sys) begin
	reg old_hs;
	reg old_hblank;

	old_hs <= hs;
	old_hblank <= hblank;

	hcnt <= hcnt + 1'd1;
	if(~hs) hcnt <= 0;

	if(old_hblank & ~hblank) hend <= hcnt;
	if(~old_hblank & hblank) hsta <= hcnt;
	if(old_hs & ~hs)         hmax <= hcnt;

	if(hcnt == hend+hbl_l-2'd2) shbl <= 0;
	if(hcnt == hsta+hbl_r-2'd2) shbl <= 1;

	//force hblank
	if(hcnt == 8)         fhbl <= 0;
	if(hcnt == hmax-4'd8) fhbl <= 1;
	
	if(~old_hblank & hblank & ~field1 & (vcnt == 1'd1)) hsize <= hcnt - hend;
end

reg [11:0] vbl_t=0, vbl_b=0;
reg [11:0] vend, vmax, f1_vend, f1_vsize, vcnt, vs_end;
reg [11:0] vsize;
always @(posedge clk_sys) begin
	reg old_vs;
	reg old_vblank, old_hs, old_hbl;

	old_vs <= vs;
	old_hs <= hs;
	old_vblank <= vblank;
	
	if(old_hs & ~hs) vcnt <= vcnt + 1'd1;
	if(~old_vblank & vblank) vcnt <= 0;

	if(~lace | ~field1) begin
		if(old_vblank & ~vblank) vend <= vcnt;
		if(~old_vs & vs)         vs_end <= vcnt;
		
		if(~old_vblank & vblank) begin
			vmax <= vcnt;
			vsize <= vcnt - vend + f1_vsize;
			f1_vsize <= 0;
		end
	end
	else begin
		if(old_vblank & ~vblank) f1_vend <= vcnt;
		if(~old_vblank & vblank) begin
			f1_vsize <= vcnt - f1_vend;
		end
	end

	old_hbl <= hbl;
	if((old_hbl & ~hbl) | !vcnt) begin
		if(vcnt == vend+vbl_t) svbl <= 0;
		if(vcnt == (vbl_b[11] ? vmax+vbl_b : vbl_b) ) svbl <= 1;

		//force vblank
		if(vcnt == vmax-1)    fvbl <= 1;
		if(vcnt == vs_end+2)  fvbl <= 0;
	end
	
	hde <= ~hbl;
end

always @(posedge clk_sys) begin
	reg old_level;
	reg alt = 0;

	old_level <= kbd_mouse_level;
	if((old_level ^ kbd_mouse_level) && (kbd_mouse_type==3)) begin
		if(kbd_mouse_data == 'h41) begin //backspace
			vbl_t <= 0; vbl_b <= 0;
			hbl_l <= 0; hbl_r <= 0;
		end
		else if(kbd_mouse_data == 'h4c) begin //up
			if(alt) vbl_b <= vbl_b + 1'd1;
			else    vbl_t <= vbl_t + 1'd1;
		end
		else if(kbd_mouse_data == 'h4d) begin //down
			if(alt) vbl_b <= vbl_b - 1'd1;
			else    vbl_t <= vbl_t - 1'd1;
		end
		else if(kbd_mouse_data == 'h4f) begin //left
			if(alt) hbl_r <= hbl_r + 3'd4;
			else    hbl_l <= hbl_l + 3'd4;
		end
		else if(kbd_mouse_data == 'h4e) begin //right
			if(alt) hbl_r <= hbl_r - 3'd4;
			else    hbl_l <= hbl_l - 3'd4;
		end
		else if(kbd_mouse_data == 'h64 || kbd_mouse_data == 'h65) begin //alt press
			alt <= 1;
		end
		else if(kbd_mouse_data == 'hE4 || kbd_mouse_data == 'hE5) begin //alt release
			alt <= 0;
		end
	end
	
	if(sset) begin
		vbl_t <= svbl_t; vbl_b <= svbl_b;
		hbl_l <= shbl_l; hbl_r <= shbl_r;
	end
end


reg [11:0] scr_hbl_l, scr_hbl_r;
reg [11:0] scr_vbl_t, scr_vbl_b;
reg [11:0] scr_hsize, scr_vsize;
reg  [1:0] scr_res;
reg  [6:0] scr_flg;

always @(posedge clk_sys) begin
	reg old_vblank;

	old_vblank <= vblank;
	if(old_vblank & ~vblank) begin
		scr_hbl_l <= hbl_l;
		scr_hbl_r <= hbl_r;
		scr_vbl_t <= vbl_t;
		scr_vbl_b <= vbl_b;
		scr_hsize <= hsize;
		scr_vsize <= vsize;
		scr_res   <= res;

		if(scr_res != res || scr_vsize != vsize || scr_hsize != hsize) scr_flg <= scr_flg + 1'd1;
	end
end

////////////////////////////  MT32pi  ////////////////////////////////// 

reg   userport_change_reset;
wire        mt32_reset    = status[32] | reset | userport_change_reset;
wire        mt32_disable  = status[33];
wire        mt32_mode_req = status[34];
wire  [1:0] mt32_rom_req  = status[36:35];
wire  [7:0] mt32_sf_req   = status[39:37];
wire  [1:0] mt32_info     = status[41:40];
wire        midi_tx       = uart_tx;

wire [15:0] mt32_i2s_r, mt32_i2s_l;
wire  [7:0] mt32_mode, mt32_rom, mt32_sf;
wire        mt32_lcd_en, mt32_lcd_pix, mt32_lcd_update;
wire        midi_rx;

wire mt32_newmode;
wire mt32_available;
wire mt32_use  = mt32_available & ~mt32_disable;
wire mt32_mute = mt32_available &  mt32_disable;

mt32pi mt32pi
(
	.*,
	.USER_IN(USER_IN),
	.USER_OUT(IndirectUserOutmt32),

	.CE_PIXEL(ce_pix_mt32),
	.reset(mt32_reset),
	.midi_tx(midi_tx | mt32_mute)
);

wire  [4:0] mt32_cfg = (mt32_mode == 'hA2) ? {mt32_sf[2:0],  2'b10} :
                       (mt32_mode == 'hA1) ? {mt32_rom[1:0], 2'b01} : 5'd0;

reg mt32_info_req;
reg [3:0] mt32_info_disp;
reg last_userport_mode;
always @(posedge clk_sys) begin
	reg old_mode;
	
	userport_change_reset <= 0;
	last_userport_mode <= user_port_mode;
	if (last_userport_mode != user_port_mode) userport_change_reset <= 1;

	old_mode <= mt32_newmode;
	mt32_info_req <= (old_mode ^ mt32_newmode) && (mt32_info == 1);
	
	mt32_info_disp <= (mt32_mode == 'hA2) ? (4'd1 + mt32_sf[2:0]) :
                     (mt32_mode == 'hA1 && mt32_rom == 0) ?  4'd9 :
                     (mt32_mode == 'hA1 && mt32_rom == 1) ?  4'd10 :
                     (mt32_mode == 'hA1 && mt32_rom == 2) ?  4'd11 : 4'd12;
end

reg mt32_lcd_on;
always @(posedge CLK_VIDEO) begin
	int to;
	reg old_update;

	old_update <= mt32_lcd_update;
	if(to) to <= to - 1;

	if(mt32_info == 2) mt32_lcd_on <= 1;
	else if(mt32_info != 3) mt32_lcd_on <= 0;
	else begin
		if(!to) mt32_lcd_on <= 0;
		if(old_update ^ mt32_lcd_update) begin
			mt32_lcd_on <= 1;
			to <= 114000000 * 2;
		end
	end
end

wire mt32_lcd = mt32_lcd_on & mt32_lcd_en;

reg ce_pix_mt32;
always @(posedge CLK_VIDEO) begin
	reg [3:0] div;
	
	div <= div + 1'd1;
	ce_pix_mt32 <= !div;
end

/* ------------------------------------------------------------------------------ */

wire flt_en    = ~status[48] ? pwr_led : status[47];
wire aud_1200  = status[49];
wire paula_pwm = status[50];

wire [15:0] dsnd_l, dsnd_r;
drive_sounds drive_sounds
(
	.clk(clk_114),
	.rst(reset_d),
	.volume(status[52:51]),
	.drive_snd(drive_snd),
	.sample_l(dsnd_l),
	.sample_r(dsnd_r),
	.ddr_addr(dsnd_addr),
	.ddr_rd(dsnd_rd),
	.ddr_busy(dsnd_busy),
	.ddr_dout(DDRAM_DOUT),
	.ddr_dout_ready(dsnd_ready)
);

wire [15:0] paula_smp_l = (paula_pwm ? {ldata_okk[8:0], 7'b0} : {ldata[14:0], 1'b0});
wire [15:0] paula_smp_r = (paula_pwm ? {rdata_okk[8:0], 7'b0} : {rdata[14:0], 1'b0});

// LPF 4400Hz, 1st order, 6db/oct
wire [15:0] lpf4400_l, lpf4400_r;
IIR_filter #(0) lpf4400
(
	.clk(clk_sys),
	.reset(reset),

	.ce(clk7_en | clk7n_en),
	.sample_ce(1),

	.cx (40'd4304835800),
	.cx0(1),
	.cy0(-2088941),
	
	.input_l(paula_smp_l),
	.input_r(paula_smp_r),
	.output_l(lpf4400_l),
	.output_r(lpf4400_r)
);

wire [15:0] audm_l = aud_1200 ? paula_smp_l : lpf4400_l;
wire [15:0] audm_r = aud_1200 ? paula_smp_r : lpf4400_r;

// LPF 3000Hz 1st + 3400Hz 1st
wire [15:0] lpf3275_l, lpf3275_r;
IIR_filter #(0) lpf3275
(
	.clk(clk_sys),
	.reset(reset),

	.ce(clk7_en | clk7n_en),
	.sample_ce(1),

	.cx (40'd8536629),
	.cx0(2),
	.cx1(1),
	.cy0(-4182432),
	.cy1(2085297),

	.input_l(audm_l),
	.input_r(audm_r),
	.output_l(lpf3275_l),
	.output_r(lpf3275_r)
);

reg [15:0] aud_l, aud_r;
always @(posedge CLK_AUDIO) begin
	reg [15:0] old_l0, old_l1, old_r0, old_r1;

	old_l0 <= flt_en ? lpf3275_l : audm_l;
	old_l1 <= old_l0;
	if(old_l0 == old_l1) aud_l <= old_l1;

	old_r0 <= flt_en ? lpf3275_r : audm_r;
	old_r1 <= old_r0;
	if(old_r0 == old_r1) aud_r <= old_r1;
end

wire  [15:0] cdda_l;
wire  [15:0] cdda_r;
wire  [15:0] cdda_dout;
wire         cdda_req;
wire         cdda_wr;

cdda #(28375160) cdda
(
	.CLK(clk_sys),
	.nRESET(~reset),
	.WRITE_REQ(cdda_req),
	.WRITE(cdda_wr),
	.DIN(cdda_dout),
	.AUDIO_L(cdda_l),
	.AUDIO_R(cdda_r)
);

wire [10:0] cdda_gain = (cdtv_mode && cdtv_cdda_volume_valid) ? {1'b0, cdtv_cdda_volume} : 11'd1023;

reg signed [15:0] cdda_sl, cdda_sr;
always @(posedge CLK_AUDIO) begin
	reg signed [26:0] pl, pr;

	pl = $signed(cdda_l) * $signed(cdda_gain);
	pr = $signed(cdda_r) * $signed(cdda_gain);
	cdda_sl <= pl[25:10];
	cdda_sr <= pr[25:10];
end

reg [15:0] dsnd_al, dsnd_ar;
always @(posedge CLK_AUDIO) begin
	reg [31:0] old_d0, old_d1;

	old_d0 <= {dsnd_l, dsnd_r};
	old_d1 <= old_d0;
	if(old_d0 == old_d1) {dsnd_al, dsnd_ar} <= old_d1;
end

// Coherent stereo mailbox. The source holds both words until the audio
// clock acknowledges the toggle; neither channel can tear across a sample.
reg [31:0] ext_mailbox;
reg ext_toggle, ext_ack;
(* ASYNC_REG = "TRUE" *) reg [1:0] ext_ack_sync, ext_toggle_sync;
reg signed [15:0] ext_audio_l, ext_audio_r;
always @(posedge clk_sys or posedge reset) begin
	if (reset) begin
		ext_mailbox <= 0;
		ext_toggle <= 0;
		ext_ack_sync <= 0;
	end else begin
		ext_ack_sync <= {ext_ack_sync[0], ext_ack};
		if (ext_ack_sync[1] == ext_toggle) begin
			ext_mailbox <= {audio_ext_l, audio_ext_r};
			ext_toggle <= ~ext_toggle;
		end
	end
end
always @(posedge CLK_AUDIO or posedge reset) begin
	if (reset) begin
		ext_toggle_sync <= 0;
		ext_ack <= 0;
		ext_audio_l <= 0;
		ext_audio_r <= 0;
	end else begin
		ext_toggle_sync <= {ext_toggle_sync[0], ext_toggle};
		if (ext_toggle_sync[1] != ext_ack) begin
			{ext_audio_l, ext_audio_r} <= ext_mailbox;
			ext_ack <= ext_toggle_sync[1];
		end
	end
end

reg [15:0] out_l, out_r;
always @(posedge CLK_AUDIO) begin
	reg [18:0] tmp_l, tmp_r;

	tmp_l <= {{3{aud_l[15]}},aud_l} + {{3{toccata_aud_left[15]}},toccata_aud_left} + (mt32_mute ? 19'd0 : {{3{mt32_i2s_l[15]}},mt32_i2s_l}) + {{3{cdda_sl[15]}}, cdda_sl} + {{3{dsnd_al[15]}}, dsnd_al} + {{3{ext_audio_l[15]}},ext_audio_l};
	tmp_r <= {{3{aud_r[15]}},aud_r} + {{3{toccata_aud_right[15]}},toccata_aud_right} + (mt32_mute ? 19'd0 : {{3{mt32_i2s_r[15]}},mt32_i2s_r}) + {{3{cdda_sr[15]}}, cdda_sr} + {{3{dsnd_ar[15]}}, dsnd_ar} + {{3{ext_audio_r[15]}},ext_audio_r};

	// clamp the output
	out_l <= (tmp_l[18:15] == 4'b0000 || tmp_l[18:15] == 4'b1111) ? tmp_l[15:0] : {tmp_l[18], {15{~tmp_l[18]}}};
	out_r <= (tmp_r[18:15] == 4'b0000 || tmp_r[18:15] == 4'b1111) ? tmp_r[15:0] : {tmp_r[18], {15{~tmp_r[18]}}};
end

assign AUDIO_S = 1;
assign AUDIO_L = out_l;
assign AUDIO_R = out_r;

endmodule
