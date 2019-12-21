
; *** CIA-A/B code (store/restore)

; *** timer storage offsets

TimerAA = $0
TimerAB = $5
TimerBA = $A
TimerBB = $F

CR = 0
THI = 1
TLO = 2
LHI = 3
LLO = 4


; *** Save CIA registers

SaveCIARegs
	STORE_REGS	D0/A1/A4
	SET_VAR_CONTEXT
	LEAVAR	sys_ciaregs,A1
	bsr	GetCiaRegs
	bsr	.getled
	RESTORE_REGS	D0/A1/A4
	rts


.getled:
	move.b	$BFE001,D0	; CIAPRA
	lsr.b	#1,D0
	and.w	#1,D0		; changed from .b to .w, could store trash in MSB!!
	SETVAR_W	D0,ledstate		; store LED value

	; if filter off is set, then removes audio filter

	TSTVAR_L	filteroff_flag
	beq.b	.noforceoff
	bset.b	#1,$BFE001
.noforceoff
	rts
; *** Restore CIA registers

RestoreCIARegs
	STORE_REGS	D0/A1/A4
	SET_VAR_CONTEXT
	LEAVAR	sys_ciaregs,A1
	bsr	SetCiaRegs
	bsr	ResetCIAs
	RESTORE_REGS	A1/D0/A4
	rts


SetLed:
	STORE_REGS	A4

	; ** reset LED/Filter
	
	SET_VAR_CONTEXT

	TSTVAR_W	ledstate
	bne.b	1$
	bclr.b	#1,$BFE001
	bra.b	2$
1$
	bset.b	#1,$BFE001
2$
	RESTORE_REGS	A4
	rts

; *** Save CIA registers in a buffer
; in: A1: buffer

GetCiaRegs:
	STORE_REGS
	LEA	$BFE001,A2
	lea	$BFD000,a4

	move.l	A1,A5		; buffer for timers, base

	lea	$1E01(a4),a0
	lea	$1401(a4),a1
	lea	$1501(a4),a2
	lea	TimerAA(A5),A3	; offset
	bsr	GetTimer

	lea	$1F01(a4),a0
	lea	$1601(a4),a1
	lea     $1701(a4),a2
	lea	TimerAB(A5),A3	; offset
	bsr	GetTimer

	lea	$E00(a4),a0
	lea	$400(a4),a1
	lea	$500(a4),a2
	lea	TimerBA(A5),A3	; offset
	bsr	GetTimer

	lea	$F00(a4),a0
	lea	$600(a4),a1
	lea	$700(a4),a2
	lea	TimerBB(A5),A3	; offset
	bsr	GetTimer

	clr.b	$1E01(a4)
	clr.b	$1F01(a4)
	clr.b	$E00(a4)
	clr.b	$F00(a4)

	RESTORE_REGS
	rts

; *** Restore CIA regs from a buffer
; in: A1: buffer

SetCiaRegs:
	STORE_REGS
	lea     $BFD000,a4
	move.l	A1,A5		; timer base

	lea     $1E01(a4),a0
	lea     $1401(a4),a1
	lea     $1501(a4),a2
	lea     TimerAA(A5),a3
	bsr	SetTimer

	lea     $1F01(a4),a0
	lea     $1601(a4),a1
	lea     $1701(a4),a2
	lea     TimerAB(A5),a3
	bsr   SetTimer

	lea     $E00(a4),a0
	lea     $400(a4),a1
	lea     $500(a4),a2
	lea	TimerBA(A5),a3
	bsr   SetTimer

	lea     $F00(a4),a0
	lea     $600(a4),a1
	lea     $700(a4),a2
	lea	TimerBB(A5),a3
	bsr   SetTimer
	RESTORE_REGS
	rts

; originally those were NOPs, but I figured out this is an active delay
; so it's better to rely on a slow CIA read than a nop

CIADELAY:MACRO
	tst.b	$bfe001
	ENDM
	
; *** get timer values
; *** thanks to Alain Malek for the source code

GetTimer:
	move.b  (a0),CR(a3)             ;store state of control register
	bclr    #0,(a0)                 ;stop the timer
	CIADELAY
	move.b  (a1),TLO(a3)            ;store the actual timer values
	move.b  (a2),THI(a3)
	bclr    #3,(a0)                 ;set continuous mode
	CIADELAY
	bclr    #1,(a0)                 ;clear PB operation mode
	CIADELAY
	bset    #4,(a0)                 ;force load latch->timer
	CIADELAY
	move.b  (a1),LLO(a3)            ;store latch values
	move.b  (a2),LHI(a3)
	;;;bsr	SetTimer ; ?? WTF thx Toni!!!
	rts

; *** set timer values
; *** thanks to Alain Malek for the source code

SetTimer:
	clr.b   CR(a0)                  ;clear all CR values
	CIADELAY
	move.b  TLO(a3),(a1)            ;set latch to original timer value
	move.b  THI(a3),(a2)
	CIADELAY
	bset    #4,(a0)                 ;move latch->timer
	CIADELAY
	move.b  LLO(a3),(a1)            ;set latch to original latch value
	move.b  LHI(a3),(a2)
	CIADELAY
	move.b  CR(a3),(a0)             ;restore the timer's work
	rts




