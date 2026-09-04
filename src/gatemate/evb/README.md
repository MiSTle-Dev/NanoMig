# NanoMig on CologneChip Gatemate

This is the begin of a port of NanoMig to the CologneChip gatemate CCGM1A1.
This is currently done on a Colognechip EVB with a HDMI-PMOD in PMODA.

## Current state

  - Complete minimal setup is synthesizable into 58% CPE's on CCGM1A1
     - Frequent unsuccesful routing can be solved be changing the seed like e.g. ```make SEED=2```
  - Most IO is wired to random unused pin locations
     - SDRAM is wired to banks EA and SA
     - Flash memory is wired to bank WC
     - SD card is wired to bank WC
  - HDMI/video is wired to PMODA
     - Working rarely and intermittent from build to build
     - top two red bits are currently tied high to give a red image in PAL 720x576@50Hz or NTSC 720x580@60Hz mode depending on the state of the amiga video circuit
     - Works (more) reliable when the main system is being removed
        - Enable ```define NO_SYS``` in [Makefile](Makefile) to remove everything but the video circuitry itself
  - Companion (rp2040) is wired PMODB
     - Can e.g. be used with the [Pi-Zero PMOD](https://github.com/MiSTle-Dev/Boards/tree/main/pizero_pmod)
     - Seems to work but is not yet needed at this stage
  - LEDs     
     - LED 1 is tied to the Amiga power led and changes between dim and bright
        - Dim by default, Amiga can switch to bright
     - LED 8 is tied to the 28 Mhz clock
        - Flashing once a second indicating HDMI clock and clock divider are working
     - LED 7 is tied to the main CPU reset circuit
        - Turning off shortly after startup inidcates that the CPU is taken out of reset
     - Other LEDs are tied to internal signals which are unimportant at this stage
  - Flash and SDRAM are not available (yet)
     - Internal 2k ROM is activated for tests without working external memory
     - Default test [pwr_led_blink](../../test_roms/pwr_led_blink.s) is placed in internal ROM
  - What should be working at this stage but isn't
    - CPU should boot and blink with the Amiga led
    - HDMI should display a stable 720x576@50hz PAL or 720x480@60hz NTSC image

## Next steps

  - Get signs of life from CPU
  - Get stable DVI/HDMI
  - Use Hyperram as SDRAM replacement
  - Read kickstart ROM from flash memory
  - Amiga ROM should boot into splash screen at this point
