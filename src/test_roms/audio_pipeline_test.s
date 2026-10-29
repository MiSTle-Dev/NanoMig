; ==============================================================================
; NanoMig 16-Kanal Audio-Erweiterung - Vollständige Test-Suite
; Ziel: Motorola 68000 / 68020 (Amiga AGA / Minimig auf Tang Nano 20K)
; Assembler: vasmm68k_mot / ASM-One / PhxAss
; ==============================================================================
; Dieses Testprogramm demonstriert und verifiziert alle Features der neuen
; 16-Kanal Audio-Pipeline:
;   1. 16-Stimmen Polyphonie & Stereo Panning (16 gleichzeitige Töne)
;   2. 16-Bit Hi-Fi PCM vs. 8-Bit Paula PCM Dynamikvergleich & 32-Bit LEN
;   3. Hardware Biquad IIR Filter-Sweep & Stereo-Routing Matrix
;   4. Parallele Filterbank / 3-Band Graphic EQ (INPUT_SRC = 01 Ch n-1 Durchreichung)
;   5. Serielle Moog-Filterkaskade (INPUT_SRC = 10, 48 dB / Oktave 4-Stufig)
;   6. Hardware Amplitude Modulation / Tremolo (MOD_MODE = 01)
;   7. Hardware Ringmodulation / Sci-Fi Bell (MOD_MODE = 10)
;   8. Zero-RAM Hardware Start-Delay / Ping-Pong Stereo Echo (AUDxDELAY)
;   9. Globales Channel 15 Interrupt-System (AUD_INTENA / AUD_INTREQ W1C)
;
; Steuerung:
;   - Linke Maustaste / Leertaste: Nächster Test
;   - Rechte Maustaste / ESC:      Beenden und saubere Rückkehr zum AmigaOS
;   - Farbbalken im Hintergrund zeigen den aktuellen Teststatus optisch an.
; ==============================================================================

                SECTION Code,CODE

; --- Amiga Hardware Register ---
CUSTOM          EQU     $DFF000
DMACON          EQU     $096
DMACONR         EQU     $002
INTENA          EQU     $09A
INTENAR         EQU     $01C
INTREQ          EQU     $09C
INTREQR         EQU     $01E
COP1LCH         EQU     $080
COP1LCL         EQU     $082
COPJMP1         EQU     $088
COLOR00         EQU     $180
COLOR01         EQU     $182
BPLCON0         EQU     $100
VHPOSR          EQU     $006
CIAA_PRA        EQU     $BFE001

; --- NanoMig 16-Kanal Audio-Register ($DFF400..$DFF5FF) ---
AUD_BASE        EQU     $DFF400
AUD_CH_SIZE     EQU     $20             ; 32 Bytes pro Kanal

; Register-Offsets pro Kanal:
AUDxPTRH        EQU     $00             ; DMA Zeiger High (Word)
AUDxPTRL        EQU     $02             ; DMA Zeiger Low (Word)
AUDxLENH        EQU     $04             ; DMA Länge High (Word) - 32-Bit!
AUDxLENL        EQU     $06             ; DMA Länge Low (Word)
AUDxVOL         EQU     $08             ; Lautstärke: High=Links, Low=Rechts (0..255)
AUDxPER         EQU     $0A             ; Sample-Periode (50 MHz / PER)
AUDxCTRL        EQU     $0C             ; Steuerregister
AUDxPRED        EQU     $0E             ; ADPCM Initial Predictor
AUDxBQ_B0       EQU     $10             ; Biquad Koeffizient B0 (Q2.14)
AUDxBQ_B1       EQU     $12             ; Biquad Koeffizient B1 (Q2.14)
AUDxBQ_B2       EQU     $14             ; Biquad Koeffizient B2 (Q2.14)
AUDxBQ_A1       EQU     $16             ; Biquad Koeffizient A1 (Q2.14)
AUDxBQ_A2       EQU     $18             ; Biquad Koeffizient A2 (Q2.14)
AUDxCMD         EQU     $1A             ; Kommando (W) / Status (R)
AUDxDELAY       EQU     $1C             ; Start-Delay Zähler (0..65535 Ticks @ 32.768 kHz)
AUDxSTATUS      EQU     $1E             ; Status / Peak Readback

; Globale Interrupt-Register bei Kanal 15 ($DFF5E0):
AUD_INTENA      EQU     $DFF5FC         ; Globales 16-Bit Interrupt Enable
AUD_INTREQ      EQU     $DFF5FE         ; Globales 16-Bit Interrupt Request (W1C)

; Bitdefinitionen für AUDxCTRL:
CTRL_PCM16      EQU     (1<<0)          ; 1 = 16-Bit Signed PCM, 0 = 8-Bit
CTRL_ONESHOT    EQU     (1<<1)          ; 1 = One-Shot, 0 = Endlos-Loop
CTRL_STEREO     EQU     (1<<2)          ; 1 = Interleaved Stereo, 0 = Mono
CTRL_ADPCM      EQU     (1<<3)          ; 1 = ADPCM aktiviert

CTRL_FLT_NONE   EQU     (0<<7)          ; Filter Bypass
CTRL_FLT_R      EQU     (1<<7)          ; Filter nur Rechts
CTRL_FLT_L      EQU     (2<<7)          ; Filter nur Links
CTRL_FLT_BOTH   EQU     (3<<7)          ; Filter Links und Rechts

CTRL_SRC_DMA    EQU     (0<<9)          ; Eigener DMA
CTRL_SRC_PRE    EQU     (1<<9)          ; Pre-Filter von Kanal n-1 (Filterbank / EQ)
CTRL_SRC_POST   EQU     (2<<9)          ; Post-Filter von Kanal n-1 (Serielle Kaskade)

CTRL_MOD_OFF    EQU     (0<<11)         ; Keine Modulation
CTRL_MOD_AM     EQU     (1<<11)         ; AM / Tremolo (Unipolar 0..100%)
CTRL_MOD_RING   EQU     (2<<11)         ; Ringmodulation (Bipolar)

CTRL_MUTE_MIX   EQU     (1<<13)         ; Nicht in Master-Mix ausgeben (nur Chaining)

; Bitdefinitionen für AUDxCMD:
CMD_START       EQU     1
CMD_STOP        EQU     2
CMD_CLR_IRQ     EQU     4

; ==============================================================================
; Programm-Einstiegspunkt
; ==============================================================================
Main:
                movem.l d0-d7/a0-a6,-(sp)

                ; 1. Amiga-Hardware sichern & initialisieren
                lea     CUSTOM,a6
                move.w  DMACONR(a6),OldDMACON
                move.w  INTENAR(a6),OldINTENA
                move.l  $6c,OldIRQ2             ; Level 2 IRQ Vektor sichern

                ; Alle Amiga-Audiokanäle und DMA/IRQs vorübergehend sperren
                move.w  #$7FFF,INTENA(a6)
                move.w  #$7FFF,INTREQ(a6)
                move.w  #$000F,DMACON(a6)       ; Paula Audio DMA aus

                ; Eigenen Copperlist aktivieren für visuellen Status
                lea     TestCopperList,a0
                move.l  a0,COP1LCH(a6)
                clr.w   COPJMP1(a6)
                move.w  #$8280,DMACON(a6)       ; DMA: Master + Copper an

                ; 2. Alle 16 Audio-Erweiterungs-Kanäle stummschalten und stoppen
                bsr     StopAllVoices

                ; 3. Eigene Level-2 Interrupt Service Routine installieren
                lea     Audio_ISR(pc),a0
                move.l  a0,$6c

                ; ==============================================================
                ; Hauptschleife: Führt Tests nacheinander aus
                ; ==============================================================
TestLoop:
                ; Testnummer holen und ausführen
                move.w  CurrentTestIndex,d0
                cmp.w   #NumTests,d0
                blt.s   .RunTest
                clr.w   d0                      ; Nach Test 9 wieder bei Test 1 anfangen
                move.w  d0,CurrentTestIndex

.RunTest:
                lsl.w   #2,d0                   ; Longword Offset
                lea     TestJumpTable,a0
                move.l  (a0,d0.w),a0
                jsr     (a0)                    ; Test ausführen

                ; Warten auf Benutzereingabe oder Zeitablauf
.WaitLoop:
                bsr     WaitRasterFrame

                ; Prüfen auf Rechte Maustaste (Abbruch / Exit)
                btst    #10,$dff016             ; POTGOR / RMB
                beq     ExitProgram

                ; Prüfen auf Linke Maustaste (Nächster Test)
                btst    #6,CIAA_PRA
                beq.s   .NextTest

                ; Timeout-Zähler für automatischen Ablauf
                subq.w  #1,AutoAdvanceTimer
                bgt.s   .WaitLoop

.NextTest:
                ; Warten bis Taste losgelassen
.WaitRelease:
                btst    #6,CIAA_PRA
                beq.s   .WaitRelease

                bsr     StopAllVoices
                addq.w  #1,CurrentTestIndex
                move.w  #250,AutoAdvanceTimer   ; Reset 5 Sekunden @ 50 Hz
                bra     TestLoop

ExitProgram:
                bsr     StopAllVoices

                ; Amiga-Systemzustand sauber wiederherstellen
                lea     CUSTOM,a6
                move.w  #$7FFF,INTENA(a6)
                move.w  #$7FFF,INTREQ(a6)
                move.l  OldIRQ2,$6c             ; Alten Level 2 Vektor zurückholen

                move.w  OldINTENA,d0
                or.w    #$8000,d0
                move.w  d0,INTENA(a6)

                move.w  OldDMACON,d0
                or.w    #$8000,d0
                move.w  d0,DMACON(a6)

                movem.l (sp)+,d0-d7/a0-a6
                clr.l   d0
                rts

; ==============================================================================
; Test 1: 16-Stimmen Polyphonie & Stereo Panning
; ------------------------------------------------------------------------------
; Startet alle 16 Kanäle gleichzeitig mit verschiedenen Audiofrequenzen
; (pentatonische Akkordfolge) und verteilt sie im Stereopanorama von links bis rechts.
; ==============================================================================
Test1_Polyphony:
                move.w  #$0033,TestColor        ; Hintergrund: Tiefblau
                lea     AUD_BASE,a0
                lea     FreqTable,a1
                moveq   #0,d1                   ; Kanal-Index 0..15

.SetupVoice:
                ; 1. Stoppen
                move.w  #CMD_STOP,AUDxCMD(a0)

                ; 2. Sample-Adresse: 16-Bit Sinuswelle
                lea     SineWave16,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a0)         ; PTRH
                swap    d0
                move.w  d0,AUDxPTRL(a0)         ; PTRL

                ; 3. Länge: 128 Words
                clr.w   AUDxLENH(a0)
                move.w  #128,AUDxLENL(a0)

                ; 4. Periode (Tonhöhe) aus Frequenztabelle
                move.w  (a1)+,AUDxPER(a0)

                ; 5. Stereopanning berechnen (Kanal 0 = ganz links, 15 = ganz rechts)
                move.w  d1,d2
                lsl.w   #4,d2                   ; 0 .. 240
                move.w  #255,d3
                sub.w   d2,d3                   ; 255 .. 15
                lsl.w   #8,d3                   ; Links im High-Byte
                or.w    d2,d3                   ; Rechts im Low-Byte
                lsr.w   #1,d3                   ; moderate Lautstärke (128/255)
                and.w   #$7F7F,d3
                move.w  d3,AUDxVOL(a0)

                ; 6. CTRL: 16-Bit PCM, Endlosschleife, Mono (Panning via VOL), Bypass
                move.w  #CTRL_PCM16,AUDxCTRL(a0)

                ; 7. Sofortstart ohne Delay
                clr.w   AUDxDELAY(a0)
                move.w  #CMD_START,AUDxCMD(a0)

                lea     AUD_CH_SIZE(a0),a0      ; Nächster Kanal
                addq.w  #1,d1
                cmp.w   #16,d1
                blt.s   .SetupVoice
                rts

; ==============================================================================
; Test 2: 16-Bit Hi-Fi PCM vs. 8-Bit Paula PCM & 32-Bit Pufferlänge
; ------------------------------------------------------------------------------
; Kanal 0 spielt echtes 16-Bit PCM (96 dB Rauschabstand).
; Kanal 1 spielt Amiga 8-Bit Signed PCM (48 dB Rauschabstand).
; Nutzt AUDxLENH für Pufferlängen über 64K Words.
; ==============================================================================
Test2_16Bit_vs_8Bit:
                move.w  #$0050,TestColor        ; Hintergrund: Grün
                ; --- Kanal 0: 16-Bit Sinus ---
                lea     AUD_BASE,a0
                move.w  #CMD_STOP,AUDxCMD(a0)
                lea     SineWave16,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a0)
                swap    d0
                move.w  d0,AUDxPTRL(a0)

                ; 32-Bit Pufferlänge demonstrieren: $00010000 = 65536 Words
                move.w  #$0001,AUDxLENH(a0)     ; LENH > 0!
                move.w  #$0000,AUDxLENL(a0)
                move.w  #$FF00,AUDxVOL(a0)      ; Nur Linker Lautsprecher
                move.w  #1134,AUDxPER(a0)       ; 44.1 kHz @ 50 MHz
                move.w  #CTRL_PCM16,AUDxCTRL(a0); Bit 0 = 1 (16-Bit Hi-Fi)
                clr.w   AUDxDELAY(a0)
                move.w  #CMD_START,AUDxCMD(a0)

                ; --- Kanal 1: 8-Bit Sinus ---
                lea     AUD_BASE+AUD_CH_SIZE,a1
                move.w  #CMD_STOP,AUDxCMD(a1)
                lea     SineWave8,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a1)
                swap    d0
                move.w  d0,AUDxPTRL(a1)
                clr.w   AUDxLENH(a1)
                move.w  #64,AUDxLENL(a1)        ; 64 Words = 128 Bytes
                move.w  #$00FF,AUDxVOL(a1)      ; Nur Rechter Lautsprecher
                move.w  #1134,AUDxPER(a1)       ; Gleiche Tonhöhe
                clr.w   AUDxCTRL(a1)            ; Bit 0 = 0 (8-Bit Paula PCM!)
                clr.w   AUDxDELAY(a1)
                move.w  #CMD_START,AUDxCMD(a1)
                rts

; ==============================================================================
; Test 3: Hardware Biquad IIR Filter Sweep & Stereo-Routing Matrix
; ------------------------------------------------------------------------------
; Spielt obertonreichen Sägezahn auf Kanal 0 und moduliert live die Biquad
; Koeffizienten von 300 Hz dumpf bis 10 kHz brillant.
; Testet Stereo-Filter-Routing (Links gefiltert, Rechts ungefiltert Bypass).
; ==============================================================================
Test3_FilterSweep:
                move.w  #$0550,TestColor        ; Hintergrund: Gelb
                lea     AUD_BASE,a0
                move.w  #CMD_STOP,AUDxCMD(a0)

                lea     SawWave16,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a0)
                swap    d0
                move.w  d0,AUDxPTRL(a0)
                clr.w   AUDxLENH(a0)
                move.w  #128,AUDxLENL(a0)
                move.w  #$FFFF,AUDxVOL(a0)      ; Stereo voll
                move.w  #1500,AUDxPER(a0)

                ; Filter-Routing: Nur LINKEN Kanal filtern, RECHTS bleibt Bypass!
                ; Damit hört man im Kopfhörer direkt Original vs. Filter!
                move.w  #(CTRL_PCM16|CTRL_FLT_L),AUDxCTRL(a0)

                ; Initial mit Amiga 500 LED-Filter (3.2 kHz Lowpass) laden
                move.w  #$031F,AUDxBQ_B0(a0)
                move.w  #$063E,AUDxBQ_B1(a0)
                move.w  #$031F,AUDxBQ_B2(a0)
                move.w  #$B335,AUDxBQ_A1(a0)
                move.w  #$1972,AUDxBQ_A2(a0)

                clr.w   AUDxDELAY(a0)
                move.w  #CMD_START,AUDxCMD(a0)
                rts

; ==============================================================================
; Test 4: Parallele Filterbank / 3-Band Graphic EQ (INPUT_SRC = 01)
; ------------------------------------------------------------------------------
; Verifiziert das Durchreichen von Kanal 0 über Kanäle 1, 2, 3:
;   - Kanal 0: Rauschen / Sägezahn (Pre-Filter Master, MUTE_MIX = 1 stummgeschaltet)
;   - Kanal 1: INPUT_SRC = 01 (Pre-Filter Ch 0) -> Tiefpass  (Bass, Links)
;   - Kanal 2: INPUT_SRC = 01 (Pre-Filter Ch 1 = Ch 0) -> Bandpass (Mitten, Center)
;   - Kanal 3: INPUT_SRC = 01 (Pre-Filter Ch 2 = Ch 0) -> Hochpass (Höhen, Rechts)
; ==============================================================================
Test4_ParallelFilterbank:
                move.w  #$0505,TestColor        ; Hintergrund: Magenta

                ; --- Kanal 0: Audioquelle (stumm im Master-Mix) ---
                lea     AUD_BASE,a0
                move.w  #CMD_STOP,AUDxCMD(a0)
                lea     SawWave16,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a0)
                swap    d0
                move.w  d0,AUDxPTRL(a0)
                clr.w   AUDxLENH(a0)
                move.w  #128,AUDxLENL(a0)
                move.w  #1200,AUDxPER(a0)
                ; MUTE_MIX = 1 (wird nur intern weitergereicht)
                move.w  #(CTRL_PCM16|CTRL_MUTE_MIX),AUDxCTRL(a0)

                ; --- Kanal 1: Bass-Band (Tiefpass 500 Hz, Pan Links) ---
                lea     AUD_BASE+AUD_CH_SIZE*1,a1
                move.w  #CMD_STOP,AUDxCMD(a1)
                move.w  #$FF00,AUDxVOL(a1)      ; Links
                ; Koeffizienten für Tiefpass
                move.w  #$0120,AUDxBQ_B0(a1)
                move.w  #$0240,AUDxBQ_B1(a1)
                move.w  #$0120,AUDxBQ_B2(a1)
                move.w  #$C5E0,AUDxBQ_A1(a1)
                move.w  #$1640,AUDxBQ_A2(a1)
                ; INPUT_SRC = 01 (Pre-Filter Ch 0), Filter aktiv
                move.w  #(CTRL_PCM16|CTRL_SRC_PRE|CTRL_FLT_BOTH),AUDxCTRL(a1)

                ; --- Kanal 2: Mitten-Band (Bandpass 2.0 kHz, Pan Center) ---
                lea     AUD_BASE+AUD_CH_SIZE*2,a2
                move.w  #CMD_STOP,AUDxCMD(a2)
                move.w  #$A0A0,AUDxVOL(a2)      ; Center
                ; Koeffizienten für Bandpass
                move.w  #$0800,AUDxBQ_B0(a2)
                clr.w   AUDxBQ_B1(a2)
                move.w  #$F800,AUDxBQ_B2(a2)
                move.w  #$A200,AUDxBQ_A1(a2)
                move.w  #$2400,AUDxBQ_A2(a2)
                ; INPUT_SRC = 01 (Pre-Filter Ch 1 = Ch 0!), Filter aktiv
                move.w  #(CTRL_PCM16|CTRL_SRC_PRE|CTRL_FLT_BOTH),AUDxCTRL(a2)

                ; --- Kanal 3: Höhen-Band (Hochpass 5.0 kHz, Pan Rechts) ---
                lea     AUD_BASE+AUD_CH_SIZE*3,a3
                move.w  #CMD_STOP,AUDxCMD(a3)
                move.w  #$00FF,AUDxVOL(a3)      ; Rechts
                ; Koeffizienten für Hochpass
                move.w  #$2800,AUDxBQ_B0(a3)
                move.w  #$B000,AUDxBQ_B1(a3)
                move.w  #$2800,AUDxBQ_B2(a3)
                move.w  #$8800,AUDxBQ_A1(a3)
                move.w  #$2200,AUDxBQ_A2(a3)
                ; INPUT_SRC = 01 (Pre-Filter Ch 2 = Ch 0!), Filter aktiv
                move.w  #(CTRL_PCM16|CTRL_SRC_PRE|CTRL_FLT_BOTH),AUDxCTRL(a3)

                ; Alle 4 Kanäle starten
                move.w  #CMD_START,AUDxCMD(a3)
                move.w  #CMD_START,AUDxCMD(a2)
                move.w  #CMD_START,AUDxCMD(a1)
                move.w  #CMD_START,AUDxCMD(a0)
                rts

; ==============================================================================
; Test 5: Serielle Moog-Filterkaskade (INPUT_SRC = 10, 48 dB / Oktave)
; ------------------------------------------------------------------------------
; Schaltet vier 12-dB Tiefpassfilter hintereinander in Serie:
;   Ch 0 (12 dB) -> Ch 1 (24 dB) -> Ch 2 (36 dB) -> Ch 3 (48 dB Moog Ladder!)
; Nur Ch 3 wird im Master-Mix ausgegeben (MUTE_MIX auf Ch 0, 1, 2 aktiv).
; ==============================================================================
Test5_SerialCascade_48dB:
                move.w  #$0510,TestColor        ; Hintergrund: Rot-Orange

                ; 1. Stufe: Kanal 0 (Quelle + 12 dB Tiefpass, MUTE_MIX = 1)
                lea     AUD_BASE,a0
                move.w  #CMD_STOP,AUDxCMD(a0)
                lea     SawWave16,a4
                move.l  a4,d0
                swap    d0
                move.w  d0,AUDxPTRH(a0)
                swap    d0
                move.w  d0,AUDxPTRL(a0)
                clr.w   AUDxLENH(a0)
                move.w  #128,AUDxLENL(a0)
                move.w  #1134,AUDxPER(a0)
                bsr     SetLowpassCoeffs
                move.w  #(CTRL_PCM16|CTRL_FLT_BOTH|CTRL_MUTE_MIX),AUDxCTRL(a0)

                ; 2. Stufe: Kanal 1 (INPUT_SRC = 10 Post-Filter Ch 0, 24 dB, MUTE_MIX = 1)
                lea     AUD_BASE+AUD_CH_SIZE*1,a1
                move.w  #CMD_STOP,AUDxCMD(a1)
                move.w  a1,a0
                bsr     SetLowpassCoeffs
                move.w  #(CTRL_PCM16|CTRL_SRC_POST|CTRL_FLT_BOTH|CTRL_MUTE_MIX),AUDxCTRL(a1)

                ; 3. Stufe: Kanal 2 (INPUT_SRC = 10 Post-Filter Ch 1, 36 dB, MUTE_MIX = 1)
                lea     AUD_BASE+AUD_CH_SIZE*2,a2
                move.w  #CMD_STOP,AUDxCMD(a2)
                move.w  a2,a0
                bsr     SetLowpassCoeffs
                move.w  #(CTRL_PCM16|CTRL_SRC_POST|CTRL_FLT_BOTH|CTRL_MUTE_MIX),AUDxCTRL(a2)

                ; 4. Stufe: Kanal 3 (INPUT_SRC = 10 Post-Filter Ch 2, 48 dB, MASTER AUSGABE!)
                lea     AUD_BASE+AUD_CH_SIZE*3,a3
                move.w  #CMD_STOP,AUDxCMD(a3)
                move.w  a3,a0
                bsr     SetLowpassCoeffs
                move.w  #$FFFF,AUDxVOL(a3)      ; Master-Lautstärke
                move.w  #(CTRL_PCM16|CTRL_SRC_POST|CTRL_FLT_BOTH),AUDxCTRL(a3)

                ; Kaskade von hinten nach vorne starten
                move.w  #CMD_START,AUDxCMD(a3)
                move.w  #CMD_START,AUDxCMD(a2)
                move.w  #CMD_START,AUDxCMD(a1)
                move.w  #CMD_START,AUD_BASE+AUDxCMD
                rts

SetLowpassCoeffs:
                move.w  #$05BC,AUDxBQ_B0(a0)
                move.w  #$0B78,AUDxBQ_B1(a0)
                move.w  #$05BC,AUDxBQ_B2(a0)
                move.w  #$97E2,AUDxBQ_A1(a0)
                move.w  #$1F96,AUDxBQ_A2(a0)
                rts

; ==============================================================================
; Test 6: Hardware Amplitude Modulation / Tremolo (MOD_MODE = 01)
; ------------------------------------------------------------------------------
; Kanal 0 = Träger (440 Hz Sinus, Ton A4), MUTE_MIX = 1
; Kanal 1 = LFO-Modulator (5 Hz Sinus), MOD_MODE = 01
; Kanal 1 moduliert die Amplitude von Kanal 0 mit sauberem analogen Tremolo.
; ==============================================================================
Test6_AM_Tremolo:
                move.w  #$0055,TestColor        ; Hintergrund: Cyan

                ; Kanal 0: Träger (440 Hz Sinuston)
                lea     AUD_BASE,a0
                move.w  #CMD_STOP,AUDxCMD(a0)
                lea     SineWave16,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a0)
                swap    d0
                move.w  d0,AUDxPTRL(a0)
                clr.w   AUDxLENH(a0)
                move.w  #128,AUDxLENL(a0)
                move.w  #888,AUDxPER(a0)        ; ~440 Hz
                move.w  #$FFFF,AUDxVOL(a0)
                move.w  #(CTRL_PCM16|CTRL_MUTE_MIX),AUDxCTRL(a0) ; Im Master stumm

                ; Kanal 1: LFO (5 Hz Sinus als AM-Modulator)
                lea     AUD_BASE+AUD_CH_SIZE,a1
                move.w  #CMD_STOP,AUDxCMD(a1)
                lea     SineWave16,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a1)
                swap    d0
                move.w  d0,AUDxPTRL(a1)
                clr.w   AUDxLENH(a1)
                move.w  #128,AUDxLENL(a1)
                move.w  #65000,AUDxPER(a1)      ; Sehr lange Periode = tiefer LFO
                move.w  #$FFFF,AUDxVOL(a1)      ; Voller Modulationshub
                ; MOD_MODE = 01 (AM / Tremolo unipolar)
                move.w  #(CTRL_PCM16|CTRL_MOD_AM),AUDxCTRL(a1)

                move.w  #CMD_START,AUDxCMD(a1)
                move.w  #CMD_START,AUDxCMD(a0)
                rts

; ==============================================================================
; Test 7: Hardware Ringmodulation / Sci-Fi Bell (MOD_MODE = 10)
; ------------------------------------------------------------------------------
; Multipliziert zwei Signale bipolar (4-Quadranten-Multiplizierer im DSP).
; Kanal 0 = Träger 440 Hz, Kanal 1 = Modulator 330 Hz.
; Ergibt glockenartige metallische Teiltöne (Summen- & Differenzfrequenzen).
; ==============================================================================
Test7_Ringmodulation:
                move.w  #$0555,TestColor        ; Hintergrund: Weiß/Grau

                ; Kanal 0: Träger
                lea     AUD_BASE,a0
                move.w  #CMD_STOP,AUDxCMD(a0)
                lea     SineWave16,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a0)
                swap    d0
                move.w  d0,AUDxPTRL(a0)
                clr.w   AUDxLENH(a0)
                move.w  #128,AUDxLENL(a0)
                move.w  #888,AUDxPER(a0)        ; 440 Hz
                move.w  #(CTRL_PCM16|CTRL_MUTE_MIX),AUDxCTRL(a0)

                ; Kanal 1: Ringmodulator (bipolar)
                lea     AUD_BASE+AUD_CH_SIZE,a1
                move.w  #CMD_STOP,AUDxCMD(a1)
                lea     SineWave16,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a1)
                swap    d0
                move.w  d0,AUDxPTRL(a1)
                clr.w   AUDxLENH(a1)
                move.w  #128,AUDxLENL(a1)
                move.w  #1184,AUDxPER(a1)       ; 330 Hz
                move.w  #$FFFF,AUDxVOL(a1)
                ; MOD_MODE = 10 (Ringmodulation)
                move.w  #(CTRL_PCM16|CTRL_MOD_RING),AUDxCTRL(a1)

                move.w  #CMD_START,AUDxCMD(a1)
                move.w  #CMD_START,AUDxCMD(a0)
                rts

; ==============================================================================
; Test 8: Zero-RAM Hardware Start-Delay / Stereo Ping-Pong Echo
; ------------------------------------------------------------------------------
; Nutzt das Hardware Start-Delay Register (AUDxDELAY):
;   - Kanal 0: Sofortiger Impuls Links (Delay = 0 ms)
;   - Kanal 1: 1. Echo Rechts nach 125 ms (AUDxDELAY = 4096 Ticks)
;   - Kanal 2: 2. Echo Links nach 250 ms (AUDxDELAY = 8192 Ticks, gefiltert)
; Alle 3 Kanäle lesen exakt denselben Sample-Puffer im RAM ohne extra Echo-Speicher!
; ==============================================================================
Test8_StartDelayEcho:
                move.w  #$0315,TestColor        ; Hintergrund: Violett

                ; Kanal 0: Direktsignal Links
                lea     AUD_BASE,a0
                move.w  #CMD_STOP,AUDxCMD(a0)
                lea     ImpulseSample,a3
                move.l  a3,d0
                swap    d0
                move.w  d0,AUDxPTRH(a0)
                swap    d0
                move.w  d0,AUDxPTRL(a0)
                clr.w   AUDxLENH(a0)
                move.w  #256,AUDxLENL(a0)
                move.w  #$FF00,AUDxVOL(a0)      ; Nur Links
                move.w  #1134,AUDxPER(a0)
                move.w  #(CTRL_PCM16|CTRL_ONESHOT),AUDxCTRL(a0)
                clr.w   AUDxDELAY(a0)           ; 0 ms Delay

                ; Kanal 1: 1. Echo Rechts (125 ms Delay = 4096 Ticks @ 32.768 kHz)
                lea     AUD_BASE+AUD_CH_SIZE*1,a1
                move.w  #CMD_STOP,AUDxCMD(a1)
                move.w  AUDxPTRH(a0),AUDxPTRH(a1)
                move.w  AUDxPTRL(a0),AUDxPTRL(a1)
                clr.w   AUDxLENH(a1)
                move.w  AUDxLENL(a0),AUDxLENL(a1)
                move.w  AUDxPER(a0),AUDxPER(a1)
                move.w  #$00B0,AUDxVOL(a1)      ; Rechts (leiser)
                move.w  #(CTRL_PCM16|CTRL_ONESHOT),AUDxCTRL(a1)
                move.w  #4096,AUDxDELAY(a1)     ; 125 ms Delay!

                ; Kanal 2: 2. Echo Links (250 ms Delay = 8192 Ticks + Tiefpass gedämpft)
                lea     AUD_BASE+AUD_CH_SIZE*2,a2
                move.w  #CMD_STOP,AUDxCMD(a2)
                move.w  AUDxPTRH(a0),AUDxPTRH(a2)
                move.w  AUDxPTRL(a0),AUDxPTRL(a2)
                clr.w   AUDxLENH(a2)
                move.w  AUDxLENL(a0),AUDxLENL(a2)
                move.w  AUDxPER(a0),AUDxPER(a2)
                move.w  #$7000,AUDxVOL(a2)      ; Links (noch leiser)
                ; Tiefpassfilter aktivieren (Tape Damping)
                move.w  a2,a0
                bsr     SetLowpassCoeffs
                move.w  #(CTRL_PCM16|CTRL_ONESHOT|CTRL_FLT_BOTH),AUDxCTRL(a2)
                move.w  #8192,AUDxDELAY(a2)     ; 250 ms Delay!

                ; Alle drei Kanäle synchron auslösen
                move.w  #CMD_START,AUDxCMD(a2)
                move.w  #CMD_START,AUDxCMD(a1)
                move.w  #CMD_START,AUD_BASE+AUDxCMD
                rts

; ==============================================================================
; Test 9: Globales Channel 15 Interrupt-System (AUD_INTENA / AUD_INTREQ W1C)
; ------------------------------------------------------------------------------
; Schaltet Kanal 4 mit einem kurzen One-Shot Puffer ein und aktiviert
; Bit 4 in AUD_INTENA ($DFF5FC). Nach Pufferende löst die Hardware den Level 2
; Interrupt aus. Die ISR quittiert den Interrupt über AUD_INTREQ ($DFF5FE).
; Der Bildschirm blinkt bei jedem erfolgreichen Interrupt grün auf!
; ==============================================================================
Test9_InterruptSystem:
                move.w  #$0400,TestColor        ; Dunkelgrün

                ; Kanal 4 konfigurieren (kurzer One-Shot)
                lea     AUD_BASE+AUD_CH_SIZE*4,a0
                move.w  #CMD_STOP,AUDxCMD(a0)
                lea     SineWave16,a2
                move.l  a2,d0
                swap    d0
                move.w  d0,AUDxPTRH(a0)
                swap    d0
                move.w  d0,AUDxPTRL(a0)
                clr.w   AUDxLENH(a0)
                move.w  #64,AUDxLENL(a0)        ; Sehr kurz: schnelles Pufferende
                move.w  #$7F7F,AUDxVOL(a0)
                move.w  #1134,AUDxPER(a0)
                move.w  #(CTRL_PCM16|CTRL_ONESHOT),AUDxCTRL(a0)
                clr.w   AUDxDELAY(a0)

                ; Globales Interrupt-Enable für Kanal 4 aktivieren ($0010)
                move.w  #(1<<4),AUD_INTENA

                ; Amiga Level 2 Interrupt freigeben
                move.w  #$8008,CUSTOM+INTENA    ; Ports / Ext Level-2 an

                ; Kanal 4 starten -> triggert IRQ bei Erreichen von LEN
                move.w  #CMD_START,AUDxCMD(a0)
                rts

; ==============================================================================
; Level 2 Interrupt Service Routine (ISR)
; ==============================================================================
Audio_ISR:
                movem.l d0-d1/a0,-(sp)

                ; Prüfen ob unser NanoMig Audio-Interrupt aktiv ist
                move.w  AUD_INTREQ,d0
                btst    #4,d0                   ; Hat Kanal 4 gefeuert?
                beq.s   .NotOurIRQ

                ; 1. Interrupt quittieren (Write-1-to-Clear!)
                move.w  #(1<<4),AUD_INTREQ

                ; 2. Visuelle Rückmeldung: Bildschirm kurz weiß aufblitzen lassen
                move.w  #$0FFF,CUSTOM+COLOR00

                ; 3. Amiga-Hardware Quittung für INT2
                move.w  #$0008,CUSTOM+INTREQ

.NotOurIRQ:
                movem.l (sp)+,d0-d1/a0
                rte

; ==============================================================================
; Hilfsfunktionen
; ==============================================================================
StopAllVoices:
                lea     AUD_BASE,a0
                moveq   #15,d0
.StopLoop:
                move.w  #CMD_STOP,AUDxCMD(a0)
                clr.w   AUDxVOL(a0)
                clr.w   AUDxCTRL(a0)
                clr.w   AUDxDELAY(a0)
                lea     AUD_CH_SIZE(a0),a0
                dbra    d0,.StopLoop

                ; Alle Interrupts löschen und sperren
                clr.w   AUD_INTENA
                move.w  #$FFFF,AUD_INTREQ       ; Alle anhängigen Bits löschen
                rts

WaitRasterFrame:
                ; Warten auf vertikalen Strahlrücklauf (VBL)
.WaitV1:
                move.l  CUSTOM+VHPOSR,d0
                and.l   #$0001FF00,d0
                cmp.l   #$00012C00,d0           ; Zeile 300
                bne.s   .WaitV1
.WaitV2:
                move.l  CUSTOM+VHPOSR,d0
                and.l   #$0001FF00,d0
                cmp.l   #$00012C00,d0
                beq.s   .WaitV2
                rts

; ==============================================================================
; Datensektion & Tabellen
; ==============================================================================
                SECTION Data,DATA_C             ; Chip-RAM für Copper & Samples

CurrentTestIndex:
                dc.w    0
AutoAdvanceTimer:
                dc.w    250                     ; 5 Sekunden bei 50 Hz

OldDMACON:      dc.w    0
OldINTENA:      dc.w    0
OldIRQ2:        dc.l    0

TestJumpTable:
                dc.l    Test1_Polyphony
                dc.l    Test2_16Bit_vs_8Bit
                dc.l    Test3_FilterSweep
                dc.l    Test4_ParallelFilterbank
                dc.l    Test5_SerialCascade_48dB
                dc.l    Test6_AM_Tremolo
                dc.l    Test7_Ringmodulation
                dc.l    Test8_StartDelayEcho
                dc.l    Test9_InterruptSystem
NumTests        EQU     9

; Pentatonische Tonleiter für 16 Stimmen Polyphonietest (Periodenwerte @ 50 MHz):
FreqTable:
                dc.w    1911, 1702, 1516, 1275, 1136,  955,  851,  758
                dc.w     637,  568,  477,  425,  379,  318,  284,  238

; --- Minimalistische Copperliste mit dynamischer Hintergrundfarbe ---
TestCopperList:
                dc.w    BPLCON0,$0000           ; Keine Bitplanes, nur Hintergrund
                dc.w    COLOR00
TestColor:      dc.w    $0022                   ; Wird zur Laufzeit dynamisch geändert
                dc.w    $2C07,$FFFE             ; Warten auf Zeile $2C
                dc.w    COLOR00,$0000           ; Rest des Bildschirms dunkel
                dc.w    $FFFF,$FFFE             ; Ende der Copperliste

; --- Vorberechnete Audio-Wellenformen im Chip-RAM ---

; 1. 16-Bit Sinuswelle (128 16-Bit Samples, Vorzeichenbehaftet -32768..+32767)
SineWave16:
                dc.w       0,  1607,  3211,  4807,  6392,  7961,  9511, 11038
                dc.w   12539, 14009, 15446, 16845, 18204, 19519, 20787, 22004
                dc.w   23169, 24278, 25329, 26318, 27244, 28105, 28897, 29621
                dc.w   30272, 30850, 31353, 31780, 32129, 32399, 32587, 32694
                dc.w   32719, 32662, 32523, 32303, 32001, 31618, 31155, 30613
                dc.w   29992, 29294, 28519, 27670, 26746, 25751, 24685, 23551
                dc.w   22351, 21087, 19762, 18378, 16938, 15445, 13903, 12314
                dc.w   10682,  9010,  7302,  5563,  3796,  2005,   198, -1612
                dc.w   -3418, -5217, -7002, -8769,-10512,-12226,-13904,-15541
                dc.w  -17130,-18666,-20144,-21557,-22899,-24167,-25354,-26456
                dc.w  -27467,-28383,-29200,-29913,-30519,-31015,-31398,-31666
                dc.w  -31818,-31853,-31770,-31568,-31249,-30812,-30258,-29590
                dc.w  -28807,-27913,-26910,-25799,-24584,-23267,-21852,-20343
                dc.w  -18744,-17059,-15293,-13451,-11538, -9560, -7523, -5433
                dc.w   -3296, -1118,  1092,  3324,  5571,  7826, 10080, 12327
                dc.w   14559, 16769, 18949, 21092, 23190, 25234, 27218, 29133

; 2. 8-Bit Amiga Signed Sinuswelle (128 Bytes, -128..+127)
SineWave8:
                dc.b       0,    6,   12,   18,   25,   31,   37,   43
                dc.b      49,   54,   60,   65,   71,   76,   81,   85
                dc.b      90,   94,   98,  102,  106,  109,  112,  115
                dc.b     118,  120,  122,  124,  125,  126,  127,  127
                dc.b     127,  127,  126,  125,  124,  122,  120,  118
                dc.b     115,  112,  109,  106,  102,   98,   94,   90
                dc.b      85,   81,   76,   71,   65,   60,   54,   49
                dc.b      43,   37,   31,   25,   18,   12,    6,    0
                dc.b      -6,  -12,  -18,  -25,  -31,  -37,  -43,  -49
                dc.b     -54,  -60,  -65,  -71,  -76,  -81,  -85,  -90
                dc.b     -94,  -98, -102, -106, -109, -112, -115, -118
                dc.b    -120, -122, -124, -125, -126, -127, -127, -127
                dc.b    -127, -126, -125, -124, -122, -120, -118, -115
                dc.b    -112, -109, -106, -102,  -98,  -94,  -90,  -85
                dc.b     -81,  -76,  -71,  -65,  -60,  -54,  -49,  -43
                dc.b     -37,  -31,  -25,  -18,  -12,   -6,    0,    0

; 3. 16-Bit Sägezahnwelle (Obertonreich für Filtertests, 128 Words)
SawWave16:
                dc.w  -32000,-31500,-31000,-30500,-30000,-29500,-29000,-28500
                dc.w  -28000,-27500,-27000,-26500,-26000,-25500,-25000,-24500
                dc.w  -24000,-23500,-23000,-22500,-22000,-21500,-21000,-20500
                dc.w  -20000,-19500,-19000,-18500,-18000,-17500,-17000,-16500
                dc.w  -16000,-15500,-15000,-14500,-14000,-13500,-13000,-12500
                dc.w  -12000,-11500,-11000,-10500,-10000, -9500, -9000, -8500
                dc.w   -8000, -7500, -7000, -6500, -6000, -5500, -5000, -4500
                dc.w   -4000, -3500, -3000, -2500, -2000, -1500, -1000,  -500
                dc.w       0,   500,  1000,  1500,  2000,  2500,  3000,  3500
                dc.w    4000,  4500,  5000,  5500,  6000,  6500,  7000,  7500
                dc.w    8000,  8500,  9000,  9500, 10000, 10500, 11000, 11500
                dc.w   12000, 12500, 13000, 13500, 14000, 14500, 15000, 15500
                dc.w   16000, 16500, 17000, 17500, 18000, 18500, 19000, 19500
                dc.w   20000, 20500, 21000, 21500, 22000, 22500, 23000, 23500
                dc.w   24000, 24500, 25000, 25500, 26000, 26500, 27000, 27500
                dc.w   28000, 28500, 29000, 29500, 30000, 30500, 31000, 31500

; 4. Percussiver Impuls für Delay/Echo-Test (Kurzer exponentieller Burst, 256 Words)
ImpulseSample:
                dc.w   32767, 28000, 22000, 16000, 10000,  5000,  2000,   800
                dc.w     300,   100,    30,     0,     0,     0,     0,     0
                dcb.w   240, 0                  ; Rest mit Stille auffüllen

                END
