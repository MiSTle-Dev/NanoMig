# tb_cdtv_tpi_stch Questa runner — 2026-05-30 DotC STCH investigation.
# Run with: vsim -c -do run_tpi_stch.do

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -quiet C:/intelFPGA_lite/17.0/quartus/eda/sim_lib/altera_mf.v
vlog -sv -quiet ../../cdtv_bridge.v
vlog -sv -quiet tb_cdtv_tpi_stch.sv

vsim -c -voptargs=+acc work.tb_cdtv_tpi_stch
run -all

set num_errs [examine -value /tb_cdtv_tpi_stch/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
