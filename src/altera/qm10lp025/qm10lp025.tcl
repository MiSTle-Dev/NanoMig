set_global_assignment -name FAMILY "Cyclone 10 LP"
set_global_assignment -name DEVICE 10CL025YU256I7G

#============================================================
# CLOCK
#============================================================
set_location_assignment PIN_E2 -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50

#============================================================
# SDRAM
#============================================================
set_location_assignment PIN_R7 -to SDRAM_A[0]
set_location_assignment PIN_T7 -to SDRAM_A[1]
set_location_assignment PIN_T10 -to SDRAM_A[2]
set_location_assignment PIN_R10 -to SDRAM_A[3]
set_location_assignment PIN_R6 -to SDRAM_A[4]
set_location_assignment PIN_T5 -to SDRAM_A[5]
set_location_assignment PIN_R5 -to SDRAM_A[6]
set_location_assignment PIN_T4 -to SDRAM_A[7]
set_location_assignment PIN_R4 -to SDRAM_A[8]
set_location_assignment PIN_T3 -to SDRAM_A[9]
set_location_assignment PIN_T6 -to SDRAM_A[10]
set_location_assignment PIN_R3 -to SDRAM_A[11]
set_location_assignment PIN_T2 -to SDRAM_A[12]
set_location_assignment PIN_K5 -to SDRAM_DQ[0]
set_location_assignment PIN_L3 -to SDRAM_DQ[1]
set_location_assignment PIN_L4 -to SDRAM_DQ[2]
set_location_assignment PIN_L7 -to SDRAM_DQ[3]
set_location_assignment PIN_N3 -to SDRAM_DQ[4]
set_location_assignment PIN_M6 -to SDRAM_DQ[5]
set_location_assignment PIN_P3 -to SDRAM_DQ[6]
set_location_assignment PIN_N5 -to SDRAM_DQ[7]
set_location_assignment PIN_N2 -to SDRAM_DQ[8]
set_location_assignment PIN_N1 -to SDRAM_DQ[9]
set_location_assignment PIN_L1 -to SDRAM_DQ[10]
set_location_assignment PIN_L2 -to SDRAM_DQ[11]
set_location_assignment PIN_K1 -to SDRAM_DQ[12]
set_location_assignment PIN_K2 -to SDRAM_DQ[13]
set_location_assignment PIN_J1 -to SDRAM_DQ[14]
set_location_assignment PIN_J2 -to SDRAM_DQ[15]
set_location_assignment PIN_N8 -to SDRAM_BA[0]
set_location_assignment PIN_L8 -to SDRAM_BA[1]
set_location_assignment PIN_P1 -to SDRAM_DQMH
set_location_assignment PIN_N6 -to SDRAM_DQML
set_location_assignment PIN_M8 -to SDRAM_nRAS
set_location_assignment PIN_M7 -to SDRAM_nCAS
set_location_assignment PIN_P6 -to SDRAM_nWE
set_location_assignment PIN_P8 -to SDRAM_nCS
set_location_assignment PIN_R1 -to SDRAM_CKE
set_location_assignment PIN_P2 -to SDRAM_CLK

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_*
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to SDRAM_*
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[*]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[*]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_BA[*]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQM*
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_nRAS
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_nCAS
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_nWE
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_nCS
set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to SDRAM_DQ[*]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[*]

#============================================================
# LED / KEY
#============================================================
set_location_assignment PIN_F3 -to KEY1
set_location_assignment PIN_N9 -to LED
#set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to RESET_N
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY1

#set_location_assignment PIN_J14 -to M0S[0]
#set_location_assignment PIN_L14 -to M0S[1]
#set_location_assignment PIN_F16 -to M0S[2]
#set_location_assignment PIN_K15 -to M0S[3]
#set_location_assignment PIN_G15 -to M0S[4]

set_location_assignment PIN_R11 -to M0S0
set_location_assignment PIN_T11 -to M0S1
set_location_assignment PIN_R12 -to M0S2
set_location_assignment PIN_T12 -to M0S3
#set_location_assignment PIN_A8 -to M0S3
set_location_assignment PIN_M10 -to M0S4

set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to M0S0
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to M0S1
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to M0S2
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to M0S3
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to M0S4

#============================================================
# SD-CARD
#============================================================
#set_location_assignment PIN_R14 -to SD_CLK
#set_location_assignment PIN_T13 -to SD_CMD
#set_location_assignment PIN_T14 -to SD_DAT[0]
#set_location_assignment PIN_T15 -to SD_DAT[1]
#set_location_assignment PIN_T12 -to SD_DAT[2]
#set_location_assignment PIN_R13 -to SD_DAT[3]
set_location_assignment PIN_F13 -to SD_CLK
set_location_assignment PIN_F14 -to SD_CMD
set_location_assignment PIN_G15 -to SD_DAT[0]
set_location_assignment PIN_G16 -to SD_DAT[1]
set_location_assignment PIN_F15 -to SD_DAT[2]
set_location_assignment PIN_F16 -to SD_DAT[3]

set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SD_CLK
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SD_CMD
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SD_DAT[*]

#============================================================
# TMDS HDMI
#============================================================
set_location_assignment PIN_N15 -to TMDS[0]
set_location_assignment PIN_N16 -to "TMDS[0](n)"
set_location_assignment PIN_L15 -to TMDS[1]
set_location_assignment PIN_L16 -to "TMDS[1](n)"
set_location_assignment PIN_K15 -to TMDS[2]
set_location_assignment PIN_K16 -to "TMDS[2](n)"
set_location_assignment PIN_R16 -to TMDS[3]
set_location_assignment PIN_P16 -to "TMDS[3](n)"
set_instance_assignment -name IO_STANDARD LVDS -to TMDS[0]
set_instance_assignment -name IO_STANDARD LVDS -to TMDS[1]
set_instance_assignment -name IO_STANDARD LVDS -to TMDS[2]
set_instance_assignment -name IO_STANDARD LVDS -to TMDS[3]

#============================================================
# LVDS LCD
#============================================================
#set_location_assignment PIN_A3 -to LCD[0]
#set_location_assignment PIN_A2 -to "LCD[0](n)"
#set_location_assignment PIN_B4 -to LCD[1]
#set_location_assignment PIN_A4 -to "LCD[1](n)"
#set_location_assignment PIN_B5 -to LCD[2]
#set_location_assignment PIN_A5 -to "LCD[2](n)"
#set_location_assignment PIN_B6 -to LCD[3]
#set_location_assignment PIN_A6 -to "LCD[3](n)"
#set_location_assignment PIN_B7 -to LCD[4]
#set_location_assignment PIN_A7 -to "LCD[4](n)"

#set_location_assignment PIN_R10 -to LCD[0]
#set_location_assignment PIN_T10 -to "LCD[0](n)"
#set_location_assignment PIN_R11 -to LCD[1]
#set_location_assignment PIN_T11 -to "LCD[1](n)"
#set_location_assignment PIN_R12 -to LCD[2]
#set_location_assignment PIN_T12 -to "LCD[2](n)"
#set_location_assignment PIN_R13 -to LCD[3]
#set_location_assignment PIN_T13 -to "LCD[3](n)"
#set_location_assignment PIN_T14 -to LCD[4]
#set_location_assignment PIN_T15 -to "LCD[4](n)"

set_instance_assignment -name IO_STANDARD LVDS -to LCD[0]
set_instance_assignment -name IO_STANDARD LVDS -to LCD[1]
set_instance_assignment -name IO_STANDARD LVDS -to LCD[2]
set_instance_assignment -name IO_STANDARD LVDS -to LCD[3]
set_instance_assignment -name IO_STANDARD LVDS -to LCD[4]

### BANK5
set_location_assignment PIN_J13 -to BANK5_J13
set_location_assignment PIN_J14 -to BANK5_J14
set_location_assignment PIN_J15 -to BANK5_J15
set_location_assignment PIN_J16 -to BANK5_J16
set_location_assignment PIN_L13 -to BANK5_L13
set_location_assignment PIN_L14 -to BANK5_L14
set_location_assignment PIN_N14 -to BANK5_N14
set_location_assignment PIN_P15 -to BANK5_P15

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to MSPI_DI
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to MSPI_CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to MSPI_DO
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to MSPI_CS
set_location_assignment PIN_H1 -to MSPI_CLK
set_location_assignment PIN_D2 -to MSPI_CS
set_location_assignment PIN_C1 -to MSPI_DI
set_location_assignment PIN_H2 -to MSPI_DO
#set_location_assignment PIN_H1 -to epcs_dclk
#set_location_assignment PIN_D2 -to epcs_sce
#set_location_assignment PIN_C1 -to epcs_sdo
#set_location_assignment PIN_H2 -to epcs_data0
