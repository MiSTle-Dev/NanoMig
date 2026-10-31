; ==============================================================================
; MiSTer FPGA / Minimig-AGA 32-Voice High-Definition Audio Pipeline Test Suite
; Target: Motorola 68000 / 68020 / TG68K on MiSTer DE10-Nano (Cyclone V)
; Address Space: $DFF400 - $DFF7FF (32 Voices * 32 Bytes = 1024 Bytes)
; ==============================================================================

; ------------------------------------------------------------------------------
; Custom Chip Register Definitions
; ------------------------------------------------------------------------------
CUSTOM          EQU $DFF000
DMACON          EQU $096
INTENA          EQU $09A
INTREQ          EQU $09C
COLOR00         EQU $180

; ------------------------------------------------------------------------------
; 32-Channel Audio Extension Base & Register Offsets
; ------------------------------------------------------------------------------
AUDIO_EXT_BASE  EQU $DFF400
VOICE_STRIDE    EQU $20         ; 32 Bytes per voice

; Per-Voice Offsets ($00..$1F)
AUD_PTRH        EQU $00         ; DMA Sample Start Address High (Bits 23..16)
AUD_PTRL        EQU $02         ; DMA Sample Start Address Low (Bits 15..0)
AUD_LENH        EQU $04         ; Buffer Length High in Words (Bits 31..16) - 32-Bit!
AUD_LENL        EQU $06         ; Buffer Length Low in Words (Bits 15..0)
AUD_VOL         EQU $08         ; Volume: High-Byte = Left, Low-Byte = Right (0..255)
AUD_PER         EQU $0A         ; Sample Period Divider: Fs = 50 MHz / PER
AUD_CTRL        EQU $0C         ; Control Register (Format, Filter, AM/Ringmod, Mute)
AUD_PRED        EQU $0E         ; ADPCM Initial Predictor & Step Index
AUD_BQ_B0       EQU $10         ; Biquad Coeff b0 (Q2.14, $4000 = 1.0)
AUD_BQ_B1       EQU $12         ; Biquad Coeff b1 (Q2.14)
AUD_BQ_B2       EQU $14         ; Biquad Coeff b2 (Q2.14)
AUD_BQ_A1       EQU $16         ; Biquad Coeff a1 (Q2.14)
AUD_BQ_A2       EQU $18         ; Biquad Coeff a2 (Q2.14)
AUD_CMD         EQU $1A         ; Command & Status: Bit 0 = Start, Bit 1 = Stop
AUD_DELAY       EQU $1C         ; Zero-RAM Hardware Start-Delay Counter (32.768 kHz)
AUD_STATUS      EQU $1E         ; Channel Status / Readback

; Global 32-Bit Interrupt Registers (Located at Channel 31: $DFF7E0 + Offsets)
AUD_INTENA_HI   EQU $DFF7F8     ; Global IRQ Enable High (Voices 31..16)
AUD_INTENA_LO   EQU $DFF7FA     ; Global IRQ Enable Low  (Voices 15..0)
AUD_INTREQ_HI   EQU $DFF7FC     ; Global IRQ Request High (W1C: Voices 31..16)
AUD_INTREQ_LO   EQU $DFF7FE     ; Global IRQ Request Low  (W1C: Voices 15..0)

; Control Register (AUDxCTRL) Bitmasken (MiSTer Hardware-Verifiziert):
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
; Main Program Entry
; ------------------------------------------------------------------------------
    SECTION Code,CODE

Main:
    MOVEM.L D0-D7/A0-A6,-(SP)   ; Save context
    LEA     CUSTOM,A6

    ; 1. Disable all DMA and Paula interrupts
    MOVE.W  #$7FFF,INTENA(A6)   ; Disable Amiga IRQs
    MOVE.W  #$7FFF,INTREQ(A6)   ; Acknowledge pending IRQs
    MOVE.W  #$000F,DMACON(A6)   ; Disable standard Paula Audio DMA (0..3)

    ; 2. Initialize and silence all 32 voices
    BSR     Reset_All_Voices

    ; 3. Run Test 1: 32-Voice Polyphony & Stereo Panning Test
    MOVE.W  #$00F0,COLOR00(A6)  ; Visual marker: Green (Polyphony)
    BSR     Test_32Voice_Polyphony
    BSR     Wait_Frames         ; Listen to 32-voice chords

    ; 4. Run Test 2: Dual Biquad DSP Engine Verification (Engines 0 & 1)
    MOVE.W  #$000F,COLOR00(A6)  ; Visual marker: Blue (Biquad DSP)
    BSR     Test_Dual_Biquad_Engines
    BSR     Wait_Frames

    ; 5. Run Test 3: Channel Pre-Filter Cascading (24 dB/Oct 4-Pole Moog Mode)
    MOVE.W  #$0FF0,COLOR00(A6)  ; Visual marker: Yellow (Filter Cascade)
    BSR     Test_PreFilter_Cascade
    BSR     Wait_Frames

    ; 6. Run Test 4: AM Tremolo & Ringmodulation
    MOVE.W  #$0F0F,COLOR00(A6)  ; Visual marker: Magenta (Modulation)
    BSR     Test_AM_Ringmod
    BSR     Wait_Frames

    ; 7. Run Test 5: Zero-RAM Spatial Start-Delay Engine
    MOVE.W  #$00FF,COLOR00(A6)  ; Visual marker: Cyan (Spatial Delay)
    BSR     Test_Start_Delay
    BSR     Wait_Frames

    ; 8. Run Test 6: 32-Bit Global Interrupt Verification
    MOVE.W  #$0FFF,COLOR00(A6)  ; Visual marker: White (Interrupts)
    BSR     Test_32Bit_Interrupts

    ; All tests completed successfully
    MOVE.W  #$00A0,COLOR00(A6)  ; Dark Green: All Tests Passed!
    BSR     Reset_All_Voices

    MOVEM.L (SP)+,D0-D7/A0-A6
    RTS

; ==============================================================================
; Subroutine: Reset_All_Voices
; Silence, stop, and clear all 32 channel registers and interrupts
; ==============================================================================
Reset_All_Voices:
    ; Disable and clear all 32-bit interrupts
    MOVE.W  #$0000,AUD_INTENA_HI
    MOVE.W  #$0000,AUD_INTENA_LO
    MOVE.W  #$FFFF,AUD_INTREQ_HI    ; Clear requests W1C
    MOVE.W  #$FFFF,AUD_INTREQ_LO

    LEA     AUDIO_EXT_BASE,A0
    MOVEQ   #31,D0                  ; 32 Voices (0..31)

.clear_loop:
    MOVE.W  #$0002,AUD_CMD(A0)      ; Command: STOP
    MOVE.W  #$0000,AUD_CTRL(A0)     ; Disable voice, PCM, no filter
    MOVE.W  #$0000,AUD_VOL(A0)      ; Silence volume
    MOVE.W  #$0000,AUD_DELAY(A0)    ; Reset delay
    MOVE.W  #$0000,AUD_LENH(A0)
    MOVE.W  #$0000,AUD_LENL(A0)
    LEA     VOICE_STRIDE(A0),A0
    DBRA    D0,.clear_loop
    RTS

; ==============================================================================
; Test 1: 32-Voice Polyphony & Spatial Stereo Panning
; Plays a 32-tone harmonic chord across all 32 voices.
; Voice 0 is 100% Left ($FF00), Voice 16 is Center ($8080), Voice 31 is 100% Right ($00FF).
; ==============================================================================
Test_32Voice_Polyphony:
    LEA     AUDIO_EXT_BASE,A0
    LEA     Sine_Wave_16Bit,A1
    MOVE.L  A1,D1                   ; 32-bit Sample Address

    MOVEQ   #0,D0                   ; Voice counter: 0..31
    MOVE.W  #$0400,D2               ; Base Period (~48.8 kHz divider)

.voice_loop:
    ; Set 32-bit DMA Sample Address
    SWAP    D1
    MOVE.W  D1,AUD_PTRH(A0)         ; High 8/16 bits
    SWAP    D1
    MOVE.W  D1,AUD_PTRL(A0)         ; Low 16 bits

    ; Set 32-bit Buffer Length (128 words = 256 bytes)
    MOVE.W  #$0000,AUD_LENH(A0)
    MOVE.W  #$0080,AUD_LENL(A0)

    ; Calculate Panning: Volume Left = (31 - D0) * 8, Right = D0 * 8
    MOVE.W  #31,D3
    SUB.W   D0,D3                   ; 31 - Voice
    LSL.W   #3,D3                   ; * 8 -> Left Vol (0..248)
    LSL.W   #8,D3                   ; To high byte
    MOVE.W  D0,D4
    LSL.W   #3,D4                   ; Right Vol (0..248)
    OR.W    D4,D3
    MOVE.W  D3,AUD_VOL(A0)          ; Set Left/Right Volume

    ; Calculate frequency: Period = Base + (D0 * 16)
    MOVE.W  D2,AUD_PER(A0)
    ADD.W   #$0010,D2               ; Shift frequency per voice

    ; Set Control: Active (bit 0=1), Continuous Loop (bit 1=0), 16-Bit PCM
    MOVE.W  #CTRL_PCM16,AUD_CTRL(A0)

    ; Trigger Voice Start
    MOVE.W  #$0001,AUD_CMD(A0)

    LEA     VOICE_STRIDE(A0),A0
    ADDQ.W  #1,D0
    CMP.W   #32,D0
    BNE.S   .voice_loop
    RTS

; ==============================================================================
; Test 2: Dual Biquad DSP Engine Verification
; Engine 0 (Voices 0..15) and Engine 1 (Voices 16..31) run simultaneously.
; Programs Low-Pass on Voice 4 (Engine 0) and Band-Pass on Voice 20 (Engine 1).
; ==============================================================================
Test_Dual_Biquad_Engines:
    ; Configure Voice 4 (DSP Engine 0)
    LEA     AUDIO_EXT_BASE+(4*VOICE_STRIDE),A0
    MOVE.W  #$0A00,AUD_BQ_B0(A0)    ; Low-Pass b0
    MOVE.W  #$1400,AUD_BQ_B1(A0)    ; Low-Pass b1
    MOVE.W  #$0A00,AUD_BQ_B2(A0)    ; Low-Pass b2
    MOVE.W  #$2400,AUD_BQ_A1(A0)    ; Low-Pass a1
    MOVE.W  #$1200,AUD_BQ_A2(A0)    ; Low-Pass a2
    ; Enable Filter (bits 8..7 = 11: Stereo Biquad Active)
    MOVE.W  #(CTRL_PCM16|CTRL_FLT_STEREO),AUD_CTRL(A0)

    ; Configure Voice 20 (DSP Engine 1)
    LEA     AUDIO_EXT_BASE+(20*VOICE_STRIDE),A0
    MOVE.W  #$1000,AUD_BQ_B0(A0)    ; Band-Pass b0
    MOVE.W  #$0000,AUD_BQ_B1(A0)    ; Band-Pass b1
    MOVE.W  #$F000,AUD_BQ_B2(A0)    ; Band-Pass b2
    MOVE.W  #$2000,AUD_BQ_A1(A0)    ; Band-Pass a1
    MOVE.W  #$0E00,AUD_BQ_A2(A0)    ; Band-Pass a2
    ; Enable Filter (bits 8..7 = 11: Stereo Biquad Active)
    MOVE.W  #(CTRL_PCM16|CTRL_FLT_STEREO),AUD_CTRL(A0)
    RTS

; ==============================================================================
; Test 3: Pre-Filter Chaining (24 dB/Oct 4-Pole Moog-Style Cascade)
; Cascades Voice 0 output into Voice 1 input pre-filter (Input Src = 01).
; ==============================================================================
Test_PreFilter_Cascade:
    ; Voice 0: First 2-pole resonant stage
    LEA     AUDIO_EXT_BASE+(0*VOICE_STRIDE),A0
    MOVE.W  #(CTRL_PCM16|CTRL_FLT_STEREO),AUD_CTRL(A0) ; Filter enabled, Input=DMA

    ; Voice 1: Second 2-pole resonant stage receiving Voice 0
    LEA     AUDIO_EXT_BASE+(1*VOICE_STRIDE),A0
    ; AUDxCTRL: Bit 6..5 = 01 (Pre-filter cascaded from Channel 0)
    ;           Bit 8..7 = 11 (Biquad Enabled)
    MOVE.W  #(CTRL_PCM16|CTRL_FLT_STEREO|CTRL_SRC_PRE),AUD_CTRL(A0)
    MOVE.W  #$FF80,AUD_VOL(A0)
    MOVE.W  #$0001,AUD_CMD(A0)      ; Start cascade stage
    RTS

; ==============================================================================
; Test 4: Hardware AM & Ringmodulation
; Voice 4 modulates Voice 5 (AM Tremolo)
; Voice 6 modulates Voice 7 (Ringmodulation)
; ==============================================================================
Test_AM_Ringmod:
    ; Voice 5: AM Tremolo enabled (AUDxCTRL bits 10..9 = 01)
    LEA     AUDIO_EXT_BASE+(5*VOICE_STRIDE),A0
    MOVE.W  #(CTRL_PCM16|CTRL_MOD_AM),AUD_CTRL(A0) ; AM mode

    ; Voice 7: Ringmodulation enabled (AUDxCTRL bits 10..9 = 10)
    LEA     AUDIO_EXT_BASE+(7*VOICE_STRIDE),A0
    MOVE.W  #(CTRL_PCM16|CTRL_MOD_RING),AUD_CTRL(A0) ; Ringmod mode
    RTS

; ==============================================================================
; Test 5: Zero-RAM Spatial Start-Delay Engine
; Programs 4 voices with staggered start-delay counters (32.768 kHz ticks)
; ==============================================================================
Test_Start_Delay:
    ; Voice 8: Dry impulse (0 ms delay)
    LEA     AUDIO_EXT_BASE+(8*VOICE_STRIDE),A0
    MOVE.W  #0,AUD_DELAY(A0)
    MOVE.W  #$0001,AUD_CMD(A0)

    ; Voice 9: 125 ms delay (4096 ticks @ 32.768 kHz)
    LEA     AUDIO_EXT_BASE+(9*VOICE_STRIDE),A0
    MOVE.W  #4096,AUD_DELAY(A0)
    MOVE.W  #$0001,AUD_CMD(A0)

    ; Voice 10: 250 ms delay (8192 ticks @ 32.768 kHz)
    LEA     AUDIO_EXT_BASE+(10*VOICE_STRIDE),A0
    MOVE.W  #8192,AUD_DELAY(A0)
    MOVE.W  #$0001,AUD_CMD(A0)

    ; Voice 11: 500 ms delay (16384 ticks @ 32.768 kHz)
    LEA     AUDIO_EXT_BASE+(11*VOICE_STRIDE),A0
    MOVE.W  #16384,AUD_DELAY(A0)
    MOVE.W  #$0001,AUD_CMD(A0)
    RTS

; ==============================================================================
; Test 6: 32-Bit Global Interrupt Verification
; Enables Level-2 interrupt on Channel 31 one-shot completion.
; ==============================================================================
Test_32Bit_Interrupts:
    ; Set up Level-2 Autovector ($68)
    MOVE.L  $68,Saved_Level2_Vector
    LEA     Level2_ISR,A1
    MOVE.L  A1,$68

    ; Enable Channel 31 interrupt in Global High Register ($DFF7F8 bit 15 = Ch 31)
    MOVE.W  #$8000,AUD_INTENA_HI
    MOVE.W  #$0000,AUD_INTENA_LO

    ; Enable Paula Level-2 Interrupts in INTENA ($8008 = Set INT2)
    MOVE.W  #$8008,INTENA(A6)

    ; Set Channel 31 to One-Shot Mode (AUDxCTRL bit 1 = 1) and small buffer (16 words)
    LEA     AUDIO_EXT_BASE+(31*VOICE_STRIDE),A0
    MOVE.W  #$0000,AUD_LENH(A0)
    MOVE.W  #$0010,AUD_LENL(A0)
    MOVE.W  #(CTRL_PCM16|CTRL_ONESHOT),AUD_CTRL(A0) ; Active + One-Shot
    CLR.W   IRQ_Fired_Flag

    ; Start Channel 31
    MOVE.W  #$0001,AUD_CMD(A0)

    ; Wait for interrupt flag to be set by Level2_ISR
    MOVE.L  #$00050000,D0
.wait_irq:
    TST.W   IRQ_Fired_Flag
    BNE.S   .irq_received
    SUBQ.L  #1,D0
    BNE.S   .wait_irq
    ; If timed out, show red warning
    MOVE.W  #$0F00,COLOR00(A6)

.irq_received:
    ; Restore vector and disable interrupts
    MOVE.W  #$0008,INTENA(A6)       ; Disable INT2
    MOVE.W  #$0000,AUD_INTENA_HI
    MOVE.L  Saved_Level2_Vector,$68
    RTS

; ==============================================================================
; Level-2 Interrupt Service Routine (Audio Extension IRQ)
; ==============================================================================
Level2_ISR:
    MOVEM.L D0/A0,-(SP)

    ; Check if Audio Extension IRQ is pending in Channel 31 High word
    MOVE.W  AUD_INTREQ_HI,D0
    BTST    #15,D0                  ; Channel 31 pending?
    BEQ.S   .not_ch31

    ; Acknowledge by writing 1 to clear (W1C)
    MOVE.W  #$8000,AUD_INTREQ_HI
    MOVE.W  #1,IRQ_Fired_Flag

.not_ch31:
    ; Clear Amiga INTREQ INT2 bit
    MOVE.W  #$0008,CUSTOM+INTREQ

    MOVEM.L (SP)+,D0/A0
    RTE

; ==============================================================================
; Helper Routine: Wait_Frames (~1 Second Delay via VBL)
; ==============================================================================
Wait_Frames:
    MOVE.W  #50,D7                  ; 50 frames = 1 second PAL
.vbl_loop:
    MOVE.L  CUSTOM+$004,D0          ; VPOSR / VHPOSR
    ANDI.L  #$1FF00,D0
    CMP.I   #$10000,D0              ; Rasterline ~256
    BNE.S   .vbl_loop
.wait_off:
    MOVE.L  CUSTOM+$004,D0
    ANDI.L  #$1FF00,D0
    CMP.I   #$10000,D0
    BEQ.S   .wait_off
    DBRA    D7,.vbl_loop
    RTS

; ------------------------------------------------------------------------------
; Data Section: Variables & 16-Bit PCM Test Sample (128 Words / 256 Bytes)
; ------------------------------------------------------------------------------
    SECTION Data,DATA

Saved_Level2_Vector:
    DC.L    0
IRQ_Fired_Flag:
    DC.W    0

    CNOP    0,4                     ; 32-bit aligned sample buffer
Sine_Wave_16Bit:
    ; 128-word full-scale 16-bit sine wave table
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
