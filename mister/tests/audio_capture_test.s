; ==============================================================================
; MiSTer FPGA Minimig-AGA: Audio Capture & Double-Buffering Test (Weg A)
; Tests: Dual 4 KB Buffers ($DF8000..$DF9FFF) & Hardware Backpressure Protection
; ==============================================================================

CUSTOM          EQU $DFF000
COLOR00         EQU $180
INTENA          EQU $09A
INTREQ          EQU $09C

; Audio Extension & Capture Registers
AUDIO_EXT_BASE  EQU $DFF400
AUD_CAP_CTRL    EQU $DFF802     ; Capture Control & Status Register
AUD_BUF_A       EQU $DF8000     ; Capture Block A (4 KB = 1024 Stereo Pairs)
AUD_BUF_B       EQU $DF9000     ; Capture Block B (4 KB = 1024 Stereo Pairs)

; AUD_CAP_CTRL Bit Definitions:
; Bit 0:    CAPTURE_EN (1 = Active, 0 = Stopped)
; Bit 1:    FLAG_BLOCK_A (1 = Block A full / ready; W1C)
; Bit 2:    FLAG_BLOCK_B (1 = Block B full / ready; W1C)
; Bit 3:    ACTIVE_BLOCK (0 = Hardware writing A, 1 = Hardware writing B)
; Bit 4:    OVERRUN_FLAG (1 = Dropped samples due to backpressure; W1C)
; Bit 5:    IRQ_EN (1 = Enable INT2)
; Bits 15..6: SAMPLE_POS (0..1023)

    SECTION Code,CODE

Main:
    MOVEM.L D0-D7/A0-A6,-(SP)
    LEA     CUSTOM,A6

    ; 1. Paula DMA & IRQs stoppen
    MOVE.W  #$7FFF,INTENA(A6)
    MOVE.W  #$7FFF,INTREQ(A6)

    ; 2. Audio-Synthesizer starten (Spielt Test-Sinus auf Stimme 0 ab)
    BSR     Start_Test_Audio

    ; --------------------------------------------------------------------------
    ; TEST 1: Capture starten & Warten auf Block A
    ; Rahmenfarbe: GELB ($0FF0)
    ; --------------------------------------------------------------------------
    MOVE.W  #$0FF0,COLOR00(A6)

    ; Capture aktivieren (Bit 0 = 1, Flags löschen)
    MOVE.W  #$0017,AUD_CAP_CTRL     ; CAPTURE_EN=1, Clear Flags A & B & Overrun

.wait_block_a:
    MOVE.W  AUD_CAP_CTRL,D0
    BTST    #1,D0                   ; Ist Block A fertig (FLAG_BLOCK_A == 1)?
    BEQ.S   .wait_block_a

    ; --------------------------------------------------------------------------
    ; TEST 2: Block A erfolgreich gefüllt!
    ; Rahmenfarbe: CYAN ($00FF)
    ; Daten aus Block A ($DF8000) lesen und verifizieren
    ; --------------------------------------------------------------------------
    MOVE.W  #$00FF,COLOR00(A6)

    LEA     AUD_BUF_A,A0
    MOVE.W  (A0)+,D1                ; Erstes Sample Links
    MOVE.W  (A0)+,D2                ; Erstes Sample Rechts

    ; Quittieren: Flag A zurücksetzen (W1C), Capture aktiv lassen
    MOVE.W  #%00000000_00000011,AUD_CAP_CTRL ; Bit 1 = 1 (Clear A), Bit 0 = 1 (En)

    ; --------------------------------------------------------------------------
    ; TEST 3: Warten auf Block B
    ; Rahmenfarbe: BLAU ($000F)
    ; --------------------------------------------------------------------------
    MOVE.W  #$000F,COLOR00(A6)

.wait_block_b:
    MOVE.W  AUD_CAP_CTRL,D0
    BTST    #2,D0                   ; Ist Block B fertig (FLAG_BLOCK_B == 1)?
    BEQ.S   .wait_block_b

    ; Block B auslesen ($DF9000)
    LEA     AUD_BUF_B,A0
    MOVE.W  (A0)+,D1
    MOVE.W  (A0)+,D2

    ; Quittieren: Flag B zurücksetzen
    MOVE.W  #%00000000_00000101,AUD_CAP_CTRL ; Bit 2 = 1 (Clear B), Bit 0 = 1 (En)

    ; --------------------------------------------------------------------------
    ; TEST 4: Hardware-Backpressure Test (Überlaufschutz)
    ; Rahmenfarbe: MAGENTA ($0F0F)
    ; Wir warten erneut auf Block A, quittieren ihn aber ABSICHTLICH NICHT!
    ; Die Hardware MUSS anhalten und darf Block A NICHT überschreiben!
    ; --------------------------------------------------------------------------
    MOVE.W  #$0F0F,COLOR00(A6)

.wait_block_a_again:
    MOVE.W  AUD_CAP_CTRL,D0
    BTST    #1,D0
    BEQ.S   .wait_block_a_again

    ; Wir merken uns den ersten Messwert von Block A
    MOVE.W  AUD_BUF_A,D3

    ; Wir warten jetzt ca. 50 ms (länger als 2 Pufferzyklen!), OHNE zu quittieren
    MOVE.L  #$00020000,D7
.busy_delay:
    SUBQ.L  #1,D7
    BNE.S   .busy_delay

    ; Prüfen: Hat die Hardware brav angehalten und OVERRUN (Bit 4) gesetzt?
    MOVE.W  AUD_CAP_CTRL,D0
    BTST    #4,D0                   ; Overrun gesetzt?
    BEQ.S   .backpressure_failed

    ; Prüfen: Wurden die Daten in Block A intakt gelassen?
    CMP.W   AUD_BUF_A,D3
    BNE.S   .backpressure_failed

    ; --------------------------------------------------------------------------
    ; TEST ERFOLGREICH: Alles perfekt!
    ; Rahmenfarbe: DUNKELGRÜN ($0080)
    ; --------------------------------------------------------------------------
    MOVE.W  #$0080,COLOR00(A6)
    BRA.S   .finish

.backpressure_failed:
    ; Fehler: ROT ($0F00)
    MOVE.W  #$0F00,COLOR00(A6)

.finish:
    ; Capture stoppen
    MOVE.W  #$0000,AUD_CAP_CTRL

    ; Audio stummschalten
    MOVE.W  #$0002,AUDIO_EXT_BASE+$1A ; STOP Voice 0

    MOVEM.L (SP)+,D0-D7/A0-A6
    RTS

; ------------------------------------------------------------------------------
; Hilfsroutine: Audio auf Stimme 0 starten
; ------------------------------------------------------------------------------
Start_Test_Audio:
    LEA     AUDIO_EXT_BASE,A0
    LEA     Test_Sine,A1
    MOVE.L  A1,D0
    SWAP    D0
    MOVE.W  D0,$00(A0)              ; PTR High
    SWAP    D0
    MOVE.W  D0,$02(A0)              ; PTR Low
    MOVE.W  #$0000,$04(A0)          ; LEN High
    MOVE.W  #$0080,$06(A0)          ; LEN Low (128 Words)
    MOVE.W  #$FFFF,$08(A0)          ; Volume Max
    MOVE.W  #$0380,$0A(A0)          ; Periode
    MOVE.W  #%00000000_00000001,$0C(A0) ; Aktiv
    MOVE.W  #$0001,$1A(A0)          ; Start
    RTS

    SECTION Data,DATA
    CNOP    0,4
Test_Sine:
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
