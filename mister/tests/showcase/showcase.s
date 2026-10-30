; ==============================================================================
; MiSTer FPGA / Minimig-AGA: 32-Channel Audio Showcase & Demonstration Suite
; Target: Motorola 68000 / 68020 on MiSTer DE10-Nano
; Uses: 32 Hardware Voices, Cascaded Dual Biquad IIR Moog Filters,
;       AM/Ringmodulation, Zero-RAM Delay & Double-Buffered Capture ($DF8000).
; Assembler: vasmm68k_mot -Fhunk -o showcase.o showcase.s
; ==============================================================================

CUSTOM          EQU $DFF000
DMACON          EQU $096
INTENA          EQU $09A
INTREQ          EQU $09C
COLOR00         EQU $180
COLOR01         EQU $182
COP1LCH         EQU $080
COP1LCL         EQU $082
COPJMP1         EQU $088
VPOSR           EQU $004

; 32-Channel Audio Extension Base
AUDIO_EXT_BASE  EQU $DFF400
VOICE_STRIDE    EQU $20

; Per-Voice Register Offsets
AUD_PTRH        EQU $00         ; DMA Address High [23:16]
AUD_PTRL        EQU $02         ; DMA Address Low [15:0]
AUD_LENH        EQU $04         ; DMA Length High [31:16] in Bytes!
AUD_LENL        EQU $06         ; DMA Length Low [15:0] in Bytes!
AUD_VOL         EQU $08         ; Vol Left [15:8], Vol Right [7:0]
AUD_PER         EQU $0A         ; Period Divider
AUD_CTRL        EQU $0C         ; Control Register
AUD_PRED        EQU $0E         ; ADPCM Predictor / Index
AUD_BQ_B0       EQU $10         ; Biquad b0
AUD_BQ_B1       EQU $12         ; Biquad b1
AUD_BQ_B2       EQU $14         ; Biquad b2
AUD_BQ_A1       EQU $16         ; Biquad a1
AUD_BQ_A2       EQU $18         ; Biquad a2
AUD_CMD         EQU $1A         ; Command: 1=Start, 2=Stop
AUD_DELAY       EQU $1C         ; Start-Delay Counter (32.768 kHz)

; Audio Capture & Double Buffer
AUD_CAP_CTRL    EQU $DFF802     ; Capture Control & Status
CAP_BUF_A       EQU $DF8000     ; 4 KB Buffer A
CAP_BUF_B       EQU $DF9000     ; 4 KB Buffer B

; Control Bitmasken
CTRL_PCM16      EQU %0000000000000001
CTRL_LOOP       EQU %0000000000000000
CTRL_ONESHOT    EQU %0000000000000010
CTRL_STEREO     EQU %0000000000000100
CTRL_FLT_R      EQU %0000000010000000
CTRL_FLT_L      EQU %0000000100000000
CTRL_FLT_STEREO EQU %0000000110000000
CTRL_SRC_DMA    EQU %0000000000000000
CTRL_SRC_PRE    EQU %0000001000000000
CTRL_SRC_POST   EQU %0000010000000000
CTRL_MOD_AM     EQU %0000100000000000
CTRL_MOD_RING   EQU %0001000000000000

; ==============================================================================
; Code Section
; ==============================================================================
    SECTION Code,CODE

Main:
    MOVEM.L D0-D7/A0-A6,-(SP)
    LEA     CUSTOM,A6

    ; 1. Hardware sichern und initialisieren
    MOVE.W  $01C(A6),Saved_INTENA
    MOVE.W  $002(A6),Saved_DMACON
    MOVE.W  #$7FFF,INTENA(A6)       ; IRQs sperren
    MOVE.W  #$7FFF,INTREQ(A6)
    MOVE.W  #$000F,DMACON(A6)       ; Paula Audio DMA aus

    ; 2. Stimmen stummschalten
    BSR     Silence_All_Voices

    ; 3. Audio-Capture starten (Doppel-Puffer A/B)
    MOVE.W  #$0017,AUD_CAP_CTRL     ; CAPTURE_EN=1, Clear Flags & Overrun

    ; --------------------------------------------------------------------------
    ; SZENE 1: "THX / Deep Note" - 31 Stimmen polyphone Frequenz-Gleitung
    ; --------------------------------------------------------------------------
    MOVE.W  #$0003,COLOR00(A6)      ; Hintergrund dunkelblau
    BSR     Init_Scene_DeepNote

    ; Gleitphase über 300 Frames (~6 Sekunden)
    MOVE.W  #SA_GLIDE,D6
.glide_loop:
    BSR     Wait_VBL
    BSR     Update_DeepNote_Glide
    BSR     Draw_Scope_Color        ; Visualizer aus Capture-Puffer
    BTST    #6,$BFE001              ; Linke Maustaste zum Überspringen?
    BEQ.S   .exit_scene1
    DBRA    D6,.glide_loop

    ; 1 Sekunde voller Akkord
    MOVE.W  #50,D6
.hold_loop:
    BSR     Wait_VBL
    BSR     Draw_Scope_Color
    BTST    #6,$BFE001
    BEQ.S   .exit_scene1
    DBRA    D6,.hold_loop

.exit_scene1:
    BSR     Silence_All_Voices

    ; --------------------------------------------------------------------------
    ; SZENE 2: "Cyberpunk 32-Channel Synth Track"
    ; Ch 0..1:   Acid Bassline (24 dB kaskadierter Moog-Filter Sweep)
    ; Ch 2..3:   AM-modulierte Pluck-Lead
    ; Ch 4..5:   Ringmodulations-Space-Bells
    ; Ch 6..8:   Drums (Kick, Snare, HiHat)
    ; Ch 21..30: 10-stimmiges warmes Breitwand-Pad
    ; Ch 31:     Sub-Bass
    ; --------------------------------------------------------------------------
    MOVE.W  #$0000,COLOR00(A6)
    BSR     Init_Scene_Track

    ; Sequenzer-Schleife über 4 Takte (256 16tel-Steps)
    MOVE.W  #256,D6                 ; 256 Steps
    MOVEQ   #0,D5                   ; Step Counter

.track_loop:
    BSR     Process_Track_Step
    ; Jeder 16tel Step dauert 6 VBL Frames (125 BPM Shuffle)
    MOVEQ   #5,D4
.step_delay:
    BSR     Wait_VBL
    BSR     Update_Filter_LFO       ; Biquad Filter Cutoff pro Frame modulieren
    BSR     Draw_Scope_Color        ; Oszilloskop-Farbeffekt aus Audio-Capture
    BTST    #6,$BFE001              ; Maustaste beendet Showcase
    BEQ.S   .exit_showcase
    DBRA    D4,.step_delay

    ADDQ.W  #1,D5
    ANDI.W  #$003F,D5               ; Loop nach 64 Schritten
    SUBQ.W  #1,D6
    BNE.S   .track_loop

.exit_showcase:
    ; 4. System sauber zurückgeben
    BSR     Silence_All_Voices
    MOVE.W  #$0000,AUD_CAP_CTRL     ; Capture stoppen
    MOVE.W  Saved_INTENA,D0
    OR.W    #$8000,D0
    MOVE.W  D0,INTENA(A6)
    MOVE.W  Saved_DMACON,D0
    OR.W    #$8000,D0
    MOVE.W  D0,DMACON(A6)

    MOVEM.L (SP)+,D0-D7/A0-A6
    RTS

; ==============================================================================
; Subroutinen
; ==============================================================================

Silence_All_Voices:
    LEA     AUDIO_EXT_BASE,A0
    MOVEQ   #31,D0
.s_loop:
    MOVE.W  #$0002,AUD_CMD(A0)      ; STOP
    MOVE.W  #$0000,AUD_VOL(A0)      ; Mute
    MOVE.W  #$0000,AUD_CTRL(A0)
    MOVE.W  #$0000,AUD_DELAY(A0)
    LEA     VOICE_STRIDE(A0),A0
    DBRA    D0,.s_loop
    RTS

; ------------------------------------------------------------------------------
; Szene 1 Init: Startet 31 Stimmen mit Zufallsfrequenzen
; ------------------------------------------------------------------------------
Init_Scene_DeepNote:
    LEA     AUDIO_EXT_BASE,A0
    LEA     SA_StartPer,A1
    LEA     SA_Vol,A2
    LEA     SA_Delay,A3
    LEA     SA_CurPerFP,A4
    LEA     Saw32,A5
    MOVE.L  A5,D1

    MOVEQ   #30,D0                  ; 31 Stimmen (0..30)
.sa_init_loop:
    ; DMA Ptr
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A0)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A0)
    ; Länge: 32 Bytes
    MOVE.W  #0,AUD_LENH(A0)
    MOVE.W  #32,AUD_LENL(A0)

    ; Period & FP State
    MOVE.W  (A1)+,D2
    MOVE.W  D2,AUD_PER(A0)
    SWAP    D2
    CLR.W   D2                      ; D2 = Period in 16.16 FP
    MOVE.L  D2,(A4)+

    ; Volume & Start-Delay
    MOVE.W  (A2)+,AUD_VOL(A0)
    MOVE.W  (A3)+,AUD_DELAY(A0)

    ; Loop, 8-Bit PCM
    MOVE.W  #CTRL_LOOP,AUD_CTRL(A0)
    MOVE.W  #$0001,AUD_CMD(A0)      ; Starten!

    LEA     VOICE_STRIDE(A0),A0
    DBRA    D0,.sa_init_loop
    RTS

; ------------------------------------------------------------------------------
; Szene 1 Update: Gleitet alle 31 Stimmen zur Zielharmonie
; ------------------------------------------------------------------------------
Update_DeepNote_Glide:
    LEA     AUDIO_EXT_BASE,A0
    LEA     SA_Delta,A1
    LEA     SA_CurPerFP,A2
    MOVEQ   #30,D0
.glide_step:
    MOVE.L  (A2),D2
    ADD.L   (A1)+,D2                ; Period += Delta
    MOVE.L  D2,(A2)+
    SWAP    D2
    MOVE.W  D2,AUD_PER(A0)          ; Neues Period-Register
    LEA     VOICE_STRIDE(A0),A0
    DBRA    D0,.glide_step
    RTS

; ------------------------------------------------------------------------------
; Szene 2 Init: Konfiguriert die 32-Channel Synth Track Architektur
; ------------------------------------------------------------------------------
Init_Scene_Track:
    LEA     AUDIO_EXT_BASE,A0

    ; --- KANAL 0 & 1: Moog 24 dB Kaskadierter Acid-Bass ---
    ; Ch 0: Erste 12 dB Filterstufe (DMA Saw256)
    LEA     Saw256,A1
    MOVE.L  A1,D1
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A0)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A0)
    MOVE.W  #0,AUD_LENH(A0)
    MOVE.W  #256,AUD_LENL(A0)
    MOVE.W  #$9090,AUD_VOL(A0)
    MOVE.W  #(CTRL_LOOP|CTRL_FLT_STEREO|CTRL_SRC_DMA),AUD_CTRL(A0)

    ; Ch 1: Zweite 12 dB Filterstufe kaskadiert von Ch 0 (POST)
    LEA     VOICE_STRIDE(A0),A2
    MOVE.W  #0,AUD_PTRH(A2)
    MOVE.W  #0,AUD_PTRL(A2)
    MOVE.W  #0,AUD_LENH(A2)
    MOVE.W  #256,AUD_LENL(A2)
    MOVE.W  #$A0A0,AUD_VOL(A2)
    MOVE.W  #(CTRL_LOOP|CTRL_FLT_STEREO|CTRL_SRC_POST),AUD_CTRL(A2)

    ; Filterkoeffizienten initialisieren
    BSR     Set_Acid_Filter_Coeffs

    MOVE.W  #$0001,AUD_CMD(A0)      ; Ch 0 starten
    MOVE.W  #$0001,AUD_CMD(A2)      ; Ch 1 starten

    ; --- KANAL 2 & 3: AM Pluck Synth (Ch 2 moduliert Ch 3) ---
    LEA     (2*VOICE_STRIDE)(A0),A2
    LEA     EnvPluck,A1             ; Ch 2 spielt AM Envelope Sample
    MOVE.L  A1,D1
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A2)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A2)
    MOVE.W  #0,AUD_LENH(A2)
    MOVE.W  #ENV_LEN,AUD_LENL(A2)
    MOVE.W  #PER_ENV,AUD_PER(A2)
    MOVE.W  #$0000,AUD_VOL(A2)      ; Stumm im Mix (nur Carrier!)
    MOVE.W  #CTRL_ONESHOT,AUD_CTRL(A2)

    LEA     (3*VOICE_STRIDE)(A0),A3 ; Ch 3: Ton-Generator
    LEA     Saw64,A1
    MOVE.L  A1,D1
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A3)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A3)
    MOVE.W  #0,AUD_LENH(A3)
    MOVE.W  #64,AUD_LENL(A3)
    MOVE.W  #$C080,AUD_VOL(A3)
    MOVE.W  #(CTRL_LOOP|CTRL_MOD_AM),AUD_CTRL(A3)
    MOVE.W  #$0001,AUD_CMD(A3)

    ; --- KANAL 4 & 5: Ringmod Space Bells (Ch 4 moduliert Ch 5) ---
    LEA     (4*VOICE_STRIDE)(A0),A2 ; Carrier
    LEA     BellCar,A1
    MOVE.L  A1,D1
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A2)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A2)
    MOVE.W  #0,AUD_LENH(A2)
    MOVE.W  #BELLCAR_LEN,AUD_LENL(A2)
    MOVE.W  #CTRL_ONESHOT,AUD_CTRL(A2)

    LEA     (5*VOICE_STRIDE)(A0),A3 ; Ton
    LEA     Sine64,A1
    MOVE.L  A1,D1
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A3)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A3)
    MOVE.W  #0,AUD_LENH(A3)
    MOVE.W  #64,AUD_LENL(A3)
    MOVE.W  #$80C0,AUD_VOL(A3)
    MOVE.W  #(CTRL_LOOP|CTRL_MOD_RING),AUD_CTRL(A3)

    ; --- KANAL 21..30: 10-Stimmiges Pad ---
    LEA     PadVolTab,A4
    MOVEQ   #9,D0
.pad_init:
    MOVE.W  D0,D1
    ADD.W   #21,D1
    MULU.W  #VOICE_STRIDE,D1
    LEA     (A0,D1.W),A2
    LEA     Saw32,A1
    MOVE.L  A1,D2
    SWAP    D2
    MOVE.W  D2,AUD_PTRH(A2)
    SWAP    D2
    MOVE.W  D2,AUD_PTRL(A2)
    MOVE.W  #0,AUD_LENH(A2)
    MOVE.W  #32,AUD_LENL(A2)
    MOVE.W  (A4)+,AUD_VOL(A2)
    MOVE.W  #CTRL_LOOP,AUD_CTRL(A2)
    MOVE.W  #$0001,AUD_CMD(A2)
    DBRA    D0,.pad_init

    RTS

; ------------------------------------------------------------------------------
; Sequenzer Step Update
; ------------------------------------------------------------------------------
Process_Track_Step:
    LEA     AUDIO_EXT_BASE,A0

    ; 1. Kick Drum (Ch 6)
    LEA     KickPat,A1
    MOVE.W  D5,D0
    ANDI.W  #$000F,D0
    TST.B   (A1,D0.W)
    BEQ.S   .no_kick
    LEA     (6*VOICE_STRIDE)(A0),A2
    LEA     KickSmp,A3
    MOVE.L  A3,D1
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A2)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A2)
    MOVE.W  #0,AUD_LENH(A2)
    MOVE.W  #KICK_LEN,AUD_LENL(A2)
    MOVE.W  #PER_DRUM,AUD_PER(A2)
    MOVE.W  #$D0D0,AUD_VOL(A2)
    MOVE.W  #CTRL_ONESHOT,AUD_CTRL(A2)
    MOVE.W  #$0001,AUD_CMD(A2)
.no_kick:

    ; 2. Snare Drum (Ch 7)
    LEA     SnarePat,A1
    TST.B   (A1,D0.W)
    BEQ.S   .no_snare
    LEA     (7*VOICE_STRIDE)(A0),A2
    LEA     SnareSmp,A3
    MOVE.L  A3,D1
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A2)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A2)
    MOVE.W  #0,AUD_LENH(A2)
    MOVE.W  #SNARE_LEN,AUD_LENL(A2)
    MOVE.W  #PER_DRUM,AUD_PER(A2)
    MOVE.W  #$B0B0,AUD_VOL(A2)
    MOVE.W  #CTRL_ONESHOT,AUD_CTRL(A2)
    MOVE.W  #$0001,AUD_CMD(A2)
.no_snare:

    ; 3. HiHat mit HP-Filter (Ch 8)
    LEA     HatPat,A1
    TST.B   (A1,D0.W)
    BEQ.S   .no_hat
    LEA     (8*VOICE_STRIDE)(A0),A2
    LEA     HatSmp,A3
    MOVE.L  A3,D1
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A2)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A2)
    MOVE.W  #0,AUD_LENH(A2)
    MOVE.W  #HAT_LEN,AUD_LENL(A2)
    MOVE.W  #PER_DRUM,AUD_PER(A2)
    MOVE.W  #$9090,AUD_VOL(A2)
    ; Hat HP Filter Coeffs laden
    LEA     HatHP,A4
    MOVE.W  (A4)+,AUD_BQ_B0(A2)
    MOVE.W  (A4)+,AUD_BQ_B1(A2)
    MOVE.W  (A4)+,AUD_BQ_B2(A2)
    MOVE.W  (A4)+,AUD_BQ_A1(A2)
    MOVE.W  (A4)+,AUD_BQ_A2(A2)
    MOVE.W  #(CTRL_ONESHOT|CTRL_FLT_STEREO),AUD_CTRL(A2)
    MOVE.W  #$0001,AUD_CMD(A2)
.no_hat:

    ; 4. Acid Bass Pitch & Accent (Ch 0)
    LEA     AcidPerSeq,A1
    MOVE.W  D5,D0
    ADD.W   D0,D0
    MOVE.W  (A1,D0.W),D1
    BEQ.S   .no_acid
    MOVE.W  D1,AUD_PER(A0)
    MOVE.W  D1,AUD_PER+VOICE_STRIDE(A0) ; Ch 1 Kaskade auf selbe Frequenz
    LEA     AcidVolSeq,A2
    MOVE.W  (A2,D0.W),AUD_VOL+VOICE_STRIDE(A0)
.no_acid:

    ; 5. Lead Pluck Trigger (Ch 2 Carrier Neustart)
    LEA     LeadPerSeq,A1
    MOVE.W  (A1,D0.W),D1
    BEQ.S   .no_lead
    LEA     (3*VOICE_STRIDE)(A0),A3
    MOVE.W  D1,AUD_PER(A3)
    LEA     (2*VOICE_STRIDE)(A0),A2
    MOVE.W  #$0001,AUD_CMD(A2)      ; Envelope triggern
.no_lead:

    ; 6. Bell Ringmod Trigger (Ch 4 Carrier)
    LEA     BellPerSeq,A1
    MOVE.W  D5,D0
    LSL.W   #2,D0                   ; 4 Bytes pro Eintrag (2 Words)
    MOVE.W  (A1,D0.W),D1
    BEQ.S   .no_bell
    LEA     (5*VOICE_STRIDE)(A0),A3
    MOVE.W  D1,AUD_PER(A3)
    LEA     (4*VOICE_STRIDE)(A0),A2
    MOVE.W  2(A1,D0.W),AUD_PER(A2)
    MOVE.W  #$0001,AUD_CMD(A2)      ; Carrier triggern
    MOVE.W  #$0001,AUD_CMD(A3)
.no_bell:

    ; 7. Pad Akkorde (Ch 21..30)
    MOVE.W  D5,D0
    LSR.W   #4,D0                   ; Alle 16 Steps (1 Takt)
    ANDI.W  #$0003,D0
    MULU.W  #20,D0                  ; 10 Words = 20 Bytes pro Akkord
    LEA     PadPerSeq,A1
    LEA     (A1,D0.W),A1
    MOVEQ   #9,D1
.pad_update:
    MOVE.W  D1,D2
    ADD.W   #21,D2
    MULU.W  #VOICE_STRIDE,D2
    MOVE.W  (A1)+,AUD_PER(A0,D2.W)
    DBRA    D1,.pad_update

    RTS

; ------------------------------------------------------------------------------
; LFO Filter Sweep (Moog 24 dB Cutoff pro Frame modulieren)
; ------------------------------------------------------------------------------
Update_Filter_LFO:
    ADDQ.B  #1,LFO_Phase
    MOVE.B  LFO_Phase,D0
    LEA     LfoTab,A1
    MOVE.B  (A1,D0.W),D0
    ANDI.W  #$003F,D0               ; 0..63 Filter-Index

Set_Acid_Filter_Coeffs:
    MULU.W  #10,D0                  ; 5 Koeffizienten = 10 Bytes
    LEA     AcidLP1,A1
    LEA     (A1,D0.W),A1
    LEA     AcidLP2,A2
    LEA     (A2,D0.W),A2

    LEA     AUDIO_EXT_BASE,A0       ; Ch 0: Stufe 1
    MOVE.W  (A1)+,AUD_BQ_B0(A0)
    MOVE.W  (A1)+,AUD_BQ_B1(A0)
    MOVE.W  (A1)+,AUD_BQ_B2(A0)
    MOVE.W  (A1)+,AUD_BQ_A1(A0)
    MOVE.W  (A1)+,AUD_BQ_A2(A0)

    LEA     VOICE_STRIDE(A0),A3     ; Ch 1: Stufe 2 (Kaskade)
    MOVE.W  (A2)+,AUD_BQ_B0(A3)
    MOVE.W  (A2)+,AUD_BQ_B1(A3)
    MOVE.W  (A2)+,AUD_BQ_B2(A3)
    MOVE.W  (A2)+,AUD_BQ_A1(A3)
    MOVE.W  (A2)+,AUD_BQ_A2(A3)
    RTS

; ------------------------------------------------------------------------------
; Live Audio Capture Visualizer: Liest Audio-Puffer aus $DF8000
; ------------------------------------------------------------------------------
Draw_Scope_Color:
    ; Prüfe Capture-Status an $DFF802
    MOVE.W  AUD_CAP_CTRL,D0
    BTST    #1,D0                   ; Ist Block A fertig?
    BNE.S   .read_buf_a
    BTST    #2,D0                   ; Ist Block B fertig?
    BNE.S   .read_buf_b
    RTS                             ; Noch kein neuer Block

.read_buf_a:
    LEA     CAP_BUF_A,A1
    MOVE.W  #$0002,AUD_CAP_CTRL     ; W1C Quittierung Block A
    BRA.S   .render_scope
.read_buf_b:
    LEA     CAP_BUF_B,A1
    MOVE.W  #$0004,AUD_CAP_CTRL     ; W1C Quittierung Block B

.render_scope:
    ; Liest erstes 16-Bit Sample und färbt Hintergrund entsprechend Amplitude
    MOVE.W  (A1),D1                 ; 16-Bit Signed Sample
    ASR.W   #8,D1                   ; Auf 8-Bit skalieren
    ANDI.W  #$000F,D1               ; 4-Bit Farbanteil
    MOVE.W  D1,D2
    LSL.W   #4,D2
    OR.W    D1,D2
    LSL.W   #4,D2
    OR.W    D1,D2                   ; Graustufen/Farbwert $0RGB
    MOVE.W  D2,COLOR00(A6)
    RTS

; ------------------------------------------------------------------------------
; VBL Wait
; ------------------------------------------------------------------------------
Wait_VBL:
    MOVE.L  VPOSR(A6),D0
    ANDI.L  #$1FF00,D0
    CMPI.L  #$10000,D0
    BNE.S   Wait_VBL
.vbl_off:
    MOVE.L  VPOSR(A6),D0
    ANDI.L  #$1FF00,D0
    CMPI.L  #$10000,D0
    BEQ.S   .vbl_off
    RTS

; ==============================================================================
; Data Section
; ==============================================================================
    SECTION Data,DATA

Saved_INTENA:   DC.W    0
Saved_DMACON:   DC.W    0
LFO_Phase:      DC.B    0
                EVEN

; 31 Stimmen Gleitzustand für Szene 1 (16.16 Fixed Point)
SA_CurPerFP:    DS.L    31

; Generierte Musikdaten (Periods, Filter, Drum-Samples, Noten)
    INCLUDE "showcase_data.i"

    END
