# NanoMig simulation

The fact that the entire Minimig and the fx68k CPU core are written in
verilog allows them to be run in a verilator simulation on a Linux PC.

Currently implemented in this testbench are:

 - Run the complete Minimig and fx68k core on a real kickstart
 - Video output via SDL
 - Floppy disk read emulation
 - IDE HDD emulation incl. write support (tested with kick 3.1)
 - SD card emulation
 - UART emulation (for e.g. diagnostic output of DiagROM)
 - Includes a skeleton for a [custom test rom](test_rom)

Some of these features can be enabled and disabled in the ```Makefile```
and in ```nanomig.cpp``` itself. Not all options are always tested and
some changes in the HDL core may be broken some tests. By default
the simulation is configured for video emulation in endless
operation. This means that running the simulation will not output
any wave data but will instead just run with emulated video. Using
a kickstart 1.3 ROM this will e.g. display the disk/hand screen after
having simulated 187 frames.

![NanoMig simulation](nanomig_sim.png)

The [original fx68k core](https://github.com/ijor/fx68k) does not
work in verilator. This simulation thus includes a [variant
that runs on verilator](https://github.com/emoon/fx68x_verilator).

## Building and running

The simulation has only been tested on Linux.

It has been tested with Verilator 5.026 built from the [github master
branch](https://github.com/verilator/verilator). Earlier versions,
especially the ones that come with some Linux distros are likely too
old. Newer versions will probably work. You'll need to adjust the
[Makefile](Makefile#L27) to point to your installed verilator setup.

For video simulation ```libsdl2``` is needed.

### Additional files needed

At least a kickstart (e.g. 1.3) ROM named ```kick13.rom``` is needed
to run the simulation, HDD emulation has only been tested with
kickstart 3.1.  Other ROMs like
[DiagROM](https://github.com/ChuckyGang/DiagROM) may also work
although the video simulation is far from being complete and e.g. the
video output of DiagROM is broken. However, UART output can be enabled
allowing to see the initial diagnostic output of DiagROM.

Further simulation features like e.g. floppy simulation may
need additional files like e.g. ADF disk images. See the
[```nanomig_tb.cpp```](nanomig_tb.cpp) for details.

With all dependencies in place a simple ```make run``` should build
the simulator and run it.

### Verilator version notes

Starting with Verilator 5.038 the default behavior for handling ```unique```
statements changed: [verilator/verilator-announce#77](https://github.com/verilator/verilator-announce/issues/77).  
Earlier versions did run without these assertions per default. 

This will lead to the error when running the simulation:
```
[0] %Error: fx68kAlu.sv:313: Assertion failed in TOP.nanomig_tb.nanomig.cpu_wrapper.cpu_inst_o.excUnit.alu: unique case, but none matched for '32'h00000000'
%Error: fx68x_verilator/fx68kAlu.sv:313: Verilog $stop
```

Workarounds are to use Verilator up to 5.036 or to add the parameter:
`--no-assert` to the commandline of Verilator in the Makefile
```
verilator --no-assert -O3 -Wno-fatal --no-timing --trace --threads 1 --trace-underscore  -top-module \$(PRJ)\_tb \$(VERILATOR\_FLAGS) -cc \${HDL\_FILES} --exe \${CPP\_FILES} -o ../\$(PRJ) -CFLAGS "\${EXTRA\_CFLAGS}" -LDFLAGS "\${EXTRA\_LDFLAGS}"
```

## Running traces

Tracing can be enabled in [```nanomig_tb.cpp```](nanomig_tb.cpp#L49) by
setting the following lines like e.g.:

```
#define TRACESTART   0.4
#define TRACEEND     (TRACESTART + 0.2)   // 0.1s ~ 1G
```

This will start writing out a trace file after 0.4 seconds of simulated run
time and it will write a trace for 0.2 seconds of runtime. The traces
will be ~1 GBytes per 100ms simulated runtime.

The resulting VCD trace can e.g. be loaded into
[gtkwave](https://gtkwave.sourceforge.net/) for further inspection.

![NanoMig trace in gtkwave](nanomig_wave.png)

## Floppy disk simulation

The floppy disk can be simulated including the SD card itself or by
omitting the SD card. By default the SD card itself is not simulated
and the simulation environment sends data into the Minimig floppy
implementation directly. This should be sufficient for most tests.

Floppy simulation is now by default enabled and expects a file named
```df0.adf``` to be present. This will then be inserted as DF0. If
no such file is present, then the simulation behaves as if no disk
is inserted in the amiga kick displays the disk/hand logo after
around 3 seconds simulation time.

When booting kickstart 1.3, the floppy will first be accessed at
around 3 seconds simulation time with some debug output about disk IO
on the console.

## Screenshots

With video emulation enabled all frames are written to the
[screenshots](screenshots) directory in PNG format.
