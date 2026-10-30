# tb_sdram_fwd runner (posted-write -> chip-read store-to-load forwarding).
# Run with: vsim -c -do run_fwd.do
# Exit code 0 on PASS, 1 on FAIL (read from bench `errs`).
#
# All-Verilog build. sdram_ctrl instantiates cpu_cache_new which instantiates
# `dpram`; we supply the behavioral Verilog dpram (dpram_sim.v) as in the cache
# bench to avoid the VHDL altera_mf altsyncram model.

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -sv -quiet dpram_sim.v
vlog -sv -quiet ../../cpu_cache_new.v
vlog -sv -quiet sdram_ctrl_sim.v
vlog -sv -quiet tb_sdram_fwd.sv

vsim -c -voptargs=+acc work.tb_sdram_fwd
run -all

set num_errs [examine -value /tb_sdram_fwd/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
