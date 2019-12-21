	movem.l	d0-d3/A0/A1,-(a7)

	; < A0: source
	; < A1: destination
	; < D0: size
	
	cmp.l	A0,A1
	beq.b	.exit		; same regions: out	
	bcs.b	.copyfwd	; A1 < A0: copy from start

	tst.l	D0
	beq.b	.exit		; length 0: out

	; here A0 > A1, copy from end

	add.l	D0,A0		; adds length to A0
	cmp.l	A0,A1
	bcc.b	.cancopyfwd	; A0+D0<=A1: can copy forward (optimized)
	add.l	D0,A1		; adds length to A1 too

.copybwd:
	move.b	-(A0),-(A1)
	subq.l	#1,D0
	bne.b	.copybwd

.exit
	movem.l	(a7)+,d0-d3/A0/A1
	rts

.cancopyfwd:
	sub.l	D0,A0		; restores A0 from A0+D0 operation
.copyfwd:
	move.l	A0,D1
	btst	#0,D1
	bne.b	.fwdbytecopy	; src odd: byte copy
	move.l	A1,D1
	btst	#0,D1
	bne.b	.fwdbytecopy	; dest odd: byte copy

	move.l	D0,D2
	lsr.l	#4,D2		; divides by 16
	move.l	D2,D3
	beq.b	.fwdbytecopy	; < 16: byte copy

.fwd4longcopy
	move.l	(A0)+,(A1)+
	move.l	(A0)+,(A1)+
	move.l	(A0)+,(A1)+
	move.l	(A0)+,(A1)+
	subq.l	#1,D2
	bne.b	.fwd4longcopy

	lsl.l	#4,D3		; #of bytes*16 again
	sub.l	D3,D0		; remainder of 16 division

.fwdbytecopy:
	tst.l	D0
	beq.b	.exit
.fwdbytecopy_loop:
	move.b	(A0)+,(A1)+
	subq.l	#1,D0
	bne.b	.fwdbytecopy_loop
	bra.b	.exit
