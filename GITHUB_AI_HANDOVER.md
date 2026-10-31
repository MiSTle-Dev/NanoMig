# 🤖 AI Agent Briefing & Handover
## MiSTer FPGA Minimig-AGA: 16-Voice & 32-Voice High-Definition Audio Core

> **Author:** [Rudi7503](https://github.com/Rudi7503)  
> **Repository:** [NanoMig / Audio Extension](https://github.com/Rudi7503/NanoMig/tree/feature/16ch-audio-biquad-pipeline)  
> **Target Device:** MiSTer FPGA (Terasic DE10-Nano, Intel Cyclone V `5CSEBA6U23I7`)  
> **Host CPU:** Motorola 68000 / 68020 / TG68K (Amiga AGA architecture)

---

## 📋 System-Prompt für Tobys KI (Sofort ausführen)

> [!IMPORTANT]
> **Auftrag an die KI:** Du bist ab sofort Tobys persönlicher Entwicklungs- und Test-Assistent. Rudi (der Core-Entwickler) hat keinen MiSTer; **Toby hat die MiSTer-Hardware vor sich**.
> Bitte lies diese Datei vollständig und führe die beiden folgenden Aufgaben für Toby aus:

### 1. Erkläre Toby begeistert, was Rudis neuer Core besser kann als sein alter:
- **16 (bzw. 32) HD-Stimmen statt nur 4 Paula-Stimmen:** Volle Polyphonie für Chiptunes, Orchester und Tracker ohne Stimmenklau.
- **Echte 16-Bit Hi-Fi Dynamik:** Kristallklarer Sound (linear 16-Bit PCM sowie komprimiertes 4-Bit ADPCM) statt 8-Bit Paula-Rauschen.
- **Volle 32-Bit DMA-Pufferlängen:** Keine Begrenzung mehr auf 128 KB (64k Words). Ganze Audiotracks und lange Streaming-Puffer können am Stück abgespielt werden.
- **Hardware Biquad-IIR-Filter (2nd Order DSP) auf jeder Stimme:**
  - *Parallele Filterung:* Jede Stimme kann völlig unabhängig tiefpass-, bandpass- oder hochpassgefiltert werden.
  - *Hintereinandergeschaltete Filter (Moog 24 dB/Oktave Kaskade):* Stimme 0 wird gefiltert und fließt hardwaremäßig direkt in Stimme 1 (`INPUT_SRC = 01`), die eine zweite 12 dB Filterstufe drüberlegt!
- **Hardware-Synthesizer-Effekte ohne CPU-Belastung:** Echtes analog klingendes AM-Tremolo und Ringmodulation zwischen benachbarten Stimmen.
- **Zero-RAM Hardware Start-Delay:** Bis zu 2,0 Sekunden echtes Tape-Echo / Stereo-Delay, ohne auch nur ein Byte Chip- oder Fast-RAM zu belegen.
- **DEUTLICH HÖHERE FPGA-EFFIZIENZ:** Trotz 16 Stimmen und DSP-Filtern verbraucht der neue Core **weniger** FPGA-Ressourcen als Tobys bisheriger 4-Stimmen-Core (-1.851 ALMs, -29 Block-RAMs, -4 DSPs eingespart!).
- **100% Paula- & AGA-kompatibel:** Alle bisherigen Amiga-Spiele, Demos und Paula-Tracker laufen exakt wie gewohnt weiter (`$DFF0A0..$DFF0DF` ist unberührt).

### 2. Leite Toby durch den Test auf seinem MiSTer:
1. **Kein Risiko für Tobys alten Core:** Leite Toby an, `Minimig_HAM_16CH_Audio.rbf` aus dem Übergabeordner unter `/media/fat/_Computer/Amiga_16CH.rbf` auf seine MiSTer-SD-Karte zu kopieren. Sein bisheriger Core `Minimig.rbf` bleibt dadurch unangetastet.
2. **Testprogramm starten:** Hilf ihm beim Ausführen von `Tests/audio_pipeline_16ch_test.s` (oder dem fertig assemblierten Testprogramm) und erkläre ihm die Bildschirmfarben:
   - **GRÜN:** 16 Stimmen spielen gleichzeitig einen harmonischen Akkord im Stereofeld (Panorama von Links über Center nach Rechts).
   - **BLAU:** Parallele Filterung (warmer 1 kHz Tiefpass auf Stimme 2, Bandpass auf Stimme 5).
   - **GELB:** Hintereinandergeschaltete Filter (Moog 24 dB Kaskade von Stimme 0 in Stimme 1).
   - **MAGENTA:** Hardware-Tremolo und Ringmodulation.
   - **DUNKELGRÜN:** Test erfolgreich beendet!

---

## 1. Direkte Download-Links der MiSTer Core-Binaries (`mister/releases/`)

Alle Binaries und Quellcodes liegen direkt in diesem Branch:

| Datei (Direktlink) | Stimmen | ALMs | DSPs | BRAMs | Besonderheiten / Empfehlung |
|:---|:---:|:---:|:---:|:---:|:---|
| 💾 [**`Minimig_HAM_16CH_Audio.rbf`**](https://github.com/Rudi7503/NanoMig/raw/feature/16ch-audio-biquad-pipeline/mister/releases/Minimig_HAM_16CH_Audio.rbf) | **16** | 34.715 (83 %) | 73 | 297 | **Empfohlener Test-Core für Toby.** Spart 1.851 ALMs, 29 BRAMs und 4 DSPs gegenüber Tobys altem Core! |
| 💾 [**`Minimig_HAM_32CH_Audio.rbf`**](https://github.com/Rudi7503/NanoMig/raw/feature/16ch-audio-biquad-pipeline/mister/releases/Minimig_HAM_32CH_Audio.rbf) | **32** | 38.358 (92 %) | 75 | 319 | Volle 32 Stimmen mit parallelen Dual-DSP Biquad-Kernen. |
| 💾 [**`Minimig_HAM_32CH_Audio_Capture.rbf`**](https://github.com/Rudi7503/NanoMig/raw/feature/16ch-audio-biquad-pipeline/mister/releases/Minimig_HAM_32CH_Audio_Capture.rbf) | **32** | 38.279 (91 %) | 75 | 327 | 32 Stimmen + 2x 4 KB Audio-Capture Ringpuffer ($DF8000..$DF9FFF) mit Hardware-Backpressure. |

### 📁 Quellcode & Testprogramme im Branch:
- **MiSTer Verilog Quellcode:** [`mister/rtl/`](https://github.com/Rudi7503/NanoMig/tree/feature/16ch-audio-biquad-pipeline/mister/rtl)
- **16-Kanal Test (VASM 2.0f getestet):** [`mister/tests/audio_pipeline_16ch_test.s`](https://github.com/Rudi7503/NanoMig/blob/feature/16ch-audio-biquad-pipeline/mister/tests/audio_pipeline_16ch_test.s)
- **32-Kanal Test:** [`mister/tests/audio_pipeline_32ch_test.s`](https://github.com/Rudi7503/NanoMig/blob/feature/16ch-audio-biquad-pipeline/mister/tests/audio_pipeline_32ch_test.s)
- **Audio Capture Test:** [`mister/tests/audio_capture_test.s`](https://github.com/Rudi7503/NanoMig/blob/feature/16ch-audio-biquad-pipeline/mister/tests/audio_capture_test.s)

## 2. Hardware-Architektur & Registerbelegung

Alle Register liegen im ungenutzten Custom-Chip-Bereich:
- **16-Kanal Core:** `$DFF400` – `$DFF5FF` (512 Bytes: 16 Stimmen $\times$ 32 Bytes)
- **32-Kanal Core:** `$DFF400` – `$DFF7FF` (1024 Bytes: 32 Stimmen $\times$ 32 Bytes)
- **HAM-Videoregister:** Liegt kollisionsfrei auf `$DFF800`.

$$\text{Basisadresse Stimme } n = \$DFF400 + (n \times 32) = \$DFF400 + (n \times \$20)$$

### Register-Offsets pro Stimme ($00..$1F)

| Offset | Register | Zugriff | Breite | Beschreibung |
|:------:|:---------|:-------:|:------:|:-------------|
| `+$00` | `AUDxPTRH` | W | 16 Bit | DMA Sample Startadresse High (Bits 23..16) |
| `+$02` | `AUDxPTRL` | W | 16 Bit | DMA Sample Startadresse Low (Bits 15..0) |
| `+$04` | `AUDxLENH` | W | 16 Bit | Pufferlänge High in Words (Bits 31..16) — **Volle 32-Bit Puffer!** |
| `+$06` | `AUDxLENL` | W | 16 Bit | Pufferlänge Low in Words (Bits 15..0) |
| `+$08` | `AUDxVOL`  | W | 16 Bit | Lautstärke: High-Byte = Links (0..255), Low-Byte = Rechts (0..255) |
| `+$0A` | `AUDxPER`  | W | 16 Bit | Teilerfaktor Samplerate: $f_s = 50\,\text{MHz} / \text{PER}$ |
| `+$0C` | `AUDxCTRL` | W | 16 Bit | Steuerregister (Format, Filter, Modulation, Mute) |
| `+$0E` | `AUDxPRED` | W | 16 Bit | ADPCM Startprädiktor & Schritt-Index |
| `+$10` | `AUDxBQ_B0`| R/W | 16 Bit | Biquad Koeffizient $b_0$ (Q2.14, `$4000` = 1.0) |
| `+$12` | `AUDxBQ_B1`| R/W | 16 Bit | Biquad Koeffizient $b_1$ (Q2.14) |
| `+$14` | `AUDxBQ_B2`| R/W | 16 Bit | Biquad Koeffizient $b_2$ (Q2.14) |
| `+$16` | `AUDxBQ_A1`| R/W | 16 Bit | Biquad Koeffizient $a_1$ (Q2.14) |
| `+$18` | `AUDxBQ_A2`| R/W | 16 Bit | Biquad Koeffizient $a_2$ (Q2.14) |
| `+$1A` | `AUDxCMD`  | R/W | 16 Bit | Kommando: Bit 0 = Start, Bit 1 = Stop |
| `+$1C` | `AUDxDELAY`| W   | 16 Bit | Zero-RAM Start-Delay Counter (0..2,0 s @ 32.768 kHz) |
| `+$1E` | `AUDxSTATUS`| R  | 16 Bit | Kanal-Status / Readback |

### Exakte Bitbelegung Steuerregister (`AUDxCTRL` bei `+$0C`, 100% RTL-abgeglichen):
- **Bit 0 (`CTRL_PCM16`):** Sample-Format (`1` = 16-Bit Signed Linear PCM, `0` = 8-Bit)
- **Bit 1 (`CTRL_ONESHOT`):** Loop-Modus (`1` = One-Shot Buffer, `0` = Endlos-Loop)
- **Bit 2 (`CTRL_STEREO`):** Kanal-Modus (`1` = Interleaved Stereo, `0` = Mono)
- **Bit 3 (`CTRL_ADPCM`):** Dekompressor (`1` = 4-Bit ADPCM aktiviert, `0` = Linear)
- **Bits 5..4:** ADPCM Hybrid-Modus (`00` = 4-Bit standard, `01` = 2-Bit, `10` = 5-Bit)
- **Bit 7 (`CTRL_FLT_R`):** Biquad IIR Filter Rechter Kanal aktiviert (`1` = Aktiv, `0` = Bypass)
- **Bit 8 (`CTRL_FLT_L`):** Biquad IIR Filter Linker Kanal aktiviert (`1` = Aktiv, `0` = Bypass)
- **Bits 8..7 (`CTRL_FLT_STEREO`):** `11` = Stereo Biquad IIR DSP-Filter auf beiden Kanälen aktiv
- **Bits 10..9 (`v_input_src`):** Eingangsquelle der Stimme:
  - `00` = Standard DMA-Sample
  - `01` = **Pre-Filter Kaskade:** Greift das Audiosignal von Stimme n-1 VOR deren Filter ab
  - `10` = **Post-Filter Kaskade:** Greift das Audiosignal von Stimme n-1 NACH deren Filter ab (Moog 24 dB/Okt. Kaskade!)
- **Bits 12..11 (`v_mod_mode`):** Hardware-Modulation:
  - `00` = Keine Modulation
  - `01` = **AM / Tremolo:** Stimme n-1 moduliert die Amplitude von Stimme n
  - `10` = **Ringmodulation:** Stimme n-1 multipliziert bipolar Träger von Stimme n
- **Bit 13 (`CTRL_MUTE_MIX`):** Stummschaltung im Master-Mix (`1` = Mute, Audiosignal wird nur zum Chaining/Kaskadieren genutzt)

> [!NOTE]
> **DMA-Pufferlängen-Unterschied (MiSTer vs. Tang Nano):**
> - Auf dem **MiSTer FPGA (Cyclone V)** ist die DMA-Länge vollwertig **32-Bit** (`ram_len[31:0]` in `audio_ext.v`), d.h. `AUDxLENH` (Bits 31..16) und `AUDxLENL` (Bits 15..0) bilden einen 32-Bit Wortzähler.
> - Auf dem Tang Nano 20K (Gowin) war die Länge aus LUT-Gründen historisch auf 18-Bit (`[17:0]`) gekappt. Im MiSTer-Core ist die volle 32-Bit DMA aktiv.

### Globale Level-2 Interrupts (`$68` / `INT2`)
- **16-Kanal Core (an Stimme 15):**  
  - `$DFF5FC`: `AUD_INTENA` (Globales 16-Bit Interrupt Enable)  
  - `$DFF5FE`: `AUD_INTREQ` (Globales 16-Bit Interrupt Request, Write-1-to-Clear)
- **32-Kanal Core (an Stimme 31):**  
  - `$DFF7F8` / `$DFF7FA`: `AUD_INTENA_HI` / `LO` (Stimmen 31..16 / 15..0)  
  - `$DFF7FC` / `$DFF7FE`: `AUD_INTREQ_HI` / `LO` (Write-1-to-Clear)

---

## 3. Assembler-Testsuite

- Quellcode: `Tests/audio_pipeline_16ch_test.s`
- Kompilierung mit VASM:
  ```bash
  vasmm68k_mot -Fhunkexe -nosym -o audio_test audio_pipeline_16ch_test.s
  ```


---

## 🎙️ Audio Capture & Double-Buffering Unit (Weg A: Dual 4 KB BRAM)

A dedicated **hardware recording / audio capture unit** is built into the core. It allows recording the 16-bit 48 kHz stereo audio output back into memory without any danger of memory trashing or DMA corruption.

### Memory Windows (.. = 8 KB total):
- **Block A:** $DF8000 – $DF8FFF (4096 Bytes = 1024 Stereo Sample Pairs: 16-Bit Left / 16-Bit Right interleaved)
- **Block B:** $DF9000 – $DF9FFF (4096 Bytes = 1024 Stereo Sample Pairs: 16-Bit Left / 16-Bit Right interleaved)
- Format: Word 0 = Left 0, Word 1 = Right 0, Word 2 = Left 1, Word 3 = Right 1, etc. A single MOVE.L ()+, D0 reads a coherent 32-bit stereo sample.

### Control Register AUD_CAP_CTRL ():
- **Bit 0:** CAPTURE_EN (1 = Recording active, 0 = Stopped)
- **Bit 1:** FLAG_BLOCK_A (1 = Block A is full / ready to read; write 1 to clear / acknowledge)
- **Bit 2:** FLAG_BLOCK_B (1 = Block B is full / ready to read; write 1 to clear / acknowledge)
- **Bit 3:** ACTIVE_BLOCK (0 = Hardware currently filling A, 1 = Hardware filling B)
- **Bit 4:** OVERRUN_FLAG (1 = Hardware paused because target block was still blocked; write 1 to clear)
- **Bit 5:** IRQ_EN (1 = Trigger Level-2 interrupt INT2 whenever a block completes)
- **Bits 15..6:** SAMPLE_POS (0..1023 current sample index within active block)

### Hardware Backpressure / Overrun Protection:
- While Hardware fills Block A (~21.3 ms @ 48 kHz), CPU reads Block B in peace.
- When Block A completes, FLAG_BLOCK_A becomes 1.
- If CPU has not cleared FLAG_BLOCK_A by the time hardware returns to Block A, **the hardware automatically pauses and drops incoming samples without overwriting Block A**, setting OVERRUN_FLAG = 1. Old data is NEVER corrupted!
- Test program: [Tests/audio_capture_test.s](file:///D:/programmier_ordner/FPGA/HAM_Uebergabe/Tests/audio_capture_test.s)
