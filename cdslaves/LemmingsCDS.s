	INCDIR	"Include:"
	INCLUDE	whdload.i
	INCLUDE	whdmacros.i
	IFD	BARFLY
	OUTPUT	Lemmings.cdslave
	BOPT	O+				;enable optimizing
	BOPT	OG+				;enable optimizing
	BOPT	ODd-				;disable mul optimizing
	BOPT	ODe-				;disable mul optimizing
	BOPT	w4-				;disable 64k warnings
	BOPT	wo-			;disable optimizer warnings
	SUPER
	ENDC
CD_SLAVE_HEADER	MACRO
		moveq	#-1,d0
		rts
		dc.b	"CD32LOAD"
		ENDM

_base		CD_SLAVE_HEADER			;ws_Security + ws_ID
	; we don't need/can't really use expmem info, because depending on
	; slave build options, we can have expmem at 0 and chipmem at $100000
	; or expmem at $80000 and chipmem at $0 but in the end CD32load sets
	; expmem to $80000 most of the time so why bother?? (or we can get that
	; from a game address register, e.g. no issue to "repatch" a patchlist since
	; we are called with the original arguments
	;
	; and the other data from slave header aren't very useful either
	;
	; what we need:
	; init routine (optional)
	; hook for each hookable call (optional)
_resload
	dc.l	0	; cd32load writes (unhooked!) resident loader address here
_cdplay
	dc.l	0	; cd32load writes the address of the play routine here
_cdstop
	dc.l	0	; cd32load writes the address of the stop routine here
_cdstatus
	dc.l	0	; cd32load writes the address of the status routine here
				; 0: cd playing
				; 1: cd stopped playing
				; 2: cd not started playing
				; 3: error
_cdreplay
	dc.l	0	; cd32load writes the address of the play-if-play-ended routine here
_reserved
	dc.l	0	; cd32load writes the address of ??? future use

	; now the hooks
	dc.w	0   ;init-_base	; init: called just BEFORE the main slave init
	dc.w	0	; Decrunch: called after a call to resload_Decrunch
	dc.w	0	; DiskLoad: same thing for all below calls
	dc.w	0	; LoadFile
	dc.w	0	; LoadFileDecrunch-_base	; LoadFileDecrunch
	dc.w	0	; LoadFileOffset
	dc.w	0	; Patch
	dc.w	PatchSeg-_base	; PatchSeg
	dc.w	0	; Relocate

;LoadFileDecrunch:
;	cmp.l	#'usic',4(a0)
;	bne.b	.skip
;	blitz
;.skip
;	rts
	
; section 0 jumps at section 2 right away
; section 1 is the chipmem
; segstart at $58a68, first skip patch is $58CE8 which matches expmem+$298 ($78298)
	
PatchSeg:
	; we're going to force SFX and add cd player calls
	lea	pl_main(pc),a0
	move.l	_resload(pc),a2
	jsr	(resload_PatchSeg,a2)
.skip

	rts

pl_main
	PL_START
	PL_W	$5c45e,$50ED	; TST => ST to force SFX
	PL_NOP	$5c462,6
	PL_PS	$5c46e,compute_music_track
	PL_S	$5c474,$5c54a-$5c474
	PL_PSS	$58F48,mainloop_hook,6
	PL_PS	$58fac,end_of_level
	PL_END

mainloop_hook:
	; our code inserts here
	movem.l	a0/d1,-(a7)
	lea	music_countdown(pc),a0
	tst.w	(a0)
	beq.b	.check_stop
	subq.w	#1,(a0)
	bne.b	.noneed
	; countdown reached zero: run play once
	move.l	current_track(pc),d0
	moveq.l	#0,d1
	move.l	_cdplay(pc),a0
	jsr	(a0)	
.noneed
	movem.l	(a7)+,d1/a0
	; original
	TST.B	9(A5)			;58f48 ($784f8): 4a2d0009
	BNE.W	.out		;58f4c ($784fc): 6600000c
	TST.B	13(A5)			;58f50 ($78500): 4a2d000d
.out
	RTS
.check_stop
	move.l	_cdstatus(pc),a0
	jsr	(a0)
	cmp.l	#1,d0
	bne.b	.noneed
	; music stopped: replay
	move.l	_cdreplay(pc),a0
	jsr		(a0)
	bra.b	.noneed


compute_music_track
	; D0 is it the level number? original game performs a modulus:
	;DIVU	#$0011,D0		;5c486 ($7ba36): 80fc0011
	;SWAP	D0			;5c48a ($7ba3a): 4840
	; but there are special cases (beast/awesome/menace special levels)
	; handled with another variable
	; so what the hell, let's use a pre-computed table and that's it
	
	movem.l	a0,-(a7)
	lea	track_table(pc),a0

	move.b	(a0,d0.w),d0
	and.l	#$FF,D0
	
	lea	current_track(pc),a0
	move.l	d0,(a0)
	lea	music_countdown(pc),a0
	move.w	#40,(a0)
	movem.l	(a7)+,a0
	rts
	

end_of_level:
	; original
	MOVE.W	#$8020,154(A6)		;58fac ($7855c): 3d7c8020009a
	lea	music_countdown(pc),a0
	move.w	#50,(a0)
	move.l	_cdstop(pc),-(a7)	; stop music
	RTS


music_countdown
	dc.w	0
current_track
	dc.l	0

; 1 level on each difficulty setting is a special reference to
; another psygnosis game, the music also follows
; fun: level 22: beast level
; tricky: level 14: menace 
; taxing: level 15: awesome
; mayhem: level 22: 
track_table:
	dc.b	2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,2,3,4,5,19,7,8,9,10,11,12,13,14
	dc.b	15,16,17,18,2,3,4,5,6,7,8,9,10,20,12,13,14,15,16,17,18,2,3,4,5,6,7,8,9,10
	dc.b	11,12,13,14,15,16,17,18,2,3,4,5,6,7,21,9,10,11,12,13,14,15,16,17,18,2,3,4,5,6
	dc.b	7,8,9,10,11,12,13,14,15,16,17,18,2,3,4,5,6,7,8,9,10,22,12,13,14,15,16,17,18,2

	
	