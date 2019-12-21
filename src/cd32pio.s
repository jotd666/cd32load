; ugly and experimental PIO mode CD32 CD audio player example
; by Toni Wilen
; converted to fully relocatable code by JOTD
;
	;;include struct.i
	
;SET_VAR_CONTEXT:MACRO
;	lea	vars(pc),a4
;	ENDM
	MC68020
;;CD32DEBUG=0

; defining this enables save/restore of AKIKO DMA&Intena
; it works on WinUAE, but on the real machine, when restoring previous state
; a constant level 2 interrupt is triggered and it results in a lock-up
;;SAVE_RESTORE_BUG

cd_audio_test
	movem.l	d0-A6,-(a7)
	lea $dff000,a6
	lea $b80000,a5


	lea	oldakikointena(pc),a4
	move.l 8(a5),(A4) ;oldakikointena
	lea	oldakikodma(pc),a4
	move.l $24(a5),(a4)  ; oldakikodma
	lea	oldintena(pc),a4
	move.w $1c(a6),(A4) ; oldintena
	move.w #$7fff,$9a(a6)
	lea	oldlev2(pc),a4
	movec	VBR,A3
	move.l ($68,A3),(a4); oldlev2
	lea	_cd_level2_handler(pc),a4
	move.l A4,($68,A3)

	move.w #$7fff,$9c(a6)
	move.w #$c008,$9a(a6)

	moveq.l	#4,D0
	bsr	cdaudio_play_track
	
	bsr	cdaudio_monitor_play_blocking
	
	bsr	cdaudio_stop

	move.w #$7fff,$9a(a6)
	move.w #$7fff,$9c(a6)
	move.l oldakikodma(pc),$24(a5)
	move.l oldakikointena(pc),8(a5)
	movec	VBR,A3
	move.l oldlev2(pc),($68,A3)
	move.w oldintena(pc),d0
	or.w #$8000,d0
	move.w d0,$9a(a6)

	movem.l	(a7)+,d0-A6
	moveq #0,d0
	rts
	
	IFD	SAVE_RESTORE_BUG
; save akiko registers prior to trigger cd play
save_akiko_state:
	movem.l	a4-a5,-(a7)
	SET_VAR_CONTEXT
	lea $b80000,a5
	; don't save registers twice!!!
	; if registers are saved twice without being restored
	; (cd audio loop), then old values are clobbered
	TSTVAR_B	cdaudio_regs_saved
	bne.b	.skip	
	SETVAR_L 8(a5),cdaudio_oldakikointena
	SETVAR_L $24(a5),cdaudio_oldakikodma
	SETVAR_B	#1,cdaudio_regs_saved
.skip
	movem.l	(a7)+,a4-a5
	rts
	
;restore akiko registers like they were before cd play
restore_akiko_state:
	movem.l	a4-a5,-(a7)
	SET_VAR_CONTEXT
	TSTVAR_B	cdaudio_regs_saved
	beq.b	.skip	
	lea $b80000,a5
	; wait until $B80020.W is zero as Toni suggested
.wz
	tst.w	$20(a5)
	bne.b	.wz
	
	; try to clear the remaining interrupts
	clr.b	$1f(a5)
	clr.b	$1d(a5)
	clr.b	$20(a5)	; that one!!!
	
	GETVAR_L cdaudio_oldakikodma,$24(a5)
	GETVAR_L cdaudio_oldakikointena,8(a5)
	; clear the "regs saved" flags, so save_akiko_state saves registers
	CLRVAR_B	cdaudio_regs_saved
.skip
	movem.l	(a7)+,a4-a5
	rts
	ENDC

	
; check CD status
; D0: 0 playing
;     1 playing ended
;     2 not playing/manually stopped
;     3 error ????

cdaudio_status:
	movem.l	d1-A5,-(a7)
	SET_VAR_CONTEXT
	TSTVAR_W	cd_track_playing
	beq.b	.play_not_started
	
	lea $b80000,a5
	moveq #0,d6

	move.w play_status(pc),d0
	tst.b d0
	bmi.s .play_error
	move.b playing_status(pc),d0
	bmi.s .play_ended

	addq.w #1,d6
	cmp.w #2*50,d6
	bne.s .loop4
	lea cmd_led_on(pc),a0
	bsr.w sendcmd
	bra.s .loop6
.loop4
	cmp.w #4*50,d6
	bne.s .loop6
	lea cmd_led_off(pc),a0
	bsr.w sendcmd
	moveq #0,d6
.loop6
	; set flag to "playing"
	moveq.l	#0,d0
	bra	.out

.play_error
	moveq.l	#3,d0
	bra.b	.out
.play_ended
	moveq.l	#1,d0
.out
	movem.l	(a7)+,d1-A5
	rts
.play_not_started
	moveq.l	#2,d0
	bra	.out
	
cdaudio_monitor_play_blocking:
	movem.l	d0-A6,-(a7)
	lea $b80000,a5
	lea $dff000,a6
	moveq #0,d6
.loop
	move.w play_status(pc),d0
	bmi.s .loop5
	tst.b d0
	bmi.s .play_error
	move.b playing_status(pc),d0
	bmi.s .play_ended

; beamdelay between each test
.loop5
	btst #6,$bfe001
	beq.b	.out
	move.b 6(a6),d0
	cmp.b #100,d0
	bne.s .loop5
.loop2
	move.b 6(a6),d0
	cmp.b #100,d0
	beq.s .loop2
	addq.w #1,d6
	cmp.w #2*50,d6
	bne.s .loop4
	lea cmd_led_on(pc),a0
	bsr.w sendcmd
	bra.s .loop6
.loop4
	cmp.w #4*50,d6
	bne.s .loop3
	lea cmd_led_off(pc),a0
	bsr.w sendcmd
	moveq #0,d6
.loop6
	; get current playing position
	; (track, index, MSF absolute and relative position)
	; only if you need to show current play position.
	; same format as TOC entry
	;lea cmd_subq(pc),a0
	;bsr.w sendcmd
.loop3
	btst #6,$bfe001
	bne.s .loop
.out
.play_error
.play_ended
	movem.l	(a7)+,d0-A6
	rts
	
cdaudio_stop:
	movem.l	d0-A6,-(a7)
	SET_VAR_CONTEXT
	TSTVAR_W	cd_track_playing
	beq.b	.out		; if track is not playing, stopping can block

	; set flag to 0 now, because if routine is called twice in a row fast enough
	; this can block as the second routine tries to stop an already stopped audio
	CLRVAR_W	cd_track_playing
		

	lea AKIKO_BASE,a5
	lea cmd_pause(pc),a0
	bsr.w sendcmd

	lea cmd_led_off(pc),a0
	bsr.w sendcmd

	; set the akiko regs just like before cd play
	IFD	SAVE_RESTORE_BUG
	bsr	restore_akiko_state
	ENDC
	
.out
	; stopped
	; mute CD32 CD audio
	bclr #0,$bfe001

	lea	playing_status(pc),a0
	clr.b	(a0)		; so status is correct
	movem.l	(a7)+,d0-A6
	rts
	
; test if track playing. If it doesn't, replay it
cdaudio_replay_track:
	movem.l	d0-d1/a4,-(A7)
	SET_VAR_CONTEXT
	; check if CD track is playing. If it does, check if looped
	GETVAR_W	cd_track_playing,d1
	beq.b	.no_need_to_play
	bsr	cdaudio_status
	cmp.l	#1,d0
	bne.b	.no_need_to_play
	; loop & cd stopped playing and we're in loop mode: play the same track
	moveq.l	#0,d0
	move.w	d1,d0
	moveq.l	#0,d1
	bsr	cdaudio_play_track
.no_need_to_play
	movem.l	(a7)+,d0-d1/a4
	rts
	
; D0: track number
; D1: flags (0: loop play, 1: single play for now)
cdaudio_play_track:
	movem.l	d0-A6,-(a7)
	; enable level 2 interrupt
	lea $dff000,a6
	move.w #$c008,$9a(a6)
	
	; reset playing status
	lea	playing_status(pc),a0
	clr.b	(a0)		; so status is correct

	; Unmute CD32 CD audio
	bset #0,$bfe001
	IFD	SAVE_RESTORE_BUG
	bsr	save_akiko_state
	ENDC
	
	move.l	d0,d6		; track number
	SET_VAR_CONTEXT
	
	not.w	d1	; 0 becomes all ones: 0 means loop
	CLRVAR_W	cd_track_playing
	SETVAR_W	d1,cd_track_loop
	
	lea $b80000,a5
	;enable only pio receive interrupt
	move.l #$20000000,8(a5)		; intena
	; all dma off, other flags not changed
	and.l #$11800000,$24(a5)

	; CD command index counter
	moveq #0,d7

	; flush possible half-transmitted
	; command, 12 bytes is max command length
	moveq #12/2+1-1,d4
flushit
	lea cmd_led_off(pc),a0
	bsr.w sendcmd
	lea cmd_led_on(pc),a0
	bsr.w sendcmd
	dbf d4,flushit

	; get firmware version etc..
	; this also stops the motor
	;lea cmd_info(pc),a0
	;bsr.w sendcmd

	lea cmd_toc(pc),a0
	bsr.w sendcmd
waittoc
;	btst #6,$bfe001
;	beq.s skiptoc
	move.b toc_total(pc),d0
	beq.s waittoc
	cmp.b toc_found(pc),d0
	bne.s waittoc
skiptoc
	; JOTD that doesn't seem needed
	;lea cmd_unpause(pc),a0
	;bsr.w sendcmd

	move.l	d6,d0 ;track number to play (1-99)

	cmp.b toc_total(pc),d0
	bcc.w play_error
	subq.w #1,d0
	bmi.w play_error
	lsl.w #2,d0
	lea toc_data(pc),a1
	add.w d0,a1
	move.b (a1)+,d0
	btst #6,d0 ; data track?
	bne.w play_error
	lea cmd_play+1(pc),a0
	;start
	move.b (a1)+,(a0)+ ;M
	move.b (a1)+,(a0)+ ;S
	move.b (a1)+,(a0)+ ;F
	addq.l #1,a1
	;end

	move.b (a1)+,(a0)+ ;M
	move.b (a1)+,(a0)+ ;S
	move.b (a1)+,(a0) ;F
	IFEQ	1
	; if we play from start to end respecting TOC 100%
	; the next track can be heard during a fraction of a second
	; removing 14 frames allows to fix the glitch (at least on WinUAE it does)
FRAMES_TO_SUB = 14
	cmp.b	#FRAMES_TO_SUB,(a0)
	bcs.b	.nevermind
	sub.b	#FRAMES_TO_SUB,(a0)
.nevermind
	ENDC
	
	lea cmd_play(pc),a0
	bsr.w sendcmd

	lea cmd_unpause(pc),a0
	bsr.w sendcmd
	
	SETVAR_W	d6,cd_track_playing
	
play_error:
	movem.l	(a7)+,d0-A6
	rts
	
sendcmd
	moveq #0,d3
	move.b (a0),d3
	move.b cmd_lengths(pc,d3.w),d3
	beq.s .invalid
	subq.w #1,d3
	; command index counter (1..15)
	addq.b #1,d7
	and.b #15,d7
	bne.s .inc
	moveq #1,d7
.inc
	move.b d7,d1
	lsl.b #4,d1
	move.b (a0)+,d0
	or.b d1,d0
	moveq #-1,d2
	bsr.s sendbyte
.nextbyte
	subq.w #1,d3
	bmi.s .check
	move.b (a0)+,d0
	bsr.s sendbyte
	bra.s .nextbyte
.check
	move.b d2,d0
	bsr.s sendbyte
.invalid
	rts

sendbyte
	move.l 4(a5),d1
	btst #30,d1
	beq.s sendbyte
	sub.b d0,d2
	move.b d0,$28(a5)
	rts

cmd_lengths
	dc.b 1,2,1,1,12,2,1,1,4,1,2,0,0,0,0,0

status_lengths
	dc.b 0,2,2,2,2,2,15,20,0,0,2,0,0,0,0,0

_cd_level2_handler:
	bsr	cd_level2_interrupt
	; this may have been CIA-A timer interrupt
	; remove if you handle CIA-A interrupts properly
	tst.b $bfed01
	move.w #$0008,$dff09c
	rte

	IFEQ	1
; this is a hook to check if the loop flag is set
; if so,
cd_level3_interrupt:
	movem.l d0-d1/a0-a5,-(sp)
	SET_VAR_CONTEXT
	TSTVAR_W	cd_track_playing
	beq.b	.dont_bother
	TSTVAR_W	cd_track_loop
	beq.b	.dont_bother
	; now CD is supposed to be playing AND in loop mode
	; check that the track is still playing, else start it again	
.dont_bother
	movem.l (sp)+,d0-d1/a0-a5
	rts
	ENDC
	
cd_level2_interrupt:
	movem.l d0-d1/a0-a5,-(sp)
	lea $b80000,a5
.moredata
	lea statusout(pc),a3
	moveq #0,d0
	move.w statusoffset(pc),d0
	add.l d0,a3
	move.l 4(a5),d0
	btst #29,d0
	beq.w .nodata
	moveq #0,d0
	move.b $28(a5),d0
	lea	statuspacket_size(pc),a4
	tst.w (a4)		; statuspacket_size
	bne.s .notfirst
	moveq #0,d1
	move.b d0,d1
	; upper 4 bits contain index number of
	; command that generated this status packet
	and.b #15,d1
	move.b status_lengths(pc,d1.w),d1
	addq.w #1,d1 ; checksum
	move.w d1,(A4)  ; statuspacket_size
	lea	statuspacket_offset(pc),a4
	clr.w (A4) ; statuspacket_offset
	lea	statuspacket_start_addr(pc),a4
	move.l a3,(A4);   statuspacket_start_addr
.notfirst	
	move.b d0,(a3)+
	lea	statuspacket_offset(pc),a4
	addq.w #1,(a4)   ; statuspacket_offset
	move.w statuspacket_offset(pc),d0
	cmp.w statuspacket_size(pc),d0
	bcs.s .notyet
	; packet received, check checksum
	moveq #0,d0
	move.l statuspacket_start_addr(pc),a2
	move.w statuspacket_size(pc),d1
.check
	add.b (a2)+,d0
	subq.w #1,d1
	bne.s .check
	cmp.b #$ff,d0
	beq.s .checkok
	IFD CD32DEBUG
	; just a marker to see separate packets in statusout
	lea	statusoffset(pc),a4
	addq.w #4,(A4)  ; statusoffset
	move.b #$ff,(a3)+
	move.b #$55,(a3)+
	move.b d0,(a3)+
	move.b #$ff,(a3)+
	ENDC
	bra.s .checkfail
.checkok
	;checksum ok, do something with the status packet
	move.l statuspacket_start_addr(pc),a0
	bsr.w analyze_status
	IFD CD32DEBUG
	lea	statusoffset(pc),a4
	addq.w #4,(A4)  ; statusoffset
	move.b #$ff,(a3)+
	move.b #$ff,(a3)+
	move.b #$ff,(a3)+
	move.b #$ff,(a3)+
	ENDC
.checkfail
	lea	statuspacket_offset(pc),a4
	clr.w (A4) ; statuspacket_offset
	lea	statuspacket_size(pc),a4
	clr.w (A4)  ; statuspacket_size
	IFND CD32DEBUG
	lea	statusoffset(pc),a4
	clr.w (A4)  ; statusoffset
	ENDC
.notyet
	lea	statusoffset(pc),a4
	addq.w #1,(A4) ; statusoffset
	IFND CD32DEBUG
	cmp.w #statusoutend-statusout,(A4) ; statusoffset
	bcs.w .moredata
	clr.w (A4) ; statusoffset
	ENDC
	bra.w .moredata
.nodata
	
	movem.l (sp)+,d0-d1/a0-a5
	rts

; called from level 2 interrupt
analyze_status
	move.b (a0),d0
	and.b #15,d0
	; TEMP store value here
	;;bsr	log_byte

	cmp.b #6,d0 ;TOC
	bne.w .nottoc
	lea bcdtens(pc),a2
	lea toc_data(pc),a1
	moveq #0,d0
	move.b 5(a0),d0 ;track (bcd)
	
	; TEMP store value here
	;;bsr	log_byte
	
	cmp.b #$a0,d0
	bcs.s .notax
	cmp.b #$a2,d0 ;last msf
	bne.s .nota2
	lea	toc_total(pc),a4
	tst.b (a4); toc_total ;zero? something is wrong.
	beq.w .exitstatus
	move.b toc_total(pc),d0
	subq.b #1,d0
	lsl.w #2,d0
	add.w d0,a1
	tst.b (a1) ;have already?
	bne.w .exitstatus
	; last MSF
	st.b (a1)+
	add.w #10,a0
	move.b (a0)+,(a1)+ ;M (bcd)
	move.b (a0)+,(a1)+ ;S (bcd)
	move.b (a0)+,(a1)+ ;F (bcd)
	lea	toc_found(pc),a4
	addq.b #1,(A4); toc_found
	bra.w .exitstatus
.nota2
	cmp.b #$a1,d0 ;last track
	bne.w .exitstatus
	move.b 10(a0),d0 ;last track number (bcd)
	move.b d0,d1
	lsr.b #4,d1
	move.b 0(a2,d1.w),d1
	and.b #15,d0
	add.b d0,d1
	addq.b #1,d1
	lea	toc_total(pc),a4
	move.b d1,(A4); toc_total ;save total tracks+1
	bra.w .exitstatus
	; normal track entry
.notax
	moveq #0,d1
	move.b d0,d1
	lsr.b #4,d1
	move.b 0(a2,d1.w),d1
	and.b #15,d0
	add.b d0,d1
	subq.b #1,d1 ;min 1
	bmi.w .exitstatus
	cmp.b #99,d1 ;max 99
	bhi.w .exitstatus
	move.w d1,d0
	lsl.w #2,d1 ;*4
	add.w d1,a1
	tst.b (a1)
	bne.s .exitstatus ;already filled
	move.b 3(a0),d0
	move.b d0,d1
	and.b #15,d0
	cmp.b #1,d0 ;position entry?
	bne.s .exitstatus
	move.b d1,(a1)+ ; ctrladr
	add.w #10,a0
	move.b (a0)+,(a1)+ ;M (bcd)
	move.b (a0)+,(a1)+ ;S (bcd)
	move.b (a0)+,(a1)+ ;F (bcd)
	lea	toc_found(pc),a4
	addq.b #1,(A4); toc_found
	bra.s .exitstatus
	
.nottoc
	; don't change, most play status bits
	; are unknown and not checked by
	; existing code, this does same
	; tests as KS ROM code.
	cmp.b #4,d0 ;play status
	bne.s .notplay
	move.b 1(a0),d1
	lea	play_status(pc),a4
	clr.b (A4); play_status
	move.b d1,(1,A4) ; play_status+1
	and.b #$78,d1
	lea	playing_status(pc),a4
	tst.b (A4)  ;playing_status
	bne.s .notstart
	cmp.b #8,d1
	bne.s .notstart
	; now playing
	move.b #1,(A4); playing_status
	bra.s .notplay
.notstart
	cmp.b #1,(A4) ; playing_status
	bne.s .notplay
	tst.b d1
	bne.s .notplay
	; end reached
	move.b #-1,(A4); playing_status	
.notplay

.exitstatus
	rts

bcdtens
	dc.b 0,10,20,30,40,50,60,70,80,90
	even

cmd_toc
	dc.b $04, $00,$00,$00, $00,$00,$00, $03,$00,$00,$00,$00

cmd_play
	dc.b $04, $00,$00,$00, $00,$00,$00, $00,$00,$00,$04,$00
	; $4 + BCD START MSF + BCD END MSF

cmd_stop
	dc.b $01

cmd_pause
	dc.b $02

cmd_unpause
	dc.b $03

cmd_led_on
	dc.b $05,$01

cmd_led_off
	dc.b $05,$00

cmd_subq
	dc.b $06

cmd_info
	dc.b $07

	even

play_status
	dc.w -1
playing_status
	dc.b 0
	even

TOC_SIZE = 4

toc_total
	dc.b 0 ;tracks+1
toc_found
	dc.b 0
	; very minimal toc data
	;0 = CTRL/ADR field
	;1 = M (BCD)
	;2 = S (BCD)
	;3 = F (BCD)
toc_data
	dcb.b TOC_SIZE*100,0

oldakikointena
	dc.l 0
oldakikodma
	dc.l 0
oldintena
	dc.w 0
oldlev2
	dc.l 0
	
statuspacket_size
	dc.w 0
statuspacket_offset
	dc.w 0
statuspacket_start_addr
	dc.l 0

statusoffset
	dc.w 0
statusout
	IFD CD32DEBUG
	dcb.b 65536,0
	ELSE
	; technically only 22 bytes needed
	; but added some extra space if sender
	; and receiver goes out of sync
	dcb.b 48,0
	ENDC
statusoutend
