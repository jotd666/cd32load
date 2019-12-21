	incdir	include:
	include whdload.i
	include whdmacros.i
	include macros.i
	include struct.i
	include	cd32loader.i	; Psygore CD32 loader
	
	include hardware/custom.i
	include dos/dos.i
	
	XDEF	reloc_start
	XDEF	reloc_end
	XDEF	whd_bootstrap
	XDEF	debugger_nmi		; for direct access

SET_VAR_CONTEXT:MACRO
	lea	reloc_start(pc),a4
	ENDM
	
reloc_start:
	blk.b	RelVar_SIZEOF,0
	cnop	0,4
	


	include util.asm
	include cdio.asm

SHOW_DEBUGSCREEN_1:
	bra	SHOW_DEBUGSCREEN_2
	include	ReadJoypad.s
	include whd.asm
SHOW_DEBUGSCREEN_2:
	bsr	SHOW_DEBUGSCREEN
	SET_VAR_CONTEXT_2
	move.l	debugger_nmi(pc),d0
	beq.b	.nodebug
.debug
	; display RSOD then enter the debugger, then repeat
	move.l	#$F000,D0
	bsr	BeamDelay
	move.l	#$F000,D0
	bsr	BeamDelay
	bsr	EnterDebugger
	bra.b	.debug
	
.nodebug
	TSTVAR_L	autoreboot_flag
	beq.b	.il		; no timeout: RSOD stays forever
	; timeout set: we may want to wait a while, then reboot
	move.l	#$F000,D0
	bsr	BeamDelay
	move.l	#$F000,D0
	bsr	BeamDelay
	bra	_reset
.il
	bra	.il
	include	send_key_event.asm
	include virtual_keyboard.asm
	include virtual_mouse.asm	
	include	hunk.asm
	include DebugScreen.s

	dc.b	"CD32LOAD"
reloc_end:
