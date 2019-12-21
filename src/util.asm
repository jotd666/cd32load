; $200 is OK for CDIO and RN decruncher. Buffer is shared by both codes
; (no risk since they cannot call each other)
CDIO_STACK_SIZE = $200

RELOC_STACK:MACRO
	; save old stack pointer, relocate stack for the cdio exec (eats a lot of stack)
	movem.l	A1,-(A7)
	lea	old_stack(pc),A1
	move.l	A7,(a1)
	add.l	#4,(A1)	; rectify address
	movem.l	(A7)+,A1
	lea	cdio_stack(pc),A7	; install a new stack
	ENDM
UNRELOC_STACK:MACRO
	move.l	old_stack(pc),A7	; restore original stack
	ENDM

; *** Decrunch a TPWM crunched file (TPWM)
; <   A0 start of source/dest buffer
; >   D0=0 if OK, -1 else

TPWMDecrunch:
	INCLUDE	TPWMDecrunch.asm


; *** Decrunch a ATN! file
; in: A0: crunched buffer
;     A1: decrunched dest (may be the same)

; out: D0=0 if not a ATN file

; *** Decrunch a Imploder crunched file (IMP!)
; >   D0=0 if OK, -1 else
; in: A0: crunched/decrunched buffer
    
ImploderDecrunch:
	move.l	A0,A1
ATNDecrunch:
	STORE_REGS
	bsr	.dec
	RESTORE_REGS
	rts

.dec:
	include	"ATNDecrunch.asm"


; *** Decrunches a RNC type 1/2 file (Rob Northen Cruncher, header: RNC\01, RNC\02)
; *** Ripped from SSBOOT/HOOK (Cannon Fodder2, SWOS)

; in: A0: crunched buffer start
; in: A1: destination (may be the same !!)

; This type of cruncher is very heavily used in lots of games
; from EOA, Team 17, Renegade, Akklaim, and lots of others.

RNCDecrunch:
	include	"RNC12Decrunch.asm"
	
; CRC16 algorithm
; Converted from the C program CRCPPC, found on aminet.

;;M16 = $A001
	
crctab:
	dc.w		$0000, $C0C1, $C181, $0140, $C301, $03C0, $0280, $C241
	dc.w		$C601, $06C0, $0780, $C741, $0500, $C5C1, $C481, $0440
	dc.w		$CC01, $0CC0, $0D80, $CD41, $0F00, $CFC1, $CE81, $0E40 
	dc.w		$0A00, $CAC1, $CB81, $0B40, $C901, $09C0, $0880, $C841
	dc.w		$D801, $18C0, $1980, $D941, $1B00, $DBC1, $DA81, $1A40 
	dc.w		$1E00, $DEC1, $DF81, $1F40, $DD01, $1DC0, $1C80, $DC41 
	dc.w		$1400, $D4C1, $D581, $1540, $D701, $17C0, $1680, $D641
	dc.w		$D201, $12C0, $1380, $D341, $1100, $D1C1, $D081, $1040
	dc.w		$F001, $30C0, $3180, $F141, $3300, $F3C1, $F281, $3240
	dc.w		$3600, $F6C1, $F781, $3740, $F501, $35C0, $3480, $F441 
	dc.w		$3C00, $FCC1, $FD81, $3D40, $FF01, $3FC0, $3E80, $FE41 
	dc.w		$FA01, $3AC0, $3B80, $FB41, $3900, $F9C1, $F881, $3840
	dc.w		$2800, $E8C1, $E981, $2940, $EB01, $2BC0, $2A80, $EA41 
	dc.w		$EE01, $2EC0, $2F80, $EF41, $2D00, $EDC1, $EC81, $2C40
	dc.w		$E401, $24C0, $2580, $E541, $2700, $E7C1, $E681, $2640 
	dc.w		$2200, $E2C1, $E381, $2340, $E101, $21C0, $2080, $E041
	dc.w		$A001, $60C0, $6180, $A141, $6300, $A3C1, $A281, $6240 
	dc.w		$6600, $A6C1, $A781, $6740, $A501, $65C0, $6480, $A441 
	dc.w		$6C00, $ACC1, $AD81, $6D40, $AF01, $6FC0, $6E80, $AE41
	dc.w		$AA01, $6AC0, $6B80, $AB41, $6900, $A9C1, $A881, $6840 
	dc.w		$7800, $B8C1, $B981, $7940, $BB01, $7BC0, $7A80, $BA41
	dc.w		$BE01, $7EC0, $7F80, $BF41, $7D00, $BDC1, $BC81, $7C40
	dc.w		$B401, $74C0, $7580, $B541, $7700, $B7C1, $B681, $7640 
	dc.w		$7200, $B2C1, $B381, $7340, $B101, $71C0, $7080, $B041 
	dc.w		$5000, $90C1, $9181, $5140, $9301, $53C0, $5280, $9241 
	dc.w		$9601, $56C0, $5780, $9741, $5500, $95C1, $9481, $5440
	dc.w		$9C01, $5CC0, $5D80, $9D41, $5F00, $9FC1, $9E81, $5E40 
	dc.w		$5A00, $9AC1, $9B81, $5B40, $9901, $59C0, $5880, $9841
	dc.w		$8801, $48C0, $4980, $8941, $4B00, $8BC1, $8A81, $4A40
	dc.w		$4E00, $8EC1, $8F81, $4F40, $8D01, $4DC0, $4C80, $8C41
	dc.w		$4400, $84C1, $8581, $4540, $8701, $47C0, $4680, $8641
	dc.w		$8201, $42C0, $4380, $8341, $4100, $81C1, $8081, $4040

; < A0: pointer on zone
; < D0: length in bytes
; > D0: CRC 16

CRC16:
	STORE_REGS	D1-A6
	move.l	D0,D7
	moveq.l	#0,D0	; initialize to 0
	tst.l	D7
	beq	.exit	; 0 length: out!

	lea	crctab(pc),A2
.loop

	moveq.l	#0,D1
	move.b	(A0)+,D1	; gets one char
	bsr		updctcr
	subq.l	#1,D7
	bne.b	.loop

.exit
	RESTORE_REGS	D1-A6
	rts

updctcr:
	move.w	D0,D4	; current CRC (tmp)
	move.w	D0,D3	; current CRC
	eor.w	D1,D4	; tmp=crc^c
	and.w	#$FF,D4	; limited to 0xFF
	add.w	D4,D4	; *2
	lsr.w	#8,D3	; crc>>8
	move.w	(A2,D4.W),D0	; crc16tab[tmp & 0xff]
	eor.w	D3,D0	; crc=(crc>>8)^crc16tab[tmp & 0xff];
	rts

; Memory Copy
; This is not optimized, but it works
; Even if memory regions overlap

; < A0: start pointer
; < A1: dest pointer
; < D0: length

CopyMem:
	include	"copymem.asm"
	
; < D1: file/dir name
; > D0: 0 if absolute, -1 if not
IsAbs:
	STORE_REGS	D2/A0-A1
	move.l	D1,A0
	moveq.l	#-1,d0
.loop
	move.b	(A0)+,D2
	beq.b	.out
	cmp.b	#':',D2
	beq.b	.abs
	bra.b	.loop
.abs
	moveq.l	#0,D0
.out
	RESTORE_REGS	D2/A0-A1
	rts
	
; < D1: file/dir name
; < D2 (modified): dirname of D1

Dirname:
	STORE_REGS	D0-D2/A0-A1
	move.l	d2,A1
	clr.b	(A1)	; default: nothing
	
	
	move.l	D1,D0
	bsr	StrlenAsm
	tst.l	D0
	beq.w	.out
	
	move.l	d1,a1
	add.l	d0,a1
.loop
	subq.l	#1,a1
	cmp.l	d1,a1
	beq.b	.out	; dirname is empty
	cmp.b	#'/',(a1)
	beq.b	.found
	cmp.b	#':',(a1)
	beq.b	.found2
	bra.b	.loop
.found
	subq.l	#1,a1
.found2
	move.l	d1,d0	; source
	sub.l	d1,a1	; substract to base to get size
	move.l	a1,d1
	exg.l	d1,d2	; size in d2, destination in d1
	bsr	StrncpyAsm
.out
	RESTORE_REGS	D0-D2/A0-A1
	rts

	
; < D1: file/dir name
; < D2 (modified): basename of D1

Basename:
	STORE_REGS	D0-D2/A0-A1
	move.l	d2,A1
	clr.b	(A1)	; default: nothing
	
	move.l	D1,D0
	bsr	StrlenAsm
	tst.l	D0
	beq.w	.out
	
	move.l	d1,a1
	add.l	d0,a1
.loop
	subq.l	#1,a1
	cmp.l	d1,a1
	beq.b	.found2	; dirname is empty
	cmp.b	#'/',(a1)
	beq.b	.found
	cmp.b	#':',(a1)
	beq.b	.found
	bra.b	.loop
.found
	subq.l	#1,a1
.found2
	; a1 points to basename
	move.l	a1,d0
	move.l	d2,d1
	bsr	StrcpyAsm
.out
	RESTORE_REGS	D0-D2/A0-A1
	rts
		
; < D1: dirname (modified)
; < D2: filename
; < D3: max buffer size
; > D0: !=0 if ok, =0 if buffer overflow

AddPart:
	STORE_REGS	D1-A6
	
	move.l	D2,D0
	bsr	StrlenAsm
	tst.l	D0
	beq.w	.nofile

	move.l	D1,D0
	bsr	StrlenAsm
	tst.l	D0
	beq.b	.nodir

	move.l	D1,A0
	move.b	-1(A0,D0),D4	; last char of directory

	add.l	D0,D1		; end of directory string

	cmp.b	#":",D4
	beq.b	.skipslash

	cmp.b	#"/",D4
	beq.b	.skipslash

	; simple concatenation, with "/"

	move.l	D1,A0
	move.b	#"/",(A0)
	addq.l	#1,D1
.skipslash:
	move.l	D2,D0
	bsr	StrcpyAsm

.exit
	moveq.l	#1,D0		; ok
	RESTORE_REGS	D1-A6
	rts
	
.nofile:
	bra.b	.exit
	
.nodir:
	move.l	D2,D0
	bsr	StrcpyAsm
	bra.b	.exit

; *** Converts a ascii string to number
; both formats $ABCD and 0xABCD are accepted
; in: A1: pointer to source buffer
; out: D0: number
	
HexStringToNum:
	STORE_REGS	D1-A6
	moveq.l	#0,D0
	tst.b	(a1)
	beq.b	.out
		
	cmp.b	#'$',(a1)
	beq.b	.hexok
	cmp.b	#'0',(a1)+
	bne.b	.out
	cmp.b	#'X',(a1)
	beq.b	.hexok
	cmp.b	#'x',(a1)
	bne.b	.out	
.hexok
	addq.l	#1,A1
	moveq.l	#0,d1
	moveq.l	#0,d2
.loop
	move.b	(a1)+,d1
	beq.b	.end
	cmp.b	#'9'+1,d1
	bcs.b	.digit
	
	cmp.b	#'G',d1
	bcs.b	.ucletter
	cmp.b	#'g',d1
	bcs.b	.lcletter
	bra.b	.out

.lcletter
	sub.b	#'a',d1
	bmi.b	.out
	add.b	#10,d1
	bra.b	.store

.ucletter
	sub.b	#'A',d1
	bmi.b	.out
	add.b	#10,d1
	bra.b	.store
.digit
	sub.b	#'0',d1
	bmi.b	.out
.store	
	lsl.l	#4,d2
	or.b	d1,d2
	bra.b	.loop
.end
	move.l	d2,d0
	bra	.out

.out

	RESTORE_REGS	D1-A6
	rts
; *** Converts a hex number to a ascii string (size 4 $xxxx)
; in: D0: number
; in: A1: pointer to destination buffer
; out: nothing

ShortHexToString:
	STORE_REGS
	swap	D0
	moveq.l	#3,D4		; 4 digits
	bsr	HexToString
	RESTORE_REGS
	rts

; *** Copies 2 strings

; D0: pointer on first string
; D1: pointer on second string

; out: nothing

StrcpyAsm:
	STORE_REGS	D2
	move.l	#$FFFF,D2
	bsr	StrncpyAsm
	RESTORE_REGS	D2
	rts

; *** Copies 2 strings

; D0: pointer on first string
; D1: pointer on second string
; D2: max length of the string

; out: nothing

StrncpyAsm:
	STORE_REGS	A0-A1/D2

	move.l	D0,A0
	move.l	D1,A1
.copy
	move.b	(A0)+,(A1)+
	beq.b	.exit
	dbf	D2,.copy

	; terminates if end reached

	clr.b	(A1)
.exit
	RESTORE_REGS	A0-A1/D2
	rts

; *** Sets buffer in upper case

; D0: pointer on string

ToUpperAsm:
	STORE_REGS
	move.l	D0,A0
	clr.l	D0
.loop: 
	move.b	(A0,D0.L),D1		; gets char
	beq.b	.exit

	cmp.b	#'a',D1
	bcs	.skip
	cmp.b	#'z'+1,D1
	bcc	.skip

	add.b	#'A'-'a',D1		; converts to upper
	move.b	D1,(A0,D0.L)
.skip
	addq.l	#1,D0
	bra	.loop
.exit:
	RESTORE_REGS
	rts

; *** Compares 2 strings (uc=lc)

; D0: pointer on first string
; D1: pointer on second string

; out: D0=0 if OK, -1 elsewhere

	cnop	0,4
StrcmpAsm:
	STORE_REGS	D1-A6

	move.l	D0,D6
	move.l	D1,D7

	; *** Test String Lengths

	move.l	D6,D0
	bsr	StrlenAsm
	move.l	D0,D2

	move.l	D7,D0
	bsr	StrlenAsm

	cmp.l	D0,D2
	bne	.wrong

	tst.l	D2
	beq	.right	; empty -> match

	; *** Test String Contents

	move.l	D6,A0
	move.l	D7,A1
	subq.l	#1,D2

	bsr	intern_strncmp

.exit
	RESTORE_REGS	D1-A6
	rts

.right:
	moveq.l	#0,D0
	bra	.exit

.wrong:
	moveq.l	#-1,D0
	bra	.exit

; *** Compares 2 strings beginnings (uc=lc)

; D0: pointer on first string
; D1: pointer on second string
; D2: length

; out: D0=0 if OK, -1 elsewhere

	cnop	0,4
StrncmpAsm:
	STORE_REGS	D1-A6

	move.l	D0,A0
	move.l	D1,A1

	subq.l	#1,D2

	; *** Test String Contents

	bsr	intern_strncmp

.exit
	RESTORE_REGS	D1-A6
	rts

.right:
	moveq.l	#0,D0
	bra	.exit

.wrong:
	moveq.l	#-1,D0
	bra	.exit

intern_strncmp:
.cmploop:
	move.b	(A0),D0
	cmp.b	(A1),D0
	beq	.match		; exact match

	move.b	(A0),D0
	sub.b	#'A',D0
	bcs	.wrong		; not a letter -> wrong

	move.b	(A0),D0
	sub.b	#'z'+1,D0
	bcc	.wrong		; not a letter -> wrong

	; between 'A' and 'z'

	move.b	(A0),D0
	sub.b	#'Z'+1,D0
	bcc	.lower		; a lower case

	; between 'A' and 'Z' : compare

	move.b	(A0),D0
	add.b	#'a'-'A',D0
	cmp.b	(A1),D0
	beq	.match		; case unsensitive match
	bra	.wrong		; false

.lower
	move.b	(A0),D0
	sub.b	#'a'-'A',D0
	cmp.b	(A1),D0
	beq	.match		; case unsensitive match
	bra	.wrong		; false

.match
	lea	1(A0),A0
	lea	1(A1),A1
	dbf	D2,.cmploop
	moveq.l	#0,D0
.exit
	rts

.wrong:
	moveq.l	#-1,D0
	bra	.exit

; *** Returns the length of a NULL-terminated string

; in: D0: string pointer
; out:D0: number of chars before '/0'

StrlenAsm:
	STORE_REGS	A0
	move.l	D0,A0
	clr.l	D0
.loop: 
	tst.b	(A0,D0.L)
	beq.b	.exit
	addq.l	#1,D0
	bra	.loop
.exit:
	RESTORE_REGS	A0
	rts

; *** Converts a hex number to a ascii string (size 9 $xxxxxxxx)
; in: D0: number
; in: A1: pointer to destination buffer
; out: nothing

HexToString:
	STORE_REGS	D1-D4/A1
	moveq.l	#7,D4		; 8 digits
	bsr	__HexToString
	RESTORE_REGS	D1-D4/A1
	rts

; internal HexToString

__HexToString:
	move.l	#$F0000000,D3
	moveq.l	#4,D2
	move.b	#'$',(A1)+	
.loop
	move.l	D0,D1
	and.l	D3,D1
	rol.l	D2,D1
	cmp.b	#9,D1
	bgt	.letter
	add.b	#'0',D1
	move.b	D1,(A1)+
	bra	.loopend
.letter
	add.b	#'A'-10,D1
	move.b	D1,(A1)+
.loopend
	addq.l	#4,D2
	lsr.l	#4,D3
	dbf	D4,.loop

	rts

; *** Converts a hex number to a ascii string of the decimal value
; in: D0: number (-655350:655350), if overflow, Nan or -Nan is returned
; in: A1: pointer to destination buffer (must be at least of size 8)
; out: nothing

HexToDecString:
	STORE_REGS

	tst.l	D0
	bpl.b	.positive
	neg.l	D0	; D0 = -D0
	move.b	#'-',(A1)+
.positive

	cmp.l	#655351,D0
	bcs.b	.ok

	; overflow

	move.l	A1,A3
	move.b	#'N',(A3)+
	move.b	#'a',(A3)+
	move.b	#'N',(A3)+
	bra	.end
.ok
	move.l	A1,A2	; store user buffer pointer

	move.l	D0,D2
	moveq.l	#0,D3

.loop
	divu	#10,D2
	swap	D2	
	move.w	D2,D3	; D3=remainder

	add.b	#'0',D3
	move.b	D3,(A2)+	; store the number in reverse

	clr.w	D2
	swap	D2	; D2=result
	tst.l	D2
	bne.b	.loop

	; division over, now reverse the number in the buffer

	move.l	A2,A3	; store end of string

	move.l	A2,D0
	sub.l	A1,D0	; D0: number of digits
	lsr	#1,D0	; only swap on half!
	beq.b	.end	; 1 char: no swap
	subq.l	#1,D0
.reverse
	move.b	-(A2),D2
	move.b	(A1),(A2)
	move.b	D2,(A1)+
	dbf	D0,.reverse
.end
	clr.b	(A3)


	RESTORE_REGS
	rts

;*** Search and replace a longword
;
; < D0	longword to search for
; < D1	longword to replace
; < A0	start address
; < A1	end address

HexReplaceLong:
	STORE_REGS	A0-A1/D0-D1
.srch
	cmp.l	(A0),D0
	beq.b	.found
.next
	addq.l	#2,A0
	cmp.l	A1,A0
	bcc.b	.exit
	bra.b	.srch
.found
	move.l	D1,(A0)+
	bra	.next

.exit
	RESTORE_REGS	A0-A1/D0-D1
	rts

;*** Search and replace a word
;
; < D0	word to search for
; < D1	word to replace
; < A0	start address
; < A1	end address

HexReplaceWord:
	STORE_REGS
.srch
	cmp.w	(A0),D0
	beq.b	.found
.next
	addq.l	#2,A0
	cmp.l	A1,A0
	bcc.b	.exit
	bra.b	.srch
.found
	move.w	D1,(A0)+
	bra	.next

.exit
	RESTORE_REGS
	rts


;*** Skips colon in file name
; < A0 string
; > A0 string without ':'

SkipColon:
	STORE_REGS	A2
	move.l	A0,A2

.loop
	cmp.b	#0,(A2)
	beq.b	.nocolon	; no colon: unchanged

	cmp.b	#':',(A2)
	beq.b	.colon
	addq.l	#1,A2
	bra.b	.loop
	
.colon
	move.l	A2,A0
	addq.l	#1,A0
.nocolon
	RESTORE_REGS	A2
.exit
	rts

;*** Search for hex data
;
; < A0	start address
; < A1	end address
; < A2	start address for hex string
; < D0  length
; > A0  address where the string was found, 0 if error

HexSearch:
	STORE_REGS	D1/D3/A1-A2
	
.addrloop:
	moveq.l	#0,D3
.strloop
	move.b	(A0,D3.L),D1	; gets byte
	cmp.b	(A2,D3.L),D1	; compares it to the user string
	bne.b	.notok		; nope
	addq.l	#1,D3
	cmp.l	D0,D3
	bcs.b	.strloop

	; pattern was entirely found!

	bra.b	.exit
.notok:
	addq.l	#1,A0	; next byte please
	cmp.l	A0,A1
	bcc.b	.addrloop	; end?
	sub.l	A0,A0
.exit:
	RESTORE_REGS	D1/D3/A1-A2
	rts


; *** Waits for LMB while the screen is full of colors
; *** Useful to see if a point is reached
; *** interrupts are enabled

WaitMouseInterrupt:
	STORE_REGS

	lea	$DFF000,A6
	move.w	SR,D1
	move.w	intenar(A6),D2
	or.w	#$8000,D2

	move.w	#$2000,SR
	move.w	#$C028,intena(A6)


.1
	move.w	d0,$dff180
	addq.w	#7,D0
	btst	#6,$bfe001
	bne	.1

.2
	btst	#6,$bfe001
	beq	.2		; waits for release

	move.w	D1,SR
	move.w	D2,intena(A6)

	RESTORE_REGS
	rts

; *** returns the length of the file once decrunched
; in: A0: pointer on the memory zone
; out: D0: decrunched length (-1 if not rnc)

RNCLength:
	moveq.l	#-1,D0
	CMPI.L         #$524E4301,(A0)	; RNC\01 tag.
	beq	.ok			; not a rnc01 file
	CMPI.L         #$524E4302,(A0)	; RNC\02 tag.
	bne	.exit			; not a rnc file
.ok
	move.l	4(A0),D0
.exit
	rts


; *** returns the length of the file once decrunched
; in: A0: pointer on the memory zone
; out: D0: decrunched length (-1 if not rnc)

ATNLength:
	moveq.l	#-1,D0
	CMPI.L         #'ATN!',(A0)	; ATN! tag.
	beq	.ok			; not a rnc01 file
	CMPI.L         #'IMP!',(A0)	; IMP! tag.
	bne	.exit			; not a rnc file
.ok
	move.l	4(A0),D0
.exit
	rts

; *** waits using the beam register (thanks Harry)

BeamDelay:
.loop1
	tst.w	d0
	beq.b	.exit	; don't wait
	move.w  d0,-(a7)
        move.b	$dff006,d0
.loop2
	cmp.b	$dff006,d0
	beq.s	.loop2
	move.w	(a7)+,d0
	dbf	d0,.loop1
.exit
	RTS

; *** waits for blitter operation to finish

WaitBlit:
	TST.B	dmaconr+$DFF000
	BTST	#6,dmaconr+$DFF000
	BNE.S	.wait
	RTS
.wait
	TST.B	$BFE001
	TST.B	$BFE001
	BTST	#6,dmaconr+$DFF000
	BNE.S	.wait
	TST.B	dmaconr+$DFF000
	RTS

; *** Reset the CIAs for the keyboard
; *** Thanks to Alain Malek for this piece of code

ResetCIAs:
	move.b  #$c0,$bfd200            ;reinit CIAs
	move.b  #$ff,$bfd300            ;for
	move.b  #$03,$bfe201            ;KB
;	move.b  #$7f,$bfec01
	move.b  #$00,$bfee01
	move.b  #$88,$bfed01

	tst.b	$bfdd00			; acknowledge CIA-B Timer A interrupt
	tst.b	$bfed01			; acknowledge CIA-A interrupts

	bsr	AckKeyboard

	rts

AckKeyboard:
	STORE_REGS	D0
	bset	#$06,$BFEE01
	moveq.l	#3,D0
	bsr	BeamDelay
	bclr	#$06,$BFEE01
	RESTORE_REGS	D0
	rts

colored_beam_delay:
.loop1
	tst.w	d0
	beq.b	.exit	; don't wait
	move.w  d0,-(a7)
    move.b	$dff006,d0
.loop2
	move.w	D1,$DFF180
	cmp.b	$dff006,d0
	beq.s	.loop2
	move.w	(a7)+,d0
	dbf	d0,.loop1
.exit
	rts

	; cdio eats a lot of stack, not suitable for all games
	; this stack is shared by RN decruncher, same issue (when game files are packed)
	blk.b	CDIO_STACK_SIZE,0
cdio_stack:
	dc.l	0	; required by RN routine, return code stored here
old_stack:
	dc.l	0	
		IFEQ	1
alternate_color_error:
	move.l	#5000,D0
	bsr	colored_beam_delay
	exg.l	D2,D1
	move.l	#5000,D0
	bsr	colored_beam_delay
	exg.l	D2,D1
	bra	alternate_color_error
	ENDC
	