set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_regs {*cpu_inst_p/*}] -setup -end 2
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_regs {*cpu_inst_p/*}] -hold -end 1
// the TG68K only advances every second clk_28 cycle (CPU_SLOW14), so its reset has two cycles too
set_multicycle_path -from [get_regs {cpu_reset*}] -to [get_regs {*cpu_inst_p/*}] -setup -end 2
set_multicycle_path -from [get_regs {cpu_reset*}] -to [get_regs {*cpu_inst_p/*}] -hold -end 1
