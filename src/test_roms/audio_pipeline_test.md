# NanoMig 16-Kanal Audio-Pipeline Test-Suite
## Vollständige Dokumentation & Verifikationsanleitung

Die Test-Suite [`audio_pipeline_test.s`](audio_pipeline_test.s) ist ein eigenständiges, modulares M68000/68020 Assembler-Programm zur vollständigen Verifikation aller Hardware-Features der neuen NanoMig Audio-Erweiterung auf dem Gowin Tang Nano 20K FPGA.

---

## 1. Übersicht der Test-Routinen

| Test # | Routine | Getestete Hardware-Features | Akustische / Optische Rückmeldung |
|:---:|:---|:---|:---|
| **1** | `Test1_Polyphony` | 16-Kanal TDM Core, DMA-Engine, 16-Bit Lautstärken-Mixer, Saturation-Clamping | Pentatonischer 16-Stimmen-Akkord, aufgefächert von ganz links bis ganz rechts. *Farbe: Tiefblau* |
| **2** | `Test2_16Bit_vs_8Bit` | `CTRL_PCM16` Umschaltung, 32-Bit DMA-Länge (`AUDxLENH/L`) | A/B-Vergleich: Linker Lautsprecher = 16-Bit Hi-Fi (96 dB SNR), Rechter Lautsprecher = 8-Bit Paula (48 dB SNR). *Farbe: Grün* |
| **3** | `Test3_FilterSweep` | Dual-Pass Biquad IIR Filter, Stereo-Routing Matrix (`CTRL_FLT_L`) | Sägezahn: Linker Kanal gefiltert (3.2 kHz Tiefpass), Rechter Kanal ungefiltert (Bypass-Direktvergleich im Kopfhörer). *Farbe: Gelb* |
| **4** | `Test4_ParallelFilterbank` | Pre-Filter Chaining (`INPUT_SRC = 01`), `MUTE_MIX` | 3-Band Equalizer: Ch 0 (Quelle stumm), Ch 1 (Bass links), Ch 2 (Mitten center), Ch 3 (Höhen rechts). *Farbe: Magenta* |
| **5** | `Test5_SerialCascade_48dB` | Serielle Kaskade (`INPUT_SRC = 10`), 48 dB Moog Ladder | Vier hintereinandergeschaltete 12-dB Tiefpassfilterstufen (Ch 0 -> 1 -> 2 -> 3), ultrakompakter analoger Moog-Sound. *Farbe: Rot-Orange* |
| **6** | `Test6_AM_Tremolo` | Unipolare Modulation (`MOD_MODE = 01`), LFO-Steuerung | Träger (440 Hz) moduliert mit 5 Hz Sinus-LFO. Reines analoges Lautstärken-Tremolo (0..100%). *Farbe: Cyan* |
| **7** | `Test7_Ringmodulation` | Bipolare Modulation (`MOD_MODE = 10`), DSP 4-Quadranten-Multiplizierer | Träger (440 Hz) multipliziert mit Modulator (330 Hz). Erzeugt Summen- (770 Hz) und Differenztöne (110 Hz), Glocken-Klang. *Farbe: Weiß* |
| **8** | `Test8_StartDelayEcho` | Zero-RAM Start-Delay Zähler (`AUDxDELAY` @ 32.768 kHz) | Ping-Pong Tape Echo: Ch 0 Direkt (Links), Ch 1 Echo 125 ms (Rechts), Ch 2 Echo 250 ms gefiltert (Links). *Farbe: Violett* |
| **9** | `Test9_InterruptSystem` | Globales 16-Bit IRQ-System (`AUD_INTENA` & `AUD_INTREQ` @ Ch 15, W1C) | One-Shot Pufferende auf Ch 4 löst Amiga Level-2 Interrupt aus. ISR quittiert per Write-1-to-Clear. *Farbe: Dunkelgrün + Weißer Blitz* |

---

## 2. Detaillierte Funktionsbeschreibung der Tests

### Test 1: 16-Stimmen Polyphonie & Stereopanorama (`Test1_Polyphony`)
- **Ziel:** Nachweis, dass alle 16 Hardware-TDM-Slots unabhängig und parallel ohne Jitter oder Aussetzer mit 50 MHz verarbeitet werden.
- **Registerkonfiguration:**
  - Für alle 16 Stimmen ($n = 0 \dots 15$) wird `AUDxPTRH/L` auf eine 16-Bit Sinustabelle im Chip-RAM gesetzt.
  - `AUDxPER` wird aus einer 16-stufigen pentatonischen Frequenztabelle geladen (Tonhöhen von 160 Hz bis 2500 Hz).
  - `AUDxVOL` berechnet lineares Stereo-Panning:
    $$\text{Volume Links} = 127 - (n \times 8), \quad \text{Volume Rechts} = n \times 8$$
  - `AUDxCTRL = $0001` (`CTRL_PCM16 = 1`, Mono, Bypass).
  - Alle Stimmen werden gestartet (`AUDxCMD = 1`).
- **Verifikation:** Alle 16 Töne klingen sauber gleichzeitig im Raum verteilt. Die 18-Bit Summierungsstufe verhindert Übersteuern durch internes Headroom-Management.

---

### Test 2: 16-Bit Hi-Fi PCM vs. 8-Bit Paula PCM & 32-Bit DMA (`Test2_16Bit_vs_8Bit`)
- **Ziel:** Hörbarer Nachweis der 16-Bit Auflösung gegenüber herkömmlichem 8-Bit Amiga Paula Sound sowie Prüfung von DMA-Längen über 64K Words.
- **Registerkonfiguration:**
  - **Kanal 0 (16-Bit):** `AUD0CTRL = $0001` (`PCM16 = 1`). `AUD0LENH = $0001`, `AUD0LENL = $0000` (65.536 Words = 131.072 Bytes Pufferlänge!). Lautstärke links voll (`$FF00`).
  - **Kanal 1 (8-Bit):** `AUD1CTRL = $0000` (`PCM16 = 0`). Liest standard 8-Bit vorzeichenbehaftete Bytes (-128..+127). Lautstärke rechts voll (`$00FF`).
- **Verifikation:** Im linken Ohr ertönt eine absolut rauschfreie 16-Bit Sinusschwingung (theoretischer Dynamikumfang 96 dB). Im rechten Ohr ist die 8-Bit Stufenquantisierung mit typischem Amiga-Klang (48 dB) zu hören.

---

### Test 3: Hardware Biquad Filter-Sweep & Stereo-Routing (`Test3_FilterSweep`)
- **Ziel:** Verifikation der 2nd-Order Biquad IIR Filterengine und der unabhängigen Stereo-Routing Matrix.
- **Registerkonfiguration:**
  - Kanal 0 spielt einen obertonreichen 16-Bit Sägezahn.
  - `AUD0CTRL = $0101` (`CTRL_PCM16 | CTRL_FLT_L`): Bit 8:7 = `10` weist das Filter **nur dem linken Stereokanal** zu. Der rechte Kanal wird im Bypass durchgereicht!
  - Die Biquad-Koeffizienten werden auf das klassische Amiga 500 LED-Tiefpassfilter (3.2 kHz, Butterworth $Q = 0.707$) gesetzt:
    - $b_0 = \$031F, \quad b_1 = \$063E, \quad b_2 = \$031F$
    - $a_1 = \$B335, \quad a_2 = \$1972$
- **Verifikation:** Im linken Kopfhörer ist der dumpfe, analog gefilterte Sägezahn zu hören; im rechten Kopfhörer gleichzeitig der ungefilterte, höhenreiche Rohsound zum direkten Vergleich.

---

### Test 4: Parallele Filterbank / 3-Band Equalizer (`Test4_ParallelFilterbank`)
- **Ziel:** Prüfung von `INPUT_SRC = 01` (Pre-Filter Signal von Kanal $n-1$).
- **Architektur & Signalfluss:**
  ```
               +------------------------------------------------------+
               | Kanal 0: Sägezahn-Quelle (MUTE_MIX = 1, stumm)       |
               +------------------------------------------------------+
                    |                       |                      |
            (Pre-Filter Ch 0)       (Pre-Filter Ch 0)      (Pre-Filter Ch 0)
                    v                       v                      v
             +--------------+        +--------------+       +--------------+
             | Kanal 1      |        | Kanal 2      |       | Kanal 3      |
             | Tiefpass     |        | Bandpass     |       | Hochpass     |
             | Bass (Links) |        | Mitten (Mid) |       | Höhen (Recht)|
             +--------------+        +--------------+       +--------------+
  ```
- **Registerkonfiguration:**
  - **Kanal 0:** `AUD0CTRL = $2001` (`PCM16 = 1`, `MUTE_MIX = 1`). Gibt keinen Ton in den Master-Mix aus.
  - **Kanal 1:** `AUD1CTRL = $0381` (`INPUT_SRC = 01`, `FLT_BOTH = 11`, `PCM16 = 1`). Koeffizienten: Tiefpass 500 Hz. Lautstärke links voll (`$FF00`).
  - **Kanal 2:** `AUD2CTRL = $0381` (`INPUT_SRC = 01`, `FLT_BOTH = 11`, `PCM16 = 1`). Koeffizienten: Bandpass 2.0 kHz. Lautstärke mitte (`$A0A0`).
  - **Kanal 3:** `AUD3CTRL = $0381` (`INPUT_SRC = 01`, `FLT_BOTH = 11`, `PCM16 = 1`). Koeffizienten: Hochpass 5.0 kHz. Lautstärke rechts voll (`$00FF`).
- **Verifikation:** Der Rohsound von Kanal 0 wird ohne DMA-Zugriff von Kanälen 1, 2 und 3 übernommen, frequenzmäßig in 3 Bänder aufgespalten und im Stereopanorama verteilt ausgegeben.

---

### Test 5: Serielle Moog-Filterkaskade 48 dB / Oktave (`Test5_SerialCascade_48dB`)
- **Ziel:** Prüfung von `INPUT_SRC = 10` (Post-Filter Signal von Kanal $n-1$).
- **Architektur:**
  $$\text{Ch } 0 \xrightarrow{12\,\text{dB}} \text{Ch } 1 \xrightarrow{24\,\text{dB}} \text{Ch } 2 \xrightarrow{36\,\text{dB}} \text{Ch } 3 \xrightarrow{48\,\text{dB}} \text{Master-Mix}$$
- **Registerkonfiguration:**
  - Kanäle 0, 1, 2 haben `MUTE_MIX = 1` gesetzt (keine Zwischenausgabe).
  - Kanal 1 greift Post-Filter Ch 0 ab (`INPUT_SRC = 10`).
  - Kanal 2 greift Post-Filter Ch 1 ab (`INPUT_SRC = 10`).
  - Kanal 3 greift Post-Filter Ch 2 ab (`INPUT_SRC = 10`), `MUTE_MIX = 0` und Lautstärke `$FFFF`.
  - Alle vier Stufen nutzen ein identisches 12-dB Tiefpassfilter.
- **Verifikation:** Ein extrem steilflankiges 48 dB / Oktave Analogfilter (äquivalent zu einer 8-Pol bzw. doppelten Moog-Kaskade). Oberhalb der Cutoff-Frequenz werden alle Harmonischen komplett ausgelöscht.

---

### Test 6: Hardware Amplitude Modulation / Tremolo (`Test6_AM_Tremolo`)
- **Ziel:** Prüfung der unipolaren Amplitudenmodulation (`MOD_MODE = 01`).
- **Registerkonfiguration:**
  - **Kanal 0 (Träger):** 440 Hz Sinus, `AUD0CTRL = $2001` (`MUTE_MIX = 1`).
  - **Kanal 1 (Modulator):** 5 Hz Sinus LFO (`AUD1PER = 65000`). `AUD1CTRL = $0801` (`MOD_MODE = 01`, AM).
- **Funktionsweise:**
  Die Hardware multipliziert das Trägersignal von Kanal 0 mit dem vorzeichenlosen Wert (0..255) des Modulators:
  $$\text{Signal}_{\text{Out}} = \text{Sample}_{\text{Ch0}} \times \frac{\text{LFO}_{\text{Ch1}} + 32768}{65536}$$
- **Verifikation:** Ein gleichmäßiges, weiches Pulsieren der Lautstärke (klassisches Röhren-Tremolo) ohne Klick- oder Phasengeräusche.

---

### Test 7: Hardware Ringmodulation (`Test7_Ringmodulation`)
- **Ziel:** Prüfung der bipolaren 4-Quadranten-Ringmodulation (`MOD_MODE = 10`).
- **Registerkonfiguration:**
  - **Kanal 0:** 440 Hz Sinuston, `MUTE_MIX = 1`.
  - **Kanal 1:** 330 Hz Sinuston, `AUD1CTRL = $1001` (`MOD_MODE = 10`, Ringmod).
- **Funktionsweise:**
  $$y[n] = \frac{x_0[n] \times x_1[n]}{32768}$$
  Erzeugt die reinen Seitenbänder $f_1 + f_2 = 770\,\text{Hz}$ und $|f_1 - f_2| = 110\,\text{Hz}$ bei vollständiger Unterdrückung der Trägerfrequenzen.
- **Verifikation:** Typischer metallischer Sci-Fi-Klang (Dalek-Roboterstimmen, Glocken, Gongs).

---

### Test 8: Zero-RAM Start-Delay / Stereo Echo (`Test8_StartDelayEcho`)
- **Ziel:** Verifikation des hardwarenahen SSRAM-basierten Start-Delay-Zählers (`AUDxDELAY`).
- **Registerkonfiguration:**
  - Alle drei Kanäle greifen auf denselben kurzen Nadelimpuls (`ImpulseSample`) zu.
  - **Kanal 0:** `AUD0DELAY = 0` (Sofortstart, 0 ms, Links).
  - **Kanal 1:** `AUD1DELAY = 4096` ($4096 \times 30{,}517\,\mu\text{s} = 125\,\text{ms}$, Rechts).
  - **Kanal 2:** `AUD2DELAY = 8192` ($8192 \times 30{,}517\,\mu\text{s} = 250\,\text{ms}$, Links mit Tiefpass).
- **Verifikation:** Perfektes Stereo-Ping-Pong-Echo ohne ein einziges Byte Ringpuffer-Speicher im Amiga-RAM! Das Echo auf Kanal 2 klingt dank Biquad-Tiefpass wärmer wie ein analoges Band-Echo (Tape Delay).

---

### Test 9: Globales Channel 15 Interrupt-System (`Test9_InterruptSystem`)
- **Ziel:** Verifikation der Option-A Interrupt-Architektur (`$DFF5FC` und `$DFF5FE`) am Ende des Adressraums.
- **Ablauf & Registerkonfiguration:**
  1. Kanal 4 wird mit einem One-Shot Puffer (`AUD4CTRL` Bit 1 = 1) von 64 Words konfiguriert.
  2. Im globalen Interrupt-Register wird Bit 4 gesetzt:
     $$\text{move.w } \#(1 \ll 4), \$DFF5FC \quad (\text{AUD\_INTENA})$$
  3. Kanal 4 wird gestartet (`AUD4CMD = 1`).
  4. Nach dem Abspielen des 64-Word-Puffers setzt die Hardware Bit 4 in `AUD_INTREQ` (`$DFF5FE`) und triggert den Amiga Level-2 Interrupt (`INT2`).
  5. Die Interrupt Service Routine (`Audio_ISR`) liest `$DFF5FE`, erkennt Bit 4, quittiert den IRQ mit Write-1-to-Clear (`move.w #(1<<4), $DFF5FE`) und färbt den Bildschirm weiß.
- **Verifikation:** Bei jedem Durchlauf blitzt der Bildschirm auf. `AUD_INTREQ` kehrt sofort wieder auf 0 zurück.

---

## 3. Kompilierung & Ausführung

### Assemblieren mit vasm:
```bash
vasmm68k_mot -Fhunkexe -nosym audio_pipeline_test.s -o audio_pipeline_test
```

### Ausführung auf dem Amiga / Minimig:
1. Kopiere `audio_pipeline_test` auf eine Diskette oder CF-Karte / IDE-Festplatte.
2. Starte das Programm aus dem AmigaOS CLI / Shell:
   ```amiga
   1> audio_pipeline_test
   ```
3. **Bedienung:**
   - **Linke Maustaste:** Schaltet sofort zum nächsten Test.
   - **Rechte Maustaste:** Beendet das Programm sauber und stellt Copper, Interrupts und DMA für AmigaOS wieder her.
   - **Automatisch:** Wenn keine Taste gedrückt wird, wechselt das Programm alle 5 Sekunden zum nächsten Test.
