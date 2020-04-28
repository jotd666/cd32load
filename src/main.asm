	include	"macros.i"
	include	"whdload.i"
	include	"whdmacros.i"

	include	"exec/types.i"
	include	"exec/memory.i"
	include	"exec/libraries.i"
	include	"exec/execbase.i"

	include "dos/dos.i"
	include "dos/var.i"
	include "dos/dostags.i"
	include "dos/dosextens.i"
	include "intuition/intuition.i"
	include	"hardware/cia.i"
	include	"hardware/custom.i"
	include	"hardware/intbits.i"
	include	"graphics/gfxbase.i"
	include	"graphics/videocontrol.i"
	include	"graphics/view.i"
	include	"devices/console.i"
	include	"devices/conunit.i"
	include	"libraries/lowlevel.i"
	INCLUDE	"workbench/workbench.i"
	INCLUDE	"workbench/startup.i"
	
	include "lvo/exec.i"
	include "lvo/dos.i"
	include "lvo/lowlevel.i"
	include "lvo/graphics.i"

	include	"struct.i"

	XDEF	EntryPoint

	XREF	reloc_start
	XREF	reloc_end
	XREF	rnloader
	XREF	rnloader_end
	XREF	pgloader
	XREF	pgloader_end
	
	XREF	whd_bootstrap
	XREF	debugger_nmi
	XREF	stop_akiko_activity
	
MIN_CDBUFFER_ADDRESS = $10000
	
; keymap.library
_LVOSetKeyMapDefault   equ     -30     ; Functions in V36 or higher (2.0)
_LVOAskKeyMapDefault   equ     -36
_LVOMapRawKey          equ     -42
_LVOMapANSI            equ     -48


MAJOR_VERSION = 0
MINOR_VERSION = 4
SUBMINOR_VERSION = 9

SET_VAR_CONTEXT:MACRO
	lea	reloc_start,A4
	ENDM
	
PARSEHEXARG:MACRO
	move.l	(A0)+,D0
	beq.b	.sk\@
	move.l	D0,A1
	bsr	HexStringToNum
	;tst.b	D0
	;beq.b	.sk\@
	SETVAR_B	D0,\1_keycode
.sk\@
	ENDM
	
EntryPoint:
	move.l	A7,OriginalStack
	move.l	A0,TaskArgsPtr
	move.l	D0,TaskArgsLength
	move.l	$4.w,_SysBase		;store execbase in fastmem
	move.l	_SysBase,a6		;exec base
	JSRLIB	Forbid
	sub.l	A1,A1
	JSRLIB	FindTask		;find ourselves
	move.l	D0,TaskPointer
	move.l	D0,A0
	move.l	(TC_SPLOWER,A0),D0
	add.l	#$100,D0	; 256 bytes for safety
	move.l	D0,TaskLower	; for task check
	move.l	#TaskName,LN_NAME(a0)	; sets task name
	move.l	#-1,pr_WindowPtr(A0)	; no more system requesters (insert volume...)
	JSRLIB	Permit

	lea	dosname(pc),a1
	moveq.l	#0,d0
	JSRLIB	OpenLibrary
	move.l	d0,_DosBase

	move.l	TaskPointer(pc),A4
	tst.l	pr_CLI(A4)
	bne.b	.fromcli

	; gets wb message

	lea	pr_MsgPort(A4),A0
	JSRLIB	WaitPort
	lea	pr_MsgPort(A4),A0
	JSRLIB	GetMsg
	move.l	D0,RtnMess
	
	
.fromcli
	bsr	OpenOutput
	bsr	start
	
exit:
	SET_VAR_CONTEXT
	move.l	allocated_filecache(pc),d0
	beq.b	.nopreloadfree
	move.l	d0,a1
	move.l	allocated_filesize(pc),d0
	move.l	_SysBase,A6
	JSRLIB	FreeMem	
	clr.l	allocated_filecache
.nopreloadfree
	GETVAR_L	kick_and_rtb_size,d0
	beq.b	.nokickfree
	GETVAR_L	kickstart_ptr,A1
	move.l	_SysBase,A6
	JSRLIB	FreeMem
	SETVAR_L	#0,kick_and_rtb_size
.nokickfree
	move.l	slave_start(pc),d0
	beq.b	.nofree
	move.l	d0,a1
	GETVAR_L	slaves_size,d0
	move.l	_SysBase,A6
	JSRLIB	FreeMem
.nofree
	move.l	_DosBase(pc),D0
	beq.b	.skipcd
	move.l	rdargs_struct(pc),D1
	beq.b	.noargsfree		; already freed/not parsed
	move.l	D0,A6
	JSRLIB	FreeArgs
.noargsfree
	move.l	_SysBase,A6
	move.l	_DosBase(pc),D0
	beq.b	.skipcd
	move.l	d0,a1
	JSRLIB	CloseLibrary
.skipcd
	move.l	_SysBase,A6
	move.l	_LowlevelBase(pc),D0
	beq.b	.skipcl
	move.l	d0,a1
	JSRLIB	CloseLibrary
.skipcl

	; replies to workbench

	move.l	RtnMess(pc),d0
	tst.l	D0
	beq.b	.cliend

	JSRLIB	Forbid
	move.l	D0,A1
	JSRLIB	ReplyMsg
	; no permit here??
	JSRLIB	Permit
.cliend
	moveq.l	#0,D0
	rts

slave_alloc_error:
		SET_VAR_CONTEXT
		PRINT_MSG	error_prefix
		PRINT	"Cannot allocate "
		GETVAR_L	slaves_size,D0
		PRINTH	D0
		PRINTLN	" bytes for slave(s)"
		bra.b	CloseAll

ReadArgsErr:
		PRINT_ERROR_MSG	readargs_error
		PRINT_MSG	help
		bra.b	CloseAll
		
CloseAll:
	move.l	OriginalStack,A7
	bra	exit

LoadSlave:
	SET_VAR_CONTEXT
	; *** Open the file

	move.l	#slave_name,D1
	move.l	#MODE_OLDFILE,D2
	move.l	_DosBase,A6
	JSRLIB	Open
	move.l	D0,D6
	beq	.noslave	; very unlikely!

	; ** skip the file header
	move.l	D6,D1
	move.l	#OFFSET_BEGINNING,D3
	move.l	#$20,D2
	JSRLIB	Seek
	; ** Read the contents
	move.l	D6,D1
	move.l	whd_slave_size,D3
	move.l	slave_start(pc),D2
	JSRLIB	Read
	; ** Close the file
	move.l	D6,D1
	JSRLIB	Close
	
	; now same thing for CD slave if exists
    ; (and hasn't been disabled)
	tst.b	cd_slave_name
	beq	.out
	move.l	#cd_slave_name,D1
	move.l	#MODE_OLDFILE,D2
	move.l	_DosBase,A6
	JSRLIB	Open
	move.l	D0,D6
	beq	.nocdslave	; very unlikely!

	; ** skip the file header
	move.l	D6,D1
	move.l	#OFFSET_BEGINNING,D3
	move.l	#$20,D2
	JSRLIB	Seek
	; ** Read the contents
	move.l	D6,D1
	move.l	cd_slave_size(pc),D3
	move.l	slave_start(pc),D2
	add.l	cd_slave_offset(pc),D2
	JSRLIB	Read
	; ** Close the file
	move.l	D6,D1
	JSRLIB	Close
.out	
	rts
.noslave
	PRINT_MSG	error_prefix
	PRINT		"Cannot read "
	PRINT_MSG	slave_name
	PRINTLN	
	bra	CloseAll
.nocdslave
	PRINT_MSG	error_prefix
	PRINT		"Cannot read "
	PRINT_MSG	cd_slave_name
	PRINTLN	
	bra	CloseAll

; the aim here is to see if a joystick is connected in port 1 with JOYPAD=2
; in that case, button remapping won't work, and so won't joypad detection
; if JOYPAD=2 AND joystick is connected in port 2 AND joypad is connected in port 1,
; then set JOYPAD=1 and map joypad 2 controls to joypad 1
;
; of course this only works on real hardware. On winuae, joystick/joypad detection fails

VTRANS:MACRO
	GETVAR_B	joy1_\1_keycode,D0
	SETVAR_B	D0,joy0_\1_keycode
	ENDM
	
CheckJoypads:
	SET_VAR_CONTEXT
    
    
	lea	lowname(pc),a1
	moveq.l	#0,d0
	move.l	$4.W,A6
	JSRLIB	OpenLibrary
	move.l	D0,_LowlevelBase
	beq.b	.nolowl	; A1200/A600: maybe not present: who cares?
	move.l	D0,A6
    ; wait a while, first reads are unreliable (first detects a joystick even
    ; if joypad is connected, then detects joypad but no buttons...)
    ; I've seen a more delirious loop even in DeluxeGalaga code.
    ; I suppose the author went crazy and read the joypad 500 times!!
    ; better wait between the reads.
    move.l  #3,d2
.rloop
    move.l  #100,d0
    bsr BeamDelay
	moveq	#1,D0
	JSRLIB	ReadJoyPort
    dbf d2,.rloop
	move.l	d0,d1
    

	and.l	#JP_TYPE_MASK,D0
	cmp.l	#JP_TYPE_JOYSTK,D0
	bne.b	.exit		; no joystick in port 1: direct jump to button test
    
    ; now port 1 has a joystick. transfer control buttons to joypad 0 if
    ; joypad is connected in port 0
	moveq	#0,D0
	JSRLIB	ReadJoyPort
 
	moveq	#0,D0
	JSRLIB	ReadJoyPort
	move.l	d0,d1
	and.l	#JP_TYPE_MASK,D0
	cmp.l	#JP_TYPE_GAMECTLR,D0
	bne.b	.exit		; no joypad in port 0: forget it
	; 0: no joypad remapping
	; 1: joyport 0 remapping only
	; 2: joyport 1 remapping only (default)
	; 3: both joyports remapping

	GETVAR_L	joypad_flag,D0
	cmp.l	#2,D0		; port 1 and only port 1
	bne	.exit
	; we are in the target configuration, swap ports (doesn't seem to work)
	SETVAR_L	#1,joypad_flag		; port 1 remap only
	move.l	#1,swapjoy

	; set values for joypad 0 from values from joypad 1
	VTRANS	play
	VTRANS	red
	VTRANS	fwd
	VTRANS	bwd
	VTRANS	fwdbwd
	VTRANS	green
	VTRANS	blue
	VTRANS	yellow

.exit
 	; D1 has joypad state
	; if some button is pressed, enable CUSTOMx
	; don't consider RED button since it could be used to run the game on startup menus
;	btst	#JPB_BUTTON_RED,D1
;	beq.b	.nored	
;.nored
	btst	#JPB_BUTTON_BLUE,D1
	beq.b	.noblue
	SETVAR_L	#-1,custom1_flag
	move.w	#$00F,d0
	bsr	colordelay_button
.noblue
	btst	#JPB_BUTTON_YELLOW,D1
	beq.b	.noyellow
	SETVAR_L	#-1,custom2_flag
	move.w	#$FF0,d0
	bsr	colordelay_button
.noyellow
	btst	#JPB_BUTTON_FORWARD,D1
	beq.b	.noforward
	SETVAR_L	#-1,custom5_flag
	move.w	#$494,d0
	bsr	colordelay_button	
.noforward
	btst	#JPB_BUTTON_REVERSE,D1
	beq.b	.noreverse
	SETVAR_L	#-1,custom4_flag
	move.w	#$949,d0
	bsr	colordelay_button	
	
.noreverse
	btst	#JPB_BUTTON_GREEN,D1
	beq.b	.nogreen
	SETVAR_L	#-1,custom3_flag
	move.w	#$0F0,d0
	bsr	colordelay_button	
.nogreen
	btst	#JPB_BUTTON_PLAY,D1
	beq.b	.noplay
    ; as if cd slave hasn't been specified
	clr.b   cd_slave_name
    move.w  #$EEE,d0
	bsr	colordelay_button	

.noplay
.nolowl
	rts

; < D0: rgb
colordelay_button:
	movem.l	d1,-(a7)
	move.l	d0,d1
	move.l	#$1000,d0
	bsr	colordelay
	movem.l	(a7)+,d1
	rts
	
colordelay:
; < D0: numbers of vertical positions to wait
; < D1: color $0rgb
.bd_loop1
	move.w  d0,-(a7)
    move.b	$dff006,d0	; VPOS
.bd_loop2
	move.w	d1,$dff180
	cmp.b	$dff006,d0
	beq.s	.bd_loop2
	move.w	(a7)+,d0
	dbf	d0,.bd_loop1
	rts
	
LoadKick:
	STORE_REGS
	add.l	A1,D0
	move.l	#kickstart_suffix,D1
	bsr	StrcpyAsm		; compose full filename

	move.l	D1,D0
	bsr	StrlenAsm
	move.l	D1,A0
	add.l	D0,A0
	move.l	A0,rtb_suffix_ptr
	; add .RTB suffix
	move.b	#'.',(a0)+
	move.b	#'R',(a0)+
	move.b	#'T',(a0)+
	move.b	#'B',(a0)+
	move.l	#kickstart_filename,D0
	; get RTB size
	bsr	GetFileLength
	move.l	D0,D4
	bmi	.nortb
	
	move.l	ws_kicksize(A1),D1
	SETVAR_L	D1,kicksize
	move.w	ws_kickcrc(A1),D5

	
	add.l	D1,D0	; kick+RTB size
	SETVAR_L	D0,kick_and_rtb_size

	
	moveq.l	#0,D1
	move.l	_SysBase,A6
	JSRLIB	AllocMem
	SETVAR_L	D0,kickstart_ptr
	; now read the .RTB file
	move.l	#kickstart_filename,D1
	move.l	#MODE_OLDFILE,D2
	move.l	_DosBase,A6
	JSRLIB	Open
	move.l	D0,D6
	beq	.nortb	; very unlikely!

	; ** Read the file
	move.l	D6,D1
	move.l	D4,D3	; read all file
	GETVAR_L	kickstart_ptr,D2
	ADDVAR_L	kicksize,d2
	JSRLIB	Read
	; ** Close the .RTB file
	move.l	D6,D1
	JSRLIB	Close
		

	; now read kickstart file (remove .RTB suffix)
	move.l	rtb_suffix_ptr(pc),A0
	clr.b	(A0)
	move.l	#kickstart_filename,D1
	move.l	#MODE_OLDFILE,D2
	move.l	_DosBase,A6
	JSRLIB	Open
	move.l	D0,D6
	beq	.nortb
	; ** Read the file
	move.l	D6,D1
	GETVAR_L	kicksize,D3	; read all file
	GETVAR_L	kickstart_ptr,D2
	JSRLIB	Read
	; ** Close the kickstart file
	move.l	D6,D1
	JSRLIB	Close

	; perform CRC just in case

	GETVAR_L	kickstart_ptr,A0
	GETVAR_L	kicksize,d0
	bsr	CRC16
	cmp.w	D5,D0	; checks with provided CRC
	bne	.wrong_kick_crc

	RESTORE_REGS
	rts
	
.kickerr
	LEA	kickstart_filename(pc),A1
	bsr	Display
	PRINTLN
	bra	CloseAll
.nortb
	PRINT_MSG	error_prefix
	PRINTLN	"RTB file not found: "
	bra.b	.kickerr
.wrong_kick_crc:
	PRINT_MSG	error_prefix
	PRINTLN	"Wrong kickstart CRC for file "
	bra.b	.kickerr

rtb_suffix_ptr:
	dc.l	0
LinkSlaveInfo:
	SET_VAR_CONTEXT
	; first check CD slave if any
	tst.l	cd_slave_offset
	beq.b	.no_cd_slave
	move.l	slave_start,A1
	add.l	cd_slave_offset,A1
	move.l	$4(A1),D0
	cmp.l	#"CD32",D0
	beq.b	.cdslok
	PRINT_MSG	error_prefix
	PRINTLN	"CD Slave is illegal (no CD32LOAD prefix)"
	bra	CloseAll
.cdslok	
.no_cd_slave
	move.l	slave_start,A1
	move.l	$4(A1),D0
	cmp.l	#"WHDL",D0
	beq.b	.slok
	PRINT_MSG	error_prefix
	PRINTLN	"Slave is illegal (no WHDLOADS prefix)"
	bra	CloseAll
.slok
	move.l	force_chipmem,D0
	bne.b	.forcechip
	move.l	ws_BaseMemSize(A1),D0
.forcechip
	move.l	D0,ws_BaseMemSize(A1)
	SETVAR_L	D0,maxchip
	SETVAR_L	D0,top_game_mem

	SETVAR_W	ws_Flags(A1),whdflags
	move.w	ws_Version(A1),D2
	cmp.w	#16,D2
	bcs.b	.nokick				; not supported before version 16
	moveq.l	#0,D0
	move.w	ws_kickname(A1),D0
	beq.b	.nokick
	; ATM cannot loadkick with rn/idehd
	;tst.l	idehd_flag
	;bne	.kickrnerror
	;tst.l	rncd_flag
	;bne	.kickrnerror
	; cannot LoadKick if alternate CDBUFFER is set
	TSTVAR_L	cdio_buffer_2
	beq.b	.canloadkick
	PRINT_MSG	error_prefix
	PRINTLN	"Cannot execute KickEmu slaves with CDBUFFER2 set"
	bra	CloseAll	
.canloadkick
	bsr	LoadKick
	
.nokick
	move.w	ws_Version(A1),D2
	cmp.w	#8,D2
	bcs.b	.noext				; not supported before version 8!
	tst.l	ws_ExpMem(A1)
	beq.b	.noext				; no expansion memory required, no need to check force expmem
	bpl.b	.acceptexp
	; cannot afford optional memory unless forced
	move.l	ws_ExpMem(A1),D1
	not.l	D1		; optional extsize
	tst.l	force_optional_memory_flag
	bne.b	.acceptexp
	; cancel expansion memory
	clr.l	ws_ExpMem(a1)
	bra.b	.noext
.acceptexp
	move.l	force_expmem,D1
	bne.b	.forceexp
	move.l	ws_ExpMem(A1),D1
.forceexp
	SETVAR_L	D1,extsize
	ADDVAR_L	top_game_mem,D1
	SETVAR_L	D1,top_game_mem
	GETVAR_L	maxchip,D0

	move.l	D0,ws_ExpMem(A1)		; ext memory replaces ext size!
	;;add.l	D1,D0

.noext

	lea	data_str(pc),a0
	tst.b	(a0)
	bne.b	.nocurdir		; CurrentDir overridden: don't use data subdir from the slave
	
	; no DATA keyword on command line: read slave current dir
	moveq.l	#0,D0
	add.w	ws_CurrentDir(A1),D0
	beq	.nocurdir
	add.l	A1,D0	; sub directory
	move.l	d0,-(a7)
; < D1: dirname (modified)
; < D2: filename
; < D3: max buffer size

	LEAVAR	data_directory,A0
	move.l	A0,D1
	move.l	D0,D2
	move.l	#$80,D3
	bsr	AddPart
	move.l	(a7)+,d0
	
	; apply same thing to unhacked data directory
	lea	unhacked_data_directory(pc),A0
	move.l	A0,D1
	move.l	D0,D2
	move.l	#$80,D3
	bsr	AddPart
	
	
.nocurdir	
	IFEQ	1
	PRINT	"Base+exp mem size: "
	PRINTH	D0
	PRINTLN
	
	moveq.l	#0,D0
	move.w	ws_Flags(A1),D0
	PRINT	"Flags: "
	PRINTH	D0
	PRINTLN
	ENDC

	SETVAR_B	ws_keyexit(A1),quitkey
	move.b	#$7E,ws_keydebug(A1) ; trash the keydebug so slaves which hardcode debug stuff won't trigger it

	rts

.kickrnerror:
		SET_VAR_CONTEXT
		PRINT_MSG	error_prefix
		PRINT	"RNCD/IDEHD is not compatible with kickstart emulation (yet)"
		bra.b	CloseAll

vbr_alloc_error:
	PRINT_MSG	error_prefix
	PRINT	"Cannot allocate $100 bytes for VBR!!"
	bra	CloseAll
	
FreezeAll:
	MOVE.W	#$7FFF,intena+$DFF000
	MOVE.W	#$7FFF,dmacon+$DFF000
	MOVE.W	#$7FFF,intreq+$DFF000
	MOVE.W	#$7FFF,adkcon+$DFF000
	rts
ReadArgsString:
	dc.b	"SLAVE/A,CDSLAVE/K,DATA/K,CUSTOM/K,CUSTOM1/K/N,CUSTOM2/K/N,CUSTOM3/K/N,CUSTOM4/K/N,CUSTOM5/K/N,"
	dc.b	"FORCECHIP/K,FORCEEXP/K,FORCEOPT/S,"
	dc.b	"NTSC/S,PAL/S,BUTTONWAIT/S,FILTEROFF/S,D/S,PRETEND=TEST/S,NOVBRMOVE/S,CPUCACHE/S,IDEHD/S,DISKUNIT/K/N,"
	dc.b	"JOYPAD/K/N,"
	dc.b	"JOY1RED/K,JOY1GREEN/K,JOY1YELLOW/K,JOY1BLUE/K,JOY1FWD/K,JOY1BWD/K,JOY1PLAY/K,JOY1FWDBWD/K,"
	dc.b	"JOY1RIGHT/K,JOY1LEFT/K,JOY1UP/K,JOY1DOWN/K,"
	dc.b	"JOY0RED/K,JOY0GREEN/K,JOY0YELLOW/K,JOY0BLUE/K,JOY0FWD/K,JOY0BWD/K,JOY0PLAY/K,JOY0FWDBWD/K,"
	dc.b	"JOY0RIGHT/K,JOY0LEFT/K,JOY0UP/K,JOY0DOWN/K,"
	dc.b	"VK/K,VM/K,VMDELAY/K/N,VMMODDELAY/K/N,VMMODBUT/K,"
	dc.b	"CDBUFFER/K,CDBUFFER2/K,FREEBUFFER/K,NB_READ_RETRIES/K/N,CDFREEZE/S,NOBUFFERCHECK/S,RETRYDELAY/K/N,READDELAY/K/N,RESLOAD_TOP/K,TIMEOUT/K/N,AUTOREBOOT/S,"
	dc.b	"FREEZEKEY/K,FILECACHE/S,PRELOAD/K,USEFASTMEM/S,MASKINT2/S,MASKINT6/S,CDX1/2,DEBUG/S,FAILSAFE/S"		; PRELOAD is different from WHDLoad option
	dc.b	0
	even
	
start:
	tst.l	RtnMess
	bne	.wbunsup
	
	SET_VAR_CONTEXT
	; see how much chipmem we have (lame!!)
	move.l	#10,D0
	move.l	#MEMF_CHIP|MEMF_REVERSE,D1
	move.l	_SysBase,A6
	JSRLIB	AllocMem
	move.l	d0,d4
	move.l	d0,a1
	move.l	#10,D0
	JSRLIB	FreeMem
	
	; round to the upper 512k
	add.l	#$80000,d4
	and.l	#$FFF80000,d4
	move.l	d4,d0
	SETVAR_L	d0,top_system_chipmem
	
	; with WinUAE with 4MB chip, MaxLocMem still returns $200000 whereas I can alloc blocks above $300000 using MEMF_REVERSE
	; so I'm not using it, since I use WinUAE 4MB setting to test CDBUFFER locations. The alloc method above works fine
	; when memory is not all taken of course!
	
	;move.l	MaxLocMem(a6),d0		; gives wrong results when chipmem is above 2MB (WinUAE)
	SETVAR_L	d0,resload_top	; TODO adapt if fastmem
	
	sub.l	#CD_BUFFER_SIZE,D0
	move.l	D0,max_cdbuffer_address
	
	; 3000 ~ 200 ms => time to wait between 2 reads when a fail occurs
	; should not be set to a value lower than that
	; tests on WinUAE show that game that work on real hardware have a 150ms delay between each ead
	; games using a lower value tend to fail
	SETVAR_L	#3000,retrydelay_value
	; time to wait between 2 reads, period (this will wait even if the reads are
	; far away from each other, there's no reliable way to time the calls since interrupts
	; can be disabled, too bad for counting the time with CIA or VBL
	SETVAR_L	#3000,readdelay_value
	SETVAR_L	#709379,eclock_freq	; PAL forced: TODO adapt NTSC
	SETVAR_L	#2,nb_retries
	; default values for joypad 1
	SETVAR_B	#$19,joy1_play_keycode	; P
	SETVAR_B	#$50,joy1_bwd_keycode	; F1
	SETVAR_B	#$51,joy1_fwd_keycode	; F2
	
	SETVAR_B	#$44,joy1_green_keycode	; RETURN
	SETVAR_B	#$40,joy1_blue_keycode	; SPACE
	SETVAR_B	#$64,joy1_yellow_keycode	; left-ALT
	SETVAR_B	#$45,joy1_fwdbwd_keycode	; ESC
	
	; default values for joypad 0
	SETVAR_B	#$19,joy0_play_keycode	; P	;(same as player 1)
	SETVAR_B	#$52,joy0_bwd_keycode	; F3
	SETVAR_B	#$53,joy0_fwd_keycode	; F4
	
	SETVAR_B	#$01,joy0_green_keycode	; 1
	SETVAR_B	#$02,joy0_blue_keycode	; 2
	SETVAR_B	#$41,joy0_yellow_keycode	; backspace
	SETVAR_B	#$45,joy0_fwdbwd_keycode	; ESC

	move.l	#ReadArgsString,d1
	move.l	#ProgArgs,d2
	moveq.l	#0,d3
	move.l	_DosBase,A6

	JSRLIB	ReadArgs

	move.l	d0,rdargs_struct		;NULL is OK
	beq	ReadArgsErr
	
	
	; ** copy the object name in a buffer

	
	lea	ProgArgs(pc),A0
	move.l	(A0)+,D0
	beq.b	.skn
	move.l	#slave_name,D1
	bsr	StrcpyAsm
.skn
	move.l	(A0)+,D0
	beq.b	.skcds
	LEA	cd_slave_name(pc),A1
	move.l	A1,D1
	bsr	StrcpyAsm
.skcds
	move.l	(A0)+,D0
	beq.b	.skd
	LEA	data_str(pc),A1
	move.l	A1,D1
	bsr	StrcpyAsm
.skd
	move.l	(A0)+,D0
	beq.b	.sku
	LEAVAR	custom_str,A1
	move.l	A1,D1
	bsr	StrcpyAsm
.sku
	SETVAR_L	#2,joypad_flag	; default: mapping on port 2 only

	; *** users flags
	
	move.l	(A0)+,D0
	beq.b	.skc1
	move.l	D0,A1
	SETVAR_L	(a1),custom1_flag
.skc1
	move.l	(A0)+,D0
	beq.b	.skc2
	move.l	D0,A1
	SETVAR_L	(a1),custom2_flag
.skc2
	move.l	(A0)+,D0
	beq.b	.skc3
	move.l	D0,A1
	SETVAR_L	(a1),custom3_flag
.skc3
	move.l	(A0)+,D0
	beq.b	.skc4
	move.l	D0,A1
	SETVAR_L	(a1),custom4_flag
.skc4
	move.l	(A0)+,D0
	beq.b	.skc5
	move.l	D0,A1
	SETVAR_L	(a1),custom5_flag
.skc5
	move.l	(A0)+,D0	; FORCECHIP
	beq.b	.nofchip
	move.l	D0,A1
	bsr	HexStringToNum
	tst.l	D0
	beq.b	.nofchip
	move.l	D0,force_chipmem
.nofchip
	move.l	(A0)+,D0	; FORCEEXP
	beq.b	.nofexp
	move.l	D0,A1
	bsr	HexStringToNum
	tst.l	D0
	beq.b	.nofexp
	move.l	D0,force_expmem
.nofexp
	move.l	(a0)+,force_optional_memory_flag	; FORCEOPT
		
	SETVAR_L	(A0)+,ntsc_flag		; Force NTSC
	bne.b	.skippal
	SETVAR_L	(A0),pal_flag		; Force PAL
.skippal
	add.l	#4,a0
	SETVAR_L	(A0)+,buttonwait_flag	; waits fire after loads to be able to read
	SETVAR_L	(A0)+,filteroff_flag			; CHANGE IT IF ADD OTHER TOOLTYPES BETWEEN
	SETVAR_L	(A0)+,d_flag			; CHANGE IT IF ADD OTHER TOOLTYPES BETWEEN
	move.l	(A0)+,pretend_flag
	SETVAR_L	(A0)+,novbrmove_flag
	SETVAR_L	(A0)+,cpucache_flag
	move.l	(A0)+,idehd_flag
	; 0-3
	move.l	(A0)+,D0
	beq.b	.skdu
	move.l	D0,A1
	move.l	(a1),diskunit_number
.skdu
	move.l	(A0)+,D0
	beq.b	.skjoy
	move.l	D0,A1
	; 0: no joypad remapping
	; 1: joyport 0 remapping only
	; 2: joyport 1 remapping only (default)
	; 3: both joyports remapping
	SETVAR_L	(a1),joypad_flag	
	beq.b	.skjoy
	st.b	explicit_joypad_option
.skjoy
	
	
	PARSEHEXARG	joy1_red
	PARSEHEXARG	joy1_green
	PARSEHEXARG	joy1_yellow
	PARSEHEXARG	joy1_blue
	PARSEHEXARG	joy1_fwd
	PARSEHEXARG	joy1_bwd
	PARSEHEXARG	joy1_play
	PARSEHEXARG	joy1_fwdbwd
	
	PARSEHEXARG joy1_right
	PARSEHEXARG joy1_left
	PARSEHEXARG joy1_up
	PARSEHEXARG joy1_down
	
	PARSEHEXARG	joy0_red
	PARSEHEXARG	joy0_green
	PARSEHEXARG	joy0_yellow
	PARSEHEXARG	joy0_blue
	PARSEHEXARG	joy0_fwd
	PARSEHEXARG	joy0_bwd
	PARSEHEXARG	joy0_play
	PARSEHEXARG	joy0_fwdbwd
	
	PARSEHEXARG joy0_right
	PARSEHEXARG joy0_left
	PARSEHEXARG joy0_up
	PARSEHEXARG joy0_down
	
	move.l  (A0)+,D0	; VK
	tst.b	D0
	beq.b	.skipvk
	move.l	D0,A1
	bsr	HexStringToNum
	tst.b	D0
	beq.b	.skipvk
	SETVAR_B	D0,vk_button
	
.skipvk
	move.l  (A0)+,D0	; VM
	tst.b	D0
	beq.b	.skipvm
	move.l	D0,A1
	bsr	HexStringToNum
	tst.b	D0
	beq.b	.skipvm
	SETVAR_B	D0,vm_button
.skipvm

	move.l		(A0)+,D0	; VMDELAY
	beq.b		.skipvmdelay
	move.l		D0,A1
	SETVAR_L	(a1),vm_delay
	SETVAR_B	#1,vm_enabled
	
.skipvmdelay
	move.l		(A0)+,D0	; VMMODDELAY
	beq.b		.skipvmoddelay
	move.l		D0,A1
	SETVAR_L	(a1),vm_modifierdelay
	SETVAR_B	#1,vm_enabled
	
.skipvmoddelay
	move.l  (A0)+,D0		; VMMODBUT
	tst.b	D0
	beq.b	.skipvmodifybutton
	move.l	D0,A1
	bsr	HexStringToNum
	tst.b	D0
	beq.b	.skipvmodifybutton
	SETVAR_B	D0,vm_modifierbutton
	
.skipvmodifybutton
	move.l	(A0)+,D0	; CDBUFFER
	beq.b	.skb
	LEA	cdio_asked_buf_str(pc),A1
	move.l	A1,D1
	bsr	StrcpyAsm
	
	lea	cdio_asked_buf_str(pc),a1
	bsr	HexStringToNum
	; D0 holds main CDBUFFER address
	cmp.l	#MIN_CDBUFFER_ADDRESS,D0
	bcs	.buferror
	cmp.l	max_cdbuffer_address(pc),D0
	bcc	.buferror
	and.l	#$FFFF0000,d0	; align on 64k or won't work
	SETVAR_L	D0,cdio_buffer_1

.skb
; optional alternate CDBUFFER address
	move.l	(A0)+,D0	; CDBUFFER2
	beq.b	.skb2
	LEA	cdio_asked_buf_str(pc),A1
	move.l	A1,D1
	bsr	StrcpyAsm
	
	lea	cdio_asked_buf_str(pc),a1
	bsr	HexStringToNum
	; D0 holds alternate CDBUFFER address
	cmp.l	#MIN_CDBUFFER_ADDRESS,D0
	bcs	.buferror
	cmp.l	max_cdbuffer_address(pc),D0
	bcc	.buferror
	and.l	#$FFFF0000,d0	; align on 64k or won't work
	; we want buffer 1 below buffer 2: force it
	; it will minimze the dynamic buffer selection tests
	GETVAR_L	cdio_buffer_1,D1
	cmp.l	D0,D1
	bcs.b	.ok
	; not what we want: swap them
	exg.l	D0,D1
	SETVAR_L	D1,cdio_buffer_1
.ok
	SETVAR_L	D0,cdio_buffer_2

.skb2
; optional FREEBUFFER address. When using CDBUFFER2, this is required
	move.l	(A0)+,D0		; FREEBUFFER
	beq.b	.skb3
	LEA	cdio_asked_buf_str(pc),A1
	move.l	A1,D1
	bsr	StrcpyAsm
	
	lea	cdio_asked_buf_str(pc),a1
	bsr	HexStringToNum
	; D0 holds free/swap buffer address, can be anywhere
	cmp.l	max_cdbuffer_address(pc),D0
	bcc	.buferror
	SETVAR_L	D0,free_buffer

.skb3

	move.l	(A0)+,D0	; NB_READ_RETRIES
	beq.b	.skretries
	move.l	D0,A1
	SETVAR_L	(a1),nb_retries
.skretries
	SETVAR_L	(A0)+,cdfreeze_flag	; CDFREEZE
	SETVAR_L	(A0)+,nobuffercheck_flag	; NOBUFFERCHECK
	bne.b	.skc
	
	GETVAR_L	cdio_buffer_1,d0
	beq.b	.skc
	cmp.l	#MIN_CDBUFFER_ADDRESS,D0
	bcs	.buferror
	cmp.l	max_cdbuffer_address(pc),D0
	bcc	.buferror

.skc
	move.l	(A0)+,D0	; RETRYDELAY
	beq.b	.skrtd
	move.l	D0,A1
	SETVAR_L	(a1),retrydelay_value
.skrtd
	move.l	(A0)+,D0	; READDELAY
	beq.b	.skrd
	move.l	D0,A1
	SETVAR_L	(a1),readdelay_value
.skrd

	move.l	(A0)+,D0	; RESLOAD_TOP
	beq.b	.skrl
	LEA	cdio_asked_buf_str(pc),A1
	move.l	A1,D1
	bsr	StrcpyAsm
	move.l	A1,D0
	bsr	ToUpperAsm
	
	lea	cdio_asked_buf_str(pc),a1
	bsr	HexStringToNum

	cmp.l	#$10000,D0
	bcs	.resload_error
	CMPVAR_L	top_system_chipmem,D0
	bcc	.resload_error
	
	SETVAR_L	d0,resload_top
	; if resload_top is set, enable nobuffercheck
	SETVAR_L	#1,nobuffercheck_flag
	
.skrl
	move.l	(A0)+,D0	; TIMEOUT
	beq.b	.skto
	move.l	D0,A1
	move.l	(a1),timeout_in_seconds
.skto
	SETVAR_L	(a0)+,autoreboot_flag

	move.l	(A0)+,D0
	beq.b	.skdk
	move.l	D0,A1
	bsr	HexStringToNum
	SETVAR_B	d0,freeze_key
.skdk
	SETVAR_L	(a0)+,filecache_flag
	
	move.l	(A0)+,D0
	beq.b	.skpreload
	lea	preload_file(pc),A1
	move.l	A1,D1
	bsr	StrcpyAsm
	SETVAR_L	#1,filecache_flag	; PRELOAD implies FILECACHE
	SETVAR_L	#1,delay_cdinit_flag	; PRELOAD implies delay_cdinit_flag
.skpreload
	SETVAR_L	(a0)+,use_fastmem
	SETVAR_L	(a0)+,mask_int_2_flag
	SETVAR_L	(a0)+,mask_int_6_flag
	SETVAR_L	(a0)+,cdreadspeedx1_flag	; only with Psygore reader
	SETVAR_L	(a0)+,debug_flag
	tst.l	(a0)+	; failsafe
	beq.b	.nofailsafe
	; failsafe activates flags which degrade CD32load features but give more chance
	; to programs to work: equivalent to JOYPAD=0 CDFREEZE CD1X
	; MASKINT6 isn't included because it can also cause issues
	; MASKINT2 isn't included because CDFREEZE overrides it
	SETVAR_L	#-1,cdreadspeedx1_flag
	SETVAR_L	#-1,cdfreeze_flag
	SETVAR_B	#0,vbl_redirect
	CLRVAR_L	joypad_flag
.nofailsafe
	
	; end of arguments
    
	; swap joypad 1=>0 if joypad in port 0
	; also check if buttons pressed to enable CUSTOMx tooltypes
    ; and disable CD play
	bsr	CheckJoypads

	
	lea	cdx_name(pc),A0
	move.b	2(A0),D0
	add.l	diskunit_number(pc),D0	; CDx:
	move.b	D0,2(A0)
	move.l	A0,D0
	move.l	d0,a1
	bsr	ObjectExists
	tst.l	D0
	beq.b	.cdexists
	move.l	#1,idehd_flag	; CD does not exist: force IDE HD
.cdexists
	move.l	#slave_name,D1
	bsr	IsAbs
	; make slave name absolute
	tst.l	D0
	beq.b	.absok
	; get current dir string
	lea	nullname(pc),A0
	move.l	A0,D1
	move.l	#ACCESS_READ,D2
	move.l	_DosBase,A6
	JSRLIB	Lock
	move.l	D0,D4
	move.l	D0,D1
	lea		current_dir(pc),A0
	move.l	A0,D2
	move.l	#$100,D3
	JSRLIB	NameFromLock
	move.l	D4,D1
	JSRLIB	UnLock
	
	lea		current_dir(pc),A0
	move.l	A0,D1
	move.l	#slave_name,D2
	move.l	#$100,D3
	bsr	AddPart
	; transfer in slave_name
	move.l	A0,D0
	move.l	D2,D1
	bsr	StrcpyAsm
.absok
	move.l	#slave_name,D1
	; default: data_directory is the same as slave directory
	lea	unhacked_data_directory(pc),A0
	move.l	A0,D2
	bsr	Dirname

	move.l	#slave_name,D0
	lea	tmpstring2(pc),A0
	move.l	A0,D1
	bsr	StrcpyAsm
; hack data dir to CD0:/DH0:
.skipcolon:
	move.b	(a0),d1
	beq.b	.scout
	addq.l	#1,A0
	cmp.b	#':',d1
	bne.b	.skipcolon
	subq.l	#1,A0
	; turn device to CD0: (hack but 1: difficult to convert label to device and 2: CD0: could be a SCSI-CDROM anyway)
	move.l	diskunit_number(pc),d0
	add.b	#'0',d0
	move.b	d0,-(A0)
	tst.l	idehd_flag
	bne.b	.fromhd
	move.b	#'D',-(A0)
	move.b	#'C',-(A0)
	bra.b	.scout
.fromhd
	; from HD: we have to use RN loader
	SETVAR_B	#1,use_rn_loader
	move.b	#'H',-(A0)
	move.b	#'D',-(A0)
.scout

	; default: data_directory is the same as slave directory
	move.l	A0,D1
	LEAVAR	data_directory,A0
	move.l	A0,D2
	bsr	Dirname

; < D1: dirname (modified)
; < D2: filename
; < D3: max buffer size
; > D0: !=0 if ok, =0 if buffer overflow

	LEA	data_str(pc),A0
	tst.b	(a0)
	beq.b	.nodata
	move.l	A0,D2
	LEAVAR	data_directory,A0
	move.l	A0,D1
	move.l	#$80,D3
	bsr	AddPart
	
	LEA	data_str(pc),A0
	move.l	A0,D2
	lea	unhacked_data_directory(pc),A0
	move.l	A0,D1
	move.l	#$80,D3
	bsr	AddPart
	
.nodata
	GETVAR_L	top_system_chipmem,D4
	cmp.l	#$100000,D4
	bcc.b	.chipok
	PRINT_MSG	error_prefix
	PRINT	"Program needs at least 1MB chipmem, found "
	PRINTH	D4
	PRINTLN	" bytes."
	bra	CloseAll
.chipok
	; get slave size
	move.l	#slave_name,D0
	bsr	GetFileLength
	tst.l	D0
	bmi	.noslave
	sub.l	#$20,D0
	bmi	.noslave
	move.l	D0,whd_slave_size
	move.l	d0,d4
	
	tst.b	cd_slave_name
	beq.b	.nocdslave
	move.l	#cd_slave_name,d0
	bsr	GetFileLength
	sub.l	#$20,D0
	bmi	.nocdslave
	move.l	D0,cd_slave_size
	add.l	#4,d4
	and.l	#$FFFFFFFC,d4	; align 4 bytes
	move.l	d4,cd_slave_offset
	add.l	d0,d4			; add cd slave size
.nocdslave
	; slave + cdslave size + align
	SETVAR_L	d4,slaves_size
	move.l	d4,d0
	; alloc slave memory
	;;move.l	slave_size(pc),d0
	move.l	#MEMF_PUBLIC,D1
	move.l	_SysBase,A6
	JSRLIB	AllocMem
	move.l	d0,slave_start
	beq	slave_alloc_error
	
	; check CD buffer consistency
	GETVAR_L	cdio_buffer_2,D0
	beq.b	.noaltcd
	TSTVAR_L	free_buffer
	bne.b	.fzok
	; error: free buffer is not defined
	PRINT_MSG	error_prefix
	PRINTLN	"When CDBUFFER2 is defined, FREEBUFFER must also be defined"
	bra	CloseAll
.fzok
	; would be good to check freezone overlap with buffers too

	GETVAR_L	cdio_buffer_1,D1
	cmp.l	D0,D1
	bne.b	.bdiff	; different addresses: OK
	; error: cd buffers are located at the same aligned address
	PRINT_MSG	error_prefix
	PRINTLN	"CDBUFFER2 must be located at a different location than CDBUFFER"
	bra	CloseAll
.bdiff
	sub.l	D0,D1
	bcc.b	.pos
	neg.l	D1
.pos
	cmp.l	#CD_BUFFER_SIZE,D1
	bcc.b	.noaltcd
	; check that CDBUFFER 1&2 are not too close
	PRINT_MSG	error_prefix
	PRINTLN	"CDBUFFER2 must be far enough of CDBUFFER (at least $20000 bytes)"
	bra	CloseAll	
.noaltcd
	tst.l	idehd_flag
	beq	.skipchk
	lea	data_str(pc),A1
	move.l	#ACCESS_READ,D2
	move.l	a1,d1
	move.l	_DosBase,a6
	JSRLIB	Lock
	move.l	d0,d1
	beq.b	.skipchk	; cannot happen
	
	move.l	d1,d3	; save lock
	move.l	#infobuffer,D2
	JSRLIB	Info
	tst.l	d0
	beq.b	.skipchk	; cannot happen
	
	lea	infobuffer(pc),a1
	move.l	(id_BytesPerBlock,a1),d0

	
	cmp.l	#$200,d0	; 512 block size or error
	beq.b	.sizeok
	PRINT_MSG	error_prefix
	move.l	d3,d1	; saved lock
	JSRLIB	UnLock		; unlock subdirectory
	PRINTLN	"Data disk block size must be 512 bytes"
	bra	CloseAll
.sizeok
	move.l	(id_DiskType,a1),d0
	clr.b	d0
	cmp.l	#$444F5300,d0
	beq.b	.typeok
	move.l	d3,d1	; saved lock
	JSRLIB	UnLock		; unlock subdirectory
	PRINT_MSG	error_prefix
	PRINTLN	"Data disk type should be DOS"
	bra	CloseAll
.typeok
	move.l	d3,d1	; saved lock
	JSRLIB	UnLock		; unlock subdirectory
	moveq.l	#0,d2
.skipchk

	
	; load slave from disk
	bsr	LoadSlave

	
	; display info about slave & fill structures
	bsr	LinkSlaveInfo

	; detect debugger and adapt resload_top if needed

	bsr	DetectDebugger
	
	; automatic cd buffer computation
	bsr	ComputeCdBuffer
	
	; store attnflags to rel zone
	bsr	ComputeAttnFlags
	
	GETVAR_L	attnflags,D0	; save attnflags in fastmem
	btst	#AFB_68010,D0
	bne.b	.vbrok
	; 68000: force NOVBRMOVE
	SETVAR_L	#1,novbrmove_flag
.vbrok

	TSTVAR_L	novbrmove_flag
	beq.b	.novbm

	tst.b	explicit_joypad_option
	beq.b	.noejo
	; explicit joypad option set and NOVBRMOVE/68000 CPU:
	; enable special VBL interrupt remap to be able to enjoy remap on A600/68000/IDEHD or NOVBRMOVE
	SETVAR_B	#1,vbl_redirect
.noejo
	TSTVAR_L	mask_int_6_flag
	beq.b	.novbm
	PRINT_MSG	error_prefix
	PRINT	"NOVBRMOVE cannot be used alongside MASKINT6"
	bra	CloseAll	
.novbm
	lea	unhacked_data_directory(pc),A1
	move.l	A1,D0
	bsr	ObjectExists
	tst.l	d0
	beq.b	.data_exists
	PRINT_MSG	error_prefix
	PRINT		"Cannot lock "
	lea	unhacked_data_directory(pc),A1
	bsr	Display
	PRINTLN	
	bra	CloseAll
	
	
.data_exists
	; compute read buffer address (useful only if FILECACHE is on or RNCD/HD is needed
	GETVAR_L	top_game_mem,D0
	; don't forget to add RTB size or file will be corrupted by RTB copy
	; on whd bootstrap
	ADDVAR_L	kick_and_rtb_size,D0
	SUBVAR_L	kicksize,D0
	add.l	#$F,D0
	and.l	#$FFFFFFF0,D0		; align on $10 byte boundary
	SETVAR_L	D0,read_buffer_address
	
	; try to load file in cache
	tst.b	preload_file
	beq.b	.nopreload
	; if PRELOAD is set with some file, we try to AllocAbs the datablock computed
	; above to read the big file using AmigaOS ROM CD routines, supposedly more reliable
	; and also avoid interactions between game & cd loader
	
	; compose full path of preload file
; < D1: dirname (modified)
; < D2: filename
; < D3: max buffer size

	; TODO: if IDEHD mode and not DH0, PRELOAD won't be effective. But PRELOAD is not really useful in IDE mode
	LEAVAR	data_directory,A1
	move.l	a1,d0
	move.l	#tmpstring2,d1
	bsr		StrcpyAsm
	
	move.l	#preload_file,d2
	move.l	#200,D3
	bsr	AddPart
	
	move.l	#tmpstring2,d0
	bsr		GetFileLength
	move.l	d0,allocated_filesize	; save it
	bmi.b	.preload_file_error

	move.l	_SysBase,A6
	; here we allocate PRELOAD memory for the file passed as arguments
	TSTVAR_L	use_fastmem
	beq.b	.nofast
	move.l	#MEMF_FAST|MEMF_CLEAR,d1
	JSRLIB	AllocMem
	tst.l	d0
	beq	.fastfail
	; set NOBUFFERCHECK: fastmem is used, so it will work okay
	; and buffer check computation doesn't account for fastmem so better
	; disable it now or it will fail
	SETVAR_L	#1,nobuffercheck_flag
	bra.b	.cont
.nofast
	GETVAR_L	read_buffer_address,A1
	JSRLIB	AllocAbs		; caveat: if memory is taken, it won't work
.cont
	move.l	d0,allocated_filecache
	beq.b	.alloc_error

	; the value will be different because of rounding
	; that's why we added a $10 safety margin because previous bytes
	; will be used for RTB data end (and not allocated)
	SETVAR_L	d0,read_buffer_address	
	
	; all OK: load file in memory
	move.l	#tmpstring2,D1		; full file path
	move.l	#MODE_OLDFILE,D2
	move.l	_DosBase,A6
	JSRLIB	Open
	move.l	D0,D6
	beq	.alloc_error	; very unlikely!!

	; ** Read the contents
	move.l	D6,D1
	move.l 	allocated_filesize(pc),D3
	move.l	allocated_filecache(pc),D2
	JSRLIB	Read

	; ** Close the file

	move.l	D6,D1
	JSRLIB	Close

	
	; register the file in the resload cache, else it would be useless to have read it
	move.l	#preload_file,d0
	LEAVAR	last_loaded_file,a0
	move.l	a0,d1
	bsr	StrcpyAsm
	SETVAR_L	allocated_filesize,last_loaded_filesize
	bra.b	.nopreload
.preload_file_error
	PRINT	"Warning: PRELOAD option cancelled: cannot lock file '"
	lea	tmpstring2(pc),A1
	bsr	Display
	PRINTLN	"'"
	bra.b	.nopreload
.alloc_error
	; could also happen for fast memory allocation failure, but in that case, we exit with a
	; fatal error instead
	PRINT	"Warning: PRELOAD option cancelled: cannot alloc absolute memory at "
	GETVAR_L	read_buffer_address,A1
	move.l	a1,d0
	PRINTH	d0
	PRINTLN
	
.nopreload
	; compute total reloc length, both loaders are useless together
	; we select the one which is required, which saves precious memory, specially
	; for 2MB chip / AGA games
	tst.l	idehd_flag
	bne.b	.rnl
	; Psygore CD loader, only CD, smaller
	move.l	#pgloader_end,loader_len
	sub.l	#pgloader,loader_len
	move.l	#pgloader,loader_start
	bra.b	.relocend
.rnl
	; RN CD/HD loader, mostly useful to read from HD, bigger
	move.l	#rnloader_end,loader_len
	sub.l	#rnloader,loader_len
	move.l	#rnloader,loader_start
.relocend
	move.l	#reloc_end,D0
	sub.l	#reloc_start,D0
	move.l	d0,reloc_len	; relocatable but not optional I/O code
	add.l	loader_len,d0
	move.l	d0,resload_len	; total relocated (not including slave)

	
	tst.l	timeout_in_seconds
	beq.b	.xx
	; timeout overrides buttonwait
	CLRVAR_L	buttonwait_flag
	
	TSTVAR_L	novbrmove_flag
	beq.b	.xx
	PRINT_MSG	error_prefix
	PRINT		"TIMEOUT and NOVBRMOVE cannot be set together"
	PRINTLN
	bra	CloseAll
.xx
	
	tst.l	pretend_flag
	beq		.nodisplayparams

	; display parameters
	PRINT	"Slave file: "
	PRINT_MSG	slave_name
	PRINT " "
	move.l	whd_slave_size,D0
	PRINTH	D0
	PRINT " bytes"
	PRINTLN
	tst.b	cd_slave_name
	beq.b	.nocdslave1
	PRINT	"CD Slave file: "
	PRINT_MSG	cd_slave_name
	PRINT " "
	move.l	cd_slave_size,D0
	PRINTH	D0
	PRINT " bytes"
	PRINTLN
.nocdslave1
	PRINT	"Data root dir (hacked for raw drive name): "
	LEAVAR	data_directory,A1
	bsr	Display
	PRINTLN
	PRINT	"Data root dir: "
	lea	unhacked_data_directory(pc),A1
	bsr	Display
	
	moveq.l	#0,d0
	PRINTLN
	PRINT	"JOY1BLUE: "
	GETVAR_B	joy1_blue_keycode,D0
	PRINTH	D0
	PRINTLN
	PRINT	"JOY1YELLOW: "
	GETVAR_B	joy1_yellow_keycode,D0
	PRINTH	D0
	PRINTLN
	PRINT	"JOY1GREEN: "
	GETVAR_B	joy1_green_keycode,D0
	PRINTH	D0
	PRINTLN
	PRINT	"JOY1RED: "
	GETVAR_B	joy1_red_keycode,D0
	PRINTH	D0
	PRINTLN
	PRINT	"JOY1PLAY: "
	GETVAR_B	joy1_play_keycode,D0
	PRINTH	D0
	PRINTLN
	PRINT	"VIRTUAL MOUSE: "
	GETVAR_L	vm_delay,D0
	PRINTH	D0
	PRINTLN
	PRINT	"RESLOAD_TOP: "
	GETVAR_L	resload_top,D0
	PRINTH	D0
	PRINTLN
	PRINT	"RETRYDELAY: "
	GETVAR_L	retrydelay_value,D0
	PRINTH	D0
	PRINTLN
	PRINT	"READDELAY: "
	GETVAR_L	readdelay_value,D0
	PRINTH	D0
	PRINTLN
	PRINT	"resload+slave(s) len: "
	move.l	resload_len,D0
	ADDVAR_L	slaves_size,d0
	PRINTH	D0
	PRINTLN
	
	tst.l	swapjoy
	
	beq.b	.noswap
	PRINTLN	"*** Joystick <-> Joypad mapping swap ***"
.noswap
	move.l	debugger_nmi,d0
	beq.b	.nodebugger
	PRINT	"HRTMon detected at "
	PRINTH	D0
	PRINTLN
.nodebugger
	moveq.l	#0,d0
	GETVAR_B	freeze_key,d0
	beq.b	.nodkset
	PRINT	"FREEZEKEY: "
	PRINTH	D0
	PRINTLN
.nodkset
	GETVAR_L	nb_retries,d0
	PRINT	"NB_READ_RETRIES: "
	PRINTH	D0
	PRINTLN

	TSTVAR_L	filecache_flag
	beq.b	.nofilecache
	PRINTLN	"File cache/preloading activated"
	tst.l	allocated_filecache
	beq.b	.nofilecache
	PRINT	"File '"
	lea	preload_file(pc),a1
	bsr	Display
	PRINT	"' preloaded at "
	move.l	allocated_filecache(pc),d0
	PRINTH	D0
	PRINTLN
	
.nofilecache
	TSTVAR_L	cdfreeze_flag
	beq.b	.nocdfreeze
	PRINTLN	"Interrupts disabled when loading from CD (CDFREEZE)"
.nocdfreeze

	tst.l	idehd_flag
	beq.b	.noide
	PRINTLN	"IDE RN HD loader activated"	
.noide
	PRINTLN
	PRINT	"Custom arg: "
	LEAVAR	custom_str,A1
	bsr	Display
	PRINTLN
	PRINT	"Custom1: "
	GETVAR_L	custom1_flag,D0
	PRINTH	D0
	PRINTLN
	PRINT	"Custom2: "
	GETVAR_L	custom2_flag,D0
	PRINTH	D0
	PRINTLN
	PRINT	"Custom3: "
	GETVAR_L	custom3_flag,D0
	PRINTH	D0
	PRINTLN
	PRINT	"Custom4: "
	GETVAR_L	custom4_flag,D0
	PRINTH	D0
	PRINTLN
	PRINT	"Custom5: "
	GETVAR_L	custom5_flag,D0
	PRINTH	D0
	PRINTLN
	PRINT	"Joypad: "
	GETVAR_L	joypad_flag,D0
	PRINTH	D0
	PRINTLN
	PRINT	"Forced display mode: "
	TSTVAR_L	pal_flag

	beq.b	.skp
	PRINT	"PAL"
	bra	.noforce
.skp
	TSTVAR_L	ntsc_flag
	beq	.sknf
	PRINT	"NTSC"
	bra	.noforce
.sknf
	PRINT	"none"
.noforce
	PRINTLN
	PRINT	"Novbrmove: "
	GETVAR_L	novbrmove_flag,D0
	PRINTH	D0
	PRINTLN
	PRINT	"68000/NOVBRMOVE VBLank redirect: "
	moveq	#0,D0
	GETVAR_B	vbl_redirect,D0
	PRINTH	D0
	PRINTLN
	PRINT	"Buttonwait: "
	GETVAR_L	buttonwait_flag,D0
	PRINTH	D0
	PRINTLN
	PRINT	"Debug start: "
	GETVAR_L	d_flag,D0
	PRINTH	D0
	PRINTLN
	PRINT	"CD buffer address: "
	GETVAR_L	cdio_buffer_1,D0
	PRINTH	D0
	PRINTLN
	GETVAR_L	cdio_buffer_2,D0
	beq.b	.skipcd2
	PRINT	"Second CD buffer address: "
	PRINTH	D0
	PRINTLN
	PRINT	"Free buffer address: "
	GETVAR_L	free_buffer,D0
	PRINTH	D0
	PRINTLN
.skipcd2
	PRINT	"Top game chipmem: "
	GETVAR_L	maxchip,D0
	PRINTH	D0
	PRINTLN
	PRINT	"Top game mem: "
	GETVAR_L	top_game_mem,D0
	PRINTH	D0
	PRINTLN


	IFEQ	1
	cmp.l	#AKIKO_ID,AKIKO_BASE
	bne.b	.skipakdump

	; leave time to pause / CD state to stabilize (???)
	PRINTLN	"Akiko registers: "
	move.l	_DosBase(pc),A6
	move.l	#200,D1
	JSRLIB	Delay
	lea	AKIKO_BASE,A0
	moveq	#15,D2
.akikoloop
	PRINTH	A0
	PRINT	" = "
	move.l	(A0)+,d0
	PRINTH	d0
	PRINTLN
	dbf		d2,.akikoloop
.skipakdump
	ENDC
	
	bra	CloseAll
.nodisplayparams	

	; most games only use one buffer: set default
	GETVAR_L	cdio_buffer_1,D0
	SETVAR_L	D0,cdio_buffer

	TSTVAR_L	use_fastmem
	beq.b	.nofastavail
	
	; try to alloc reloc memory in fastmem (SX32/winuae debug config or terrible fire CD32 board)
	GETVAR_L	slaves_size,d0
	add.l	resload_len,D0
	move.l	d0,D2
	move.l	#MEMF_FAST|MEMF_CLEAR,D1
	move.l	_SysBase,A6
	JSRLIB	AllocMem
	tst.l	D0
	beq.b	.nofastavail
	add.l	D2,D0
	move.l	d0,fast_reloc_end
	
.nofastavail

	; delay before shutting OS
	move.l	_DosBase,A6
	move.l	#50,D1
	JSRLIB	Delay

	cmp.l	#AKIKO_ID,AKIKO_BASE
	bne.b	.skipaksave
	; sets the "real CD32" flag. Older versions of Winuae only have CAFE in B80000
	; CD32 & newer WinUAE versions have C0CACAFE in $B80000
	SETVAR_B	#1,realcd32_flag
	; disable all Akiko CD interrupts
	bsr		stop_akiko_activity	
.skipaksave:
	
	; sprites to normal size (useful?)
	
	; degrade display
	lea	gfxname(pc),a1
	moveq.l	#0,d0
	move.l	_SysBase,A6
	JSRLIB	OpenLibrary
	move.l	D0,_GfxBase
	
	
	move.l	_GfxBase,A6
	; save bplcon & chiprev bits so resload_Control can recall them
	SETVAR_W	(gb_system_bplcon0,A6),system_bplcon0
	SETVAR_B	(gb_ChipRevBits0,A6),system_chiprev_bits

	;move.l	gb_ActiView(A6),my_actiview
	;move.l	gb_copinit(A6),my_copinit
	sub.l	A1,A1
	JSRLIB	LoadView
	JSRLIB	WaitTOF
	JSRLIB	WaitTOF

.wav
	tst.l	(gb_ActiView,a6)
	bne.b	.wav
	JSRLIB	WaitTOF

	
	bsr	DegradeBandWidth
	; allocate memory for safe copperlist
	
	lea	$1000.W,a0
	move.l	#-2,(a0)	; end of copperlist
	
	lea	$DFF000,A5
	; copperlist is valid
	move.l	a0,(cop1lc,a5)
	move.l	a0,(cop2lc,a5)
	
	IFEQ	1
	lea	$DFF000+bplpt,A5
	; zero bitplanes: disabled, seems to crash HD mode!!!
	; plus no test AGA/ECS
	move.l	A0,(A5)+
	move.l	A0,(A5)+
	move.l	A0,(A5)+
	move.l	A0,(A5)+
	move.l	A0,(A5)+
	move.l	A0,(A5)+
	move.l	A0,(A5)+
	move.l	A0,(A5)+
	ENDC

	; init custom chips with values expected in kickstart 1.3
	; some games did not take the hassle to set them


	move.w	#0,(bltamod,a5)
	move.w	#0,(bltbmod,a5)
	move.w	#0,(bltcmod,a5)
	move.w	#0,(bltdmod,a5)
	move.w	#0,(bltadat,a5)
	move.w	#0,(bltbdat,a5)
	move.w	#0,(bltcdat,a5)
	
	; Panza Kick Boxing display was too large (some pixels missing)

	move.w	#$1200,(bplcon0,A5)
	move.w	#$0,(bplcon1,A5)	; new from JST v4.7

	; the others were set since Keith told me to set them to 0
	; ex: clear bitplane modulos (gfx problem in Brat)

	move.w	#$0024,(bplcon2,A5)	; sprite priority (Battle Squadron)
	move.w	#$0C40,(bplcon3,A5)
	move.w	#$0011,(bplcon4,A5)	; sprite color table order (Jim Power)
	move.w	#$0,(bpl1mod,A5)
	move.w	#$0,(bpl2mod,A5)

	; set blitter masks to all ones (Lemmings)

	move.w	#$FFFF,(bltafwm,A5)	
	move.w	#$FFFF,(bltalwm,A5)
	
	move.w	#0,(bltamod,A5)
	move.w	#0,(bltbmod,A5)
	move.w	#0,(bltcmod,A5)
	move.w	#0,(bltdmod,A5)

	TSTVAR_L	cpucache_flag
	bne	.5		; Disable ALL caches unless "cpucache" flag is set

	moveq.l	#0,D0
	moveq.l	#-1,D1
	move.l	_SysBase,A6
	JSRLIB	CacheControl
.5

	; freeze interrupts,DMA & go supervisor
	
	bsr	FreezeAll
	bsr	SupervisorMode
	move	#$2000,SR	; like WHDLoad (interrupts are still off because of INTENA)
	
	bsr	InitCIAs
	
	SET_VAR_CONTEXT


	move.l	fast_reloc_end(pc),A6
	cmp.l	#0,A6
	bne.b	.relocfast
	GETVAR_L	resload_top,A6
.relocfast
	GETVAR_L	slaves_size,D0
	sub.l	D0,A6
	SETVAR_L	A6,whd_slave_reloc_start			; relocated slave start
	tst.l	cd_slave_size
	beq.b	.skipcd
	move.l	A6,-(a7)
	add.l	cd_slave_offset,a6
	SETVAR_L	A6,cd_slave_reloc_start			; relocated slave start
	move.l	(a7)+,A6
.skipcd
	; copy slave(s) in memory
	move.l	A6,A1
	move.l	slave_start,A0
	;;move.l	slave_size,D0
	bsr	CopyMem
	; copy CD/HD loader in memory
	sub.l	loader_len,A6

	move.l	loader_start,A0
	move.l	A6,A1
	move.l	loader_len,D0
	bsr	CopyMem
	
	; store relocated version in variables
	SETVAR_L	A6,loader
	
	; now copy reloc part in memory
	sub.l	reloc_len,A6

	
	lea	reloc_start,A0
	move.l	A6,A1
	move.l	reloc_len,D0
	bsr	CopyMem


	move.l	A6,A0
	sub.l	#reloc_start,A0
	add.l	#whd_bootstrap,A0	; bootstrap relocated entry
	jmp	(A0)
.wbunsup
	rts
	
.fastfail
	PRINT_MSG	error_prefix
	PRINT		"Cannot use USEFASTMEM option, no/not enough fast memory"
	PRINTLN
	bra	CloseAll

.noslave
	PRINT_MSG	error_prefix
	PRINT		"Cannot lock "
	PRINT_MSG	slave_name
	PRINTLN
	bra	CloseAll
	
.buferror
	PRINT_MSG	error_prefix
	PRINT	"CD buffer must be within range $10000-"
	GETVAR_L	top_system_chipmem,D0
	sub.l	#$12000,d0
	PRINTH	D0
	PRINTLN
	bra	CloseAll
.resload_error
	PRINT_MSG	error_prefix
	PRINTLN	"resload_top must be within range $10000-"
	GETVAR_L	top_system_chipmem,D0
	PRINTH	D0
	PRINTLN
	bra	CloseAll

ComputeCdBuffer:
	SET_VAR_CONTEXT
		
	TSTVAR_L	cdio_buffer_1
	bne.b	.cdset			; already configured: skip

	move.l	fast_reloc_end(pc),A6
	cmp.l	#0,A6
	beq.b	.resloadchip
	; slave/reloc is in fastmem: put buffer as high as possible
	GETVAR_L	resload_top,A6
	bra.b	.store
.resloadchip
	GETVAR_L	resload_top,A6
	sub.l	D3,A6
	GETVAR_L	slaves_size,D0
	sub.l	d0,A6
	; copy slave(s) in memory
	sub.l	resload_len,A6
.store
	sub.l	#CD_BUFFER_SIZE,A6
	move.l	A6,D0
	clr.w	D0		; align on 64k
	SETVAR_L	D0,cdio_buffer_1			; aligned on 64k
	TSTVAR_L	nobuffercheck_flag
	bne.b	.sc
	move.l	slave_start,A1
	move.l	ws_BaseMemSize(A1),D0
	CMPVAR_L	cdio_buffer_1,D0
	beq.b	.ok
	bcc.b	.basemem_err
.ok
	GETVAR_L	top_game_mem,D0
	CMPVAR_L	cdio_buffer_1,D0
	beq.b	.sc
	bcc.b	.expmem_err
.sc
	; if CDBUFFER is set by the user, then don't check the buffer, trust the user
.cdset
	rts
.basemem_err:
	PRINT_MSG	error_prefix
	PRINT	"Basemem ("
	GETVAR_L	maxchip,D0
	PRINTH	D0
	PRINT	") > cdbuffer ("
	GETVAR_L	cdio_buffer_1,D0
	PRINTH	D0
	PRINT	")"
	PRINTLN
	bra	CloseAll
.expmem_err:
	PRINT_MSG	error_prefix
	PRINT	"Base+exp mem ("
	GETVAR_L	top_game_mem,D0
	PRINTH	D0
	PRINT	") > cdbuffer ("
	GETVAR_L	cdio_buffer_1,D0
	PRINTH	D0
	PRINT	")"
	PRINTLN
	bra	CloseAll

SupervisorMode:
	STORE_REGS	D0/D1/A0/A1/A4/A6
	move.l	_SysBase,A6
	JSRLIB	SuperState
	;SETVAR_L	D0,system_superstack
	RESTORE_REGS	D0/D1/A0/A1/A4/A6
	; now we're in supervisor mode
	rts

InitCIAs:
	; since forced CIA init to do exactly like whdload,
	; the $7F in debugkey triggered debug!!!
	; now $00 in debugkey is safe
	lea	$BFE001,A0
	move.b	#%11,(ciaddra,a0)
	move.b	#$21,(ciatahi,a0)
	move.b	#$21,(ciatbhi,a0)
	move.b	#0,(ciaddrb,a0)
	bsr	.init_a_cia
	lea	$BFD000,A0
	move.b	#%11000000,(ciaddra,a0)
	move.b	#$ff,(ciatahi,a0)
	move.b	#0,(ciaddrb,a0)
	move.b	#$ff,(ciatbhi,a0)
	bsr	.init_a_cia
	rts
	
.init_a_cia:
	move.b	#0,(ciapra,a0)
	move.b	#0,(ciaprb,a0)
	move.b	#$FF,(ciatalo,a0)
	move.b	#$FF,(ciatblo,a0)
	move.b	#$0,(ciasdr,a0)
	move.b	#$0,(ciaicr,a0)
	move.b	#$0,(ciacra,a0)
	move.b	#$0,(ciacrb,a0)
	rts

		
DegradeBandWidth:
	STORE_REGS
	SET_VAR_CONTEXT
	move.l	(_GfxBase),a6
	cmp.l	#39,(LIB_VERSION,a6)
	blo	.noaga
	btst	#GFXB_AA_ALICE,(gb_ChipRevBits0,a6)
	beq	.noaga
	GETVAR_W	whdflags,D0
	btst	#WHDLB_ReqAGA,D0
	beq.b	.noaga		; no need to degrade when AGA is required
	;move.b	(gb_MemType,a6),oldbandwidth
	move.b	#BANDWIDTH_1X,(gb_MemType,a6)	;auf ECS Wert setzen
	move.l	#SETCHIPREV_A,D0
	JSRLIB	SetChipRev
	;move.l	D0,oldchiprev

.noaga
	move.w	#50,d0		; todo: compute native screen freq
	
	lea	$DFF000,A5
	TSTVAR_L	pal_flag

	beq.b	.skp
	move.w	#$0020,beamcon0(A5)	; go PAL
	move.w	#50,d0
	SETVAR_L	#709379,eclock_freq	; PAL forced

	bra	.sknf
.skp
	TSTVAR_L	ntsc_flag
	beq	.sknf
	move.w	#$0000,beamcon0(A5)	; go NTSC
	move.w	#60,d0
	SETVAR_L	#715909,eclock_freq	; NTSC forced
.sknf
	MOVE.W	#$0,fmode(A5)		; disable AGA-fetch rate
	move.l	timeout_in_seconds,D1
	mulu	D0,D1
	SETVAR_L	D1,timeout_value
	
	RESTORE_REGS
	rts
	
; in: D0: filename
; out: D0: 0 if OK, -1 if error
ObjectExists:
	STORE_REGS	D2/A6
	moveq.l	#-1,D2

	move.l	D0,D1
	move.l	#ACCESS_READ,D2
	move.l	_DosBase,A6
	JSRLIB	Lock
	move.l	D0,D1		; D5=File Lock
	beq.b	.end

	JSRLIB	UnLock		; unlock subdirectory
	moveq.l	#0,d2
.end
	move.l	D2,D0
	RESTORE_REGS	D2/A6
	rts

; *** VBR operation
; < D0: optional param
; > D0: optional out
; < A0: routine to be called in supervisor mode

get_system_vbr:
	STORE_REGS	D1-D7/A0-A6
	lea	.get_vbr_sup(pc),A5			; supervisor function
	move.l	$4.W,A6
	move.b	AttnFlags+1(A6),D1
	btst	#AFB_68010,D1		; At least 68010
	beq	.error

	JSRLIB	Supervisor
.exit
	RESTORE_REGS	D1-D7/A0-A6
	rts
.error
	moveq.l	#0,D0
	bra	.exit
.get_vbr_sup:
	MC68010
	movec	VBR,D0
	MC68000
	RTE
	
; *** Gets the length (bytes) of a file on the hard drive
; in: D0: filename
; out: D0: length in bytes (-1 if not found!)

GetFileLength
	STORE_REGS	D1-A6
	moveq.l	#-1,D6

	move.l	D0,D1
	move.l	#ACCESS_READ,D2
	move.l	_DosBase,A6
	JSRLIB	Lock
	move.l	D0,D5		; D5=File Lock
	beq.b	.end

	
	bsr	AllocInfoBlock
	move.l	D0,D7

	move.l	D5,D1
	move.l	D7,D2	; infoblock
	bsr	examine

	move.l	D7,A0
	move.l	fib_Size(A0),D6	; file size

	move.l	D5,D1
	move.l	_DosBase,A6
	JSRLIB	UnLock		; unlock subdirectory
	move.l	D7,D0
	bsr	FreeInfoBlock
.end
	move.l	D6,D0
	RESTORE_REGS	D1-A6
	rts

DetectDebugger:
	bsr	get_system_vbr
	
	MOVE.L	D0,A0
	move.l	($7C,A0),A0	; NMI interrupt
	move.l	A0,D0

	CMP.L	#"HRT!",-4(A0)
	BNE.S	.nohrt

	MOVE.L	-8(A0),A0
	CMP.L	#"HRT!",4(A0)
	BNE.S	.nohrt	
	
	move.l	D0,debugger_nmi	; HRT entrypoint is here, not in global struct
							; because we need to access it without any registers set
	
	; locate resload + CDBUFFER below HRT
	; (HRT locates itself automatically around $1C0000 which leaves plenty of room to install resload
	; unless it is an AGA game or RN loader is used with diskfiles)
	
	SETVAR_L	A0,resload_top
.nohrt	
	rts
	
AllocInfoBlock:
	STORE_REGS	D1/D2/A0/A1/A6
	move.l	#DOS_FIB,D1
	moveq.l	#0,D2
	move.l	_DosBase,A6
	JSRLIB	AllocDosObject
	tst.l	D0
	beq	.error
	RESTORE_REGS	D1/D2/A0/A1/A6
	rts

.error:
	PRINT_MSG	error_prefix
	PRINTLN	"Cannot allocate infoblock"
	bra	CloseAll


FreeInfoBlock
	STORE_REGS
	tst.l	D0
	beq.b	.exit	; safety
	move.l	D0,D2
	move.l	#DOS_FIB,D1
	move.l	_DosBase,A6
	JSRLIB	FreeDosObject
.exit
	RESTORE_REGS
	rts


examine:
	STORE_REGS	D1-A6
	move.l	_DosBase,A6
	JSRLIB	Examine
	RESTORE_REGS	D1-A6
	rts
	

; *** open window/get console output handle

OpenOutput:
	STORE_REGS
	tst.l	ConHandle
	bne.b	.go			; already open

	move.l	_DosBase(pc),a6
	JSRLIB	Output
	move.l	D0,ConHandle
	bne	.go		; Output? Ok.

	move.l	_DosBase(pc),A6
	lea	ConName(pc),A0
	tst.b	(A0)		; Maybe we don't want to open a console
	beq	.nowin
	move.l	a0,D1
	move.l	#MODE_NEWFILE,D2
	JSRLIB	Open
.exit
	move.l	D0,ConHandle
.go
	RESTORE_REGS
	rts

.nowin
	moveq.l	#0,D0
	bra	.exit

ComputeAttnFlags:
	STORE_REGS
	move.l	_SysBase,A6
	moveq.l	#0,D0
	move.b	AttnFlags+1(A6),D0
	btst	#AFB_68040,D0
	beq.b	.noclr6888x

	; remove 6888x coprocessors declaration if 68040+ is set

	bclr	#AFB_68881,D0
	bclr	#AFB_68882,D0
.noclr6888x
	SET_VAR_CONTEXT
	SETVAR_L	D0,attnflags	; save attnflags in fastmem
	RESTORE_REGS
	rts
	

MakeRawTable:
	STORE_REGS
	SET_VAR_CONTEXT
	move.l	_SysBase,A6
	moveq	#0,D0
	lea	.kbname(pc),A1
	JSRLIB	OpenLibrary
	tst.l	D0
	beq	.exit
	move.l	D0,A6

	JSRLIB	AskKeyMapDefault
	move.l	D0,A2

	LEAVAR	raw_ascii_table,A5

	; create a fake event

	lea	(-22,A7),A7
	move.l	A7,A3
	
	moveq.l	#10,D0
.clrloop
	clr.w	(A3)+
	dbf	D0,.clrloop

	move.l	A7,A3

	move.b	#IECLASS_RAWKEY,(ie_Class,A3)

	clr.w	(ie_Qualifier,A3)
	bsr	.convloop

	move.w	#IEQUALIFIER_LSHIFT,(ie_Qualifier,A3)
	bsr	.convloop

	move.w	#IEQUALIFIER_LALT,(ie_Qualifier,A3)
	bsr	.convloop

	move.w	#IEQUALIFIER_CONTROL,(ie_Qualifier,A3)
	bsr	.convloop

	lea	(22,A7),A7

	; close library

	move.l	A6,A1
	move.l	_SysBase,A6
	JSRLIB	CloseLibrary
	
.exit
	RESTORE_REGS
	RTS

; <A3: event
; <A5: buffer
; <A2: keymap

.convloop:
	moveq.l	#0,D2
	lea	-4(A7),A7
.loop
	move.l	A7,A1
	moveq.l	#4,D1
	move.l	A3,A0
	move.w	D2,(ie_Code,A0)
	JSRLIB	MapRawKey

	cmp.l	#1,D0
	beq.b	.onechar
	clr.l	(A7)
.onechar
	move.b	(A7),(A5)+	; only first char
	addq.l	#1,D2
	cmp.w	#$80,D2
	bne.b	.loop

	lea	4(A7),A7
	rts

.kbname:
	dc.b	"keymap.library",0
	even

	
		IFEQ	1
CheckHardwareReqs:
	btst	#WHDLB_NoError,D0
	beq.b	.nonfatal

	move.l	D0,-(A7)		; fixed a long time bug in whdload emulation in 2015 :)
	moveq.l	#-1,D0
	JSRGEN	SetRTFileError
	move.l	(A7)+,D0
.nonfatal
	SET_VAR_CONTEXT
	TSTVAR_L	forcewhd_flag		; ignore all checks for badly written slaves
	bne	.noagachk
	

.no020chk

	btst	#WHDLB_ReqAGA,D0
	beq	.noagachk
	
	bsr	CheckAGA
	tst.l	D0
	bne	WHDAgaError
.noagachk
	rts



	ENDC
	

; < A1: message to display (null terminated)
Display:
	STORE_REGS
	clr.l	d3

.aff_count:
	tst.b	(A1,D3)		
	beq.b	.aff_ok
	addq	#1,D3
	bra.b	.aff_count
.aff_ok
	move.l	A1,D2
	move.l	ConHandle(PC),D1
	beq	.1		; If no console, write nothing
	move.l	_DosBase(pc),a6
	JSRLIB	Write
.1
	RESTORE_REGS
	rts

linefeed:
	dc.b	10,13,0
error_prefix:
	dc.b	"** Error: ",0
	
readargs_error:
	dc.b	"ReadArgs error",0
version:
	dc.b	"$VER "
help:
	dc.b	"CD32LOAD version ",MAJOR_VERSION+'0',"."
	dc.b	MINOR_VERSION+'0',SUBMINOR_VERSION+'0',10,13,0
	
ConName:
	dc.b	"CON:20/20/350/200/CD32Load - JOTD 2016-2018/CLOSE",0
TaskName:
	dc.b	"CD32Load",0
dosname:
	dc.b	"dos.library",0
lowname:
	dc.b	"lowlevel.library",0
gfxname:
	dc.b	"graphics.library",0
cdx_name:
	dc.b	"CD0:",0
	even
slave_name:
	blk.b	255,0
data_str:
	blk.b	255,0
cd_slave_name:
	blk.b	255,0
nullname:
	dc.b	0
	blk.b	$4,0	; to hack the paths devname => CD0
current_dir
	blk.b	$100,0
	even


ProgArgs:
	blk.l	120,0
ProgArgsEnd:

TaskArgsPtr:
	dc.l	0
TaskArgsLength:
	dc.l	0
TaskPointer:
	dc.l	0
TaskLower:
	dc.l	0
OriginalStack:
	dc.l	0
ConHandle:
	dc.l	0

	
allocated_filecache:
	dc.l	0
allocated_filesize:
	dc.l	0
RtnMess:
	dc.l	0

rdargs_struct:
	dc.l	0

diskunit_number:
	dc.l	0
idehd_flag:
	dc.l	0
_SysBase:
	dc.l	0
_DosBase:
	dc.l	0
_GfxBase:
	dc.l	0
_LowlevelBase:
	dc.l	0
max_cdbuffer_address:
	dc.l	0
; offset of the buffer for the aux CD slave
cd_slave_offset:
	dc.l	0
cd_slave_size:
	dc.l	0
slave_start:
	dc.l	0
whd_slave_size:
	dc.l	0
swapjoy:
	dc.l	0
force_expmem:
	dc.l	0
force_chipmem:
	dc.l	0
fast_reloc_end
	dc.l	0
timeout_in_seconds:
	dc.l	0
pretend_flag
	dc.l	0
reloc_len:
	dc.l	0
resload_len:
	dc.l	0
loader_len
	dc.l	0
loader_start
	dc.l	0
dumpakiko_flag
	dc.l	0
force_flag:
	dc.l	0

force_optional_memory_flag
	dc.l	0
	cnop	0,4
infobuffer:
	blk.b	id_SIZEOF,0

kickstart_filename:
	dc.b	"DEVS:Kickstarts/Kick"
kickstart_suffix:
	blk.b	24,0
tmpstring2:
	blk.b	200,0
unhacked_data_directory:
	blk.b	200,0
preload_file:
	blk.b	32,0
vbl_handler_code_file:
	blk.b	108,0
cdio_asked_buf_str:
	blk.b	20,0
explicit_joypad_option:
	dc.b	0
	even
; labels
	
	include util.asm
