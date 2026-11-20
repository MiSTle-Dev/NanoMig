create_clock -name clk85 -period 11.764 -waveform {0 5.882} [get_ports {O_sdram_clk}] -add
create_clock -name clk_companion -period 50 -waveform {0 25} [get_ports {companion_clk}] -add
create_clock -name clk_hdmi -period 7 -waveform {0 3} [get_pins {amigaclks/pll_hdmi/u_pll/PLLA_inst/CLKOUT0}] -add
create_clock -name clk_osc -period 37 -waveform {0 18} [get_ports {clk}] -add
create_clock -name clk_spi -period 11.764 -waveform {0 5.882} [get_ports {mspi_clk}] -add
create_clock -name clk28 -period 35.71 -waveform {0 17.85} [get_pins {amigaclks/clk_div_5/clkdiv_inst/CLKOUT}]
create_clock -name clk_audio -period 20833 -waveform {0 10416} [get_nets {clk_audio}]

// every multi cycle setup exception needs its hold counterpart, otherwise the
// hold analysis still assumes a single cycle relationship between the two
// domains and reports thousands of meaningless violations
set_multicycle_path -from [get_clocks {clk28}] -to [get_clocks {clk85}] 2
set_multicycle_path -from [get_clocks {clk28}] -to [get_clocks {clk85}] -hold 1
set_multicycle_path -from [get_clocks {clk85}] -to [get_clocks {clk28}] -start 2
set_multicycle_path -from [get_clocks {clk85}] -to [get_clocks {clk28}] -hold -start 1

// set_false_path -from [get_cells {sysctrl/system_cpu*}]
set_false_path -from [get_cells {sysctrl/system_chipset*}]
set_false_path -from [get_cells {sysctrl/system_video*}]
set_false_path -from [get_cells {sysctrl/system_chipmem*}]
set_false_path -from [get_cells {sysctrl/system_slowmem*}]
set_false_path -from [get_cells {sysctrl/system_fastmem*}]
set_false_path -from [get_cells {sysctrl/system_volume*}]

// The disk length register reaches the blitter through the dma priority logic.
// Both live in the chipset, which advances on the 7MHz (and slower) clock
// enables, so these are multi cycle paths on the 28MHz clock.
set_multicycle_path -from [get_regs {*PAULA1/pf1/dsklen*}] -to [get_regs {*AGNUS1/bl1/*}] -setup -end 4
set_multicycle_path -from [get_regs {*PAULA1/pf1/dsklen*}] -to [get_regs {*AGNUS1/bl1/*}] -hold -end 3
