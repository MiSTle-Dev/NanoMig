//Copyright (C)2014-2025 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.11.01
//Created Time: 2025-06-25 21:13:21
create_clock -name clk85 -period 11.684 -waveform {0 5.848} [get_pins {amigaclks/sysclk_inst/CLKOUT}]
create_clock -name clk_hdmi -period 7 -waveform {0 3} [get_nets {clk_pixel_x5}] -add
create_clock -name clk_osc -period 37 -waveform {0 18} [get_ports {clk}] -add
create_clock -name clk_spi -period 14.085 -waveform {0 7.04} [get_ports {mspi_clk}] -add
create_generated_clock -name clk28 -source [get_pins {amigaclks/sysclk_inst/CLKOUT}] -master_clock clk85 -divide_by 3 [get_pins {amigaclks/sysclk_inst/CLKOUTD3}]

// every multi cycle setup exception needs its hold counterpart, otherwise the
// hold analysis still assumes a single cycle relationship between the two
// domains and reports thousands of meaningless violations
set_multicycle_path -from [get_clocks {clk28}] -to [get_clocks {clk85}] 4
set_multicycle_path -from [get_clocks {clk28}] -to [get_clocks {clk85}] -hold 3
set_multicycle_path -from [get_clocks {clk85}] -to [get_clocks {clk28}] -start 2
set_multicycle_path -from [get_clocks {clk85}] -to [get_clocks {clk28}] -hold -start 1

set_false_path -from [get_cells {sysctrl/system_cpu*}]
set_false_path -from [get_cells {sysctrl/system_chipset*}]
set_false_path -from [get_cells {sysctrl/system_video*}]
set_false_path -from [get_cells {sysctrl/system_chipmem*}]
set_false_path -from [get_cells {sysctrl/system_slowmem*}]
set_false_path -from [get_cells {sysctrl/system_fastmem*}]
set_false_path -from [get_cells {sysctrl/system_turbo*}]
set_false_path -from [get_cells {sysctrl/system_volume*}]

// the TG68K advances at most every second clk28 cycle (CPU_SLOW14 in
// cpu_wrapper.v), so all its internal register to register paths are
// true two cycle paths
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_regs {*cpu_inst_p/*}] -setup -end 2
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_regs {*cpu_inst_p/*}] -hold -end 1
// the TG68K register file is distributed LUT ram, not covered by get_regs,
// so additionally relax paths ending at any pin inside the cpu core
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_pins {*cpu_inst_p/*/DI* *cpu_inst_p/*/AD* *cpu_inst_p/*/WRE}] -setup -end 2
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_pins {*cpu_inst_p/*/DI* *cpu_inst_p/*/AD* *cpu_inst_p/*/WRE}] -hold -end 1
// The hdmi audio sample words cross from the 48kHz audio clock into the pixel
// clock domain through a toggle handshake: the data is written a full audio
// period (~10us) before the synchronized toggle releases the capture, so the
// single cycle relationship the analyzer assumes here is meaningless. Left
// unconstrained the path is only met by lucky placement, and when it is not
// the captured sample words pick up wrong bits - audible as noisy samples.
set_false_path -from [get_regs {*packet_picker/audio_sample_word_transfer*}] -to [get_regs {*packet_picker/audio_sample_word_buffer*}]
// The disk length register reaches the blitter through the dma priority logic.
// Both live in the chipset, which advances on the 7MHz (and slower) clock
// enables, so these are multi cycle paths on the 28MHz clock.
set_multicycle_path -from [get_regs {*PAULA1/pf1/dsklen*}] -to [get_regs {*AGNUS1/bl1/*}] -setup -end 4
set_multicycle_path -from [get_regs {*PAULA1/pf1/dsklen*}] -to [get_regs {*AGNUS1/bl1/*}] -hold -end 3
