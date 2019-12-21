; CD32Load debug screen
; stingray, 05-jan-2016
; for JOTD CD32Load project
;
; how to use:
;  - call SHOW_DEBUGSCREEN with the error code in d0.w, the texts
;    for each error code are defined in "ERRORTAB"
;
; or:
;
; - call SHOW_DEBUGSCREEN with your custom error text in a0 (d0=0), error
;   codes are then ignored and just your text will be written on screen
;
; To test the output, set "TEST" below to 1, a very basic startup-code
; (NOT suitable for general use, a few hacks have been used to keep size
; small) will then be executed.  Hardware state will be saved,
; then the debug screen is shown, once left mouse has been pressed the
; hardware state will be restored and the code returns to the OS.
;
; limitations:
; - hex dump will only be performed for registers in the chip
;  memory area, MAXCHIP specifies the upper bound
; - quick hack which does its job, not exactly clean or optimised code

TEST	= 0			; 1: save system/show debug screen/return to OS
				; 0: just show debug screen, NO return to OS!
MAXCHIP	= $200000		; end of chip memory (for hex dump)


	IFEQ	TEST

	moveq	#10,d0		; error code
	bsr	SHOW_DEBUGSCREEN

.deadend	
	bra.b	.deadend

	ELSE	

	;SECTION	CODE,CODE_c

	lea	.VARS(pc),a5
	move.l	$4.w,a6
	move.l	$9c(a6),a6			; GfxBase
	move.l	34(a6),.OldView(a5)
	sub.l	a1,a1
	bsr.w	.DoView
	move.l	$26(a6),.OldCop1(a5)		; Store old CL 1

	lea	$dff000,a6			; base address
	move.w	$10(a6),.ADK(a5)		; Store old ADKCON
	move.w	$1C(a6),.INTENA(a5)		; Store old INTENA
	move.w	$02(a6),.DMA(a5)		; Store old DMA
	move.w	#$7FFF,d0
	bsr	WaitRaster
	move.w	d0,$9A(a6)			; Disable Interrupts
	move.w	d0,$96(a6)			; Clear all DMA channels
	move.w	d0,$9C(a6)			; Clear all INT requests

	; save memory that is used for the screen
	lea	BUF,a0
	lea	$60000,a1
	move.w	#80*256/4-1,d7
.save	move.l	(a1)+,(a0)+
	dbf	d7,.save

	moveq	#21,d0			; error code
	;moveq	#0,d0
	lea	.test(pc),a0
	bsr	SHOW_DEBUGSCREEN
	bra.b	.LMB
.test	dc.b	"test text",0
	CNOP	0,4

.LMB	btst	#6,$bfe001
	bne.b	.LMB

	; restore memory that is used for the screen
	lea	$60000,a0
	lea	BUF,a1
	move.w	#80*256/4-1,d7
.restore
	move.l	(a1)+,(a0)+
	dbf	d7,.restore


	lea	.VARS(pc),a5
	lea	$dff000,a6

	move.w	#$8000,d0
	or.w	d0,.INTENA(a5)			; SET/CLR-Bit to 1
	or.w	d0,.DMA(a5)			; SET/CLR-Bit to 1
	or.w	d0,.ADK(a5)			; SET/CLR-Bit to 1
	subq.w	#1,d0
	bsr	WaitRaster
	move.w	d0,$9A(a6)			; Clear all INT bits
	move.w	d0,$96(a6)			; Clear all DMA channels
	move.w	d0,$9C(a6)			; Clear all INT requests

	move.l	.OldCop1(a5),$80(a6)		; Restore old CL 1
	move.w	d0,$88(a6)			; start copper1
	move.w	.INTENA(a5),$9A(a6)		; Restore INTENA
	move.w	.DMA(a5),$96(a6)		; Restore DMAcon
	move.w	.ADK(a5),$9E(a6)		; Restore ADKcon

	move.l	$4.w,a6
	move.l	$9c(a6),a6			; GfxBase
	move.l	.OldView(a5),a1			; restore old viewport

.DoView	jsr	-222(a6)			; LoadView()
	jsr	-270(a6)			; WaitTOF()
	jmp	-270(a6)




.VARS		RSRESET
.OldCop1	rs.l	1
.OldView	rs.l	1
.ADK		rs.w	1
.INTENA		rs.w	1
.DMA		rs.w	1
.SIZEOF		rs.b	0
		ds.b	.SIZEOF	


BUF	ds.b	80*256

	ENDC


SCREEN	= $60000

; in the stack:
; message pointer
; PC where error occured (the caller can hack it so it will display the proper PC)
; slave basename
; return PC (ignored)

SHOW_DEBUGSCREEN
	movem.l	A0,-(A7)
	lea	REGS(pc),A0
	movem.l	d0-a7,(A0)
	movem.l	(A7)+,A0
	lea	REGS(pc),A1
	move.l	A0,32(A1)
	sub.l	#12,60(A1)	; correct stack
	move.l	60(A1),A6
	move.l	8(A7),64(A1)	; program counter
	lea	$dff000,a6
	move.w	#$7FFF,d2
	move.w	d2,$9A(a6)		; Disable Interrupts
	move.w	d2,$96(a6)		; Clear all DMA channels
	move.w	d2,$9C(a6)		; Clear all INT requests


; clear screen
	lea	SCREEN,a1	; absolute address (no PC!!)
	move.w	#80*256/4-1,d1
	moveq	#0,d2
.cls	move.l	d2,(a1)+
	dbf	d1,.cls

	move.l	4(A7),A0	; pushed in the stack as a parameter
	bsr.b	.MakeDebugText
	

	lea	cop(pc),a0
	; we're going to copy copperlist data in chipmem;
	; just in case this program is located in fastmem (terrible fire + failing to use chipmem by my end :))
	lea	SCREEN-$100,a1
	move.l	#end_cop-cop,d0
	subq.l	#1,d0
.copycop
	move.b	(a0)+,(a1)+
	dbf		d0,.copycop

	lea	SCREEN-$100,a1
	move.l	a1,$80(a6)
	move.w	#0,$88(a6)
	move.w	#$8380,$96(a6)		; enabled copper+bitplane DMA
	rts





.MakeDebugText

	lea	TXTPTR(pc),A1
	move.l	A0,(A1)


; convert registers to Ascii
	lea	REGS(pc),a0
	lea	REGS_ASCII(pc),a1
	moveq	#16-1,d7
.loop	move.l	(a0)+,d0
	bsr	Convert
	dbf	d7,.loop


; write data registers
	lea	REGS_ASCII(pc),a1
	moveq	#3,d0			; x-position on screen
	bsr	WriteRegs		; write data registers
	moveq	#15,d0			; x-position on screen
	bsr	WriteRegs		; write address registers

; write PC
	move.l	REGS+64(pc),D0
	lea	ERRCODE_PC(pc),A1
	bsr	Convert
	
; write header text
	lea	DEBUG_TEXT(pc),a0
	lea	SCREEN,a1
	bsr	PRINTTEXT

; write error code text
	lea	ERRCODE_TEXT(pc),a0
	lea	SCREEN+80*(10*3),a1
	bsr	PRINTTEXT
.noerrcode
	
; write actual error text
	move.l	TXTPTR(pc),a0
	lea	SCREEN+80*(10*3),a1
	;tst.w	d6
	;beq.b	.no_offset
	add.w	#13,a1
.no_offset
	bsr	PRINTTEXT

	lea	REGS_TEXT(pc),a0
	lea	SCREEN+80*(10*6),a1
	bsr	PRINTTEXT
	


; write hex dump for address registers
	lea	REGS_TEXT(pc),a0
	moveq	#57-1,d7
	moveq	#" ",d0
.clear	move.b	d0,(a0)+
	dbf	d7,.clear

	clr.b	(a0)
	moveq	#'"',d0
	move.b	d0,-2(a0)
	move.b	d0,-19(a0)		

	lea	SCREEN,a4
	lea	6*10*80+23(a4),a4
	lea	REGS+8*4(pc),a5		; start with register a0
	moveq	#8-1,d5
.loop2	lea	REGS_TEXT(pc),a1
	lea	40-1(a1),a2
	move.b	#" ",(a1)+
	move.b	#">",(a1)+

	move.l	(a5)+,a3		; get address register

	cmp.l	#MAXCHIP,a3		; valid address?
	bcs.b	.isvalid
	lea	.invalid(pc),a3		; nope!
.isvalid
	
	moveq	#4-1,d7
.conv	move.b	(a3)+,d0
	rol.l	#8,d0
	move.b	(a3)+,d0
	rol.l	#8,d0
	move.b	(a3)+,d0
	rol.l	#8,d0
	move.b	(a3)+,d0


	move.l	d0,d3
	bsr	Convert
	addq.w	#1,a1

	move.l	d3,d0
	rol.w	#8,d0
	swap	d0
	rol.w	#8,d0
	moveq	#4-1,d6
	
.conv2	moveq	#".",d1
	cmp.b	#" ",d0
	blt.b	.illegal
	cmp.b	#$7e,d0
	bgt.b	.illegal
	move.b	d0,d1
.illegal
	move.b	d1,(a2)+

	
	ror.l	#8,d0
	dbf	d6,.conv2
	dbf	d7,.conv


.print	lea	REGS_TEXT(pc),a0
	move.l	a4,a1
	bsr.b	PRINTTEXT
	lea	80*10(a4),a4
	dbf	d5,.loop2
	rts

.invalid
	ds.b	4*4

WriteRegs
	lea	REGS_TEXT(pc),a0
	moveq	#8-1,d7
.loop	move.b	(a1)+,(a0,d0.w)
	move.b	(a1)+,1(a0,d0.w)
	move.b	(a1)+,2(a0,d0.w)
	move.b	(a1)+,3(a0,d0.w)

	move.b	(a1)+,4(a0,d0.w)
	move.b	(a1)+,5(a0,d0.w)
	move.b	(a1)+,6(a0,d0.w)
	move.b	(a1)+,7(a0,d0.w)
	lea	24(a0),a0
	dbf	d7,.loop

	rts


; d0.l: hex value
; a1.l: destination

Convert	moveq	#8-1,d1
.loop	rol.l	#4,d0
	move.b	d0,d2
	and.b	#$f,d2
	add.b	#"0",d2
	cmp.b	#"9",d2
	ble.b	.ok
	addq.b	#"A"-("9"+1),d2
.ok	move.b	d2,(a1)+
	dbf	d1,.loop
	rts
	
; a0: Text
; a1: Screen

PRINTTEXT
	movem.l	d0-a6,-(a7)
	moveq	#0,d0			; x pos
	moveq	#0,d1			; x pos
.write	moveq	#0,d2
	move.b	(a0)+,d2
	beq.b	.end
	cmp.b	#10,d2			; new line?
	bne.b	.nonew
	moveq	#0,d0
	add.w	#80*10,d1
	add.w	d1,d0
	bra.b	.write
.nonew	sub.w	#" ",d2
	lsl.w	#3,d2
	lea	FONT(pc),a2
	add.w	d2,a2
	lea	(a1,d0.w),a3

	moveq	#8-1,d7
.char	move.b	(a2)+,(a3)
	lea	80(a3),a3
	dbf	d7,.char
	addq.w	#1,d0
	bra.b	.write
.end	movem.l	(a7)+,d0-a6
	rts


WaitRaster
	move.l	d0,-(a7)
.loop	move.l	$dff004,d0		; wait for Beam pos $xxx
	and.l	#$1ff00,d0
	cmp.l	#303<<8,d0
	bne.b	.loop
	move.l	(a7)+,d0
	rts

		CNOP	0,4
TXTPTR		dc.l	0
REGS		dcb.l	17
REGS_ASCII	ds.b	16*8
DEBUG_TEXT	dc.b	"                         CD32Load Debug screen",10,10
		dc.b	"Sorry, an error occured",0
ERRCODE_TEXT	dc.b	"PC="
ERRCODE_PC      dc.b	"xxxxxxxx: ",0

REGS_TEXT
		dc.b	"D0=xxxxxxxx A0=xxxxxxxx",10
		dc.b	"D1=xxxxxxxx A1=xxxxxxxx",10
		dc.b	"D2=xxxxxxxx A2=xxxxxxxx",10
		dc.b	"D3=xxxxxxxx A3=xxxxxxxx",10
		dc.b	"D4=xxxxxxxx A4=xxxxxxxx",10
		dc.b	"D5=xxxxxxxx A5=xxxxxxxx",10
		dc.b	"D6=xxxxxxxx A6=xxxxxxxx",10
		dc.b	"D7=xxxxxxxx A7=xxxxxxxx",10,10

		dc.b	"I'm afraid this is the end. Have you tried to turn it off and on again ?",10
		dc.b	10,"Last: "
LAST_IO_CALL
		ds.b	256,0









		CNOP	0,2

	

FONT		;INCBIN	SOURCES:FONTS/FONT8/PAT.fnt
	DC.L	$00000000,$00000000,$18181818,$18001800
	DC.L	$6C6C6C00,$00000000,$006CFE6C,$6CFE6C00
	DC.L	$183C6630,$0C663C18,$00C6CC18,$3066C600
	DC.L	$00386C38,$6E6C3A00,$30303000,$00000000
	DC.L	$1C303030,$30301C00,$380C0C0C,$0C0C3800
	DC.L	$007CFEFE,$FE7C0000,$00001818,$7E181800
	DC.L	$00000000,$00183060,$00000000,$7E000000
	DC.L	$00000000,$00181800,$00060C18,$3060C000
	DC.L	$7CC6C6E6,$F6F67C00,$0C0C0C1C,$3C3C3C00
	DC.L	$7C06067C,$E0E0FE00,$7C06061C,$0E0EFC00
	DC.L	$C6C6C67E,$0E0E0E00,$FEC0FC0E,$0E0EFC00
	DC.L	$7CC0FCCE,$CECE7C00,$FE060C18,$38383800
	DC.L	$7CC6C67C,$E6E67C00,$7CC6C67E,$0E0E7C00
	DC.L	$00003030,$00303000,$00001818,$00183060
	DC.L	$0C183070,$381C0E00,$0000FE00,$FE000000
	DC.L	$30180C0E,$1C387000,$7CC6061C,$38003800
	DC.L	$C0C0C0C0,$C0C0C0FF,$7CC6C6FE,$E6E6E600
	DC.L	$FCC6C6FC,$E6E6FC00,$7EC0C0E0,$F0F07E00
	DC.L	$FCC6C6E6,$F6F6FC00,$7EC0C0FC,$E0E07E00
	DC.L	$7EC0C0F8,$E0F0F000,$7EC0C0EE,$F6F67E00
	DC.L	$C6C6C6FE,$E6E6E600,$18181838,$78787800
	DC.L	$7E06060E,$1E1EFC00,$C6CCD8F8,$DCDEDE00
	DC.L	$C0C0C0E0,$F0F0FE00,$EEFED6C6,$E6F6F600
	DC.L	$FCC6C6E6,$F6F6F600,$7CC6C6E6,$F6F67C00
	DC.L	$FCC6C6FC,$E0E0E000,$7CC6C6CE,$DEDE7F00
	DC.L	$FCC6C6FC,$CECECE00,$7CC0C07C,$0E0EFC00
	DC.L	$FE181838,$78787800,$C6C6C6E6,$F6F67C00
	DC.L	$CECECECC,$D8F0E000,$E6E6E6F6,$FEEEC600
	DC.L	$C66C386C,$EEEEEE00,$C6C6C67E,$0E0EFC00
	DC.L	$FE0C1830,$70F0FE00,$3C303030,$30303C00
	DC.L	$00C06030,$180C0600,$3C0C0C0C,$0C0C3C00
	DC.L	$03030303,$030303FF,$00000000,$000000FF
	DC.L	$30180C00,$00000000,$007CC6C6,$FEE6E600
	DC.L	$00FCC6FC,$E6E6FC00,$007CC0E0,$F0F07E00
	DC.L	$00FCC6E6,$F6F6FC00,$007EC0FC,$E0E07E00
	DC.L	$007EC0F8,$E0F0F000,$007EC0EE,$F6F67E00
	DC.L	$00C6C6FE,$E6E6E600,$00181818,$38787800
	DC.L	$007E0606,$0E1EFC00,$00C6CCF8,$DCDEDE00
	DC.L	$00C0C0C0,$E0F0FE00,$00EEFED6,$E6F6F600
	DC.L	$00FCC6E6,$F6F6F600,$007CC6C6,$E6F67C00
	DC.L	$00FCC6C6,$FCE0E000,$007CC6C6,$CEDE7F00
	DC.L	$00FCC6C6,$FCCECE00,$007CC07C,$0E0EFC00
	DC.L	$00FE1818,$38787800,$00C6C6C6,$E6F67C00
	DC.L	$00CECECC,$D8F0E000,$00E6E6F6,$FEEEC600
	DC.L	$00C66C38,$6CEEEE00,$00C6C67E,$0E0EFC00
	DC.L	$00FE0C18,$3878FE00,$1E303070,$30301E00
	DC.L	$03030303,$03030303,$780C0C0E,$0C0C7800
	DC.L	$C0C0C0C0,$C0C0C0C0,$FFFFFFFF,$FFFFFFFF



cop	dc.w	fmode,0			; burst off 
	dc.w	bplcon0,$9200
	dc.w	diwstrt,$2981		; Window start
	dc.w	diwstop,$29D1		; Window stop
	dc.w	ddfstrt,$3c		; Data fetch start = xx1/2-8.5
	dc.w	ddfstop,$d4		; Data fetch stop  = PLwdt*4-8+DDstart
	dc.w	bpl1mod,$00		; Mod 1 odd
	dc.w	bpl2mod,$00		; Mod 2 even
	dc.w	bplcon2,$00		; Bplcon2
	dc.w	bplcon1,$00		; Bplcon1
	dc.w	bplcon3,$00		
	dc.w	$e0,$6,$e2,0
	dc.w	color,$F00		; red background
	dc.w	color+2,$fff		; white foreground
	dc.l	-2			; End of Clist
end_cop


