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

### 1. Signal- & Datenfluss-Diagramm

```mermaid
flowchart LR
    %% STAGE 1: DECODING
    subgraph S1 ["1. DEKODIERUNG (Channel n)"]
        direction TB
        FIFO["Sample FIFO<br/>(DMA Stream)"]
        PCM["Linear PCM<br/>8 / 16 Bit"]
        ADPCM["Shared ADPCM Core<br/>2..5 Bit DPCM"]
        DECMUX{"Decoder MUX<br/>(v_adpcm)"}
        
        FIFO --> PCM
        FIFO --> ADPCM
        PCM -->|PCM| DECMUX
        ADPCM -->|DPCM| DECMUX
    end

    %% STAGE 2: CHAINING & INPUT
    subgraph S2 ["2. KANAL-KASKADIERUNG"]
        direction TB
        IN_PRE["Ch(n-1) Pre-Filter"]
        IN_POST["Ch(n-1) Post-Filter"]
        SRCMUX{"Input MUX<br/>(v_input_src)"}
        
        IN_PRE -->|Dry Pass| SRCMUX
        IN_POST -->|24 dB Kaskade| SRCMUX
    end

    %% STAGE 3: FILTER DSP
    subgraph S3 ["3. BIQUAD IIR DSP FILTER"]
        direction TB
        FLT_IN["Filter Input"]
        BIQ["Dual Biquad IIR<br/>LP / HP / BP / Notch<br/>12 dB/Okt."]
        
        FLT_IN -->|Pre-Tap| FWD_PRE["an Ch(n+1) Pre"]
        FLT_IN --> BIQ
        BIQ -->|Post-Tap| FWD_POST["an Ch(n+1) Post"]
    end

    %% STAGE 4: MODULATION & VOLUME
    subgraph S4 ["4. MODULATION & PANNING"]
        direction TB
        MOD_IN["Carrier von Ch(n-1)"]
        MODMUX{"Modus<br/>(v_mod_mode)"}
        MOD_CALC["AM / RingMod / Pan<br/>Faktor-Berechnung"]
        MULT["Stereo Multiplizierer<br/>(Sample × Faktor)"]
        
        MOD_IN --> MODMUX
        MODMUX --> MOD_CALC
        MOD_CALC --> MULT
        MULT --> FWD_CARRIER["Carrier an Ch(n+1)"]
    end

    %% STAGE 5: ACCUMULATOR & CAPTURE
    subgraph S5 ["5. MASTER-SUMME & CAPTURE"]
        direction TB
        ACC["Master Akkumulator<br/>Summe über 32 Channels<br/>32-Bit Soft-Clipping"]
        CAP_CTRL["Capture Router<br/>Handshake ($DFF802)"]
        BRAM0["Block 0: $DF8000 (4 KB)"]
        BRAM1["Block 1: $DF9000 (4 KB)"]
        
        ACC --> CAP_CTRL
        CAP_CTRL -->|Block 0| BRAM0
        CAP_CTRL -->|Block 1| BRAM1
    end

    %% INTER-STAGE CONNECTIONS
    DECMUX -->|Eigenes Sample| SRCMUX
    SRCMUX --> FLT_IN
    BIQ --> MULT
    MULT -->|32x TDM Summe| ACC
```

### 2. Detailliertes Register- & Busbreiten-Schaltbild

```text
========================================================================================================================
                                     32-CHANNEL HIGH-DEFINITION AUDIO & DSP PIPELINE
========================================================================================================================

 [ DMA SAMPLE STREAM ]
          │
          ├───► [ 8/16-Bit Linear PCM Unpacker ] ──────┐
          │                                            ▼ (v_adpcm [3])
          └───► [ Shared ADPCM Decoder (2..5 Bit) ] ──► (MUX) ── [ Eigenes Sample (00) ] ─┐
                                                                                           │
 [ Von Channel n-1 ] ──► Pre-Filter Signal Durchreichung ─────── [ Ch(n-1) Pre-Filter (01) ] ──────► ( INPUT-MUX )
 [ Von Channel n-1 ] ──► Post-Filter Signal (Kaskadierung) ───── [ Ch(n-1) Post-Filter (10) ] ─┘        (v_input_src [10:9])
                                                                                                           │
      ┌────────────────────────────────────────────────────────────────────────────────────────────────────┘
      ▼
 [ FILTER-EINGANG ] ──────┬──────────────────────────────────────────────────────────► Weiterleitung: Pre-Filter an Ch(n+1)
      │                   │
      │ (Aktiv / Bypass)  ▼
      │           ┌──────────────────────────────────────────────┐
      └──────────►│      DUAL PARALLEL BIQUAD IIR DSP FILTER     │
                  │   Tiefpass / Hochpass / Bandpass / Notch     │
                  │     12 dB/Okt. (24 dB bei Kaskadierung)      │
                  └──────────────────────┬───────────────────────┘
                                         │
                                         ├───────────────────────────────────────────► Weiterleitung: Post-Filter an Ch(n+1)
                                         ▼                                             (für kaskadierte 24 dB Moog-Filter)
                              [ Gefiltertes Sample ]
                                         │
 [ Von Channel n-1 ] ──► Carrier-Signal  │
            │                            ▼
            ├───────────────► ┌──────────────────────────────────────────┐
            │                 │       MODULATION & PANNING STUFE         │
            │                 │   • 00: Direkte Lautstärke / Panning     │
            │                 │   • 01: Amplitudenmodulation (Tremolo)   │
            │                 │   • 10: Ringmodulation (Bipolar)         │
            │                 └──────────────────┬───────────────────────┘
            │                                    │
            │                                    ├───────────────────────────► Weiterleitung: Carrier-Signal an Ch(n+1)
            │                                    ▼
            │                         [ Stereo Multiplizierer ]
            │                         (Kanal-Sample × Mod-Faktor)
            │                                    │
════════════╧════════════════════════════════════╪════════════════════════════════════════════════════════════════════════════
                        ZEITMULTIPLEXING ÜBER ALLE 32 CHANNELS (TDM 48 kHz)
════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
                                                 │
                                                 ▼
                              ┌──────────────────────────────────────────┐
                              │     32-BIT MASTER-SUMMEN-AKKUMULATOR     │
                              │   Headroom-Schutz & Soft-Clipping        │
                              └──────────────────┬───────────────────────┘
                                                 │
                                                 ▼
                              ┌──────────────────────────────────────────┐
                              │      AUDIO-CAPTURE & DOPPEL-PUFFER       │
                              │      Hardware-Handshake & Overrun-Schutz │
                              │      Status & Freigabe-Flag: $DFF802     │
                              └──────────────┬────────────┬──────────────┘
                                             │            │
                         [ Puffer 0: 4 KB ] ─┘            └── [ Puffer 1: 4 KB ]
                         $DF8000 .. $DF8FFF                   $DF9000 .. $DF9FFF
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
