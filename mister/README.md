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
flowchart TD
    subgraph CHANNEL_PIPELINE["Channel Pipeline (TDM über Channels 0..31)"]
        direction TB

        subgraph DEC_STAGE["1. Dekodier-Stufe (Pro Channel n)"]
            RAW_STREAM["Sample-Stream (DMA / FIFO)"]
            PCM_DEC["Linear PCM Unpacker<br/>(8-Bit / 16-Bit)"]
            ADPCM_DEC["Shared ADPCM Decoder<br/>(2/3/4/5-Bit DPCM Prädiktor & Schrittindex)"]
            SEL_DEC{"Format-Wahl<br/>(v_adpcm [3])"}
            
            RAW_STREAM --> PCM_DEC
            RAW_STREAM --> ADPCM_DEC
            PCM_DEC -->|Linear PCM| SEL_DEC
            ADPCM_DEC -->|Rekonstruiertes PCM| SEL_DEC
        end

        subgraph INPUT_ROUTER["2. Input-Multiplexer & Channel-Chaining"]
            PRE_PREV["Ch(n-1) Pre-Filter Signal<br/>(Ungefiltertes Durchreichen)"]
            POST_PREV["Ch(n-1) Post-Filter Signal<br/>(Filter-Kaskadierung / 24 dB Moog-Typ)"]
            SRC_MUX{"Input-Source Select<br/>(v_input_src [10:9])"}

            SEL_DEC -->|2'b00: Eigener Sample-Stream| SRC_MUX
            PRE_PREV -->|2'b01: Ch(n-1) Pre-Filter| SRC_MUX
            POST_PREV -->|2'b10: Ch(n-1) Post-Filter| SRC_MUX
        end

        subgraph FILTER_STAGE["3. Dual Biquad IIR Filter DSP-Stufe"]
            SRC_MUX --> IN_FILTER["Filter-Eingangssignal (in_pcm_src)"]
            IN_FILTER --> BIQ_CORE["Dual Parallel Biquad IIR DSP Filter<br/>(Tiefpass / Hochpass / Bandpass / Notch / Peaking)"]
            
            IN_FILTER -->|Pre-Filter Abgriff| PRE_FORWARD["Pre-Filter Durchreichung an Ch(n+1)"]
            BIQ_CORE -->|Post-Filter Abgriff| POST_FORWARD["Post-Filter Signal an Ch(n+1)<br/>(Kaskadierung für 24 dB/Okt. Flankensteilheit)"]
        end

        subgraph MOD_STAGE["4. Modulations- & Lautstärkestufe"]
            BIQ_CORE --> MIX_VOICE["Gefiltertes Kanalsignal"]
            CARRIER_IN["Carrier-Signal von Ch(n-1) (prev_carrier_l)"]
            
            MOD_SELECT{"Modulations-Modus<br/>(v_mod_mode [12:11])"}
            AM_MOD["Amplitudenmodulation / Tremolo (01)"]
            RING_MOD["Ringmodulation (Bipolares Produkt) (10)"]
            DIR_VOL["Direkte Lautstärke / Panning (00)"]
            
            CARRIER_IN --> MOD_SELECT
            MOD_SELECT --> AM_MOD
            MOD_SELECT --> RING_MOD
            MOD_SELECT --> DIR_VOL
            
            MIX_VOICE --> MULT_STAGE["Stereo Multiplizierer-Stufe<br/>(Kanal-Sample × Modulations-/Vol-Faktor)"]
            AM_MOD --> MULT_STAGE
            RING_MOD --> MULT_STAGE
            DIR_VOL --> MULT_STAGE
            
            MULT_STAGE --> CARRIER_OUT["Carrier-Signal an Ch(n+1)"]
        end
    end

    subgraph MIXER_CAPTURE["5. Summierungs- & Capture-Einheit"]
        MULT_STAGE -->|32x Kanalsumme| MASTER_SUM["Master Accumulator (32 Channels)<br/>32-Bit Summe mit Soft-Clipping / Headroom-Schutz"]
        
        MASTER_SUM --> CAP_LOGIC["Capture Router & Overrun-Protection<br/>(Handshake-Flag $DFF802)"]
        CAP_LOGIC -->|Block 0 aktiv| BRAM0["BRAM Puffer 0 (4 KB)<br/>$DF8000 - $DF8FFF"]
        CAP_LOGIC -->|Block 1 aktiv| BRAM1["BRAM Puffer 1 (4 KB)<br/>$DF9000 - $DF9FFF"]
    end
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
