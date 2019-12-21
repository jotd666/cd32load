; IRA V2.00 (Nov  2 2010) (c)1993-95 Tim Ruehsen, (c)2009 Frank Wille
; Rob Northen hardware IDE OFS/FFS hard-disk loading routine
;
; JOTD: resourced for CD32Load
; JOTD: removed CD, floppy & NVM parts which aren't useful for CD32Load
; JOTD: added read part of file capability

	include	whdmacros.i

RN_AKIKO_BASE	EQU	$B80000
RN_AKIKO_NVM	EQU	$B80030
CIAB_PRB	EQU	$BFD100
CIAB_TBLO	EQU	$BFD600
CIAB_TBHI	EQU	$BFD700
CIAB_CRB	EQU	$BFDF00
CIAA_PRA	EQU	$BFE001
; $da.2000-$da.21ff 	IDE command registers
A1200_IDE_REGISTER	EQU	$DA2000
; DD2000 to DDFFFF        A4000 IDE
A4000_IDE_REGISTER	EQU	$DD2022
; GAYLE registers at $DE1000 - $DE1FFF
GAYLE_BASE	EQU	$DE1000

HARDBASE	EQU	$DFF000
DMACONR		EQU	$DFF002
INTENAR		EQU	$DFF01C
INTREQR		EQU	$DFF01E
;DSKLEN		EQU	$DFF024
DMACON		EQU	$DFF096
INTENA		EQU	$DFF09A
INTREQ		EQU	$DFF09C
ADKCON		EQU	$DFF09E

; variable offsets
file_or_dir_name = 16
current_command = 112
drive_type = 211
main_drive_buffer = 28
init_done = 210
inout_data_buffer = 20
buffer_512_1 = 32
buffer_512_2 = 36
buffer_512_3 = 40
buffer_4 = 44
block_size_TBC = 238
datablock_size = 84
current_file_size = 12
current_file_read_start_offset = 406
current_file_read_size = 410

; BSIZE-188/-0xbc	ulong	1	byte_size	file size in bytes: $200-188 = 324 all righty
st_size = 324

FLOPPY_DRIVE_TYPE = 'F'
CD32_DRIVE_TYPE = 'D'
HARD_DRIVE_TYPE = 'H'

; <D0: command: known commands
;  0: read
;  3: get file size
;  4: change directory
; 12: (added by JOTD) partial read, with D1=start offset, D2=length or -1 to read till the end
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



RNL_0000:
	MOVEM.L	A0-A3/A6,-(A7)		;0000: 48e700f2
	LEA	rn_locals(PC),A6		;0004: 4dfa0f3c
	MOVE.W	D0,current_command(A6)		;0008: 3d400070
	MOVEQ	#0,D0			;000c: 7000
;	TST.W	current_command(A6)			;000e: 4a6e0070
;	NOP				;0012: 4e71
	BSR.S	RNL_0002		;0014: 6142
	BMI.S	RNL_0000		;0016: 6b20
	MOVE.W	current_command(A6),D0		;0018: 302e0070
	ADD.W	D0,D0			;001c: d040
	LEA	command_jump_table(PC),A3		;001e: 47fa0020
	ADDA.W	0(A3,D0.W),A3		;0022: d6f30000
	JSR	(A3)			;0026: 4e93
;	CMPI.B	#FLOPPY_DRIVE_TYPE,drive_type(A6)		;0028: 0c2e004600d3
;	BNE.S	unknown_drive_type		;002e: 6608
;	MOVE.L	D0,-(A7)		;0030: 2f00
;	BSR.W	RNL_00B5		;0032: 61000ec2
;	MOVE.L	(A7)+,D0		;0036: 201f
unknown_drive_type:
	EXT.L	D0			;0038: 48c0
	MOVEM.L	(A7)+,A0-A3/A6		;003a: 4cdf4f00
	RTS				;003e: 4e75
	
REL_OFFSET:MACRO
	dc.w	command_\1-command_jump_table
	ENDM
	; 0-11 : 12 commands + 1 added
command_jump_table:
	REL_OFFSET	0_read			;0040
	REL_OFFSET	1_write		;0042
	REL_OFFSET	2_probably_delete		;0042
	REL_OFFSET	3_get_file_size		;0042
	REL_OFFSET	4_change_directory
	dc.w	$7CE	; command 5 offset looks invalid
	REL_OFFSET	6_unknown
	REL_OFFSET	7_unknown
	REL_OFFSET	8_unknown
	REL_OFFSET	9_unknown
	REL_OFFSET	10_unknown
	REL_OFFSET	11_floppy_only_unknown		; maybe format?
	REL_OFFSET	12_partial_read
RNL_0002:
	MOVEM.L	D1-D6/A1,-(A7)		;0058: 48e77e40
	MOVE.L	A0,file_or_dir_name(A6)		;005c: 2d480010
	TST.B	init_done(A6)			;0060: 4a2e00d2
	BEQ.S	RNL_0003		;0064: 670a
	CMPA.L	main_drive_buffer(A6),A2		;0066: b5ee001c
	BEQ.S	RNL_0004		;006a: 672c
	; not the same drive buffer address: reinit everything
	CLR.B	init_done(A6)			;006c: 422e00d2
RNL_0003:
	MOVE.B	#FLOPPY_DRIVE_TYPE,drive_type(A6)		;0070: 1d7c004600d3
	MOVE.L	#$000006e0,8(A6)	;0076: 2d7c000006e00008
	; default OFS
	MOVE.L	#$000001e8,datablock_size(A6)	;007e: 2d7c000001e80054
	MOVEA.L	A2,A0			;0086: 204a
	MOVEQ	#26,D0			;0088: 701a		; 512*26 buffer size
	MOVEQ	#1,D1			;008a: 7201
	MOVEQ	#11,D2			;008c: 740b
	MOVEA.L	A2,A0			;008e: 204a
	BSR.W	init_drive_buffers		;0090: 61000166
	BSR.W	init_other_pointers		;0094: 61000242
RNL_0004:
	MOVEQ	#0,D0			;0098: 7000
	CMPI.B	#$08,current_command(A6)		;009a: 0c2e00080070
	BCC.W	RNL_000C_error		;00a0: 6400014e
	MOVEQ	#0,D4			;00a4: 7800
	MOVEA.L	file_or_dir_name(A6),A0		;00a6: 206e0010
	CMPI.B	#':',3(A0)		;00aa: 0c28003a0003
	BNE.W	RNL_0009		;00b0: 660000bc
	MOVEQ	#0,D5			;00b4: 7a00
	MOVE.B	2(A0),D5		;00b6: 1a280002
	SUBI.B	#'0',D5			;00ba: 04050030
	BLT.W	RNL_0009		;00be: 6d0000ae
	; D5 is the unit
	CMPI.B	#$03,D5			;00c2: 0c050003
	BHI.W	RNL_0009		;00c6: 620000a6
	BSR.W	RNL_008E		;00ca: 61000bca
	LSL.W	#8,D0			;00ce: e148
	BSR.W	RNL_008E		;00d0: 61000bc4
	MOVE.W	D0,D6			;00d4: 3c00
	; now test device type
	; DFx
	CMPI.W	#$4446,D6		;00d6: 0c464446  
	BNE.S	RNL_0005		;00da: 660e
	; floppy drive
	MOVEQ	#26,D0			;00dc: 701a
	MOVEQ	#1,D1			;00de: 7201
	MOVEQ	#11,D2			;00e0: 740b
	MOVE.L	#$000006e0,D4		;00e2: 283c000006e0
	BRA.S	RNL_0008		;00e8: 6064
RNL_0005:
	; DHx:
	CMPI.W	#$4448,D6		;00ea: 0c464448
	BNE.S	RNL_0006		;00ee: 6630
	; hard drive
	MOVE.L	D5,D1			;00f0: 2205
	MOVEQ	#2,D0			;00f2: 7002
	BSR.W	send_hard_drive_command		;00f4: 61001840
	BMI.W	RNL_000C_error		;00f8: 6b0000f6
	; D4: DOS\0 / DOS\1
	MOVE.L	D4,(A6)			;00fc: 2c84
	MOVE.L	D2,D4			;00fe: 2802
	MOVEQ	#2,D0			;0100: 7002
	MOVEQ	#10,D1			;0102: 720a
	MOVEQ	#25,D2			;0104: 7419
	MOVE.L	#$00000200,datablock_size(A6)	;0106: 2d7c000002000054
	CMPI.L	#$444f5301,(A6)		;010e: 0c96444f5301
	BEQ.S	RNL_0008		;0114: 6738
	; OFS datablock size
	MOVE.L	#$000001e8,datablock_size(A6)	;0116: 2d7c000001e80054
	BRA.S	RNL_0008		;011e: 602e
RNL_0006:
	; CDx
	CMPI.W	#$4344,D6		;0120: 0c464344
	BNE.S	RNL_0007		;0124: 6616
	MOVEQ	#1,D1			;0126: 7201
	MOVEQ	#9,D0			;0128: 7009
	BSR.W	cd_drive_unsupported		;012a: 61001f4a
	BMI.W	RNL_000C_error		;012e: 6b0000c0
	MOVE.L	D2,D4			;0132: 2802
	MOVEQ	#-117,D0		;0134: 708b
	MOVEQ	#0,D1			;0136: 7200
	MOVEQ	#0,D2			;0138: 7400
	BRA.S	RNL_0008		;013a: 6012
RNL_0007:
	MOVEQ	#-30,D0			;013c: 70e2
	; NFx (nonvolatile??)
	CMPI.W	#$4e56,D6		;013e: 0c464e56
	BNE.W	RNL_000C_error		;0142: 660000ac
	MOVEQ	#0,D0			;0146: 7000
	MOVEQ	#0,D1			;0148: 7200
	MOVEQ	#0,D2			;014a: 7400
	MOVEQ	#2,D4			;014c: 7802
RNL_0008:
	MOVEA.L	A2,A0			;014e: 204a
	BSR.W	init_drive_buffers		;0150: 610000a6
	MOVE.L	D4,8(A6)		;0154: 2d440008
	MOVE.L	D5,4(A6)		;0158: 2d450004
	ADDQ.L	#4,file_or_dir_name(A6)		;015c: 58ae0010
	CMP.B	drive_type(A6),D6		;0160: bc2e00d3
	BEQ.S	RNL_0009		;0164: 6708
	BSR.W	RNL_0016		;0166: 61000172
	MOVE.B	D6,drive_type(A6)		;016a: 1d4600d3
RNL_0009:
	CLR.B	212(A6)			;016e: 422e00d4
	MOVEQ	#78,D0			;0172: 704e
	MOVEA.L	file_or_dir_name(A6),A0		;0174: 206e0010
	LEA	325(A6),A1		;0178: 43ee0145
	CMPI.B	#$2f,(A0)+		;017c: 0c18002f
	BEQ.S	RNL_000A		;0180: 6726
	CMPI.B	#$5c,-1(A0)		;0182: 0c28005cffff
	BEQ.S	RNL_000A		;0188: 671e
	SUBQ.W	#1,A0			;018a: 5348
	TST.L	D4			;018c: 4a84
	BNE.S	RNL_000A		;018e: 6618
	MOVE.B	#$01,212(A6)		;0190: 1d7c000100d4
	LEA	245(A6),A0		;0196: 41ee00f5
	BSR.W	copy_byte_loop		;019a: 61000094
	MOVE.B	#$2f,-1(A1)		;019e: 137c002fffff
	MOVEA.L	file_or_dir_name(A6),A0		;01a4: 206e0010
RNL_000A:
	MOVE.L	A0,file_or_dir_name(A6)		;01a8: 2d480010
	BSR.W	copy_byte_loop		;01ac: 61000082
	MOVEA.L	file_or_dir_name(A6),A0		;01b0: 206e0010
	TST.L	(A6)			;01b4: 4a96
	BNE.S	RNL_000B		;01b6: 6630
	CMPI.B	#FLOPPY_DRIVE_TYPE,drive_type(A6)		;01b8: 0c2e004600d3
	BNE.S	RNL_000B		;01be: 6628
	CMPI.W	#$0006,current_command(A6)		;01c0: 0c6e00060070
	BEQ.S	RNL_000B		;01c6: 6720
	BSR.W	detect_floppy_filesystem_type		;01c8: 610000e2
	BMI.S	RNL_000C_error		;01cc: 6b22
	MOVE.L	D1,(A6)			;01ce: 2c81
	MOVE.L	#$00000200,datablock_size(A6)	;01d0: 2d7c000002000054
	CMPI.L	#$444f5301,D1		;01d8: DOS\1
	BEQ.S	RNL_000B		;01de: 6708
	MOVE.L	#$000001e8,datablock_size(A6)	;01e0: 2d7c000001e80054
RNL_000B:
	MOVE.B	#$01,init_done(A6)		;01e8: 1d7c000100d2
	MOVEQ	#0,D0			;01ee: 7000
RNL_000C_error:
	TST.L	D0			;01f0: 4a80
	MOVEM.L	(A7)+,D1-D6/A1		;01f2: 4cdf027e
	RTS				;01f6: 4e75
init_drive_buffers:
	MOVE.L	A0,main_drive_buffer(A6)		;01f8: 2d48001c
	MOVEQ	#9,D3			;01fc: 7609
	LSL.L	D3,D0			;01fe: e7a8
	; A0 += D0*512
	ADDA.L	D0,A0			;0200: d1c0
	MOVE.L	A0,buffer_512_1(A6)		;0202: 2d480020
	LEA	512(A0),A0		;0206: 41e80200
	MOVE.L	A0,buffer_512_2(A6)		;020a: 2d480024
	LEA	512(A0),A0		;020e: 41e80200
	MOVE.L	A0,buffer_512_3(A6)		;0212: 2d480028
	LEA	512(A0),A0		;0216: 41e80200
	MOVE.L	A0,buffer_4(A6)		;021a: 2d48002c
	MOVE.L	D1,64(A6)		;021e: 2d410040
	LSL.L	D3,D1			;0222: e7a9
	ADDA.L	D1,A0			;0224: d1c1
	MOVE.L	A0,48(A6)		;0226: 2d480030
	MOVE.L	D2,68(A6)		;022a: 2d420044
	RTS				;022e: 4e75
copy_byte_loop:
	MOVE.B	(A0)+,(A1)+		;0230: 12d8
	DBEQ	D0,copy_byte_loop		;0232: 57c8fffc
	RTS				;0236: 4e75
	
command_4_change_directory:
	MOVEM.L	A0-A1,-(A7)		;0238: 48e700c0
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;023c: 0c2e004400d3
	BNE.S	RNL_000F		;0242: 660e
	; not reached
	ILLEGAL
	;LEA	325(A6),A0		;0244: 41ee0145
	;MOVEQ	#15,D0			;0248: 700f
	;BSR.W	cd_drive_unsupported		;024a: 61001e2a
	;BMI.S	RNL_0011		;024e: 6b24
	;BRA.S	RNL_0010		;0250: 6014
RNL_000F:
	MOVEA.L	buffer_512_1(A6),A0		;0252: 206e0020
	BSR.W	read_dir_meta_info		;0256: 6100092e
	CLR.L	56(A6)			;025a: 42ae0038
	TST.L	D0			;025e: 4a80
	BMI.S	RNL_0011		;0260: 6b12
	MOVE.L	D1,56(A6)		;0262: 2d410038
RNL_0010:
	LEA	325(A6),A0		;0266: 41ee0145
	LEA	245(A6),A1		;026a: 43ee00f5
	MOVEQ	#78,D0			;026e: 704e
	BSR.S	copy_byte_loop		;0270: 61be
	MOVEQ	#0,D0			;0272: 7000
RNL_0011:
	MOVEM.L	(A7)+,A0-A1		;0274: 4cdf0300
	RTS				;0278: 4e75
	
command_11_floppy_only_unknown
	MOVE.L	D1,-(A7)		;027a: 2f01
	MOVEQ	#-2,D0			;027c: 70fe
	CMPI.B	#FLOPPY_DRIVE_TYPE,drive_type(A6)		;027e: 0c2e004600d3
	BNE.S	RNL_0012		;0284: 6620
	BSR.S	init_other_pointers		;0286: 6150
	BSR.S	detect_floppy_filesystem_type		;0288: 6122
	BMI.S	RNL_0012		;028a: 6b1a
	MOVE.L	D1,(A6)			;028c: 2c81
	MOVE.L	#$00000200,datablock_size(A6)	;028e: 2d7c000002000054
	CMPI.L	#$444f5301,D1		;0296: 0c81444f5301
	BEQ.S	RNL_0012		;029c: 6708
	MOVE.L	#$000001e8,datablock_size(A6)	;029e: 2d7c000001e80054
RNL_0012:
	MOVE.L	(A7)+,D1		;02a6: 221f
	TST.L	D0			;02a8: 4a80
	RTS				;02aa: 4e75
detect_floppy_filesystem_type:
	MOVE.L	A0,-(A7)		;02ac: 2f08
	MOVEA.L	buffer_512_2(A6),A0		;02ae: 206e0024
	MOVEQ	#0,D1			;02b2: 7200
	BSR.W	read_disk_sector_raw		;02b4: 61000c38
	BMI.S	RNL_0014		;02b8: 6b18
	MOVE.L	(A0),D1			;02ba: 2210
	ANDI.B	#$01,D1			;02bc: 02010001
	; OFS ?
	CMPI.L	#$444f5300,D1		;02c0: 0c81444f5300
	BEQ.S	RNL_0014		;02c6: 670a
	; FFS ?
	CMPI.L	#$444f5301,D1		;02c8: 0c81444f5301
	BEQ.S	RNL_0014		;02ce: 6702
	; unknown filesystem type
	MOVEQ	#-27,D0			;02d0: 70e5
RNL_0014:
	MOVEA.L	(A7)+,A0		;02d2: 205f
	TST.L	D0			;02d4: 4a80
	RTS				;02d6: 4e75
init_other_pointers:
	CLR.L	(A6)			;02d8: 4296
RNL_0016:
	CLR.L	56(A6)			;02da: 42ae0038
	CLR.L	60(A6)			;02de: 42ae003c
	CLR.L	96(A6)			;02e2: 42ae0060
	CLR.L	100(A6)			;02e6: 42ae0064
	CLR.L	104(A6)			;02ea: 42ae0068
	CLR.L	108(A6)			;02ee: 42ae006c
	CLR.B	245(A6)			;02f2: 422e00f5
	RTS				;02f6: 4e75
	
command_3_get_file_size:
	MOVEM.L	D2/A0,-(A7)		;02f8: 48e72080
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;02fc: 0c2e004400d3
	BNE.S	RNL_0017		;0302: 6610
	; this code isn't reached
	ILLEGAL
	;LEA	325(A6),A0		;0304: 41ee0145
	;MOVEQ	#6,D0			;0308: 7006
	;BSR.W	cd_drive_unsupported		;030a: 61001d6a
	;BMI.S	RNL_0018		;030e: 6b12
	;MOVE.L	D2,D1			;0310: 2202
	;BRA.S	RNL_0018		;0312: 600e
RNL_0017:
	MOVEA.L	buffer_512_2(A6),A0		;0314: 206e0024
	BSR.W	read_file_meta_info		;0318: 61000870
	BMI.S	RNL_0018		;031c: 6b04
	MOVE.L	st_size(A0),D1		;031e: 22280144
RNL_0018:
	MOVEM.L	(A7)+,D2/A0		;0322: 4cdf0104
	RTS				;0326: 4e75
cd_drive_unsupported:
	blitz
	nop
	nop
	illegal
nvm_unsupported
	illegal
	nop
	
command_12_partial_read:
	move.l	d1,current_file_read_start_offset(a6)
	move.l	d2,current_file_read_size(a6)
	bra	generic_read
	
command_0_read:
	clr.l	current_file_read_start_offset(a6)
	move.l	#-1,current_file_read_size(a6)		; -1: all file
	
generic_read:
	CMPI.B	#FLOPPY_DRIVE_TYPE,drive_type(A6)		;0328: 0c2e004600d3
	BEQ.S	floppy_or_hard_drive_read		;032e: 671e
	CMPI.B	#HARD_DRIVE_TYPE,drive_type(A6)		;0330: 0c2e004800d3
	BEQ.S	floppy_or_hard_drive_read		;0336: 6716
	LEA	325(A6),A0		;0338: 41ee0145
	MOVEQ	#5,D0			;033c: 7005
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;033e: 0c2e004400d3
	BEQ.W	cd_drive_unsupported		;0344: 67001d30
	bra.b	nvm_unsupported
;	MOVEQ	#0,D0			;0348: 7000
;	BRA.W	nvm_unsupported		;034a: 60002e76

; < A0: filename
; < A1: load location
floppy_or_hard_drive_read:
	MOVEM.L	D1-D6/A0-A4,-(A7)	;034e: 48e77ef8
	CLR.L	(A7)			;0352: 4297
	TST.W	D0			;0354: 4a40	; command, probably always 0
	BNE.S	RNL_001B		;0356: 6620
	MOVE.L	A1,inout_data_buffer(A6)		;0358: 2d490014
	MOVEA.L	buffer_512_2(A6),A0		;035c: 206e0024
	BSR.W	read_file_meta_info		;0360: 61000828
	BMI.W	RNL_0022_read_failure		;0364: 6b0000c0
	MOVE.L	st_size(A0),current_file_size(A6)		;0368: 2d680144000c
	
	move.l	#-31,d0		; new "seek error" code (JOTD)
	; reduce the length to read
	; the aim is to fool the original routine into believing that the file is shorter
	; when we just want to read less from it and not at the start
	move.l	current_file_read_start_offset(a6),d0
	sub.l	D0,current_file_size(A6)
	bmi.W	RNL_0022_read_failure
	tst.l	current_file_read_size(A6)
	bmi.b	.size_not_specified
	; set to current file size
	move.l	current_file_read_size(A6),current_file_size(A6)
.size_not_specified:
	; TODO: understand the "extended" stuff to read a file bigger than 35kb (OFS)
	; and figure out a way to "seek" to the offset to start reading from
	
	MOVEA.L	A0,A1			;036e: 2248
	CLR.L	508(A1)			;0370: 42a901fc
	; A2 points to the end of data blocks
	LEA	312(A1),A2		;0374: 45e90138
RNL_001B:
	MOVEA.L	A1,A4			;0378: 2849
	BSR.W	get_next_datablock_pointer		;037a: 6100010c
	BNE.W	RNL_0022_read_failure		;037e: 660000a6
	; here's the file read loop
	; reading block after block
RNL_001C_process_next_block:
;	blitz	; TEMP TEMP
;	nop
	MOVE.L	D1,D2			;0382: 2401
	MOVE.L	D1,D4			;0384: 2801
	MOVE.L	inout_data_buffer(A6),D0		;0386: 202e0014
	ADDQ.L	#1,D0			;038a: 5280
	ANDI.B	#$fe,D0			;038c: 020000fe	; align to highest even address
	MOVEA.L	D0,A3			;0390: 2640
	; divide file size by 512 (size of a read block)
	; to see how many blocks we need to read to fully read
	; the file
	MOVE.L	current_file_size(A6),D6		;0392: 2c2e000c
	MOVEQ	#9,D0			;0396: 7009
	LSR.L	D0,D6			;0398: e0ae
	BNE.S	RNL_001D_bigger_than_datablock_size_bytes		;039a: 6612
	MOVEA.L	buffer_512_2(A6),A3		;039c: 266e0024
	MOVE.L	current_file_size(A6),D0		;03a0: 202e000c
	CMP.L	datablock_size(A6),D0		;03a4: b0ae0054
	BHI.S	RNL_001D_bigger_than_datablock_size_bytes		;03a8: 6204
	; less than datablock size: only one block to read
	; into the 512 bytes buffer else it could overwrite user memory
	; (if not changed, uses user-defined buffer, which avoids memory copies)
	ADDQ.L	#1,D2			;03aa: 5282
	BRA.S	RNL_001E_read_sectors		;03ac: 6014
; here if rest to read is > 0x200 (FFS) or 0x1E8 (OFS)
RNL_001D_bigger_than_datablock_size_bytes:
	; D6 now holds the number of block file occupies
	; This routine computes the number of sectors to read at once
	; by checking that the track numbers are consecutive. Bigger read = faster read
	; with a max of 0x9000 bytes per file header (without extended block) in FFS
	; OFS: (0x80-56) * (0x200-6*4) = 0x8940 bytes
	BSR.W	get_next_datablock_pointer		;03ae: 610000d8
	BNE.S	RNL_0022_read_failure		;03b2: 6672
	ADDQ.L	#1,D2			;03b4: 5282
	MOVE.L	D1,D5			;03b6: 2a01
	BEQ.S	RNL_001E_read_sectors			;03b8: 6708
	CMP.L	D1,D2			;03ba: b481
	BNE.S	RNL_001E_read_sectors			;03bc: 6604
	SUBQ.L	#1,D6			;03be: 5386
	BGT.S	RNL_001D_bigger_than_datablock_size_bytes		;03c0: 6eec
	; here we should add read_offset/block_size and add it to D4 TODO
RNL_001E_read_sectors:
	; another thing which isn't supported, is the offset when non-aligned with block size TODO
	; which requires that first block is read in a separate buffer (like the last one), then partially
	; copied to the start of the user buffer
	
	MOVE.L	D4,D1			;03c2: 2204	; position
	SUB.L	D4,D2			;03c4: 9484	; number of blocks to read
	MOVEA.L	A3,A0			;03c6: 204b	; buffer
	BSR.W	read_disk_sectors_raw		;03c8: 61000b3a
	BMI.S	RNL_0022_read_failure		;03cc: 6b58
	MOVEA.L	inout_data_buffer(A6),A1		;03ce: 226e0014
	; OFS or FFS (block size differs so does read method probably)
	CMPI.L	#$444f5300,(A6)		;03d2: 0c96444f5300
	BEQ.S	RNL_001F_OFS		;03d8: 671c
	; FFS blocks just contain data, nothing else
	MOVE.L	current_file_size(A6),D0		;03da: 202e000c
	CMPI.L	#$00000200,D0		;03de: 0c8000000200
	BCS.S	RNL_0020		;03e4: 6524
	MOVEQ	#9,D0			;03e6: 7009
	LSL.L	D0,D2			;03e8: e1aa
	SUB.L	D2,current_file_size(A6)		;03ea: 95ae000c
	ADD.L	D2,inout_data_buffer(A6)		;03ee: d5ae0014
	ADD.L	D2,(A7)			;03f2: d597	; adds to returned size too
	BRA.S	RNL_0021		;03f4: 6024
RNL_001F_OFS:
	; OFS needs extra processing, since sectors have headers that need checking + removing
	BSR.W	RNL_00AB		;03f6: 61000ab4
	BMI.S	RNL_0022_read_failure		;03fa: 6b2a
	MOVE.L	12(A0),D0		;03fc: 2028000c
	CMP.L	current_file_size(A6),D0		;0400: b0ae000c
	BCS.S	RNL_0020		;0404: 6504
	MOVE.L	current_file_size(A6),D0		;0406: 202e000c
RNL_0020:
	BSR.S	copy_a_block		;040a: 6122
	SUB.L	D0,current_file_size(A6)		;040c: 91ae000c
	ADD.L	D0,(A7)			;0410: d197
	SUBQ.L	#1,D2			;0412: 5382
	BNE.S	RNL_001F_OFS		;0414: 66e0
	MOVE.L	A1,inout_data_buffer(A6)		;0416: 2d490014
RNL_0021:
	MOVEA.L	A4,A1			;041a: 224c
	MOVE.L	D5,D1			;041c: 2205
	MOVE.L	current_file_size(A6),D0		;041e: 202e000c
	BNE.W	RNL_001C_process_next_block		;0422: 6600ff5e
RNL_0022_read_failure:
	TST.L	D0			;0426: 4a80
	MOVEM.L	(A7)+,D1-D6/A0-A4	;0428: 4cdf1f7e
	RTS				;042c: 4e75
copy_a_block:
	LEA	512(A0),A0		;042e: 41e80200
	SUBA.L	datablock_size(A6),A0		;0432: 91ee0054
RNL_0024:
	MOVE.L	D0,-(A7)		;0436: 2f00
	MOVE.W	A0,-(A7)		;0438: 3f08
	ANDI.W	#$0001,(A7)+		;043a: 025f0001
	BNE.S	RNL_002A		;043e: 6640
	MOVE.W	A1,-(A7)		;0440: 3f09
	ANDI.W	#$0001,(A7)+		;0442: 025f0001
	BNE.S	RNL_002A		;0446: 6638
	SUBI.W	#$0030,D0		;0448: 04400030
	BCS.S	quick_memory_copy_1		;044c: 651a
	MOVEM.L	D1-D7/A2-A6,-(A7)	;044e: 48e77f3e
RNL_0025:
	MOVEM.L	(A0)+,D1-D7/A2-A6	;0452: 4cd87cfe
	MOVEM.L	D1-D7/A2-A6,(A1)	;0456: 48d17cfe
	LEA	48(A1),A1		;045a: 43e90030
	SUBI.W	#$0030,D0		;045e: 04400030
	BCC.S	RNL_0025		;0462: 64ee
	MOVEM.L	(A7)+,D1-D7/A2-A6	;0464: 4cdf7cfe
quick_memory_copy_1:
	ADDI.W	#$0030,D0		;0468: 06400030
	BEQ.S	RNL_002B		;046c: 6716
	SUBQ.W	#4,D0			;046e: 5940
	BCS.S	RNL_0028		;0470: 6506
RNL_0027:
	MOVE.L	(A0)+,(A1)+		;0472: 22d8
	SUBQ.W	#4,D0			;0474: 5940
	BCC.S	RNL_0027		;0476: 64fa
RNL_0028:
	ADDQ.W	#4,D0			;0478: 5840
	BEQ.S	RNL_002B		;047a: 6708
	BRA.S	RNL_002A		;047c: 6002
RNL_0029:
	MOVE.B	(A0)+,(A1)+		;047e: 12d8
RNL_002A:
	DBF	D0,RNL_0029		;0480: 51c8fffc
RNL_002B:
	MOVE.L	(A7)+,D0		;0484: 201f
	RTS				;0486: 4e75
	

; < A1: stat structure (data is in/out)
; < A2 (in/out): pointer on datablock top (next accessed by -(A2))
; seems that offset >= 508 is used by the RN routine itself to track down file position/read status
; > D1 datablock pointer
;
; handles extension block too transparently, no need to worry about it outside this routine
;
get_next_datablock_pointer:
	MOVE.L	8(A1),D0		;0488: 20290008  high_seq
	SUB.L	508(A1),D0		;048c: 90a901fc
	BNE.S	RNL_002D		;0490: 6616
	MOVE.L	504(A1),D1		;0492: 222901f8	pointer to 1st file extension block
	BEQ.S	RNL_002E		;0496: 6718
	MOVEA.L	A1,A0			;0498: 2049
	BSR.W	read_disk_sector_and_check		;049a: 61000a0c
	BMI.S	RNL_002E		;049e: 6b10
	CLR.L	508(A1)			;04a0: 42a901fc
	LEA	312(A1),A2		;04a4: 45e90138	; init A2 to first datablock; else use existing A2
RNL_002D:
	; return next datablock pointer in D1
	MOVE.L	-(A2),D1		;04a8: 2222
	ADDQ.B	#1,511(A1)		;04aa: 522901ff
	MOVEQ	#0,D0			;04ae: 7000
RNL_002E:
	RTS				;04b0: 4e75
	
	
	MOVEQ	#-2,D0			;04b2: 70fe
command_1_write:
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;04b4: 0c2e004400d3
	BEQ.W	RNL_003F		;04ba: 670001c6
	MOVEQ	#1,D0			;04be: 7001
	CMPI.B	#'V',drive_type(A6)		;04c0: 0c2e005600d3
	BEQ.W	nvm_unsupported		;04c6: 67002cfa
	MOVEM.L	D1-D6/A0-A5,-(A7)	;04ca: 48e77efc
	MOVE.L	D1,current_file_size(A6)		;04ce: 2d41000c
	MOVE.L	A1,inout_data_buffer(A6)		;04d2: 2d490014
	BSR.W	RNL_0043		;04d6: 610001ec
	BEQ.S	RNL_002F		;04da: 6712
	CMPI.L	#$ffffffe8,D0		;04dc: 0c80ffffffe8
	BNE.W	RNL_003E		;04e2: 6600019a
	BSR.W	RNL_0096		;04e6: 6100080a
	BMI.W	RNL_003E		;04ea: 6b000192
RNL_002F:
	MOVEA.L	buffer_512_2(A6),A4		;04ee: 286e0024
	MOVEA.L	inout_data_buffer(A6),A5		;04f2: 2a6e0014
	CMPI.L	#$444f5301,(A6)		;04f6: 0c96444f5301
	BEQ.S	RNL_0030		;04fc: 6704
	MOVEA.L	48(A6),A5		;04fe: 2a6e0030
RNL_0030:
	MOVEQ	#2,D0			;0502: 7002
	MOVE.L	D0,(A4)			;0504: 2880
	MOVE.L	current_file_size(A6),324(A4)		;0506: 296e000c0144
	MOVEA.L	A4,A0			;050c: 204c
	BSR.W	RNL_0058		;050e: 610002d8
	MOVE.L	52(A6),500(A4)		;0512: 296e003401f4
	MOVEQ	#-3,D0			;0518: 70fd
	MOVE.L	D0,508(A4)		;051a: 294001fc
	MOVEQ	#1,D0			;051e: 7001
	MOVE.L	D0,88(A6)		;0520: 2d400058
	MOVEQ	#2,D6			;0524: 7c02
	BSR.W	RNL_0049		;0526: 610001fc
	BMI.W	RNL_003E		;052a: 6b000152
	MOVE.L	D0,80(A6)		;052e: 2d400050
	MOVE.L	D0,4(A4)		;0532: 29400004
	MOVE.L	current_file_size(A6),D1		;0536: 222e000c
	MOVE.L	datablock_size(A6),D2		;053a: 242e0054
	MULU	#$0048,D2		;053e: c4fc0048
RNL_0031:
	BSR.W	RNL_0049		;0542: 610001e0
	BMI.W	RNL_003E		;0546: 6b000136
	ADDQ.L	#1,D6			;054a: 5286
	SUB.L	D2,D1			;054c: 9282
	BHI.S	RNL_0031		;054e: 62f2
	MOVEQ	#0,D3			;0550: 7600
	MOVEQ	#0,D4			;0552: 7800
	MOVE.L	D6,D5			;0554: 2a06
	BRA.S	RNL_0033		;0556: 6008
RNL_0032:
	MOVEQ	#72,D0			;0558: 7048
	CMP.L	8(A4),D0		;055a: b0ac0008
	BNE.S	RNL_0034		;055e: 661c
RNL_0033:
	MOVE.L	4(A4),D6		;0560: 2c2c0004
	BSR.W	RNL_0049		;0564: 610001be
	BSR.W	RNL_0056		;0568: 61000246
	MOVE.L	D6,4(A4)		;056c: 29460004
	CLR.L	8(A4)			;0570: 42ac0008
	CLR.L	504(A4)			;0574: 42ac01f8
	LEA	312(A4),A2		;0578: 45ec0138
RNL_0034:
	MOVE.L	D5,D6			;057c: 2c05
	BSR.W	RNL_0051		;057e: 61000200
	BMI.W	RNL_003E		;0582: 6b0000fa
	CMP.L	D3,D4			;0586: b883
	BNE.S	RNL_0036		;0588: 6618
	MOVE.L	D6,D5			;058a: 2a06
	MOVEQ	#0,D3			;058c: 7600
	MOVEA.L	A5,A1			;058e: 224d
	CMPI.L	#$444f5301,(A6)		;0590: 0c96444f5301
	BEQ.S	RNL_0035		;0596: 6708
	MOVE.L	68(A6),D4		;0598: 282e0044
	CMP.L	D4,D1			;059c: b284
	BGE.S	RNL_0036		;059e: 6c02
RNL_0035:
	MOVE.L	D1,D4			;05a0: 2801
RNL_0036:
	MOVE.L	D6,-(A2)		;05a2: 2506
	MOVE.L	D6,D0			;05a4: 2006
	BSR.W	RNL_0056		;05a6: 61000208
	ADDQ.L	#1,D6			;05aa: 5286
	MOVE.L	datablock_size(A6),D0		;05ac: 202e0054
	CMP.L	current_file_size(A6),D0		;05b0: b0ae000c
	BCS.S	RNL_0037		;05b4: 6504
	MOVE.L	current_file_size(A6),D0		;05b6: 202e000c
RNL_0037:
	MOVEA.L	A1,A3			;05ba: 2649
	CMPI.L	#$444f5301,(A6)		;05bc: 0c96444f5301
	BEQ.S	RNL_0038		;05c2: 672a
	MOVE.L	#$00000008,(A1)+	;05c4: 22fc00000008
	MOVE.L	4(A4),(A1)+		;05ca: 22ec0004
	MOVE.L	88(A6),(A1)+		;05ce: 22ee0058
	MOVE.L	D0,(A1)+		;05d2: 22c0
	MOVE.L	D6,(A1)+		;05d4: 22c6
	CLR.L	(A1)+			;05d6: 4299
	MOVEA.L	inout_data_buffer(A6),A0		;05d8: 206e0014
	BSR.W	RNL_0024		;05dc: 6100fe58
	MOVEA.L	A3,A0			;05e0: 204b
	MOVE.L	D0,-(A7)		;05e2: 2f00
	BSR.W	compute_block_checksum		;05e4: 610008ce
	; store checksum in block (must be write operation)
	MOVE.L	D0,20(A0)		;05e8: 21400014
	MOVE.L	(A7)+,D0		;05ec: 201f
RNL_0038:
	SUB.L	D0,current_file_size(A6)		;05ee: 91ae000c
	ADD.L	D0,inout_data_buffer(A6)		;05f2: d1ae0014
	ADDQ.L	#1,D3			;05f6: 5283
	MOVEQ	#1,D0			;05f8: 7001
	ADD.L	D0,88(A6)		;05fa: d1ae0058
	ADD.L	D0,8(A4)		;05fe: d1ac0008
	TST.L	current_file_size(A6)			;0602: 4aae000c
	BEQ.S	RNL_003A		;0606: 671a
	MOVEQ	#72,D0			;0608: 7048
	CMP.L	8(A4),D0		;060a: b0ac0008
	BEQ.S	RNL_0039		;060e: 6706
	CMP.L	D3,D4			;0610: b883
	BNE.S	RNL_0036		;0612: 668e
	BRA.S	RNL_003B		;0614: 6024
RNL_0039:
	MOVE.L	4(A4),D6		;0616: 2c2c0004
	BSR.W	RNL_0049		;061a: 61000108
	MOVE.L	D6,504(A4)		;061e: 294601f8
RNL_003A:
	MOVEA.L	A4,A0			;0622: 204c
	MOVE.L	308(A0),D0		;0624: 20280134
	MOVE.L	D0,16(A0)		;0628: 21400010
	MOVE.L	4(A0),D1		;062c: 22280004
	BSR.W	RNL_00B0		;0630: 610008a2
	BMI.S	RNL_003E		;0634: 6b48
	MOVEQ	#16,D0			;0636: 7010
	MOVE.L	D0,(A0)			;0638: 2080
RNL_003B:
	MOVE.L	current_file_size(A6),D0		;063a: 202e000c
	BEQ.S	RNL_003C		;063e: 670e
	CMP.L	D3,D4			;0640: b883
	BNE.W	RNL_0032		;0642: 6600ff14
	MOVE.L	D5,D6			;0646: 2c05
	BSR.W	RNL_0049		;0648: 610000da
	MOVE.L	D6,D0			;064c: 2006
RNL_003C:
	CMPI.L	#$444f5301,(A6)		;064e: 0c96444f5301
	BEQ.S	RNL_003D		;0654: 6712
	MOVEA.L	A3,A0			;0656: 204b
	MOVE.L	D0,16(A0)		;0658: 21400010
	CLR.L	20(A0)			;065c: 42a80014
	BSR.W	compute_block_checksum		;0660: 61000852
	MOVE.L	D0,20(A0)		;0664: 21400014
RNL_003D:
	MOVE.L	D5,D1			;0668: 2205
	MOVE.L	D3,D2			;066a: 2403
	MOVEA.L	A5,A0			;066c: 204d
	BSR.W	RNL_00B2		;066e: 61000876
	BMI.S	RNL_003E		;0672: 6b0a
	TST.L	current_file_size(A6)			;0674: 4aae000c
	BNE.W	RNL_0032		;0678: 6600fede
	BSR.S	RNL_0040		;067c: 6106
RNL_003E:
	MOVEM.L	(A7)+,D1-D6/A0-A5	;067e: 4cdf3f7e
RNL_003F:
	RTS				;0682: 4e75
RNL_0040:
	MOVEM.L	D1-D2/A0,-(A7)		;0684: 48e76080
	MOVE.L	72(A6),D1		;0688: 222e0048
	MOVEA.L	buffer_512_2(A6),A0		;068c: 206e0024
	BSR.W	read_disk_sector_and_check		;0690: 61000816
	BMI.S	RNL_0042		;0694: 6b28
	MOVE.L	80(A6),D0		;0696: 202e0050
	MOVE.L	76(A6),D2		;069a: 242e004c
	MOVE.L	D0,0(A0,D2.W)		;069e: 21802000
	BSR.W	RNL_00B0		;06a2: 61000830
	BMI.S	RNL_0042		;06a6: 6b16
	MOVE.L	80(A6),D0		;06a8: 202e0050
	BEQ.S	RNL_0041		;06ac: 670c
	MOVE.L	D0,72(A6)		;06ae: 2d400048
	MOVE.L	#$000001f0,76(A6)	;06b2: 2d7c000001f0004c
RNL_0041:
	BSR.W	RNL_0097		;06ba: 61000652
RNL_0042:
	MOVEM.L	(A7)+,D1-D2/A0		;06be: 4cdf0106
	RTS				;06c2: 4e75
RNL_0043:
	MOVEQ	#-2,D0			;06c4: 70fe
command_2_probably_delete:
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;06c6: 0c2e004400d3
	BEQ.S	RNL_0048		;06cc: 6754
	MOVEQ	#2,D0			;06ce: 7002
	CMPI.B	#'V',drive_type(A6)		;06d0: 0c2e005600d3
	BEQ.W	nvm_unsupported		;06d6: 67002aea
	MOVEM.L	D1/A0-A1,-(A7)		;06da: 48e740c0
	MOVEA.L	buffer_512_2(A6),A0		;06de: 206e0024
	BSR.W	read_file_meta_info		;06e2: 610004a6
	BMI.S	RNL_0047		;06e6: 6b36
	BSR.W	RNL_0096		;06e8: 61000608
	BMI.S	RNL_0047		;06ec: 6b30
RNL_0044:
	MOVE.L	D1,D0			;06ee: 2001
	BSR.W	RNL_0057		;06f0: 610000da
	MOVEA.L	buffer_512_2(A6),A0		;06f4: 206e0024
	LEA	312(A0),A1		;06f8: 43e80138
	MOVE.L	8(A0),D1		;06fc: 22280008
	SUBQ.L	#1,D1			;0700: 5381
RNL_0045:
	MOVE.L	-(A1),D0		;0702: 2021
	BSR.W	RNL_0057		;0704: 610000c6
	DBF	D1,RNL_0045		;0708: 51c9fff8
	MOVE.L	504(A0),D1		;070c: 222801f8
	BEQ.S	RNL_0046		;0710: 6708
	BSR.W	read_disk_sector_and_check		;0712: 61000794
	BMI.S	RNL_0047		;0716: 6b06
	BRA.S	RNL_0044		;0718: 60d4
RNL_0046:
	BSR.W	RNL_0040		;071a: 6100ff68
RNL_0047:
	MOVEM.L	(A7)+,D1/A0-A1		;071e: 4cdf0302
RNL_0048:
	RTS				;0722: 4e75
RNL_0049:
	MOVEM.L	D1-D3/A0,-(A7)		;0724: 48e77080
	MOVE.L	8(A6),D3		;0728: 262e0008
	SUB.L	D6,D3			;072c: 9686
	BEQ.S	RNL_004E		;072e: 6744
RNL_004A:
	MOVE.L	D6,D0			;0730: 2006
	BSR.W	RNL_009B		;0732: 6100061c
	MOVE.L	0(A0,D0.W),D2		;0736: 24300000
	LSR.L	D1,D2			;073a: e2aa
	BNE.S	RNL_004D		;073c: 662c
	SUBI.L	#$00000020,D1		;073e: 048100000020
	NEG.L	D1			;0744: 4481
	ADD.L	D1,D6			;0746: dc81
	SUB.L	D1,D3			;0748: 9681
	BRA.S	RNL_004C		;074a: 6012
RNL_004B:
	MOVE.L	0(A0,D0.W),D2		;074c: 24300000
	BNE.S	RNL_004D		;0750: 6618
	ADDI.L	#$00000020,D6		;0752: 068600000020
	SUBI.L	#$00000020,D3		;0758: 048300000020
RNL_004C:
	BLS.S	RNL_004E		;075e: 6314
	ADDQ.W	#4,D0			;0760: 5840
	CMPI.W	#$0200,D0		;0762: 0c400200
	BNE.S	RNL_004B		;0766: 66e4
	BRA.S	RNL_004A		;0768: 60c6
RNL_004D:
	ROR.L	#1,D2			;076a: e29a
	BCS.S	RNL_004F		;076c: 650a
	ADDQ.L	#1,D6			;076e: 5286
	SUBQ.L	#1,D3			;0770: 5383
	BNE.S	RNL_004D		;0772: 66f6
RNL_004E:
	MOVEQ	#-26,D0			;0774: 70e6
	BRA.S	RNL_0050		;0776: 6002
RNL_004F:
	MOVE.L	D6,D0			;0778: 2006
RNL_0050:
	MOVEM.L	(A7)+,D1-D3/A0		;077a: 4cdf010e
	RTS				;077e: 4e75
RNL_0051:
	MOVEQ	#0,D1			;0780: 7200
	BSR.S	RNL_0049		;0782: 61a0
	BMI.S	RNL_0054		;0784: 6b14
	MOVE.L	D6,D0			;0786: 2006
RNL_0052:
	ADDQ.L	#1,D1			;0788: 5281
	ADDQ.L	#1,D0			;078a: 5280
	CMP.L	8(A6),D0		;078c: b0ae0008
	BEQ.S	RNL_0053		;0790: 6704
	BSR.S	RNL_0055		;0792: 6108
	BNE.S	RNL_0052		;0794: 66f2
RNL_0053:
	MOVE.L	D6,D0			;0796: 2006
	TST.L	D1			;0798: 4a81
RNL_0054:
	RTS				;079a: 4e75
RNL_0055:
	MOVEM.L	D0-D1/A0,-(A7)		;079c: 48e7c080
	BSR.W	RNL_009B		;07a0: 610005ae
	MOVE.L	0(A0,D0.W),D0		;07a4: 20300000
	BTST	D1,D0			;07a8: 0300
	MOVEM.L	(A7)+,D0-D1/A0		;07aa: 4cdf0103
	RTS				;07ae: 4e75
RNL_0056:
	MOVEM.L	D0-D2/A0,-(A7)		;07b0: 48e7e080
	BSR.W	RNL_009B		;07b4: 6100059a
	MOVE.L	0(A0,D0.W),D2		;07b8: 24300000
	BCLR	D1,D2			;07bc: 0382
	MOVE.L	D2,0(A0,D0.W)		;07be: 21820000
	ORI.B	#$80,(A0)		;07c2: 00100080
	MOVEM.L	(A7)+,D0-D2/A0		;07c6: 4cdf0107
	RTS				;07ca: 4e75
RNL_0057:
	MOVEM.L	D0-D2/A0,-(A7)		;07cc: 48e7e080
	BSR.W	RNL_009B		;07d0: 6100057e
	MOVE.L	0(A0,D0.W),D2		;07d4: 24300000
	BSET	D1,D2			;07d8: 03c2
	MOVE.L	D2,0(A0,D0.W)		;07da: 21820000
	ORI.B	#$80,(A0)		;07de: 00100080
	MOVEM.L	(A7)+,D0-D2/A0		;07e2: 4cdf0107
	RTS				;07e6: 4e75
RNL_0058:
	MOVEM.L	A1-A2,-(A7)		;07e8: 48e70060
	LEA	433(A0),A1		;07ec: 43e801b1
	MOVEA.L	file_or_dir_name(A6),A2		;07f0: 246e0010
	MOVEQ	#-1,D0			;07f4: 70ff
RNL_0059:
	ADDQ.B	#1,D0			;07f6: 5200
	CMPI.B	#$1e,D0			;07f8: 0c00001e
	BEQ.S	RNL_005A		;07fc: 6704
	MOVE.B	(A2)+,(A1)+		;07fe: 12da
	BNE.S	RNL_0059		;0800: 66f4
RNL_005A:
	MOVE.B	D0,432(A0)		;0802: 114001b0
	MOVEM.L	(A7)+,A1-A2		;0806: 4cdf0600
	RTS				;080a: 4e75
	MOVEM.L	D2-D3/A0-A3,-(A7)	;080c: 48e730f0
	MOVEQ	#-2,D0			;0810: 70fe
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;0812: 0c2e004400d3
	BEQ.S	RNL_0060		;0818: 6758
	MOVEA.L	buffer_512_2(A6),A0		;081a: 206e0024
	BSR.W	read_dir_meta_info		;081e: 61000366
	BMI.S	RNL_0060		;0822: 6b4e
	MOVEQ	#0,D2			;0824: 7400
	MOVEQ	#0,D3			;0826: 7600
	MOVEA.L	A0,A3			;0828: 2648
RNL_005B:
	MOVE.L	24(A3,D2.W),D1		;082a: 22332018
	BEQ.S	RNL_005F		;082e: 6736
	MOVEA.L	48(A6),A0		;0830: 206e0030
RNL_005C:
	BSR.W	read_disk_sector_and_check		;0834: 61000672
	BMI.S	RNL_0060		;0838: 6b38
	MOVEQ	#2,D0			;083a: 7002
	CMP.L	(A0),D0			;083c: b090
	BNE.S	RNL_005F		;083e: 6626
	MOVEQ	#-3,D0			;0840: 70fd
	CMP.L	508(A0),D0		;0842: b0a801fc
	BEQ.S	RNL_005D		;0846: 6708
	MOVEQ	#2,D0			;0848: 7002
	CMP.L	508(A0),D0		;084a: b0a801fc
	BNE.S	RNL_005F		;084e: 6616
RNL_005D:
	MOVE.B	D0,(A1)+		;0850: 12c0
	LEA	432(A0),A2		;0852: 45e801b0
	MOVEQ	#30,D0			;0856: 701e
RNL_005E:
	MOVE.B	(A2)+,(A1)+		;0858: 12da
	DBF	D0,RNL_005E		;085a: 51c8fffc
	ADDQ.L	#1,D3			;085e: 5283
	MOVE.L	496(A0),D1		;0860: 222801f0
	BNE.S	RNL_005C		;0864: 66ce
RNL_005F:
	ADDQ.W	#4,D2			;0866: 5842
	CMPI.W	#$0120,D2		;0868: 0c420120
	BNE.S	RNL_005B		;086c: 66bc
	MOVE.L	D3,D1			;086e: 2203
	MOVEQ	#0,D0			;0870: 7000
RNL_0060:
	MOVEM.L	(A7)+,D2-D3/A0-A3	;0872: 4cdf0f0c
	RTS				;0876: 4e75
	MOVEQ	#-2,D0			;0878: 70fe
command_7_unknown
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;087a: 0c2e004400d3
	BEQ.S	RNL_0064		;0880: 6758
	MOVEM.L	D1/A0-A1,-(A7)		;0882: 48e740c0
	MOVE.L	A1,inout_data_buffer(A6)		;0886: 2d490014
	MOVEQ	#1,D2			;088a: 7401
	LEA	114(A6),A1		;088c: 43ee0072
RNL_0061:
	TST.L	16(A1)			;0890: 4aa90010
	BNE.S	RNL_0062		;0894: 6630
	MOVEA.L	inout_data_buffer(A6),A0		;0896: 206e0014
	BSR.W	read_file_meta_info		;089a: 610002ee
	BMI.S	RNL_0062		;089e: 6b26
	MOVE.L	4(A6),(A1)		;08a0: 22ae0004
	CLR.L	4(A1)			;08a4: 42a90004
	MOVEQ	#-1,D0			;08a8: 70ff
	MOVE.L	D0,8(A1)		;08aa: 23400008
	CLR.L	12(A1)			;08ae: 42a9000c
	MOVE.L	inout_data_buffer(A6),16(A1)		;08b2: 236e00140010
	MOVE.L	st_size(A0),D0		;08b8: 20280144
	MOVE.L	D0,20(A1)		;08bc: 23400014
	MOVE.L	D2,D1			;08c0: 2202
	MOVEQ	#0,D0			;08c2: 7000
	BRA.S	RNL_0063		;08c4: 6010
RNL_0062:
	LEA	24(A1),A1		;08c6: 43e90018
	ADDQ.B	#1,D2			;08ca: 5202
	CMPI.B	#$04,D2			;08cc: 0c020004
	BLE.S	RNL_0061		;08d0: 6fbe
	; error????
	MOVEQ	#0,D1			;08d2: 7200
	MOVEQ	#-28,D0			;08d4: 70e4
RNL_0063:
	MOVEM.L	(A7)+,D2/A0-A1		;08d6: 4cdf0304
RNL_0064:
	RTS				;08da: 4e75
	MOVEQ	#-2,D0			;08dc: 70fe
command_8_unknown
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;08de: 0c2e004400d3
	BEQ.S	RNL_0066		;08e4: 670e
	MOVE.L	A0,-(A7)		;08e6: 2f08
	BSR.W	RNL_0076		;08e8: 61000184
	BMI.S	RNL_0065		;08ec: 6b04
	CLR.L	16(A0)			;08ee: 42a80010
RNL_0065:
	MOVEA.L	(A7)+,A0		;08f2: 205f
RNL_0066:
	RTS				;08f4: 4e75
	MOVEQ	#-2,D0			;08f6: 70fe
command_10_unknown
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;08f8: 0c2e004400d3
	BEQ.S	RNL_0069		;08fe: 6718
	MOVE.L	A0,-(A7)		;0900: 2f08
	BSR.W	RNL_0076		;0902: 6100016a
	BMI.S	RNL_0068		;0906: 6b0e
	CMP.L	20(A0),D2		;0908: b4a80014
	BLE.S	RNL_0067		;090c: 6f04
	MOVE.L	20(A0),D2		;090e: 24280014
RNL_0067:
	MOVE.L	D2,12(A0)		;0912: 2142000c
RNL_0068:
	MOVEA.L	(A7)+,A0		;0916: 205f
RNL_0069:
	RTS				;0918: 4e75
	MOVEQ	#-2,D0			;091a: 70fe
command_9_unknown
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;091c: 0c2e004400d3
	BEQ.W	RNL_0073		;0922: 6700010a
	MOVEM.L	D1-D6/A0-A3,-(A7)	;0926: 48e77ef0
	CLR.L	4(A7)			;092a: 42af0004
	MOVE.L	A0,inout_data_buffer(A6)		;092e: 2d480014
	BSR.W	RNL_0076		;0932: 6100013a
	MOVEA.L	A0,A3			;0936: 2648
	MOVE.L	D2,D6			;0938: 2c02
	MOVE.L	20(A3),D0		;093a: 202b0014
	SUB.L	12(A3),D0		;093e: 90ab000c
	BEQ.W	RNL_0072		;0942: 670000e6
	CMP.L	D6,D0			;0946: b086
	BGE.S	RNL_006A		;0948: 6c02
	MOVE.L	D0,D6			;094a: 2c00
RNL_006A:
	MOVE.L	(A3),4(A6)		;094c: 2d530004
	MOVE.L	12(A3),D0		;0950: 202b000c
	BSR.W	RNL_0074		;0954: 610000da
	MOVEA.L	16(A3),A0		;0958: 206b0010
	MOVE.L	4(A3),D0		;095c: 202b0004
	CMP.L	D0,D2			;0960: b480
	BEQ.S	RNL_006D		;0962: 6730
	ADDQ.L	#1,D0			;0964: 5280
	CMP.L	D0,D2			;0966: b480
	BEQ.S	RNL_006B		;0968: 6714
	CLR.L	4(A3)			;096a: 42ab0004
	MOVE.L	4(A0),D1		;096e: 22280004
	MOVEQ	#2,D0			;0972: 7002
	CMP.L	(A0),D0			;0974: b090
	BEQ.S	RNL_006C		;0976: 670e
	MOVE.L	500(A0),D1		;0978: 222801f4
	BRA.S	RNL_006C		;097c: 6008
RNL_006B:
	MOVE.L	504(A0),D1		;097e: 222801f8
	ADDQ.L	#1,4(A3)		;0982: 52ab0004
RNL_006C:
	BSR.W	read_disk_sector_and_check		;0986: 61000520
	BMI.W	RNL_0072		;098a: 6b00009e
	CMP.L	4(A3),D2		;098e: b4ab0004
	BNE.S	RNL_006B		;0992: 66ea
RNL_006D:
	CMP.L	8(A3),D4		;0994: b8ab0008
	BEQ.S	RNL_0070		;0998: 672c
	MOVE.L	D3,D0			;099a: 2003
	LSL.L	#2,D0			;099c: e588
	MOVE.L	#$00000134,D1		;099e: 223c00000134
	SUB.L	D0,D1			;09a4: 9280
	MOVE.L	0(A0,D1.L),D1		;09a6: 22301800
	LEA	512(A0),A0		;09aa: 41e80200
	CMPI.L	#$444f5301,(A6)		;09ae: 0c96444f5301
	BNE.S	RNL_006E		;09b4: 6606
	BSR.W	read_disk_sector_raw		;09b6: 61000536
	BRA.S	RNL_006F		;09ba: 6004
RNL_006E:
	BSR.W	read_disk_sector_and_check		;09bc: 610004ea
RNL_006F:
	BMI.S	RNL_0072		;09c0: 6b68
	MOVE.L	D4,8(A3)		;09c2: 27440008
RNL_0070:
	MOVEA.L	16(A3),A0		;09c6: 206b0010
	LEA	512(A0),A0		;09ca: 41e80200
	MOVE.L	datablock_size(A6),D0		;09ce: 202e0054
	SUB.L	D5,D0			;09d2: 9085
	ADDA.L	D5,A0			;09d4: d1c5
	CMP.L	D0,D6			;09d6: bc80
	BGE.S	RNL_0071		;09d8: 6c02
	MOVE.L	D6,D0			;09da: 2006
RNL_0071:
	MOVEA.L	inout_data_buffer(A6),A1		;09dc: 226e0014
	BSR.W	copy_a_block		;09e0: 6100fa4c
	SUB.L	D0,D6			;09e4: 9c80
	ADD.L	D0,12(A3)		;09e6: d1ab000c
	ADD.L	D0,4(A7)		;09ea: d1af0004
	MOVE.L	A1,inout_data_buffer(A6)		;09ee: 2d490014
	MOVE.L	D6,D0			;09f2: 2006
	BEQ.S	RNL_0072		;09f4: 6734
	ADDQ.L	#1,D3			;09f6: 5283
	MOVEA.L	16(A3),A1		;09f8: 226b0010
	MOVE.L	D3,508(A1)		;09fc: 234301fc
	LEA	312(A1),A2		;0a00: 45e90138
	LSL.L	#2,D3			;0a04: e58b
	SUBA.L	D3,A2			;0a06: 95c3
	MOVE.L	D6,current_file_size(A6)		;0a08: 2d46000c
	MOVEQ	#12,D0			;0a0c: 700c
	BSR.W	command_0_read		;0a0e: 6100f918
	BMI.S	RNL_0072		;0a12: 6b16
	ADD.L	D1,4(A7)		;0a14: d3af0004
	ADD.L	D1,12(A3)		;0a18: d3ab000c
	MOVE.L	12(A3),D0		;0a1c: 202b000c
	SUBQ.L	#1,D0			;0a20: 5380
	BSR.S	RNL_0074		;0a22: 610c
	MOVE.L	D2,4(A3)		;0a24: 27420004
	MOVEQ	#0,D0			;0a28: 7000
RNL_0072:
	MOVEM.L	(A7)+,D1-D6/A0-A3	;0a2a: 4cdf0f7e
RNL_0073:
	RTS				;0a2e: 4e75
RNL_0074:
	MOVE.L	D0,D4			;0a30: 2800
	ANDI.L	#$000001ff,D0		;0a32: 0280000001ff
	MOVEQ	#9,D5			;0a38: 7a09
	LSR.L	D5,D4			;0a3a: eaac
	MOVE.L	D0,D5			;0a3c: 2a00
	CMPI.L	#$00000200,datablock_size(A6)	;0a3e: 0cae000002000054
	BEQ.S	RNL_0075		;0a46: 6712
	MOVE.L	D4,D5			;0a48: 2a04
	MULU	#$0018,D5		;0a4a: cafc0018
	ADD.L	D0,D5			;0a4e: da80
	DIVU	#$01e8,D5		;0a50: 8afc01e8
	ADD.W	D5,D4			;0a54: d845
	CLR.W	D5			;0a56: 4245
	SWAP	D5			;0a58: 4845
RNL_0075:
	MOVE.L	D4,D2			;0a5a: 2404
	DIVU	#$0048,D2		;0a5c: 84fc0048
	MOVE.L	D2,D3			;0a60: 2602
	CLR.W	D3			;0a62: 4243
	SWAP	D3			;0a64: 4843
	ANDI.L	#$0000ffff,D2		;0a66: 02820000ffff
	RTS				;0a6c: 4e75
RNL_0076:
	MOVEQ	#-29,D0			;0a6e: 70e3
	TST.L	D1			;0a70: 4a81
	BLE.S	RNL_0077		;0a72: 6f14
	MULU	#$0018,D1		;0a74: c2fc0018
	LEA	90(A6,D1.W),A0		;0a78: 41f6105a
	DIVU	#$0018,D1		;0a7c: 82fc0018
	TST.L	16(A0)			;0a80: 4aa80010
	BEQ.S	RNL_0077		;0a84: 6702
	MOVEQ	#0,D0			;0a86: 7000
RNL_0077:
	TST.L	D0			;0a88: 4a80
	RTS				;0a8a: 4e75
RNL_0078:
	MOVEM.L	D0-D7/A1,-(A7)		;0a8c: 48e7ff40
	MOVEQ	#9,D1			;0a90: 7209
	LSL.W	D1,D0			;0a92: e368
	LEA	0(A0,D0.W),A0		;0a94: 41f00000
	LSR.W	#5,D0			;0a98: ea48
	MOVEQ	#0,D1			;0a9a: 7200
	MOVEQ	#0,D2			;0a9c: 7400
	MOVEQ	#0,D3			;0a9e: 7600
	MOVEQ	#0,D4			;0aa0: 7800
	MOVEQ	#0,D5			;0aa2: 7a00
	MOVEQ	#0,D6			;0aa4: 7c00
	MOVEQ	#0,D7			;0aa6: 7e00
	SUBA.L	A1,A1			;0aa8: 93c9
	SUBQ.W	#1,D0			;0aaa: 5340
RNL_0079:
	MOVEM.L	D1-D7/A1,-(A0)		;0aac: 48e07f40
	DBF	D0,RNL_0079		;0ab0: 51c8fffa
	MOVEM.L	(A7)+,D0-D7/A1		;0ab4: 4cdf02ff
	RTS				;0ab8: 4e75
	MOVEQ	#-2,D0			;0aba: 70fe
command_6_unknown
	CMPI.B	#CD32_DRIVE_TYPE,drive_type(A6)		;0abc: 0c2e004400d3
	BEQ.W	RNL_007C		;0ac2: 670000c0
	MOVEQ	#3,D0			;0ac6: 7003
	CMPI.B	#'V',drive_type(A6)		;0ac8: 0c2e005600d3
	BEQ.W	nvm_unsupported		;0ace: 670026f2
	MOVEM.L	D1-D2/A0-A1,-(A7)	;0ad2: 48e760c0
	BSR.W	init_other_pointers		;0ad6: 6100f800
	MOVEQ	#0,D1			;0ada: 7200
	MOVE.L	8(A6),D2		;0adc: 242e0008
	SUBA.L	A0,A0			;0ae0: 91c8
	BSR.W	RNL_00AF		;0ae2: 610003e8
	BMI.W	RNL_007B		;0ae6: 6b000098
	MOVEA.L	buffer_512_1(A6),A0		;0aea: 206e0020
	MOVEQ	#1,D0			;0aee: 7001
	BSR.S	RNL_0078		;0af0: 619a
	MOVEQ	#2,D0			;0af2: 7002
	MOVE.L	D0,(A0)			;0af4: 2080
	MOVEQ	#72,D0			;0af6: 7048
	MOVE.L	D0,12(A0)		;0af8: 2140000c
	MOVEQ	#-1,D0			;0afc: 70ff
	MOVE.L	D0,312(A0)		;0afe: 21400138
	LSR.L	#1,D2			;0b02: e28a
	ADDQ.L	#1,D2			;0b04: 5282
	MOVE.L	D2,316(A0)		;0b06: 2142013c
	BSR.W	RNL_0058		;0b0a: 6100fcdc
	MOVEQ	#1,D0			;0b0e: 7001
	MOVE.L	D0,508(A0)		;0b10: 214001fc
	BSR.W	compute_block_checksum		;0b14: 6100039e
	MOVE.L	D0,20(A0)		;0b18: 21400014
	MOVEA.L	buffer_4(A6),A0		;0b1c: 206e002c
	MOVEQ	#1,D0			;0b20: 7001
	BSR.W	RNL_0078		;0b22: 6100ff68
	MOVEQ	#2,D0			;0b26: 7002
RNL_007A:
	BSR.W	RNL_0057		;0b28: 6100fca2
	ADDQ.L	#1,D0			;0b2c: 5280
	CMP.L	8(A6),D0		;0b2e: b0ae0008
	BNE.S	RNL_007A		;0b32: 66f4
	MOVE.L	8(A6),D0		;0b34: 202e0008
	LSR.L	#1,D0			;0b38: e288
	BSR.W	RNL_0056		;0b3a: 6100fc74
	ADDQ.L	#1,D0			;0b3e: 5280
	BSR.W	RNL_0056		;0b40: 6100fc6e
	BSR.W	compute_block_checksum		;0b44: 6100036e
	MOVE.L	D0,(A0)			;0b48: 2080
	MOVE.L	8(A6),D1		;0b4a: 222e0008
	LSR.L	#1,D1			;0b4e: e289
	MOVEA.L	buffer_512_1(A6),A0		;0b50: 206e0020
	BSR.W	RNL_00B1		;0b54: 61000388
	BMI.S	RNL_007B		;0b58: 6b26
	MOVE.L	D1,56(A6)		;0b5a: 2d410038
	ADDQ.L	#1,D1			;0b5e: 5281
	MOVEA.L	buffer_4(A6),A0		;0b60: 206e002c
	BSR.W	RNL_00B1		;0b64: 61000378
	BMI.S	RNL_007B		;0b68: 6b16
	MOVE.L	D1,60(A6)		;0b6a: 2d41003c
	MOVEA.L	buffer_512_2(A6),A0		;0b6e: 206e0024
	MOVEQ	#1,D0			;0b72: 7001
	BSR.W	RNL_0078		;0b74: 6100ff16
	MOVE.L	(A7),(A0)		;0b78: 2097
	MOVEQ	#0,D1			;0b7a: 7200
	BSR.W	RNL_00B1		;0b7c: 61000360
RNL_007B:
	MOVEM.L	(A7)+,D1-D2/A0-A1	;0b80: 4cdf0306
RNL_007C:
	RTS				;0b84: 4e75
	
read_dir_meta_info:
	MOVEQ	#1,D0			;0b86: 7001
	BRA.S	RNL_007F		;0b88: 6002

; < A0: file info 512 bytes buffer
; < A6: points on locals, where filename is already stored
read_file_meta_info:
	MOVEQ	#0,D0			;0b8a: 7000
RNL_007F:
	MOVEM.L	D2/A1-A4,-(A7)		;0b8c: 48e72078
	MOVEA.L	A0,A4			;0b90: 2848
	MOVE.L	D0,-(A7)		;0b92: 2f00
	MOVE.L	file_or_dir_name(A6),-(A7)		;0b94: 2f2e0010
	BSR.W	RNL_0091		;0b98: 61000112
	BMI.W	RNL_0087		;0b9c: 6b00008e
RNL_0080:
	MOVE.L	D1,52(A6)		;0ba0: 2d410034
	MOVE.L	file_or_dir_name(A6),(A7)		;0ba4: 2eae0010
	BSR.W	RNL_0088		;0ba8: 61000090
	BEQ.S	RNL_0087		;0bac: 677e
	LSL.L	#2,D0			;0bae: e588
	MOVEA.L	file_or_dir_name(A6),A3		;0bb0: 266e0010
RNL_0081:
	MOVE.L	D1,72(A6)		;0bb4: 2d410048
	MOVE.L	D0,76(A6)		;0bb8: 2d40004c
	MOVE.L	0(A0,D0.W),D1		;0bbc: 22300000
	BEQ.S	RNL_0085		;0bc0: 674c
	MOVEA.L	A4,A0			;0bc2: 204c
	BSR.W	read_disk_sector_and_check		;0bc4: 610002e2
	BMI.S	RNL_0087		;0bc8: 6b62
	MOVEQ	#-27,D0			;0bca: 70e5
	MOVEQ	#2,D2			;0bcc: 7402
	CMP.L	(A0),D2			;0bce: b490
	BNE.S	RNL_0087		;0bd0: 665a
	MOVEQ	#2,D2			;0bd2: 7402
	TST.L	4(A7)			;0bd4: 4aaf0004
	BNE.S	RNL_0082_dir_expected		;0bd8: 6606
	TST.B	(A3)			;0bda: 4a13
	BNE.S	RNL_0082_dir_expected		;0bdc: 6602
	MOVEQ	#-3,D2			;0bde: 74fd
RNL_0082_dir_expected:
	CMP.L	508(A0),D2		;0be0: b4a801fc
	BNE.S	RNL_0084		;0be4: 6620
	LEA	432(A0),A1		;0be6: 43e801b0
	LEA	213(A6),A2		;0bea: 45ee00d5
	MOVEQ	#0,D2			;0bee: 7400
	MOVE.B	(A1)+,D2		;0bf0: 1419
	SUBQ.B	#1,D2			;0bf2: 5302
RNL_0083:
	MOVE.B	(A1)+,D0		;0bf4: 1019
	BSR.W	RNL_008F		;0bf6: 610000a0
	CMP.B	(A2)+,D0		;0bfa: b01a
	DBNE	D2,RNL_0083		;0bfc: 56cafff6
	BNE.S	RNL_0084		;0c00: 6604
	TST.B	(A2)			;0c02: 4a12
	BEQ.S	RNL_0086		;0c04: 6718
RNL_0084:
	MOVE.L	#$000001f0,D0		;0c06: 203c000001f0
	BRA.S	RNL_0081		;0c0c: 60a6
RNL_0085:
	MOVEQ	#-25,D0			;0c0e: 70e7
	TST.L	4(A7)			;0c10: 4aaf0004
	BNE.S	RNL_0087		;0c14: 6616
	TST.B	(A3)			;0c16: 4a13
	BNE.S	RNL_0087		;0c18: 6612
	MOVEQ	#-24,D0			;0c1a: 70e8
	BRA.S	RNL_0087		;0c1c: 600e
RNL_0086:
	TST.B	(A3)			;0c1e: 4a13
	BNE.W	RNL_0080		;0c20: 6600ff7e
	MOVE.L	496(A0),80(A6)		;0c24: 2d6801f00050
	MOVEQ	#0,D0			;0c2a: 7000
RNL_0087:
	MOVE.L	(A7)+,file_or_dir_name(A6)		;0c2c: 2d5f0010
	ADDQ.W	#4,A7			;0c30: 584f
	TST.L	D0			;0c32: 4a80
	MOVEM.L	(A7)+,D2/A1-A4		;0c34: 4cdf1e04
	RTS				;0c38: 4e75
	
RNL_0088:
	MOVEM.L	D1/A0-A2,-(A7)		;0c3a: 48e740e0
	MOVEQ	#0,D0			;0c3e: 7000
	MOVEQ	#-1,D1			;0c40: 72ff
	MOVEA.L	file_or_dir_name(A6),A0		;0c42: 206e0010
	MOVEA.L	A0,A2			;0c46: 2448
RNL_0089:
	ADDQ.L	#1,D1			;0c48: 5281
	TST.B	(A2)			;0c4a: 4a12
	BEQ.S	RNL_008A		;0c4c: 6708
	CMPI.B	#$2f,(A2)+		;0c4e: 0c1a002f
	BNE.S	RNL_0089		;0c52: 66f4
	SUBQ.W	#1,A2			;0c54: 534a
RNL_008A:
	LEA	213(A6),A1		;0c56: 43ee00d5
	CLR.B	(A1)			;0c5a: 4211
	TST.L	D1			;0c5c: 4a81
	BEQ.S	RNL_008D		;0c5e: 672a
RNL_008B:
	MULU	#$000d,D1		;0c60: c2fc000d
	MOVE.B	(A0)+,D0		;0c64: 1018
	BSR.S	RNL_008F		;0c66: 6130
	MOVE.B	D0,(A1)+		;0c68: 12c0
	ADD.W	D0,D1			;0c6a: d240
	ANDI.L	#$000007ff,D1		;0c6c: 0281000007ff
	CMPA.L	A0,A2			;0c72: b5c8
	BNE.S	RNL_008B		;0c74: 66ea
	CMPI.B	#$2f,(A2)		;0c76: 0c12002f
	BNE.S	RNL_008C		;0c7a: 6602
	ADDQ.W	#1,A2			;0c7c: 524a
RNL_008C:
	CLR.B	(A1)+			;0c7e: 4219
	DIVU	#$0048,D1		;0c80: 82fc0048
	CLR.W	D1			;0c84: 4241
	SWAP	D1			;0c86: 4841
	ADDQ.W	#6,D1			;0c88: 5c41
RNL_008D:
	MOVE.L	A2,file_or_dir_name(A6)		;0c8a: 2d4a0010
	MOVE.L	D1,D0			;0c8e: 2001
	MOVEM.L	(A7)+,D1/A0-A2		;0c90: 4cdf0702
	RTS				;0c94: 4e75
RNL_008E:
	MOVE.B	(A0)+,D0		;0c96: 1018
RNL_008F:
	CMPI.B	#$61,D0			;0c98: 0c000061
	BLT.S	RNL_0090		;0c9c: 6d0a
	CMPI.B	#$7a,D0			;0c9e: 0c00007a
	BGT.S	RNL_0090		;0ca2: 6e04
	ANDI.B	#$df,D0			;0ca4: 020000df
RNL_0090:
	TST.B	D0			;0ca8: 4a00
	RTS				;0caa: 4e75
RNL_0091:
	TST.B	212(A6)			;0cac: 4a2e00d4
	BEQ.S	RNL_0094		;0cb0: 671a
	MOVEA.L	buffer_512_1(A6),A0		;0cb2: 206e0020
	MOVE.L	56(A6),D1		;0cb6: 222e0038
	BNE.S	RNL_0092		;0cba: 660c
	CLR.L	56(A6)			;0cbc: 42ae0038
	BSR.S	RNL_0094		;0cc0: 610a
	BMI.S	RNL_0093		;0cc2: 6b06
	MOVE.L	D1,56(A6)		;0cc4: 2d410038
RNL_0092:
	MOVEQ	#0,D0			;0cc8: 7000
RNL_0093:
	RTS				;0cca: 4e75
RNL_0094:
	MOVE.L	8(A6),D1		;0ccc: 222e0008
	LSR.L	#1,D1			;0cd0: e289
	BSR.W	read_disk_sector_and_check		;0cd2: 610001d4
	BMI.S	RNL_0095		;0cd6: 6b18
	MOVEQ	#-27,D0			;0cd8: 70e5
	MOVEQ	#2,D2			;0cda: 7402
	CMP.L	(A0),D2			;0cdc: b490
	BNE.S	RNL_0095		;0cde: 6610
	MOVEQ	#1,D2			;0ce0: 7401
	CMP.L	508(A0),D2		;0ce2: b4a801fc
	BNE.S	RNL_0095		;0ce6: 6608
	MOVE.L	316(A0),60(A6)		;0ce8: 2d68013c003c
	MOVEQ	#0,D0			;0cee: 7000
RNL_0095:
	RTS				;0cf0: 4e75
RNL_0096:
	MOVEM.L	D1-D3,-(A7)		;0cf2: 48e77000
	MOVE.L	8(A6),D0		;0cf6: 202e0008
	BSR.W	RNL_00A8		;0cfa: 61000176
	ADDQ.L	#1,D0			;0cfe: 5280
	MOVE.L	D0,92(A6)		;0d00: 2d40005c
	MOVEQ	#2,D0			;0d04: 7002
	BSR.S	RNL_009B		;0d06: 6148
	MOVEM.L	(A7)+,D1-D3		;0d08: 4cdf000e
	RTS				;0d0c: 4e75
RNL_0097:
	MOVEM.L	D1-D2/A0,-(A7)		;0d0e: 48e76080
	MOVE.L	100(A6),D0		;0d12: 202e0064
	SUB.L	96(A6),D0		;0d16: 90ae0060
	BEQ.S	RNL_009A		;0d1a: 672e
	MOVE.L	D0,D2			;0d1c: 2400
	MOVEA.L	buffer_4(A6),A0		;0d1e: 206e002c
RNL_0098:
	MOVE.L	(A0),D1			;0d22: 2210
	BPL.S	RNL_0099		;0d24: 6a16
	ANDI.L	#$7fffffff,D1		;0d26: 02817fffffff
	CLR.L	(A0)			;0d2c: 4290
	BSR.W	compute_block_checksum		;0d2e: 61000184
	MOVE.L	D0,(A0)			;0d32: 2080
	BSR.W	RNL_00B1		;0d34: 610001a8
	BMI.S	RNL_009A		;0d38: 6b10
	MOVE.L	D1,(A0)			;0d3a: 2081
RNL_0099:
	LEA	512(A0),A0		;0d3c: 41e80200
	SUBI.L	#$00000fe0,D2		;0d40: 048200000fe0
	BHI.S	RNL_0098		;0d46: 62da
	MOVEQ	#0,D0			;0d48: 7000
RNL_009A:
	MOVEM.L	(A7)+,D1-D2/A0		;0d4a: 4cdf0106
	RTS				;0d4e: 4e75
RNL_009B:
	SUBQ.L	#2,D0			;0d50: 5580
	SUB.L	96(A6),D0		;0d52: 90ae0060
	BCS.S	RNL_009C		;0d56: 6508
	CMP.L	100(A6),D0		;0d58: b0ae0064
	BCS.W	RNL_00A5		;0d5c: 650000e8
RNL_009C:
	MOVEM.L	D1-D4/A0-A2,-(A7)	;0d60: 48e778e0
	ADD.L	96(A6),D0		;0d64: d0ae0060
	CMP.L	8(A6),D0		;0d68: b0ae0008
	BCC.W	RNL_00A6		;0d6c: 640000fc
	MOVE.L	D0,D4			;0d70: 2800
	BSR.S	RNL_0097		;0d72: 619a
	BMI.W	RNL_00A7		;0d74: 6b0000f6
	MOVE.L	D4,D0			;0d78: 2004
	BSR.W	RNL_00A8		;0d7a: 610000f6
	MOVE.L	64(A6),D1		;0d7e: 222e0040
	LSR.L	#1,D1			;0d82: e289
	SUB.L	D1,D0			;0d84: 9081
	BCC.S	RNL_009D		;0d86: 6402
	MOVEQ	#0,D0			;0d88: 7000
RNL_009D:
	MOVE.L	D0,D3			;0d8a: 2600
	BSR.W	RNL_00A9		;0d8c: 61000110
	MOVE.L	D0,96(A6)		;0d90: 2d400060
	MOVE.L	D0,100(A6)		;0d94: 2d400064
	MOVEA.L	buffer_4(A6),A2		;0d98: 246e002c
	MOVE.L	64(A6),D2		;0d9c: 242e0040
	SUBQ.L	#1,D2			;0da0: 5382
RNL_009E:
	MOVE.L	D3,D0			;0da2: 2003
	SUB.L	104(A6),D0		;0da4: 90ae0068
	BCS.S	RNL_009F		;0da8: 6506
	CMP.L	108(A6),D0		;0daa: b0ae006c
	BCS.S	RNL_00A4		;0dae: 655c
RNL_009F:
	CLR.L	108(A6)			;0db0: 42ae006c
	MOVE.L	8(A6),D1		;0db4: 222e0008
	LSR.L	#1,D1			;0db8: e289
	MOVEA.L	buffer_512_3(A6),A0		;0dba: 206e0028
RNL_00A0:
	MOVE.L	108(A6),D0		;0dbe: 202e006c
	MOVE.L	D0,104(A6)		;0dc2: 2d400068
	BSR.W	read_disk_sector_raw		;0dc6: 61000126
	BMI.W	RNL_00A7		;0dca: 6b0000a0
	MOVEQ	#127,D0			;0dce: 707f
	TST.L	108(A6)			;0dd0: 4aae006c
	BNE.S	RNL_00A2		;0dd4: 6612
	LEA	316(A0),A1		;0dd6: 43e8013c
	MOVEQ	#25,D0			;0dda: 7019
RNL_00A1:
	MOVE.L	(A1)+,(A0)+		;0ddc: 20d9
	DBF	D0,RNL_00A1		;0dde: 51c8fffc
	MOVEA.L	buffer_512_3(A6),A0		;0de2: 206e0028
	MOVEQ	#25,D0			;0de6: 7019
RNL_00A2:
	MOVE.L	D0,D1			;0de8: 2200
	ADD.L	104(A6),D1		;0dea: d2ae0068
	SUB.L	92(A6),D1		;0dee: 92ae005c
	BLS.S	RNL_00A3		;0df2: 6302
	SUB.L	D1,D0			;0df4: 9081
RNL_00A3:
	ADD.L	D0,108(A6)		;0df6: d1ae006c
	LSL.L	#2,D0			;0dfa: e588
	MOVE.L	0(A0,D0.W),D1		;0dfc: 22300000
	CMP.L	108(A6),D3		;0e00: b6ae006c
	BHI.S	RNL_00A0		;0e04: 62b8
	MOVE.L	D3,D0			;0e06: 2003
	SUB.L	104(A6),D0		;0e08: 90ae0068
RNL_00A4:
	LSL.L	#2,D0			;0e0c: e588
	MOVEA.L	buffer_512_3(A6),A0		;0e0e: 206e0028
	MOVE.L	0(A0,D0.L),D1		;0e12: 22300800
	MOVEA.L	A2,A0			;0e16: 204a
	BSR.W	read_disk_sector_raw		;0e18: 610000d4
	BMI.S	RNL_00A7		;0e1c: 6b4e
	BSR.W	RNL_00AB		;0e1e: 6100008c
	BMI.S	RNL_00A7		;0e22: 6b48
	MOVE.L	D1,(A0)			;0e24: 2081
	LEA	512(A2),A2		;0e26: 45ea0200
	ADDI.L	#$00000fe0,100(A6)	;0e2a: 06ae00000fe00064
	ADDQ.L	#1,D3			;0e32: 5283
	CMP.L	92(A6),D3		;0e34: b6ae005c
	DBEQ	D2,RNL_009E		;0e38: 57caff68
	MOVE.L	D4,D0			;0e3c: 2004
	SUB.L	96(A6),D0		;0e3e: 90ae0060
	MOVEM.L	(A7)+,D1-D4/A0-A2	;0e42: 4cdf071e
RNL_00A5:
	DIVU	#$0fe0,D0		;0e46: 80fc0fe0
	LSL.W	#8,D0			;0e4a: e148
	ADD.W	D0,D0			;0e4c: d040
	MOVEA.L	buffer_4(A6),A0		;0e4e: 206e002c
	LEA	0(A0,D0.W),A0		;0e52: 41f00000
	CLR.W	D0			;0e56: 4240
	SWAP	D0			;0e58: 4840
	MOVE.L	D0,D1			;0e5a: 2200
	ANDI.W	#$001f,D1		;0e5c: 0241001f
	LSR.W	#3,D0			;0e60: e648
	ADDQ.W	#4,D0			;0e62: 5840
	ANDI.W	#$fffc,D0		;0e64: 0240fffc
	RTS				;0e68: 4e75
RNL_00A6:
	MOVEQ	#-5,D0			;0e6a: 70fb
RNL_00A7:
	MOVEM.L	(A7)+,D1-D4/A0-A2	;0e6c: 4cdf071e
	RTS				;0e70: 4e75
RNL_00A8:
	MOVE.L	D0,D1			;0e72: 2200
	ANDI.L	#$00000fff,D1		;0e74: 028100000fff
	LSR.L	#7,D0			;0e7a: ee88
	ANDI.L	#$ffffffe0,D0		;0e7c: 0280ffffffe0
	ADD.L	D0,D1			;0e82: d280
	DIVU	#$0fe0,D1		;0e84: 82fc0fe0
	LSR.L	#5,D0			;0e88: ea88
	ADD.W	D1,D0			;0e8a: d041
	CLR.W	D1			;0e8c: 4241
	SWAP	D1			;0e8e: 4841
	MOVE.L	D1,D2			;0e90: 2401
	ANDI.W	#$001f,D2		;0e92: 0242001f
	LSR.W	#3,D1			;0e96: e649
	ANDI.W	#$fffc,D1		;0e98: 0241fffc
	RTS				;0e9c: 4e75
RNL_00A9:
	LSL.L	#5,D0			;0e9e: eb88
	MOVE.L	D0,-(A7)		;0ea0: 2f00
	LSL.L	#7,D0			;0ea2: ef88
	SUB.L	(A7)+,D0		;0ea4: 909f
	RTS				;0ea6: 4e75
	
read_disk_sector_and_check:
	BSR.S	read_disk_sector_raw		;0ea8: 6144
	BNE.S	RNL_00AC		;0eaa: 6606
RNL_00AB:
	BSR.S	compute_block_checksum		;0eac: 6106
	BEQ.S	RNL_00AC		;0eae: 6702
	; checksum not zero: error
	MOVEQ	#-23,D0			;0eb0: 70e9
RNL_00AC:
	RTS				;0eb2: 4e75
	
compute_block_checksum:
	MOVEM.L	D1/A0,-(A7)		;0eb4: 48e74080
	MOVEQ	#0,D0			;0eb8: 7000
	MOVE.W	#$007f,D1		;0eba: 323c007f
RNL_00AE:
	ADD.L	(A0)+,D0		;0ebe: d098
	DBF	D1,RNL_00AE		;0ec0: 51c9fffc
	NEG.L	D0			;0ec4: 4480
	MOVEM.L	(A7)+,D1/A0		;0ec6: 4cdf0102
	RTS				;0eca: 4e75
	
	
RNL_00AF:
	MOVEM.L	D1-D3/A2,-(A7)		;0ecc: 48e77020
	MOVEQ	#2,D0			;0ed0: 7002
	BRA.S	RNL_00B8		;0ed2: 6036
RNL_00B0:
	CLR.L	20(A0)			;0ed4: 42a80014
	BSR.S	compute_block_checksum		;0ed8: 61da
	MOVE.L	D0,20(A0)		;0eda: 21400014
RNL_00B1:
	MOVEM.L	D1-D3/A2,-(A7)		;0ede: 48e77020
	MOVEQ	#1,D2			;0ee2: 7401
	BRA.S	RNL_00B3		;0ee4: 6004
RNL_00B2:
	MOVEM.L	D1-D3/A2,-(A7)		;0ee6: 48e77020
RNL_00B3:
	MOVEQ	#1,D0			;0eea: 7001
	BRA.S	RNL_00B8		;0eec: 601c
	
; < D1 block number ?
; < A0 disk buffer (512 bytes)
read_disk_sector_raw:
	MOVEM.L	D1-D3/A2,-(A7)		;0eee: 48e77020
	MOVEQ	#1,D2			;0ef2: 7401
	BRA.S	RNL_00B7		;0ef4: 6012
RNL_00B5:
	MOVEM.L	D1-D3/A2,-(A7)		;0ef6: 48e77020
	MOVE.W	#$8000,D0		;0efa: 303c8000
	MOVEQ	#0,D1			;0efe: 7200
	MOVEQ	#0,D2			;0f00: 7400
	BRA.S	RNL_00B8		;0f02: 6006
	
; < D1 block number ?
; < D2: number of sectors to read?
; < A0: disk buffer
read_disk_sectors_raw:
	MOVEM.L	D1-D3/A2,-(A7)		;0f04: 48e77020
RNL_00B7:
	MOVEQ	#0,D0			;0f08: 7000
RNL_00B8:
	MOVE.L	D2,D3			;0f0a: 2602
	MOVE.L	D1,D2			;0f0c: 2401
	MOVEA.L	main_drive_buffer(A6),A2		;0f0e: 246e001c
	MOVE.L	4(A6),D1		;0f12: 222e0004
	BSR.S	RNL_00B9		;0f16: 6108
	MOVEM.L	(A7)+,D1-D3/A2		;0f18: 4cdf040e
	TST.L	D0			;0f1c: 4a80
	RTS				;0f1e: 4e75
RNL_00B9:
	CMPI.B	#FLOPPY_DRIVE_TYPE,drive_type(A6)		;0f20: 0c2e004600d3
	BEQ.W	floppy_entrypoint		;0f26: 670001b8
	CMPI.B	#HARD_DRIVE_TYPE,drive_type(A6)		;0f2a: 0c2e004800d3
	BEQ.W	send_hard_drive_command		;0f30: 67000a04
	; probably a mistake???? C appears only here
	; doesn't matter much at this point since CD routine works
	; so this is probably never reached
	CMPI.B	#'C',drive_type(A6)		;0f34: 0c2e004300d3
	BEQ.W	cd_drive_unsupported		;0f3a: 6700113a
	MOVEQ	#-30,D0			;0f3e: 70e2
	RTS				;0f40: 4e75
rn_locals:
	; JOTD: added 2 longwords for partial read handling: offset & length
	ds.b	8+406	
	dc.b	"DOSIO",0,0,0

; floppy support removed, not really useful here...
floppy_entrypoint
	blitz
	ILLEGAL
		
hd_command_type = 232
rn_saved_intena = 234

	; looks like CD-routine, Psygore seems to have
	; been inspired a lot by that one
	; it's HD routine see Gary base differences
	; < D0: command type.
send_hard_drive_command:
	MOVEM.L	A0-A3/A5-A6,-(A7)	;1936: 48e700f6
	LEA	hdio_locals(PC),A6		;193a: 4dfa0638
	MOVE.W	D0,hd_command_type(A6)		;193e: 3d4000e8
	MOVE.W	INTENAR,D0		;1942: 303900dff01c
	ANDI.W	#$0008,D0		;1948: 02400008
	ORI.W	#$8000,D0		;194c: 00408000
	MOVE.W	D0,rn_saved_intena(A6)		;1950: 3d4000ea
	MOVE.W	#$0008,INTENA		;1954: 33fc000800dff09a
	MOVEQ	#-1,D0			;195c: 70ff
	CMPI.W	#$0005,hd_command_type(A6)		;195e: 0c6e000500e8
	BCC.S	RNL_0120		;1964: 6418
	BSR.S	RNL_0122		;1966: 6130
	BMI.S	RNL_0120		;1968: 6b14
	MOVE.W	hd_command_type(A6),D0		;196a: 302e00e8
	LEA	hd_jump_table(PC),A3		;196e: 47fa001e
	ADD.W	D0,D0			;1972: d040
	ADDA.W	0(A3,D0.W),A3		;1974: d6f30000
	MOVE.W	hd_command_type(A6),D0		;1978: 302e00e8
	JSR	(A3)			;197c: 4e93
RNL_0120:
	MOVE.W	rn_saved_intena(A6),INTENA		;197e: 33ee00ea00dff09a
	TST.L	D0			;1986: 4a80
	MOVEM.L	(A7)+,A0-A3/A5-A6	;1988: 4cdf6f00
	RTS				;198c: 4e75
hd_jump_table:
	DC.W	hdfunction_1-hd_jump_table
	DC.W	hdfunction_1-hd_jump_table
	DC.W	hdfunction_3-hd_jump_table
	dc.w	RNL_0139-hd_jump_table
	dc.w	RNL_0139-hd_jump_table
	
RNL_0122:
	movem.l d1-d2/a0,-(sp)	; $1998
	MOVE.L	A2,4(A6)		;199c: 2d4a0004
	MOVEQ	#0,D0			;19a0: 7000
	MOVEA.L	(A6),A5			;19a2: 2a56
	TST.B	242(A6)			;19a4: 4a2e00f2
	BNE.W	RNL_0129_error		;19a8: 6600010c
	MOVE.B	#$00,243(A6)		;19ac: 1d7c000000f3
	BSR.W	do_stuff_with_ide		;19b2: 610003fa
	BMI.S	RNL_0123		;19b6: 6b0a
	MOVE.B	#$a0,D0			;19b8: 103c00a0
	BSR.W	do_stuff_with_ide		;19bc: 610003f0
	BPL.S	RNL_0124		;19c0: 6a1a
RNL_0123:
	MOVE.B	#$01,243(A6)		;19c2: 1d7c000100f3
	BSR.W	do_stuff_with_ide		;19c8: 610003e4
	BMI.W	RNL_0129_error		;19cc: 6b0000e8
	MOVE.B	#$a0,D0			;19d0: 103c00a0
	BSR.W	do_stuff_with_ide		;19d4: 610003d8
	BMI.W	RNL_0129_error		;19d8: 6b0000dc
RNL_0124:
	MOVE.L	A5,(A6)			;19dc: 2c8d
	CLR.B	4120(A5)		;19de: 422d1018
	MOVE.B	#$10,28(A5)		;19e2: 1b7c0010001c
	BSR.W	RNL_0165		;19e8: 61000530
	BMI.W	RNL_0129_error		;19ec: 6b0000c8
	BSR.W	check_ide_status		;19f0: 61000520
	MOVEA.L	A2,A0			;19f4: 204a
	BSR.W	RNL_0132		;19f6: 61000164
	BMI.W	RNL_0129_error		;19fa: 6b0000ba
	MOVE.B	12(A0),8(A5)		;19fe: 1b68000c0008
	MOVE.B	6(A0),D0		;1a04: 10280006
	SUBQ.B	#1,D0			;1a08: 5300
	ORI.B	#$a0,D0			;1a0a: 000000a0
	MOVE.B	D0,24(A5)		;1a0e: 1b400018
	MOVE.B	#$91,28(A5)		;1a12: 1b7c0091001c
	BSR.W	RNL_0165		;1a18: 61000500
	BSR.W	check_ide_status		;1a1c: 610004f4
	MOVE.B	94(A0),D0		;1a20: 1028005e
	CMPI.B	#$10,D0			;1a24: 0c000010
	BLS.S	RNL_0125		;1a28: 6302
	MOVEQ	#16,D0			;1a2a: 7010
RNL_0125:
	MOVE.B	D0,246(A6)		;1a2c: 1d4000f6
	BEQ.S	RNL_0126		;1a30: 6718
	MOVE.B	D0,8(A5)		;1a32: 1b400008
	MOVE.B	#$a0,24(A5)		;1a36: 1b7c00a00018
	MOVE.B	#$c6,28(A5)		;1a3c: 1b7c00c6001c
	BSR.W	RNL_0165		;1a42: 610004d6
	BSR.W	check_ide_status		;1a46: 610004ca
RNL_0126:
	MOVE.W	2(A0),D0		;1a4a: 30280002
	ROL.W	#8,D0			;1a4e: e158
	MOVE.W	D0,236(A6)		;1a50: 3d4000ec
	MOVEQ	#0,D0			;1a54: 7000
	MOVEQ	#0,D1			;1a56: 7200
	MOVE.B	6(A0),D0		;1a58: 10280006
	MOVE.B	D0,247(A6)		;1a5c: 1d4000f7
	MOVE.B	12(A0),D1		;1a60: 1228000c
	MOVE.B	D1,248(A6)		;1a64: 1d4100f8
	MULU	D0,D1			;1a68: c2c0
	MOVE.W	D1,block_size_TBC(A6)		;1a6a: 3d4100ee
	MOVE.W	236(A6),D0		;1a6e: 302e00ec
	MULU	D0,D1			;1a72: c2c0
	MOVE.L	D1,8(A6)		;1a74: 2d410008
	MOVEQ	#0,D1			;1a78: 7200
	; search for rigid disk block id
	MOVE.L	#'RDSK',D2		;1a7a: 243c5244534b
RNL_0127:
	BSR.W	search_partition_start		;1a80: 61000104
	BEQ.S	.found		;1a84: 670a
	ADDQ.B	#1,D1			;1a86: 5201
	CMPI.B	#$10,D1			;1a88: 0c010010
	BNE.S	RNL_0127		;1a8c: 66f2	; error? retry?
	BRA.S	RNL_0129_error		;1a8e: 6026
.found:
	MOVE.W	146(A0),240(A6)		;1a90: 3d68009200f0
	MOVE.L	24(A0),file_or_dir_name(A6)		;1a96: 2d6800180010
	MOVE.L	28(A0),inout_data_buffer(A6)		;1a9c: 2d68001c0014
	MOVE.L	32(A0),24(A6)		;1aa2: 2d6800200018
	BSR.S	RNL_012A		;1aa8: 6114
	BMI.S	RNL_0129_error		;1aaa: 6b0a
	BSR.S	RNL_012C		;1aac: 6134
	BMI.S	RNL_0129_error		;1aae: 6b06
	MOVE.B	#$01,242(A6)		;1ab0: 1d7c000100f2
RNL_0129_error:
	TST.L	D0			;1ab6: 4a80
	MOVEM.L	(A7)+,D1-D2/A0		;1ab8: 4cdf0106
	RTS				;1abc: 4e75
RNL_012A:
	MOVEQ	#0,D0			;1abe: 7000
	RTS				;1ac0: 4e75
	
hdfunction_3
	MOVEQ	#-16,D0			;1ac2: 70f0
	CMP.B	244(A6),D1		;1ac4: b22e00f4
	BHI.S	RNL_012B		;1ac8: 6216
	MULU	#$0014,D1		;1aca: c2fc0014
	MOVE.L	32(A6,D1.W),D2		;1ace: 24361020
	MOVE.L	28(A6,D1.W),D3		;1ad2: 2636101c
	MOVE.L	44(A6,D1.W),D4		;1ad6: 2836102c
	ANDI.B	#$01,D4			;1ada: 02040001
	MOVEQ	#0,D0			;1ade: 7000
RNL_012B:
	RTS				;1ae0: 4e75
RNL_012C:
	MOVEM.L	D1/A1-A3,-(A7)		;1ae2: 48e74070
	CLR.B	244(A6)			;1ae6: 422e00f4
	LEA	main_drive_buffer(A6),A1		;1aea: 43ee001c
	LEA	512(A0),A2		;1aee: 45e80200
	MOVE.L	28(A0),D1		;1af2: 2228001c
	BMI.S	RNL_0130		;1af6: 6b54
RNL_012D:
	MOVE.L	#'PART',D2		;1af8: 243c50415254
	BSR.W	search_partition_start		;1afe: 61000086
	BMI.S	RNL_0131		;1b02: 6b4a
	BTST	#1,23(A0)		;1b04: 082800010017
	BNE.S	RNL_012F		;1b0a: 663a
	; low cylinder
	MOVE.L	164(A0),D0		;1b0c: 202800a4
	; multiplied by ?
	MULU	240(A6),D0		;1b10: c0ee00f0
	MOVE.L	D0,(A1)+		;1b14: 22c0
	; high cylinder
	MOVE.L	168(A0),D0		;1b16: 202800a8
	ADDQ.L	#1,D0			;1b1a: 5280
	SUB.L	164(A0),D0		;1b1c: 90a800a4
	; multiplied to get disk size
	MULU	240(A6),D0		;1b20: c0ee00f0
	MOVE.L	D0,(A1)+		;1b24: 22c0
	LSR.L	#1,D0			;1b26: e288
	ADD.L	-8(A1),D0		;1b28: d0a9fff8
	MOVE.L	D0,(A1)+		;1b2c: 22c0
	MOVE.L	A2,(A1)+		;1b2e: 22ca
	; dostype
	MOVE.L	192(A0),(A1)+		;1b30: 22e800c0
	; drive name length
	LEA	36(A0),A3		;1b34: 47e80024
	MOVE.B	(A3)+,D0		;1b38: 101b
	; copy drive name
RNL_012E:
	MOVE.B	(A3)+,(A2)+		;1b3a: 14db
	SUBQ.B	#1,D0			;1b3c: 5300
	BNE.S	RNL_012E		;1b3e: 66fa
	; null-terminate
	CLR.B	(A2)+			;1b40: 421a
	ADDQ.B	#1,244(A6)		;1b42: 522e00f4
RNL_012F:
	; block number of the next partition block
	MOVE.L	16(A0),D1		;1b46: 22280010
	BPL.S	RNL_012D		;1b4a: 6aac
	; no more partitions
RNL_0130:
	MOVEQ	#0,D0			;1b4c: 7000
RNL_0131:
	MOVEM.L	(A7)+,D1/A1-A3		;1b4e: 4cdf0e02
	RTS				;1b52: 4e75
	MOVE.L	24(A6),D1		;1b54: 222e0018
	BSR.S	search_partition_start		;1b58: 612c
	RTS				;1b5a: 4e75
RNL_0132:
	MOVE.L	A0,-(A7)		;1b5c: 2f08
	MOVE.B	#$a0,24(A5)		;1b5e: 1b7c00a00018
	MOVE.B	#$ec,28(A5)		;1b64: 1b7c00ec001c
	BSR.W	RNL_0165		;1b6a: 610003ae
	BMI.S	RNL_0134		;1b6e: 6b12
	BSR.W	RNL_0162		;1b70: 61000384
	BMI.S	RNL_0134		;1b74: 6b0c
	MOVE.W	#$00ff,D0		;1b76: 303c00ff
RNL_0133:
	MOVE.W	(A5),(A0)+		;1b7a: 30d5
	DBF	D0,RNL_0133		;1b7c: 51c8fffc
	MOVEQ	#0,D0			;1b80: 7000
RNL_0134:
	MOVEA.L	(A7)+,A0		;1b82: 205f
	RTS				;1b84: 4e75
search_partition_start:
	MOVEM.L	D1-D2/A0,-(A7)		;1b86: 48e76080
	MOVEQ	#1,D2			;1b8a: 7401
	MOVE.B	#$00,D0			;1b8c: 103c0000
	BSR.S	RNL_0139		;1b90: 6166
	BMI.S	RNL_0137		;1b92: 6b1c
	MOVEQ	#-15,D0			;1b94: 70f1
	MOVE.L	(A0),D1			;1b96: 2210
	CMP.L	4(A7),D1		;1b98: b2af0004
	BNE.S	RNL_0137		;1b9c: 6612
	MOVE.L	4(A0),D1		;1b9e: 22280004
	SUBQ.L	#1,D1			;1ba2: 5381
	MOVEQ	#0,D0			;1ba4: 7000
RNL_0136:
	ADD.L	(A0)+,D0		;1ba6: d098
	DBF	D1,RNL_0136		;1ba8: 51c9fffc
	BEQ.S	RNL_0137		;1bac: 6702
	MOVEQ	#-7,D0			;1bae: 70f9
RNL_0137:
	MOVEM.L	(A7)+,D1-D2/A0		;1bb0: 4cdf0106
	RTS				;1bb4: 4e75
hdfunction_1
	MOVEM.L	D1-D3,-(A7)		;1bb6: 48e77000
	MOVEQ	#-16,D0			;1bba: 70f0
	CMP.B	244(A6),D1		;1bbc: b22e00f4
	BHI.S	RNL_0138		;1bc0: 622e
	MULU	#$0014,D1		;1bc2: c2fc0014
	MOVEQ	#-5,D0			;1bc6: 70fb
	CMP.L	32(A6,D1.W),D2		;1bc8: b4b61020
	BCC.S	RNL_0138		;1bcc: 6422
	MOVEQ	#-6,D0			;1bce: 70fa
	TST.L	D3			;1bd0: 4a83
	BEQ.S	RNL_0138		;1bd2: 671c
	ADD.L	D2,D3			;1bd4: d682
	CMP.L	32(A6,D1.W),D3		;1bd6: b6b61020
	BHI.S	RNL_0138		;1bda: 6214
	SUB.L	D2,D3			;1bdc: 9682
	ADD.L	28(A6,D1.W),D2		;1bde: d4b6101c
	MOVE.W	hd_command_type(A6),D0		;1be2: 302e00e8
	MOVE.L	D2,D1			;1be6: 2202
	MOVE.L	D3,D2			;1be8: 2403
	BSR.S	RNL_0139		;1bea: 610c
	MOVE.L	D2,8(A7)		;1bec: 2f420008
RNL_0138:
	TST.L	D0			;1bf0: 4a80
	MOVEM.L	(A7)+,D1-D3		;1bf2: 4cdf000e
	RTS				;1bf6: 4e75
RNL_0139:
	MOVEM.L	D1/D3/A0,-(A7)		;1bf8: 48e75080
	CLR.L	228(A6)			;1bfc: 42ae00e4
	MOVE.B	D0,D3			;1c00: 1600
	MOVE.L	D1,D0			;1c02: 2001
	BSR.W	RNL_015F		;1c04: 61000286
	BMI.S	RNL_013C		;1c08: 6b1e
RNL_013A:
	MOVE.L	#$00000100,D0		;1c0a: 203c00000100
	CMP.L	D0,D2			;1c10: b480
	BCC.S	RNL_013B		;1c12: 6404
	MOVE.L	D2,D0			;1c14: 2002
	BEQ.S	RNL_013D		;1c16: 6718
RNL_013B:
	BSR.S	hard_disk_read		;1c18: 615a
	BMI.S	RNL_013C		;1c1a: 6b0c
	ADD.L	D0,D1			;1c1c: d280
	SUB.L	D0,D2			;1c1e: 9480
	MOVE.L	D2,D0			;1c20: 2002
	BEQ.S	RNL_013D		;1c22: 670c
	BSR.S	RNL_013E		;1c24: 6116
	BRA.S	RNL_013A		;1c26: 60e2
RNL_013C:
	EXG	D0,D1			;1c28: c141
	BSR.W	RNL_0161		;1c2a: 6100029a
	EXG	D0,D1			;1c2e: c141
RNL_013D:
	MOVE.L	228(A6),D2		;1c30: 242e00e4
	TST.L	D0			;1c34: 4a80
	MOVEM.L	(A7)+,D1/D3/A0		;1c36: 4cdf010a
	RTS				;1c3a: 4e75
RNL_013E:
	MOVE.B	12(A5),D0		;1c3c: 102d000c
	ADDQ.B	#1,D0			;1c40: 5200
	CMP.B	248(A6),D0		;1c42: b02e00f8
	BLS.S	RNL_0141		;1c46: 6326
	MOVE.B	24(A5),D0		;1c48: 102d0018
	ANDI.B	#$0f,D0			;1c4c: 0200000f
	ADDQ.B	#1,D0			;1c50: 5200
	CMP.B	247(A6),D0		;1c52: b02e00f7
	BCS.S	RNL_0140		;1c56: 650c
	ADDQ.B	#1,16(A5)		;1c58: 522d0010
	BCC.S	RNL_013F		;1c5c: 6404
	ADDQ.B	#1,20(A5)		;1c5e: 522d0014
RNL_013F:
	MOVEQ	#0,D0			;1c62: 7000
RNL_0140:
	ORI.B	#$a0,D0			;1c64: 000000a0
	MOVE.B	D0,24(A5)		;1c68: 1b400018
	MOVEQ	#1,D0			;1c6c: 7001
RNL_0141:
	MOVE.B	D0,12(A5)		;1c6e: 1b40000c
	RTS				;1c72: 4e75
	
hard_disk_read:
	CMPI.B	#$04,D3			;1c74: 0c030004
	BEQ.W	RNL_014C		;1c78: 67000098
	CMPI.B	#$01,D3			;1c7c: 0c030001
	BEQ.W	RNL_014C		;1c80: 67000090
	MOVEM.L	D0-D2/A1,-(A7)		;1c84: 48e7e040
	MOVE.B	D0,D1			;1c88: 1200
	MOVE.B	D0,8(A5)		;1c8a: 1b400008
	TST.B	246(A6)			;1c8e: 4a2e00f6
	BEQ.S	RNL_0143		;1c92: 670c
	CMPI.B	#$01,D0			;1c94: 0c000001
	BNE.S	RNL_0144		;1c98: 660e
	TST.L	228(A6)			;1c9a: 4aae00e4
	BNE.S	RNL_0144		;1c9e: 6608
RNL_0143:
	MOVE.B	#$20,28(A5)		;1ca0: 1b7c0020001c
	BRA.S	RNL_0145		;1ca6: 6006
RNL_0144:
	MOVE.B	#$c4,28(A5)		;1ca8: 1b7c00c4001c
RNL_0145:
	MOVEQ	#0,D2			;1cae: 7400
	MOVEA.L	A5,A1			;1cb0: 224d
	CMPI.B	#$01,243(A6)		;1cb2: 0c2e000100f3
	BNE.S	RNL_0146		;1cb8: 6602
	SUBQ.W	#2,A1			;1cba: 5549
RNL_0146:
	TST.B	D2			;1cbc: 4a02
	BNE.S	RNL_0147		;1cbe: 6604
	BSR.W	RNL_0165		;1cc0: 61000258
RNL_0147:
	BSR.W	RNL_0162		;1cc4: 61000230
	BMI.S	RNL_014A		;1cc8: 6b3e
	
	; this reads 32*16=512 bytes from $DA2000 / whatever IDE register
	; each read seems different
	MOVEQ	#15,D0			;1cca: 700f
.copyloop:
	MOVE.W	(A1),(A0)+		;1ccc: 30d1
	MOVE.W	(A1),(A0)+		;1cce: 30d1
	MOVE.W	(A1),(A0)+		;1cd0: 30d1
	MOVE.W	(A1),(A0)+		;1cd2: 30d1
	MOVE.W	(A1),(A0)+		;1cd4: 30d1
	MOVE.W	(A1),(A0)+		;1cd6: 30d1
	MOVE.W	(A1),(A0)+		;1cd8: 30d1
	MOVE.W	(A1),(A0)+		;1cda: 30d1
	MOVE.W	(A1),(A0)+		;1cdc: 30d1
	MOVE.W	(A1),(A0)+		;1cde: 30d1
	MOVE.W	(A1),(A0)+		;1ce0: 30d1
	MOVE.W	(A1),(A0)+		;1ce2: 30d1
	MOVE.W	(A1),(A0)+		;1ce4: 30d1
	MOVE.W	(A1),(A0)+		;1ce6: 30d1
	MOVE.W	(A1),(A0)+		;1ce8: 30d1
	MOVE.W	(A1),(A0)+		;1cea: 30d1
	DBF	D0,.copyloop		;1cec: 51c8ffde
	
	ADDI.L	#$00000200,228(A6)	;1cf0: 06ae0000020000e4
	ADDQ.B	#1,D2			;1cf8: 5202
	CMP.B	246(A6),D2		;1cfa: b42e00f6
	BCS.S	RNL_0149		;1cfe: 6502
	MOVEQ	#0,D2			;1d00: 7400
RNL_0149:
	SUBQ.B	#1,D1			;1d02: 5301
	BNE.S	RNL_0146		;1d04: 66b6
	BRA.S	RNL_014B		;1d06: 6002
RNL_014A:
	MOVE.L	D0,(A7)			;1d08: 2e80
RNL_014B:
	MOVEM.L	(A7)+,D0-D2/A1		;1d0a: 4cdf0207
	TST.L	D0			;1d0e: 4a80
	RTS				;1d10: 4e75
RNL_014C:
	MOVEM.L	D0-D2/A1,-(A7)		;1d12: 48e7e040
	MOVE.B	D0,D1			;1d16: 1200
	MOVE.B	D0,8(A5)		;1d18: 1b400008
	TST.B	246(A6)			;1d1c: 4a2e00f6
	BEQ.S	RNL_014D		;1d20: 670c
	CMPI.B	#$01,D0			;1d22: 0c000001
	BNE.S	RNL_014E		;1d26: 660e
	TST.L	228(A6)			;1d28: 4aae00e4
	BNE.S	RNL_014E		;1d2c: 6608
RNL_014D:
	MOVE.B	#$30,28(A5)		;1d2e: 1b7c0030001c
	BRA.S	RNL_014F		;1d34: 6006
RNL_014E:
	MOVE.B	#$c5,28(A5)		;1d36: 1b7c00c5001c
RNL_014F:
	MOVEQ	#0,D2			;1d3c: 7400
	MOVEA.L	A5,A1			;1d3e: 224d
	CMPI.B	#$01,243(A6)		;1d40: 0c2e000100f3
	BNE.S	RNL_0151		;1d46: 660e
	SUBQ.W	#2,A1			;1d48: 5549
	BRA.S	RNL_0151		;1d4a: 600a
RNL_0150:
	TST.B	D2			;1d4c: 4a02
	BNE.S	RNL_0151		;1d4e: 6606
	BSR.W	RNL_0165		;1d50: 610001c8
	BMI.S	RNL_0154		;1d54: 6b4e
RNL_0151:
	BSR.W	RNL_0162		;1d56: 6100019e
	BMI.S	RNL_0154		;1d5a: 6b48
	MOVEQ	#15,D0			;1d5c: 700f
RNL_0152:
	MOVE.W	(A0)+,(A1)		;1d5e: 3298
	MOVE.W	(A0)+,(A1)		;1d60: 3298
	MOVE.W	(A0)+,(A1)		;1d62: 3298
	MOVE.W	(A0)+,(A1)		;1d64: 3298
	MOVE.W	(A0)+,(A1)		;1d66: 3298
	MOVE.W	(A0)+,(A1)		;1d68: 3298
	MOVE.W	(A0)+,(A1)		;1d6a: 3298
	MOVE.W	(A0)+,(A1)		;1d6c: 3298
	MOVE.W	(A0)+,(A1)		;1d6e: 3298
	MOVE.W	(A0)+,(A1)		;1d70: 3298
	MOVE.W	(A0)+,(A1)		;1d72: 3298
	MOVE.W	(A0)+,(A1)		;1d74: 3298
	MOVE.W	(A0)+,(A1)		;1d76: 3298
	MOVE.W	(A0)+,(A1)		;1d78: 3298
	MOVE.W	(A0)+,(A1)		;1d7a: 3298
	MOVE.W	(A0)+,(A1)		;1d7c: 3298
	DBF	D0,RNL_0152		;1d7e: 51c8ffde
	ADDI.L	#$00000200,228(A6)	;1d82: 06ae0000020000e4
	ADDQ.B	#1,D2			;1d8a: 5202
	CMP.B	246(A6),D2		;1d8c: b42e00f6
	BCS.S	RNL_0153		;1d90: 6502
	MOVEQ	#0,D2			;1d92: 7400
RNL_0153:
	SUBQ.B	#1,D1			;1d94: 5301
	BNE.S	RNL_0150		;1d96: 66b4
	BSR.W	RNL_0165		;1d98: 61000180
	BMI.S	RNL_0154		;1d9c: 6b06
	BSR.W	check_ide_status		;1d9e: 61000172
	BRA.S	RNL_0155		;1da2: 6002
RNL_0154:
	MOVE.L	D0,(A7)			;1da4: 2e80
RNL_0155:
	MOVEM.L	(A7)+,D0-D2/A1		;1da6: 4cdf0207
	TST.L	D0			;1daa: 4a80
	RTS				;1dac: 4e75
do_stuff_with_ide:
	MOVEM.L	D1-D4/A0-A1,-(A7)	;1dae: 48e778c0
	MOVE.B	D0,D4			;1db2: 1800
	LEA	A4000_IDE_REGISTER,A5		;1db4: 4bf900dd2022
	CMPI.B	#$01,243(A6)		;1dba: 0c2e000100f3
	BEQ.S	RNL_0158		;1dc0: 6762
	LEA	A1200_IDE_REGISTER,A5		;1dc2: 4bf900da2000
	LEA	HARDBASE,A0		;1dc8: 41f900dff000
	LEA	GAYLE_BASE,A1		;1dce: 43f900de1000
	MOVE.W	#$4000,154(A0)		;1dd4: 317c4000009a
	MOVE.W	28(A0),-(A7)		;1dda: 3f28001c
	MOVE.W	#$bfff,154(A1)		;1dde: 337cbfff009a
	MOVE.W	#$3fff,D1		;1de4: 323c3fff
	CMP.W	28(A0),D1		;1de8: b268001c
	BNE.S	RNL_0157		;1dec: 660c
	MOVE.W	D1,154(A1)		;1dee: 3341009a
	TST.W	28(A0)			;1df2: 4a68001c
	BNE.S	RNL_0157		;1df6: 6602
	MOVEQ	#0,D1			;1df8: 7200
RNL_0157:
	MOVE.W	#$3fff,154(A0)		;1dfa: 317c3fff009a
	ORI.W	#$8000,(A7)		;1e00: 00578000
	MOVE.W	(A7)+,154(A0)		;1e04: 315f009a
	MOVE.W	#$c000,154(A0)		;1e08: 317cc000009a
	TST.W	D1			;1e0e: 4a41
	BEQ.S	RNL_015C		;1e10: 6766
	MOVEQ	#0,D1			;1e12: 7200
	CLR.B	(A1)			;1e14: 4211
	BSR.S	RNL_015E		;1e16: 616c
	BSR.S	RNL_015E		;1e18: 616a
	BSR.S	RNL_015E		;1e1a: 6168
	BSR.S	RNL_015E		;1e1c: 6166
	CMPI.B	#$0d,D1			;1e1e: 0c01000d
	BNE.S	RNL_015C		;1e22: 6654
RNL_0158:
	MOVEQ	#9,D3			;1e24: 7609
RNL_0159:
	MOVE.B	D4,24(A5)		;1e26: 1b440018
	MOVE.B	16(A5),D1		;1e2a: 122d0010
	MOVE.B	28(A5),D0		;1e2e: 102d001c
	MOVE.B	D0,D2			;1e32: 1400
	ANDI.B	#$c0,D0			;1e34: 020000c0
	BEQ.S	RNL_015A		;1e38: 6716
	CMPI.B	#$c0,D0			;1e3a: 0c0000c0
	BEQ.S	RNL_015C		;1e3e: 6738
	TST.B	D0			;1e40: 4a00
	BPL.S	RNL_015B		;1e42: 6a18
	EOR.B	D1,D2			;1e44: b302
	ANDI.B	#$fd,D2			;1e46: 020200fd
	BNE.S	RNL_015C		;1e4a: 662c
	MOVEQ	#2,D0			;1e4c: 7002
	BRA.S	RNL_015D		;1e4e: 602a
RNL_015A:
	BTST	#4,D4			;1e50: 08040004
	BNE.S	RNL_015C		;1e54: 6622
	DBF	D3,RNL_0159		;1e56: 51cbffce
	BRA.S	RNL_015C		;1e5a: 601c
RNL_015B:
	MOVEQ	#18,D0			;1e5c: 7012
	MOVE.B	D0,16(A5)		;1e5e: 1b400010
	CMP.B	16(A5),D0		;1e62: b02d0010
	BNE.S	RNL_015C		;1e66: 6610
	MOVEQ	#52,D0			;1e68: 7034
	MOVE.B	D0,16(A5)		;1e6a: 1b400010
	CMP.B	16(A5),D0		;1e6e: b02d0010
	BNE.S	RNL_015C		;1e72: 6604
	MOVEQ	#1,D0			;1e74: 7001
	BRA.S	RNL_015D		;1e76: 6002
RNL_015C:
	MOVEQ	#-4,D0			;1e78: 70fc
RNL_015D:
	MOVEM.L	(A7)+,D1-D4/A0-A1	;1e7a: 4cdf031e
	RTS				;1e7e: 4e75
	MOVE.B	D0,D4			;1e80: 1800
	RTS				;1e82: 4e75
RNL_015E:
	MOVE.B	(A1),D0			;1e84: 1011
	LSL.B	#1,D0			;1e86: e308
	ADDX.B	D1,D1			;1e88: d301
	RTS				;1e8a: 4e75
RNL_015F:
	CMP.L	8(A6),D0		;1e8c: b0ae0008
	BCC.S	RNL_0160		;1e90: 6430
	MOVE.L	D0,D1			;1e92: 2200
	DIVU	block_size_TBC(A6),D0		;1e94: 80ee00ee
	MOVE.B	D0,16(A5)		;1e98: 1b400010
	LSR.W	#8,D0			;1e9c: e048
	MOVE.B	D0,20(A5)		;1e9e: 1b400014
	CLR.W	D0			;1ea2: 4240
	SWAP	D0			;1ea4: 4840
	MOVEQ	#0,D1			;1ea6: 7200
	MOVE.B	248(A6),D1		;1ea8: 122e00f8
	DIVU	D1,D0			;1eac: 80c1
	ORI.B	#$a0,D0			;1eae: 000000a0
	MOVE.B	D0,24(A5)		;1eb2: 1b400018
	SWAP	D0			;1eb6: 4840
	ADDQ.B	#1,D0			;1eb8: 5200
	MOVE.B	D0,12(A5)		;1eba: 1b40000c
	MOVEQ	#0,D0			;1ebe: 7000
	RTS				;1ec0: 4e75
RNL_0160:
	MOVEQ	#-5,D0			;1ec2: 70fb
	RTS				;1ec4: 4e75
RNL_0161:
	MOVE.L	D1,-(A7)		;1ec6: 2f01
	MOVE.B	20(A5),D0		;1ec8: 102d0014
	LSL.W	#8,D0			;1ecc: e148
	MOVE.B	16(A5),D0		;1ece: 102d0010
	MULU	block_size_TBC(A6),D0		;1ed2: c0ee00ee
	MOVE.L	D0,-(A7)		;1ed6: 2f00
	MOVE.B	24(A5),D0		;1ed8: 102d0018
	ANDI.W	#$000f,D0		;1edc: 0240000f
	MOVEQ	#0,D1			;1ee0: 7200
	MOVE.B	248(A6),D1		;1ee2: 122e00f8
	MULU	D0,D1			;1ee6: c2c0
	ADD.L	(A7)+,D1		;1ee8: d29f
	MOVE.B	12(A5),D0		;1eea: 102d000c
	SUBQ.B	#1,D0			;1eee: 5300
	ADD.L	D1,D0			;1ef0: d081
	MOVE.L	(A7)+,D1		;1ef2: 221f
	RTS				;1ef4: 4e75
RNL_0162:
	BSR.S	check_ide_status		;1ef6: 611a
	BTST	#0,D0			;1ef8: 08000000
	BNE.S	RNL_0163		;1efc: 660a
	BTST	#3,D0			;1efe: 08000003
	BEQ.S	RNL_0162		;1f02: 67f2
	MOVEQ	#0,D0			;1f04: 7000
	RTS				;1f06: 4e75
RNL_0163:
	MOVE.B	4(A5),245(A6)		;1f08: 1d6d000400f5
	MOVEQ	#-1,D0			;1f0e: 70ff
	RTS				;1f10: 4e75
	; < A5: DA2000 or whatever gayle register base
check_ide_status:
	MOVE.B	28(A5),D0		;1f12: 102d001c
	BMI.S	check_ide_status		;1f16: 6bfa
	RTS				;1f18: 4e75
RNL_0165:
	BSR.W	RNL_011A		;1f1a: 6100f9ca
	MOVE.W	#$0fa0,D0		;1f1e: 303c0fa0
	CMPI.B	#$01,243(A6)		;1f22: 0c2e000100f3
	BNE.S	RNL_0167		;1f28: 6612
RNL_0166:
	BSR.W	timer_routine_2		;1f2a: 6100f9ac
	BEQ.S	RNL_0169		;1f2e: 6740
	TST.W	4094(A5)		;1f30: 4a6d0ffe
	BPL.S	RNL_0166		;1f34: 6af4
	MOVE.B	28(A5),D0		;1f36: 102d001c
	BRA.S	RNL_0168		;1f3a: 6030
RNL_0167:
	BSR.W	timer_routine_2		;1f3c: 6100f99a
	BEQ.S	RNL_0169		;1f40: 672e
	TST.B	28672(A5)		;1f42: 4a2d7000
	BPL.S	RNL_0167		;1f46: 6af4
	MOVE.B	28(A5),D0		;1f48: 102d001c
	MOVE.W	#$4000,INTENA		;1f4c: 33fc400000dff09a
	MOVE.B	28672(A5),D0		;1f54: 102d7000
	ANDI.B	#$03,D0			;1f58: 02000003
	ORI.B	#$7c,D0			;1f5c: 0000007c
	MOVE.B	D0,28672(A5)		;1f60: 1b407000
	MOVE.W	#$c000,INTENA		;1f64: 33fcc00000dff09a
RNL_0168:
	MOVEQ	#0,D0			;1f6c: 7000
	RTS				;1f6e: 4e75
RNL_0169:
	MOVEQ	#-3,D0			;1f70: 70fd
	RTS				;1f72: 4e75
hdio_locals:
	ds.b	$206c-$1F74
	dc.b	"HDIOEND",0
	

timer_routine_1:
	BSR.S	RNL_011A		;18c6: 611e
RNL_0118:
	BTST	#0,CIAB_CRB		;18c8: 0839000000bfdf00
	BNE.S	RNL_0118		;18d0: 66f6
	SUBQ.W	#1,D0			;18d2: 5340
	BNE.S	timer_routine_1		;18d4: 66f0
	RTS				;18d6: 4e75
timer_routine_2:
	BTST	#0,CIAB_CRB		;18d8: 0839000000bfdf00
	BNE.S	RNL_011B		;18e0: 661c
	SUBQ.W	#1,D0			;18e2: 5340
	BEQ.S	RNL_011B		;18e4: 6718
RNL_011A:
	MOVE.B	#$08,CIAB_CRB		;18e6: 13fc000800bfdf00
	MOVE.B	#$cc,CIAB_TBLO		;18ee: 13fc00cc00bfd600
	MOVE.B	#$02,CIAB_TBHI		;18f6: 13fc000200bfd700
RNL_011B:
	RTS				;18fe: 4e75