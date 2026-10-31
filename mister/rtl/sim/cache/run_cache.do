# tb_cache_snoop runner (cpu_cache_new fill-vs-snoop coherency).
# Run with: vsim -c -do run_cache.do
# Sets exit code 0 on PASS, 1 on FAIL (read from bench `errs`).
#
# All-Verilog build. cpu_cache_new instantiates `dpram`; we supply a behavioral
# Verilog dpram (dpram_sim.v) that reproduces the altsyncram semantics relevant
# to the race (1-cycle registered read, same-port NEW_DATA, mixed-port
# OLD_DATA). This avoids the ModelSim ASE *VHDL* altera_mf altsyncram model,
# which fatals (vsim-3471 slice range) on the width_byteena=1 dpram config.

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# behavioral dpram + cache + bench (all Verilog/SV).
vlog -sv -quiet dpram_sim.v
vlog -sv -quiet ../../cpu_cache_new.v
vlog -sv -quiet tb_cache_snoop.sv

vsim -c -voptargs=+acc work.tb_cache_snoop
run -all

set num_errs [examine -value /tb_cache_snoop/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
