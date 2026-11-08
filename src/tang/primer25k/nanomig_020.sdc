//Copyright (C)2014-2024 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.9 
//Created Time: 2024-02-23 19:02:18
create_clock -name clk_hdmi -period 7 -waveform {0 3} [get_nets {clk_pixel_x5}] -add
create_clock -name clk_flash -period 11.764 -waveform {0 5.882} [get_ports {mspi_clk}] -add
create_clock -name clk_85 -period 11.764 -waveform {0 5.882} [get_ports {O_sdram_clk}] -add
create_clock -name clk_osc -period 20 -waveform {0 10} [get_ports {clk}] -add
create_clock -name clk_28 -period 35.71 -waveform {0 17.85} [get_pins {clk_div_5/clkdiv_inst/CLKOUT}]
create_clock -name clk_companion -period 50 -waveform {0 25} [get_ports {pmod_companion_clk}] -add

// 68020/AGA build, same exceptions as mistle/gw5a_25 with this board's clock names
set_multicycle_path -from [get_clocks {clk_28}] -to [get_clocks {clk_85}] 2
set_multicycle_path -from [get_clocks {clk_28}] -to [get_clocks {clk_85}] -hold 1
set_multicycle_path -from [get_clocks {clk_85}] -to [get_clocks {clk_28}] -start 2
set_multicycle_path -from [get_clocks {clk_85}] -to [get_clocks {clk_28}] -hold -start 1
set_false_path -from [get_cells {sysctrl/system_chipset*}]
set_false_path -from [get_cells {sysctrl/system_video*}]
set_false_path -from [get_cells {sysctrl/system_chipmem*}]
set_false_path -from [get_cells {sysctrl/system_slowmem*}]
set_false_path -from [get_cells {sysctrl/system_fastmem*}]
set_false_path -from [get_cells {sysctrl/system_turbo*}]
set_false_path -from [get_cells {sysctrl/system_volume*}]
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_regs {*cpu_inst_p/*}] -setup -end 2
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_regs {*cpu_inst_p/*}] -hold -end 1
set_false_path -from [get_regs {*packet_picker/audio_sample_word_transfer*}] -to [get_regs {*packet_picker/audio_sample_word_buffer*}]
set_multicycle_path -from [get_regs {*PAULA1/pf1/dsklen*}] -to [get_regs {*AGNUS1/bl1/*}] -setup -end 4
set_multicycle_path -from [get_regs {*PAULA1/pf1/dsklen*}] -to [get_regs {*AGNUS1/bl1/*}] -hold -end 3
// the TG68K only advances every second clk_28 cycle (CPU_SLOW14), so its reset has two cycles too
set_multicycle_path -from [get_regs {cpu_reset*}] -to [get_regs {*cpu_inst_p/*}] -setup -end 2
set_multicycle_path -from [get_regs {cpu_reset*}] -to [get_regs {*cpu_inst_p/*}] -hold -end 1
// reset_cnt only counts while the cpu is held in reset and is static afterwards
set_false_path -from [get_regs {reset_cnt*}]
