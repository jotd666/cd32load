	INCDIR	"Include:"
	INCLUDE	whdload.i
	INCLUDE	whdmacros.i
	IFD	BARFLY
	OUTPUT	Silkworm.cdslave
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

	
	
Patch:
	sub.l	a1,a1
	lea	pl_main(pc),a0
	move.l	_resload(pc),a2
	jsr	resload_Patch(a2)
	rts

	
	; 6867C is main loop start. We don't insert patches here because it's
	; full of BSR stuff
	
pl_main
	PL_START
	PL_PS	$000686B8,main_loop_hook
	PL_PS	$00068DEC,esc_pressed
	PL_PS	$00068666,before_main_loop
	PL_PS	$0006ef8e,a_player_lost_all_his_lives
	; make sure that completing level / game stops the music (else last level freeze)
	PL_PS	$68764,level_or_game_complete
	PL_PS	$6f91c,level_or_game_complete
	PL_PS	$703f2,level_or_game_complete
	PL_PS	$6870c,game_completed
	; enable programmer cheat keys
	PL_NOP	$6872a,2
	PL_END
	
level_or_game_complete
	MOVE.W	#$0002,-32374(A6)	; set complete status
	bsr	cd_stop		; just set the flag, we cannot stop CD from here (VBLANK)
	rts
	
a_player_lost_all_his_lives:
	; check if both players lost all lives
	tst.w	$2B4.W
	bpl.b	.one_alive
	tst.w	$326.W
	bpl.b	.one_alive
	; stop music
	bsr	cd_stop
.one_alive
	BSET	#6,72(A4)		;: 08ec00060048
	rts
	
before_main_loop:
	movem.l	A0,-(a7)
	lea	stop_requested(pc),a0
	move.w	#0,(A0)
	movem.l	(A7)+,A0
	
	MOVE.W #$000a,(-$7fe0,A6) ; $000000a0 [0000]
	RTS

	; this could have been simple, but I want to make sure I'm stopping the music
	; and I have to play all the level to test each time so...
game_completed:
	movem.l	A0,-(a7)
	move.l	_cdstop(pc),a0	; stop music
	jsr		(a0)
	movem.l	(a7)+,a0
.loop
	TST.W	-32748(A6)		;6870c: 4a6e8014
	BNE.S	.loop		;68710: 66fa
	rts
	
esc_pressed:
	CLR.W (-$7f1e,A6) ; == $00000162
	bsr	cd_stop
	rts
	
cd_stop
	movem.l	A0,-(a7)
	lea	stop_requested(pc),a0
	move.w	#1,(A0)
	movem.l	(A7)+,A0
	rts

	; joypad detection fails with CD32load?? si JOYPAD pas a 0 ??
	 ; totest stop music when no more lives for both players
	 ; totest last boss killed: freeze when stopping music
main_loop_hook	
	tst.w	-32764(A6)		; is demo/rolling mode
	bne.b	.out2
	movem.l	d0/d1/d2/a0,-(a7)
	
	move.w	stop_requested(pc),d0
	beq.b	.playing
	; real CD stop action
.really_stop
	pea	.out(pc)
	move.l	_cdstop(pc),-(a7)	; stop music
	rts
.playing
	; TEMP infinite lives
;;	move.w	#8,$2B4.W
;;	move.w	#8,$326.W

	move.w	(-$7e76, A6),d1		; AKA $20A
	move.w	previous_state(pc),d2
	cmp.w	d1,d2
	beq.b	.skip_stop
	cmp.w	#2,d1		; new state is 2, previous state is different: stop music
	beq.b	.force_stop
	cmp.w	#0,d1
	beq.b	.skip_stop
	cmp.w	#1,d1
	beq.b	.boss    ; change state normal => boss: force CD play for boss track
	; I wonder how we can reach that. whatever
	; state change boss => end
.force_stop
	bsr		cd_stop
	bra.b	.really_stop
.skip_stop

	move.l	_cdstatus(pc),a0
	jsr	(a0)
	cmp.l	#0,d0
	beq.b	.out	; playing: okay
	cmp.l	#3,d0
	beq.b	.out	; error: well, skip that	

	; launch CD play because was not running or just stopped
	tst.w	d1	; 1: boss
	beq.b	.normal
.boss
	move.b	$15F.W,d0		; level number 1-...
	and.b	#1,d0	; keep only last bit
	addq.l	#2,d0	; track 2 or 3 depending on the boss
	bra.b	.do_play
.normal:
	moveq.l	#0,d0
	move.b	$15F.W,d0		; level number 1-...
	addq.l	#3,d0
.do_play
	moveq.l	#0,d1
	move.l	_cdplay(pc),a0
	jsr	(a0)
.out
	; store previous_state for later
	lea	previous_state(pc),a0
	move.w	(-$7e76, A6),(a0)
	movem.l	(a7)+,d0/d1/d2/a0
.out2	
	; original
	CMP.W #$0002,(-$7e76, A6)		; boss killed
	rts
	


	
current_level_address
		dc.l	0
stop_requested:
	dc.w	0
previous_state:
	dc.w	0


	


	