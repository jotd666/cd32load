	INCDIR	"Include:"
	INCLUDE	whdload.i
	INCLUDE	whdmacros.i
	IFD	BARFLY
	OUTPUT	Premiere.cdslave
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
	dc.w	0	; LoadFileDecrunch
	dc.w	0	; LoadFileOffset
	dc.w	Patch-_base	; Patch
	dc.w	0	; PatchSeg
	dc.w	0	; Relocate

	
; the patch that we want to override is the one
; of the main program, starting at expmem, that we
; don't know but there's only 1 patch in expmem and so
; only 1 call with a1 >= $80000
; (well CD32load always sets expmem at $80000 anyway)

Patch:
	cmp.l	#$80000,a1
	bcs.b	.boot_patches
	lea	expmem(pc),a0
	move.l	a1,(a0)
	add.l	#$11386,a1
	lea	current_level_address(pc),a0
	move.l	a1,(a0)

	move.l	expmem(pc),a1
	lea	pl_main(pc),a0
	move.l	_resload(pc),a2
	jsr	resload_Patch(a2)
.boot_patches
	rts

	
pl_main
	PL_START
	PL_PSS	$a84,main_loop_hook,2
	PL_PSS	$1D0,stop_music,8
	PL_NOP	$1388,8	; don't toggle music/sfx
	; sfx default and locked
	PL_B	$113d7,1
	PL_END
	
; after quit/continue: next file load seems to freeze
stop_music
	bsr		cd_stop
	rts
	
cd_stop:
	move.l	_cdstop(pc),-(a7)
	rts

; < D0: numbers of vertical positions to wait
beamdelay
.bd_loop1
	move.w  d0,-(a7)
        move.b	$dff006,d0	; VPOS
.bd_loop2
	cmp.b	$dff006,d0
	beq.s	.bd_loop2
	move.w	(a7)+,d0
	dbf	d0,.bd_loop1
	rts
	
main_loop_hook
	BTST	#5,31(A6)		;80a84: 082e0005001f
	; wait VBL
	BEQ.S	main_loop_hook		;80a8a: 67f2

	movem.l	d0-d1/a0,-(a7)
	move.l	_cdstatus(pc),a0
	jsr	(a0)
	cmp.l	#0,d0
	beq.b	.out	; playing: okay
	cmp.l	#3,d0
	beq.b	.out	; error: well, skip that	

	move.l	current_level_address(pc),a0
	move.w	(a0),d0		; level number 0 ..
	addq.l	#2,d0
.do_play
	moveq.l	#0,d1
	move.l	_cdplay(pc),a0
	jsr	(a0)
.out
	movem.l	(a7)+,d0-d1/a0
	rts
	



current_level_address
		dc.l	0
expmem:
	dc.l	0


	


	