# NanoMig on CologneChip Gatemate

This is the begin of a port of NanoMig to the CologneChip gatemate CCGM1A1.
This is currently done on a Colognechip EVB with a HDMI-PMOD in PMODA.

## Current state

  - Complete minimal setup is synthesizable into 58% CPE's on CCGM1A1
  - Most IO is wired to random unused pin locations
     - SDRAM is wired to banks EA and EB
     - Flash memory is wired to bank WC
     - SD card is wired to bank WC
     - Companion (rp2040) is wired to bank WC
  - HDMI/video is wired to PMODA
     - Working intermittent from build to build
     - top red bits are tied high to give a red image in PAL 720x576@50Hz mode
  - LED 1 is tied to the Amiga power led and changes between dim and bright
     - Dim by default, Amiga can switch to bright
  - Flash and SDRAM are not available (yet)
     - Internal 2k ROM is activated for tests without working external memory
     - Default test [pwr_led_blink](../../test_roms/pwr_led_blink.s) is loaded
     - CPU should boot and blink with the Amiga led but this does not work

## Next steps

  - Get signs of life from CPU
  - Get stable DVI/HDMI
  - Use Hyperram as SDRAM replacement
  - Read kickstart ROM from flash memory
  - Amiga ROM should boot into splash screen at this point
