create_clock -name root_clk -period 20.000 [get_ports {CLOCK_50}]
create_clock -name spi_clk -period 10.000 [get_ports {SPI_IO_CLK}]
#create_clock -name {clk} -period 20.000 -waveform { 0.000 10.000 } [get_ports {CLOCK_50}]

derive_clock_uncertainty
derive_pll_clocks
#derivate_lock_uncertainty