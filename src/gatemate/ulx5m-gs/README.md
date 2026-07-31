# NanoMig on CologneChip Gatemate

This is a port of NanoMig to the CologneChip gatemate.

Without FPGA Companion connected and without kickstart in ROM, the
Amigas video circuitry should still start up and display a black image
at 720x576@50Hz scandoubled PAL timing.

## Kickstart

A kickstart has to be uploaded to address 0x400000 in the
on-board flash. A 256k kickstart needs to be flashed two
times:

```
openFPGALoader --index-chain 0 -f -o 0x400000 kick13.rom
openFPGALoader --index-chain 0 -f -o 0x440000 kick13.rom
```

or once if the kickstart ROM is 512k in size:

```
openFPGALoader --index-chain 0 -f -o 0x400000 kick31.rom
```

Once core and kickstart are in place, the Amiga should boot
to the kickstart splash screen.
