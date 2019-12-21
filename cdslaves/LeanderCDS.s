	INCDIR	"Include:"
	INCLUDE	whdload.i
	INCLUDE	whdmacros.i
	IFD	BARFLY
	OUTPUT	Leander.cdslave
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
	dc.w	LoadFileDecrunch-_base	; LoadFileDecrunch
	dc.w	0	; LoadFileOffset
	dc.w	Patch-_base	; Patch
	dc.w	0	; PatchSeg
	dc.w	0	; Relocate

LoadFileDecrunch:
;	cmp.l	#'usic',4(a0)
;	bne.b	.skip
;	blitz
;.skip
	rts
	
; section 0 jumps at section 2 right away
; section 1 is the chipmem
; segstart at $58a68, first skip patch is $58CE8 which matches expmem+$298 ($78298)
	
Patch:

	rts

pl_main
	PL_START
	PL_END
	; we don't care about pause, but we hook here to restart music if it has ended
test_for_pause
	move.l	a0,-(a7)
	move.l	_cdreplay(pc),a0
	jsr		(a0)
	RTS

end_of_level:
	move.l	_cdstop(pc),-(a7)	; stop music
	RTS	
	
	
play_level_music

	move.w	(a0,d0.w),d0
.play
	moveq.l	#0,d1
	move.l	_cdplay(pc),a1
	jsr	(a1)
.out
	movem.l	(a7)+,D0/D1/D2/A0/A1
	rts
_expmem:
	dc.l	0
	


	