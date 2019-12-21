	INCDIR	"Include:"
	INCLUDE	whdload.i
	INCLUDE	whdmacros.i
	IFD	BARFLY
	OUTPUT	MarbleMadness.cdslave
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

;       game over music ne marche pas: check arcade pour voir en mode 2 joueurs?
;       fin du jeu (ultimate) que se passe t il ? ajouter musique congrats

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

	
PatchSeg:
	; store some variable addresses
	move.l	a1,d1
	add.l	d1,d1
	add.l	d1,d1

	moveq.l	#3,d2
	bsr		get_section
	lea	$005D2-$224(a0),a2
	lea	game_state_address(pc),a4
	move.l	a2,(a4)
	lea	$005D6-$224(a0),a2
	lea	current_level_address(pc),a4
	move.l	a2,(a4)
	
	; we're going to turn off music and add cd player calls
	lea	pl_main(pc),a0
	move.l	_resload(pc),a2
	jsr	(resload_PatchSeg,a2)

	pea	mainloop_hook(pc)
	move.l	(a7)+,$BC.W		; TRAP #F handle

	rts
	
; < d1 seglist
; < d2 section #
; > a0 segment
get_section
	move.l	d1,a0
	subq	#1,d2
	bmi.b	.out
.loop
	move.l	(a0),a0
	add.l	a0,a0
	add.l	a0,a0
	dbf	d2,.loop
.out
	addq.l	#4,a0
	rts
pl_main
	PL_START
	PL_NOP	$1F384,4
	PL_W	$20AD6,$4E4F	; TRAP #F
	PL_P	$24740,c_open_hook
	PL_END

c_open_hook:
	move.l	_cdstop(pc),a0
	jsr	(a0)
	JSR	-30(A6)	;24740 (dos.library)
	MOVEM.L	(A7)+,D2/A6		;24744: 4CDF4004
	RTS				;24748: 4E75

	
mainloop_hook:
	movem.l	a0/d0-d1,-(a7)
	move.l	game_state_address(pc),a0
	move.w	(a0),d0
	
	cmp.w	#5,d0	; menu/adding seconds
	beq	.menu		; maybe add some music at some point...
	cmp.w	#4,d0	; game over player 1
	beq.b	.game_over
	cmp.w	#2,d0	; game over player 2
	beq.b	.game_over
	cmp.w	#3,d0	; level complete
	beq.b	.out	; don't restart the music
	cmp.w	#6,d0	; game complete
	beq.b	.game_complete
	
	cmp.w	#0,d0	; game playing
	; Check if CD is currently playing, else, play current level track
	bne.b	.other

	move.l	_cdstatus(pc),a0
	jsr	(a0)
	cmp.l	#0,d0
	beq.b	.out	; playing: okay
	cmp.l	#3,d0
	beq.b	.out	; error: well, skip that
	
	; launch CD play because was not running or just stopped
	moveq.l	#0,d0
	move.l	current_level_address(pc),a0
	move.w	(a0),d0
	add.w	#4,d0	; skip 2 first special tracks + data track
	moveq.l	#0,d1
	move.l	_cdplay(pc),a0
	jsr	(a0)
.out
	; save previous state
	move.l	game_state_address(pc),a0
	move.w	(a0),d0
	lea		previous_state(pc),a0
	move.w	d0,(a0)

	movem.l	(a7)+,a0/d0-d1
	
	MOVE.L	D0,D7			;20AD6: 2E00
	RTE		; return from TRAP
.other
	; state 1 ???? WTF??
	blitz
	nop
	bra.b	.out
.game_over:
	cmp.w		previous_state(pc),d0
	beq.b	.out	; not the first time
	move.w	#3,d0	; game over tune
	moveq.l	#0,d1
	move.l	_cdplay(pc),a0
	jsr	(a0)
	bra.b	.out
	
.game_complete:
	cmp.w		previous_state(pc),d0
	; music only must be played once
	beq.b	.out

.start_congrats_music
	; launch CD play because was not running or just stopped
	moveq.l	#2,d0
	moveq.l	#0,d1
	move.l	_cdplay(pc),a0
	jsr	(a0)	
	bra.b	.out
	
.menu
	; if music is playing, stop it
	move.l	_cdstatus(pc),a0
	jsr	(a0)
	cmp.l	#2,d0
	beq.b	.out
	cmp.l	#3,d0
	beq.b	.out
	; music playing or just stopped playing: stop
	move.l	_cdstop(pc),a0
	jsr	(a0)
	bra.b	.out
	
	


game_state_address
	dc.l	0
current_level_address
	dc.l	0
previous_state
	dc.w	0


	
	