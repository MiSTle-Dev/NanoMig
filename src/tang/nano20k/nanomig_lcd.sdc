//Copyright (C)2014-2025 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.11.01 
//Created Time: 2025-06-25 21:13:21
create_clock -name clk85 -period 11.684 -waveform {0 5.848} [get_pins {amigaclks/sysclk_inst/CLKOUT}]
create_clock -name clk_osc -period 37 -waveform {0 18} [get_ports {clk}] -add
create_clock -name clk_spi -period 14.085 -waveform {0 7.04} [get_ports {mspi_clk}] -add
create_generated_clock -name clk28 -source [get_pins {amigaclks/sysclk_inst/CLKOUT}] -master_clock clk85 -divide_by 3 [get_pins {amigaclks/sysclk_inst/CLKOUTD3}]
set_multicycle_path -from [get_clocks {clk28}] -to [get_clocks {clk85}]  -setup -start 2
set_multicycle_path -from [get_clocks {clk28}] -to [get_clocks {clk85}]  -hold -start 2
