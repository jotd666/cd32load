	XDEF	pgloader
	XDEF	pgloader_end
	XDEF	rnloader
	XDEF	rnloader_end
rnloader:
	;incbin	"rnloader.bin"
	include	"rnloader.asm"
rnloader_end
pgloader:
	;incbin	"cd32loader.bin"
	include	"cd32loader.asm"
pgloader_end
