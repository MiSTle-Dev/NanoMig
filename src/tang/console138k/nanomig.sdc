create_clock -name clk_osc -period 20 -waveform {0 10} [get_ports {clk}] -add
create_clock -name clk_hdmi -period 7 -waveform {0 3} [get_nets {clk_pixel_x5}] -add
create_clock -name clk_flash -period 11.764 -waveform {0 5.882} [get_ports {mspi_clk}] -add
create_clock -name clk_28 -period 35.71 -waveform {0 17.85} [get_pins {clk_div_5/clkdiv_inst/CLKOUT}]
create_clock -name clk_companion -period 50 -waveform {0 25} [get_ports {pmod_companion_clk}] -add
create_clock -name clk_companion_int -period 50 -waveform {0 25} [get_ports {spi_sclk}] -add
