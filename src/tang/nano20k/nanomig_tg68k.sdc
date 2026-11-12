set_false_path -from [get_cells {sysctrl/system_cpu*}]
// the TG68K advances at most every second clk28 cycle (CPU_SLOW14 in
// cpu_wrapper.v), so all its internal register to register paths are
// true two cycle paths
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_regs {*cpu_inst_p/*}] -setup -end 2
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_regs {*cpu_inst_p/*}] -hold -end 1
// the TG68K register file is distributed LUT ram, not covered by get_regs,
// so additionally relax paths ending at any pin inside the cpu core
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_pins {*cpu_inst_p/*/DI* *cpu_inst_p/*/AD* *cpu_inst_p/*/WRE}] -setup -end 2
set_multicycle_path -from [get_regs {*cpu_inst_p/*}] -to [get_pins {*cpu_inst_p/*/DI* *cpu_inst_p/*/AD* *cpu_inst_p/*/WRE}] -hold -end 1
