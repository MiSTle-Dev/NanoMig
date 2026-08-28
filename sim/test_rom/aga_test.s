	;; aga_test.s
	;; AGA test rom for the NanoMig simulation
	;;
	;; Sets up an AGA screen: 8 bitplanes, lores, FMODE=3 (64 bit
	;; bitplane fetch via the chip48 side band), 40 vertical stripes
	;; of 8 pixels each using color indices 0..39. Indices 32..39
	;; only exist on AGA (palette bank 1). A frame counter is printed
	;; into plane 0 to show the CPU is alive.
	;;
	;; If the chip48 wide fetch path is broken, 3 of every 4 stripe
	;; columns render with corrupted plane data.

VIDMEM	EQU	2048		; plane 0, planes are 10240 bytes apart
PLSIZE	EQU	10240		; 40*256 bytes per plane
COPPER  EQU     $220		; copperlist in RAM
XPOS	EQU     $200
YPOS	EQU     $202

	;; amiga like rom header
	ORG $f80000

        bra.s   start-1   	; -1? wtf ...
        dc.w    $4ef9           ; jmp ...

        dc.l    $f80030
        dc.l    $f80008

        ORG $f80030

	;; actual code starting point
start:
        ;; wait >80ms for minimig-aga syctrl reset to be gone
        move    #60000,d0
iwlp:   dbra    d0,iwlp

	move.l  #$100,sp	; use ram below $100 as stack
	move.b	#3,$bfe201	; LED and OVL are outputs
	move.b	#2,$bfe001	; switch rom overlay off

	bsr	fillplanes
	bsr	setpalette
	bsr	startcopper

	;; print the chipset id registers once:
	;; VPOSR (Alice id in bits 14..8) and DENISEID/LISAID
	clr.w	XPOS
	move.w	#1,YPOS
	move.w	$dff004,d0
	swap	d0
	move.w	$dff07c,d0
	jsr	printlong

	;; just count ...
	clr.l	d0
prt_lp:	clr.w	XPOS
	clr.w	YPOS
	jsr 	printlong
	addq.l	#1,d0
	bra.s	prt_lp

	;; fill the 8 bitplanes with vertical stripes:
	;; byte column i (0..39) of plane p is $ff when bit p of i is set,
	;; so the 8 pixels of column i all use color index i
fillplanes:
	moveq	#0,d2		; plane number
plp:	move.l	#VIDMEM,a0
	move.l	d2,d0
	mulu	#PLSIZE,d0
	add.l	d0,a0
	move.w	#256-1,d3	; rows
rowlp:	moveq	#0,d4		; byte column
collp:	move.w	d4,d0
	move.w	d2,d1
	lsr.w	d1,d0
	and.w	#1,d0
	neg.b	d0		; 0 or $ff
	move.b	d0,(a0)+
	addq.w	#1,d4
	cmp.w	#40,d4
	bne.s	collp
	dbra	d3,rowlp
	addq.w	#1,d2
	cmp.w	#8,d2
	bne.s	plp
	rts

	;; write 40 palette entries: 32 into bank 0 and
	;; 8 into bank 1 (indices 32..39, AGA only)
setpalette:
	lea	$dff000,a5
	lea	coltab,a0
	move.w	#$0000,$106(a5)	; BPLCON3: bank 0
	lea	$180(a5),a1
	moveq	#32-1,d0
c0lp:	move.w	(a0)+,(a1)+
	dbra	d0,c0lp
	move.w	#$2000,$106(a5)	; BPLCON3: bank 1
	lea	$180(a5),a1
	moveq	#8-1,d0
c1lp:	move.w	(a0)+,(a1)+
	dbra	d0,c1lp
	move.w	#$0000,$106(a5)	; back to bank 0
	rts

startcopper:
	;; copy copper list to ram
	move.l	#(copperlist_end-copperlist)/4-1,d1
	move.l	#copperlist,a0
	move.l	#COPPER,a1
cplp:	move.l	(a0)+,(a1)+
	dbra	d1,cplp

	move.l	#COPPER,$dff080 ; load copper list
	move.w	$dff088,d0      ; start copper
	move.w	#$8380,$dff096  ; init dma controller
	move.w	#$20,$dff1dc	; PAL

	;; reset cursor
	clr.w	XPOS
	clr.w	YPOS

	rts

	IFND	FMODEVAL
FMODEVAL	EQU	3
	ENDC

copperlist:
	dc.w $01fc,FMODEVAL ; FMODE: 64 bit bitplane fetch (or 0 for 16 bit)
	dc.w $0100,$0210 ; BPLCON0: 8 bitplanes (BPU3), lores, color
	dc.w $0102,$0000 ; BPLCON1: no scroll
	dc.w $0104,$0000 ; BPLCON2
	;; with the wide fetch modes the hardware always completes full
	;; 64 bit blocks past DDFSTOP. With DDFSTRT/STOP $38/$d0 six
	;; blocks of 8 bytes are fetched per line (48 bytes) while the
	;; row is only 40 bytes wide, so a -8 modulo compensates.
	IFEQ	FMODEVAL
	dc.w $0108,$0000 ; BPL1MOD
	dc.w $010a,$0000 ; BPL2MOD
	ELSE
	dc.w $0108,$fff8 ; BPL1MOD
	dc.w $010a,$fff8 ; BPL2MOD
	ENDC
	dc.w $0092,$0038 ; display data fetch start
	dc.w $0094,$00d0 ; display data fetch stop
	dc.w $008e,$2c81 ; \__ PAL 320x256
	dc.w $0090,$2cc1 ; /
	dc.w $00e0,$0000 ; bitplane 1 (VIDMEM + 0*PLSIZE = $000800)
	dc.w $00e2,$0800
	dc.w $00e4,$0000 ; bitplane 2 ($003000)
	dc.w $00e6,$3000
	dc.w $00e8,$0000 ; bitplane 3 ($005800)
	dc.w $00ea,$5800
	dc.w $00ec,$0000 ; bitplane 4 ($008000)
	dc.w $00ee,$8000
	dc.w $00f0,$0000 ; bitplane 5 ($00a800)
	dc.w $00f2,$a800
	dc.w $00f4,$0000 ; bitplane 6 ($00d000)
	dc.w $00f6,$d000
	dc.w $00f8,$0000 ; bitplane 7 ($00f800)
	dc.w $00fa,$f800
	dc.w $00fc,$0001 ; bitplane 8 ($012000)
	dc.w $00fe,$2000

	dc.w $ffff,$fffe ; End of copperlist
copperlist_end:

	;; 40 colors: red -> yellow -> green -> cyan -> blue gradient
coltab:
	dc.w $f00,$f20,$f40,$f60,$f80,$fa0,$fc0,$fe0 ;  0.. 7
	dc.w $ff0,$df0,$bf0,$9f0,$7f0,$5f0,$3f0,$1f0 ;  8..15
	dc.w $0f0,$0f2,$0f4,$0f6,$0f8,$0fa,$0fc,$0fe ; 16..23
	dc.w $0ff,$0df,$0bf,$09f,$07f,$05f,$03f,$01f ; 24..31
	dc.w $00f,$20f,$40f,$60f,$80f,$a0f,$c0f,$f0f ; 32..39 (AGA bank 1)

	;; print long given in D0
printlong:
	swap	d0
	jsr 	printword
	swap	d0
	jsr 	printword
	rts

printword:
	movem.l	d0/d1,-(sp)
	move.w	#8,d1
	rol.w	d1,d0
	jsr 	printbyte
	rol.w	d1,d0
	jsr 	printbyte
	movem.l	(sp)+,d0/d1
	rts

printbyte:
	movem.l	d0/d1,-(sp)
	move	d0,d1
	lsr	#4,d0
	jsr 	printdigit
	move	d1,d0
	jsr 	printdigit
	movem.l	(sp)+,d0/d1
	rts

	;; print hex digit given in D0 into plane 0
printdigit:
	movem.l	d0/a0-a1,-(sp)
	move.l	#hexchars,a0
	and.l	#15,d0
	lsl	#3,d0
	add.l	d0,a0
	move.l	#VIDMEM,a1
	move	YPOS,d0
	mulu	#(8*40),d0
	add.l	d0,a1
	add	XPOS,d0
	ext.l	d0
	add.l	d0,a1
	moveq	#7,d0
pd0:	move.b	(a0)+,(a1)+
	add.l	#(40-1),a1
	dbra	d0,pd0
	add	#1,XPOS
	movem.l	(sp)+,d0/a0-a1
	rts

hexchars:
	dc.b $7C, $C6, $CE, $DE, $F6, $E6, $7C, $00   ; 0
	dc.b $30, $70, $30, $30, $30, $30, $FC, $00   ; 1
	dc.b $78, $CC, $0C, $38, $60, $CC, $FC, $00   ; 2
	dc.b $78, $CC, $0C, $38, $0C, $CC, $78, $00   ; 3
	dc.b $1C, $3C, $6C, $CC, $FE, $0C, $1E, $00   ; 4
	dc.b $FC, $C0, $F8, $0C, $0C, $CC, $78, $00   ; 5
	dc.b $38, $60, $C0, $F8, $CC, $CC, $78, $00   ; 6
	dc.b $FC, $CC, $0C, $18, $30, $30, $30, $00   ; 7
	dc.b $78, $CC, $CC, $78, $CC, $CC, $78, $00   ; 8
	dc.b $78, $CC, $CC, $7C, $0C, $18, $70, $00   ; 9
	dc.b $30, $78, $CC, $CC, $FC, $CC, $CC, $00   ; A
	dc.b $FC, $66, $66, $7C, $66, $66, $FC, $00   ; B
	dc.b $3C, $66, $C0, $C0, $C0, $66, $3C, $00   ; C
	dc.b $F8, $6C, $66, $66, $66, $6C, $F8, $00   ; D
	dc.b $FE, $62, $68, $78, $68, $62, $FE, $00   ; E
	dc.b $FE, $62, $68, $78, $68, $60, $F0, $00   ; F
