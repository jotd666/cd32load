	INCDIR	"Include:"
	INCLUDE	whdload.i
	INCLUDE	whdmacros.i
	IFD	BARFLY
	OUTPUT	Wonderdog.cdslave
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
	dc.l	0	; 0000: cd32load writes (unhooked!) resident loader address here
_cdplay
	dc.l	0	; 0004: cd32load writes the address of the play routine here
_cdstop
	dc.l	0	; 0008: cd32load writes the address of the stop routine here
_cdstatus
	dc.l	0	; 000C: cd32load writes the address of the status routine here
				; 0: cd playing
				; 1: cd stopped playing
				; 2: cd not started playing
				; 3: error
_cdreplay
	dc.l	0	; 0010: cd32load writes the address of the play-if-play-ended routine here
_reserved
	dc.l	0	; 0014: cd32load writes the address of ??? future use
	
	; now the hooks
	dc.w	0   ; 0018: init-_base	; init: called just BEFORE the main slave init
	dc.w	0	; 001A: Decrunch: called after a call to resload_Decrunch
	dc.w	0	; 001C: DiskLoad: same thing for all below calls
	dc.w	0	; 001E: LoadFile
	dc.w	0	; 0020: LoadFileDecrunch
	dc.w	0	; 0022: LoadFileOffset
	dc.w	Patch-_base	; 0024: Patch
	dc.w	0	; 0028: PatchSeg
	dc.w	0	; 002A: Relocate
	

	
Patch:
	cmp.l	#$4278027A,$63A2.W
	beq.b	 .doit
	rts
.doit

	; we're going to add cd player calls
	lea	pl_main(pc),a0
	sub.l	a1,a1
	move.l	_resload(pc),a3
	jsr	(resload_Patch,a3)
	rts

	
pl_main
	PL_START
	PL_P	$40,stop_music_when_player_killed
	PL_PS	$63CA,play_intro_music
	PL_P	$652E,begin_quest
	PL_L	$3B6A,$4EB80040
	PL_PS	$00002EDA,stop_music_when_end_world_or_level
	PL_PS	$131DE,start_music_when_next_world
	PL_PS	$00002C20,game_loop_hook
	PL_PS	$00003A60,quit_game
	PL_PS	$00013828,start_music_before_shop_loop
	PL_PS	$0001394A,end_shop_music
	PL_PS	$0000AFE0,start_guardian_music
	PL_PSS	$0000C33A,end_guardian_music,2
	PL_PS	$000030B4,end_of_gamewon
	PL_PS	$00002F46,gamewon	; starts at 2F12 but loads something so kills the CD track!
	PL_PSS	$00003A42,gameover_hook,6
	PL_END
	
gameover_hook:
; enter your name screen + highscore
	; play win track
	movem.l	D0/A1,-(a7)
	moveq.l	#3,D0
	moveq.l	#0,d1
	move.l	_cdplay(pc),a1
	jsr	(a1)
	movem.l	(a7)+,D0/A1
	JSR $00006780
	JSR $000068de
	bra	stop_music
	
gamewon:
	; original code
    MOVE.W #$00bf,D7
    MOVE.L #$13,D6
	
	; play win track
	movem.l	D0/A1,-(a7)
	moveq.l	#11,D0
	moveq.l	#0,d1
	move.l	_cdplay(pc),a1
	jsr	(a1)
	movem.l	(a7)+,D0/A1
	rts
 
end_of_gamewon
	JSR $0000565e
	bsr	stop_music
	bra	start_music_in_mainloop_40
	
 
end_guardian_music:
      CLR.W $023a.W
      MOVE.W $04e8.W,D2
	  bra	start_music_in_mainloop
	 
start_music_in_mainloop:
	  movem.l	a0,-(a7)
	  lea	music_countdown(pc),a0
	  clr.w	(a0)
	  movem.l	(a7)+,a0
	  rts
start_music_in_mainloop_40:
	movem.l	a0,-(a7)
	lea	music_countdown(pc),a0
	move.w	#40,(A0)
	movem.l	(a7)+,a0
	RTS	
	
quit_game:
      MOVE.W #$0001,$027a.W		; quit flag
	  bra	stop_music

end_shop_music:
	JSR $0001d058	; original
	bsr	stop_music
	; and start music when game restarts
	bra	start_music_in_mainloop
	
start_guardian_music
	MOVE.W #$0001,$023a 	; enable guardian flag
	  ; playing the guardian music here does not work: there is some loading done first
	  ; so set the countdown flag so, we play the guardian score
	  ; as soon as we enter the main loop
	bra	start_music_in_mainloop
	
 
start_music_before_shop_loop:
	JSR $0001cfca
	movem.l	D0/D1/A0/A1,-(a7)
	moveq.l	#9,D0
	moveq.l	#0,d1
	move.l	_cdplay(pc),a1
	jsr	(a1)
	movem.l	(a7)+,D0/D1/A0/A1
	RTS
 
start_music_when_next_world:
    CLR.W $0230
    MOVE.L #$1f,D0
	; give it a little time
	; not noticeable, but helps when completing the last world
	; so music doesn't restart. It restarts when warping to the next level
	movem.l	a0,-(a7)
	lea	music_countdown(pc),a0
	move.w	#10,(A0)
	movem.l	(a7)+,a0
	rts
	
stop_music_when_player_killed:
	bsr	stop_music
    CLR.W $02a6.W	; original
	bra	start_music_in_mainloop_40


stop_music_when_end_world_or_level
	bsr	stop_music
	JMP $00012e04
	
	IFEQ	1
stop_music_when_end_world:
	MOVE.W #$0001,$0230.W
	bra	stop_music
	ENDC
	
	; just sets a countdown so the intro sound plays before music starts
play_music_when_level_starts:
     MOVE.W #$007f,D1
     MOVE.W #$0009,D0
	 movem.l	a0,-(a7)
	 lea	music_countdown(pc),a0
	 move.w	#40,(A0)
	 movem.l	(a7)+,a0
	 rts
	 
music_countdown
	dc.w	0
	
game_loop_hook
	 movem.l	d0/a0,-(a7)

	IFEQ	1
	 ; get cd playing status
	 move.l	_cdstatus(pc),a0
	 jsr	(a0)
	 cmp.l	#1,d0
	 bne.b	.play_not_stopped
	 move.w	#$F00,$DFF180
.play_not_stopped
	ENDC
	
	 lea	music_countdown(pc),a0
	 move.w	(a0),d0
	 bmi.b	.test_replay
	 beq.b	.play
	 sub.w	#1,d0
	 move.w	d0,(a0)
	 bra.b	.skip
.play
	move.w	#$FFFF,(a0)

	; start level music from here
	; starting from the mainloop has HUGE advantages:
	; - we can add a delay to wait for the "welcoming" sound to play
	; - we can "order" music from some part of the game, let some loading
	; complete, and the music will start as soon as the game loop is reached
	movem.l	D1/D2/A1,-(a7)
	move.w	#2,D0	; guardian
	tst.w	$23A.W		; if guardian
	bne.b	.guardian
.level
	addq.w	#1,d0
	add.w	$1D4.W,d0		; 1D4 contains level 1=>4. Level 1 starts at track 4
.guardian
	moveq.l	#0,d1
	move.l	_cdplay(pc),a1
	jsr	(a1)
	movem.l	(a7)+,D1/D2/A1
	
.skip	 
	 movem.l	(a7)+,d0/a0

	JMP $00016e3e	; original
.test_replay
	move.l	_cdreplay(pc),a0
	jsr	(a0)
	bra.b	.skip
	
play_intro_music
	; original game
    MOVE.W #$0001,$02f2.W
	
	; play menu
	movem.l	D0/D1/D2/A0/A1,-(a7)
	move.w	intro_music_playing(pc),d0
	bne.b	.test_replay
	lea	intro_music_playing(pc),a0
	move.w	#1,(a0)

	moveq.l	#8,D0
	moveq.l	#0,d1
	move.l	_cdplay(pc),a1
	jsr	(a1)
.out
	movem.l	(a7)+,D0/D1/D2/A0/A1
	rts
.test_replay:
	move.l	_cdreplay(pc),a1
	jsr	(a1)
	bra.b	.out
	
	; begin quest, with or without password
begin_quest:
	CLR.W $0266.W	; original, set world index to 0
	
	movem.l	A0,-(a7)
	lea	intro_music_playing(pc),a0
	clr.w	(a0)
	lea	music_countdown(pc),a0
	move.w	#20,(A0)
	movem.l	(a7)+,A0
	
	bsr	stop_music
	
	JMP $2452.W

stop_music:
	movem.l	A1,-(a7)
	move.l	_cdstop(pc),a1
	jsr	(a1)
	movem.l	(a7)+,A1
	rts
	
; play once, else when screen loops, the music restarts
intro_music_playing
	dc.w	0



;version 1 amiga:

;$1D4.W: current level 1,2,3,4
;$224.W: nb lives
;$230.W: is world completed 0/1
;$23A.W: is fighting guardian 0/1/2
;$2a6.W: death animation counter ($FFFF: alive)
;$27a.W: game quit
;$1E0/$1E2: pos X,Y

; stop music (end of world)
;;00012D06 660c                     BNE.B #$0c == $00012d14 (T)
;00012D08 31fc 0001 0230           MOVE.W #$0001,$0230 [0001] ; stop cd play
;00012D0E 4cdf 0101                MOVEM.L (A7)+,D0/A0
; restart music (next world starts)
;000131DE 4278 0230                CLR.W $0230
;000131E2 701f                     MOVE.L #$1f,D0
; player killed
;00003B6A 4278 02a6                CLR.W $02a6
;00003B6E 4a78 02a6                TST.W $02a6 [0000]
; quit game
;?????
; level starts
;00002B86 323c 007f                MOVE.W #$007f,D1
;00002B8A 303c 0009                MOVE.W #$0009,D0
; player respawns
;000038BE 4240                     CLR.W D0
;000038C0 4eb9 0001 d23a           JSR $0001d23a
;000038C6 31fc 0018 0c96           MOVE.W #$0018,$0c96 [0018]
;000038CC 31fc 0001 0216           MOVE.W #$0001,$0216 [0001]

; world end
;?????
; guardian

;BeginQuest: $2452.W
;GameWon: $2F12.W

;GameLoop address: $2C20 (similar code at $0000FC2E)
;00002C20 4eb9 0001 6e3e           JSR $00016e3e
;00002C26 6100 0a12                BSR.W #$0a12 == $0000363a
;00002C2A 4678 0196                NOT.W $0196 [0000]

;Screen_MainMenu address:
; 000063A6 4278 02f4                CLR.W $02f4
; 000063AA 4eb9 0000 f514           JSR $0000f514

; trigger level end
; f $2F0E
; g
; g $2F12
	