# tb_akiko_chipram_master Questa runner (M5 -- chip-RAM master arbiter).
# Run with: vsim -c -do run_chipram.do
# Sets exit code 0 on PASS, 1 on FAIL.

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -sv -quiet ../../memory_router.v
vlog -sv -quiet ../../chipdma_arb.v
vlog -sv -quiet tb_akiko_chipram_master.sv

vsim -c -voptargs=+acc work.tb_akiko_chipram_master
run -all

set num_errs [examine -value /tb_akiko_chipram_master/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
