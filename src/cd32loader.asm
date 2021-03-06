; IRA V2.00 (Nov  2 2010) (c)1993-95 Tim Ruehsen, (c)2009 Frank Wille
; partial reverse from Psygore binary by JOTD

AKIKO_BASE_PLUS_8	EQU	$B80008
CIAA_TDLO	EQU	$BFE801
CIAA_TDMD	EQU	$BFE901
CIAA_TDHI	EQU	$BFEA01
; those are already defined somewhere else (RN loader)
;INTENAR		EQU	$DFF01C
;INTENA		EQU	$DFF09A

	include	cd32loader.i
	include	whdmacros.i
	
timeout_wait_counter = 338
saved_intena = 336
status_flags = 334
current_filename_size = 60
current_file_buffer = 61
copy_of_writeonly_b8001f = 344
copy_of_writeonly_b8001d = 342

AKIKO_INTENA_OFFSET = 0
AKIKO_INTREQR_OFFSET = -4
AKIKO_DMA_OFFSET = 28
AKIKO_TRANSFER_REQ_OFFSET = 24
AKIKO_12_OFFSET = 12
AKIKO_16_OFFSET = 16
AKIKO_17_OFFSET = 17
AKIKO_18_OFFSET = 18
transmit_DMA_circular_buffer_end_position = 21
receive_DMA_circular_buffer_end_position = 23
AKIKO_DMA_BASE_ADDRESS = 8

NB_IRQ_RETRIES = 4
; < D0: command
; < A0: file (optional)
; < A1: chip CD buffer

CDL_0000:
	bra	.go
    ; small message of appreciation
	dc.b	"THANK YOU PSYGORE FOR NOT PROVIDING THE SOURCE CODE "
	dc.b	"BECAUSE YOU PROBABLY RIPPED THAT FROM ROB NORTHEN CODE",0
	even
.go
	MOVEM.L	D3/A2-A4,-(A7)		;032: 48e71038
	MOVE.L	D0,D3			;036: 2600
	LEA	AKIKO_BASE_PLUS_8,A3		;038: 47f900b80008
	LEA	locals(PC),A4		;03e: 49fa0df2	
CDL_0001:
	MOVE.W	INTENAR,D0		;042: 303900dff01c
	ANDI.W	#$0008,D0		;048: 02400008
	ORI.W	#$8000,D0		;04c: 00408000
	MOVE.W	D0,saved_intena(A4)		;050: 39400150
	; no level 2 interrupts
	MOVE.W	#$0008,INTENA		;054: 33fc000800dff09a

	bsr	try_to_clear_akiko_interrupts

	; JOTD: after CD play this DMA value was altered and causes long delays in the IRQ wait
	; now this is fixed from the cd audio side but better safe than sorry, it took me a long time
	; to figure it out
	; set AKIKO dma & intena (added by JOTD), same values as ROM
	move.l	#$10000000,AKIKO_INTENA_OFFSET(A3)
	bsr	activate_akiko_dma
	
	MOVEQ	#CDLERR_NOCMD,D0			;05c: 70ff
	CMPI.W	#$0008,D3		;05e: 0c430008
	BCC.S	.out		;062: 641a
	BSR	CDL_0006		;064: 6148
	BMI.S	.out		;066: 6b16
	MOVEQ	#CDLERR_NODISK,D0			;068: 70fa
	BTST	#1,335(A4)		;06a: 082c0001014f
	BEQ.S	.out		;070: 670c

	LEA	jump_table(PC),A2		;072: 45fa002a
	ADD.W	D3,D3			;076: d643
	ADDA.W	0(A2,D3.W),A2		;078: d4f23000
	JSR	(A2)			;07c: 4e92
.out:
	BSR.W	wait_until_interrupts_stop		;07e: 61000a3c
	ANDI.L	#$f7ffffff,AKIKO_INTENA_OFFSET(A3)		;082: 0293f7ffffff
	; JFF: turn off DMA completely
	; Notes:
	; - setting to 0 locks up the loading next time
	; - not doing anything about DMA triggers infinite level 2 interrupts:
	;      * only if CD audio play routine was active before
	;      * only on the real machine
	;; and.l	#$11800000,AKIKO_DMA_OFFSET(A3)  this makes loading fail
	
	; cancel pending interrupts interrupts by writing copy of values again in write only registers
	; that works better than the previous wait routine
	bsr	try_to_clear_akiko_interrupts
	
	MOVE.W	saved_intena(A4),INTENA		;088: 33ec015000dff09a
	; D0 contains status flags on MSW and error code (or 0) in MSB
	SWAP	D0			;090: 4840
CDL_0004:
	MOVE.W	status_flags(A4),D0		;092: 302c014e
	SWAP	D0			;096: 4840
	MOVEM.L	(A7)+,D3/A2-A4		;098: 4cdf1c08
	RTS				;09c: 4e75
	
try_to_clear_akiko_interrupts:
;	btst	#29,AKIKO_INTREQR_OFFSET(A3)
;	bne.b	.has_int
	btst	#28,AKIKO_INTREQR_OFFSET(A3)
	beq.b	.no_int
;.has_int
	move.b	copy_of_writeonly_b8001f(A4),receive_DMA_circular_buffer_end_position(A3)
	move.b	copy_of_writeonly_b8001d(A4),transmit_DMA_circular_buffer_end_position(A3)
	clr.b	AKIKO_TRANSFER_REQ_OFFSET(A3)

	move.l  d5,-(a7)
	move.l	#100,d5
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
	move.l	(a7)+,d5
	bra.b	try_to_clear_akiko_interrupts
	
.no_int
	rts
	
REL_OFFSET:MACRO
	dc.w	lab_\1-jump_table
	ENDM
	
jump_table:
     REL_OFFSET	CD_DRIVEINIT
	 REL_OFFSET	CD_INFOSTATUS
	 REL_OFFSET	CD_SETREADSPEED
	 REL_OFFSET	CD_CURRENTDIR
	 REL_OFFSET	CD_READSECTOR
	 REL_OFFSET	CD_GETFILEINFO
	 REL_OFFSET	CD_READFILE
	 REL_OFFSET	CD_READFILEOFFSET

CDL_0006:
	movem.l d1-d2/a0-a1,-(sp)
	MOVEQ	#0,D0			;0b2: 7000
	TST.W	D3			;0b4: 4a43
	BEQ.S	CDL_0007		;0b6: 671c
	TST.B	339(A4)			;0b8: 4a2c0153
	BEQ.S	CDL_0007		;0bc: 6716
	TST.L	20(A4)			;0be: 4aac0014
	BEQ.S	CDL_0007		;0c2: 6710
	ORI.L	#$08000000,AKIKO_INTENA_OFFSET(A3)		;0c4: 009308000000
	MOVE.B	copy_of_writeonly_b8001f(A4),receive_DMA_circular_buffer_end_position(A3)		;0ca: 176c01580017
	BRA.W	CDL_000C		;0d0: 600000c8
CDL_0007:
	CLR.B	339(A4)			;0d4: 422c0153
	MOVE.L	A0,D0			;0d8: 2008
	BEQ.S	CDL_0009		;0da: 6758
	TST.W	D0			;0dc: 4a40
	BNE.S	CDL_0009		;0de: 6654
	MOVE.L	A0,20(A4)		;0e0: 29480014
	MOVE.L	A0,AKIKO_DMA_BASE_ADDRESS(A3)		;0e4: 27480008
	ADDA.L	#$00010000,A0		;0e8: d1fc00010000
	MOVE.L	A0,24(A4)		;0ee: 29480018
	MOVE.L	A0,12(A3)		;0f2: 2748000c
	LEA	512(A0),A0		;0f6: 41e80200
	MOVE.L	A0,28(A4)		;0fa: 2948001c
	LEA	512(A0),A0		;0fe: 41e80200
	MOVE.L	A0,32(A4)		;102: 29480020
	LEA	512(A0),A0		;106: 41e80200
	MOVE.L	A0,36(A4)		;10a: 29480024
	MOVE.W	#$0037,332(A4)		;10e: 397c0037014c
	MOVEQ	#5,D1			;114: 7205
CDL_0008:
	CLR.W	status_flags(A4)			;116: 426c014e
	BSR.W	CDL_005A		;11a: 610005f4
	MOVE.B	#$07,316(A4)		;11e: 197c0007013c
	BSR.W	CDL_0083		;124: 61000938
	BPL.S	CDL_000A		;128: 6a0e
	BSR.W	wait_for_something		;12a: 61000936
	BPL.S	CDL_000A		;12e: 6a08
	DBF	D1,CDL_0008		;130: 51c9ffe4
CDL_0009:
	MOVEQ	#CDLERR_DRIVEINIT,D0			;134: 70fe
	BRA.S	CDL_000C		;136: 6062
CDL_000A:
	ANDI.B	#$03,D0			;138: 02000003
	BEQ.S	CDL_000B		;13c: 6706
	ORI.W	#$0001,status_flags(A4)		;13e: 006c0001014e
CDL_000B:
	MOVE.W	#$00de,332(A4)		;144: 397c00de014c
	BSR.S	CDL_000D		;14a: 6156
	CMPI.L	#$fffffffa,D0		;14c: 0c80fffffffa
	BEQ.S	CDL_000C		;152: 6746
	TST.L	D0			;154: 4a80
	BMI.S	CDL_000B		;156: 6bec
	MOVEA.L	32(A4),A0		;158: 206c0020
	MOVEQ	#CDLERR_BADTOC,D0			;15c: 70f9
	MOVE.L	2(A0),D1		;15e: 22280002
	BEQ.S	CDL_000C		;162: 6736
	MOVE.L	D1,D0			;164: 2001
	BSR.W	CDL_007A		;166: 6100084c
	MOVE.L	D0,52(A4)		;16a: 29400034
	ST	339(A4)			;16e: 50ec0153
	MOVEQ	#0,D0			;172: 7000
	BTST	#4,335(A4)		;174: 082c0004014f
	BEQ.S	CDL_000C		;17a: 671e
	CLR.L	8(A4)			;17c: 42ac0008
	MOVEQ	#16,D1			;180: 7210
	MOVEQ	#1,D2			;182: 7401
	MOVEA.L	36(A4),A1		;184: 226c0024
	BSR.W	lab_CD_READSECTOR		;188: 6100048a
	BMI.S	CDL_000C		;18c: 6b0c
	MOVE.L	136(A1),4(A4)		;18e: 296900880004
	MOVE.L	148(A1),0(A4)		;194: 296900940000
CDL_000C:
	MOVEM.L	(A7)+,D1-D2/A0-A1	;19a: 4cdf0306
	TST.L	D0			;19e: 4a80
	RTS				;1a0: 4e75
CDL_000D:
	ANDI.L	#$ff7fffff,44(A4)	;1a2: 02acff7fffff002c
	MOVEA.L	32(A4),A0		;1aa: 206c0020
	MOVE.W	#$0100,(A0)+		;1ae: 30fc0100
	CLR.L	(A0)+			;1b2: 4298
	MOVE.W	#$0053,D0		;1b4: 303c0053
CDL_000E:
	CLR.W	(A0)+			;1b8: 4258
	CLR.L	(A0)+			;1ba: 4298
	DBF	D0,CDL_000E		;1bc: 51c8fffa
	CLR.L	56(A4)			;1c0: 42ac0038
	CLR.L	48(A4)			;1c4: 42ac0030
CDL_000F:
	MOVE.W	#$0501,316(A4)		;1c8: 397c0501013c
	BSR.W	CDL_007C		;1ce: 6100080a
	CLR.B	350(A4)			;1d2: 422c015e
	MOVE.L	48(A4),D0		;1d6: 202c0030
	MOVE.L	D0,D1			;1da: 2200
	BEQ.S	CDL_0010		;1dc: 6710
	BSR.W	CDL_0077		;1de: 6100078e
	BSR.W	CDL_0076		;1e2: 61000768
	MOVE.L	D0,D1			;1e6: 2200
	SUBI.L	#$000008ca,D0		;1e8: 0480000008ca
CDL_0010:
	BSR.W	CDL_0079		;1ee: 610007a0
	BSR.W	CDL_007A		;1f2: 610007c0
	MOVE.L	D0,316(A4)		;1f6: 2940013c
	MOVE.L	D1,D0			;1fa: 2001
	BSR.W	CDL_0079		;1fc: 61000792
	BSR.W	CDL_007A		;200: 610007b2
	LSL.L	#8,D0			;204: e188
	MOVE.L	D0,320(A4)		;206: 29400140
	CLR.L	324(A4)			;20a: 42ac0144
	MOVE.B	#$02,316(A4)		;20e: 197c0002013c
	BSR.W	CDL_0083		;214: 61000848
	MOVE.B	#$04,316(A4)		;218: 197c0004013c
	MOVE.B	#$03,323(A4)		;21e: 197c00030143
	ST	349(A4)			;224: 50ec015d
	BSR.W	CDL_0083		;228: 61000834
	BPL.S	CDL_0011		;22c: 6a0a
	TST.L	56(A4)			;22e: 4aac0038
	BNE.S	CDL_0015		;232: 6658
	BRA.W	CDL_0019		;234: 600000b6
CDL_0011:
	CLR.L	48(A4)			;238: 42ac0030
	BTST	#2,335(A4)		;23c: 082c0002014f
	BNE.S	CDL_0014		;242: 6628
CDL_0012:
	MOVE.B	#$03,316(A4)		;244: 197c0003013c
	BSR.W	CDL_0083		;24a: 61000812
	BPL.S	CDL_0013		;24e: 6a16
	ANDI.B	#$f8,D0			;250: 020000f8
	CMPI.B	#$f8,D0			;254: 0c0000f8
	BEQ.W	CDL_0019		;258: 67000092
	CMPI.B	#$98,D0			;25c: 0c000098
	BEQ.W	CDL_0019		;260: 6700008a
	BRA.S	CDL_0012		;264: 60de
CDL_0013:
	ORI.W	#$0006,status_flags(A4)		;266: 006c0006014e
CDL_0014:
	MOVE.L	#$02900000,D0		;26c: 203c02900000
	BSR.W	wait_for_something_with_timeout		;272: 6100080a
	BTST	#23,D0			;276: 08000017
	BEQ.S	CDL_0019		;27a: 6770
	MOVE.L	48(A4),D0		;27c: 202c0030
	OR.L	D0,56(A4)		;280: 81ac0038
	TST.L	48(A4)			;284: 4aac0030
	BNE.W	CDL_000F		;288: 6600ff3e
CDL_0015:
	TST.L	56(A4)			;28c: 4aac0038
	BEQ.S	CDL_0016		;290: 671c
	CLR.L	316(A4)			;292: 42ac013c
	CLR.L	320(A4)			;296: 42ac0140
	CLR.L	324(A4)			;29a: 42ac0144
	MOVE.B	#$04,316(A4)		;29e: 197c0004013c
	MOVE.B	#$03,323(A4)		;2a4: 197c00030143
	BSR.W	CDL_0083		;2aa: 610007b2
CDL_0016:
	MOVE.B	#$02,316(A4)		;2ae: 197c0002013c
	BSR.W	CDL_0083		;2b4: 610007a8
	MOVEA.L	32(A4),A0		;2b8: 206c0020
	MOVE.B	6(A0),D0		;2bc: 10280006
	ANDI.B	#$f0,D0			;2c0: 020000f0
	CMPI.B	#$40,D0			;2c4: 0c000040
	BNE.S	CDL_0017		;2c8: 6606
	BSET	#4,335(A4)		;2ca: 08ec0004014f
CDL_0017:
	BSET	#3,335(A4)		;2d0: 08ec0003014f
	MOVEQ	#0,D0			;2d6: 7000
CDL_0018:
	CLR.B	349(A4)			;2d8: 422c015d
	MOVE.L	D0,-(A7)		;2dc: 2f00
	MOVE.W	#$0500,316(A4)		;2de: 397c0500013c
	BSR.W	CDL_007C		;2e4: 610006f4
	MOVE.L	(A7)+,D0		;2e8: 201f
	RTS				;2ea: 4e75
CDL_0019:
	MOVEQ	#CDLERR_NODISK,D0			;2ec: 70fa
	BTST	#1,335(A4)		;2ee: 082c0001014f
	BEQ.S	CDL_0018		;2f4: 67e2
	MOVEQ	#CDLERR_BADTOC,D0			;2f6: 70f9
	BRA.S	CDL_0018		;2f8: 60de

lab_CD_SETREADSPEED:	
lab_CD_DRIVEINIT:
	ORI.W	#$0280,status_flags(A4)		;2fa: 006c0280014e
	TST.L	D1			;300: 4a81
	BNE.S	CDL_001A		;302: 6606
	ANDI.W	#$fd7f,status_flags(A4)		;304: 026cfd7f014e
CDL_001A:
	MOVEQ	#0,D0			;30a: 7000
	RTS				;30c: 4e75
lab_CD_INFOSTATUS:
	MOVEQ	#0,D0			;30e: 7000
	RTS				;310: 4e75
lab_CD_READFILEOFFSET
	MOVEM.L	D3-D4,-(A7)		;312: 48e71800
	MOVE.L	D1,D3			;316: 2601
	MOVE.L	D2,D4			;318: 2802
	BSR.S	lab_CD_GETFILEINFO		;31a: 6132
	TST.L	D0			;31c: 4a80
	BMI.S	.out		;31e: 6b14
	MOVE.L	D3,D0			;320: 2003
	ADD.L	D4,D0			;322: d084
	CMP.L	D2,D0			;324: b082
	BGT.S	.error2		;326: 6e12
	LSL.L	#8,D1			;328: e189
	LSL.L	#3,D1			;32a: e789
	ADD.L	D4,D1			;32c: d284
	MOVE.L	D3,D2			;32e: 2403
	BSR.W	do_the_read_sector_job		;330: 610002f6
.out:
	MOVEM.L	(A7)+,D3-D4		;334: 4cdf0018
	RTS				;338: 4e75
.error2:
	MOVEQ	#CDLERR_READOFFSET,D0			;33a: 70f5
	BRA.S	.out		;33c: 60f6
	
lab_CD_READFILE
	BSR.S	lab_CD_GETFILEINFO		;33e: 610e
	TST.L	D0			;340: 4a80
	BMI.S	.out		;342: 6b08
	LSL.L	#8,D1			;344: e189
	LSL.L	#3,D1			;346: e789
	BRA.W	do_the_read_sector_job		;348: 600002de
.out:
	RTS				;34c: 4e75
lab_CD_GETFILEINFO:
	MOVEQ	#CDLERR_NODATA,D0			;34e: 70f8
	BTST	#4,335(A4)		;350: 082c0004014f
	BEQ.S	getfileinfo_error		;356: 6728
	BSR.W	CDL_002A		;358: 617c
	BPL.S	CDL_001F		;35a: 6a0a
	; when a file error occured, retrying crashes within here
	; crashed in this routine because A0 (source) was the same as
	; destination (current_file_buffer(A4))
	BSR.W	append_file_path_to_current_dir		;35c: 6100008e
	LEA	current_file_buffer(A4),A0		;360: 41ec003d
	BRA.S	CDL_0020		;364: 6006
CDL_001F:
	MOVE.L	328(A4),D0		;366: 202c0148
	BNE.S	CDL_0021		;36a: 6608
CDL_0020:
	MOVEQ	#0,D0			;36c: 7000
	BSR.W	search_entry		;36e: 610000c2
	BMI.S	getfileinfo_error		;372: 6b0c
CDL_0021:
	BSR.W	read_file_metadata		;374: 610001a2
	BMI.S	getfileinfo_error		;378: 6b06
	MOVE.L	D1,D2			;37a: 2401
	MOVE.L	D0,D1			;37c: 2200
	MOVEQ	#0,D0			;37e: 7000
getfileinfo_error:
	RTS				;380: 4e75
	
lab_CD_CURRENTDIR
	BSR.S	append_to_current_dir_name		;382: 6110
	MOVEQ	#1,D0			;384: 7001
	BSR.W	search_entry		;386: 610000aa
	BMI.S	CDL_0023		;38a: 6b06
	MOVE.L	D0,328(A4)		;38c: 29400148
	MOVEQ	#0,D0			;390: 7000
CDL_0023:
	RTS				;392: 4e75
; < A0: new dir name to append
append_to_current_dir_name:
	MOVE.L	A1,-(A7)		;394: 2f09
	MOVEA.L	A0,A1			;396: 2248
	; skip drive name (before colon)
CDL_0025:
	TST.B	(A1)			;398: 4a11
	BEQ.S	CDL_0026		;39a: 6708
	CMPI.B	#':',(A1)+		;39c: 0c19003a
	BNE.S	CDL_0025		;3a0: 66f6
	MOVEA.L	A1,A0			;3a2: 2049
CDL_0026:
	LEA	current_file_buffer(A4),A1		;3a4: 43ec003d
	; end of input string or "/" found: stop copying
	MOVE.B	(A0),D0			;3a8: 1010
	BEQ.S	CDL_0029		;3aa: 6726
	CMPI.B	#'/',D0			;3ac: 0c00002f
	BEQ.S	CDL_0029		;3b0: 6720
CDL_0027:
	MOVE.B	(A0)+,(A1)+		;3b2: 12d8
	TST.B	(A0)			;3b4: 4a10
	BNE.S	CDL_0027		;3b6: 66fa
	CMPI.B	#'/',-1(A1)		;3b8: 0c29002fffff
	BEQ.S	CDL_0028		;3be: 6704
	MOVE.B	#'/',(A1)+		;3c0: 12fc002f
CDL_0028:
	CLR.B	(A1)			;3c4: 4211
	; sanity check: check if the buffer isn't going to overtake max filename size
	movem.l	d0/a2,-(a7)
	LEA	current_file_buffer(A4),A2		;3a4: 43ec003d
	move.l	a1,d0
	sub.l	a2,d0	; d0 is the offset of the max char
	cmp.l	#100,d0	; cannot exceed that or things are going to be bad
	movem.l	(a7)+,d0/a2
	bcs.b	.ok
	; crash here (cannot happen, but just in case...)
.arggh
	ILLEGAL
.ok

	LEA	current_file_buffer(A4),A0		;3c6: 41ec003d
	MOVE.L	A1,D0			;3ca: 2009
	SUB.L	A0,D0			;3cc: 9088
	MOVE.B	D0,-1(A0)		;3ce: 1140ffff	; store size
CDL_0029:
	MOVEA.L	(A7)+,A1		;3d2: 225f
	RTS				;3d4: 4e75
CDL_002A:
	MOVE.L	A1,-(A7)		;3d6: 2f09
	MOVEA.L	A0,A1			;3d8: 2248
	MOVEQ	#0,D0			;3da: 7000
CDL_002B:
	MOVE.B	(A1)+,D0		;3dc: 1019
	BEQ.S	CDL_002C		;3de: 6708
	CMPI.B	#'/',D0			;3e0: 0c00002f
	BNE.S	CDL_002B		;3e4: 66f6
	MOVEQ	#-1,D0			;3e6: 70ff
CDL_002C:
	MOVEA.L	(A7)+,A1		;3e8: 225f
	RTS				;3ea: 4e75
	
; this is supposed to copy passed filename at the end of the current directory
; this overwrites buffer
; < A0: filepath
append_file_path_to_current_dir:
	MOVEM.L	A0-A1,-(A7)		;3ec: 48e700c0
	MOVEQ	#0,D0			;3f0: 7000
	LEA	current_filename_size(A4),A1		;3f2: 43ec003c  current_file_buffer-1
	MOVE.B	(A1)+,D0		;3f6: 1019		; D0: size
	ADDA.L	D0,A1			;3f8: d3c0
CDL_002E:
	MOVE.B	(A0)+,(A1)+		;3fa: 12d8
	TST.B	(A0)			;3fc: 4a10
	BNE.S	CDL_002E		;3fe: 66fa
	CLR.B	(A1)			;400: 4211
	MOVEM.L	(A7)+,A0-A1		;402: 4cdf0300
	RTS				;406: 4e75
CDL_002F:
	MOVEM.L	D0/A0,-(A7)		;408: 48e78080
CDL_0030:
	MOVE.B	(A0)+,D0		;40c: 1018
	BEQ.S	CDL_0031		;40e: 670c
	CMPI.B	#'/',D0			;410: 0c00002f
	BNE.S	CDL_0030		;414: 66f6
	MOVE.L	A0,4(A7)		;416: 2f480004
	BRA.S	CDL_0030		;41a: 60f0
CDL_0031:
	MOVEM.L	(A7)+,D0/A0		;41c: 4cdf0101
	RTS				;420: 4e75
CDL_0032:
	MOVEA.L	A0,A1			;422: 2248
CDL_0033:
	MOVE.B	(A1)+,D0		;424: 1019
	BEQ.S	CDL_0034		;426: 6706
	CMPI.B	#'/',D0			;428: 0c00002f
	BNE.S	CDL_0033		;42c: 66f6
CDL_0034:
	TST.B	-(A1)			;42e: 4a21
	RTS				;430: 4e75
	
search_entry:
	MOVEM.L	D1-D7/A0-A4,-(A7)	;432: 48e77ff8
	MOVE.L	D0,D5			;436: 2a00
	MOVEA.L	36(A4),A1		;438: 226c0024
	MOVEA.L	A1,A2			;43c: 2449
	MOVE.L	4(A4),D6		;43e: 2c2c0004
	MOVE.L	0(A4),D1		;442: 222c0000
	MOVE.L	D1,D7			;446: 2e01
	MOVE.L	D1,8(A4)		;448: 29410008
	MOVEQ	#2,D2			;44c: 7402
	BSR.W	lab_CD_READSECTOR		;44e: 610001c4
	BMI.W	CDL_003C		;452: 6b0000bc
	MOVEQ	#0,D1			;456: 7200
	MOVEQ	#1,D2			;458: 7401
	TST.B	D5			;45a: 4a05
	BEQ.S	CDL_0036		;45c: 670a
	MOVE.L	2(A2,D1.W),D0		;45e: 20321002
	TST.B	(A0)			;462: 4a10
	BEQ.W	CDL_003D		;464: 670000ac
CDL_0036:
	MOVE.B	(A0)+,D0		;468: 1018
	CMPI.B	#'/',D0			;46a: 0c00002f
	BEQ.S	CDL_0037		;46e: 6702
	SUBQ.W	#1,A0			;470: 5348
CDL_0037:
	MOVE.L	D2,D3			;472: 2602
	BSR.S	CDL_0032		;474: 61ac
	BNE.S	CDL_0038		;476: 6610
	MOVE.L	2(A2,D1.W),D0		;478: 20321002
	TST.B	D5			;47c: 4a05
	BEQ.W	CDL_003D		;47e: 67000092
	TST.B	(A0)			;482: 4a10
	BEQ.W	CDL_003D		;484: 6700008c
CDL_0038:
	MOVEM.L	A3-A4,-(A7)		;488: 48e70018
	CMP.W	6(A2,D1.W),D3		;48c: b6721006
	BNE.S	CDL_0039		;490: 660a
	MOVE.B	0(A2,D1.W),D4		;492: 18321000
	LEA	8(A2,D1.W),A3		;496: 47f21008
	MOVEA.L	A0,A4			;49a: 2848
CDL_0039:
	MOVE.B	(A3)+,D0		;49c: 101b
	BSR.W	to_lowercase		;49e: 61000980
	MOVE.W	D0,-(A7)		;4a2: 3f00
	MOVE.B	(A4)+,D0		;4a4: 101c
	BSR.W	to_lowercase		;4a6: 61000978
	CMP.W	(A7)+,D0		;4aa: b05f
	BNE.S	CDL_003A		;4ac: 661a
	SUBQ.B	#1,D4			;4ae: 5304
	BNE.S	CDL_0039		;4b0: 66ea
	CMPA.L	A1,A4			;4b2: b9c9
	BNE.S	CDL_003A		;4b4: 6612
	MOVEM.L	(A7)+,A3-A4		;4b6: 4cdf1800
	MOVE.L	2(A2,D1.W),D0		;4ba: 20321002
	TST.B	(A1)			;4be: 4a11
	BEQ.S	CDL_003D		;4c0: 6750
	LEA	1(A1),A0		;4c2: 41e90001
	BRA.S	CDL_0037		;4c6: 60aa
CDL_003A:
	MOVEM.L	(A7)+,A3-A4		;4c8: 4cdf1800
	ADDQ.L	#1,D2			;4cc: 5282
	MOVEQ	#9,D0			;4ce: 7009
	ADD.B	0(A2,D1.W),D0		;4d0: d0321000
	ANDI.B	#$fe,D0			;4d4: 020000fe
	ADD.L	D0,D1			;4d8: d280
	CMPI.L	#$00001000,D6		;4da: 0c8600001000
	BCS.S	CDL_003B		;4e0: 6528
	MOVE.L	#$00000800,D0		;4e2: 203c00000800
	CMP.L	D0,D1			;4e8: b280
	BCS.S	CDL_003B		;4ea: 651e
	SUB.L	D0,D1			;4ec: 9280
	SUB.L	D0,D6			;4ee: 9c80
	ADDQ.L	#1,D7			;4f0: 5287
	MOVEM.L	D1-D2/A1,-(A7)		;4f2: 48e76040
	MOVE.L	D7,D1			;4f6: 2207
	MOVE.L	D1,8(A4)		;4f8: 29410008
	MOVEQ	#2,D2			;4fc: 7402
	MOVEA.L	A2,A1			;4fe: 224a
	BSR.W	lab_CD_READSECTOR		;500: 61000112
	MOVEM.L	(A7)+,D1-D2/A1		;504: 4cdf0206
	BMI.S	CDL_003C		;508: 6b06
CDL_003B:
	CMP.L	D6,D1			;50a: b286
	BCS.W	CDL_0038		;50c: 6500ff7a
CDL_003C:
	MOVEQ	#CDLERR_DIRNOTFOUND,D0			;510: 70f6
CDL_003D:
	MOVEM.L	(A7)+,D1-D7/A0-A4	;512: 4cdf1ffe
	RTS				;516: 4e75
	
	
	
read_file_metadata:
	MOVEM.L	D2-D3/A0-A2,-(A7)	;518: 48e730e0
	BSR.W	CDL_002F		;51c: 6100feea
	MOVE.L	A0,8(A7)		;520: 2f480008
	MOVEA.L	36(A4),A2		;524: 246c0024
	MOVE.L	12(A4),D2		;528: 242c000c
	MOVE.L	D2,16(A4)		;52c: 29420010
	CMP.L	8(A4),D0		;530: b0ac0008
	BEQ.S	CDL_0040		;534: 6710
	MOVE.L	D0,8(A4)		;536: 29400008
	LSL.L	#8,D0			;53a: e188
	LSL.L	#3,D0			;53c: e788
CDL_003F:
	MOVE.L	D0,D2			;53e: 2400
	MOVE.L	D0,16(A4)		;540: 29400010
	BRA.S	CDL_0041		;544: 6018
CDL_0040:
	MOVE.L	16(A4),D1		;546: 222c0010
	SUB.L	12(A4),D1		;54a: 92ac000c
	MOVEQ	#0,D0			;54e: 7000
	MOVE.B	0(A2,D1.W),D0		;550: 10321000
	ADD.L	D1,D0			;554: d081
	CMPI.L	#$000007ff,D0		;556: 0c80000007ff
	BLE.S	CDL_0042		;55c: 6f24
CDL_0041:
	MOVEM.L	D2/A1,-(A7)		;55e: 48e72040
	MOVE.L	16(A4),D1		;562: 222c0010
	MOVE.L	#$00000800,D2		;566: 243c00000800
	MOVEA.L	A2,A1			;56c: 224a
	BSR.W	do_the_read_sector_job		;56e: 610000b8
	MOVEM.L	(A7)+,D2/A1		;572: 4cdf0204
	BMI.W	CDL_0047		;576: 6b000090
	MOVE.L	16(A4),12(A4)		;57a: 296c0010000c
	MOVEQ	#0,D1			;580: 7200
CDL_0042:
	TST.B	0(A2,D1.W)		;582: 4a321000
	BNE.S	CDL_0043		;586: 6630
	MOVE.L	16(A4),D0		;588: 202c0010
	ANDI.W	#$f800,D0		;58c: 0240f800
	ADDI.L	#$00000800,D0		;590: 068000000800
	MOVE.L	D0,16(A4)		;596: 29400010
	LSR.L	#8,D0			;59a: e088
	LSR.L	#3,D0			;59c: e688
	SUB.L	8(A4),D0		;59e: 90ac0008
	CMPI.B	#$0e,D0			;5a2: 0c00000e
	BLT.S	CDL_0041		;5a6: 6db6
	MOVE.L	8(A4),D0		;5a8: 202c0008
	LSL.L	#8,D0			;5ac: e188
	LSL.L	#3,D0			;5ae: e788
	CMP.L	D2,D0			;5b0: b082
	BCS.S	CDL_003F		;5b2: 658a
	MOVEQ	#CDLERR_FILENOTFOUND,D0			;5b4: 70f7
	BRA.S	CDL_0048		;5b6: 6054
CDL_0043:
	BTST	#1,25(A2,D1.W)		;5b8: 083200011019
	BNE.S	CDL_0046		;5be: 663a
	MOVEA.L	8(A7),A0		;5c0: 206f0008
	MOVE.B	32(A2,D1.W),D3		;5c4: 16321020
	SUBQ.B	#1,D3			;5c8: 5303
	LEA	33(A2,D1.W),A1		;5ca: 43f21021
	MOVEQ	#0,D0			;5ce: 7000
CDL_0044:
	CMPI.B	#$3b,(A1)		;5d0: 0c11003b
	BEQ.S	CDL_0045		;5d4: 6716
	MOVE.B	(A0)+,D0		;5d6: 1018
	BSR.W	to_lowercase		;5d8: 61000846
	MOVE.W	D0,-(A7)		;5dc: 3f00
	MOVE.B	(A1)+,D0		;5de: 1019
	BSR.W	to_lowercase		;5e0: 6100083e
	CMP.W	(A7)+,D0		;5e4: b05f
	BNE.S	CDL_0046		;5e6: 6612
	SUBQ.B	#1,D3			;5e8: 5303
	BNE.S	CDL_0044		;5ea: 66e4
CDL_0045:
	TST.B	(A0)			;5ec: 4a10
	BNE.S	CDL_0046		;5ee: 660a
	MOVE.L	6(A2,D1.W),D0		;5f0: 20321006
	MOVE.L	14(A2,D1.W),D1		;5f4: 2232100e
	BRA.S	CDL_0048		;5f8: 6012
CDL_0046:
	MOVEQ	#0,D0			;5fa: 7000
	MOVE.B	0(A2,D1.W),D0		;5fc: 10321000
	ADD.L	D0,16(A4)		;600: d1ac0010
	BRA.W	CDL_0040		;604: 6000ff40
CDL_0047:
	CLR.L	8(A4)			;608: 42ac0008
CDL_0048:
	TST.L	D0			;60c: 4a80
	MOVEM.L	(A7)+,D2-D3/A0-A2	;60e: 4cdf070c
	RTS				;612: 4e75
    
; Toni wrote (https://eab.abime.net/showpost.php?p=1267853&postcount=11):
; Writing loader isn't that difficult
; (CDTV CD controller is much more intelligent than CD32,
; CDTV can return 2048 byte "cooked" sectors. CD32 only returns
; raw 2352 sectors)
; below is the read sector routine (cooked) for CD32

; < D1: track number ($800*track number = offset in ISO)
; < D2: number of tracks to read (one track = $800 bytes)
; < A1: destination buffer
lab_CD_READSECTOR:
	MOVEQ	#CDLERR_NODATA,D0			;614: 70f8
	BTST	#4,335(A4)		;616: 082c0004014f
	BNE.S	CDL_004A		;61c: 6602
	RTS				;61e: 4e75
CDL_004A:
    ; multiply D1 and D2 by $800 
    ; to get real iso offset & size
	LSL.L	#8,D1			;620: e189
	LSL.L	#3,D1			;622: e789
	LSL.L	#8,D2			;624: e18a
	LSL.L	#3,D2			;626: e78a
    ; can be directly called there too from other sub-routines
do_the_read_sector_job:
	MOVEM.L	D2-D5/A0-A1,-(A7)	;628: 48e73cc0
	MOVE.L	D1,D4			;62c: 2801
	ANDI.W	#$07ff,D4		;62e: 024407ff
	MOVE.L	D2,D5			;632: 2a02
	BEQ.W	CDL_0059		;634: 670000ce
	MOVE.L	D1,D3			;638: 2601
	MOVEQ	#11,D0			;63a: 700b
	LSR.L	D0,D3			;63c: e0ab
	CLR.L	44(A4)			;63e: 42ac002c
	BSR.W	CDL_0063		;642: 61000182
CDL_004C:
	CLR.B	timeout_wait_counter(A4)			;646: 422c0152
check_irq_loop:
	; here is the buggy wait code Toni was talking about
	BSR.W	check_irq		;64a: 6100012a
	BPL.S	CDL_004E		;64e: 6a2c

	; it enters here when "check_irq" fails
	; then it loops 10 times and after that, the CD loading works again...
	; one way to force "check_irq" to fail is to leave AKIKODMA/INTENA in "cd play" mode
	;
	; When it fails it waits for 1 minute or such, which is ridiculous
	; so what I did (JOTD) was to only loop once, and also reduce the time in check_irq
	; 
	; so when the bug occurs (which is now NEVER but we never know), the delay is way shorter
	
;	move.w	#$F0F,$DFF180
;	btst	#6,$BFE001
;	bne.b	.w
	
	MOVE.L	#$fffffff8,40(A4)	;650: 297cfffffff80028
	ADDQ.B	#1,timeout_wait_counter(A4)		;658: 522c0152
	CMPI.B	#NB_IRQ_RETRIES,timeout_wait_counter(A4)		;65c: 0c2c000a0152   10 times
	BGE.W	CDL_0057		;662: 6c000080
	CMPI.B	#NB_IRQ_RETRIES/2,timeout_wait_counter(A4)		;666: 0c2c00050152
	BNE.S	check_irq_loop		;66c: 66dc
	MOVEQ	#0,D0			;66e: 7000
	BSR.W	CDL_0070		;670: 61000270
	ANDI.W	#$ff7f,status_flags(A4)		;674: 026cff7f014e
	BRA.S	check_irq_loop		;67a: 60ce
CDL_004E:
	BTST	#1,status_flags(A4)		;67c: 082c0001014e
	BEQ.S	CDL_004F		;682: 6706
	BSET	#7,335(A4)		;684: 08ec0007014f
CDL_004F:
	LEA	16(A0,D4.W),A0		;68a: 41f04010
	MOVE.L	#$00000800,D0		;68e: 203c00000800
	SUB.W	D4,D0			;694: 9044
	MOVEQ	#0,D4			;696: 7800
	CMP.L	D0,D5			;698: ba80
	BCC.S	CDL_0050		;69a: 6402
	MOVE.L	D5,D0			;69c: 2005
CDL_0050:
	SUB.L	D0,D5			;69e: 9a80
	SUBI.W	#$0028,D0		;6a0: 04400028
	BCS.S	CDL_0052		;6a4: 651a
	MOVEM.L	D3-D7/A2-A4,-(A7)	;6a6: 48e71f38
CDL_0051:
	MOVEM.L	(A0)+,D1-D7/A2-A4	;6aa: 4cd81cfe
	MOVEM.L	D1-D7/A2-A4,(A1)	;6ae: 48d11cfe
	LEA	40(A1),A1		;6b2: 43e90028
	SUBI.W	#$0028,D0		;6b6: 04400028
	BCC.S	CDL_0051		;6ba: 64ee
	MOVEM.L	(A7)+,D3-D7/A2-A4	;6bc: 4cdf1cf8
CDL_0052:
	ADDI.W	#$0028,D0		;6c0: 06400028
	BEQ.S	CDL_0056		;6c4: 6714
	SUBQ.W	#4,D0			;6c6: 5940
	BCS.S	CDL_0054		;6c8: 6506
CDL_0053:
	MOVE.L	(A0)+,(A1)+		;6ca: 22d8
	SUBQ.W	#4,D0			;6cc: 5940
	BCC.S	CDL_0053		;6ce: 64fa
CDL_0054:
	ADDQ.W	#4,D0			;6d0: 5840
	BEQ.S	CDL_0056		;6d2: 6706
CDL_0055:
	MOVE.B	(A0)+,(A1)+		;6d4: 12d8
	SUBQ.B	#1,D0			;6d6: 5300
	BNE.S	CDL_0055		;6d8: 66fa
CDL_0056:
	ADDQ.L	#1,D3			;6da: 5283
	TST.L	D5			;6dc: 4a85
	BNE.W	CDL_004C		;6de: 6600ff66
	MOVEQ	#0,D0			;6e2: 7000
CDL_0057:
	TST.L	D0			;6e4: 4a80
	BPL.S	CDL_0058		;6e6: 6a12
	MOVE.L	D0,-(A7)		;6e8: 2f00
	MOVEQ	#0,D0			;6ea: 7000
	BSR.W	CDL_0070		;6ec: 610001f4
	BSR.S	CDL_005A		;6f0: 611e
	BSR.W	wait_for_something		;6f2: 6100036e
	MOVE.L	(A7)+,D0		;6f6: 201f
	BRA.S	CDL_0059		;6f8: 600a
CDL_0058:
	TST.B	347(A4)			;6fa: 4a2c015b
	BEQ.S	CDL_0059		;6fe: 6704
	BSR.W	CDL_0063		;700: 610000c4
CDL_0059:
	MOVE.L	(A7),D1			;704: 2217
	SUB.L	D5,D1			;706: 9285
	TST.L	D0			;708: 4a80
	MOVEM.L	(A7)+,D2-D5/A0-A1	;70a: 4cdf033c
	RTS				;70e: 4e75
CDL_005A:
	CLR.B	receive_DMA_circular_buffer_end_position(A3)			;710: 422b0017
	CLR.B	transmit_DMA_circular_buffer_end_position(A3)			;714: 422b0015
	MOVE.B	17(A3),copy_of_writeonly_b8001d(A4)		;718: 196b00110156
	; set AKIKO DMA properly, enable CD data DMA
	bsr		activate_akiko_dma
	MOVE.B	18(A3),D0		;732: 102b0012
	MOVE.B	D0,343(A4)		;736: 19400157
	ADDQ.B	#1,D0			;73a: 5200
	MOVE.B	D0,receive_DMA_circular_buffer_end_position(A3)		;73c: 17400017
	MOVE.B	D0,copy_of_writeonly_b8001f(A4)		;740: 19400158
	CLR.B	345(A4)			;744: 422c0159
	CLR.B	transmit_DMA_circular_buffer_end_position(A3)			;748: 422b0015
	MOVE.L	#$18000000,AKIKO_INTENA_OFFSET(A3)		;74c: 26bc18000000
	MOVE.B	#$10,340(A4)		;752: 197c00100154
	MOVE.L	#$fffffffc,40(A4)	;758: 297cfffffffc0028
	CLR.L	44(A4)			;760: 42ac002c
	CLR.B	347(A4)			;764: 422c015b
	BSR.W	CDL_0074		;768: 610001c2
	MOVE.W	#$0500,316(A4)		;76c: 397c0500013c
	BRA.W	CDL_0083		;772: 600002ea
activate_akiko_dma
	MOVE.L	AKIKO_DMA_OFFSET(A3),D0		;71e: 202b001c
	ANDI.L	#$00800000,D0		;722: 028000800000
	ORI.L	#$79000000,D0		;728: 008079000000
	MOVE.L	D0,AKIKO_DMA_OFFSET(A3)		;72e: 2740001c
	rts
	
check_irq:
	MOVEQ	#100,D2			;776: 7464
irq_retry:
	MOVEQ	#CDLERR_IRQ,D0			;778: 70fd
	SUBQ.L	#1,D2			;77a: 5382
	BMI.S	irq_timeout		;77c: 6b44
	BSR.S	CDL_0064		;77e: 6152
	BEQ.S	irq_success		;780: 6742
	TST.B	347(A4)			;782: 4a2c015b
	BNE.S	CDL_005E		;786: 6606
CDL_005D:
	BSR.W	CDL_006C		;788: 61000104
	BMI.S	irq_timeout		;78c: 6b34
CDL_005E:
	; that's a loooong delay, but I tried reducing it and it failed on the real console
	MOVE.L	#$03100000,D0		;78e: 203c03100000
	BSR.W	wait_for_something_with_timeout		;794: 610002e8
	BMI.S	irq_timeout		;798: 6b28
	BTST	#20,D0			;79a: 08000014
	BEQ.S	CDL_0060		;79e: 671a
	SUBQ.L	#8,40(A4)		;7a0: 51ac0028
	CMPI.L	#$ffffffe8,40(A4)	;7a4: 0cacffffffe80028
	BGE.S	CDL_005F		;7ac: 6c08
	MOVE.L	#$ffffffe8,40(A4)	;7ae: 297cffffffe80028
CDL_005F:
	BSR.S	CDL_0063		;7b6: 610e
	BRA.S	CDL_005D		;7b8: 60ce
CDL_0060:
	BTST	#25,D0			;7ba: 08000019
	BEQ.S	irq_retry		;7be: 67b8
	MOVEQ	#CDLERR_ABORTDRIVE,D0			;7c0: 70fc
irq_timeout:
	BRA.S	CDL_0063		;7c2: 6002
irq_success:
	RTS				;7c4: 4e75
CDL_0063:
	MOVE.L	D0,-(A7)		;7c6: 2f00
	MOVEQ	#0,D0			;7c8: 7000
	BSR.W	CDL_00A1		;7ca: 6100048c
	MOVE.L	(A7)+,D0		;7ce: 201f
	RTS				;7d0: 4e75
CDL_0064:
	MOVEQ	#0,D1			;7d2: 7200
	MOVEA.L	20(A4),A0		;7d4: 206c0014
CDL_0065:
	MOVE.W	2(A0),D0		;7d8: 30280002
	BMI.W	CDL_0068		;7dc: 6b00008c
	ANDI.B	#$1f,D0			;7e0: 0200001f
	CMP.B	346(A4),D0		;7e4: b02c015a
	BNE.W	CDL_0068		;7e8: 66000080
	BTST	#8,D0			;7ec: 08000008
	BNE.S	CDL_0068		;7f0: 6678
	MOVE.L	(A0),D0			;7f2: 2010
	ANDI.B	#$c0,D0			;7f4: 020000c0
	CMPI.B	#$c0,D0			;7f8: 0c0000c0
	BEQ.S	CDL_0068		;7fc: 676c
	MOVE.L	12(A0),D0		;7fe: 2028000c
	SUBQ.B	#1,D0			;802: 5300
	BNE.S	CDL_0068		;804: 6664
	LSR.L	#8,D0			;806: e088
	BSR.W	CDL_0077		;808: 61000164
	BSR.W	CDL_0076		;80c: 6100013e
	SUBI.L	#$00000096,D0		;810: 048000000096
	SUB.L	D3,D0			;816: 9083
	BEQ.S	CDL_006A		;818: 6762
	TST.B	347(A4)			;81a: 4a2c015b
	BEQ.S	CDL_0067		;81e: 672e
	CMPI.L	#$fffffff6,D0		;820: 0c80fffffff6
	BGE.S	CDL_0067		;826: 6c26
	CMPI.B	#$01,347(A4)		;828: 0c2c0001015b
	BNE.S	CDL_0066		;82e: 6618
	ADDQ.L	#2,D0			;830: 5480
	SUB.L	D0,40(A4)		;832: 91ac0028
	CMPI.L	#$00000018,40(A4)	;836: 0cac000000180028
	BLE.S	CDL_0066		;83e: 6f08
	MOVE.L	#$00000018,40(A4)	;840: 297c000000180028
CDL_0066:
	BSR.W	CDL_0063		;848: 6100ff7c
	BRA.S	CDL_0069		;84c: 602a
CDL_0067:
	MOVE.W	#$8000,2(A0)		;84e: 317c80000002
	MOVEQ	#0,D0			;854: 7000
	BSET	D1,D0			;856: 03c0
	MOVE.W	D0,AKIKO_TRANSFER_REQ_OFFSET(A3)		;858: 37400018
	ADDQ.B	#1,346(A4)		;85c: 522c015a
	ANDI.B	#$1f,346(A4)		;860: 022c001f015a
	BRA.W	CDL_0064		;866: 6000ff6a
CDL_0068:
	LEA	4096(A0),A0		;86a: 41e81000
	ADDQ.B	#1,D1			;86e: 5201
	CMPI.B	#$10,D1			;870: 0c010010
	BNE.W	CDL_0065		;874: 6600ff62
CDL_0069:
	MOVEQ	#1,D0			;878: 7001
	RTS				;87a: 4e75
CDL_006A:
	CMPI.B	#$01,347(A4)		;87c: 0c2c0001015b
	BNE.S	CDL_006B		;882: 6606
	MOVE.B	#$02,347(A4)		;884: 197c0002015b
CDL_006B:
	MOVEQ	#0,D0			;88a: 7000
	RTS				;88c: 4e75
CDL_006C:
	BSR.W	CDL_0074		;88e: 6100009c
	MOVE.W	#$0501,316(A4)		;892: 397c0501013c
	BSR.W	CDL_007C		;898: 61000140
	MOVE.L	D3,D0			;89c: 2003
	ADD.L	40(A4),D0		;89e: d0ac0028
	BSR.S	CDL_0070		;8a2: 613e
	BMI.S	CDL_006F		;8a4: 6b3a
	BTST	#1,D0			;8a6: 08000001
	BEQ.S	CDL_006D		;8aa: 6708
	BTST	#2,335(A4)		;8ac: 082c0002014f
	BNE.S	CDL_006E		;8b2: 6612
CDL_006D:
	MOVE.B	#$03,316(A4)		;8b4: 197c0003013c
	BSR.W	CDL_0083		;8ba: 610001a2
	BMI.S	CDL_006F		;8be: 6b20
	ORI.W	#$0004,status_flags(A4)		;8c0: 006c0004014e
CDL_006E:
	MOVE.B	#$01,347(A4)		;8c6: 197c0001015b
	CLR.B	346(A4)			;8cc: 422c015a
	ORI.L	#$04000000,AKIKO_DMA_OFFSET(A3)	;8d0: 00ab04000000001c
	ORI.L	#$04000000,AKIKO_INTENA_OFFSET(A3)		;8d8: 009304000000
	MOVEQ	#0,D0			;8de: 7000
CDL_006F:
	RTS				;8e0: 4e75
CDL_0070:
	MOVE.L	#$80000004,323(A4)	;8e2: 297c800000040143
	BTST	#7,335(A4)		;8ea: 082c0007014f
	BEQ.S	CDL_0071		;8f0: 6706
	BSET	#6,324(A4)		;8f2: 08ec00060144
CDL_0071:
	CLR.B	327(A4)			;8f8: 422c0147
	MOVE.L	52(A4),319(A4)		;8fc: 296c0034013f
	ADDI.L	#$00000096,D0		;902: 068000000096
	BSR.W	CDL_0079		;908: 61000086
	BSR.W	CDL_007A		;90c: 610000a6
	MOVE.L	D0,316(A4)		;910: 2940013c
	CMP.L	52(A4),D0		;914: b0ac0034
	BCC.S	CDL_0072		;918: 640c
	MOVE.B	#$04,316(A4)		;91a: 197c0004013c
	BSR.W	CDL_0083		;920: 6100013c
	BPL.S	CDL_0073		;924: 6a02
CDL_0072:
	MOVEQ	#CDLERR_CMDREAD,D0			;926: 70fb
CDL_0073:
	TST.L	D0			;928: 4a80
	RTS				;92a: 4e75
	
	; this code writes $8000 every $1000 address in CD read buffer then writes
	; $FFFF to akiko transfer req
CDL_0074:
	MOVE.L	A0,-(A7)		;92c: 2f08
	MOVEQ	#15,D0			;92e: 700f
	MOVEA.L	20(A4),A0		;930: 206c0014
	ADDQ.L	#2,A0			;934: 5488
CDL_0075:
	MOVE.W	#$8000,(A0)		;936: 30bc8000
	LEA	4096(A0),A0		;93a: 41e81000
	DBF	D0,CDL_0075		;93e: 51c8fff6
	MOVE.W	#$ffff,AKIKO_TRANSFER_REQ_OFFSET(A3)		;942: 377cffff0018
	MOVEA.L	(A7)+,A0		;948: 205f
	RTS				;94a: 4e75
CDL_0076:
	MOVEM.L	D1-D2,-(A7)		;94c: 48e76000
	SWAP	D0			;950: 4840
	MOVE.W	D0,D1			;952: 3200
	MULU	#$1194,D1		;954: c2fc1194
	SWAP	D0			;958: 4840
	MOVEQ	#0,D2			;95a: 7400
	MOVE.B	D0,D2			;95c: 1400
	ADD.L	D2,D1			;95e: d282
	LSR.W	#8,D0			;960: e048
	MULU	#$004b,D0		;962: c0fc004b
	ADD.L	D1,D0			;966: d081
	MOVEM.L	(A7)+,D1-D2		;968: 4cdf0006
	RTS				;96c: 4e75
CDL_0077:
	SWAP	D0			;96e: 4840
	BSR.S	CDL_0078		;970: 6106
	ROL.L	#8,D0			;972: e198
	BSR.S	CDL_0078		;974: 6102
	ROL.L	#8,D0			;976: e198
CDL_0078:
	MOVEM.L	D1,-(A7)		;978: 48e74000
	MOVE.B	D0,D1			;97c: 1200
	ANDI.B	#$0f,D0			;97e: 0200000f
	LSR.B	#4,D1			;982: e809
	MULU	#$000a,D1		;984: c2fc000a
	ADD.B	D1,D0			;988: d001
	MOVEM.L	(A7)+,D1		;98a: 4cdf0002
	RTS				;98e: 4e75
CDL_0079:
	MOVEM.L	D1,-(A7)		;990: 48e74000
	MOVE.L	D0,D1			;994: 2200
	MOVEQ	#0,D0			;996: 7000
	DIVU	#$004b,D1		;998: 82fc004b
	SWAP	D1			;99c: 4841
	MOVE.B	D1,D0			;99e: 1001
	CLR.W	D1			;9a0: 4241
	SWAP	D1			;9a2: 4841
	DIVU	#$003c,D1		;9a4: 82fc003c
	SWAP	D1			;9a8: 4841
	LSL.W	#8,D1			;9aa: e149
	OR.L	D1,D0			;9ac: 8081
	MOVEM.L	(A7)+,D1		;9ae: 4cdf0002
	RTS				;9b2: 4e75
CDL_007A:
	MOVEM.L	D1,-(A7)		;9b4: 48e74000
	SWAP	D0			;9b8: 4840
	BSR.S	CDL_007B		;9ba: 610e
	ROL.L	#8,D0			;9bc: e198
	BSR.S	CDL_007B		;9be: 610a
	ROL.L	#8,D0			;9c0: e198
	BSR.S	CDL_007B		;9c2: 6106
	MOVEM.L	(A7)+,D1		;9c4: 4cdf0002
	RTS				;9c8: 4e75
CDL_007B:
	MOVEQ	#0,D1			;9ca: 7200
	MOVE.B	D0,D1			;9cc: 1200
	DIVU	#$000a,D1		;9ce: 82fc000a
	MULU	#$0006,D1		;9d2: c2fc0006
	ADD.B	D1,D0			;9d6: d001
	RTS				;9d8: 4e75
CDL_007C:
	MOVEQ	#0,D0			;9da: 7000
CDL_007D:
	MOVEM.L	D0-D2/A0-A1,-(A7)	;9dc: 48e7e0c0
	MOVE.B	348(A4),D0		;9e0: 102c015c
	ANDI.B	#$0f,D0			;9e4: 0200000f
	MOVE.B	316(A4),D1		;9e8: 122c013c
	ANDI.B	#$0f,D1			;9ec: 0201000f
	CMP.B	D0,D1			;9f0: b200
	BNE.S	CDL_007E		;9f2: 6604
	CLR.B	348(A4)			;9f4: 422c015c
CDL_007E:
	LEA	316(A4),A0		;9f8: 41ec013c
	MOVEQ	#0,D0			;9fc: 7000
	MOVE.B	(A0),D0			;9fe: 1010
	MOVE.B	CDL_0082(PC,D0.W),D1	;a00: 123b004c
	OR.B	340(A4),D0		;a04: 802c0154
	MOVE.B	D0,(A0)			;a08: 1080
CDL_007F:
	ADDI.B	#$10,340(A4)		;a0a: 062c00100154
	BEQ.S	CDL_007F		;a10: 67f8
	MOVEQ	#0,D2			;a12: 7400
	MOVE.B	copy_of_writeonly_b8001d(A4),D2		;a14: 142c0156
	MOVEA.L	28(A4),A1		;a18: 226c001c

		; needs	patching to fix	grinding bug

	MOVEQ	#-1,D0			;a20: 70ff
.copy1
	sub.b (a0),d0
	move.b (a0)+,0(a1,d2.w) ;command bytes
	addq.b #1,d2	; wraps when D2=0xFF, that's on purpose
	subq.b #1,d1
	bne.s .copy1
	move.b d0,0(a1,d2.w) ;checksum byte
		
		;; end patch	
	
	ADDQ.B	#1,D2			;a2c: 5202
	MOVE.B	D2,copy_of_writeonly_b8001d(A4)		;a2e: 19420156
	MOVE.B	D2,transmit_DMA_circular_buffer_end_position(A3)		;a32: 17420015
	TST.W	2(A7)			;a36: 4a6f0002
	BEQ.S	CDL_0081		;a3a: 6706
	MOVE.B	316(A4),348(A4)		;a3c: 196c013c015c
CDL_0081:
	ORI.L	#$08000000,AKIKO_INTENA_OFFSET(A3)		;a42: 009308000000
	MOVEM.L	(A7)+,D0-D2/A0-A1	;a48: 4cdf0307
	RTS				;a4c: 4e75
CDL_0082:
	dc.b	1,2,1,1,$C,2,1,1,4,1,0,0,0,0,0,0

	
CDL_0083:
	BSR.W	CDL_007C		;a5e: 6100ff7a
wait_for_something:
	MOVE.L	A0,-(A7)		;a62: 2f08
	MOVEQ	#16,D0			;a64: 7010
	SWAP	D0			;a66: 4840
	; here we are when the wait is just loooooong
	BSR.S	wait_for_something_with_timeout		;a68: 6114
	BMI.S	CDL_0085		;a6a: 6b0e
	MOVEA.L	24(A4),A0		;a6c: 206c0018
	MOVEQ	#0,D0			;a70: 7000
	MOVE.B	341(A4),D0		;a72: 102c0155
	MOVE.B	1(A0,D0.W),D0		;a76: 10300001
CDL_0085:
	MOVEA.L	(A7)+,A0		;a7a: 205f
	RTS				;a7c: 4e75
	
wait_for_something_with_timeout:
	MOVEM.L	D1-D3,-(A7)		;a7e: 48e77000
	MOVE.L	D0,D1			;a82: 2200
	MOVEQ	#0,D0			;a84: 7000
	MOVE.W	332(A4),D0		;a86: 302c014c
	BSR.W	get_timer_value_in_d3		;a8a: 6100037a
	ADD.L	D3,D0			;a8e: d083
	
	; this loops too much in case of a spurious error
loop_until_wtf:
	BSR.S	CDL_008C		;a90: 6144
	MOVE.L	44(A4),D2		;a92: 242c002c
	AND.L	D1,D2			;a96: c481
	BNE.S	CDL_0088		;a98: 660c
	BSR.W	get_timer_value_in_d3		;a9a: 6100036a
	CMP.L	D3,D0			;a9e: b083
	BCC.S	loop_until_wtf		;aa0: 64ee

	; timeout: set an error, but doesn't seem to matter
	MOVEQ	#CDLERR_IRQ,D0			;aa2: 70fd
	BRA.S	CDL_0089		;aa4: 6010
CDL_0088:

	
	MOVE.L	44(A4),D0		;aa6: 202c002c
	MOVE.L	D0,-(A7)		;aaa: 2f00
	NOT.L	D1			;aac: 4681
	AND.L	D1,D0			;aae: c081
	MOVE.L	D0,44(A4)		;ab0: 2940002c
	MOVE.L	(A7)+,D0		;ab4: 201f
CDL_0089:
	MOVEM.L	(A7)+,D1-D3		;ab6: 4cdf000e
	RTS				;aba: 4e75
wait_until_interrupts_stop:
	MOVEM.L	D0-D1,-(A7)		;abc: 48e7c000
	MOVE.W	#$01f4,D1		;ac0: 323c01f4
CDL_008B:
	BSR.S	CDL_008C		;ac4: 6110
	MOVE.L   AKIKO_INTENA_OFFSET(A3),D0			;ac6: 2013
	AND.L	AKIKO_INTREQR_OFFSET(A3),D0		;ac8: c0abfffc
	DBEQ	D1,CDL_008B		;acc: 57c9fff6
	MOVEM.L	(A7)+,D0-D1		;ad0: 4cdf0003
	RTS				;ad4: 4e75
CDL_008C:
	MOVEM.L	D0-D2/A0-A2,-(A7)	;ad6: 48e7e0e0
	MOVE.L   AKIKO_INTENA_OFFSET(A3),D2			;ada: 2413
	AND.L	AKIKO_INTREQR_OFFSET(A3),D2		;adc: c4abfffc
	BEQ.S	CDL_0090		;ae0: 672c
	LEA	CDL_0091(PC),A2		;ae2: 45fa0030
	BTST	#28,D2			;ae6: 0802001c
	BEQ.S	CDL_008D		;aea: 6702
	BSR.S	CDL_0092		;aec: 6136
CDL_008D:
	BTST	#27,D2			;aee: 0802001b
	BEQ.S	CDL_008E		;af2: 6706
	ANDI.L	#$f7ffffff,AKIKO_INTENA_OFFSET(A3)		;af4: 0293f7ffffff
CDL_008E:
	BTST	#31,D2			;afa: 0802001f
	BEQ.S	CDL_008F		;afe: 6704
	CLR.B	16(A3)			;b00: 422b0010
CDL_008F:
	BTST	#26,D2			;b04: 0802001a
	BEQ.S	CDL_0090		;b08: 6704
	BSR.W	CDL_009C		;b0a: 61000110
CDL_0090:
	MOVEM.L	(A7)+,D0-D2/A0-A2	;b0e: 4cdf0707
	RTS				;b12: 4e75
CDL_0091:
	BTST	D0,D3			;b14: 0103
	BTST	D1,D3			;b16: 0303
	BTST	D1,D3			;b18: 0303
	MOVE.B	(A5),D0			;b1a: 1015
	BTST	D1,D1			;b1c: 0301
	BTST	D1,D1			;b1e: 0301
	BTST	D0,D1			;b20: 0101
	BTST	D0,D1			;b22: 0101
CDL_0092:
	ANDI.L	#$efffffff,AKIKO_INTENA_OFFSET(A3)		;b24: 0293efffffff
	MOVEA.L	24(A4),A0		;b2a: 206c0018
	TST.B	345(A4)			;b2e: 4a2c0159
	BNE.S	CDL_0095		;b32: 663e
	ST	345(A4)			;b34: 50ec0159
	MOVEQ	#0,D0			;b38: 7000
	MOVE.B	343(A4),D0		;b3a: 102c0157
	MOVE.B	0(A0,D0.W),D0		;b3e: 10300000
	ANDI.B	#$0f,D0			;b42: 0200000f
	MOVE.B	0(A2,D0.W),D0		;b46: 10320000
	ADD.B	copy_of_writeonly_b8001f(A4),D0		;b4a: d02c0158
	SUBQ.B	#1,D0			;b4e: 5300
CDL_0093:
	MOVE.B	D0,copy_of_writeonly_b8001f(A4)		;b50: 19400158
	MOVE.B	D0,receive_DMA_circular_buffer_end_position(A3)		;b54: 17400017
	SUB.B	18(A3),D0		;b58: 902b0012
	BMI.S	CDL_0092		;b5c: 6bc6
	BNE.S	CDL_0094		;b5e: 660a
	MOVE.L	AKIKO_INTREQR_OFFSET(A3),D0		;b60: 202bfffc
	BTST	#28,D0			;b64: 0800001c
	BEQ.S	CDL_0092		;b68: 67ba
CDL_0094:
	ORI.L	#$10000000,AKIKO_INTENA_OFFSET(A3)		;b6a: 009310000000
	RTS				;b70: 4e75
CDL_0095:
	MOVE.L	D2,-(A7)		;b72: 2f02
	MOVEQ	#0,D2			;b74: 7400
	MOVE.B	343(A4),D2		;b76: 142c0157
	MOVE.B	0(A0,D2.W),D0		;b7a: 10302000
	ANDI.W	#$000f,D0		;b7e: 0240000f
	MOVE.B	0(A2,D0.W),D1		;b82: 12320000
	MOVEQ	#0,D0			;b86: 7000
CDL_0096:
	ADD.B	0(A0,D2.W),D0		;b88: d0302000
	ADDQ.B	#1,D2			;b8c: 5202
	SUBQ.B	#1,D1			;b8e: 5301
	BNE.S	CDL_0096		;b90: 66f6
	MOVE.L	(A7)+,D2		;b92: 241f
	CMPI.B	#$ff,D0			;b94: 0c0000ff
	BNE.S	CDL_009B		;b98: 665a
	MOVEQ	#0,D1			;b9a: 7200
	MOVE.B	343(A4),D1		;b9c: 122c0157
	MOVE.B	0(A0,D1.W),D0		;ba0: 10301000
	CMP.B	348(A4),D0		;ba4: b02c015c
	BEQ.S	CDL_009B		;ba8: 674a
	CMPI.B	#$06,D0			;baa: 0c000006
	BEQ.W	CDL_00A3		;bae: 670000e4
	ANDI.B	#$0f,D0			;bb2: 0200000f
	ADDQ.B	#1,D1			;bb6: 5201
	CMPI.B	#$04,D0			;bb8: 0c000004
	BEQ.S	CDL_0097		;bbc: 6706
	CMPI.B	#$03,D0			;bbe: 0c000003
	BNE.S	CDL_0098		;bc2: 6606
CDL_0097:
	MOVE.B	0(A0,D1.W),D0		;bc4: 10301000
	BMI.S	CDL_009A		;bc8: 6b1c
CDL_0098:
	MOVE.B	0(A0,D1.W),D0		;bca: 10301000
	BMI.S	CDL_0099		;bce: 6b06
	ANDI.B	#$70,D0			;bd0: 02000070
	BNE.S	CDL_009B		;bd4: 661e
CDL_0099:
	SUBQ.B	#1,D1			;bd6: 5301
	MOVE.B	0(A0,D1.W),D0		;bd8: 10301000
	ANDI.B	#$0f,D0			;bdc: 0200000f
	CMPI.B	#$0a,D0			;be0: 0c00000a
	BEQ.S	CDL_009B		;be4: 670e
CDL_009A:
	MOVE.B	343(A4),341(A4)		;be6: 196c01570155
	ORI.L	#$00100000,44(A4)	;bec: 00ac00100000002c
CDL_009B:
	CLR.B	345(A4)			;bf4: 422c0159
	MOVEA.L	24(A4),A0		;bf8: 206c0018
	MOVEQ	#0,D0			;bfc: 7000
	MOVE.B	343(A4),D0		;bfe: 102c0157
	MOVE.B	0(A0,D0.W),D0		;c02: 10300000
	ANDI.W	#$000f,D0		;c06: 0240000f
	MOVE.B	0(A2,D0.W),D1		;c0a: 12320000
	ADD.B	D1,343(A4)		;c0e: d32c0157
	MOVE.B	copy_of_writeonly_b8001f(A4),D0		;c12: 102c0158
	ADDQ.B	#1,D0			;c16: 5200
	BRA.W	CDL_0093		;c18: 6000ff36
CDL_009C:
	MOVE.L	AKIKO_INTREQR_OFFSET(A3),D0		;c1c: 202bfffc
	BTST	#25,D0			;c20: 08000019
	BEQ.S	CDL_009D		;c24: 670a
	MOVEQ	#1,D0			;c26: 7001
	BSR.S	CDL_00A1		;c28: 612e
	BSR.W	CDL_0074		;c2a: 6100fd00
	BRA.S	CDL_00A0		;c2e: 601a
CDL_009D:
	MOVE.W	AKIKO_TRANSFER_REQ_OFFSET(A3),D0		;c30: 302b0018
	MOVEQ	#0,D1			;c34: 7200
CDL_009E:
	LSR.W	#1,D0			;c36: e248
	BCC.S	CDL_009F		;c38: 6402
	ADDQ.B	#1,D1			;c3a: 5201
CDL_009F:
	TST.W	D0			;c3c: 4a40
	BNE.S	CDL_009E		;c3e: 66f6
	CMPI.B	#$02,D1			;c40: 0c010002
	BHI.S	CDL_00A0		;c44: 6204
	MOVEQ	#1,D0			;c46: 7001
	BSR.S	CDL_00A1		;c48: 610e
CDL_00A0:
	ORI.L	#$01000000,44(A4)	;c4a: 00ac01000000002c
	CLR.W	AKIKO_TRANSFER_REQ_OFFSET(A3)			;c52: 426b0018
	RTS				;c56: 4e75
CDL_00A1:
	MOVE.L	D0,-(A7)		;c58: 2f00
	ANDI.L	#$f9ffffff,AKIKO_INTENA_OFFSET(A3)		;c5a: 0293f9ffffff
	ANDI.L	#$fbffffff,AKIKO_DMA_OFFSET(A3)	;c60: 02abfbffffff001c
	MOVE.W	#$0500,316(A4)		;c68: 397c0500013c
	BSR.W	CDL_007C		;c6e: 6100fd6a
	TST.B	347(A4)			;c72: 4a2c015b
	BEQ.S	CDL_00A2		;c76: 6718
	CLR.B	347(A4)			;c78: 422c015b
	MOVE.B	#$02,316(A4)		;c7c: 197c0002013c
	MOVE.L	(A7),D0			;c82: 2017
	BSR.W	CDL_007D		;c84: 6100fd56
	TST.L	(A7)			;c88: 4a97
	BNE.S	CDL_00A2		;c8a: 6604
	BSR.W	wait_for_something		;c8c: 6100fdd4
CDL_00A2:
	MOVE.L	(A7)+,D0		;c90: 201f
	RTS				;c92: 4e75
CDL_00A3:
	MOVE.L	D2,-(A7)		;c94: 2f02
	TST.B	349(A4)			;c96: 4a2c015d
	BEQ.W	CDL_00AA		;c9a: 6700012c
	MOVE.W	#$0500,D0		;c9e: 303c0500
	TST.B	350(A4)			;ca2: 4a2c015e
	BNE.S	CDL_00A4		;ca6: 6602
	ADDQ.B	#1,D0			;ca8: 5200
CDL_00A4:
	NOT.B	350(A4)			;caa: 462c015e
	MOVE.W	D0,316(A4)		;cae: 3940013c
	BSR.W	CDL_007C		;cb2: 6100fd26
	BTST	#3,335(A4)		;cb6: 082c0003014f
	BNE.W	CDL_00AA		;cbc: 6600010a
	MOVEA.L	24(A4),A1		;cc0: 226c0018
	MOVEQ	#1,D0			;cc4: 7001
	BSR.W	CDL_00AB		;cc6: 61000106
	BMI.W	CDL_00AA		;cca: 6b0000fc
	MOVEQ	#2,D0			;cce: 7002
	BSR.W	CDL_00AB		;cd0: 610000fc
	BNE.W	CDL_00AA		;cd4: 660000f2
	MOVEQ	#3,D0			;cd8: 7003
	BSR.W	CDL_00AB		;cda: 610000f2
	ANDI.B	#$0f,D0			;cde: 0200000f
	CMPI.B	#$01,D0			;ce2: 0c000001
	BEQ.S	CDL_00A5		;ce6: 6722
	CMPI.B	#$05,D0			;ce8: 0c000005
	BNE.W	CDL_00AA		;cec: 660000da
	BSR.W	CDL_00AB		;cf0: 610000dc
	CMPI.B	#$b0,D0			;cf4: 0c0000b0
	BNE.W	CDL_00AA		;cf8: 660000ce
	MOVEQ	#5,D0			;cfc: 7005
	BSR.W	CDL_00AC		;cfe: 610000da
	MOVE.L	D0,48(A4)		;d02: 29400030
	BRA.W	CDL_00AA		;d06: 600000c0
CDL_00A5:
	MOVEQ	#4,D0			;d0a: 7004
	BSR.W	CDL_00AB		;d0c: 610000c0
	BNE.W	CDL_00AA		;d10: 660000b6
	MOVEA.L	32(A4),A0		;d14: 206c0020
	MOVEQ	#5,D0			;d18: 7005
	BSR.W	CDL_00AB		;d1a: 610000b2
	CMPI.B	#$a0,D0			;d1e: 0c0000a0
	BEQ.S	CDL_00A8		;d22: 6770
	CMPI.B	#$a1,D0			;d24: 0c0000a1
	BNE.S	CDL_00A6		;d28: 6610
	MOVEQ	#10,D0			;d2a: 700a
	BSR.W	CDL_00AB		;d2c: 610000a0
	BSR.W	CDL_0078		;d30: 6100fc46
	MOVE.B	D0,1(A0)		;d34: 11400001
	BRA.S	CDL_00A8		;d38: 605a
CDL_00A6:
	CMPI.B	#$a2,D0			;d3a: 0c0000a2
	BNE.S	CDL_00A7		;d3e: 6628
	MOVEQ	#0,D2			;d40: 7400
	MOVE.B	1(A0),D2		;d42: 14280001
	BEQ.W	CDL_00AA		;d46: 67000080
	ADDQ.W	#1,D2			;d4a: 5242
	MULU	#$0006,D2		;d4c: c4fc0006
	CLR.W	0(A0,D2.W)		;d50: 42702000
	MOVEQ	#9,D0			;d54: 7009
	BSR.W	CDL_00AC		;d56: 61000082
	BSR.W	CDL_0077		;d5a: 6100fc12
	MOVE.L	D0,2(A0)		;d5e: 21400002
	MOVE.L	D0,2(A0,D2.W)		;d62: 21802002
	BRA.S	CDL_00A8		;d66: 602c
CDL_00A7:
	BSR.W	CDL_0078		;d68: 6100fc0e
	BEQ.S	CDL_00AA		;d6c: 675a
	CMPI.B	#$64,D0			;d6e: 0c000064
	BCC.S	CDL_00AA		;d72: 6454
	MOVEQ	#0,D2			;d74: 7400
	MOVE.B	D0,D2			;d76: 1400
	MULU	#$0006,D2		;d78: c4fc0006
	MOVE.B	D0,1(A0,D2.W)		;d7c: 11802001
	MOVEQ	#3,D0			;d80: 7003
	BSR.S	CDL_00AB		;d82: 614a
	MOVE.B	D0,0(A0,D2.W)		;d84: 11802000
	MOVEQ	#9,D0			;d88: 7009
	BSR.S	CDL_00AC		;d8a: 614e
	BSR.W	CDL_0077		;d8c: 6100fbe0
	MOVE.L	D0,2(A0,D2.W)		;d90: 21802002
CDL_00A8:
	CMPI.B	#$01,(A0)		;d94: 0c100001
	BNE.S	CDL_00AA		;d98: 662e
	TST.B	1(A0)			;d9a: 4a280001
	BEQ.S	CDL_00AA		;d9e: 6728
	TST.L	2(A0)			;da0: 4aa80002
	BEQ.S	CDL_00AA		;da4: 6722
	MOVEQ	#1,D0			;da6: 7001
	MOVE.W	#$0006,D2		;da8: 343c0006
CDL_00A9:
	TST.B	1(A0,D2.W)		;dac: 4a302001
	BEQ.S	CDL_00AA		;db0: 6716
	ADDQ.B	#1,D0			;db2: 5200
	ADDQ.W	#6,D2			;db4: 5c42
	CMP.B	1(A0),D0		;db6: b0280001
	BLS.S	CDL_00A9		;dba: 63f0
	CLR.B	349(A4)			;dbc: 422c015d
	ORI.L	#$00800000,44(A4)	;dc0: 00ac00800000002c
CDL_00AA:
	MOVE.L	(A7)+,D2		;dc8: 241f
	BRA.W	CDL_009B		;dca: 6000fe28
CDL_00AB:
	ADD.B	D1,D0			;dce: d001
	ANDI.W	#$00ff,D0		;dd0: 024000ff
	MOVE.B	0(A1,D0.W),D0		;dd4: 10310000
	RTS				;dd8: 4e75
CDL_00AC:
	MOVEM.L	D2-D3,-(A7)		;dda: 48e73000
	MOVE.B	D0,D2			;dde: 1400
	MOVEQ	#0,D0			;de0: 7000
	ADDQ.B	#1,D2			;de2: 5202
	MOVE.B	D2,D0			;de4: 1002
	BSR.S	CDL_00AB		;de6: 61e6
	MOVE.B	D0,D3			;de8: 1600
	LSL.L	#8,D3			;dea: e18b
	ADDQ.B	#1,D2			;dec: 5202
	MOVE.B	D2,D0			;dee: 1002
	BSR.S	CDL_00AB		;df0: 61dc
	MOVE.B	D0,D3			;df2: 1600
	LSL.L	#8,D3			;df4: e18b
	ADDQ.B	#1,D2			;df6: 5202
	MOVE.B	D2,D0			;df8: 1002
	BSR.S	CDL_00AB		;dfa: 61d2
	MOVE.B	D0,D3			;dfc: 1600
	MOVE.L	D3,D0			;dfe: 2003
	MOVEM.L	(A7)+,D2-D3		;e00: 4cdf000c
	RTS				;e04: 4e75
	
get_timer_value_in_d3:
	MOVEQ	#0,D3			;e06: 7600
	MOVE.B	CIAA_TDHI,D3		;e08: 163900bfea01
	SWAP	D3			;e0e: 4843
	MOVE.B	CIAA_TDMD,D3		;e10: 163900bfe901
	LSL.W	#8,D3			;e16: e14b
	MOVE.B	CIAA_TDLO,D3		;e18: 163900bfe801
	RTS				;e1e: 4e75
to_lowercase:
	CMPI.B	#$61,D0			;e20: 0c000061
	BLT.S	CDL_00AF		;e24: 6d0a
	CMPI.B	#$7a,D0			;e26: 0c00007a
	BGT.S	CDL_00AF		;e2a: 6e04
	SUBI.B	#$20,D0			;e2c: 04000020
CDL_00AF:
	RTS				;e30: 4e75
locals:
	ds.b	352,0

