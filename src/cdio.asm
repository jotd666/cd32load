	XDEF	stop_akiko_activity
; big beam delay in case of an error, or between 2 reads
; READDELAY: 10000 => 650 ms wait
;            2000  => 130 ms wait
;            approx 1,5 ms per unit

retrydelay:
	GETVAR_L	retrydelay_value,D5
readdelay_d5
.loop1
	tst.l	d5
	beq.b	.nodelay	; don't wait
	move.l  d5,-(a7)
    move.b	$dff006,d5
.loop2
	cmp.b	$dff006,d5
	beq.s	.loop2
	move.l	(a7)+,d5
	subq.l	#1,d5
	bne.b	.loop1
.nodelay
	rts

	
start_akiko_activity:
	RTS

	
stop_akiko_activity:
	; completely disabled until proven more useful than harmful
	RTS
	
	; Toni: It probably is also good idea to clear B80024.L to disable all Akiko DMA, it also aborts all still active transfers.
	; Actually it is safer to only clear bits 27, 29, 30 and 31 (DMA bits) and not touch other bits (flags/control bits). 
	; not done...
	
	; JOTD: well, sorry Toni, but this code is toxic on a real CD32. It stops INTENA and never switches it back again
	; so the loading freezes. It works on WinUAE, but not on the real thing
	
	
	;and.l	#AKIKO_DMA_STOP,AKIKO_DMA
	;move.l	#0,AKIKO_INTENA	; disable all Akiko CD interrupts
	;move.w	#0,AKIKO_TRANSFER_REQ ; clear possible still active transfer complete interrupt request.	
	; (It may be active if loader prefetches following sectors and prefetching is still active)
.skip
	rts

	
	
direct_psygore_cdio:
	; Unmute CD32 CD audio ouch it's horrible DON'T DO THAT!!
	;; bset #0,$bfe001

	;; CDIO logging seems to work. Useful when CD32load crashes
	bsr	log_cdio
	
	movem.l	D3-D6/A5,-(a7)
	SET_VAR_CONTEXT
	
	; this routine stops the audio CD (not possible to read audio & data at the same time)
	; so better force CD audio stop, else the next cd audio stop locks up (because of looping test)
	; (if audio wasn't playing, this has no effect)
	
	bsr before_cdio
	

	GETVAR_L	nb_retries,d6
	GETVAR_L	loader,a5

	move.l	d0,d3	; command
.loop
	move.l	d3,d0
	; psygore routine trashes A0 & A1, so if we want to retry...
	movem.l	A0-A1,-(a7)
	jsr		(a5)
	movem.l	(a7)+,A0-A1
	swap	d0
	clr.w	d0		; remove status
	swap	d0
	
	; TEMP introduce bugs to force retry
;	btst	#7,$bfe001
;	bne.b	.nobug
;	tst.l	d6
;	beq	.nobug
;	move.w	#-10,d0
;	cmp.l	#CD_READFILEOFFSET,d3
;	bne.b	.nobug
;	move.l	#CDLERR_READOFFSET,d0	; introduce bug TEMP TEMP
.nobug
	; CD loader sometimes return strange $200 return code or real machine
	; (Chaos Engine 2) but that's probably because of interrupt occurring
	; and trashing the whole thing, so nevermind that
	tst.w	d0
	beq.b	.sk
	
	cmp.w	#CDLERR_NODATA,d0
	beq.b	.retry
	cmp.w	#CDLERR_NODISK,d0
	beq.b	.retry
	cmp.w	#CDLERR_IRQ,d0
	beq.b	.retry
	cmp.w	#CDLERR_DRIVEINIT,d0
	beq.b	.retry
	cmp.w	#CDLERR_BADTOC,d0
	beq.b	.retry
	cmp.w	#CDLERR_READOFFSET,d0
	beq.b	.retry
	cmp.w	#CDLERR_CMDREAD,d0
	beq.b	.retry
	
	; temp if kickstart loaded don't test for those
	TSTVAR_B	disable_file_dir_error
	bne	.sk
	; retry only on some errors
	; we don't want kickemu Examine() call to fail (they test with CURRENTDIR
	; to check if object is a file or a dir, so it can fail)
	; also if a file doesn't exist, it's not necessarily an issue
	; (so we ruled out CDLERR_FILENOTFOUND, CDLERR_DIRNOTFOUND)
	; it's the same when WHDLF_NoError isn't set BTW
	movem.l	d1,-(a7)
	GETVAR_W	whdflags,D1
	and.l	#WHDLF_NoError,d1
	movem.l	(a7)+,d1
	beq.b	.sk
	
	; whatever the error is, just retry
;	bra.b	.retry
	
;	cmp.w	#CDLERR_FILENOTFOUND,d0
;	beq.b	.retry
;	cmp.w	#CDLERR_DIRNOTFOUND,d0
;	beq.b	.retry
;	bra.b	.sk
.retry
	; wait a while before retrying
	TSTVAR_L	debug_flag
	beq.b	.nocol3
	move.w	#$F00,$dff180
.nocol3
	bsr	retrydelay
	TSTVAR_L	debug_flag
	beq.b	.nocol4
	move.w	#$0,$dff180
.nocol4
	dbf	d6,.loop	; retry only if NODISK or CMDREAD (happens on real hardware)
	pea	cdio_error_message(pc)
	bra	SHOW_DEBUGSCREEN_1
.sk

	bsr	after_cdio

	
	movem.l	(A7)+,D3-D6/A5
	rts




; <D0: command: known commands
;  0: read
;  3: get file size
;  4: change directory
; <A0: file/dir name
; <A1: destination (if needed by command: ex read)
; <A2: cd buffers (ex: $1E0000)
; return
; >D0: error code
;  0: OK
;  -$18: file not found
;  -$19: directory not found
;  others????
; >D1: file size (command 3)

	; some games (ex: Pinball Dreams with A6) set up a fixed register which is used during interrupts! Using A6 outside interrupts
	; disrupts game interrupt handling
	; this is not perfect since any register could be used like this, but cdio is the slowest part of the patch code and thus the more
	; likely to set registers used by interrupts.
	; of course, there could be any convention for games doing this: ex: D0 is set with a particular value, but that does not happen.
	; Usually, it's high-end address registers that are used like that: A4?, A5 (seen somewhere I don't remember), A6 (PDreams)
	;
	; cdio uses a lot of registers, that's why cdio code has been protected against it by blocking interrupts
	; we use custom registers instead of SR so cdio can be called from user state

	include	"custom.asm"

	
direct_robnorthen_cdio:
	
	movem.l	d2-d7/A4-A5,-(A7)
	
	moveq.l	#0,D4
	SET_VAR_CONTEXT
	
	bsr	before_cdio

	GETVAR_L	nb_retries,d3

	GETVAR_L	loader,A5
.retry
	movem.l	d0/d3/d4/a0/a1/a2,-(A7)

	
	jsr	(A5)
	move.l	d0,d2	; save return code
	movem.l	(A7)+,d0/d3/d4/a0/a1/a2	; restore parameters for possible retry
	tst.l	D2
	beq.b	.ok
	
	bsr	retrydelay

	; set current dir can return $FFFFFFFB
	cmp.l	#-$18,d2
	beq.b	.filenotfound
	cmp.l	#-$19,d2
	beq.b	.directorynotfound
	dbf	D3,.retry
.err
	pea	cdio_error_message(pc)
	bra	SHOW_DEBUGSCREEN_1

.directorynotfound
.filenotfound
	moveq.l	#-1,D2
.ok
	
	bsr	after_cdio
	
	move.l	D2,D0
	movem.l	(A7)+,d2-d7/A4-A5
	
	rts
	
cdio_error_message:
	dc.b	"cdio read error after nb_retries",0
	even

; < expects A4 with vars

; > D4: saved intena value

before_cdio:
	movem.l	d5/A3,-(a7)
	lea	$dff000,a3
	; this routine (I don't know exactly why) stops the audio CD
	; so better clear the playing flag, else the next cd audio stop locks up (because of looping test)
	bsr	cdaudio_stop
	; experimental: some disk-based games crash when reading data
	; when the cached version works perfectly. Maybe we should wait a while
	; between the reads
	GETVAR_L	readdelay_value,d5
	beq.b	.nodelay
	TSTVAR_L	debug_flag
	beq.b	.nocol1
	move.w	#$0F0,$dff180
.nocol1
	bsr	readdelay_d5
	TSTVAR_L	debug_flag
	beq.b	.nodelay
	move.w	#$000,$dff180
.nodelay
	move.w	(intenar,a3),D4
	move.w	#$0008,(intena,a3)	; disable level 2 interrupts first
	move.w	#$0008,(intreq,a3)	; clear level 2 interrupt request	
	
	SETVAR_B	#1,cdio_in_progress
	TSTVAR_L	cdfreeze_flag
	beq.b	.nofreeze		; if flag is set, then don't freeze interrupts when loading
	move.w	#$7FFF,(intena,a3)	; disable interrupts
.nofreeze
	bsr	start_akiko_activity	; does nothing right now
	movem.l	(a7)+,d5/A3
	rts

after_cdio
	movem.l	A3,-(a7)
	lea	$dff000,a3
	bsr	stop_akiko_activity		; does nothing right now
	CLRVAR_B	cdio_in_progress

	;;bsr	RestoreCIARegs
	or.w	#$8000,D4
	;move.w	#$7FFF,$DFF09C	; clear interrupt requests, some games don't like that!!
	move.w	D4,(intena,a3)	; restore interrupt register state
	movem.l	(a7)+,A3
	rts
	
	; only for Psygore loader
	; logs the parameters values/strings
	; if a "red screen" occurs, the last attempted operation
	; will be displayed
	
log_cdio:
	movem.l	d0/a1-a3,-(a7)
	cmp.l	#CD_DRIVEINIT,d0
	bne.b	.1
	lea	.cddriveinit(pc),a3
.set_read_speed
	bsr	.log_command_name
	lea	.speed2x(pc),a3
	cmp.l	#CDREADSPEEDX1,d1
	bne.b	.2x
	lea	.speed1x(pc),a3	
.2x
	lea	.d1reg(pc),a3
	bsr	.log_parameter_name
	bsr	.log_string_parameter
	bra	.out
.1
	cmp.l	#CD_SETREADSPEED,d0
	bne.b	.2
	lea	.cdsetreadspeed(pc),a3
	bra.b	.set_read_speed
.2
	cmp.l	#CD_CURRENTDIR,d0
	bne.b	.3
	lea	.cdcurrentdir(pc),a3
	bsr	.log_command_name
	lea	.a0reg(pc),a3
	bsr	.log_parameter_name
	move.l	a0,a3
	bsr	.log_string_parameter
	bra	.out
.3
	cmp.l	#CD_GETFILEINFO,d0
	bne.b	.4
	lea	.cdgetfileinfo(pc),a3
	bsr	.log_command_name
	move.l	a0,a3
	bsr	.log_string_parameter
	lea	.a0reg(pc),a3
	bsr	.log_parameter_name
	bra	.out
.4
	cmp.l	#CD_READFILE,d0
	bne.b	.5
	lea	.cdreadfile(pc),a3
	bsr	.log_command_name
	lea	.a0reg(pc),a3
	bsr	.log_parameter_name
	move.l	a0,a3
	bsr	.log_string_parameter
	bra	.out
.5
	cmp.l	#CD_READFILEOFFSET,d0
	bne.b	.out
	
	lea	.cdreadfileoffset(pc),a3
	bsr	.log_command_name
	lea	.a0reg(pc),a3
	bsr	.log_parameter_name
	move.l	a0,a3	; filename
	bsr	.log_string_parameter
	lea	.a1reg(pc),a3
	bsr	.log_parameter_name
	move.l	a1,a3	; dest
	bsr	.log_hex_parameter
	lea	.d1reg(pc),a3
	bsr	.log_parameter_name
	move.l	d1,a3	; size
	bsr	.log_hex_parameter
	lea	.d2reg(pc),a3
	bsr	.log_parameter_name
	move.l	d2,a3	; offset
	bsr	.log_hex_parameter

.out
	movem.l	(a7)+,d0/a1-a3
	rts
	
; < A3: command name
; > A2: buffer to write params to
.log_command_name
	; reset command buffer
	lea	LAST_IO_CALL(pc),a2
.copyname
	move.b	(a3)+,(a2)+
	bne.b	.copyname
	rts
; <> A2: buffer to write param name to
; < A3: string to copy
.log_parameter_name:
	move.b	#',',(-1,a2)
	bsr	.copyname
	subq.l	#1,a2
	move.b	#'=',(a2)+
	clr.b	(a2)+
	rts
	
; <> A2: buffer to write param to
; < A3: string to copy
.log_string_parameter:
	move.b	#'"',(-1,a2)
	bsr	.copyname
	move.b	#'"',(-1,a2)
	clr.b	(a2)+
	rts
; <> A2: buffer to write param to
; < D0: value to write
.log_hex_parameter
	move.l	a3,d0
	subq.l	#1,a2
	move.l	a2,a1
; in: D0: number
; in: A1: pointer to destination buffer
; out: nothing
	bsr	HexToString
	add.l	#10,a2
	rts

.d0reg:
	dc.b	"d0",0
.d1reg:
	dc.b	"d1",0
.d2reg:
	dc.b	"d2",0
.a0reg:
	dc.b	"a0",0
.a1reg:
	dc.b	"a1",0
	
.speed1x:
	dc.b	"1X",0
.speed2x:
	dc.b	"2X",0
.cddriveinit
	dc.b	"CD_DRIVEINIT",0
.cdsetreadspeed
	dc.b	"CD_SETREADSPEED",0
.cdcurrentdir
	dc.b	"CD_CURRENTDIR",0
.cdgetfileinfo
	dc.b	"CD_GETFILEINFO",0
.cdreadfile
	dc.b	"CD_READFILE",0
.cdreadfileoffset
	dc.b	"CD_READFILEOFFSET",0
	even
	
;CD_DRIVEINIT				;init the CD drive
; IN:	D1 = CDREADSPEEDX1 or CDREADSPEEDX2
;	A0 = APTR CD-ROM buffer (24-bit & 64k-aligned (&zeroed) memory, size: $11600 bytes)
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;
;CD_INFOSTATUS				;get info status
; IN:	-
; OUT:	D0 = (CDSTSF.w<<16!CDLERR.w)
;
;CD_SETREADSPEED			;set the CD read speed
; IN:	D1 = CDREADSPEEDX1 or CDREADSPEEDX2
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;
;CD_CURRENTDIR				;set a current dir
; IN:	A0 = APTR full path
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;
;CD_READSECTOR				;read sectors from CD
; IN:	D1 = sector offset
;	D2 = number of sectors (1 sector = 2048 bytes)
;	A1 = APTR destination
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;	D1 = bytes read
;
;CD_GETFILEINFO				;get file size and sector offset
; IN:	A0 = APTR filename
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;	D1 = sector offset
;	D2 = file size
;
;CD_READFILE				;read a file
; IN:	A0 = APTR filename
;	A1 = APTR destination
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;	D1 = bytes read
;
;CD_READFILEOFFSET			;read a file part
; IN:	D1 = size
;	D2 = offset
;	A0 = APTR filename
;	A1 = APTR destination
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;	D1 = bytes read
