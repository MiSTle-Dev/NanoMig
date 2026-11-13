# 31 kHz pass-through (DblPAL and other productivity modes) on HDMI

Tang Primer 25K, AGA build only (`tp25k aga`, define `VID31_PASSTHROUGH`).

## What it does

The Amiga scandoubler turns the 15 kHz video of the Amiga into 31 kHz for the
HDMI output. If Workbench is switched to a 31 kHz screen mode (for example
DblPAL), the Amiga already produces 31 kHz and doubling it again gives no
usable picture.

With `VID31_PASSTHROUGH` the core measures the raw line length of the Amiga
video. A line shorter than 1400 clocks (28.37 MHz) is a 31 kHz mode and the
video bypasses the scandoubler. The HDMI frame then follows the picture the
Amiga makes, and the picture is placed from the Amiga's own blanking signals.
15 kHz modes (PAL, NTSC, interlace) work as before.

## Using it

Pick a 31 kHz screen mode for Workbench (Prefs / ScreenMode, for example
DblPAL). The monitor or TV has to accept the resulting HDMI timing.

Measured on the Primer 25K with DblPAL: 1040 clocks x 575 lines, 27.28 kHz
line frequency, 47.5 Hz frame rate.

## Files

* `src/misc/video_timing.v` measures the raw line length (`fast`) and the
  picture geometry from the blanking.
* `src/misc/video_analyzer.v` passes the measured values on to the HDMI part.
* `src/nanomig.v` bypasses the scandoubler when `fast` is set.
* `src/minimig-aga/minimig.v` exports the horizontal display window.
* `src/hdmi/hdmi.sv` sets frame size and picture position from the measured
  values.
* `src/tang/primer25k/top.sv` wiring.

## Cost

About 750 logic cells. The Primer 25K AGA build is at 22250 of 23040 (97 %).
To make room, `cpu_config` is a constant 68020 for the AGA build: the AGA
menu has no CPU entry (`amiga.xml`) and `sysctrl.v` starts at 68020, so the
68000 path was dead logic (238 cells).

## Tested

Tang Primer 25K, Gowin 1.9.11.03: PAL 15 kHz, NTSC 15 kHz, DblPAL 31 kHz.
