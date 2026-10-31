# tb_cdtv_cr511 Questa runner — M2 phase-0.
# Run with: vsim -c -do run_cr511.do
# Sets exit code 0 on PASS, 1 on FAIL.

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -quiet C:/intelFPGA_lite/17.0/quartus/eda/sim_lib/altera_mf.v
vlog -sv -quiet ../../cdtv_bridge.v
vlog -sv -quiet tb_cdtv_cr511.sv

vsim -c -voptargs=+acc work.tb_cdtv_cr511
run -all

set num_errs [examine -value /tb_cdtv_cr511/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
