; ==============================================================================
; MiSTer FPGA / Minimig-AGA 16-Voice Audio Pipeline Test Suite
; Target: Motorola 68000 / 68020 on MiSTer DE10-Nano
; Core: Minimig_HAM_16CH_Audio.rbf
; Address Space: $DFF400 - $DFF5FF (16 Voices * 32 Bytes = 512 Bytes)
; ==============================================================================

; ------------------------------------------------------------------------------
; Amiga Custom Chip Base & Registers
; ------------------------------------------------------------------------------
CUSTOM          EQU $DFF000
DMACON          EQU $096
INTENA          EQU $09A
INTREQ          EQU $09C
COLOR00         EQU $180

; ------------------------------------------------------------------------------
; 16-Channel Audio Extension Base & Register Offsets
; ------------------------------------------------------------------------------
AUDIO_EXT_BASE  EQU $DFF400
VOICE_STRIDE    EQU $20         ; 32 Bytes per voice ($DFF400, $DFF420, ...)

; Offsets per Voice ($00..$1F)
AUD_PTRH        EQU $00         ; DMA Startadresse High (Bits 23..16)
AUD_PTRL        EQU $02         ; DMA Startadresse Low (Bits 15..0)
AUD_LENH        EQU $04         ; Pufferlänge High in Words (Bits 31..16)
AUD_LENL        EQU $06         ; Pufferlänge Low in Words (Bits 15..0)
AUD_VOL         EQU $08         ; Lautstärke: High-Byte=Links (0..255), Low-Byte=Rechts (0..255)
AUD_PER         EQU $0A         ; Sample Periode (50 MHz Teiler: Fs = 50 MHz / PER)
AUD_CTRL        EQU $0C         ; Steuerregister (Format, Filter, Input-Src, AM/Ringmod)
AUD_PRED        EQU $0E         ; ADPCM Start-Prädiktor & Schritt-Index
AUD_BQ_B0       EQU $10         ; Biquad Koeffizient b0 (Q2.14, $4000 = 1.0)
AUD_BQ_B1       EQU $12         ; Biquad Koeffizient b1 (Q2.14)
AUD_BQ_B2       EQU $14         ; Biquad Koeffizient b2 (Q2.14)
AUD_BQ_A1       EQU $16         ; Biquad Koeffizient a1 (Q2.14)
AUD_BQ_A2       EQU $18         ; Biquad Koeffizient a2 (Q2.14)
AUD_CMD         EQU $1A         ; Kommando & Status (Bit 0 = Start, Bit 1 = Stop)
AUD_DELAY       EQU $1C         ; Zero-RAM Hardware Start-Delay (32.768 kHz)
AUD_STATUS      EQU $1E         ; Kanal-Status / Peak Readback

; Global 16-Bit Interrupt Registers (an Kanal 15: $DFF5E0)
AUD_INTENA      EQU $DFF5FC     ; Kanal 15 + $1C: Global 16-Bit IRQ Enable
AUD_INTREQ      EQU $DFF5FE     ; Kanal 15 + $1E: Global 16-Bit IRQ Request (W1C)

; Control Register (AUDxCTRL) Bitmasken:
CTRL_PCM16       EQU %0000000000000001 ; Bit 0: 1 = 16-Bit Signed PCM, 0 = 8-Bit
CTRL_ONESHOT     EQU %0000000000000010 ; Bit 1: 1 = One-Shot, 0 = Loop
CTRL_STEREO      EQU %0000000000000100 ; Bit 2: 1 = Stereo, 0 = Mono
CTRL_ADPCM       EQU %0000000000001000 ; Bit 3: 1 = ADPCM, 0 = Linear
CTRL_FLT_R       EQU %0000000010000000 ; Bit 7: Filter Right Enable
CTRL_FLT_L       EQU %0000000100000000 ; Bit 8: Filter Left Enable
CTRL_FLT_STEREO  EQU %0000000110000000 ; Bits 8..7: Stereo Filter Enabled
CTRL_SRC_DMA     EQU %0000000000000000 ; Bits 10..9 = 00: DMA Input
CTRL_SRC_PRE     EQU %0000001000000000 ; Bits 10..9 = 01: Pre-Filter Cascade
CTRL_SRC_POST    EQU %0000010000000000 ; Bits 10..9 = 10: Post-Filter Cascade (Moog 24 dB)
CTRL_MOD_OFF     EQU %0000000000000000 ; Bits 12..11 = 00: None
CTRL_MOD_AM      EQU %0000100000000000 ; Bits 12..11 = 01: AM / Tremolo
CTRL_MOD_RING    EQU %0001000000000000 ; Bits 12..11 = 10: Ringmodulation
CTRL_MUTE_MIX    EQU %0010000000000000 ; Bit 13: Mute Mix

; ------------------------------------------------------------------------------
; Hauptprogramm
; ------------------------------------------------------------------------------
    SECTION Code,CODE

Main:
    MOVEM.L D0-D7/A0-A6,-(SP)
    LEA     CUSTOM,A6

    ; 1. Paula Audio-DMA und alte Interrupts stoppen
    MOVE.W  #$7FFF,INTENA(A6)
    MOVE.W  #$7FFF,INTREQ(A6)
    MOVE.W  #$000F,DMACON(A6)   ; Stoppt Paula Kanäle 0..3

    ; 2. Alle 16 neuen Stimmen initialisieren & stummschalten
    BSR     Reset_16_Voices

    ; --------------------------------------------------------------------------
    ; TEST 1: 16 Audiostimmen Polyphonie & Stereo-Panorama
    ; Rahmenfarbe: GRÜN ($00F0)
    ; Spielt alle 16 Stimmen gleichzeitig als harmonischen Akkord ab.
    ; Panorama von ganz links (Ch 0) über die Mitte (Ch 7/8) nach ganz rechts (Ch 15).
    ; --------------------------------------------------------------------------
    MOVE.W  #$00F0,COLOR00(A6)  ; Visueller Marker: GRÜN
    BSR     Test_16_Voices_Polyphony
    BSR     Wait_Two_Seconds

    ; --------------------------------------------------------------------------
    ; TEST 2: Parallele Filterung (Biquad IIR DSP-Filter auf getrennten Kanälen)
    ; Rahmenfarbe: BLAU ($000F)
    ; Kanal 2 erhält einen 1 kHz Tiefpassfilter (Low-Pass).
    ; Kanal 5 erhält einen resonanten Bandpassfilter.
    ; Beide Stimmen spielen parallel und unabhängig gefiltert.
    ; --------------------------------------------------------------------------
    MOVE.W  #$000F,COLOR00(A6)  ; Visueller Marker: BLAU
    BSR     Test_Parallel_Filters
    BSR     Wait_Two_Seconds

    ; --------------------------------------------------------------------------
    ; TEST 3: Hintereinandergeschaltete Filter (Kaskadierung / 24 dB Moog-Mode)
    ; Rahmenfarbe: GELB ($0FF0)
    ; Kanal 0 läuft durch seinen eigenen Tiefpassfilter (12 dB/Oktave).
    ; Kanal 1 greift das gefilterte Signal von Kanal 0 ab (INPUT_SRC = 01)
    ; und leitet es durch eine zweite Filterstufe (24 dB/Oktave Kaskade).
    ; --------------------------------------------------------------------------
    MOVE.W  #$0FF0,COLOR00(A6)  ; Visueller Marker: GELB
    BSR     Test_Cascaded_Filters
    BSR     Wait_Two_Seconds

    ; --------------------------------------------------------------------------
    ; TEST 4: AM-Tremolo & Ringmodulation
    ; Rahmenfarbe: MAGENTA ($0F0F)
    ; Kanal 4 moduliert Kanal 5 (AM-Tremolo-Effekt).
    ; Kanal 6 moduliert Kanal 7 (metallischer Ringmodulator-Klang).
    ; --------------------------------------------------------------------------
    MOVE.W  #$0F0F,COLOR00(A6)  ; Visueller Marker: MAGENTA
    BSR     Test_Modulation
    BSR     Wait_Two_Seconds

    ; Ende: Alle Stimmen zurücksetzen, Rahmenfarbe auf Dunkelgrün (Alles OK)
    MOVE.W  #$0080,COLOR00(A6)
    BSR     Reset_16_Voices

    MOVEM.L (SP)+,D0-D7/A0-A6
    RTS

; ==============================================================================
; Routine: Reset_16_Voices (Alle 16 Kanäle stoppen und säubern)
; ==============================================================================
Reset_16_Voices:
    MOVE.W  #$0000,AUD_INTENA
    MOVE.W  #$FFFF,AUD_INTREQ       ; Clear pending IRQs
    LEA     AUDIO_EXT_BASE,A0
    MOVEQ   #15,D0                  ; 16 Stimmen (0..15)

.rst_loop:
    MOVE.W  #$0002,AUD_CMD(A0)      ; STOP
    MOVE.W  #$0000,AUD_CTRL(A0)     ; Disabled
    MOVE.W  #$0000,AUD_VOL(A0)      ; Volume = 0
    MOVE.W  #$0000,AUD_DELAY(A0)
    MOVE.W  #$0000,AUD_LENH(A0)
    MOVE.W  #$0000,AUD_LENL(A0)
    LEA     VOICE_STRIDE(A0),A0
    DBRA    D0,.rst_loop
    RTS

; ==============================================================================
; Test 1: 16 Stimmen Polyphonie mit Stereo-Panning
; ==============================================================================
Test_16_Voices_Polyphony:
    LEA     AUDIO_EXT_BASE,A0
    LEA     Sample_Sine_16Bit,A1
    MOVE.L  A1,D1                   ; DMA Adresse

    MOVEQ   #0,D0                   ; Kanal 0..15
    MOVE.W  #$0380,D2               ; Grundperiode (~44.1 kHz Bereich)

.poly_loop:
    ; 32-Bit DMA Sample-Adresse setzen
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A0)
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A0)

    ; Pufferlänge: 128 Words (256 Bytes)
    MOVE.W  #$0000,AUD_LENH(A0)
    MOVE.W  #$0080,AUD_LENL(A0)

    ; Stereo-Panning berechnen:
    ; Links  = (15 - Ch) * 16
    ; Rechts = Ch * 16
    MOVE.W  #15,D3
    SUB.W   D0,D3
    LSL.W   #4,D3                   ; 0..240
    LSL.W   #8,D3                   ; Ins High-Byte
    MOVE.W  D0,D4
    LSL.W   #4,D4                   ; Ins Low-Byte
    OR.W    D4,D3
    MOVE.W  D3,AUD_VOL(A0)

    ; Frequenz variieren (jeder Kanal spielt einen eigenen Halbton/Oberton)
    MOVE.W  D2,AUD_PER(A0)
    ADD.W   #$0020,D2

    ; Format: 16-Bit PCM, Endlos-Loop, Stimme aktiv
    MOVE.W  #CTRL_PCM16,AUD_CTRL(A0)

    ; Stimme starten
    MOVE.W  #$0001,AUD_CMD(A0)

    LEA     VOICE_STRIDE(A0),A0
    ADDQ.W  #1,D0
    CMP.W   #16,D0
    BNE.S   .poly_loop
    RTS

; ==============================================================================
; Test 2: Parallele Filterung (Biquad DSP Filter auf Kanal 2 und Kanal 5)
; ==============================================================================
Test_Parallel_Filters:
    ; --- Kanal 2: Tiefpassfilter (1 kHz Cutoff @ 48 kHz, Q=0.707) ---
    LEA     AUDIO_EXT_BASE+(2*VOICE_STRIDE),A0
    MOVE.W  #$08A0,AUD_BQ_B0(A0)    ; b0
    MOVE.W  #$1140,AUD_BQ_B1(A0)    ; b1
    MOVE.W  #$08A0,AUD_BQ_B2(A0)    ; b2
    MOVE.W  #$27A0,AUD_BQ_A1(A0)    ; a1
    MOVE.W  #$1320,AUD_BQ_A2(A0)    ; a2
    ; AUDxCTRL: Biquad Stereo aktiv (Bits 8..7 = 11), Voice aktiv (Bit 0 = 1)
    MOVE.W  #(CTRL_PCM16|CTRL_FLT_STEREO),AUD_CTRL(A0)

    ; --- Kanal 5: Bandpassfilter (2.5 kHz Center) ---
    LEA     AUDIO_EXT_BASE+(5*VOICE_STRIDE),A0
    MOVE.W  #$1200,AUD_BQ_B0(A0)    ; b0
    MOVE.W  #$0000,AUD_BQ_B1(A0)    ; b1
    MOVE.W  #$EE00,AUD_BQ_B2(A0)    ; b2 (-b0)
    MOVE.W  #$2100,AUD_BQ_A1(A0)    ; a1
    MOVE.W  #$0C00,AUD_BQ_A2(A0)    ; a2
    ; AUDxCTRL: Biquad Stereo aktiv (Bits 8..7 = 11), Voice aktiv
    MOVE.W  #(CTRL_PCM16|CTRL_FLT_STEREO),AUD_CTRL(A0)
    RTS

; ==============================================================================
; Test 3: Hintereinandergeschaltete Filter (Filter-Kaskadierung / Moog 24 dB)
; ==============================================================================
Test_Cascaded_Filters:
    ; Kanal 0: Filterstufe 1 (12 dB Resonant Low-Pass)
    LEA     AUDIO_EXT_BASE+(0*VOICE_STRIDE),A0
    MOVE.W  #$0C00,AUD_BQ_B0(A0)
    MOVE.W  #$1800,AUD_BQ_B1(A0)
    MOVE.W  #$0C00,AUD_BQ_B2(A0)
    MOVE.W  #$2400,AUD_BQ_A1(A0)
    MOVE.W  #$1100,AUD_BQ_A2(A0)
    MOVE.W  #(CTRL_PCM16|CTRL_FLT_STEREO),AUD_CTRL(A0) ; Input = DMA, Biquad = An

    ; Kanal 1: Filterstufe 2 (Kaskade von Kanal 0, INPUT_SRC = 01)
    LEA     AUDIO_EXT_BASE+(1*VOICE_STRIDE),A0
    MOVE.W  #$0C00,AUD_BQ_B0(A0)
    MOVE.W  #$1800,AUD_BQ_B1(A0)
    MOVE.W  #$0C00,AUD_BQ_B2(A0)
    MOVE.W  #$2400,AUD_BQ_A1(A0)
    MOVE.W  #$1100,AUD_BQ_A2(A0)
    ; AUDxCTRL:
    ; Bit 6..5 = 01  -> Greift das gefilterte Signal von Kanal 0 ab
    ; Bit 8..7 = 11  -> Eigene Biquad-Filterstufe aktiv (ergibt 24 dB Filterung!)
    ; Bit 0    = 1   -> Aktiv
    MOVE.W  #(CTRL_PCM16|CTRL_FLT_STEREO|CTRL_SRC_PRE),AUD_CTRL(A0)
    MOVE.W  #$FFFF,AUD_VOL(A0)      ; Volle Stereo-Lautstärke
    MOVE.W  #$0001,AUD_CMD(A0)      ; Startet Kaskade
    RTS

; ==============================================================================
; Test 4: Hardware Modulation (AM-Tremolo und Ringmodulation)
; ==============================================================================
Test_Modulation:
    ; Kanal 4 moduliert Kanal 5 (AM Tremolo)
    LEA     AUDIO_EXT_BASE+(5*VOICE_STRIDE),A0
    ; Bits 10..9 = 01 (AM / Tremolo aktiviert)
    MOVE.W  #(CTRL_PCM16|CTRL_MOD_AM),AUD_CTRL(A0)

    ; Kanal 6 moduliert Kanal 7 (Ringmodulation)
    LEA     AUDIO_EXT_BASE+(7*VOICE_STRIDE),A0
    ; Bits 10..9 = 10 (Ringmodulation aktiviert)
    MOVE.W  #(CTRL_PCM16|CTRL_MOD_RING),AUD_CTRL(A0)
    RTS

; ==============================================================================
; Hilfsroutine: Wait_Two_Seconds (100 VBL Frames @ 50 Hz PAL)
; ==============================================================================
Wait_Two_Seconds:
    MOVE.W  #100,D7
.vbl_wait:
    MOVE.L  CUSTOM+$004,D0
    ANDI.L  #$1FF00,D0
    CMP.I   #$10000,D0
    BNE.S   .vbl_wait
.vbl_off:
    MOVE.L  CUSTOM+$004,D0
    ANDI.L  #$1FF00,D0
    CMP.I   #$10000,D0
    BEQ.S   .vbl_off
    DBRA    D7,.vbl_wait
    RTS

; ------------------------------------------------------------------------------
; Sample-Daten: 128 Words 16-Bit Hi-Fi Sinuswelle
; ------------------------------------------------------------------------------
    SECTION Data,DATA
    CNOP    0,4

Sample_Sine_16Bit:
    DC.W    $0000,$0647,$0C8B,$12C7,$18F8,$1F19,$2527,$2B1E
    DC.W    $30FA,$36B9,$3C56,$41CD,$471C,$4C3F,$5133,$55F4
    DC.W    $5A81,$5ED6,$62F1,$66CE,$6A6C,$6DC9,$70E1,$73B4
    DC.W    $7640,$7883,$7A7C,$7C29,$7D89,$7E9C,$7F61,$7FD7
    DC.W    $7FFF,$7FD7,$7F61,$7E9C,$7D89,$7C29,$7A7C,$7883
    DC.W    $7640,$73B4,$70E1,$6DC9,$6A6C,$66CE,$62F1,$5ED6
    DC.W    $5A81,$55F4,$5133,$4C3F,$471C,$41CD,$3C56,$36B9
    DC.W    $30FA,$2B1E,$2527,$1F19,$18F8,$12C7,$0C8B,$0647
    DC.W    $0000,$F9B9,$F375,$ED39,$E708,$E0E7,$DAD9,$D4E2
    DC.W    $CF06,$C947,$C3AA,$BE33,$B8E4,$B3C1,$AECC,$AA0C
    DC.W    $A57F,$A12A,$9D0F,$9932,$9594,$9237,$8F1F,$8C4C
    DC.W    $89C0,$877D,$8584,$83D7,$8277,$8164,$809F,$8029
    DC.W    $8001,$8029,$809F,$8164,$8277,$83D7,$8584,$877D
    DC.W    $89C0,$8C4C,$8F1F,$9237,$9594,$9932,$9D0F,$A12A
    DC.W    $A57F,$AA0C,$AECC,$B3C1,$B8E4,$BE33,$C3AA,$C947
    DC.W    $CF06,$D4E2,$DAD9,$E0E7,$E708,$ED39,$F375,$F9B9

    END
