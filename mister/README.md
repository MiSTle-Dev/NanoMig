# NanoMig MiSTer DE10-Nano - 32-Channel Audio Engine & Capture Pipeline

This directory contains the MiSTer DE10-Nano implementation files, pre-compiled RBF bitstreams, RTL sources, and verification test ROMs for the 32-channel Biquad Audio Pipeline with Dual-Buffer Capture.

---

## 📂 Directory Layout

* **`releases/`**: Pre-built bitstreams ready for MiSTer:
  * [`Minimig_HAM_32CH_Audio_Capture.rbf`](releases/Minimig_HAM_32CH_Audio_Capture.rbf) (4,127,424 Bytes) — Full Amiga AGA + 68020 + 32-Voice Biquad DSP + 2x 4 KB Capture BRAM ($DF8000).
  * [`Minimig_HAM_32CH.rbf`](releases/Minimig_HAM_32CH.rbf) (4,127,424 Bytes) — 32-Voice Audio core without capture window.
  * [`Minimig_HAM_16CH.rbf`](releases/Minimig_HAM_16CH.rbf) (4,127,424 Bytes) — 16-Voice baseline audio core.
* **`rtl/`**: Verilog / SystemVerilog hardware source files:
  * [`audio_shifter.v`](rtl/audio_shifter.v) — Core 32-channel time-multiplexed audio engine, Biquad DSP filters, AM/FM modulation, and Zero-RAM delay unit.
  * [`audio_capture_buffer.v`](rtl/audio_capture_buffer.v) — Double-buffering capture unit (2x 4 KB BRAM) with hardware overrun protection and register control.
  * [`minimig_m68k_bridge.v`](rtl/minimig_m68k_bridge.v) — Bus interface decoding `$DF8000..$DF9FFF` and `$DFF800..$DFF9FC`.
* **`tests/`**: Ready-to-run M68k assembly test programs:
  * [`audio_capture_test.s`](tests/audio_capture_test.s) — Validates double buffering, buffer swap handshake, and overrun protection.
  * [`audio_pipeline_test.s`](tests/audio_pipeline_test.s) — Validates 16/32 voice playback, Biquad filtering, AM modulation, and Level 2 interrupt autovector.

---

## 📐 Architecture Highlights

```mermaid
flowchart LR
    subgraph AMIGA_BUS["Amiga Host"]
        CPU["68020 CPU"]
        DMA["Audio DMA"]
        REGS["Registers $DFF800..$DFF9FC"]
        MEM["Capture Window $DF8000..$DF9FFF"]
    end

    subgraph ENGINE["32-Ch Audio DSP"]
        OSC["32x Hardware Voices"]
        MOD["AM / FM / RingMod"]
        MIX["Master Summing"]
        BIQ["Dual Biquad IIR (12/24 dB)"]
        DLY["Zero-RAM Stereo Delay"]
    end

    subgraph CAPTURE["Capture & Handshake"]
        BUF0["BRAM 0 (4 KB)"]
        BUF1["BRAM 1 (4 KB)"]
        FLAG["Status Flag $DFF802"]
    end

    CPU --> REGS
    REGS --> OSC --> MOD --> MIX --> BIQ --> DLY
    DLY --> BUF0 & BUF1
    BUF0 & BUF1 --> MEM
    MEM --> CPU
    DLY --> OUT["I2S / HDMI DAC"]
```

---

## 🎛️ Register Specification

### Custom Registers (`$DFF800..$DFF9FC`)

* **Channel Pitch / Frequency:** `$DFF800 + (ch * 4)` (Bits `[15:0]`)
* **Channel Volume & Control:** `$DFF802 + (ch * 4)`:
  * `[5:0]`: Left Volume (0..64)
  * `[6]`: Filter Enable Right
  * `[7]`: Filter Enable Left
  * `[10:9]`: Input Source Select (`00`=Normal, `01`=Ch(n-1) Modulated, `10`=Noise, `11`=Mute)
  * `[12:11]`: Modulation Mode (`00`=Off, `01`=AM, `10`=RingMod, `11`=FM)
  * `[13]`: Voice Mute
* **Filter Cutoff & Resonance:**
  * `$DFF880`: Left Channel Cutoff frequency & Resonance (Q factor)
  * `$DFF882`: Right Channel Cutoff frequency & Resonance (Q factor)
* **Delay / Reverb Control:**
  * `$DFF890`: Delay Length (0..65535 samples, up to 2.0s)
  * `$DFF892`: Delay Feedback Level & Wet/Dry mix

### Capture Buffer Handshake (`$DF8000..$DF9FFF` & `$DFF802`)

* **Memory Map:**
  * `$DF8000..$DF8FFF`: Capture Block 0 (4096 bytes / 2048 16-bit stereo words)
  * `$DF9000..$DF9FFF`: Capture Block 1 (4096 bytes / 2048 16-bit stereo words)
* **Handshake Register (`$DFF802`):**
  * Read `Bit 0`: Active block written by hardware (`0` = Block 0 ready, `1` = Block 1 ready).
  * Read `Bit 1`: Buffer Ready Flag (`1` = New block ready for CPU consumption).
  * Write `Bit 1`: Clear Buffer Ready Flag (Acknowledge reception, unlocking hardware buffer write).
  * Read `Bit 2`: Overrun Alert (`1` = Hardware caught up before CPU acknowledged; overrun safely avoided without corrupted samples).

---

## 🛠️ Verification & Compilation

* Target FPGA: Intel Cyclone V SE `5CSEBA6U23I7` (DE10-Nano)
* Resource Utilization:
  * ALMs: 38,279 / 41,910 (91%)
  * Block RAM: 327 / 553 (59%)
  * DSP Blocks: 75 / 112 (67%)
* Assembler: `vasm -m68000 -Fhunk -o test.o test.s`
