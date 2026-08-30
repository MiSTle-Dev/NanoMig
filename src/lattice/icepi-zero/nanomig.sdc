create_clock -name {clk} -period 20 [get_ports {clk}]
create_clock -name {clk_pixel} -period 35.3 [get_nets {clk_pixel}]
create_clock -name {clk_pixel_x5} -period 7.06 [get_nets {clk_pixel_x5}]
create_clock -name {clk_85m} -period 11.7 [get_nets {clk_85m}]

set_multicycle_path -from [get_clocks {clk_pixel}] -to [get_clocks {clk_85m}] 2
set_multicycle_path -from [get_clocks {clk_pixel}] -to [get_clocks {clk_85m}] -hold 3
set_multicycle_path -from [get_clocks {clk_85m}] -to [get_clocks {clk_pixel}] -start 2
set_multicycle_path -from [get_clocks {clk_85m}] -to [get_clocks {clk_28}] -hold -start 1

set_false_path -from [get_cells {nanomig.minimig.AGNUS1.bc1.beamcon0*}]

set_false_path -from [get_cells {sysctrl.system_cpu*}]
set_false_path -from [get_cells {sysctrl.system_chipset*}]
set_false_path -from [get_cells {sysctrl.system_video*}]
set_false_path -from [get_cells {sysctrl.system_chipmem*}]
set_false_path -from [get_cells {sysctrl.system_slowmem*}]
set_false_path -from [get_cells {sysctrl.system_fastmem*}]
set_false_path -from [get_cells {sysctrl.system_volume*}]

set_false_path -from [get_cells {*packet_picker/audio_sample_word_transfer*}]

set_multicycle_path -from [get_cells {*PAULA1/pf1/dsklen*}] -to [get_cells {*AGNUS1/bl1/*}] -setup 4
set_multicycle_path -from [get_cells {*PAULA1/pf1/dsklen*}] -to [get_cells {*AGNUS1/bl1/*}] -hold 3
