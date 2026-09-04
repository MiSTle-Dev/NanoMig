# NanoMig for Lattice ECP5 on iCESugar-pro

This is a port of NanoMig to the [Lattice ECP5 FPGA family](https://www.latticesemi.com/en/Products/FPGAandCPLD/ECP5) and especially to the [LFE5U-25F](https://www.latticestore.com/products/tabid/417/categoryid/9/productid/122785/searchid/1/default.aspx?searchvalue=lfe5u*-25f-*bg256) on the [iCESugar-pro](https://github.com/wuxx/icesugar-pro) and [Ext-Board](https://github.com/wuxx/Colorlight-FPGA-Projects#ext-board).

![iCESugar-pro, Ext-Board and M0S Dock Setup](icesugarpro_m0s.jpg)

## Current state

  - NanoMig working
  - IDE temporarily disabled due to excessive logic usage
  - Joysticks and Companion through GPIO
  - ~~Temporary work-around for [flash clock issues](tests)~~ fixed
  - HDMI signal are driven by logic. Should finally use DDR HW serializers or the like
  - Uses OSD menu config from Gowin setup. Needs a custom config

## Setup

Joystick 0 and 1 are mapped to the GPIO as well as the Companion interface. Below
is the mapping of the companion interface.

![Wiring](wiring.png)

This can e.g. connected to the [M0S Dock variant](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/src/bl616) as seen in the photo of the breadboard setup above. For reliability, the SCK connection should not be wired directly but via a 220 ohms series resistor.

## Flashing

The core can be flashed using [ecpdap](https://github.com/adamgreig/ecpdap) or openFPGAloader using the following command:

```
ecpdap.exe flash write impl/nanomig_impl.bit
```
or
```
openFPGALoader -cft231X --pins=7:3:5:6 -f impl/nanomig_impl.bit
```

Kickstart 1.3 needs to be flashed two times as the Amiga expects it to be mirrored in the 512k
kickstart address space:
```
ecpdap.exe flash write --offset 0x400000 kick13.bin
ecpdap.exe flash write --offset 0x440000 kick13.bin

```
or
```
openFPGALoader -cft231X --pins=7:3:5:6 --external-flash -o 0x400000 kick13.rom
openFPGALoader -cft231X --pins=7:3:5:6 --external-flash -o 0x440000 kick13.rom   
```

The NanoMig should boot to the kickstart splash screen even without anything connected to the
GPIO pins. The M0S/FPGA Companion is needed to setup the on-screen-display and to
select a floppy disk image to boot from.
