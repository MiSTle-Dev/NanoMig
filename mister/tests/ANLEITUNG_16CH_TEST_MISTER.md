# Kurzanleitung: 16-Kanal Audio-Core auf Tobys MiSTer testen

Hallo Toby und Team!

Der neue Core mit der erweiterten Audio-Pipeline ist fertig gebaut und im FPGA verifiziert. Euer bisheriger Amiga-Core bleibt dabei völlig unberührt.

---

## 1. Bereitgestellte Core-Dateien

In eurem Übergabe-Ordner liegen die fertigen Bitstream-Dateien:
- **16-Kanal Core:** [`Minimig_HAM_16CH_Audio.rbf`](file:///D:/programmier_ordner/FPGA/HAM_Uebergabe/Minimig_HAM_16CH_Audio.rbf) (4.041.324 Bytes, 16 Stimmen, 83 % ALMs, spart gegenüber Tobys altem Core 1.851 ALMs, 29 RAM-Blöcke und 4 DSPs ein).
- **32-Kanal Core (optional):** [`Minimig_HAM_32CH_Audio.rbf`](file:///D:/programmier_ordner/FPGA/HAM_Uebergabe/Minimig_HAM_32CH_Audio.rbf) (4.140.916 Bytes, 32 Stimmen mit parallelen Dual-DSP Filtern).

---

## 2. Installation auf Tobys MiSTer (Ohne den alten Core zu verändern)

1. Kopiert die Datei `Minimig_HAM_16CH_Audio.rbf` auf die MiSTer SD-Karte in das Verzeichnis:
   ```text
   /media/fat/_Computer/
   ```
2. **Tipp:** Benennt die Datei dort z. B. `Amiga_16CH.rbf`. Dadurch bleibt Tobys gewohnter Standard-Core (`Minimig.rbf`) unverändert erhalten. Im MiSTer-Hauptmenü unter **_Computer** könnt ihr dann direkt zwischen beiden Cores wählen.

---

## 3. Testprogramm & Ausführung

Das Testprogramm liegt als M68000-Assemblerdatei bereit:
- **Dateipfad:** [`audio_pipeline_16ch_test.s`](file:///D:/programmier_ordner/FPGA/HAM_Uebergabe/Tests/audio_pipeline_16ch_test.s)

Es kann mit jedem gängigen Amiga-Assembler kompiliert werden (z. B. **VASM**, **ASM-One**, **Asm-Pro** oder **PhxAss**):
```bash
vasmm68k_mot -Fhunkexe -nosym -o audio_test audio_pipeline_16ch_test.s
```

### Was das Testprogramm gezielt demonstriert:
Das Programm wechselt die Amiga-Rahmenfarbe (`COLOR00`), sodass ihr am Bildschirm genau seht, welcher Test gerade über die Lautsprecher zu hören ist:

1. **GRÜNER Rahmen (`$00F0`): 16-Stimmen Polyphonie & Stereo-Panorama**
   - Spielt alle 16 Stimmen gleichzeitig als vollen harmonischen 16-Ton-Akkord ab.
   - Demonstriert das hardwarenahe Stereo-Panning: Stimme 0 spielt 100 % Links, die mittleren Stimmen in der Stereomitte, Stimme 15 spielt 100 % Rechts.
2. **BLAUER Rahmen (`$000F`): Parallele Filterung (Biquad DSP)**
   - Stimme 2 erhält einen 1 kHz Tiefpassfilter (weicher, warmer Klang).
   - Stimme 5 erhält parallel einen resonanten Bandpassfilter.
   - Beide Stimmen laufen gleichzeitig und unabhängig durch die DSP-Filterstufe, ohne sich gegenseitig zu beeinflussen.
3. **GELBER Rahmen (`$0FF0`): Hintereinandergeschaltete Filter (24 dB Kaskade)**
   - Stimme 0 läuft durch ihren eigenen 12 dB Tiefpassfilter.
   - Stimme 1 greift das Ausgangssignal von Stimme 0 ab (`INPUT_SRC = 01`) und leitet es durch ihre eigene 12 dB Filterstufe.
   - **Ergebnis:** Steilflankige Moog-artige 24 dB/Oktave Filterkaskade zweier Stimmen in Serie!
4. **MAGENTA Rahmen (`$0F0F`): AM-Tremolo & metallische Ringmodulation**
   - Stimme 4 moduliert Stimme 5 (echtes Hardware-AM-Tremolo).
   - Stimme 6 moduliert Stimme 7 (analoge Ringmodulation).
5. **DUNKELGRÜNER Rahmen (`$0080`):**
   - Alle Tests erfolgreich beendet, Stimmen werden sauber stummgeschaltet.

---

## 4. Schnelle Registerübersicht für eigene Tests

Die 16 Stimmen liegen lückenlos im Adressbereich `$DFF400` bis `$DFF5FF` (32 Bytes pro Stimme):

- **Basisadresse Stimme $n$:** `$DFF400 + (n \times $20)`
  - Stimme 0: `$DFF400`, Stimme 1: `$DFF420`, ..., Stimme 15: `$DFF5E0`
- **Wichtigste Register pro Stimme:**
  - `+$00` / `+$02`: `AUDxPTR` – 32-Bit DMA Startadresse
  - `+$04` / `+$06`: `AUDxLEN` – 32-Bit Pufferlänge in Words (keine 128k-Grenze mehr!)
  - `+$08`: `AUDxVOL` – Lautstärke (High-Byte = Links, Low-Byte = Rechts, 0..255)
  - `+$0A`: `AUDxPER` – Periode ($f_s = 50\,\text{MHz} / \text{PER}$)
  - `+$0C`: `AUDxCTRL` – Modus:
    - Bit 0: Aktiv
    - Bits 4..3: Filter-Modus (01 = Low-Pass, 10 = High-Pass, 11 = Band-Pass)
    - Bits 6..5: **Kanal-Kaskadierung:** `00` = DMA, `01` = Nimmt gefiltertes Signal vom vorherigen Kanal
    - Bits 8..7: Biquad Stereo-Routing (`11` = Stereo Biquad aktiv)
    - Bits 10..9: Modulation (`01` = AM, `10` = Ringmod)
  - `+$10` .. `+$18`: `AUDxBQ_B0..B2, A1..A2` – 5 Biquad-Koeffizienten (Q2.14 Festkomma)
  - `+$1A`: `AUDxCMD` – Kommando (`$0001` = Start, `$0002` = Stop)

Viel Erfolg beim Ausprobieren auf Tobys MiSTer! Meldet euch gerne, wenn ihr weitere Feinabstimmungen oder Koeffizienten-Tabellen benötigt.
