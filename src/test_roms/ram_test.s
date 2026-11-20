	;; ram_test.s
	;; memory test for nanomig/minimig on Tang nano 20k

	;; The ram test runs in the first 2k of kickstart rom
	;; area. With flash and sdram in place, the area behind
	;; will actually be flash content loaded into sdram

VIDMEM	EQU	2048		; start video memory at 2048
COPPER  EQU     $220		; copperlist in RAM
XPOS	EQU     $200
YPOS	EQU     $202

SUBRAM  EQU     $300
	
	ORG $f80000
	
        bra.s   start-1   	; -1? wtf ...
        dc.w    $4ef9           ; jmp ...

        dc.l    $f80030
        dc.l    $f80008 

        ORG $f80030	
start:

	;; wait >80ms for minimig-aga syctrl reset to be gone
	move 	#60000,d0
iwlp0:	dbra	d0,iwlp0
	
	move.l  #$100,sp	; use ram below $100 as stack
	move.b	#3,$bfe201	; LED and OVL are outputs
	move.b	#2,$bfe001	; switch rom overlay off

	;; a6 will not be used otherwise, so can be output later
	subq.l	#4,a6		; reset pointer to last word that was ok
	
	move.l  #$100,sp	; use ram below $100 as stack

	bsr	startcopper

	clr.l	d0
loop:
	btst.l  #9,d0
	beq.s	lon
	bset.b	#1,$bfe001	; LED off
	bra.s	cont
lon:	bclr.b	#1,$bfe001	; LED on
cont:

	add.l	#1,d0
	
	move.w	#27,XPOS
	bsr	printlong
	
	;; one d0 reaches $1000 jump into kick copy at $fc0000
	cmp.l   #$1000,d0
	bne.s	rcont
;	move.l	$fc0004,a0
;	jmp	(a0)
rcont:	
	
  	jsr 	testsub		; test stack
	bra.s	loop
	
testsub:
	move.l	#32,d1
lp:	nop
	dbra 	d1,lp
	rts

startcopper:
	;; clear screem memory
	move.l	#(320*256)/32-1,d0
	move.l	#VIDMEM,a0
cllp:	clr.l	(a0)+
	dbra 	d0,cllp
	
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

	;; test write byte enable
	;; both patterns should look the same on a
	;; big endian like the 68000
	move.l	#$cc33aa55,VIDMEM+4000
	move.b	#$cc,VIDMEM+4040
	move.b	#$33,VIDMEM+4041
	move.b	#$aa,VIDMEM+4042
	move.b	#$55,VIDMEM+4043

	;; reset cursor
	clr.w	XPOS
	clr.w	YPOS	

	;; compare both 256kBytes at $f80000 and $fc0000 which
	;; in case of kickstart 1.x should be identical
	;; exclude first 2kBytes as this is where this rom is
	move.l	#$f80000+2048,a0
	move.l	#$fc0000+2048,a1
	clr.l	d0
	move.l	#(254*1024)/4-1,d1 ; number of longs to compare
cmplp:	cmp.l	(a0)+,(a1)+
	beq.s	cmpok
	addq.l	#1,d0
cmpok:	dbra	d1,cmplp

	;; display how many long words were different
	jsr 	printlong
	add	#1,XPOS

	;; do checksum over entire second copy. This is actually the one
	;; that is executed
	move.l	#$fc0000,a0
	clr.l	d0
	move.l	#(256*1024)/4-1,d1 ; 256kBytes
sumlp:	add.l	(a0)+,d0
	dbra	d1,sumlp	
	
;	jsr 	printlong
;	add	#1,XPOS

;	move.l	a6,d0
;	jsr 	printlong
	
	;; read test long from both kick copies
	move.l	$fc0000,d0
	jsr 	printlong
	add	#1,XPOS
	
	move.l	$fc0004,d0
	jsr 	printlong
	add	#1,XPOS
	
	rts
	
copperlist:	
	dc.w $0100,$1200 ; enable one bitplane
	dc.w $0092,$003c ; display data fetch start 120
	dc.w $0094,$00d4 ; display data fetch end 424
	dc.w $008e,$2c81 ; \__ PAL 320x256
	dc.w $0090,$2cc1 ; /
	dc.w $00e0,$0000 ; bitplane 0 start hi
	dc.w $00e2,VIDMEM; bitplane 0 start low
	dc.w $0182, $000 ; pixel data black
	
	dc.w $0180, $fff ; background white
	dc.w $2c0f,$fffe ; wait for line $2c
	dc.w $0180, $0f0 ; background green
	dc.w $380f,$fffe ; wait for line $38
	dc.w $0180, $ff0 ; background yellow

	dc.w $ffff,$fffe ; End of copperlist
copperlist_end:	

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
	
	;; print hex digit given in D0
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

