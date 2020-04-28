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
	dc.w	0   ; init-_base	; init: called just BEFORE the main slave init
	dc.w	0	; Decrunch: called after a call to resload_Decrunch
	dc.w	0	; DiskLoad: same thing for all below calls
	dc.w	0	; LoadFile
	dc.w	0	; LoadFileDecrunch
	dc.w	0	; LoadFileOffset
	dc.w	Patch-_base	; Patch
	dc.w	0	; PatchSeg
	dc.w	0	; Relocate

; in cd32load 0.48 pressing "PLAY" at startup
; disables cd slave. no need for custom5
;init:
;	move.l	_resload(pc),a2
;	lea	(tag,pc),a0
;   jsr	(resload_Control,a2)
;  rts
    
;tag		dc.l	WHDLTAG_CUSTOM5_GET
;turn_off	dc.l	0
;		dc.l	0	
	
Patch:
;    move.l  turn_off(pc),d0     ; disable CD audio if CUSTOM5 is set
;    bne.b   .nopatch
	lea	.done(pc),a0
	tst.b	(a0)
	bne.b	.nopatch
    cmp.l   #$400,a1    ; adapted to Stingray's patch
    bne.b   .nopatch
	st.b	(a0)
	
	sub.l	a1,a1
	lea	pl_main(pc),a0
	move.l	_resload(pc),a2
	jsr	resload_Patch(a2)
.nopatch
	rts

.done
	dc.w	0
	

pl_main
	PL_START
	;;PL_PSS	$614,game_loop,2
	PL_PS	$56DA,init_module
	PL_P	$56E4,set_subsong
	PL_P	$56EA,play_sound
	PL_P	$56F0,cd_stop
	PL_P	$56F6,cd_stop	; fade is stop: we can't fade anyway
    ; disable fade when pausing (causes issues, restarts music, sfx are disabled...)
    PL_NOP  $34EC,4
	PL_END

game_loop
	move.w	#$F8,d0
	jsr	$46DE.W		; beam sync
	rts

    ; we could have disabled the spurious music stop when the end of level
    ; is reached, because the system detects that the music has stopped and it restarts
    ; but that means patching each game loop for that. We can also store the current track
    ; last time cd_stop was called. And in that case, the play loop does nothing until the
    ; current track changes (except this is the title screen)
	
cd_stop
	movem.l	a0,-(a7)
    lea current_track_stopped(pc),a0
    move.l  current_track(pc),(a0)
	move.l	_cdstop(pc),a0
	jsr	(a0)
	movem.l	(a7)+,a0
	jmp	$6CEB0
	
NB_PLAY_TICKS = 25

play_sound:

	; called continuously, do not try to check CD status each VBL!
	movem.l	d0-d1/a0,-(a7)
	lea	loop_counter(pc),a0
	subq.w	#1,(a0)
	bne.b	.out
	; reload not each time, would cost too much cpu
    ; to interrogate the CD device all the time
	move.w	#NB_PLAY_TICKS,(a0)
	
	move.l	_cdstatus(pc),a0
	jsr	(a0)
	cmp.l	#0,d0
	beq.b	.out	; playing: okay
	cmp.l	#3,d0
	beq.b	.out	; error: well, skip that

    ; play only if title or different track than before
	move.l	current_track(pc),d0
    beq.b   .play
.play    
    cmp.l  current_track_stopped(pc),d0
    beq.b  .out     ; don't replay the same level track
	moveq.l	#0,d1
	move.l	_cdplay(pc),a0
	jsr	(a0)
	
.out
	movem.l	(a7)+,d0-d1/a0
	; call original, so sound fx work
	jmp			$6CE88+36


loop_counter
	dc.w	1	; starts immediately on title

; custom5: turn off cd music: test if works
; trainer doesn't work?? special cd32load version with red/blue/... screens
; if button pressed

init_module:
	movem.l	a0,-(a7)
	lea	module_data(pc),a0
	move.l	d0,(a0)
	;move.l	d1,(a0)+   ; not needed
	lea	loop_counter(pc),a0
	move.w	#1,(a0)		; remove delay
	movem.l	(a7)+,a0
	JSR	$0006CEBC	; actual module init
	rts
	
; D0: 0->.. subsong number in the current TFMX module
set_subsong
	movem.l	a0-a1/d0-d3,-(a7)
	lea	track_table(pc),a1
	move.l	module_data(pc),d2
.lookup
	move.l	(a1)+,d3
	bmi.b	.out	; cannot happen
	move.l	(a1)+,d1
	cmp.l	d2,d3
	bne.b	.lookup
	; found, track number in D1, ignore subsong for now (in D0)

	lea	current_track(pc),a0

	cmp.l	#$7BEC4,d2	; title+game over
	bne.b	.set
	
	; now if subsong is not 0 there are special cases (one actually, others
	; are workarounded by load location)
	tst.l	D0
	bne.b	.nonz
	
	; 0: title. If we're coming from "game over" tune, we need
	; to stop song and play the proper one
	cmp.l	#11+1,(a0)
	bne.b	.set
	; game over was played last: stop so play periodic routine
	; plays the proper routine
	bsr		cd_stop
	bra.b	.set
.nonz
	cmp.l	#1,d0
	bne.b	.out
	move.l	#11,d1	; game over is title subsong, loaded at same location
.set
	addq.l	#1,d1
	move.l	d1,(a0)
.out

	movem.l	(a7)+,a0-a1/d0-d3
	; patch module play on the fly (sometimes reloaded)
	move.l	#$4E714E71,$6CF6E
	; original set song
	jmp	$6CEB4
	
	
current_track
	dc.l	0
current_track_stopped
    dc.l    0
    
module_data:
	dc.l	0
	; looks like load locations are always different, allowing to identify
	; tracks 100%, even if there are subsongs sometimes, we don't care
	; (except for game over which is loaded at the same location than title)
track_table:
	dc.l	$7BEC4,1	; title
	dc.l	$4AC76,2	; level 1, walking
	dc.l	$7AD24,3	; boss fight 1, flying, big easy boss
	dc.l	$3DABC,4	; level 2, rocket
	dc.l	$4ABD0,5	; boss 2
	dc.l	$4AD52,6
	dc.l	$41E90,7
	dc.l	$4A0E0,8
	dc.l	$71644,9
	dc.l	$4AC62,10
	dc.l	$4CCB0,3
	dc.l	$23800,1
	dc.l	-1,-1
	


	