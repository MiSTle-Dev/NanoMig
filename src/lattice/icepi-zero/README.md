# NanoMig for Lattice ECP5 on ICEPi-Zero

This is a port of NanoMig to the [Lattice ECP5 FPGA family](https://www.latticesemi.com/en/Products/FPGAandCPLD/ECP5) and especially to the [LFE5U-25F](https://www.latticestore.com/products/tabid/417/categoryid/9/productid/122785/searchid/1/default.aspx?searchvalue=lfe5u*-25f-*bg256) on the [Icepi-Zero](https://github.com/cheyao/icepi-zero).

![IcePi-Zero and RP-Pico Breadboard Setup](icepizero_rpico.jpg)

It also runs on the [IcePi Carrier](https://github.com/MiSTle-Dev/Boards/tree/main/icepi_carrier).

## Current state

  - NanoMig working
  - ~~IDE temporarily disabled due to excessive logic usage~~ fixed
  - Joysticks and Companion through GPIO
  - ~~Temporary work-around for [flash clock issues](tests)~~ fixed
  - ~~HDMI signal are driven by logic. Should finally use DDR HW serializers or the like~~ fixed
  - ~~Uses OSD menu config from Gowin setup. Needs a custom config~~ fixed

## Setup

Joystick 0 and 1 are mapped to the GPIO as well as the Companion interface. Below
is the mapping of the companion interface.

![Wiring](wiring.png)

This can e.g. connected to the [RP2040 variant](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/src/rp2040) as seen in the photo of the breadboard setup above. For reliability, the SCK connection should not be wired directly but via a 220 ohms series resistor.

## Flashing

The core can be flashed using openFPGAloader using the following command:

```
openFPGALoader -cft231X --pins=7:3:5:6 -f impl/nanomig_impl.bit
```

Kickstart 1.3 needs to be flashed two times as the Amiga expects it to be mirrored in the 512k
kickstart address space:

```
openFPGALoader -cft231X --pins=7:3:5:6 --external-flash -o 0x400000 kick13.rom
openFPGALoader -cft231X --pins=7:3:5:6 --external-flash -o 0x440000 kick13.rom   
```

The NanoMig should boot to the kickstart splash screen even without anything connected to the
GPIO pins. The RP2040/FPGA Companion is needed to setup the on-screen-display and to
select a floppy disk image to boot from.
