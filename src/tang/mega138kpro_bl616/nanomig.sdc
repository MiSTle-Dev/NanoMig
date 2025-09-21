//Copyright (C)2014-2024 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.9 
//Created Time: 2024-02-23 19:02:18
// create_clock -name clk_hdmi -period 6.25 -waveform {0 3.125} [get_nets {video2hdmi/clk_pixel_x5}] -add
// create_clock -name clk_flash -period 10 -waveform {0 5} [get_nets {flash_clk}]
create_clock -name clk_spi -period 10 -waveform {0 5} [get_ports {mspi_clk}] -add
create_clock -name clk_32 -period 31 -waveform {0 15} [get_ports {O_sdram_clk}] -add
create_clock -name clk_osc -period 20 -waveform {0 10} [get_ports {clk}] -add
