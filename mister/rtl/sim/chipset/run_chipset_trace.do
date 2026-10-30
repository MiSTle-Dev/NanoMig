# tb_chipset_bus_trace ModelSim/Questa runner.
# Run with: vsim -c -do run_chipset_trace.do
# Exit code: 0 on PASS, 1 on FAIL.

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -sv -quiet ../../chipset_bus_trace.v
vlog -sv -quiet tb_chipset_bus_trace.sv

vsim -c -voptargs=+acc work.tb_chipset_bus_trace
run -all

set num_errs [examine -value /tb_chipset_bus_trace/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
