		incdir	"include:"
		include	"exec/types.i"

;----------------------------------------------
;HOW TO USE
;
;---init the drive
; moveq	#CD_DRIVEINIT,d0
; moveq	#CDREADSPEEDX2,d1
; lea	($1E0000),a0
; jsr	CD32_LOADER
; tst.w	d0
; bmi	.error

;---set a current dir
; moveq	#CD_CURRENTDIR,d0
; lea	(_path),a0
; jsr	CD32_LOADER
; tst.w	d0
; bmi	.error
;...
;_path	dc.b	"Games/PuttySquad/data",0

;---load a file from current dir
; moveq	#CD_READFILE,d0
; lea	(_file),a0
; lea	($20000), a1
; jsr	CD32_LOADER
; tst.w	d0
; bmi	.error
;...
;---load another file from current dir
; moveq	#CD_READFILE,d0
; lea	(_file2),a0
; lea	($30000), a1
; jsr	CD32_LOADER
; tst.w	d0
; bmi	.error
;
;_file	dc.b	"game",0
;_file2	dc.b	"sound/noise",0

;---load a part of file from current dir
; moveq	#CD_READFILEOFFSET,d0
; move.l #$100,d1		;size
; move.l #$200,d2		;offset
; lea	(_file),a0
; lea	($20000), a1
; jsr	CD32_LOADER
; tst.w	d0
; bmi	.error
;...

;----------------------------------------------
;COMMANDS

 ENUM	0
 EITEM	CD_DRIVEINIT
 EITEM	CD_INFOSTATUS
 EITEM	CD_SETREADSPEED
 EITEM	CD_CURRENTDIR
 EITEM	CD_READSECTOR
 EITEM	CD_GETFILEINFO
 EITEM	CD_READFILE
 EITEM	CD_READFILEOFFSET

;----------------------------------------------
;CD_DRIVEINIT				;init the CD drive
; IN:	D1 = CDREADSPEEDX1 or CDREADSPEEDX2
;	A0 = APTR CD-ROM buffer (24-bit & 64k-aligned (&zeroed) memory, size: $11600 bytes)
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;
;CD_INFOSTATUS				;get info status
; IN:	-
; OUT:	D0 = (CDSTSF.w<<16!CDLERR.w)
;
;CD_SETREADSPEED			;set the CD read speed
; IN:	D1 = CDREADSPEEDX1 or CDREADSPEEDX2
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;
;CD_CURRENTDIR				;set a current dir
; IN:	A0 = APTR full path
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;
;CD_READSECTOR				;read sectors from CD
; IN:	D1 = sector offset
;	D2 = number of sectors (1 sector = 2048 bytes)
;	A1 = APTR destination
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;	D1 = bytes read
;
;CD_GETFILEINFO				;get file size and sector offset
; IN:	A0 = APTR filename
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;	D1 = sector offset
;	D2 = file size
;
;CD_READFILE				;read a file
; IN:	A0 = APTR filename
;	A1 = APTR destination
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;	D1 = bytes read
;
;CD_READFILEOFFSET			;read a file part
; IN:	D1 = size
;	D2 = offset
;	A0 = APTR filename
;	A1 = APTR destination
; OUT:	D0 = (CDSTF.w<<16!CDLERR.w)
;	D1 = bytes read

;----------------------------------------------
; Error definitions

CDLERR_OK		equ 0       ;success
CDLERR_NOCMD		equ -1	    ;unknown command
CDLERR_DRIVEINIT	equ -2	    ;drive can not be initialized
CDLERR_IRQ		equ -3	    ;interrupt error
CDLERR_ABORTDRIVE	equ -4      ;disk has changed
CDLERR_CMDREAD		equ -5	    ;command read offset error
CDLERR_NODISK		equ -6	    ;no disk / no motor on
CDLERR_BADTOC		equ -7	    ;no TOC / disk unreadable
CDLERR_NODATA		equ -8      ;CD-ROM have not data
CDLERR_FILENOTFOUND	equ -9      ;error while loading file
CDLERR_DIRNOTFOUND	equ -10	    ;file/dir name not found
CDLERR_READOFFSET	equ -11	    ;read file offset error

;----------------------------------------------
; Flags for Status

CDSTSB_CLOSED	    equ 0	 ; Drive door is closed
CDSTSB_DISK	    equ 1	 ; A disk has been detected
CDSTSB_SPIN	    equ 2	 ; Disk is spinning (motor is on)
CDSTSB_TOC	    equ 3	 ; Table of contents read.  Disk is valid.
CDSTSB_CDROM	    equ 4	 ; Track 1 contains CD-ROM data
CDSTSB_PLAYING	    equ 5	 ; Audio is playing
CDSTSB_PAUSED	    equ 6	 ; Pause mode (pauses on play command)
CDSTSB_SEARCH	    equ 7	 ; Search mode (Fast Forward/Fast Reverse)
CDSTSB_DIRECTION    equ 8	 ; Search direction (0 = Forward, 1 = Reverse)
CDSTSB_READSPEED    equ 9	 ; CD read speed (0 = Default X1, 1 = DoubleSpeed X2)

CDSTSF_CLOSED	    equ $0001
CDSTSF_DISK	    equ $0002
CDSTSF_SPIN	    equ $0004
CDSTSF_TOC	    equ $0008
CDSTSF_CDROM	    equ $0010
CDSTSF_PLAYING	    equ $0020
CDSTSF_PAUSED	    equ $0040
CDSTSF_SEARCH	    equ $0080
CDSTSF_DIRECTION    equ $0100
CDSTSF_READSPEED    equ $0200

; CD read speed
CDREADSPEEDX1	    equ 0	    ;default speed
CDREADSPEEDX2	    equ 1	    ;double speed
