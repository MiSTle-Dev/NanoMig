# NanoMig build system

NanoMig started as the attempt to make MiniMig a little less platform
dependent as it was on the MiST and MiSTer. But although it was
running on various mainly Gowin based devices from the Tang Nano 20k
to the Tang Mega 138k, the different implementations slightly diverged
and features implemented for one device would not arrive at the oher
one or even break them. A slightly updated build system tries to
address this.

The new build system is currently being used for Gowin based devices
only. It might be extended to work for other vendors as well. Even
worse, the new build system may have broken builds for other
platforms.

## The basics

At the core of the build system is the scripts/build.tcl script. This
is a TCL script because historcally most HDL tool chains come with a
TCL interpreter and the Gowin EDA is no exception.

This build script can be invoked from the command line like so:

```
gw_sh scripts/build.tcl nano20k aga
```

It will then build an AGA enabled NanoMig core for the Tang Nano 20k.

Invoking the script without parameters will give some info on the
available configurations:

```
gw_sh scripts/build.tcl
*** GOWIN Tcl Command Line Console  *** 
Usage: scripts/build.tcl <device> <optons...>
       device: nano20k, tp25k, gw5a_25, gw3a_20, mega138kpro, console60k, console138k
       options:
               nano20k: aga, lcd   - build aga+020 and/or rgblcd variant
               tp25k:   aga, dbg   - build aga and or debug variant
               all:     nosyn      - generate files only, don't run synthesis
```

In this process various files are being generated which can also be
used to build the cores throught the graphical IDE. The necessary
Gowin IDE project files are being generated in ```gowin_prj```. Only
the most common variants are distributed through github. Build files
for other variants like e.g. the GW3A_20 dev board can be generated
from the command line as needed.

## Details

All information about the different board variants and how they are
being built is stored inside the script/build.tcl script. When being
invoked it will generate a set of files that are needed for the build
itself. In case of e.g. the AGA variant for the Tang Nano 20k, these
files are:

```tang/nano20k/config_tang_nano20k_aga.vh``` holds all the variant
specific ```defines``` which in turn enable and disable all the
NanoMig features like AGA support and the CPU to be used

```tang/nano20k/nanomig_tang_nano20k_aga.cst``` contains information
about the pin usage. This is being assembled from individual CST files
since the Gowin tool chain copes with one single CST file only.

```tang/nano20k/nanomig_tang_nano20k_aga.sdc``` is the file containing
the timing constraints for this particular variant. Like the CST there
can only be one SDC and the script assembles this file from various
source file depending on the requirements of the variant.

```gowin_prj/nanomig_tang_nano20k_aga.gprj```,
```gowin_prj/impl/nanomig_tang_nano20k_aga_process_config.json``` and
```scripts/update_xml_tang_nano20k_aga.tcl```
are the project
files for the Gowin IDE. These files are not used during command line
build. But they are automatically re-generated to make sure the
configuration for the IDE build matches the one for the command line.

```misc/amiga_xml.hex``` is the file holding the converted and
compressed menu information.  It is generated from the
```misc/amiga.xml``` file. This is the only file that is being
re-generated during IDE builds as well.

