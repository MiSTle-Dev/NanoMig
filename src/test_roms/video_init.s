	;; video_init.s
	;; setup copper for display. This needs some working ram
	;; since the copper list needs to reside in ram and won't
	;; work directly from rom. If sdram is not working reliably,
	;; then defining ENABLE_INT_RAM will at least allow the
	;; copper list to work
	
VIDMEM	EQU	2048		; start video memory at 2048
COPPER  EQU     $200		; copperlist in RAM

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

startcopper:
	;; clear screem memory
	move.l	#VIDMEM,a0
	move.l	#(320*256)/32-1,d0 ; 2560 long words of ram
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
	move.b	#$cc,VIDMEM+4080
	move.b	#$33,VIDMEM+4081
	move.b	#$aa,VIDMEM+4082
	move.b	#$55,VIDMEM+4083

mainlp:

	;;  some memory r/w
	move.l	#VIDMEM+4000,a0
	move.l	#VIDMEM+4160,a1
	move.l	#VIDMEM+0,a2
	move 	#160-1,d0
mm0:	move.l	(a0),(a1)+
	move.l	(a0),(a2)+
	dbra	d0,mm0	


	bclr.b	#1,$bfe001	; LED on

	move 	#1,d1
owlp0:	move 	#50000,d0
wlp0:	dbra	d0,wlp0
	dbra	d1,owlp0
	
	;;  some memory r/w
	move.l	#VIDMEM+4000,a0
	move.l	#VIDMEM+4160,a1
	move.l	#VIDMEM+0,a2
	move 	#160-1,d0
mm1:	move.l 	(a0),d1
	neg.l	d1
	move.l	d1,(a1)+
	move.l	d1,(a2)+
	dbra	d0,mm1	


	bset.b	#1,$bfe001	; LED off
	
	move 	#5,d1
owlp1:	move 	#50000,d0
wlp1:	dbra	d0,wlp1
	dbra	d1,owlp1
	
	bra.s 	mainlp
	
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
