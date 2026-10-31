# MiSTer Minimig-AGA 32-Kanal High-Definition Audio Core
## Umfassende Register-, Architektur- und Testsuite-Dokumentation

> [!NOTE]
> Dieser Core erweitert den Amiga Minimig-AGA Core auf dem MiSTer FPGA (Cyclone V `5CSEBA6U23I7`) um eine **32-kanalige High-Definition Audio-Pipeline** mit dualen parallelen Biquad IIR DSP-Kernen, AM/Ringmodulation, Pre/Post-Filter-Kaskadierung, Zero-RAM Hardware Start-Delay und 32-Bit Global Interrupts.
> Alle bestehenden Standards (AGA-Chipset, Paula 4-Kanal Audio, HAM-Videopipeline) bleiben vollständig erhalten.

---

## 1. Register-Map & Adressierung

Der gesamte Adressraum umfasst **1024 Bytes** (32 Kanäle $\times$ 32 Bytes) im ungenutzten Custom-Chip-Bereich von **`$DFF400` bis `$DFF7FF`**.  
Das experimentelle HAM-Register wurde hinter den Audiobereich auf **`$DFF800`** verlegt, wodurch keinerlei Adresskollisionen auftreten.

$$\text{Basisadresse Kanal } n = \$DFF400 + (n \times 32) \quad (0 \le n \le 31)$$

### Kanal-Basisadressen:
| Kanal | Basisadresse | DSP-Engine | Kanal | Basisadresse | DSP-Engine |
|:-----:|:------------:|:----------:|:-----:|:------------:|:----------:|
| 0 | `$DFF400` | Engine 0 | 16 | `$DFF600` | Engine 1 |
| 1 | `$DFF420` | Engine 0 | 17 | `$DFF620` | Engine 1 |
| 2 | `$DFF440` | Engine 0 | 18 | `$DFF640` | Engine 1 |
| 3 | `$DFF460` | Engine 0 | 19 | `$DFF660` | Engine 1 |
| 4 | `$DFF480` | Engine 0 | 20 | `$DFF680` | Engine 1 |
| 5 | `$DFF4A0` | Engine 0 | 21 | `$DFF6A0` | Engine 1 |
| 6 | `$DFF4C0` | Engine 0 | 22 | `$DFF6C0` | Engine 1 |
| 7 | `$DFF4E0` | Engine 0 | 23 | `$DFF6E0` | Engine 1 |
| 8 | `$DFF500` | Engine 0 | 24 | `$DFF700` | Engine 1 |
| 9 | `$DFF520` | Engine 0 | 25 | `$DFF720` | Engine 1 |
| 10 | `$DFF540` | Engine 0 | 26 | `$DFF740` | Engine 1 |
| 11 | `$DFF560` | Engine 0 | 27 | `$DFF760` | Engine 1 |
| 12 | `$DFF580` | Engine 0 | 28 | `$DFF780` | Engine 1 |
| 13 | `$DFF5A0` | Engine 0 | 29 | `$DFF7A0` | Engine 1 |
| 14 | `$DFF5C0` | Engine 0 | 30 | `$DFF7C0` | Engine 1 |
| 15 | `$DFF5E0` | Engine 0 | 31 | `$DFF7E0` | Engine 1 / IRQ |

---

## 2. Detaillierte Kanal-Register (Offsets $00..$1F)

Relative Offsets bezogen auf die jeweilige Kanalbasis:

| Offset | Register | R/W | Format | Standard | Funktion |
|:------:|:---------|:---:|:------:|:--------:|:---------|
| `+$00` | `AUDxPTRH` | W | 16 Bit | `$0000` | DMA-Startadresse High (Bits 23..16) |
| `+$02` | `AUDxPTRL` | W | 16 Bit | `$0000` | DMA-Startadresse Low (Bits 15..0) |
| `+$04` | `AUDxLENH` | W | 16 Bit | `$0000` | **Pufferlänge High in Words (Bits 31..16) – Volle 32-Bit DMA!** |
| `+$06` | `AUDxLENL` | W | 16 Bit | `$0000` | **Pufferlänge Low in Words (Bits 15..0)** |
| `+$08` | `AUDxVOL`  | W | 16 Bit | `$0000` | Lautstärke: High-Byte = Links (0..255), Low-Byte = Rechts (0..255) |
| `+$0A` | `AUDxPER`  | W | 16 Bit | `$0100` | Sample-Periode ($f_s = 50\,\text{MHz} / \text{PER}$) |
| `+$0C` | `AUDxCTRL` | W | 16 Bit | `$0000` | Steuerregister (Format, Filter, Modulation, Mute) |
| `+$0E` | `AUDxPRED` | W | 16 Bit | `$0000` | ADPCM Start-Prädiktor & Schritt-Index |
| `+$10` | `AUDxBQ_B0`| R/W| 16 Bit | `$4000` | Biquad Koeffizient $b_0$ (Q2.14, `$4000` = 1.0) |
| `+$12` | `AUDxBQ_B1`| R/W| 16 Bit | `$0000` | Biquad Koeffizient $b_1$ (Q2.14) |
| `+$14` | `AUDxBQ_B2`| R/W| 16 Bit | `$0000` | Biquad Koeffizient $b_2$ (Q2.14) |
| `+$16` | `AUDxBQ_A1`| R/W| 16 Bit | `$0000` | Biquad Koeffizient $a_1$ (Q2.14) |
| `+$18` | `AUDxBQ_A2`| R/W| 16 Bit | `$0000` | Biquad Koeffizient $a_2$ (Q2.14) |
| `+$1A` | `AUDxCMD`  | R/W| 16 Bit | `$0000` | Kommando & Status (Bit 0 = Start, Bit 1 = Stop) |
| `+$1C` | `AUDxDELAY`| W   | 16 Bit | `$0000` | **Zero-RAM Start-Delay Counter (0..2,0 s @ 32.768 kHz)** |
| `+$1E` | `AUDxSTATUS`| R  | 16 Bit | `$0000` | Kanal-Status / Readback |

---

## 3. Globales 32-Bit Interrupt-System (Kanal 31)

Die Interrupt-Steuerung für alle 32 Stimmen befindet sich am oberen Ende des Adressfensters in den oberen Registerwörtern von Kanal 31:

| Adresse | Offset (Ch 31) | Register | R/W | Beschreibung |
|:-------:|:--------------:|:---------|:---:|:-------------|
| `$DFF7F8` | `+$18` (Word 12) | `AUD_INTENA_HI` | R/W | Interrupt Enable für Stimmen 31..16 |
| `$DFF7FA` | `+$1A` (Word 13) | `AUD_INTENA_LO` | R/W | Interrupt Enable für Stimmen 15..0 |
| `$DFF7FC` | `+$1C` (Word 14) | `AUD_INTREQ_HI` | R/W1C| Interrupt Request für Stimmen 31..16 (Write-1-to-Clear) |
| `$DFF7FE` | `+$1E` (Word 15) | `AUD_INTREQ_LO` | R/W1C| Interrupt Request für Stimmen 15..0 (Write-1-to-Clear) |

- **Interrupt-Vektor:** Löst Amiga Level-2 Autovector (`$68`, `INT2`) aus (gemeinsam mit CIA-A / IDE / Akiko).
- **Acknowledge:** Durch Schreiben einer `1` auf das jeweilige Bit im Request-Register wird der Interrupt bestätigt und gelöscht.

---

## 4. Dual-Biquad DSP Engine Architektur

Um 32 Stimmen bei 48 kHz Stereo ohne Sample-Dropping in Echtzeit filtern zu können, arbeiten zwei unabhängige, hardwarebeschleunigte Biquad IIR DSP-Engines vollkommen parallel:
- **DSP Engine 0:** Bedient Stimmen 0 bis 15 im TDM-Slot 0..15.
- **DSP Engine 1:** Bedient Stimmen 16 bis 31 im TDM-Slot 16..31.
- **Ressourcen:** Jede Engine nutzt 1 Cyclone V DSP-Block (insgesamt nur **2 DSPs** für 32 Stimmen!).
- **Verzögerungsfreie Berechnung:** Durch separate Koeffizienten- und Zustands-RAMs entfällt jegliches Bus-Stalling.

---

## 5. M68000 Testsuite (`audio_pipeline_32ch_test.s`)

Das mitgelieferte Assembler-Testprogramm führt eine automatische Verifikation aller Features durch und signalisiert die Testphasen über die Amiga Rahmenfarbe (`COLOR00`):

1. **Test 1 (Grün - `$00F0`): 32-Stimmen Polyphonie & Stereo-Panorama**
   - Spielt gleichzeitig 32 verschiedene Frequenzen (harmonischer 32-Ton-Akkord).
   - Gleichmäßige Verteilung im Stereofeld: Stimme 0 (100% Links `$FF00`) über Stimme 16 (Center `$8080`) bis Stimme 31 (100% Rechts `$00FF`).
2. **Test 2 (Blau - `$000F`): Dual-Biquad DSP-Filter Verifikation**
   - Testet Low-Pass Filter auf Stimme 4 (Engine 0).
   - Testet Band-Pass Filter auf Stimme 20 (Engine 1).
   - Verifiziert parallele Filterung über beide DSP-Kerne.
3. **Test 3 (Gelb - `$0FF0`): Pre-Filter Kaskade (24 dB/Oct Moog-Filter)**
   - Kaskadiert Stimme 0 in Stimme 1 vor dem Filter (`INPUT_SRC = 01`).
   - Erzeugt ein steilflankiges 4-Pol Filter (24 dB/Oktave).
4. **Test 4 (Magenta - `$0F0F`): AM / Tremolo & Ringmodulation**
   - Stimme 4 moduliert Stimme 5 (AM Tremolo).
   - Stimme 6 moduliert Stimme 7 (Ringmodulation).
5. **Test 5 (Cyan - `$00FF`): Zero-RAM Spatial Start-Delay**
   - Zeitverzögerter Start von Stimmen 8, 9, 10, 11 (0 ms, 125 ms, 250 ms, 500 ms) ohne Sample-Speicherverbrauch.
6. **Test 6 (Weiß - `$0FFF`): 32-Bit Global Interrupt Test**
   - Triggert One-Shot Buffer auf Kanal 31, fängt Level-2 IRQ ab und bestätigt via `AUD_INTREQ_HI`.
7. **Ergebnis (Dunkelgrün - `$00A0`):** Alle 32-Kanal Tests erfolgreich bestanden!
