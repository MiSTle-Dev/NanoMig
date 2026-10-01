set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE22F17I7

#============================================================
# CLOCK
#============================================================
set_location_assignment PIN_E15 -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50

#============================================================
# SDRAM
#============================================================
set_location_assignment PIN_D5 -to SDRAM_A[0]
set_location_assignment PIN_C3 -to SDRAM_A[1]
set_location_assignment PIN_D3 -to SDRAM_A[2]
set_location_assignment PIN_A2 -to SDRAM_A[3]
set_location_assignment PIN_B3 -to SDRAM_A[4]
set_location_assignment PIN_A3 -to SDRAM_A[5]
set_location_assignment PIN_B4 -to SDRAM_A[6]
set_location_assignment PIN_A4 -to SDRAM_A[7]
set_location_assignment PIN_B5 -to SDRAM_A[8]
set_location_assignment PIN_A5 -to SDRAM_A[9]
set_location_assignment PIN_E6 -to SDRAM_A[10]
set_location_assignment PIN_B6 -to SDRAM_A[11]
set_location_assignment PIN_A6 -to SDRAM_A[12]
set_location_assignment PIN_D14 -to SDRAM_DQ[0]
set_location_assignment PIN_C14 -to SDRAM_DQ[1]
set_location_assignment PIN_D12 -to SDRAM_DQ[2]
set_location_assignment PIN_B13 -to SDRAM_DQ[3]
set_location_assignment PIN_E10 -to SDRAM_DQ[4]
set_location_assignment PIN_B12 -to SDRAM_DQ[5]
set_location_assignment PIN_D11 -to SDRAM_DQ[6]
set_location_assignment PIN_C11 -to SDRAM_DQ[7]
set_location_assignment PIN_B10 -to SDRAM_DQ[8]
set_location_assignment PIN_A11 -to SDRAM_DQ[9]
set_location_assignment PIN_B11 -to SDRAM_DQ[10]
set_location_assignment PIN_A12 -to SDRAM_DQ[11]
set_location_assignment PIN_A13 -to SDRAM_DQ[12]
set_location_assignment PIN_A14 -to SDRAM_DQ[13]
set_location_assignment PIN_B14 -to SDRAM_DQ[14]
set_location_assignment PIN_A15 -to SDRAM_DQ[15]
set_location_assignment PIN_C6 -to SDRAM_BA[0]
set_location_assignment PIN_D6 -to SDRAM_BA[1]
set_location_assignment PIN_A10 -to SDRAM_DQMH
set_location_assignment PIN_E9 -to SDRAM_DQML
set_location_assignment PIN_C8 -to SDRAM_nRAS
set_location_assignment PIN_D8 -to SDRAM_nCAS
set_location_assignment PIN_E8 -to SDRAM_nWE
set_location_assignment PIN_E7 -to SDRAM_nCS
set_location_assignment PIN_B7 -to SDRAM_CKE
set_location_assignment PIN_A7 -to SDRAM_CLK

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDRAM_*
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to SDRAM_*
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[0]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[1]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[2]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[3]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[4]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[5]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[6]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[7]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[8]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[9]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[10]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[11]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[12]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[13]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[14]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQ[15]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[0]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[1]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[2]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[3]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[4]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[5]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[6]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[7]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[8]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[9]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[10]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[11]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_A[12]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_BA[0]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_BA[1]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQMH
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_DQML
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_nRAS
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_nCAS
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_nWE
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to SDRAM_nCS
set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to SDRAM_DQ[*]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[0]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[1]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[2]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[3]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[4]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[5]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[6]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[7]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[8]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[9]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[10]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[11]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[12]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[13]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[14]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to SDRAM_DQ[15]

#============================================================
# VGA
#============================================================
#set_location_assignment PIN_NONE -to VGA_B[4]
#set_location_assignment PIN_NONE -to VGA_B[3]
#set_location_assignment PIN_NONE -to VGA_B[2]
#set_location_assignment PIN_NONE -to VGA_B[1]
#set_location_assignment PIN_NONE -to VGA_B[0]
#set_location_assignment PIN_NONE -to VGA_G[5]
#set_location_assignment PIN_NONE -to VGA_G[4]
#set_location_assignment PIN_NONE -to VGA_G[3]
#set_location_assignment PIN_NONE -to VGA_G[2]
#set_location_assignment PIN_NONE -to VGA_G[1]
#set_location_assignment PIN_NONE -to VGA_G[0]
#set_location_assignment PIN_NONE -to VGA_R[4]
#set_location_assignment PIN_NONE -to VGA_R[3]
#set_location_assignment PIN_NONE -to VGA_R[2]
#set_location_assignment PIN_NONE -to VGA_R[1]
#set_location_assignment PIN_NONE -to VGA_R[0]
#set_location_assignment PIN_NONE -to VGA_HS
#set_location_assignment PIN_NONE -to VGA_VS
#set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_R[*]
#set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_G[*]
#set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_B[*]
#set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_HS
#set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_VS
#set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to VGA_R[*]
#set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to VGA_G[*]
#set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to VGA_B[*]
#set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_HS
#set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_VS

#============================================================
# LED / KEY
#============================================================

set_location_assignment PIN_E1 -to KEY1
set_location_assignment PIN_B8 -to KEY2
set_location_assignment PIN_A8 -to KEY3
#set_location_assignment PIN_L3 -to LED
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY1
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY2
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED

#============================================================
# UART
#============================================================
#set_location_assignment PIN_NONE -to UART_RX
#set_location_assignment PIN_NONE -to UART_TX

#============================================================
# SD-CARD
#============================================================
set_location_assignment PIN_T11 -to SD_CLK
set_location_assignment PIN_R12 -to SD_CMD
set_location_assignment PIN_T12 -to SD_DAT[0]
set_location_assignment PIN_R13 -to SD_DAT[1]
set_location_assignment PIN_T10 -to SD_DAT[2]
set_location_assignment PIN_R11 -to SD_DAT[3]
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SD_CLK
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SD_CMD
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SD_DAT[*]

#============================================================
# TMDS HDMI
#============================================================
set_location_assignment PIN_L2 -to TMDS[0]
set_location_assignment PIN_L1 -to "TMDS[0](n)"
set_location_assignment PIN_N2 -to TMDS[1]
set_location_assignment PIN_N1 -to "TMDS[1](n)"
set_location_assignment PIN_P2 -to TMDS[2]
set_location_assignment PIN_P1 -to "TMDS[2](n)"
set_location_assignment PIN_K2 -to TMDS[3]
set_location_assignment PIN_K1 -to "TMDS[3](n)"
set_instance_assignment -name IO_STANDARD LVDS -to TMDS[0]
set_instance_assignment -name IO_STANDARD LVDS -to TMDS[1]
set_instance_assignment -name IO_STANDARD LVDS -to TMDS[2]
set_instance_assignment -name IO_STANDARD LVDS -to TMDS[3]

#============================================================
# M0S
#============================================================
set_location_assignment PIN_R16 -to SPI_IO_DOUT
set_location_assignment PIN_P15 -to SPI_IO_DIN
set_location_assignment PIN_P16 -to SPI_IO_SS
set_location_assignment PIN_N15 -to SPI_IO_CLK
set_location_assignment PIN_N16 -to SPI_INTN
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SPI_IO_DOUT
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SPI_IO_DIN
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SPI_IO_SS
#set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SPI_IO_CLK
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SPI_INTN

#============================================================
# SPI FLASH EPCS
#============================================================
set_location_assignment PIN_H1 -to MSPI_CLK
set_location_assignment PIN_H2 -to MSPI_DO
set_location_assignment PIN_C1 -to MSPI_DI
set_location_assignment PIN_D2 -to MSPI_CS
