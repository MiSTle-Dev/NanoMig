# tb_akiko_regs Questa runner (M1 regression).
# Run with: vsim -c -do run.do
# Sets exit code 0 on PASS, 1 on FAIL (read from bench `errs` variable).
# (M2 bench tb_akiko_txrx_dma has its own run script: run_txrx.do.)

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# -sv on all files: legacy akiko.v and the new file both use SV-style array
# sizing (`reg [..] x[N]`) and unnamed blocks with decls. Quartus tolerates
# this in plain Verilog mode but ModelSim ASE 10.5b requires -sv.
# altera_mf.v needed because akiko_nvram.v instantiates altsyncram.
# NOTE 2026-05-07: tb_akiko_regs.sv references obsolete `hps_nvr_din`/
# `hps_nvr_we` ports that were renamed during Phase 32/33 NVRAM rework.
# Bench needs to be updated to current akiko.v port list before this passes.
vlog -quiet C:/intelFPGA_lite/17.0/quartus/eda/sim_lib/altera_mf.v
vlog -sv -quiet akiko_legacy_ref.v
vlog -sv -quiet ../../akiko_nvram.v
vlog -sv -quiet ../../akiko.v
vlog -sv -quiet tb_akiko_regs.sv

vsim -c -voptargs=+acc work.tb_akiko_regs
run -all

set num_errs [examine -value /tb_akiko_regs/errs]
if {$num_errs != 0} {
    puts "RUN: FAIL ($num_errs errors)"
    quit -code 1
} else {
    puts "RUN: PASS"
    quit -code 0
}
