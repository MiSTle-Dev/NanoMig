# tb_akiko_nvram Questa runner (Phase 13 -- I2C slave EEPROM).
# Run with: vsim -c -do run_nvram.do
# Sets exit code 0 on PASS, 1 on FAIL.

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# altera_mf.v provides the altsyncram simulation model used by akiko_nvram.
vlog -quiet C:/intelFPGA_lite/17.0/quartus/eda/sim_lib/altera_mf.v
vlog -sv -quiet ../../akiko_nvram.v
vlog -sv -quiet tb_akiko_nvram.sv

vsim -c -voptargs=+acc work.tb_akiko_nvram
run -all

set num_errs [examine -value /tb_akiko_nvram/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
