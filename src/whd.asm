	MC68020
; WHDLoad emulation source code
; relocatable routines
ALL_FRONT_BUTTONS_MASK = JPF_BTN_RED|JPF_BTN_BLU|JPF_BTN_PLAY|JPF_BTN_GRN|JPF_BTN_YEL

DEF_WHDOFFSET:MACRO
	bra.w	jst_\1
	CNOP	0,4
	ENDM	

DEF_WHDHOOK_OFFSET:MACRO
	bra.w	hook_\1
	CNOP	0,4
	ENDM	

DEF_WHDHOOK:MACRO
hook_resload_\1:
	movem.l	d3/a3/a4,-(a7)
	lea	whd_call_params(pc),a3
	movem.l	d0-d2/a0-a2,(a3)		; store params
	; call whd emu function
	bsr	jst_resload_\1
	; then call hook if set
	SET_VAR_CONTEXT
	GETVAR_L	\1_hook_address,d3
	beq.b	.nohook
	movem.l	d0-d1,-(A7)		; save return(s) from orig whd call
	; call the hook with original params
	lea	whd_call_params(pc),a3
	movem.l	(A3),d0-d2/a0-a2		; restore params	
	move.l	d3,a3	; hook
	jsr	(a3)
	movem.l	(a7)+,d0-d1		; restore orig whd call return code
.nohook
	movem.l	(a7)+,d3/a3/a4
	rts
	ENDM
	
SET_VAR_CONTEXT_2:MACRO
	bsr	load_context
	ENDM
	

RUNTIME_ERROR_ROUTINE:MACRO
RunTime_\1:
	pea	0.W
	pea	RTMess\1(pc)
	bra	SHOW_DEBUGSCREEN_2
RTMess\1:
	;dc.b	10,"Run-Time Error: "
	IFD	BARFLY
	dc.b	"\2"
	ELSE
		IFD	MAXON_ASM
		dc.b	"\2"
		ELSE
		dc.b	\2	; phxass
		ENDC
	ENDC

	dc.b	10,0
	even
	ENDM

; define the hookable resload calls, not all calls are needed, only the ones
; you can plug yourself after to add stuff
	DEF_WHDHOOK	Decrunch
	DEF_WHDHOOK	DiskLoad
	DEF_WHDHOOK	LoadFile
	DEF_WHDHOOK	LoadFileDecrunch
	DEF_WHDHOOK	LoadFileOffset
	DEF_WHDHOOK	Patch
	DEF_WHDHOOK	PatchSeg
	DEF_WHDHOOK	Relocate

whd_call_params:
	ds.l	6		; D0-D2/A0-A2 max args
whd_return_values:
	ds.l	2		; D0-D1 max

; to read the CD we need a 64k-aligned memory buffer of $11600 bytes
; but what if the game (AGA/2MB) has no free space at $1E0000 or any other aligned location below?
; we're stuck! wait. No. What if the game has free space say at $1E1000? or at any other location?
; the cd buffer selection mechanism is activated if
; - secondary/alternate cd buffer is set
; - free buffer is set
; in that case, the program selects which cd buffer is best, stores the original contents in free buffer, 
; initializes it each time and performs cd operation

; < A4: variable context (SET_VAR_CONTEXT)
; < A1: destination buffer, or 0 if no selection
prepare_cdio_buffer:	
	TSTVAR_L	cdio_buffer_2
	beq.b	.out		; no alternate cd buffer: out
;.g
;	move.w	#$0F0,$DFF180
;	bra.b	.g
	
	STORE_REGS	A0-A3/D0-D1
	lea	$DFF000,A3
	; shut off DMA to avoid screen corruption
	SETVAR_W	(dmaconr,A3),saved_dmacon
	move.w	#$7FFF,(dmacon,A3)

	GETVAR_L	cdio_buffer_1,A0
	move.l	A1,D0
	beq.b	.choice_done	; A1 = 0: select first one
	; choose buffer 1 or 2 depending on A1
	; since we don't have the read length, we have to decide only on start address
	; the buffers have to be far enough or errors could be done
	; (this is an empiric setting for each game which needs it, which fortunately is limited to AGA
	; games lacking a 64k-aligned $11600-byte spare zone)
	GETVAR_L	cdio_buffer_2,A2
	move.l	A2,A3
	add.l	#CD_BUFFER_SIZE,A3	; b2+size
	cmp.l	A3,A1
	bcc.b	.choose_b2	; if dest is above b2+buffer_size, it is above both buffers, take the second buffer: no risk at all
	cmp.l	A2,A1
	; if dest is above b2 (and below b2+buffer_size), it means that it is within b2: choose b1 since b2 would fail for sure
	bcc.b	.choice_done
	; here dest is below b2. 
	cmp.l	A1,A0
	bcc.b	.choose_b2	; if below b1, choose b2. minimize overwrite risk if too much data read
	; here dest is between b1 and b2: this is tricky, specially if b1 and b2 are close
	; which is a bad (user) choice but maybe the only one
	move.l	A0,A3
	add.l	#CD_BUFFER_SIZE,A3	; b1+size
	cmp.l	A3,A1
	bcc.b	.choice_done	; if dest is above b1+buffer_size, choose b1, no risk at all
	; here dest is between b1 and b1+buffer_size: choose b2 since b1 would fail for sure
.choose_b2
	move.l	A2,A0
.choice_done:	; A0 contains the selected CD buffer
	SETVAR_L	A0,cdio_buffer	; selects it
	CMPVAR_L	free_buffer_caching_address,A0	; is it the same as last time?
	bne.b	.do_init	; no (or zero)
	; same cd buffer as before: means that contents is in free buffer
	; swap should be enough to set cd buffer in the same state as before
	bsr	swap_buffers
	bra.b	.outrr
.do_init
	SETVAR_L	A0,free_buffer_caching_address	; link cd buffer with free buffer by remembering last cache address
	; save memory into free buffer
	GETVAR_L	free_buffer,A1
	move.l		#CD_BUFFER_SIZE/4-1,D0
.c
	move.l	(A0)+,(A1)+
	dbf	D0,.c
	; initialize CD and set directory
	GETVAR_L	init_drive,A1
	JSR	(A1)
.outrr
	RESTORE_REGS	A0-A3/D0-D1
.out
	rts
	
swap_buffers:
	GETVAR_L	free_buffer,A1
	GETVAR_L	cdio_buffer,A0
	move.l	#CD_BUFFER_SIZE/4-1,d0
	; swap memory buffers
.c
	move.l	(A0),D1
	move.l	(A1),(A0)+
	move.l	D1,(A1)+
	dbf	D0,.c
	rts
	
; restore data from free_buffer to cdio_buffer which
; is used by the game
restore_game_memory:
	TSTVAR_L	cdio_buffer_2
	beq.b	.out		; no alternate cd buffer: out
	STORE_REGS	A0-A1/D0-D1
	bsr	swap_buffers
	; restore DMA
	GETVAR_W	saved_dmacon,D0
	bset	#15,D0
	move.w	D0,dmacon+$DFF000
	RESTORE_REGS	A0-A1/D0-D1
	bsr	flush_caches
.out
	rts

; < A0: buffer start

clear_cdio_buffer:
	STORE_REGS	D0/A0
	move.l	#CD_BUFFER_SIZE/4-1,d0
.c
	clr.l	(A0)+
	dbf	D0,.c
	RESTORE_REGS	D0/A0
	rts

PG_InitDrive:

	;psygore CDIO
	;---init the drive
	; what's really needed is a good old zero memory!
	; else CD won't init on real hardware
	GETVAR_L	cdio_buffer,A0
	bsr		clear_cdio_buffer
	
	moveq	#CD_DRIVEINIT,d0
	moveq	#CDREADSPEEDX2,d1
	TSTVAR_L	cdreadspeedx1_flag
	beq.b	.zap_1x
	moveq	#CDREADSPEEDX1,d1
.zap_1x
	bsr	direct_psygore_cdio
	tst.w	d0
	beq	.cd
	bsr	cdinit_error
.cd
	; change data directory
	LEAVAR	data_directory,A0
	addq.l	#4,A0	; skip "CD0:"
	moveq	#CD_CURRENTDIR,d0
	bsr	direct_psygore_cdio
	tst.w	d0
	beq	.out
	bsr	cdlock_error
.out
	rts
	
RN_ResetCurrentDir:
	STORE_REGS	A0
	sub.l	A0,A0
	bsr	prepare_cdio_buffer		; now we compute best cd buffer. Since A0=0, it will be main
	GETVAR_L	cdio_buffer,A2
	MOVEQ	#4,D0			; cd
	LEAVAR	data_directory,A0
	bsr	robnorthen_cdio
	bsr	restore_game_memory		; now we restore memory overwritten by cd operation
	RESTORE_REGS	A0
	rts
	
RN_SetCurrentDir:
	STORE_REGS	D2-D3/A0-A2
; < D1: dirname (modified)
; < D2: filename
; < D3: max buffer size
; > D0: !=0 if ok, =0 if buffer overflow

; cd buffer must be the correct one or this won't work

	LEAVAR	data_directory,A1
	move.l	A1,d0
	lea	current_dir_buffer(pc),A2
	move.l	A2,d1
	bsr	StrcpyAsm
	move.l	a0,d2
	move.l	#$100,D3
	bsr	AddPart		; full path of dir to cd to
	move.l	A2,A0
	MOVEQ	#4,D0			; cd
	GETVAR_L	cdio_buffer,A2
	bsr	robnorthen_cdio	; cannot fail or blue screen within the routine
	RESTORE_REGS	D2-D3/A0-A2
	rts

PG_ResetCurrentDir:
	STORE_REGS	A0
	LEAVAR	data_directory,A0
	addq.l	#4,A0	; skip "CD0:"
	moveq	#CD_CURRENTDIR,d0
	bsr	psygore_cdio
	tst.w	d0
	beq	.out
	bsr	cdlock_error
.out
	RESTORE_REGS	A0
	rts

PG_SetCurrentDir:
	STORE_REGS	D2-D3/A0-A2
; < D1: dirname (modified)
; < D2: filename
; < D3: max buffer size
; > D0: !=0 if ok, =0 if buffer overflow

	SETVAR_B	#1,disable_file_dir_error
	LEAVAR	data_directory,A1
	addq.l	#4,A1	; skip "CD0:"
	move.l	A1,d0
	lea	current_dir_buffer(pc),A2
	move.l	A2,d1
	bsr	StrcpyAsm
	move.l	a0,d2
	move.l	#$100,D3
	bsr	AddPart		; full path of dir to cd to
	move.l	A2,A0
	moveq	#CD_CURRENTDIR,d0
	bsr	psygore_cdio
	CLRVAR_B	disable_file_dir_error
	RESTORE_REGS	D2-D3/A0-A2
	rts

current_dir_buffer:
	blk.b	256,0

	; macro to define a pre-function which initializes the drive only if needed
	; (if game runs fully from 1 disk preloaded in RAM then no need to access CD/HD from CD32load at all)
CDIO_WITH_INIT:MACRO
\1_cdio:
	STORE_REGS	D0/A4
	SET_VAR_CONTEXT
	TSTVAR_L	cdio_buffer_2
	bne.b	.already_ok		; is done each time, with a different address depending on destination
	; initialize drive when needed (if no file is needed, then RAM loader: never init drive)
	GETVAR_L	init_drive,D0
	beq.b	.already_ok
	STORE_REGS	D1-D7/A0-A6
	move.l	d0,a3
	jsr	(A3)
	RESTORE_REGS	D1-D7/A0-A6
	CLRVAR_L	init_drive	; tell it's already initialized
.already_ok

	RESTORE_REGS	D0/A4
	bra	direct_\1_cdio
	ENDM
	
direct_force_cdio:
	rts
	
	CDIO_WITH_INIT	psygore
	CDIO_WITH_INIT	robnorthen
	; dummy call force_cdio
	CDIO_WITH_INIT	force
		
RN_InitDrive:
	GETVAR_L	cdio_buffer,A0
	bsr		clear_cdio_buffer	; not sure if needed with RN loader, but better safe than sorry!!
	
	MOVEQ	#4,D0			; cd
	move.l	A0,A2
	LEAVAR	data_directory,A0
	;;move.l	read_buffer_address(pc),A1		; useful?
	bsr	direct_robnorthen_cdio	; cannot fail or blue screen within the routine
	rts
	
GetAttnFlags:
	MOVEM.L	A4,-(A7)
	SET_VAR_CONTEXT
	GETVAR_L	attnflags,D0
	MOVEM.L	(A7)+,A4
	RTS

; < A5: routine to jump to in supervisor mode
supervisor:
	STORE_REGS	A3-A4
	SET_VAR_CONTEXT
	GETVAR_L	resload_vbr,A3
	add.l	#$80,A3
	move.l	(A3),-(A7)
	move.l	A5,(A3)	; $E vector of trap
	TRAP	#0	; to be sure to be in supervisor state
	move.l	(sp)+,(A3)
	RESTORE_REGS	A3-A4
	rts

discache_supcode:
	STORE_REGS	D0
	moveq.l	#0,d0
	movec	D0,CACR
	RESTORE_REGS	D0
	RTE
	; *** Flushes the caches
; *** called from supervisor state only

flushcache_supcode
	STORE_REGS	D0/D1/A5/A6
	BSR.B	FlushCachesSup
	RESTORE_REGS	D0/D1/A5/A6
	RTE
		

flush_caches:
	STORE_REGS	D0/A4/A5
	SET_VAR_CONTEXT
	TSTVAR_B	vbl_redirect
	beq.b	.novblredirect
	
	lea	handle_6C(pc),A5
	cmp.l	$6C.W,A5
	beq.b	.novblredirect		; interrupt already installed: OK
	; interrupt not installed/overwritten by game
	SETVAR_L	$6C.W,game_vbl_interrupt ; save for chained call
	move.l	A5,$6C.W		; re-install
.novblredirect
	bsr	GetAttnFlags	; leave JSRGEN here
	BTST	#AFB_68020,D0
	beq.b	.exit		; no 68020: no cache flush
.hard:
	lea	flushcache_supcode(pc),A5
	bsr	supervisor
.exit
	RESTORE_REGS	D0/A4/A5
	RTS	


	cnop	0,4

; *** Flushes the caches, called only if 68020+

FlushCachesSup:
	ORI.W	#$0700,SR	; freeze interrupts
	bsr	GetAttnFlags
	MC68020
	MOVEC	CACR,D1		; gets current CACR register
	MC68000
	BSET	#CACRB_ClearI,D1
	BTST	#AFB_68030,D0
	BEQ.B	.no030
	BSET	#CACRB_ClearD,D1
.no030:
	MC68020
	MOVEC	D1,CACR
	MC68000
	BTST	#AFB_68040,D0
	BEQ.B	.no040

	MC68040
	CPUSHA	BC
	MC68000
.no040:
	RTS	

load_context:
	SET_VAR_CONTEXT
	rts
	
; *** Read Disk Part
;     Reads a part of a diskfile

; < D0.W disk unit
; < D1.L length in bytes
; < D2.L offset in bytes
; < A0   output buffer

; > D0   0 if everything went OK

ReadDiskPart:
	STORE_REGS	D1/A0/A1/A3/A4
	lea	.diskunit(pc),A4
	move.b	D0,(A4)
	add.b	#'1',(A4)
	move.l	a0,a1	; destination
	SET_VAR_CONTEXT
	lea	.diskname(pc),a0
	GETVAR_L	read_file_part,A3
	JSR	(A3)
	tst	d0
	bne	read_file_error		; cannot afford to miss a diskfile, whatever the config (noerror included)
	
	RESTORE_REGS	D1/A0/A1/A3/A4
	moveq.l	#0,d0
	rts
	
.diskname:
	dc.b	"disk."
.diskunit:
	dc.b	0,0
	even
	
cdinit_error:
	pea	0.W
	pea	.cdinit_error(pc)
	bra	SHOW_DEBUGSCREEN_2
.cdinit_error:
	dc.b	"Unable to initialize CD drive",0
	even

cdlock_error:
	move.l	d0,d2	; error code in d2, maybe will help
	LEAVAR	data_directory,A0
	move.l	a0,d0
	lea	.dirname(pc),a1
	move.l	a1,d1
	bsr	StrcpyAsm
	pea	0.W
	pea	.cdlock_error(pc)
	bra	SHOW_DEBUGSCREEN_2
.cdlock_error:
	dc.b	"Unable to lock directory "
.dirname
	blk.b	80,0
	even
	
; < A0: filename
packed_file_error:
	move.l	A0,d0
	lea	.filename(pc),a0
	move.l	a0,d1
	bsr	StrcpyAsm
	pea	0.W
	pea	.packed_files_error(pc)
	bra	SHOW_DEBUGSCREEN_2
.packed_files_error:
	dc.b	"XPKF packed files is not supported: "
.filename:
	blk.b	40,0
	even
	

; < A0: filename
read_file_error:
	move.l	d0,d2	; error code
	move.l	A0,d0	; filename
	lea	.filename(pc),a0
	move.l	a0,d1
	bsr	StrcpyAsm	; copy in message
	move.l	a0,d0
	bsr	StrlenAsm
	add.l	d0,a0
		
	move.l	d2,$100.W	; TEMP
	
	move.b	#' ',(a0)+
	move.b	#'-',(a0)+
	neg.w	d2
	cmp.w	#10,d2
	bcs.b	.ltt
	move.b	#'1',(a0)+	; Psygore IO error code cannot be above 19
	sub.w	#10,d2
.ltt
	add.b	#'0',d2
	move.b	d2,(a0)+	; Psygore IO error code
	clr.b	(a0)
	moveq.l	#0,d0
	lea	.filename(pc),a0
	pea	0.W
	pea	.read_file_error(pc)
	bra	SHOW_DEBUGSCREEN_2
.read_file_error:
	dc.b	"File read error: "
.filename:
	dc.b	"????"
	blk.b	102,0
	even

	
; ReadFile: read fully a file
; (direct load to buffer, no cache)
; < D0: command (0: read, 5 length)
; < A0: filename
; < A1: buffer (when D0=0)

; > D0: 0 if OK
; > D1: file length

RN_ReadFile:
	RELOC_STACK
	STORE_REGS	D2-A6
	move.l	D0,D2	;command
	move.l	A1,A5	; save buffer
	SET_VAR_CONTEXT
	
	; first get file size
	; parameters match closely the CD interface
	MOVEQ	#3,D0			; get size
	bsr	prepare_cdio_buffer	; uses A1 to choose which buffer to use
	GETVAR_L	cdio_buffer,A2
	bsr	robnorthen_cdio
	bsr	restore_game_memory
	tst.l	d0
	beq.b	.sizeok
	GETVAR_W	whdflags,D1
	and.l	#WHDLF_NoError,d1
	beq.b	.nopack
	; NoError is set: fail
	bra	read_file_error
.sizeok
	cmp.w	#5,D2
	beq.b	.nopack
	
	
	tst.w	D2
	beq.b	.ok
	; wrong command passed in D0
	pea	0.W
	pea	.wrong_readfile_command(pc)
	bsr	SHOW_DEBUGSCREEN_2
.ok
	; check that A1+D1 is not above max machine chip
	; TODO: now that cd address is configurable, check if does not overlap
	IFEQ	1
	move.l	A1,A2
	add.l	D1,A2
	CMPVAR_	#cdio_buffer_ADDRESS,A2
	bcs		.inrange

	pea	0.W
	pea	.read_buffer_overflow(pc)
	bsr	SHOW_DEBUGSCREEN_2

.inrange
	ENDC
	
	; parameters match closely the CD interface
	MOVEQ	#0,D0			; read
	bsr	prepare_cdio_buffer	; uses A1
	GETVAR_L	cdio_buffer,A2
	bsr	robnorthen_cdio
	bsr	restore_game_memory

.done
	move.l	(A5),D2
	cmp.l	#'XPKF',D2	; XPK packed files not supported
	bne.b	.nopack
	
	bra	packed_file_error
	
.nopack
	RESTORE_REGS	D2-A6
	UNRELOC_STACK
	rts

.wrong_readfile_command:
	dc.b	"Wrong ReadFile command",0
.read_buffer_overflow
	dc.b	"Read buffer overflow",0
	even
	
; ReadFile: read fully a file
; (direct load to buffer, no cache)
; < D0: command (0: read, 5 length)
; < A0: filename
; < A1: buffer (when D0=0)

; > D0: 0 if OK
; > D1: file length

PG_ReadFile:	
	RELOC_STACK
	STORE_REGS	D2/A4
	SET_VAR_CONTEXT
	tst.w	D0
	beq.b	.read
	cmp.w	#5,D0
	beq.b	.getsize
	; wrong command passed in D0
	pea	0.W
	pea	.wrong_readfile_command(pc)
	bsr	SHOW_DEBUGSCREEN_2
.getsize
	;  get file size
	; parameters match closely the CD interface
	MOVEQ	#CD_GETFILEINFO,D0			; get size
	bsr	prepare_cdio_buffer	; uses A1
	bsr	psygore_cdio
	bsr	restore_game_memory
	tst.w	d0
	beq.b	.sizeok
	cmp.w	#CDLERR_FILENOTFOUND,d0
	bne	read_file_error
	GETVAR_W	whdflags,D1
	and.l	#WHDLF_NoError,d1
	beq.b	.nopack
	; NoError is set: fail
	bra	read_file_error
.sizeok
	move.l	D2,D1	; size in D1
	bra.b	.nopack
.read
	; parameters match closely the CD interface
	MOVEQ	#CD_READFILE,D0			; read
	bsr	prepare_cdio_buffer	; uses A1
	bsr	psygore_cdio
	bsr	restore_game_memory
	
	tst.w	d0
	beq.b	.done
	cmp.w	#CDLERR_FILENOTFOUND,d0
	bne	read_file_error
	GETVAR_W	whdflags,D1
	and.l	#WHDLF_NoError,d1
	bne		read_file_error
.done
	move.l	(A1),D2
	cmp.l	#'XPKF',D2	; XPK packed files not supported
	bne.b	.nopack
	
	bra	packed_file_error
	
.nopack
	RESTORE_REGS	D2/A4
	UNRELOC_STACK
	rts

.wrong_readfile_command:
	dc.b	"Wrong ReadFile command",0
.read_buffer_overflow
	dc.b	"Read buffer overflow",0
	even

	
PG_ReadFilePartWithCache:
; with filecache, multiple buffers are not supported/not useful
; or we couldn't use filecache
	RELOC_STACK
	STORE_REGS	D2-A6
	
	SET_VAR_CONTEXT
	
	move.l	D1,D5		; len
	move.l	D2,D6		; offset
	move.l	A1,A3		; dest buffer
	move.l	A0,A5		; filename
	
	
	move.l	A0,d0
	LEAVAR	last_loaded_file,a2
	move.l	a2,d1
	bsr	StrcmpAsm
	tst.l	D0
	beq	file_in_cache
	; store filename for cache

	move.l	A5,D0
	move.l	A2,D1

	
	bsr	StrcpyAsm
;	move.l	A2,D0
;	bsr	ToUpperAsm		; filepath in uppercase
	

	move.l	A5,D0
	lea	filename_buffer(pc),A5
	move.l	A5,D1
	bsr	StrcpyAsm	
;	move.l	A5,D0
;	bsr	ToUpperAsm		; filepath in uppercase
	
	GETVAR_L	cdio_buffer,A2

	TSTVAR_L	nobuffercheck_flag		; don't check for overlap
	bne.b	.nocheck1

	GETVAR_L	read_buffer_address,A1
	sub.l	#CD_BUFFER_SIZE,A1
	cmp.l	A1,A2

	bcs.b	.nocheck1	; cd buffer way is below dest: OK
	GETVAR_L	read_buffer_address,A1
	cmp.l	A1,A2
	bcs		outofbounds	; cd buffer just is below dest: OK
.nocheck1	
	GETVAR_L	read_buffer_address,A1
	; parameters match closely the CD interface
	lea	filename_buffer(pc),A0
	MOVEQ.L	#CD_GETFILEINFO,D0			; get size
	bsr	psygore_cdio
	tst.w	d0
	bne	file_not_found
	move.l	d2,d1	; d2 holds size, d1=sector offset, we don't care
	SETVAR_L	D1,last_loaded_filesize
	
	TSTVAR_L	nobuffercheck_flag		; don't check for overlap
	bne.b	.nocheck2
	
	GETVAR_L	read_buffer_address,A1
	add.l	D1,A1		; buffer+filesize
	CMPVAR_L	top_system_chipmem,A1
	bcc		outofbounds
	cmp.l	A2,A1
	bcc		outofbounds
	
.nocheck2
	
	lea	filename_buffer(pc),A0
	MOVEQ.L	#CD_READFILE,D0			; read
	GETVAR_L	read_buffer_address,A1
	bsr	psygore_cdio
	tst.w	d0
	beq	readok
	bra		file_not_found
	
; ReadFilePart. generic version
; < A0: filename
; < A1: buffer
; < D0: unused
; < D1: length to read (-1: till the end)
; < D2: offset to read from

; > D0: 0 if OK
; > D1: file length

RN_ReadFilePart:
	RELOC_STACK
	STORE_REGS	D2-A6
	
	SET_VAR_CONTEXT
	
	move.l	D1,D5		; len
	move.l	D2,D6		; offset
	move.l	A1,A3		; dest buffer
	move.l	A0,A5		; filename
		
	
	move.l	A0,d0
	LEAVAR	last_loaded_file,a2
	move.l	a2,d1
	bsr	StrcmpAsm
	tst.l	D0
	beq	file_in_cache
	; store filename for cache

	move.l	A5,D0
	move.l	A2,D1
	bsr	StrcpyAsm
	

	move.l	A5,D0
	lea	filename_buffer(pc),A5
	move.l	A5,D1
	bsr	StrcpyAsm	
	;move.l	A5,D0
	;bsr	ToUpperAsm		; filepath in uppercase
	
	GETVAR_L	cdio_buffer,A2
	GETVAR_L	read_buffer_address,A1
	sub.l	#CD_BUFFER_SIZE,A1
	cmp.l	A1,A2
	bcs.b	.oklow	; cd buffer way is below dest: OK
	GETVAR_L	read_buffer_address,A1
	cmp.l	A1,A2
	bcs		outofbounds	; cd buffer just is below dest: OK
	
	; parameters match closely the CD interface
	lea	filename_buffer(pc),A0
	MOVEQ	#3,D0			; get size
	bsr	robnorthen_cdio
	tst.l	d0
	bne.b	file_not_found
	
	SETVAR_L	d1,last_loaded_filesize		; store size
	
	GETVAR_L	read_buffer_address,A1
	add.l	D1,A1		; buffer+filesize
	CMPVAR_L	top_system_chipmem,A1
	bcc		outofbounds
	TSTVAR_L	nobuffercheck_flag		; don't check for overlap
	bne.b	.oklow
	cmp.l	A2,A1
	bcc		outofbounds
	
.oklow
	
	lea	filename_buffer(pc),A0
	MOVEQ	#0,D0			; read
	GETVAR_L	read_buffer_address,A1
	bsr	robnorthen_cdio
	tst.l	d0
	beq.b	readok
	
	; common part RN loader / PG loader with cache
file_not_found
	GETVAR_W	whdflags,d1
	and.l	#WHDLF_NoError|WHDLF_Disk,d1
	beq.b	rfp_exit
	bra	read_file_error
readok
	GETVAR_L	read_buffer_address,A1
	move.l	(A1),D2
	cmp.l	#'XPKF',D2	; XPK packed files not supported
	bne.b	file_in_cache
	
	bra	packed_file_error

file_in_cache

	GETVAR_L	read_buffer_address,A0
	add.l	D6,A0	; add offset
	move.l	D5,D0	; len
	bpl.b	.limit_len
	; read till the end: we have to use size to compute actual size
	GETVAR_L	last_loaded_filesize,D0
	sub.l	d6,d0
.limit_len
	move.l	A3,A1	; dest
	
	TSTVAR_L	nobuffercheck_flag
	bne.b	.allowed_mem
	
	; check dest within chip+expmem bounds or within slave (we don't have MMU)
	move.l	A1,D2
	add.l	D0,D2
	tst.l	D2
	bmi.b	crazymemcpy	; negative? big problem
	GETVAR_L	top_game_mem,A2
	cmp.l	D2,A2
	bcc.b	.allowed_mem
	
	; not in game mem, but maybe in slave mem (allowed too ex: Agony)
	GETVAR_L	whd_slave_reloc_start,A2
	cmp.l	A2,A1		; is slave start > dest start ? if so, cannot be in slave
	bcs.b	crazymemcpy
	ADDVAR_L	slaves_size,A2
	sub.l	D0,A2
	cmp.l	A1,A2		; is dest start + size > slave end  ? if so, cannot be in slave
	bcs.b	crazymemcpy
	
	; ok: reads within slave
.allowed_mem
	; run the copy
	bsr	CopyMem

	moveq.l	#0,D0
	move.l	D5,D1

rfp_exit
	RESTORE_REGS	D2-A6
	UNRELOC_STACK
	rts


	
crazymemcpy:
	UNRELOC_STACK	; so proper A7 is displayed
	pea	.cmc_message(pc)
	bra	SHOW_DEBUGSCREEN_2
.cmc_message:
	dc.b	"Crazy memory copy. Dest=A1, Top=A2, Size=D0",0
	even
outofbounds:
	UNRELOC_STACK	; so proper A7 is displayed
	
	GETVAR_L	cdio_buffer,A2		;0152: 45f9001e0000
	GETVAR_L	read_buffer_address,A1	; and size is in D1
	pea	.outofbounds_msg(pc)
	bra	SHOW_DEBUGSCREEN_2
.outofbounds_msg
	dc.b	"A2=CD buffer/A1=read buffer overlap, D1=size",0
	even
	
filename_buffer:
		blk.b	256,0

; ReadFilePart. generic version
; < A0: filename
; < A1: buffer
; < D1: length to read (-1: till the end)
; < D2: offset to read from

; > D0: 0 if OK
; > D1: file length

PG_ReadFilePart:
	RELOC_STACK
	STORE_REGS	D2/A2-A4
	
	SET_VAR_CONTEXT
	
	move.l	A1,A3		; dest buffer
		
	GETVAR_L	cdio_buffer,A2		;0152: 45f9001e0000
	move.l	A3,A1
	sub.l	#CD_BUFFER_SIZE,A1
	cmp.l	A1,A2
	bcs.b	.oklow	; cd buffer way is below dest: OK
	move.l	A3,A1
	cmp.l	A1,A2
	bcs		outofbounds	; cd buffer just is below dest: OK
.oklow
	tst.l	D1
	bpl.b	.sizeok
	; compute size if -1 (old JST loaders)
	bsr	PG_GetFileSize
	move.l	D0,D1
	beq.b	.notfound	; 0-size is like not found
.sizeok
	MOVEQ	#CD_READFILEOFFSET,D0			; read
	move.l	A3,A1		;014c: 43f900100000
	bsr	prepare_cdio_buffer	; uses A1
	bsr	psygore_cdio
	bsr	restore_game_memory
	tst.w	d0
	beq.b	.readok
	
	cmp.w	#CDLERR_FILENOTFOUND,d0
	bne	read_file_error	; another problem
	; file not found
.notfound
	GETVAR_W	whdflags,d1
	and.l	#WHDLF_NoError|WHDLF_Disk,d1
	beq.b	.exit
	bra	read_file_error
.readok
	tst.l	D2
	bne.b	.ok
	; D2=0 check no XPK at start
	move.l	A3,A1		;014c: 43f900100000
	move.l	(A1),D2
	cmp.l	#'XPKF',D2	; XPK packed files not supported
	bne.b	.ok
	
	bra	packed_file_error

.ok

.exit
	RESTORE_REGS	D2/A2-A4
	UNRELOC_STACK
	rts


		
TRAP_HANDLER:MACRO
exception_\1:
	move.l	$\1.W,-(A7)
	move.l	#($\1/4)-$20,-(A7)	; trap number, for debug
	bra	exception_trap
	ENDM
	
	TRAP_HANDLER	80
	TRAP_HANDLER	84
	TRAP_HANDLER	88
	TRAP_HANDLER	8C
	TRAP_HANDLER	90
	TRAP_HANDLER	94
	TRAP_HANDLER	98
	TRAP_HANDLER	9C
	TRAP_HANDLER	A0
	TRAP_HANDLER	A4
	TRAP_HANDLER	A8
	TRAP_HANDLER	AC
	TRAP_HANDLER	B0
	TRAP_HANDLER	B4
	TRAP_HANDLER	B8
	TRAP_HANDLER	BC
	
exception_trap:
	STORE_REGS	D0/A4
	SET_VAR_CONTEXT
	GETVAR_W	whdflags,D0
	btst	#WHDLB_EmulTrap,D0
	RESTORE_REGS	D0/A4
	bne.b	.ok
	STORE_REGS	D0/A0/A1
	move.l	12(A7),D0
	lea	.trapn(pc),A1
	add.b	#'0',D0
	move.b	D0,(A1)
	RESTORE_REGS	D0/A0/A1
	addq.l	#2,A7
	pea	.divz_message(pc)
	bra	SHOW_DEBUGSCREEN_2
.divz_message:
	dc.b	"TRAP exception #"
.trapn:
	dc.b	0,0
	even
.ok
	addq.l	#4,A7	; pops trap number, leaving trap vector in the stack
	rts				; jump to original trap vector

	
exception_28:
	STORE_REGS	D0/A4
	SET_VAR_CONTEXT
	GETVAR_W	whdflags,D0
	btst	#WHDLB_EmulLineA,D0
	bne.b	.ok
	move.l	10(A7),A0	; reads PC
	move.l	A0,-(A7)
	pea	.divz_message(pc)
	bra	SHOW_DEBUGSCREEN_2
.divz_message:
	dc.b	"LINE-A exception",0
	even
.ok
	RESTORE_REGS	D0/A4
	; call original handler
	MOVE.L	$28.W,-(A7)
	RTS
exception_2C:
	STORE_REGS	D0/A4
	SET_VAR_CONTEXT
	GETVAR_W	whdflags,D0
	btst	#WHDLB_EmulLineF,D0
	bne.b	.ok
	move.l	10(A7),A0	; reads PC
	move.l	A0,-(A7)
	pea	.divz_message(pc)
	bra	SHOW_DEBUGSCREEN_2
.divz_message:
	dc.b	"LINE-F exception",0
	even
.ok
	RESTORE_REGS	D0/A4
	; call original handler
	MOVE.L	$2C.W,-(A7)
	RTS

exception_14:
	STORE_REGS	D0/A4
	SET_VAR_CONTEXT
	GETVAR_W	whdflags,D0
	btst	#WHDLB_NoDivZero,D0
	RESTORE_REGS	D0/A4
	bne.b	.ok
	addq.l	#2,A7
	pea	.divz_message(pc)
	bra	SHOW_DEBUGSCREEN_2
.divz_message:
	dc.b	"Division by zero exception",0
	even
.ok
	; call original handler
	MOVE.L	$14.W,-(A7)
	RTS

exception_1C:
	STORE_REGS	D0/A4
	SET_VAR_CONTEXT
	GETVAR_W	whdflags,D0
	btst	#WHDLB_EmulTrapV,D0
	RESTORE_REGS	D0/A4
	bne.b	.ok
	addq.l	#2,A7
	pea	.divz_message(pc)
	bra	SHOW_DEBUGSCREEN_2
.divz_message:
	dc.b	"TRAPV exception",0
	even
.ok
	; call original handler
	MOVE.L	$1C.W,-(A7)
	RTS

exception_20:

; We will try to see if the opcode which triggered
; the exception is known, and if we can fix it
; by replacing movesr by moveccr
; this was necessary to allow MeGaLoMania to run
; but can be useful in the JST degrader mode (PRIVILEGE function)
; (orsr, andsr not supported at the moment)

	STORE_REGS	D0-D1/A4

	move.w	(A0),D0		; gets opcode
	move.w	D0,D1		; full opcode
	and.w	#$FFF0,D0	; opcode without register number

	cmp.w	#$40C0,D0	; move sr,Dx
	beq	.movesrdx

	cmp.w	#$40F8,D1
	beq	.movesrw

	cmp.w	#$40F9,D1
	beq	.movesrdx
	
	SET_VAR_CONTEXT
	GETVAR_W	whdflags,D0
	btst	#WHDLB_EmulPriv,D0
	RESTORE_REGS	D0-D1/A4
	bne.b	.ok
	addq.l	#2,A7	; PC where it occured
	pea	.priv_message(pc)
	bra	SHOW_DEBUGSCREEN_2
.priv_message:
	dc.b	"Privileged instruction exception",0
	even
.ok
	; call original handler
	MOVE.L	$20.W,-(A7)
	RTS

.movesrw
.movesrdx
	or.w	#$0200,D1	; move sr -> move ccr
	move.w	D1,(A0)		; corrects the code
	bsr	flush_caches	; cache flush

	RESTORE_REGS	D0-D1/A4
	rte
	
EXCEPTION_ROUTINE:MACRO
exception_\1:
	IFD	BARFLY
		IFNE	NARG-3
			DEF_EXCEPTION	<\1>
			DEF_EXCEPTION_HANDLER	<\1>,<\2>
		ELSE
			DEF_EXCEPTION_HANDLER	<\1>,<\2>,<\3>
		ENDC
	ELSE
		IFNE	NARG-3
			DEF_EXCEPTION	\1
			DEF_EXCEPTION_HANDLER	\1,\2
		ELSE
			DEF_EXCEPTION_HANDLER	\1,\2,\3
		ENDC
	ENDC
	ENDM

DEF_EXCEPTION:MACRO
	STORE_REGS	D0/A0

	; before calling original routine, check if not already
	; it (VBR at 0) and in that case, directly call error handler

	LEA	exception_\1(PC),A0
	MOVE.L	$\1.W,D0
	CMP.L	D0,A0
	BEQ.S	exception_handler_\1

	RESTORE_REGS	D0/A0
	MOVE.L	$\1.W,-(A7)		; call original zero page handler. if not initialized, then falls in the handler too
	RTS
	ENDM

DEF_EXCEPTION_HANDLER:MACRO
exception_handler_\1:
	IFNE	NARG-3
		RESTORE_REGS	D0/A0
	ENDIF
	
	STORE_REGS	A4-A5
	lea	exception_message_ptr(pc),A4
	lea	exception_message\1(pc),A5
	move.l	A5,(A4)
	RESTORE_REGS	A4-A5
	bra	UnhandledException
exception_message\1:
	IFD	MAXON_ASM
		dc.b	"\2"
	ELSE
		IFD	BARFLY
			dc.b	"\2"
		ELSE
			DC.B	\2	; phxass
		ENDIF
	ENDIF
	
	dc.b	0
	even
	ENDM

	EXCEPTION_ROUTINE	XX,"Unlisted exception!!","No check"

	EXCEPTION_ROUTINE	08,"Access fault"
	EXCEPTION_ROUTINE	0C,"Address error"
	EXCEPTION_ROUTINE	10,"Illegal instruction"
	DEF_EXCEPTION_HANDLER	14,"Division by zero"	; handled by JST
	EXCEPTION_ROUTINE	18,"CHK, CHK2 instruction"
	DEF_EXCEPTION_HANDLER	1C,"TRAPV or TRAPcc instruction"	; handled by JST
	DEF_EXCEPTION_HANDLER	20,"Privilege violation"	; handled by JST
	EXCEPTION_ROUTINE	24,"Uninitialized trace"
	DEF_EXCEPTION_HANDLER	28,"LINE-A emulation"
	DEF_EXCEPTION_HANDLER	2C,"LINE-F emulation"

	EXCEPTION_ROUTINE	30,"exception $30"

	EXCEPTION_ROUTINE	34,"Coprocessor protocol violation"
	EXCEPTION_ROUTINE	38,"Format error"
	EXCEPTION_ROUTINE	3C,"interrupt $3C"

;	EXCEPTION_ROUTINE	40,"exception $40"
;	EXCEPTION_ROUTINE	44,"exception $44"
;	EXCEPTION_ROUTINE	48,"exception $48"
;	EXCEPTION_ROUTINE	4C,"exception $4C"
;	EXCEPTION_ROUTINE	50,"exception $50"
;	EXCEPTION_ROUTINE	54,"exception $54"
;	EXCEPTION_ROUTINE	58,"exception $58"
;	EXCEPTION_ROUTINE	5C,"exception $5C"

	EXCEPTION_ROUTINE	60,"Spurious interrupt"
	EXCEPTION_ROUTINE	64,"level 1 interrupt"
	EXCEPTION_ROUTINE	68,"level 2 interrupt (Kb, CIA)"
	EXCEPTION_ROUTINE	6C,"level 3 interrupt (VBL, Copper)"
	EXCEPTION_ROUTINE	70,"level 4 interrupt (Audio)"
	EXCEPTION_ROUTINE	74,"level 5 interrupt"
	EXCEPTION_ROUTINE	78,"level 6 interrupt"

	EXCEPTION_ROUTINE	7C,"level 7 interrupt (NMI)"
	DEF_EXCEPTION_HANDLER	80,"TRAP #$0"
	DEF_EXCEPTION_HANDLER	84,"TRAP #$1"
	DEF_EXCEPTION_HANDLER	88,"TRAP #$2"
	DEF_EXCEPTION_HANDLER	8C,"TRAP #$3"
	DEF_EXCEPTION_HANDLER	90,"TRAP #$4"
	DEF_EXCEPTION_HANDLER	94,"TRAP #$5"
	DEF_EXCEPTION_HANDLER	98,"TRAP #$6"
	DEF_EXCEPTION_HANDLER	9C,"TRAP #$7"
	DEF_EXCEPTION_HANDLER	A0,"TRAP #$8"
	DEF_EXCEPTION_HANDLER	A4,"TRAP #$9"
	DEF_EXCEPTION_HANDLER	A8,"TRAP #$A"
	DEF_EXCEPTION_HANDLER	AC,"TRAP #$B"
	DEF_EXCEPTION_HANDLER	B0,"TRAP #$C"
	DEF_EXCEPTION_HANDLER	B4,"TRAP #$D"
	DEF_EXCEPTION_HANDLER	B8,"TRAP #$E"
	DEF_EXCEPTION_HANDLER	BC,"TRAP #$F"

	EXCEPTION_ROUTINE	E4,"MMU E4"
	EXCEPTION_ROUTINE	E8,"MMU E8"
	
PATCH_EXCEPT:MACRO
	PEA	exception_\1(pc)
	MOVE.L	(A7),$\1(A0)		;Patch into the new VBR too ;
	move.l	(A7)+,$\1.W
	ENDM

PATCH_INTVEC:MACRO
	PEA	handle_\1(pc)
	MOVE.L	(A7),$\1(A0)		;Patch into the new VBR too;
	move.l	(A7)+,$\1.W
	ENDM

; enter the debugger from CD32load kill screen
EnterDebugger:
	STORE_REGS	A0
	LEA	debug_at_pc(PC),A0
	MOVE.L	4(A7),(A0)		; saves return address (Stackdependent)
	RESTORE_REGS	A0
	bra	EnterDebuggerEitherWay

; Enter the debugger from game code

EnterDebuggerRestore:
	STORE_REGS	A0/A4
	MOVE.L	8(A7),A0		; gets return address (Stackdependent)
	subq.l	#6,A0			; back 6 instructions
	lea	debug_at_pc(pc),A4
	move.l	a0,(A4)
	SET_VAR_CONTEXT
	GETVAR_L	saved_instructions,(A0)+
	GETVAR_W	saved_instructions+4,(A0)+
	bsr	flush_caches
	RESTORE_REGS	A0/A4
	
	
EnterDebuggerEitherWay:
	STORE_REGS	A0/A1
	bsr	.getvbrA1

	LEA	.oldTRAP0(PC),A0
	MOVE.L	($80,A1),(A0)		; saves old trap vector

	RESTORE_REGS	A0/A1

	PEA	.GO_DEBUGGER(PC)
	STORE_REGS	A1
	bsr.b	.getvbrA1
	MOVE.L	4(A7),($80,A1)		; sets TRAP #0 with .GO_DEBUGGER
	RESTORE_REGS	A1
	ADDQ.L	#8,A7			; pops up return address + .GO_DEBUGGER
	TRAP	#0

	; from here supervisor state and HRTMon returns to the code with an RTE
.GO_DEBUGGER
	STORE_REGS	A1
	bsr.b	.getvbrA1
	MOVE.L	.oldTRAP0(PC),($80,A1)	; restores TRAP #0
	RESTORE_REGS	A1

	MOVE.L	debug_at_pc(PC),2(A7)	; changes return address (for the next RTE)
	MOVE.L	debugger_nmi(PC),-(A7)
	RTS				; enters in the debugger interface pc=debug_at_pc

.getvbrA1:
	STORE_REGS	A4
	SET_VAR_CONTEXT
	LEAVAR	relocated_vbr,A1
	RESTORE_REGS	A4
	rts
	
.oldTRAP0
	DC.L	0
debug_at_pc:
	DC.L	0
debugger_nmi:
	DC.L	0

	
UnhandledException:
	move.w	(A7),$104	; SR
	move.l	2(A7),$100	; PC
	move.l	#'REGS',$10C.W
	movem.l	D0-A6,$110.W	; registers
	
	
	lea	$150.W,A0
	move.l	#'EXCE',(A0)+
	move.l	A0,D1
	move.l	exception_message_ptr(pc),A0
	move.l	A0,D0
	bsr	StrcpyAsm
	
	SET_VAR_CONTEXT
	LEAVAR	last_whd_function_called,A0
	move.l	A0,D0
	lea	$180.W,A1
	GETVAR_B	in_resload,(A1)+
	move.l	#'WHD_',(A1)+
	move.l	A1,D1
	bsr	StrcpyAsm
	LEAVAR	last_whd_parameters,A0
	lea	$1A0.W,A1
	move.l	#'PRMS',(A1)+
	move.l	(A0)+,(A1)+
	move.l	(A0)+,(A1)+
	move.l	(A0)+,(A1)+
	move.l	(A0)+,(A1)+
	move.l	#'PRME',(A1)+
	

	


	addq.l	#2,A7
	move.l	exception_message_ptr(pc),-(a7)
	bra	SHOW_DEBUGSCREEN_2

	
exception_message_ptr:
	dc.l	0
	
RelocateVBR:
	; install default dummy handler to trap everything
	GETVAR_L	novbrmove_flag,D0
	beq.b	.reloc
	sub.l	A2,A2
	bra	.setvbr
.reloc
	LEAVAR	relocated_vbr,A2
	move.l	A2,A0
	lea	exception_XX(pc),A1
	addq.l	#8,A0
	move.l	#$3D,D0
.copy
	move.l	A1,(a0)+
	dbf	D0,.copy

	
	LEAVAR	relocated_vbr,A0
	move.l	#'JST!',(A0)	; mark VBR table
	
	PATCH_EXCEPT	10
	PATCH_EXCEPT	14
	PATCH_EXCEPT	18
	PATCH_EXCEPT	1C
	PATCH_EXCEPT	20
	PATCH_EXCEPT	24
	PATCH_EXCEPT	28
	PATCH_EXCEPT	2C
	PATCH_EXCEPT	34
	PATCH_EXCEPT	38
	PATCH_EXCEPT	3C


	PATCH_EXCEPT	60	; spurious interrupt
	
	; install interrupt vectors in VBR AND in zero page
	; (some games tend to enable interrupts a bit early: Great Courts
	; and it works with JST & WHDLoad, but it shouldn't, well let's be nice with
	; badly-coded slaves, specially when I wrote them :))
	PATCH_INTVEC	64
	PATCH_INTVEC	68
	PATCH_INTVEC	6C
	PATCH_INTVEC	70
	PATCH_INTVEC	74
	PATCH_INTVEC	78
	PATCH_INTVEC	7C
.traps
	; ** traps

	PATCH_EXCEPT	80
	PATCH_EXCEPT	84
	PATCH_EXCEPT	88
	PATCH_EXCEPT	8C
	PATCH_EXCEPT	90
	PATCH_EXCEPT	94
	PATCH_EXCEPT	98
	PATCH_EXCEPT	9C
	PATCH_EXCEPT	A0
	PATCH_EXCEPT	A4	; the $A4 address, not the register!
	PATCH_EXCEPT	A8
	PATCH_EXCEPT	AC
	PATCH_EXCEPT	B0
	PATCH_EXCEPT	B4
	PATCH_EXCEPT	B8
	PATCH_EXCEPT	BC
.setvbr
	bsr	GetAttnFlags	; leave JSRGEN here
	BTST	#AFB_68010,D0
	beq.b	.exit		; no 68010: no VBR to zero

	move.l	A2,D0
	MC68010
	movec	D0,VBR
	MC68010
	SETVAR_L	D0,resload_vbr
.exit
	rts
	
init_kickstart:
	GETVAR_L	kickstart_ptr,D0
	beq	.exit
	; there's a kickstart loaded in system memory
	; we have to copy it at the end of the chip memory (start of expmem) alongside with RTB table
	move.l	D0,A0
	GETVAR_L	maxchip,A1
	GETVAR_L	kick_and_rtb_size,D0

	bsr	CopyMem
		
	SETVAR_L	A1,kickstart_ptr	; now kickstart ptr is at start of expmem
	GETVAR_L	kicksize,D3
	
	; reloc kickstart
	GETVAR_L	kickstart_ptr,D4	; reloc base
	move.l	D4,A2		; kick current address	
	move.l	D4,A3
	add.l	D3,A3		; reloc table
	addq.l	#4,A3		; skip CRC long
	sub.l	#$F80000,D4	; original ROM start
	sub.l	D3,D4		; D4: offset to add
.relocloop:
	moveq.l	#0,D0
	move.b	(A3)+,D0
	bne.b	.reloc1byte
	move.b	(A3)+,D0
	bne.b	.reloc2bytes
	move.b	(A3)+,D0
	bne.b	.reloc3bytes

	move.b	(A3)+,D0
	bne.b	.reloc1byte
	bra.b	.reloc1_end			; 4 zeros: out

.reloc3bytes
.reloc2bytes
	lsl	#8,D0
	move.b	(A3)+,D0	
.reloc1byte
	; add D0 to kick pointer and patch
	add.l	D0,A2
	add.l	D4,(A2)

	bra.b	.relocloop
.reloc1_end:
	add.l	#4,A3	; skip $FFFFFFFF
	; now BCPL, just longword relocs (much simpler)
	sub.l	#$20000,D4	; kludge for 256K rom
	asr.l	#2,D4
	add.l	#$8000,D4	; kludge (I'm tired of trying to get the proper values)
	GETVAR_L	kickstart_ptr,A2	; reloc base
.relocbcpl
	move.l	(A3)+,D0
	beq.b	.reloc2_end
	; add D0 to kick pointer and patch
	add.l	D4,(A2,D0.L)
	bra.b	.relocbcpl
.reloc2_end
.exit
	rts

	
whd_bootstrap:
	SET_VAR_CONTEXT
	; turn off akiko intena (cd data loading)
;;	and.l	#$e1ffffff,AKIKO_INTENA	; clear bits 25-28
		
	; init a temporary stack just to initialize kickstart
	; (we transfer kickstart to maxchip which may hold the stack! boom!!)
	; (and we cannot set stack to maxchip either because it could point to somewhere
	; in kickstart dest since it's not allocated)
	
	lea	cdio_stack(pc),A7

	;; detect what is connected joypad or joystick, so 2-button joysticks work
	;; (else pressing 2nd button presses all the buttons)
	bsr	_detect_controller_types
	
	bsr	init_kickstart

	GETVAR_L	maxchip,A6
	move.l	A6,A7
	sub.l	#$400,A6	; stack size
	sub.l	#12,A7
	move.l	A6,USP
	
	TSTVAR_B	use_rn_loader
	bne.b	.rn
	
	bsr	flush_caches
	
	pea	PG_GetFileSize(pc)
	pea	PG_ReadFile(pc)
	TSTVAR_L	filecache_flag
	bne.b	.fc
	pea	PG_ReadFilePart(pc)
	bra.b	.fcdone
.fc
	pea	PG_ReadFilePartWithCache(pc)
.fcdone
	pea	PG_InitDrive(pc)
	pea	PG_SetCurrentDir(pc)
	pea	PG_ResetCurrentDir(pc)
	bra.b	.cont
.rn
	pea	RN_GetFileSize(pc)
	pea	RN_ReadFile(pc)
	pea	RN_ReadFilePart(pc)
	pea	RN_InitDrive(pc)
	pea	RN_SetCurrentDir(pc)
	pea	RN_ResetCurrentDir(pc)
	
.cont
	SETVAR_L	(a7)+,reset_current_dir
	SETVAR_L	(a7)+,set_current_dir
	SETVAR_L	(a7)+,init_drive
	SETVAR_L	(a7)+,read_file_part
	SETVAR_L	(a7)+,read_file
	SETVAR_L	(a7)+,get_file_size

	GETVAR_L	whd_slave_reloc_start,A1

	; we're going to clear the memory
	; reloc_start is supposed to be very high in memory
	; the problem with AGA games is that maxchip is $200000 so we don't want to trash
	; resload data!!
	
	GETVAR_L	maxchip,A2
	lea	reloc_start(pc),A3		; bottom of relocated stuff (slave+stack+resload)
	cmp.l	A2,A3
	bcc.b	.ok		; maxchip is below reloc: go!!
	; maxchip above resload: limit to below resload or it will crash!!
	move.l	A3,A2
.ok
	move.l	A2,A7		; install stack in maxchip
	
	move.l	#$CCCCCCCC,d1
	move.w	ws_Flags(A1),D0
	btst	#WHDLB_ClearMem,D0
	beq.b	.noclr
	moveq.l	#0,d1
	; clear from 8 to reloc_start
.noclr
	lea	$8.W,A0
.zapchip
	move.l	D1,(A0)+
	cmp.l	A2,A0
	bcs	.zapchip
	
	move.l	#$F0000001,4.W
	clr.l	0.W
	bsr	RelocateVBR
	
	; disable all Akiko CD interrupts: already done in "main.asm"
	;;bsr	stop_akiko_activity

	; we used to init drive here, but now we do it at first CD/HD access unless force option is set
	TSTVAR_L	delay_cdinit_flag
	bne.b	.delayedcdinit
	bsr	force_cdio
.delayedcdinit

	GETVAR_L	whd_slave_reloc_start,A1
	
	GETVAR_L	extsize,D2	; expmem size
	beq.b	.skipexp
	GETVAR_L	kicksize,D3	; don't clear kickstart
	sub.l	D3,D2	; extsize-kicksize
	beq.b	.skipexp	; expmem only used for kickstart: zap nothing
	GETVAR_L	maxchip,A0
	add.l	D3,A0	; expmem+kicksize
	add.l	A0,D2	; expmem+kicksize+extsize-kicksize (kick end)
.zapext
	move.l	D1,(A0)+
	cmp.l	D2,A0
	bcs	.zapext
.skipexp

	moveq.l	#0,D0
	move.w	ws_GameLoader(A1),D0
	add.l	D0,A1			; loader entry address


	; Here we return to the user loader
	; start WHDLoad slave
	TSTVAR_L	d_flag
	beq	.go
	move.l	debugger_nmi(pc),d0
	beq.b	.nohrt
	move.l	A1,A5	; slave start
	bsr		prepare_debugger_call
	bra.b	.go
.nohrt:
	; "D" for winuae/built in hrtmon: cannot call the debugger, but wait with lmb blitz
	blitz
.go
	lea	fake_resload(pc),A0			; fake WHD library MUST be in A0
	TSTVAR_L	cd_slave_reloc_start
	beq.b	.no_hooks
	GETVAR_L	cd_slave_reloc_start,a2
	; now install the CD calls & resload, and resolve hook entries
	move.l	a0,($C,A2)	; resload, no hooks
	pea	cdaudio_play_track(pc)
	move.l	(a7)+,($10,A2)
	pea	cdaudio_stop(pc)
	move.l	(a7)+,($14,A2)
	pea	cdaudio_status(pc)
	move.l	(a7)+,($18,A2)
	pea	cdaudio_replay_track(pc)
	move.l	(a7)+,($1C,A2)
	pea	cdaudio_status(pc)
	move.l	(a7)+,($20,A2)	; status but reserved
	lea	($C,A2),A3			; base
	
	move.w	#$18,D1		; $24-$C: init offset
	moveq.l	#0,d0
	
	move.w	(A3,D1.W),D0	; init offset
	beq.b	.no_init_hook
	move.l	A2,A5
	add.l	d0,A5
	movem.l	D0/A0-A4,-(A7)
	jsr	(a5)		; call init
	movem.l	(A7)+,D0/A0-A4
.no_init_hook
	addq.w	#2,D1	; decrunch
	LEAVAR	Decrunch_hook_address,A5
.hookloop
	move.w	(A3,D1.W),D0
	beq.b	.no_xxx_hook
	move.l	A2,A6
	add.l	d0,A6		; address
	move.l	a6,(a5)	; install hook jump
.no_xxx_hook
	addq.l	#4,A5
	addq.l	#2,d1
	cmp.w	#$2A,d1		; offset after the last whd hook
	bne.b	.hookloop
	
	lea	resload_hook(pc),A0			; fake WHD library MUST be in A0
.no_hooks
	; zap the rest of registers. Only A0 is valid when entering slave

	pea	(A1)
	move.l	#$D0D0D0D0,D0
	move.l	#$D1D1D1D1,D1
	move.l	#$D2D2D2D2,D2
	move.l	#$D3D3D3D3,D3
	move.l	#$D4D4D4D4,D4
	move.l	#$D5D5D5D5,D5
	move.l	#$D6D6D6D6,D6
	move.l	#$D7D7D7D7,D7
	move.l	#$A1A1A1A1,A1
	move.l	#$A2A2A2A2,A2
	move.l	#$A3A3A3A3,A3
	move.l	#$A4A4A4A4,A4
	move.l	#$A5A5A5A5,A5
	move.l	#$A6A6A6A6,A6
	nop
	nop
	;;bra	cd_audio_test_custom
	rts
	nop
	nop
	
cd_audio_test_custom:
	move.w	#$8028,$DFF09A	; enable VBL+int2(+int3)
	moveq.l	#2,D0
	moveq.l	#0,d1
	bsr	cdaudio_play_track
.lp
	btst	#6,$bfe001
	beq.b	.click
	move.l	#$200,D0
	bsr	BeamDelay
	
	bsr	cdaudio_replay_track

	bra.b	.lp
.click
	bsr	cdaudio_stop
	rts

cd_audio_test_custom_novbl:
	move.w	#$8008,$DFF09A	; enable VBL+int2
	moveq.l	#2,D0
	bsr	cdaudio_play_track
.lp
	btst	#6,$bfe001
	beq.b	.click
	move.l	#$200,D0
	bsr	BeamDelay

	bsr	cdaudio_status
	cmp.l	#1,d0
	bne.b	.lp
	
	moveq.l	#2,d0
	bsr	cdaudio_play_track

	bra.b	.lp
.click
	bsr	cdaudio_stop
	rts


	include	"cd32pio.s"
	
IGNORE_VECTOR:MACRO
	STORE_REGS	A0

	;SET_VAR_CONTEXT
	;SETVAR_W	#$\1,last_interrupt

	LEA	handle_\1(PC),A0
	CMP.L	$\1.W,A0		; installed directly in page 0
	RESTORE_REGS	A0
	BEQ.S	.IGNORE
	
	MOVE.L	$\1.W,-(A7)
	RTS
.IGNORE
	ENDM

; Disk interrupt (level1)

handle_64:
	IGNORE_VECTOR	64
	move.w	#0007,intreq+$DFF000
	rte

; Keyboard and other shit

handle_68:
	
	STORE_REGS	D0/A4
	SET_VAR_CONTEXT
	TSTVAR_B	realcd32_flag
	beq.b	.skipakiko
	move.l	AKIKO_INTENA,d0
	and.l	AKIKO_INTREQ,d0
	beq	.skipakiko

	; bits 29 and 30 mean: CD audio interrupt
	btst	#29,d0
	bne.b	.audio
	btst	#30,d0
	bne.b	.audio
	; this was useful before
	; but now that stops AKIKO from interrupting us
	; and we can't hear cd playing
	; turn it off except if CD audio interrupt, don't turn it off
	; for audio operation

	; avoid game from hanging by constant interrupt
	; by clearing AKIKO_INTENA if Akiko interrupt arrives
	; if CD audio is not playing
	; (level 2 interrupts are disabled when CD data load is active)
	; should not happen
	; but it COULD happen, because VBL constantly re-enabling interrupt level 2
	; for instance in Chaos Engine 2 AGA before I fixed the slave
	
	TSTVAR_B	cdio_in_progress
	beq.b	.nocdread
	TSTVAR_L	mask_int_2_flag
	bne.b	.mask_int_2
	; fatal error, display error & suggest workaround
	bra.b	.spurious_interrupt_error
.nocdread
	move.w	#0,AKIKO_INTENA

	bra.b	.sktst	; and skip (could try skipakiko)
.audio
	; avoid game from hanging by clearing AKIKO_INTENA if Akiko interrupt arrives
	; here we have to process cd play interrupt when it occurs
	bsr	cd_level2_interrupt
	
	GETVAR_W	whdflags,D0	
	btst	#WHDLB_NoKbd,D0
	bne.b	.sktst			; don't try to read keyboard from here
	TST.B	$BFED01	; do this or the keyboard takes over	
.sktst
	RESTORE_REGS	D0/A4
	; and just acknowledge interrupt (do not forward it to the game it could crash)
	move.w	#0008,intreq+$DFF000
	rte
; special exit: DON'T clear intreq, just remove int2 from intena again
; when exiting, intreq is still set, but interrupt isn't going to occur again
; and hopefully CD loading code will be happy
.mask_int_2
	move.w	#0008,intena+$DFF000
	RESTORE_REGS	D0/A4
	RTE
	
.skipakiko

	move.b	$bfec01,d0
	ror.b	#1,d0
	not.b	d0
	CMPVAR_B	quitkey,d0
	bne.b	.noquit
	pea	TDREASON_OK
	bra	WHD_Abort
.noquit
	STORE_REGS	D0
	GETVAR_W	whdflags,D0	
	btst	#WHDLB_NoKbd,D0
	bne.b	.nokback			; don't try to read keyboard from here
	BSET	#$06,$BFEE01
	MOVEQ	#3,D0
	bsr	BeamDelay
	BCLR	#$06,$BFEE01
.nokback
	RESTORE_REGS	D0

	CMPVAR_B	freeze_key,d0
	bne.b	.nodebugger
	move.l	debugger_nmi(pc),d0
	beq.b	.nodebugger
	STORE_REGS	A5
	move.l	14(A7),A5	; the PC the interrupt arrived (stackdependent)
	bsr		prepare_debugger_call
	RESTORE_REGS	A5

.nodebugger
	RESTORE_REGS	D0/A4

	IGNORE_VECTOR	68
	; if reaches there, means that no kb int has been installed

.skipint
	move.w	#0008,intreq+$DFF000	; acknowledge interrupt
	rte
.spurious_interrupt_error
	pea	$0.W
	pea	.abort_msg(pc)
	bra	SHOW_DEBUGSCREEN_2
.abort_msg:
	dc.b	"INT2 while loading. Try CDFREEZE or MASKINT2",0
	even
	
; VBlank vector

; read the joypad here and inject keyboard instead
; > d0.l = port number (0,1)
;
; < d0.l = state bits set as follows
;        JPB_JOY_R	= $00
;        JPB_JOY_L 	= $01
;        JPB_JOY_D	= $02
;        JPB_JOY_U	= $03
;        JPB_BTN_PLAY	= $11
;        JPB_BTN_REVERSE	= $12
;        JPB_BTN_FORWARD	= $13
;        JPB_BTN_GRN	= $14
;        JPB_BTN_YEL	= $15
;        JPB_BTN_RED	= $16
;        JPB_BTN_BLU	= $17
; < d1.l = raw joy[01]dat value read from input port

HANDLE_BUTTON:MACRO
	GETVAR_B	joy\3_\2_keycode,D2
	beq.b	.no\2\3twice
	
	btst	#JPB_BTN_\1,d0
	beq.b	.no\2\3
	btst	#JPB_BTN_\1,d3
	bne.b	.no\2\3twice
	; press
	bset	#JPB_BTN_\1,d3
	move.b		#\3,D0
	bra	.send
.no\2\3
	btst	#JPB_BTN_\1,d3
;	beq.b	.no\2\3twice
	; released
	beq.b	.no\2\3twice		; 0: not set
	bset	#7,d2
	bclr	#JPB_BTN_\1,d3
	move.b		#\3,D0
	bra	.send
.no\2\3twice
	ENDM
	
HANDLE_FWDBWD:MACRO
	GETVAR_B	joy\1_fwdbwd_keycode,D2
	beq			.endfwdbwd\1
	
	TSTVAR_B	joy\1_fwdbwd_active
	bne			.fwdbwdactive\1
	
	BTST		#JPB_BTN_REVERSE,D0
	beq			.endfwdbwd\1
	BTST		#JPB_BTN_FORWARD,D0
	beq			.endfwdbwd\1
	
	SETVAR_B	#1, joy\1_fwdbwd_active
	move.b		#\1,D0	; joystick id 0 or 1
	bra			.send
	
.fwdbwdactive\1
	
	BTST		#JPB_BTN_REVERSE,D0
	bne			.endfwdbwd\1
	BTST		#JPB_BTN_FORWARD,D0
	bne			.endfwdbwd\1
	
	SETVAR_B	#0, joy\1_fwdbwd_active
	bset		#7,D2	; key released
	move.b		#\1,D0	; joystick id 0 or 1
	bra			.send
	
.endfwdbwd\1
	ENDM

	; we're going to save the 6 next bytes and insert a JSR breakpoint: call EnterDebugger from there

prepare_debugger_call:
	STORE_REGS	A2
	LEAVAR	saved_instructions,A2
	move.l	(A5),(A2)
	move.w	(4,A5),(4,A2)
	pea	EnterDebuggerRestore(pc)
	move.w	#$4EB9,(A5)+
	move.l	(A7)+,(A5)
	bsr	flush_caches	; on return from interrupt, the game code itself will call EnterDebugger
	RESTORE_REGS	A2
	rts
	
handle_6C:
	STORE_REGS	D0-D3/A4-A5
	SET_VAR_CONTEXT
	move.l	debugger_nmi(pc),d0
	beq.b	.nodebugger
	move.b	$bfec01,d0
	not.b	d0
	ror.b	#1,d0
	CMPVAR_B	freeze_key,d0
	bne.b	.nodebugger
	TSTVAR_L	debug_flag
	beq.b	.nocolor
	move.w	#$D2D,$DFF180
.nocolor
	move.l	26(A7),A5	; the PC the interrupt arrived (stackdependent)
	bsr		prepare_debugger_call
.nodebugger
	
	TSTVAR_L	timeout_value
	beq.b	.notimeout
	GETVAR_L	counter_value,D0
	addq.l	#1,d0
	SETVAR_L	d0,counter_value
	CMPVAR_L	timeout_value,d0
	; timeout: reset
	beq	_reset
.notimeout
	IFEQ	1
	TSTVAR_W	cd_track_loop
	beq.b	.no_need_to_play
	bsr	cdaudio_replay_track
.no_need_to_play
	ENDC
	
	GETVAR_L	joypad_flag,D1
	beq	.out

	btst	#0,D1
	beq		.joy1
	moveq.l	#0,D0
	bsr	_read_joystick
	GETVAR_L	previous_joy0_state,D3
;	SETVAR_L	D0,previous_joy0_state
	move.b		#0,D1	
	bsr vm	
	bsr	vk
	TSTVAR_B	vk_wason
	bne			.out	
	
	HANDLE_BUTTON	RED,red,0
	HANDLE_BUTTON	PLAY,play,0
	HANDLE_BUTTON	BLU,blue,0
	HANDLE_BUTTON	YEL,yellow,0
	HANDLE_BUTTON	GRN,green,0
	HANDLE_BUTTON	RIGHT,right,0
	HANDLE_BUTTON	LEFT,left,0
	HANDLE_BUTTON	UP,up,0
	HANDLE_BUTTON	DOWN,down,0
	
	HANDLE_FWDBWD	0
	
	HANDLE_BUTTON	REVERSE,bwd,0
	HANDLE_BUTTON	FORWARD,fwd,0

.joy1
	GETVAR_L	joypad_flag,D1
	btst	#1,D1
	beq		.out

	moveq.l	#1,D0
	bsr	_read_joystick
	move.l	d0,d1
	and.l	#ALL_FRONT_BUTTONS_MASK,d1
	cmp.l	#ALL_FRONT_BUTTONS_MASK,d1
	beq	_reset


	GETVAR_L	previous_joy1_state,D3
;	SETVAR_L	D0,previous_joy1_state
	move.b		#1,D1
	bsr vm
	bsr	vk
	TSTVAR_B	vk_wason
	bne			.out
	
	HANDLE_BUTTON	RED,red,1
	HANDLE_BUTTON	PLAY,play,1
	HANDLE_BUTTON	BLU,blue,1
	HANDLE_BUTTON	YEL,yellow,1
	HANDLE_BUTTON	GRN,green,1
	
	HANDLE_BUTTON	RIGHT,right,1
	HANDLE_BUTTON	LEFT,left,1
	HANDLE_BUTTON	UP,up,1
	HANDLE_BUTTON	DOWN,down,1	
	
	HANDLE_FWDBWD	1

	HANDLE_BUTTON	REVERSE,bwd,1
	HANDLE_BUTTON	FORWARD,fwd,1

	bra.b	.out
	
; < D0: 0 or 1 depending on joypad ID
; < D2: key code (with bit 8 set if key release)
.send

;Upon sending key event, update the joy previous state
	tst.b	D0
	bne.b	.updatejoy1state
	SETVAR_L	D3,previous_joy0_state
	bra .send2

.updatejoy1state
	SETVAR_L	D3,previous_joy1_state
	
.send2
	move.b	D2,D0
	bsr	send_key_event
.out
	TSTVAR_B	vbl_redirect
	bne.b	.call_original_interrupt
	RESTORE_REGS	D0-D3/A4-A5
	
	IGNORE_VECTOR	6C
	move.w	#$0070,intreq+$DFF000
	rte

.call_original_interrupt:
	lea	.vbli(pc),A5
	GETVAR_L	game_vbl_interrupt,(A5)
	RESTORE_REGS	D0-D3/A4-A5
	; call original VBL interrupt (guaranteed to be set else this routine wouldn't have been called)
	move.l	.vbli(pc),-(a7)
	rts
.vbli:
	dc.l	0
; Copper vector

handle_70:
	IGNORE_VECTOR	70
	move.w	#$0780,intreq+$DFF000
	rte

; Audio vector

handle_74:
	IGNORE_VECTOR	74
	move.w	#$1800,intreq+$DFF000
	rte

; CIA vector

handle_78:
	STORE_REGS	A4
	SET_VAR_CONTEXT_2
	TSTVAR_L	mask_int_6_flag
	RESTORE_REGS	A4
	; if INT6 is masked, don't forward it to the zero-page handler,
	; just ignore it (Cool Spot)
	bne.b	.maskit
	IGNORE_VECTOR	78
.maskit
	move.w	#$2000,intreq+$DFF000
	btst.b	#0,$BFDD00		; acknowledge CIA-B Timer A interrupt
	RTE

	; NMI
handle_7C:
	move.w	#$7FFF,intreq+$DFF000	; ???
	RTE

	; inserted a CNOP there to align on 4 bytes so it ensures that each offset is exactly 4
	; and no padding/no bra opt from w to b

	CNOP	0,4
fake_resload:

	DEF_WHDOFFSET	resload_Install		;(private)
	DEF_WHDOFFSET	resload_Abort
		; return to operating system
		; IN: (a7) = DEF_WHDOFFSET  success (one of TDREASON_xxx)
		;   (4,a7) = DEF_WHDOFFSET  primary error code
		;   (8,a7) = DEF_WHDOFFSET  secondary error code
		; OUT :	-
		; DANGER this routine must called via JMP ! (not JSR)
	DEF_WHDOFFSET	resload_LoadFile
		; load to BaseMem
		; IN :	a0 = CPTR   name of file
		;	a1 = APTR   address
		; OUT :	d0 = BOOL   success (size of file)
		;	d1 = DEF_WHDOFFSET  dos errcode (0 if all went ok)
	DEF_WHDOFFSET	resload_SaveFile
		; save from BaseMem
		; IN :	d0 = LONG   length to save
		;	a0 = CPTR   name of file
		;	a1 = APTR   address
		; OUT :	d0 = BOOL   success
		;	d1 = DEF_WHDOFFSET  dos errcode (0 if all went ok)
	DEF_WHDOFFSET	resload_SetCACR
		; sets the CACR (also ok with 68000's and from user-state)
		; IN :	d0 = DEF_WHDOFFSET  new cacr
		;	d1 = DEF_WHDOFFSET  mask (bits to change)
		; OUT :	d0 = DEF_WHDOFFSET  old cacr
	DEF_WHDOFFSET	resload_ListFiles
		; list files in dir to buffer
		; IN :	d0 = DEF_WHDOFFSET  buffer size (a1)
		;	a0 = CPTR   name of directory to scan (relative)
		;	a1 = APTR   buffer (MUST reside in Slave !!!)
		; OUT :	d0 = DEF_WHDOFFSET  amount of listed names
		;	d1 = DEF_WHDOFFSET  dos errcode (0 if all went ok)
	DEF_WHDOFFSET	resload_Decrunch
		; decrunch memory
		; IN :	a0 = APTR   source
		;	a1 = APTR   destination (can be equal to source)
		; OUT :	d0 = BOOL   success (size of file unpacked)
	DEF_WHDOFFSET	resload_LoadFileDecrunch
		; IN :	a0 = CPTR   name of file (anywhere)
		;	a1 = APTR   address (MUST inside BaseMem !!!)
		; OUT :	d0 = BOOL   success (size of file)
		;	d1 = DEF_WHDOFFSET  dos errcode (0 if all went ok)
	DEF_WHDOFFSET	resload_FlushCache
		; flush all caches
		; IN :	-
		; OUT :	-
	DEF_WHDOFFSET	resload_GetFileSize
		; IN :	a0 = CPTR   name of file
		; OUT :	d0 = LONG   size of file or 0 if doesn't exist (or empty)
	DEF_WHDOFFSET	resload_DiskLoad
		; IN :	d0 = DEF_WHDOFFSET  offset
		;	d1 = DEF_WHDOFFSET  size
		;	d2 = DEF_WHDOFFSET  disk number
		;	a0 = APTR   destination
		; OUT :	d0 = BOOL   success
		;	d1 = DEF_WHDOFFSET  dos errorcode (if failed)

******* the following functions require ws_Version >= 2

	DEF_WHDOFFSET	resload_DiskLoadDev
		; IN :	d0 = DEF_WHDOFFSET  offset
		;	d1 = DEF_WHDOFFSET  size
		;	a0 = APTR   destination
		;	a1 = STRUCT taglist
		; OUT :	d0 = BOOL   success
		;	d1 = DEF_WHDOFFSET  trackdisk errorcode (if failed)

******* the following functions require ws_Version >= 3

	DEF_WHDOFFSET	resload_CRC16
		; IN :	d0 = DEF_WHDOFFSET  length
		;	a0 = APTR   address
		; OUT :	d0 = UWORD  crc checksum

******* the following functions require ws_Version >= 5

	DEF_WHDOFFSET	resload_Control
		; IN :	a0 = STRUCT taglist
		; OUT :	d0 = BOOL   success
	DEF_WHDOFFSET	resload_SaveFileOffset
		; save from BaseMem
		; IN :	d0 = DEF_WHDOFFSET  length to save
		;	d1 = DEF_WHDOFFSET  offset
		;	a0 = CPTR   name of file
		;	a1 = APTR   address
		; OUT :	d0 = BOOL   success
		;	d1 = DEF_WHDOFFSET  dos errcode (if failed)

******* the following functions require ws_Version >= 6

	DEF_WHDOFFSET	resload_ProtectRead
		; IN :	d0 = DEF_WHDOFFSET  length
		;	a0 = CPTR   address
		; OUT :	-
	DEF_WHDOFFSET	resload_ProtectReadWrite
		; IN :	d0 = DEF_WHDOFFSET  length
		;	a0 = CPTR   address
		; OUT :	-
	DEF_WHDOFFSET	resload_ProtectWrite
		; IN :	d0 = DEF_WHDOFFSET  length
		;	a0 = CPTR   address
		; OUT :	-
	DEF_WHDOFFSET	resload_ProtectRemove
		; IN :	d0 = DEF_WHDOFFSET  length
		;	a0 = CPTR   address
		; OUT :	-
	DEF_WHDOFFSET	resload_LoadFileOffset
		; IN :	d0 = DEF_WHDOFFSET  offset
		;	d1 = DEF_WHDOFFSET  size
		;	a0 = CPTR   name of file
		;	a1 = APTR   destination
		; OUT :	d0 = BOOL   success
		;	d1 = DEF_WHDOFFSET  dos errorcode (if failed)

******* the following functions require ws_Version >= 8

	DEF_WHDOFFSET	resload_Relocate
		; IN :	a0 = APTR   address of executable (source/destination)
		;	a1 = STRUCT taglist
		; OUT :	d0 = DEF_WHDOFFSET  size of relocated executable
		; will *never* be emulated properly
	DEF_WHDOFFSET	resload_Delay
		; IN :	d0 = DEF_WHDOFFSET  time to wait in 1/10 seconds
		; OUT :	-
	DEF_WHDOFFSET	resload_DeleteFile
		; IN :	a0 = CPTR   name of file
		; OUT :	d0 = BOOL   success
		;	d1 = DEF_WHDOFFSET  dos errorcode (if failed)

;******* the following functions require ws_Version >= 10 (totally unsupported!)

	DEF_WHDOFFSET	resload_ProtectSMC
		; detect self modifying code
		; IN :	d0 = ULONG  length
		;	a0 = CPTR   address
		; OUT :	-
	DEF_WHDOFFSET	resload_SetCPU
		; control CPU setup
		; IN :	d0 = ULONG  properties
		;	d1 = ULONG  mask
		; OUT :	d0 = ULONG  old properties
	DEF_WHDOFFSET	resload_Patch
		; apply patchlist
		; IN :	a0 = APTR   patchlist
		;	a1 = APTR   destination address
		; OUT :	-
	DEF_WHDOFFSET	resload_LoadKick
		; load kickstart image
		; IN :	d0 = ULONG  length of image
		;	d1 = UWORD  crc16 of image
		;	a0 = CPTR   basename of image
		; OUT :	-
	DEF_WHDOFFSET	resload_Delta
		; apply wdelta
		; IN :	a0 = APTR   src data
		;	a1 = APTR   dest data
		;	a2 = APTR   wdelta data
		; OUT :	-
	DEF_WHDOFFSET	resload_GetFileSizeDec
		; get size of a packed file
		; IN :	a0 = CPTR   filename
		; OUT :	d0 = ULONG  size of file

	DEF_WHDOFFSET	resload_PatchSeg
	DEF_WHDOFFSET	resload_Examine
	DEF_WHDOFFSET	resload_ExNext
	DEF_WHDOFFSET	resload_GetCustom
	; v18
	DEF_WHDOFFSET	resload_VSNPrintF
		; format string like clib.vsnprintf/exec.RawDoFmt (84)
		; IN:	d0 = ULONG  length of buffer
		;	a0 = APTR   buffer to fill
		;	a1 = CPTR   format string
		;	a2 = APTR   argument array
		; OUT:	d0 = ULONG  length of created string with unlimited
		;		    buffer without final '\0'
		;	a0 = APTR   pointer to final '\0'

	DEF_WHDOFFSET	resload_Log
	
	CNOP	0,4
resload_hook:
	DEF_WHDOFFSET	resload_Install		;(private)
	DEF_WHDOFFSET	resload_Abort		;(no hook possible)
	DEF_WHDHOOK_OFFSET	resload_LoadFile
	DEF_WHDOFFSET	resload_SaveFile	;(not useful as dummy func)
	DEF_WHDOFFSET	resload_SetCACR		;(not hookable)
	DEF_WHDOFFSET	resload_ListFiles	;(not hookable)
	DEF_WHDHOOK_OFFSET	resload_Decrunch
	DEF_WHDHOOK_OFFSET	resload_LoadFileDecrunch
	DEF_WHDOFFSET	resload_FlushCache	;(not hookable)
	DEF_WHDOFFSET	resload_GetFileSize	;(not hookable)
	DEF_WHDHOOK_OFFSET	resload_DiskLoad
	DEF_WHDOFFSET	resload_DiskLoadDev
	DEF_WHDOFFSET	resload_CRC16
	DEF_WHDOFFSET	resload_Control
	DEF_WHDOFFSET	resload_SaveFileOffset
	DEF_WHDOFFSET	resload_ProtectRead
	DEF_WHDOFFSET	resload_ProtectReadWrite
	DEF_WHDOFFSET	resload_ProtectWrite
	DEF_WHDOFFSET	resload_ProtectRemove
	DEF_WHDHOOK_OFFSET	resload_LoadFileOffset
	DEF_WHDHOOK_OFFSET	resload_Relocate
	DEF_WHDOFFSET	resload_Delay
	DEF_WHDOFFSET	resload_DeleteFile
	DEF_WHDOFFSET	resload_ProtectSMC
	DEF_WHDOFFSET	resload_SetCPU
	DEF_WHDHOOK_OFFSET	resload_Patch
	DEF_WHDOFFSET	resload_LoadKick
	DEF_WHDOFFSET	resload_Delta
	DEF_WHDOFFSET	resload_GetFileSizeDec
	DEF_WHDHOOK_OFFSET	resload_PatchSeg
	DEF_WHDOFFSET	resload_Examine
	DEF_WHDOFFSET	resload_ExNext
	DEF_WHDOFFSET	resload_GetCustom
	DEF_WHDOFFSET	resload_VSNPrintF
	DEF_WHDOFFSET	resload_Log

jst_resload_Examine
	STORE_REGS	D2-A4
	; Examine can fail, we cannot know if it's a CD failure or a file not found
	; so we disable CD retries/fatal errors in those cases
	; which CAN be an issue with CD-audio releases & kickemu (having used CD-audio
	; tends to generate random read errors when CD-data routine takes over)
	SET_VAR_CONTEXT_2
	; init to trash
	move.l	a1,a2
	move.w	#fib_Reserved,D2
	lsr.w	#1,D2
	subq	#1,D2
.clr
	move.w	#$eeee,(a2)+
	dbf 	d2,.clr
	clr.l	(a1)		; zero key
	
	tst.b	(a0)
	bne		.norootdir
	bsr	.setdirparams
	lea	.rootname(pc),a2
	move.l	a2,d0
	lea	(fib_FileName,a1),a2
	move.l	a2,d1
	bsr	StrcpyAsm
	
	bra	.oknodk
.norootdir
	;;IFEQ	1
	; maybe a directory?
	; hack: to speed things up, system directories are okayed
	; C,L,S,DEVS,LIBS,FONTS are always scanned on startup, which means a lot of CD
	; useless accesses (either they exist or they don't and will be seen empty if the prog
	; tries to open an file in it, and ExNext is not implemented anyway!)

	; this series of string compare hacks are meant to be fast, not clean :)
	move.l	a0,a3	; dir/file name
	tst.b	(1,a3)
	bne.b	.no_1c_dir
	cmp.b	#'C',(a3)
	beq.b	.is_a_dir ; C dir: okay it
	cmp.b	#'L',(a3)
	beq.b	.is_a_dir ; L dir: okay it
	cmp.b	#'S',(a3)
	beq.b	.is_a_dir ; L dir: okay it
.no_1c_dir
	tst.b	(4,a3)
	bne.b	.no_4c_dir
	cmp.b	#'S',(3,a3)	; DEVS or LIBS?
	bne.b	.no_4c_dir
	
	cmp.b	#'D',(a3)
	bne.b	.no_devs_dir
	cmp.b	#'E',(1,a3)
	bne.b	.no_devs_dir
	cmp.b	#'V',(2,a3)
	beq.b	.is_a_dir ; DEVS dir: okay it
.no_devs_dir
	cmp.b	#'L',(a3)
	bne.b	.no_4c_dir
	cmp.b	#'I',(1,a3)
	bne.b	.no_4c_dir
	cmp.b	#'B',(2,a3)
	beq.b	.is_a_dir ; LIBS dir: okay it

.no_4c_dir
	cmp.b	#'F',(a3)+
	bne.b	.no_fonts_dir
	cmp.b	#'O',(a3)+
	bne.b	.no_fonts_dir
	cmp.b	#'N',(a3)+
	bne.b	.no_fonts_dir
	cmp.b	#'T',(a3)+
	bne.b	.no_fonts_dir
	cmp.b	#'S',(a3)+
	bne.b	.no_fonts_dir
	tst.b	(a3)+
	beq.b	.is_a_dir
.no_fonts_dir
	;;ENDC	
	SETVAR_B	#1,disable_file_dir_error
	; try to CD to it
	GETVAR_L	set_current_dir,A3
	jsr	(A3)
	CLRVAR_B	disable_file_dir_error
	
	move.w	d0,d2	; save return code
	; re-CD in the original directory / fix current dir (else, get filesize will fail)
	GETVAR_L	reset_current_dir,A3
	jsr	(A3)

	tst.w	d2		; CDLERR_DIRNOTFOUND
	bne.b	.notfound
.is_a_dir
	bsr.b	.setdirparams
	bra.b	.ok

.setdirparams:
	move.l 	#2,(fib_DirEntryType,A1)	; dir
	move.l 	#2,(fib_EntryType,A1)	; dir
	move.l	#$10,(fib_Protection,A1)		; ??? F=RWED
	moveq.l	#0,d1
	move.l	D1,(fib_Size,A1)
	move.l	D1,(fib_NumBlocks,A1)
	rts
	
.notfound
	
	; try to get file size
	GETVAR_L	get_file_size,A3
	jsr	(A3)
	tst.l	d0
	beq.b	.cannot_get_size	; or zero-len file (we'll check that later)

	
	move.l	D0,(fib_Size,A1)
	lsr.l	#8,D0
	lsr.l	#1,D0
	addq.l	#1,D0
	move.l	D0,(fib_NumBlocks,A1)
	move.l 	#-3,(fib_DirEntryType,A1)	; file
	move.l 	#-3,(fib_EntryType,A1)	; file
	move.l	#$F,(fib_Protection,A1)		; ??? F=RWED
	bra.b	.ok
.cannot_get_size:
	move.l	#DOSFALSE,d0
	move.l	#ERROR_OBJECT_NOT_FOUND,d1
	bra.b	.out
.ok
	; compute a diskkey: not needed kickfs uses it to store filename
	
	;move.l	a0,d0
	;bsr	StrlenAsm
	;bsr	CRC16
	;move.l	d0,(fib_DiskKey,a1)
	
	; copy basename
	move.l	a0,d1
	lea		(fib_FileName,a1),a2
	move.l	a2,d2
	
; < D1: file/dir name
; < D2 (modified): basename of D1
	bsr	Basename
.oknodk
	move.l	#$3670,(fib_DateStamp,A1)
	move.l	#$0256,(fib_DateStamp+4,A1)
	move.l	#$0280,(fib_DateStamp+8,A1)
	clr.b	(fib_Comment,A1)	
	move.l	#DOSTRUE,d0	; DOSTRUE
	moveq.l	#0,d1
.out
	CLRVAR_B	disable_file_dir_error
	RESTORE_REGS	D2-A4
	RTS
.rootname
		dc.b	"WHDLoad",0
		even
		
jst_resload_Delta
	RUNTIME_ERROR_ROUTINE	WHD_Delta,"Delta"

jst_resload_ExNext
	RUNTIME_ERROR_ROUTINE	WHD_ExNext,"ExNext"
jst_resload_VSNPrintF
	RUNTIME_ERROR_ROUTINE	WHD_VSNPrintF,"VSNPrintF"
jst_resload_Log
	RUNTIME_ERROR_ROUTINE	WHD_Log,"Log"
jst_resload_LoadKick
	RUNTIME_ERROR_ROUTINE	WHD_LoadKick,"LoadKick"

jst_resload_ProtectRead:
jst_resload_ProtectReadWrite:
jst_resload_ProtectWrite:
jst_resload_ProtectRemove:
	RUNTIME_ERROR_ROUTINE	WHD_Protect,"Protect"
jst_resload_Install:
	RUNTIME_ERROR_ROUTINE	WHD_Install,"WHDLoad install called!"
jst_resload_Abort:
	bra	WHD_Abort
	
jst_resload_GetFileSizeDec
	STORE_REGS	D1-D3/A1/A3/A4
	; read the start of the file in the buffer

	; cannot load files in resload zone (there are checks in CD32Load - crazy memory copy)
	SET_VAR_CONTEXT_2

	CLRVAR_L	last_io_error
	GETVAR_L	get_file_size,A3
	jsr	(A3)
	move.l	D0,D3	; save size in case file isn't packed
	beq	.out	; empty file: out
	cmp.l	#12,d0
	bcs		.out	; not possible for a packed file: don't waste our time

	lea	$100.W,A1
	move.l	(A1),-(A7)
	move.l	4(A1),-(A7)
	moveq.l	#0,D2
	moveq.l	#8,D1

	GETVAR_L	read_file_part,A3
	JSR	(A3)
	tst.l	D0
	beq.b	.ok
	SETVAR_L	#ERROR_OBJECT_NOT_FOUND,last_io_error	; set any error code: file is not found
	; allows to distinguish between file not found and file not crunched / with size 0
	moveq.l	#0,d0
	bra.b	.exit
.ok
	move.l	(A1)+,d0
	cmp.l	#"IMP!",d0
	beq.b	.read
	cmp.l	#"TPWM",d0
	beq.b	.read
	cmp.l	#"ATN!",d0
	beq.b	.read
	move.b	#'C',d0
	cmp.l	#"RNCC",d0
	beq.b	.read
	; unpacked size passed
	move.l	d3,d0
	bra.b	.exit
.read	
	move.l	(A1)+,d0
.exit
	move.l	(A7)+,$104.W
	move.l	(A7)+,$100.W
.out
	RESTORE_REGS	D1-D3/A1/A3/A4
	tst.l	d0		; some slaves test the CCR flags without performing a TST.L !!
	rts

jst_resload_GetCustom:
	STORE_REGS	D1/A1/A4
	move.l	A0,D1
	SET_VAR_CONTEXT_2
	LEAVAR	custom_str,A1
	move.l	A1,D0
	bsr	StrcpyAsm
	move.l	A1,D0
	moveq.l	#-1,d0	; let's say it always succeeds :)
	RESTORE_REGS	D1/A1/A4
	rts

		; load kickstart image
		; IN :	d0 = ULONG  length of image
		;	d1 = UWORD  crc16 of image
		;	a0 = CPTR   basename of image
		; OUT :	-

END_WHD_CALL:MACRO
	STORE_REGS	A4
	SET_VAR_CONTEXT
	CLRVAR_B	in_resload
	RESTORE_REGS	A4
	ENDM
	
LOG_WHD_CALL:MACRO
	STORE_REGS	D0/D1/A0/A2/A4
	SET_VAR_CONTEXT
	LEAVAR	last_whd_parameters,A2
	movem.l	D0/D1/D2/A0/A1,(a2)
	LEAVAR last_whd_function_called,A0
	move.l	A0,D1
	lea	.lfc(pc),a0
	move.l	A0,D0
	bsr	StrcpyAsm
	bra.b	.end
.lfc:
	dc.b	\1,0
	even
.end
	st.b	D0
	SETVAR_B	D0,in_resload
	RESTORE_REGS	D0/D1/A0/A2/A4
	ENDM

;length,errorcode = resload_LoadFile(name, address)
; D0      D1                         A0      A1
;ULONG    ULONG                      CPTR    APTR

jst_resload_LoadFile:
	;LOG_WHD_CALL	"LoadFile"
	STORE_REGS	A3/A4
	moveq.l	#-1,D1
	moveq.l	#0,D0
	SET_VAR_CONTEXT_2
	GETVAR_L	read_file,A3
	jsr	(A3)
	exg	D0,D1	; swap D0 and D1 registers
	tst.l	D1	; D1=0: okay
	bne.b	.error

	; no error, size in D0, 0 in D1
.out
	;END_WHD_CALL
	RESTORE_REGS	A3/A4
	; I thought that whdload set zero flag but that's not
	; guaranteed... it seems to be the opposite now...
	tst.l	D1
	rts
.error
	moveq.l	#0,D0	; size=0
	moveq.l	#-1,D1	; error
	bra.b	.out


jst_resload_SaveFile:
	;LOG_WHD_CALL	"SaveFile"
	;END_WHD_CALL
	moveq.l	#0,D0	; error
	rts

jst_resload_SetCACR:
;	LOG_WHD_CALL	"SetCACR"
	bsr	flush_caches
;	END_WHD_CALL
	rts
jst_resload_ListFiles:
;	LOG_WHD_CALL	"ListFiles"
;	END_WHD_CALL
	rts

jst_resload_Decrunch:
	;;LOG_WHD_CALL	"Decrunch"
	STORE_REGS	D6
	moveq.l	#0,D6
	
	bsr	RNCLength
	tst.l	D0
	bmi.b	.nornc		; not a RNC file

	move.l	D0,D6		; decrunched length

	bsr	RNCDecrunch
	bra.b	.exit
.nornc
	bsr	ATNLength
	tst.l	D0
	bmi.b	.noatn		; not a RNC file

	move.l	D0,D6		; decrunched length

	bsr	ATNDecrunch	; ATN! and IMP! files
	tst.l	D0
	bmi.b	.noatn		; not a RNC file

	bra.b	.exit
.noatn
	; last chance: try TPWM decrunch
	cmp.b	#'T',(A0)
	bne.b	.notpwm
	cmp.b	#'P',1(A0)
	bne.b	.notpwm
	cmp.b	#'W',2(A0)
	bne.b	.notpwm
	cmp.b	#'M',3(A0)
	bne.b	.notpwm

	bsr	TPWMDecrunch
	
	moveq.l	#0,D6		; len not supported
	bra.b	.exit
.notpwm
	cmp.b	#'C',(A0)
	bne.b	.nocrunchmania
	cmp.b	#'r',(A0)
	bne.b	.nocrunchmania

	pea	$0.W
	pea	.abort_msg(pc)
	bra	SHOW_DEBUGSCREEN_2
.abort_msg:
	dc.b	"Decrunch: Crunchmania unsupported",0
	even
.nocrunchmania:
	moveq.l	#0,D0		; not crunched: returns 0
.exit
	move.l	D6,D0		; decrunched length
	RESTORE_REGS	D6
	bsr	flush_caches
	; trash A0 & A1 on exit like WHDLoad
	move.l	#$A0A0A0A0,A0
	move.l	#$A1A1A1A1,A0
;;	END_WHD_CALL
	rts

jst_resload_LoadFileDecrunch:
	bsr	jst_resload_LoadFile
	;LOG_WHD_CALL	"LoadFileDecrunch"
	tst.l	D1
	bne.b	.exit	; error
	STORE_REGS	D2-A6

	move.l	D0,D6

	move.l	A1,A0
	bsr	jst_resload_Decrunch

	tst.l	D0
	bne.b	.waspacked

	move.l	D6,D0	; file was not packed: restore real length
.waspacked
	RESTORE_REGS	D2-A6
	moveq.l	#0,D1	; no error, anyway
.exit
	;END_WHD_CALL
	tst.l	D1
	rts

jst_resload_FlushCache:
	;LOG_WHD_CALL	"FlushCache"
	bsr	flush_caches
	;END_WHD_CALL
	rts

jst_resload_GetFileSize:
	;LOG_WHD_CALL	"GetFileSize"
	STORE_REGS	A1-A4
	SET_VAR_CONTEXT_2
	
	tst.b	(a0)
	beq.b	.noname

	GETVAR_L	get_file_size,A3
	jsr	(A3)
	; here we have to make a difference between a 0-file size
	; and a non-existent file
	tst.l	d0
	
	RESTORE_REGS	A1-A4
	;END_WHD_CALL
	tst.l	d0		; some slaves test the CCR flags without performing a TST.L !!
	rts
.noname:
	RUNTIME_ERROR_ROUTINE	EmptyFileName,"Empty file name passed"

; < A0: filename
PG_GetFileSize:
	STORE_REGS	D2/A1
	MOVEQ	#CD_GETFILEINFO,D0
	sub.l	A1,A1
	; that can fail because file doesn't exist
	SETVAR_B	#1,disable_file_dir_error
	bsr	prepare_cdio_buffer
	bsr	psygore_cdio
	bsr	restore_game_memory
	CLRVAR_B	disable_file_dir_error
	tst.w	D0
	beq.b	.ok
	; failed to get size, set io error to distinguish between
	; 0 size and file not found
	SETVAR_L	#ERROR_OBJECT_NOT_FOUND,last_io_error
	moveq.l	#0,D0
	beq.b	.exit
.ok
	move.l	D2,D0	; filesize in D0, block in D1
.exit
	RESTORE_REGS	D2/A1
	RTS
	
RN_GetFileSize:
	STORE_REGS	D1/A1
	; parameters match closely the CD interface
	MOVEQ	#3,D0			; get size
	SETVAR_B	#1,disable_file_dir_error
	bsr	prepare_cdio_buffer
	GETVAR_L	cdio_buffer,A2
	bsr	robnorthen_cdio
	CLRVAR_B	disable_file_dir_error
	bsr	restore_game_memory
	tst.l	d0
	beq.b	.sizeok
	; failed to get size, set io error to distinguish between
	; 0 size and file not found
	SETVAR_L	#ERROR_OBJECT_NOT_FOUND,last_io_error
	moveq.l	#0,D0
	beq.b	.exit
.sizeok
	move.l	D1,D0	; else return filesize from D1 in D0
.exit
	RESTORE_REGS	D1/A1
	rts
	
; < A0: buffer
; < D0: offset
; < D1: length
; < D2: unit

jst_resload_DiskLoad:
;	LOG_WHD_CALL	"DiskLoad"
	STORE_REGS	D2-D3
	move.l	D2,D3
	subq.l	#1,D3	; for JST disks starts from 0
	move.l	D0,D2	; offset in bytes
	move.l	D3,D0	; disk unit from 0
			; D1 ok same thing
	
	
	bsr	ReadDiskPart

	RESTORE_REGS	D2-D3
	tst.l	D0
	bmi.b	.disk_error

	bsr	flush_caches		; as WHDLoad flushes the caches, we do the same
	moveq.l	#0,D1	; errcode: 0 : OK
	moveq.l	#-1,D0	; returns TRUE
.out
;	END_WHD_CALL

	tst.l	d0
	rts

.disk_error:
	moveq.l	#0,D0
	moveq.l	#1,D1
	bra.b	.out

jst_resload_DiskLoadDev:
	RUNTIME_ERROR_ROUTINE	WHD_DiskLoadDev,"DiskLoadDev"

jst_resload_CRC16:
;	LOG_WHD_CALL	"CRC16"
	bsr	CRC16
;	END_WHD_CALL
	rts
	
jst_resload_Control:
	;LOG_WHD_CALL	"Control"
	STORE_REGS	A0/A1/A4
	SET_VAR_CONTEXT_2

.loop
	move.l	(A0)+,D0
	beq	.exit
	cmp.l	#WHDLTAG_ATTNFLAGS_GET,D0
	bne.b	.sk1
	bsr	GetAttnFlags
	bra	.storetag
.sk1
	cmp.l	#WHDLTAG_MONITOR_GET,D0
	bne.b	.sk2

	move.l	#PAL_MONITOR_ID,D0
	TSTVAR_L	ntsc_flag
	beq	.storetag
	move.l	#NTSC_MONITOR_ID,D0
	bra	.storetag

.sk2
	cmp.l	#WHDLTAG_BUTTONWAIT_GET,D0
	bne.b	.sk3
	moveq.l	#0,D0
	TSTVAR_L	buttonwait_flag
	beq	.storetag
	moveq.l	#-1,D0
	bra	.storetag

.sk3
	cmp.l	#WHDLTAG_Private3,D0	; registered, I guess?
	bne.b	.sk4
	moveq.l	#1,D0			; yes, always,
	bra	.storetag


.sk4:
	cmp.l	#WHDLTAG_CBAF_SET,D0	; access fault hook
	bne.b	.sk5
	move.l	(A0)+,D0		; gets function address

;	STORE_REGS	A0
;	move.l	D0,A0
;	JSRGEN	SetBusErrorVector
;	RESTORE_REGS	A0
	bra	.loop


.sk5:

	cmp.l	#WHDLTAG_KEYTRANS_GET,D0
	bne.b	.sk6
	; raw/ascii table

	LEAVAR	raw_ascii_table,A1
	move.l	A1,D0
	bra	.storetag
.sk6
	cmp.l	#WHDLTAG_CBSWITCH_SET,D0
	bne.b	.sk7
	move.l	(A0)+,D0		; gets function address
;	STORE_REGS	A0
;	move.l	D0,A0
;	JSRGEN	SetAfterSwitchFunction
;	RESTORE_REGS	A0
	bra	.loop
	
	; after switch to game callback: there IS no OS switch in CD32Load

.sk7
	cmp.l	#WHDLTAG_CUSTOM1_GET,D0
	bne.b	.sk8

	GETVAR_L	custom1_flag,D0
	bra.b	.storetag
.sk8
	cmp.l	#WHDLTAG_CUSTOM2_GET,D0
	bne.b	.sk9

	GETVAR_L	custom2_flag,D0
	bra.b	.storetag
.sk9
	cmp.l	#WHDLTAG_CUSTOM3_GET,D0
	bne.b	.sk10

	GETVAR_L	custom3_flag,D0
	bra.b	.storetag
.sk10
	cmp.l	#WHDLTAG_CUSTOM4_GET,D0
	bne.b	.sk11

	GETVAR_L	custom4_flag,D0
	bra.b	.storetag
.sk11
	cmp.l	#WHDLTAG_CUSTOM5_GET,D0
	bne.b	.sk12

	GETVAR_L	custom5_flag,D0
	bra.b	.storetag
.sk12
	cmp.l	#WHDLTAG_VERSION_GET,D0	;get WHDLoad major version number
	bne.b	.sk13
	move.l	#18,D0		; highest possible
	bra.b	.storetag
.sk13
	cmp.l	#WHDLTAG_REVISION_GET,D0	;get WHDLoad major version number
	bne.b	.sk14
	moveq.l	#3,D0		; highest possible
	bra	.storetag
.storetag:
	move.l	D0,(A0)+
	bra	.loop
.skiptag:
	addq.l	#4,A0
	bra	.loop

.sk14
	cmp.l	#WHDLTAG_BUILD_GET,D0	;get WHDLoad major version number
	bne.b	.sk15
	move.l	#156,D0		; random
	bra.b	.storetag
.sk15
	cmp.l	#WHDLTAG_ECLOCKFREQ_GET,D0
	bne.b	.sk16
	GETVAR_L	eclock_freq,D0
	bra.b	.storetag
.sk16
	cmp.l	#WHDLTAG_CHIPREVBITS_GET,D0
	bne.b	.sk17
	moveq.l	#0,d0
	GETVAR_B	system_chiprev_bits,D0	; so also knows about ECS/HD configs, not only CD32
	bra.b	.storetag
.sk17
	cmp.l	#WHDLTAG_IOERR_GET,D0
	bne.b	.sk18
	GETVAR_L	last_io_error,D0
	bra.b	.storetag
.sk18
	cmp.l	#WHDLTAG_TIME_GET,D0
	bne.b	.sk19
	lea	current_time(pc),A1
	; fill with fixed but acceptable values
    move.l	#365*38,whdlt_days(A1)	;days since 1978-01-01
	move.l	#500,whdlt_mins(A1)	;minutes since last day
	move.l	#500,whdlt_ticks(A1)	;1/50 seconds since last minute
	move.b	#16,whdlt_year(A1)
	move.b	#1,whdlt_month(A1)
	move.b	#1,whdlt_day(A1)
	move.b	#12,whdlt_hour(A1)
	move.b	#0,whdlt_min(A1)
	move.b	#0,whdlt_sec(A1)
	move.l	A1,D0
	bra	.storetag
.sk19
	cmp.l	#WHDLTAG_LANG_GET,D0
	bne.b	.sk20
	moveq.l	#0,D0	; english?
	bra	.storetag
.sk20
	cmp.l	#WHDLTAG_BPLCON0_GET,D0
	bne	.sk21
	moveq.l	#0,D0
	GETVAR_W	system_bplcon0,D0
	bra	.storetag
.sk21
	cmp.l	#WHDLTAG_DBGADR_SET,D0
	beq	.skiptag		; ignore
	cmp.l	#WHDLTAG_DBGSEG_SET,D0
	beq	.skiptag		; ignore
	; unsupported tag
	lea	.tag(pc),a1
	bsr	HexToString
	pea	$0.W
	pea	.abort_msg(pc)
	bra	SHOW_DEBUGSCREEN_2
.abort_msg:
	dc.b	"Unknown control tag "
.tag:
	blk.b	10,0

.exit
	RESTORE_REGS	A0/A1/A4
	;END_WHD_CALL
	moveq.l	#0,D0		; success!
	rts

current_time:
	blk.b	whdlt_SIZEOF,0

_reset

; reset the machine when quitting
	lea 2.W,A0
	RESET
	jmp (a0)
	
WHD_Abort:
	
	RESTORE_REGS	D0
	cmp.l	#TDREASON_OK,D0
	bne.b	.err
	SET_VAR_CONTEXT_2
	TSTVAR_L	timeout_value
	beq.b	_reset
	; in timeout mode, this is considered as an error
	pea	0.W
	pea	.abort_normal_msg(pc)
	bra	SHOW_DEBUGSCREEN_2
.abort_normal_msg:
	dc.b	"Abort with reason OK",0
	even

.err
	RESTORE_REGS	A0		; secondary
	RESTORE_REGS	D1		; third

	STORE_REGS	D0-D2/A0-A2
	lea	.whd_code(pc),a1
	bsr	HexToString
	add.l	d0,d0
	lea	code_to_str_table(pc),a2
	moveq.l	#0,d1
	move.w	(a2,d0.l),d1
	add.l	d1,a2
	move.l	a2,d0
	lea	(9,a1),a1
	move.b	#' ',(a1)+
	move.l	a1,d1
	bsr	StrcpyAsm
	
	RESTORE_REGS	D0-D2/A0-A2
.show
	pea	$0
	pea	.abort_msg(pc)
	bra	SHOW_DEBUGSCREEN_2
.abort_msg:
	dc.b	"WHD_Abort code "
.whd_code:
	blk.b	40,0
	even

code_to_str_table:
	dc.w	0
	dc.w	.dosread-code_to_str_table
	dc.w	.doswrite-code_to_str_table
	dc.w	0,0
	dc.w	.debug-code_to_str_table
	dc.w	.doslist-code_to_str_table
	dc.w	.diskload-code_to_str_table
	dc.w	.diskloaddev-code_to_str_table
	dc.w	.wrongver-code_to_str_table
	dc.w	.osemufail-code_to_str_table

.dosread:
	dc.b	"dosread",0
.doswrite:
	dc.b	"doswrite",0
.debug:
	dc.b	"debug",0
.doslist:
	dc.b	"doslist",0
.diskload:
	dc.b	"diskload",0
.diskloaddev:
	dc.b	"diskloaddev",0
.wrongver:
	dc.b	"wrong/unsupported version",0
.osemufail:
	dc.b	"OSEmu failure",0
	even


unsupported_patch_instruction:
	blitz
	nop
	nop
	nop
	; A2=patchlist start
	; A0=current patchlist ptr
	and.l	#$FFFF,D0
	lea	.whd_code(pc),a1
	bsr	HexToString
	pea	$0
	pea	.whd_abort_msg(pc)
	bra	SHOW_DEBUGSCREEN_2
.whd_abort_msg:
	dc.b	"Unsupported patch instruction "
.whd_code:
	blk.b	10,0
	
	; IN :	d0 = DEF_WHDOFFSET  length to save
	;	d1 = DEF_WHDOFFSET  offset
	;	a0 = CPTR   name of file
	;	a1 = APTR   address
	; OUT :	d0 = BOOL   success
	;	d1 = DEF_WHDOFFSET  dos errcode (if failed)

jst_resload_SaveFileOffset:
	;LOG_WHD_CALL	"SaveFileOffset"
	moveq.l	#0,D0		; not OK
	rts
;.ok
;	moveq.l	#-1,D0		; TRUE
;	rts
	


;;    success,error = resload_LoadFileOffset(size, offset, name, address)
;;          D0     D1                             D0     D1     A0      A1
;;        BOOL   ULONG                          ULONG  ULONG  CPTR    APTR

jst_resload_LoadFileOffset:
	;LOG_WHD_CALL	"LoadFileOffset"
	movem.l	D2/A3/A4,-(A7)
	move.l	D1,D2	; offset
	move.l	D0,D1	; length

	SET_VAR_CONTEXT_2
	GETVAR_L	read_file_part,A3
	jsr	(A3)
	movem.l	(A7)+,D2/A3/A4
	move.l	D0,D1		; "errorcode"
	beq.b	.ok

	;END_WHD_CALL
	moveq.l	#0,D0		; not OK
	rts
.ok
	;END_WHD_CALL
	moveq.l	#-1,D0		; TRUE
	rts

******* the following functions require ws_Version >= 8

jst_resload_Relocate:
	;LOG_WHD_CALL	"Relocate"
	bsr	RelocateExecutable
	;END_WHD_CALL
	rts

jst_resload_Delay:
	;LOG_WHD_CALL	"Delay"
	STORE_REGS
	SET_VAR_CONTEXT_2
	move.l	#16000,D0	; PAL mode
	TSTVAR_L	ntsc_flag
	beq.b	.pal
	move.l	#19200,D0	; PAL mode
.pal
	bsr	BeamDelay
	subq.l	#1,D1
	beq.b	.exit
	btst	#6,$BFE001
	beq.b	.exit
	btst	#7,$BFE001
	bne.b	.pal
.exit
	RESTORE_REGS
	;END_WHD_CALL
	RTS

; < A0: filename to delete
; > D0: success/error
; > D1: error code from IoErr()

jst_resload_DeleteFile:
	;LOG_WHD_CALL	"DeleteFile"
	;END_WHD_CALL
	moveq.l	#0,D0
	moveq.l	#1,D1	; ???
	rts


	
;******* the following functions require ws_Version >= 10 (totally unsupported!)

jst_resload_ProtectSMC:
		; detect self modifying code
		; IN :	d0 = ULONG  length
		;	a0 = CPTR   address
		; OUT :	-
	RUNTIME_ERROR_ROUTINE	WHD_ProtectSMC,"ProtectSMC"
jst_resload_SetCPU:
	;LOG_WHD_CALL	"SetCPU"
		; control CPU setup
		; IN :	d0 = ULONG  properties
		;	d1 = ULONG  mask
		; OUT :	d0 = ULONG  old properties
		btst	#WCPUB_IC,D0
		bne.b	.sk			; bit set: don't disable cache
	; only disable cache supported
	STORE_REGS	D0/A4/A5
	SET_VAR_CONTEXT_2
	bsr	GetAttnFlags	; leave JSRGEN here
	BTST	#AFB_68020,D0
	beq.b	.exit		; no 68020: no cache flush
	lea	discache_supcode(pc),A5
	bsr	supervisor

.exit
	RESTORE_REGS	D0/A4/A5
.sk
		bsr	flush_caches
	;END_WHD_CALL
		rts

	
jst_resload_PatchSeg
	;LOG_WHD_CALL	"PatchSeg"
	STORE_REGS
	move.l	A0,A2		; store patchlist
	move.l	A1,A6		; store seglist
	add.l	A6,A6
	add.l	A6,A6	; CPTR
	lea	patch_jumptable(pc),A5
	moveq.l	#0,D5		; condition mask: all bits must be at 0 or patch won't apply
	moveq.l	#0,D6		; nest counter

.loop:
	move.l	A6,A1	; reset segment pointers
	
	move.w	(a0)+,D0	; command
	cmp.w	#PLCMD_END,D0
	beq.w	.exit

	
	bclr	#14,D0
	bne.b	.noaddr		; command: no address argument
	bclr	#15,D0
	beq.b	.bit32
	moveq.l	#0,D1
	move.w	(a0)+,D1	; D1.W: offset
	bra.b	.bit16
.bit32
	move.l	(a0)+,D1	; D1.L: address
	; compute the correct A1 (not fixed like in resload_Patch)
	; depending on D1
.bit16
	moveq.l	#0,D3	; segment absolute offset
	
.find_a1:
	move.l	(A1)+,D2
	add.l	D2,D2
	add.l	D2,D2	; D2=next segment address
	move.l	d3,D7	; save previous accumulated segment size
	add.l	-8(a1),D3	; accumulate segment size
	subq.l	#8,d3	; minus size+next segment info
	cmp.l	D3,D1
	bcs.b	.a1_found
	; D1 is above D3: look in next segment

	tst.l	d2
	beq.b	.notfound	; end of seglist found, and offset still too high

	move.l	D2,A1
	bra.b	.find_a1
.a1_found
	sub.l	D7,D1	; make D1 offset relative to current segment
.noaddr:
	cmp.w	#45,D0
	bcc		unsupported_patch_instruction
	add.w	D0,D0
	move.w	(A5,D0.W),D0
	jsr	(A5,D0.W)
	bra.b	.loop
.notfound
	move.l	d1,d0
	lea	.whd_code(pc),a1
	bsr	HexToString
	pea	$0
	pea	.whd_abort_msg(pc)
	bra	SHOW_DEBUGSCREEN_2
.whd_abort_msg:
	dc.b	"PatchSeg: offset not found: "
.whd_code:
	blk.b	10,0

.exit
	bsr	flush_caches
	RESTORE_REGS
	;END_WHD_CALL

	RTS
	
SKIPIFFALSE	MACRO
		tst.l	d5
		beq.b	.cont\@
		rts
.cont\@
	ENDM


	
jst_resload_Patch:
	;LOG_WHD_CALL	"Patch"
		; apply patchlist
		; IN :	a0 = APTR   patchlist
		;	a1 = APTR   destination address
		; OUT :	-
	STORE_REGS
	move.l	A0,A2		; store patchlist
	lea	patch_jumptable(pc),A5
	moveq.l	#0,D5		; condition mask: all bits must be at 0 or patch won't apply
	moveq.l	#0,D6		; nest counter
	SET_VAR_CONTEXT_2
.loop:
	move.w	(a0)+,D0	; command
	cmp.w	#PLCMD_END,D0
	bne.w	.cont

	; exit
	bsr	flush_caches
	RESTORE_REGS
	;END_WHD_CALL
	RTS
.cont
	
	bclr	#14,D0
	bne.b	.noaddr		; command: no address argument
	bclr	#15,D0
	beq.b	.bit32
	moveq.l	#0,D1
	move.w	(a0)+,D1	; D1.W: offset
	bra.b	.noaddr
.bit32
	move.l	(a0)+,D1	; D1.L: address
.noaddr:
	cmp.w	#46,D0
	bcs.b	.instok
	bra	unsupported_patch_instruction
.instok
	add.w	D0,D0
	move.w	(A5,D0.W),D2
	jsr	(A5,D2.W)
	bra	.loop
	
patch_jumptable:
	dc.w	.exit-patch_jumptable	; not reached??	0
	dc.w	.R-patch_jumptable		; 1
	dc.w	.P-patch_jumptable			; 2 set JMP
	dc.w	.PS-patch_jumptable		; 3 set JSR
	dc.w	.S-patch_jumptable			; 4 set BRA (skip)
	dc.w	.I-patch_jumptable			; 5 set ILLEGAL
	dc.w	.B-patch_jumptable			; 6 write byte to specified address
	dc.w	.W-patch_jumptable			; 7 write word to specified address
	dc.w	.L-patch_jumptable			; 8 write long to specified address
; version 11
	dc.w	.UNSUP-patch_jumptable			; 9 (A) write address which is calculated as
					;base + arg to specified address
; version 14
	dc.w	.PA-patch_jumptable		; $A write address given by argument to
					;specified address
	dc.w	.NOP-patch_jumptable		; $B fill given area with NOP instructions
; version 15
	dc.w	.CZ-patch_jumptable			; $C (C) clear n bytes
	dc.w	.CB-patch_jumptable		; $D clear one byte
	dc.w	.CW-patch_jumptable		; $E clear one word
	dc.w	.CL-patch_jumptable		; $F clear one long
; version 16
	dc.w	.PSS-patch_jumptable		; $11 set JSR + NOP..
	dc.w	.NEXT-patch_jumptable		;continue with another patch list
	dc.w	.AB-patch_jumptable		;add byte to specified address
	dc.w	.AW-patch_jumptable		;add word to specified address
	dc.w	.AL-patch_jumptable		;add long to specified address
	dc.w	.DATA-patch_jumptable		;write n data bytes to specified address
; version 16.5
	dc.w	.ORB-patch_jumptable		;or byte to specified address
	dc.w	.ORW-patch_jumptable		;or word to specified address
	dc.w	.ORL-patch_jumptable		;or long to specified address
; version 16.6
	dc.w	.GA-patch_jumptable		; (GA) get specified address and store it in the slave
; version 16.9
	dc.w	.UNSUP-patch_jumptable		;call freezer
	dc.w	.UNSUP-patch_jumptable		;show visual bell
; version 17.2
	dc.w	.IFBW-patch_jumptable		;condition if ButtonWait/S
	dc.w	.IFC1-patch_jumptable		;condition if Custom1/N
	dc.w	.IFC2-patch_jumptable		;condition if Custom2/N
	dc.w	.IFC3-patch_jumptable		;condition if Custom3/N
	dc.w	.IFC4-patch_jumptable		;condition if Custom4/N
	dc.w	.IFC5-patch_jumptable		;condition if Custom5/N
	dc.w	.IFC1X-patch_jumptable		;condition if bit of Custom1/N
	dc.w	.IFC2X-patch_jumptable		;condition if bit of Custom2/N
	dc.w	.IFC3X-patch_jumptable		;condition if bit of Custom3/N
	dc.w	.IFC4X-patch_jumptable		;condition if bit of Custom4/N
	dc.w	.IFC5X-patch_jumptable		;condition if bit of Custom5/N
	dc.w	.ELSE-patch_jumptable		;condition alternative
	dc.w	.ENDIF-patch_jumptable		;end of condition block


.IFBW:
	GETVAR_L	buttonwait_flag,D0
	bra	.IFXXX
.IFC1:
	GETVAR_L	custom1_flag,D0
	bra	.IFXXX
.IFC2:
	GETVAR_L	custom2_flag,D0
	bra	.IFXXX
.IFC3:
	GETVAR_L	custom3_flag,D0
	bra	.IFXXX
.IFC4:
	GETVAR_L	custom4_flag,D0
	bra	.IFXXX
.IFC5:
	GETVAR_L	custom5_flag,D0
	bra	.IFXXX
.ELSE:
		bchg	D6,D5	; invert condition
		rts
		
.ENDIF:
		bclr	D6,D5
		subq.l	#1,D6
		rts	
.IFC1X:
	GETVAR_L	custom1_flag,D0
	bra	.IFBITXXX
.IFC2X:
	GETVAR_L	custom2_flag,D0
	bra	.IFBITXXX
.IFC3X:
	GETVAR_L	custom3_flag,D0
	bra	.IFBITXXX
.IFC4X:
	GETVAR_L	custom4_flag,D0
	bra	.IFBITXXX
.IFC5X:
	GETVAR_L	custom5_flag,D0


.IFBITXXX
	move.w	(a0)+,d2	; get argument: bit number
	; must be between 0 and 31
	btst	d2,d0
	sne	d0
	ext.w	d0
	ext.l	d0
.IFXXX
	addq.w	#1,d6	; increase nest
	tst.l	d0
	bne	.skif
	bset	d6,d5	; failed condition: set D5 so nothing is patched anymore until ELSE/ENDIF
.skif
	rts
	
.R
	SKIPIFFALSE
	move.w	#$4E75,(A1,D1.L)
	rts
.P
	bsr	.get_slave_address
	SKIPIFFALSE
	move.w	#$4EF9,(A1,D1.L)
	move.l	A3,2(A1,D1.L)
	rts
.PA
	bsr	.get_slave_address
	SKIPIFFALSE
	move.l	A3,(A1,D1.L)
	rts
.PS
	bsr	.get_slave_address
	SKIPIFFALSE
	move.w	#$4EB9,(A1,D1.L)
	move.l	A3,2(A1,D1.L)
	rts
.GA

	bsr	.get_slave_address
	SKIPIFFALSE
	; copy program address (A1+D1) into location
	move.l	A1,(A3)
	add.l	D1,(A3)
	rts
	
.PSS
	bsr	.get_slave_address
	move.w	(a0)+,d2
	SKIPIFFALSE
	move.w	#$4EB9,(A1,D1.L)
	move.l	A3,2(A1,D1.L)
	addq.l	#6,D1
	bra	.NOP_from_PSS
.ORB
	clr.w	d0
	move.w	(A0)+,D0
	SKIPIFFALSE
	or.b	D0,(A1,D1.L)
	rts
.ORW
	move.w	(A0)+,D0
	SKIPIFFALSE
	or.w	D0,(A1,D1.L)
	rts
.ORL
	move.l	(A0)+,D0
	SKIPIFFALSE
	or.l	D0,(A1,D1.L)
	rts
.AB
	clr.w	d0
	move.w	(A0)+,D0
	SKIPIFFALSE
	add.b	D0,(A1,D1.L)
	rts
.AW
	move.w	(A0)+,D0
	SKIPIFFALSE
	add.w	D0,(A1,D1.L)
	rts
.AL
	move.l	(A0)+,D0
	SKIPIFFALSE
	add.l	D0,(A1,D1.L)
	rts
.CZ
	move.w	(A0)+,D2
	SKIPIFFALSE
	subq.l	#1,D2
.czl
	clr.b	(A1,D1.L)
	addq.l	#1,D1
	dbf	D2,.czl
	rts
.CL
	SKIPIFFALSE
	clr.l	(A1,D1.L)
	rts
.CW
	SKIPIFFALSE
	clr.w	(A1,D1.L)
	rts
.CB
	SKIPIFFALSE
	clr.b	(A1,D1.L)
	rts
.S
	move.w	(A0)+,D2
	SKIPIFFALSE
	move.w	#$6000,(A1,D1.L)
	move.w	D2,2(A1,D1.L)
	rts
.NOP
	move.w	(A0)+,D2
	SKIPIFFALSE
.NOP_from_PSS
	lsr.w	#1,d2
	bne	.ncont
	rts	; safety
.ncont
	subq.w	#1,d2
.noploop
	move.w	#$4E71,(A1,D1.L)
	addq.l	#2,d1
	dbf		d2,.noploop
	rts
.I
	SKIPIFFALSE
	move.w	#$4AFC,(A1,D1.L)
	rts
.B
	move.w	(A0)+,D2
	SKIPIFFALSE
	move.b	D2,(A1,D1.L)
	rts

.W
	move.w	(A0)+,D2
	SKIPIFFALSE
	move.w	D2,(A1,D1.L)
	rts
.L
	move.l	(A0)+,D2
	SKIPIFFALSE
	move.l	D2,(A1,D1.L)
	rts
.DATA
	move.w	(A0)+,D0	; size
	beq.b	.exit
	move.w	d0,d2	
	subq.l	#1,D0
.dataloop
	tst.l	d5		; cannot use SKIPIFFALSE here
	beq.b	.writedata
	addq.l	#1,A0		; don't write, just zap
	bra.b	.contdata
.writedata
	move.b	(A0)+,(A1,D1.L)
	addq.l	#1,D1
.contdata
	dbf		D0,.dataloop
	btst	#0,d2	; odd?
	beq.b	.exit
	addq.l	#1,a0
	rts
.NEXT	; V16 patchlist support
	bsr	.get_slave_address
	move.l	a3,a0		; next patchlist
	move.l	a3,a2		; store patchlist start
	rts
.UNSUP
	lsr.w	#1,D0
	bra	unsupported_patch_instruction
.exit
	rts

; <> A0: patch buffer (+=2 on exit)
; < A2: patch start
; > A3: real address of the routine in the slave
; D2 trashed

.get_slave_address:
	move.w	(A0)+,D2
	lea	(A2,D2.W),A3
	rts



	
	RUNTIME_ERROR_ROUTINE	UnknownExit,"WHDLoad abort (unknown reason)"

	RUNTIME_ERROR_ROUTINE	ExitDebug,"WHDLoad abort (debug)"

	RUNTIME_ERROR_ROUTINE	WrongCRC,"Unsupported game version"

	RUNTIME_ERROR_ROUTINE	PalRequired,"Needs PAL video mode"
	

WHDMessUnsupported:
	dc.b	10,"Run-Time Error: Unsupported WHDLoad call: "
WHDMessUnsupported_Arg:
	blk.b	30,0
	even
	
