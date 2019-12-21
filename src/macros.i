	incdir	include:
	
	
WAIT_LMB:MACRO
.w\@
	btst	#6,$BFE001
	bne.b	.w\@
	ENDM
	
STORE_REGS: MACRO
	IFLE	NARG
	movem.l	D0-D7/A0-A6,-(A7)
	ELSE
	movem.l	\1,-(A7)
	ENDC
	ENDM

RESTORE_REGS: MACRO
	IFLE	NARG
	movem.l	(A7)+,D0-D7/A0-A6
	ELSE
	movem.l	(A7)+,\1
	ENDC
	ENDM

JSRLIB:MACRO
	jsr	_LVO\1(A6)
	ENDM


RELOC_MOVEL:MACRO
	IFNE	NARG-2
		FAIL	arguments "RELOC_MOVEL"
	ENDC

	movem.l	D0/A6,-(sp)
	lea	\2(pc),A6
	move.l	\1,(A6)
	movem.l	(sp)+,D0/A6	; movem preserves flags
	ENDM

RELOC_MOVEW:MACRO
	IFNE	NARG-2
		FAIL	arguments "RELOC_MOVEW"
	ENDC

	movem.l	A6/D0,-(sp)
	lea	\2(pc),A6
	move.w	\1,(A6)
	movem.l	(sp)+,D0/A6
	ENDM

RELOC_MOVEB:MACRO
	IFNE	NARG-2
		FAIL	arguments "RELOC_MOVEB"
	ENDC

	movem.l	A6/D0,-(sp)
	lea	\2(pc),A6
	move.b	\1,(A6)
	movem.l	(sp)+,D0/A6
	ENDM


PRINT: MACRO
	move.l	A1,-(A7)
	lea	.text\@(PC),A1
	bsr	Display

	bra.b	.ftext\@
.text\@
	dc.b	\1,0
	even

.ftext\@
	move.l	(A7)+,A1
	ENDM

PRINTLN: MACRO
	IFGT	NARG
	PRINT	\1
	ENDC
	PRINT_MSG	linefeed
	ENDM

PRINTH:MACRO
	movem.l	D0/A1,-(A7)
	move.l	\1,D0
	lea	.text\@(PC),A1
	bsr	HexToString
	bsr	Display
	bra.b	.ftext\@

.text\@
	dc.b	"$00000000",0
	even
.ftext\@
	movem.l	(A7)+,D0/A1
	ENDM
	
PRINT_MSG:MACRO
	STORE_REGS	A1
	lea	\1(pc),A1
	bsr	Display
	RESTORE_REGS	A1
	ENDM

PRINT_ERROR_MSG:MACRO
	PRINT_MSG	error_prefix
	PRINT_MSG	\1
	PRINT_MSG	linefeed
	ENDM