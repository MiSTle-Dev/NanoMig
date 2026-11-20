	;; power_led_blink.s
	;; basic cpu test, doesn't need any ram to work

	ORG $f80000
	
        bra.s   start-1   	; -1? wtf ...
        dc.w    $4ef9           ; jmp ...

        dc.l    $f80030
        dc.l    $f80008 

        ORG $f80030	
start:

	;; wait >80ms for minimig-aga syctrl reset to be gone
	move 	#60000,d0
iwlp:	dbra	d0,iwlp
	
	move.b	#3,$bfe201	; LED and OVL are outputs

mainlp:	bclr.b	#1,$bfe001	; LED on

	move 	#5,d1
owlp1:	move 	#50000,d0
iwlp1:	dbra	d0,iwlp1
	dbra	d1,owlp1
	
	bset.b	#1,$bfe001	; LED off
	
	move 	#5,d1
owlp2:	move 	#50000,d0
iwlp2:	dbra	d0,iwlp2
	dbra	d1,owlp2
	
	bra.s 	mainlp
