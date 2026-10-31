#requires -Version 5.0
$ErrorActionPreference = "Stop"

# ModelSim Intel FPGA Starter Edition (bundled with Quartus 17.0) is truly license-free.
# Questa FE/FSE require a Siemens-issued license file even for free use.
$candidates = @(
    "C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem\vsim.exe",
    "C:\altera_standard\25.1std\questa_fe\win64\vsim.exe"
)
$vsim = $null
foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { $vsim = $c; break }
}
if (-not $vsim) {
    Write-Error "No license-free vsim found. Tried: $($candidates -join ', ')"
    exit 2
}
Write-Host "Using vsim: $vsim" -ForegroundColor Cyan

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $here
try {
    # M1 regression
    & $vsim -c -do "do run.do"
    $rc1 = $LASTEXITCODE
    if ($rc1 -eq 0) {
        Write-Host "tb_akiko_regs PASSED" -ForegroundColor Green
    } else {
        Write-Host "tb_akiko_regs FAILED (vsim exit $rc1)" -ForegroundColor Red
    }

    # M2 bench
    & $vsim -c -do "do run_txrx.do"
    $rc2 = $LASTEXITCODE
    if ($rc2 -eq 0) {
        Write-Host "tb_akiko_txrx_dma PASSED" -ForegroundColor Green
    } else {
        Write-Host "tb_akiko_txrx_dma FAILED (vsim exit $rc2)" -ForegroundColor Red
    }

    # M3 bench
    & $vsim -c -do "do run_bridge.do"
    $rc3 = $LASTEXITCODE
    if ($rc3 -eq 0) {
        Write-Host "tb_akiko_hps_bridge PASSED" -ForegroundColor Green
    } else {
        Write-Host "tb_akiko_hps_bridge FAILED (vsim exit $rc3)" -ForegroundColor Red
    }

    # M4 bench
    & $vsim -c -do "do run_pbx.do"
    $rc4 = $LASTEXITCODE
    if ($rc4 -eq 0) {
        Write-Host "tb_akiko_pbx_dma PASSED" -ForegroundColor Green
    } else {
        Write-Host "tb_akiko_pbx_dma FAILED (vsim exit $rc4)" -ForegroundColor Red
    }

    # M5 bench (chip-RAM master arbiter)
    & $vsim -c -do "do run_chipram.do"
    $rc5 = $LASTEXITCODE
    if ($rc5 -eq 0) {
        Write-Host "tb_akiko_chipram_master PASSED" -ForegroundColor Green
    } else {
        Write-Host "tb_akiko_chipram_master FAILED (vsim exit $rc5)" -ForegroundColor Red
    }

    # Phase 13 bench (NVRAM I2C slave EEPROM)
    & $vsim -c -do "do run_nvram.do"
    $rc6 = $LASTEXITCODE
    if ($rc6 -eq 0) {
        Write-Host "tb_akiko_nvram PASSED" -ForegroundColor Green
    } else {
        Write-Host "tb_akiko_nvram FAILED (vsim exit $rc6)" -ForegroundColor Red
    }

    # M6.2 bench (CDDA FIFO + 44.1 kHz pump)
    & $vsim -c -do "do run_cdda.do"
    $rc7 = $LASTEXITCODE
    if ($rc7 -eq 0) {
        Write-Host "tb_akiko_cdda PASSED" -ForegroundColor Green
    } else {
        Write-Host "tb_akiko_cdda FAILED (vsim exit $rc7)" -ForegroundColor Red
    }

    if ($rc1 -ne 0 -or $rc2 -ne 0 -or $rc3 -ne 0 -or $rc4 -ne 0 -or $rc5 -ne 0 -or $rc6 -ne 0 -or $rc7 -ne 0) { exit 1 }
    exit 0
} finally {
    Pop-Location
}
