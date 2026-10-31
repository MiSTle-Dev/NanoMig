# tb_akiko_cdda Questa runner (M6.2 — CDDA FIFO + 44.1 kHz pump).
# Run with: vsim -c -do run_cdda.do
# Sets exit code 0 on PASS, 1 on FAIL.

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -sv -quiet ../../cdda.v
vlog -sv -quiet tb_akiko_cdda.sv

vsim -c -voptargs=+acc work.tb_akiko_cdda
run -all

set num_errs [examine -value /tb_akiko_cdda/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
