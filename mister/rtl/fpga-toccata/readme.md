# Introduction

This is a module emulating the playback functionality of the Toccata sound card for the Commodore Amiga. [Toccata sound card](https://amiga.resource.cx/exp/toccata)

The module is written in SystemVerilog, and is intended to be used in the Minimig core.

It was not possible for me to get an actual Toccata sound card, or find the documentation for the sound card.
This module is implemented by reverse engineering the Toccata sound card emulation of UAE, and looking at the OpenBSD driver.
The Toccata sound card uses the AD1848 audio chip, the [AD1848 data sheet](https://www.analog.com/media/en/technical-documentation/obsolete-data-sheets/ad1845.pdf) was used to implement the indirectly exposed registers to the zorro II bus.

## Implemented features

Because I needed 16-bit audio output, but have no use for audio input, input was not implemented in this module.

List of implemented features:

- Control of the playback features via the Zorre II status register.
- Status feedback via reading the Zorro II status register.
- Playback of 8-bit mono, 8-bit stereo, 16-bit mono, 16-bit stereo
- Audio volume via the AD1848 registers
- Muting of left and right audio channels via AD1848 registers
- 1kb sample buffer, with interrupt generation on half empty.
- Writing audio to the FIFO using the ZORRO II bus registers
- Configuring the playback sample rate using the AD1848 registers

Not implemented features:

- Playback of Companded Audio (Played back as normal 8-bit audio)
- Mixing in the Paula audio via the Toccata sound card
- Real audio callibration, callibration ready is faked. (Not needed for this module)
- Sound recording, the interrupts and data returned when recording are faked. (silence)

## Usage

This module needs to be hooked into the Minimig core, in the Zorro II memory space.
For this the autoconfig process needs to be configured, providing the Kickstart with the information it needs to assign a memory region (64kb wide).
In the Minimig core this means add an extra entry to handle the Toccata sound card.

The configuration I use for the Toccata auto configuration ROM is:

```verilog
// Toccata sound card

ram[sndbase+'h0] = 4'b1100; // Zorro-II card, no link, no ROM
ram[sndbase+'h2/2] = 4'b0001; // Next board not related, size 'h64k
// Inverted from here on
ram[sndbase+'h6/2] = 4'b0011; // Lower byte product number

ram[ethbase+'ha/2] = 4'b1101;   // logical size 64k

ram[sndbase+'h10/2] = 4'b1011; // Manufacturer ID: 0x4754
ram[sndbase+'h12/2] = 4'b1000;
ram[sndbase+'h14/2] = 4'b1010;
ram[sndbase+'h16/2] = 4'b1011;
```

When the Toccata sound card is the first Zorro II IO card it ends up on memory address $e90000, after autoconfiguration is completed.

For a full integration example take a look at the [OpenAARS Minimig](https://github.com/ranzbak/MinimigAGA_TC64/tree/v5.0/rtl/openaars/toccata) project.

## Memory map for the Toccata sound card

The card has a 64kb memory footprint, that start at the IO base address.
The Zorro II IO base address space starts at 0xE80000, to 0xEFFFFF.
More details [here](http://amigadev.elowar.com/read/ADCD_2.1/Hardware_Manual_guide/node0293.html)

The Toccata sound card has 4 address ranges that allow interaction with the card,
Since only bits 14, 13 and 11 are evaluated on the address bus, the ranges are bigger than documented here, generally the driver libraries use the address as listed below.
| Address space start | bits 14 | bits 13 | bits 11 | high/low byte | function |
| --- | --- | --- | --- | --- | --- |
| 0x0000 | 0 | 0 | 0 | h + l | read: Control register, write: status register  |
| 0x2000 | 0 | 0 | 1 | l | Write to playback sample buffer / read from record buffer |
| 0x6000 | 1 | 1 | 0 | l | Set the index for the indirect AD1848 registers |
| 0x6800 | 1 | 1 | 1| l | Read / Write to the indirect AD1848 registers pointed by index |

The Indirect AD1848 registers are documented in the AD1848 datasheet.

The Toccata control register bits 0x0000 (write):

| Bit number | Description |
| --- | --- |
| 0 | Set card Active (Only works when all other bits are set to '0') |
| 1 | When this bit is set the card is reset |
| 2 | Enable the FIFO, without this bit no sample data can be read or write|
| 3 | FIFO record, start sound capture |
| 4 | FIFO playback, start playback of sound from the sample buffer |
| 5 | Could not find in the UAE source code so ??? |
| 6 | Record int Enable, start generating interrupt when the FIFO is half full |
| 7 | Playback int Enable, start generating interrupt when the FIFO is half empty |

The Toccata status register bits 0x0000 (read):

| Bit number | Description |
| --- | --- |
| 2 | Recording FIFO is half full |
| 3 | Playback FIFO is half empty |
| 7 | (inverted) Interrupt pending |

The functions of the other bits I could not find, and are not needed for sound playback.

## Audio output format

The sample data is provided in unsigned 16-bit integer format, with a 0x8000 bias.
This is compatible with I2S audio data.

## Testing

Because this module is part of my Minimig project, I was able to test the module with :

- AHI sound drivers
- Eagle player 2.06 both AHI and Toccata amplifier.
- Hippo player via the AHI sound driver
- 'Octamed sound studio' using the Toccata sound 16bit ++ output.

The programs above played back audio correctly, although some weird behavior was observed when applying effects to the audio streams, not sure if this because of software errors or bugs in this module.

## Contributing

If there are things that are missing, should be improved or fixed, please create a pull request.

## License

BSD-2-Clause "Simplified" License

- Also if you like this project, and you run into me at some nerd event buy me a coffee / Club mate :-)
