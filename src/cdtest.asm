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
	include "lvo/graphics.i"


	XDEF	EntryPoint

CDIO_BUFFER	= $1D0000
CDIO_SIZE = $12000

; keymap.library
_LVOSetKeyMapDefault   equ     -30     ; Functions in V36 or higher (2.0)
_LVOAskKeyMapDefault   equ     -36
_LVOMapRawKey          equ     -42
_LVOMapANSI            equ     -48


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
	move.l	_SysBase,A6
	move.l	cdio_buf,D0
	beq.b	.nof
	move.l	D0,A1
	move.l	#CDIO_SIZE,D0
	JSRLIB	FreeMem
.nof
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
		PRINT_MSG	error_prefix
		PRINT	"Cannot allocate $"
		PRINTH	block_size
		PRINTLN	" bytes for slave"
		bra.b	CloseAll

ReadArgsErr:
		PRINT_ERROR_MSG	readargs_error
		bra.b	CloseAll
		
CloseAll:
	move.l	OriginalStack,A7
	bra	exit

	
ReadArgsString:
	dc.b	"FILENAME/A,DESTINATION/K,CDBUFFER/K,COMMAND/K/N,IDEHD/S,PRETEND/S"
	dc.b	0
	even
	
start:
	tst.l	RtnMess
	bne	.wbunsup
	

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
	move.l	#input_filename,D1
	bsr	StrcpyAsm
	move.l	D1,D0
	bsr	ToUpperAsm
.skn

	move.l	(A0)+,D0
	beq.b	.skd
	LEA	destination_str(pc),A1
	move.l	A1,D1
	bsr	StrcpyAsm
	move.l	A1,D0
	bsr	ToUpperAsm
.skd
	move.l	(A0)+,D0
	beq.b	.skb
	LEA	cdio_asked_buf_str(pc),A1
	move.l	A1,D1
	bsr	StrcpyAsm
	move.l	A1,D0
	bsr	ToUpperAsm
.skb



	lea	ProgArgs,A0
	add.l	#12,A0			; name/userdata were filled
					; by either args or tooltypes
	; *** users flags
	
	move.l	(A0)+,D0
	beq.b	.skc1
	move.l	D0,A1
	move.l	(a1),command
.skc1

	move.l	(A0)+,idehd_flag
	move.l	(A0)+,pretend_flag
	
	lea	destination_str(pc),a1
	bsr	HexStringToNum
	move.l	d0,destination
	
	lea	cdio_asked_buf_str(pc),a1
	bsr	HexStringToNum
	add.l	#$FFFF,D0
	and.l	#$FFFF0000,D0
	move.l	d0,cdio_asked_buf
	
	tst.l	command
	bpl.b	.cok
	PRINTLN	"Command not set"
	bra	CloseAll
.cok
	; get slave size
	move.l	#input_filename,D0
	bsr	GetFileLength
	move.l	d0,filesize
;	tst.l	D0
;	bmi	.noslave
	
	; display parameters
	PRINT	"file/dir: "
	PRINT_MSG	input_filename
	PRINT " "
	PRINTH	filesize
	PRINT " bytes"
	PRINTLN
	PRINT	"Dest address: "
	PRINTH	destination
	PRINTLN
	PRINT	"CD buffer: "
	PRINTH	cdio_asked_buf
	PRINTLN
	PRINT	"From HD: "
	PRINTH	idehd_flag
	PRINTLN

	PRINT	"Command (legal: 0->11): "
	
	PRINTH	command
	PRINTLN

	move.l	_SysBase,A6
	move.l	#CDIO_SIZE,D0
	move.l	cdio_asked_buf,A1
	JSRLIB	AllocAbs
	move.l	d0,cdio_buf
	bne.b	.allocok
	PRINTLN	"Cannot allocate cd buffers"
	bra	CloseAll
	
.allocok
	tst.l	pretend_flag
	bne		CloseAll
	
	; analyze slave maxchip, exit if > $100000
	; expmem+maxchip cannot be > $100000
	
	; delay before shutting OS
	move.l	_DosBase,A6
	move.l	#50,D1
	JSRLIB	Delay
	

	
	moveq.l	#1,D7
	moveq.l	#4,d0
	lea	cd0(pc),a0
	tst.l	idehd_flag
	beq.b	.c
	lea	dh0(pc),a0	; hard drive mode
.c
	move.l	cdio_buf(pc),A2
	
	movem.l	D2-A6,-(A7)
	bsr	cd_operation_routine	; call raw routine (cdio has a retry system)
	movem.l	(A7)+,D2-A6
	
	move.l	D0,D2
	beq.b	.cdok
	PRINT	"Cannot CD to "
	PRINT_MSG	cd0
	bra	.cdout
.cdok
	PRINT	"attempt #"
	PRINTH	D7
	PRINTLN
	
	move.l	_SysBase,A6
	JSRLIB	Disable
	
	move.l	command(pc),d0
	lea	input_filename(pc),a0
	move.l	destination(pc),a1
	move.l	cdio_buf(pc),A2
	
	move.l	#$1000,D1	; just in case some commands needs it
	move.l	D1,D3	; just in case some commands needs it
	
	movem.l	D2-A6,-(A7)
	bsr	cd_operation_routine	; call raw routine (cdio has a retry system)
	movem.l	(A7)+,D2-A6

	move.l	D0,D2
	move.l	D1,D3
	
	move.l	_SysBase,A6
	JSRLIB	Enable
	
	PRINT	"RETCODE: "
	tst.l	D2
	bpl.b	.pos
	PRINT	"-"
	neg.l	D2
.pos
	PRINTH	D2
	PRINTLN
	
	tst.l	D2
	bne.b	.skd1

	PRINT	"D1: "
	tst.l	D3
	bpl.b	.pos2
	PRINT	"-"
	neg.l	D3
.pos2
	PRINTH	D3
	PRINTLN
.skd1
	
	tst.l	D2
	beq.b	.cdout
	addq.b	#1,D7
	cmp.b	#4,D7
	bne		.cdok



.cdout


	bra	CloseAll
	
.wbunsup:
	bra	CloseAll
	
.noslave
	PRINT_MSG	error_prefix
	PRINT		"Cannot lock "
	PRINT_MSG	input_filename
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
.
	move.l	D7,D0
	bsr	FreeInfoBlock
.end
	move.l	D6,D0
	RESTORE_REGS	D1-A6
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
	
ConName:
	dc.b	"CON:20/20/350/200/CD32Load - JOTD 2016/CLOSE",0
TaskName:
	dc.b	"CDTEST",0
dosname:
	dc.b	"dos.library",0
gfxname:
	dc.b	"graphics.library",0
cd0:
	dc.b	"CD0:",0
dh0:
	dc.b	"DH0:",0
input_filename:
	blk.b	255,0
destination_str:
	blk.b	20,0
cdio_asked_buf_str:
	blk.b	20,0

	even


ProgArgs:
	blk.l	50,0
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

block_size
	dc.l	0
RtnMess:
	dc.l	0	

destination:
	dc.l	0
	
rdargs_struct:
	dc.l	0

filesize:
	dc.l	0
	
_SysBase:
	dc.l	0
_DosBase:
	dc.l	0
_GfxBase:
	dc.l	0

command:
	dc.l	-1
idehd_flag:
	dc.l	0
pretend_flag
	dc.l	0
cdio_asked_buf
	dc.l	0
cdio_buf
	dc.l	0
; labels
	
	include util.asm
CDTEST=1
	include cdio.asm
SHOW_DEBUGSCREEN_1:
	bra	SHOW_DEBUGSCREEN
	include DebugScreen.s