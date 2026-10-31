# tb_akiko_pbx_dma Questa runner (M4 — PBX sector DMA).
# Run with: vsim -c -do run_pbx.do
# Sets exit code 0 on PASS, 1 on FAIL.

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -quiet C:/intelFPGA_lite/17.0/quartus/eda/sim_lib/altera_mf.v
vlog -sv -quiet ../../akiko_nvram.v
vlog -sv -quiet ../../akiko.v
vlog -sv -quiet tb_akiko_pbx_dma.sv

vsim -c -voptargs=+acc work.tb_akiko_pbx_dma
run -all

set num_errs [examine -value /tb_akiko_pbx_dma/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
