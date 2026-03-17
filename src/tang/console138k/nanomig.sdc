create_clock -name clk_osc -period 20 -waveform {0 10} [get_ports {clk}] -add
create_clock -name clk_companion_int -period 50 -waveform {0 25} [get_ports {spi_sclk}] -add
create_clock -name clk85 -period 11.684 -waveform {0 5.848} [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT1}] -add
create_clock -name clk85_shift -period 11.684 -waveform {0 5.848} [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT2}] -add
create_clock -name clk_flash -period 11.684 -waveform {0 5.848} [get_ports {mspi_clk}] -add
create_clock -name clk_hdmi -period 7 -waveform {0 3} [get_nets {clk_pixel_x5}] -add
create_clock -name i2s_clk -period 500 -waveform {0 3} [get_nets {i2s_clk}] -add
create_clock -name mcuclk -period 500 -waveform {0 3} [get_nets {mcu/n4_24}] -add
create_clock -name clk_audio -period 500 -waveform {0 3} [get_nets {clk_audio}] -add
create_generated_clock -name clk28 -source [get_pins {pll_hdmi/u_pll/PLL_inst/CLKOUT0}] -master_clock clk_hdmi -divide_by 5 [get_pins {clk_div_5/clkdiv_inst/CLKOUT}]
set_multicycle_path -from [get_clocks {clk28}] -to [get_clocks {clk85}]  -setup -start 2
set_multicycle_path -from [get_clocks {clk28}] -to [get_clocks {clk85}]  -hold -start 2
