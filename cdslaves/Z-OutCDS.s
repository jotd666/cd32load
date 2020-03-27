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

; 1120: killed: lives subbing 8328.B
; test "continue"

; test 2 player
; level 6: scroll sequences? (reverted)
; boss level 5: music?
; highscore track


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
	cmp.l	#$20000,a1
	bne.b	.nopatch
	
	IFD	TESTTRACK
	blitz
	nop
	moveq.l	#1,d0
	move.l	#0,d1
	bsr	find_track
	nop
	moveq.l	#1,d0
	move.l	#10,d1
	bsr	find_track
	nop
	moveq.l	#1,d0
	move.l	#$166,d1
	bsr	find_track
	nop
	moveq.l	#1,d0
	move.l	#$169,d1
	bsr	find_track
	nop
	moveq.l	#1,d0
	move.l	#$231,d1
	bsr	find_track
	nop
	
	blitz	; STOPPPPP
	ENDC
	
	sub.l	a1,a1
	lea	pl_main(pc),a0
	move.l	_resload(pc),a2
	jsr	resload_Patch(a2)
.nopatch
	rts

level_number = $85C8
	
pl_main
	PL_START
	PL_PS		$cde0,menu_music
	PL_PSS		$ccea,start_game,2
	PL_PS		$988,pregame_loop
	PL_PS		$7682,game_music
	PL_R $2CBE2

	PL_PSS	$6AF20,in_game_music,2	; controls in-game music
	PL_PS	$1bcc,level_ended
	PL_PS	$1c50,level_ended_2
	PL_PS	$1ca6,game_over
	PL_PS	$009dc,get_ready
	PL_END
	
game_over:
	bsr	set_on_chip_music
	ADDQ.W	#1,$7860
	rts

level_ended_2
	bsr	set_cd_music
	MOVE.W	level_number,D0		;01c50: 303a6976
	ADDQ.W	#1,D0			;01c54: 5240
	rts
	
level_ended:
	bsr	set_on_chip_music
	MOVE.L	#$00020000,D0		;01bcc: 203c00020000
	rts
	
set_on_chip_music
	move.l	a0,-(a7)
	lea	on_chip_music(pc),a0
	tst.b	(a0)
	bne.b	.already_chip
	bsr	cd_stop
	lea	on_chip_music(pc),a0
	st.b	(a0)
.already_chip
	move.l	(a7)+,a0
	rts
	
set_cd_music
	move.l	a0,-(a7)
	lea	on_chip_music(pc),a0
	clr.b	(a0)
	move.l	(a7)+,a0
	rts

		
in_game_music:
	lea	on_chip_music(pc),a4
	tst.b	(a4)
	beq.b	.skip
	; level 6: on chip (no remix yet anyway)
	cmp.w	#6,level_number
	bcc.b	.skip
	
	; original code
	MOVEA.L (A6),A4
	TST.W ($002c,A6)
	rts
.skip
	MOVEA.L (A6),A4
	; pop stack
	addq.l	#4,(a7)
	rts
		
;esc_pressed
;	bsr	cd_stop
;	CLR.B	(A1)			;01a3e: 4211
;	MOVE.W	$7860,D1	;01a40: 323a5e1e
;	rts

get_ready:
	; set_cd_music shouldn't be called in the main loop, as it would conflict
	; with game over / level end chip music
	bsr	set_cd_music
	MOVE.L	#$0001ff00,D4		;009dc
	rts
	
start_game:
	bsr	cd_stop
	MOVEA.L	$0bd88,a0
	JMP	40(A0)

cd_stop
	movem.l	a0,-(a7)
	move.l	_cdstop(pc),a0
	jsr	(a0)
	movem.l	(a7)+,a0
	rts
	
; < D0: track number
play_if_needed:
	movem.l	d1/a0,-(a7)
	; level 6/7: on chip (no remix yet anyway)
	cmp.w	#6,level_number
	bcc.b	.out
	move.b	on_chip_music(pc),d1
	bne.b	.out		; if chip music is on, don't try to play
	
	move.w	current_track(pc),d1
	cmp.w	d0,d1
	bne.b	.forceplay
	; same track: check if ended
	move.l	d0,d1	; save
	move.l	_cdstatus(pc),a0
	jsr	(a0)
	cmp.l	#0,d0
	beq.b	.out	; playing: okay
	cmp.l	#3,d0
	beq.b	.out	; error: well, skip that
	move.l	d1,d0	; restore track number
.forceplay
	lea	current_track(pc),a0
	move.w	d0,(a0)		; store for next time
	moveq.l	#0,d1
	move.l	_cdplay(pc),a0
	jsr	(a0)
	
.out
	movem.l	(a7)+,d1/a0
	rts
	
update_game_music
	movem.l	d0-d2/a0-a1,-(a7)
	
	moveq.l	#0,d0
	move.w	level_number,d0	; level number
	move.w	$83A8,d1	; game X-scroll
	
	bsr	find_track
	bsr	play_if_needed
.out

	movem.l	(a7)+,d0-d2/a0-a1
	rts
	
; < D0: level number 1-6
; < D1: 
find_track:
	lea	music_table(pc),a0
	subq.l	#1,d0
	add.w	d0,d0	; level number * 2
	add.w	(a0,d0.w),a0		; address of the level music table
	move.w	(a0)+,d2	; first track x limit: 0: always passes, no need to test it
	move.w	(a0)+,d0	; track to play a priori: first level track
	
.loop
	move.w	(a0)+,d2	; track x limit
	bmi.b	.out		; should not happen!
	cmp.w	d2,d1	; sets carry if x limit < game X scroll
	bcs.b	.select
	bne.b	.cont
	move.w	(a0)+,d0	; exact match: get this track
	bra.b	.select
.cont
	move.w	(a0)+,d0	; next track to play a priori
	bra.b	.loop
.select
	rts
.out
	; end: play this track
	rts
	
music_table:
	dc.w	mt_level_1-music_table
	dc.w	mt_level_2-music_table
	dc.w	mt_level_3-music_table
	dc.w	mt_level_4-music_table
	dc.w	mt_level_5-music_table
	dc.w	mt_level_6-music_table
	
mt_level_1:
	dc.w	0,4		; first part
	dc.w	$162,5	; mid-level boss (166)
	dc.w	$167,6	; second part
	dc.w	$231,7	; level boss
	dc.w	$FFFF
mt_level_2:
	dc.w	0,8
	dc.w	$22F,9	; level boss (at 231)
	dc.w	$FFFF
mt_level_3:
	dc.w	0,10
	dc.w	$C6,11
	dc.w	$C7,12
	dc.w	$173,13
	dc.w	$174,14
	dc.w	$210,15		; boss appears before scrolling stops
;	dc.w	$22A,10
	dc.w	$FFFF
mt_level_4:
	dc.w	0,16
	dc.w	$010D,17
	dc.w	$10E,18
	dc.w	$231,19
	dc.w	$FFFF
mt_level_5:
	dc.w	0,20
	dc.w	$C2,21
	dc.w	$C3,20
	dc.w	$17B,21		; TEMP???
	dc.w	$FFFF
mt_level_6:
; backwards
	dc.w	0,22
	dc.w	$151,20
	dc.w	$133,21
	dc.w	$17B,22
	; boss $F
	dc.w	$FFFF
	
	
pregame_loop:
	bsr	update_game_music
	MOVE.L #$4b,D0
	ADD.W D7,D0
	MOVE.W (A5),D1
	rts

	
game_music
	bsr	update_game_music
	MOVE.L #$0001ff00,D4	; original
	rts
	
; scrollx: 000083A8
; level 1: scrollx = 0x166: first boss, 0x231: final boss

menu_music
	movem.l	d0,-(a7)
	bsr	set_cd_music
	moveq.l	#3,D0
	bsr	play_if_needed
	movem.l	(a7)+,d0

	TST.B	$bfe001	; original
	rts
	
; todo: in slave: check if game test disk write protect/disk in drive
; boss music should arrive earlier / finalize level 5 / check level 5 chip last boss
	
current_track
	dc.w	0	

on_chip_music
	dc.b	0,0
	


	