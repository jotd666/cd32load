;;SAFE_CONTEXT = 1
CD_BUFFER_SIZE = $11600

AKIKO_BASE = $B80000
AKIKO_INTENA = $B80008
AKIKO_INTREQ = $B80004	; read only
AKIKO_TRANSFER_REQ = $B80020	; not sure of the name of the register
AKIKO_DMA = $B80024
AKIKO_DMA_STOP = $13ffffff   ; clear bits 31, 30, 29, 27, 26 mask
AKIKO_ID = $C0CACAFE
;TOC_SIZE = 4
STATUS_OUT_SIZE = 48

AKIKO_CDINTERRUPT_SUBCODE =   $80000000
AKIKO_CDINTERRUPT_DRIVEXMIT = $40000000 ; not used by ROM. PIO mode.
AKIKO_CDINTERRUPT_DRIVERECV = $20000000 ; not used by ROM. PIO mode. 
AKIKO_CDINTERRUPT_RXDMADONE = $10000000
AKIKO_CDINTERRUPT_TXDMADONE = $08000000
AKIKO_CDINTERRUPT_PBX       = $04000000
AKIKO_CDINTERRUPT_OVERFLOW  = $02000000

GETVAR_L:MACRO
	IFNE	NARG-2
		FAIL	arguments "GETVAR_L"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	move.l	(RelVar_\1,A4),\2
	ENDM
GETVAR_W:MACRO
	IFNE	NARG-2
		FAIL	arguments "GETVAR_W"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	move.w	(RelVar_\1,A4),\2
	ENDM
GETVAR_B:MACRO
	IFNE	NARG-2
		FAIL	arguments "GETVAR_B"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	move.b	RelVar_\1(A4),\2
	ENDM
CLRVAR_L:MACRO
	IFNE	NARG-1
		FAIL	arguments "CLRVAR_L"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	clr.l	(RelVar_\1,A4)
	ENDM
CLRVAR_W:MACRO
	IFNE	NARG-1
		FAIL	arguments "CLRVAR_W"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	clr.w	(RelVar_\1,A4)
	ENDM
CLRVAR_B:MACRO
	IFNE	NARG-1
		FAIL	arguments "CLRVAR_B"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	clr.b	(RelVar_\1,A4)
	ENDM
CMPVAR_L:MACRO
	IFNE	NARG-2
		FAIL	arguments "CMPVAR_L"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	cmp.l	(RelVar_\1,A4),\2
	ENDM

ADDVAR_L:MACRO
	IFNE	NARG-2
		FAIL	arguments "ADDVAR_L"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	add.l	(RelVar_\1,A4),\2
	ENDM
ADDVAR_B:MACRO
	IFNE	NARG-2
		FAIL	arguments "ADDVAR_B"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	add.b	(RelVar_\1,A4),\2
	ENDM

ADD2VAR_B:MACRO
	IFNE	NARG-2
		FAIL	arguments "ADD2VAR_B"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	add.b	\1,(RelVar_\2,A4)
	ENDM
ADD2VAR_W:MACRO
	IFNE	NARG-2
		FAIL	arguments "ADD2VAR_W"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	add.w	\1,(RelVar_\2,A4)
	ENDM

SUBVAR_L:MACRO
	IFNE	NARG-2
		FAIL	arguments "SUBVAR_L"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	sub.l	(RelVar_\1,A4),\2
	ENDM

SUBVAR_B:MACRO
	IFNE	NARG-2
		FAIL	arguments "SUBVAR_B"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	sub.b	(RelVar_\1,A4),\2
	ENDM

SETVAR_L:MACRO
	IFNE	NARG-2
		FAIL	arguments "SETVAR_L"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	move.l	\1,(RelVar_\2,A4)
	ENDM
SETVAR_W:MACRO
	IFNE	NARG-2
		FAIL	arguments "SETVAR_W"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	move.w	\1,(RelVar_\2,A4)
	ENDM
SETVAR_B:MACRO
	IFNE	NARG-2
		FAIL	arguments "SETVAR_B"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	move.b	\1,(RelVar_\2,A4)
	ENDM
TSTVAR_L:MACRO
	IFNE	NARG-1
		FAIL	arguments "TSTVAR_L"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	tst.l	(RelVar_\1,A4)
	ENDM
TSTVAR_W:MACRO
	IFNE	NARG-1
		FAIL	arguments "TSTVAR_W"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	tst.w	(RelVar_\1,A4)
	ENDM
TSTVAR_B:MACRO
	IFNE	NARG-1
		FAIL	arguments "TSTVAR_B"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	tst.b	(RelVar_\1,A4)
	ENDM
CMPVAR_B:MACRO
	IFNE	NARG-2
		FAIL	arguments "CMPVAR_B"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	cmp.b	(RelVar_\1,A4),\2
	ENDM
CMP2VAR_B:MACRO
	IFNE	NARG-2
		FAIL	arguments "CMP2VAR_B"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	cmp.b	\1,(RelVar_\2,A4)
	ENDM
CMP2VAR_W:MACRO
	IFNE	NARG-2
		FAIL	arguments "CMP2VAR_W"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	cmp.w	\1,(RelVar_\2,A4)
	ENDM
CMPVAR_W:MACRO
	IFNE	NARG-2
		FAIL	arguments "CMPVAR_W"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	cmp.w	(RelVar_\1,A4),\2
	ENDM

LEAVAR:MACRO
	IFNE	NARG-2
		FAIL	arguments "LEAVAR"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	lea	(RelVar_\1,A4),\2
	ENDM

; lea with a data register

LEAVAR_D:MACRO
	IFNE	NARG-2
		FAIL	arguments "LEAVAR_D"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	STORE_REGS	A4
	LEAVAR	\1,A4	; destroy A4!
	move.l	A4,\2
	RESTORE_REGS	A4
	ENDM

PEAVAR:MACRO
	IFNE	NARG-1
		FAIL	arguments "PEAVAR"
	ENDC
	IFD	SAFE_CONTEXT
	SET_VAR_CONTEXT
	ENDC
	pea	(RelVar_\1,A4)
	ENDM

	STRUCTURE	SharedVars,0
	; putting relocated VBR first, so JST! id allows to locate
	; variables start
	STRUCT	RelVar_relocated_vbr,256
	STRUCT	RelVar_custom_str,$80
	STRUCT	RelVar_data_directory,$80
	STRUCT	RelVar_raw_ascii_table,256
	STRUCT	RelVar_last_loaded_file,256
	ULONG	RelVar_last_loaded_filesize
	STRUCT	RelVar_last_whd_function_called,20
	STRUCT	RelVar_last_whd_parameters,5*8	; A0,A1,D0,D1,D2 are enough for every call
	ULONG	RelVar_io_call_ptr
	ULONG	RelVar_nb_retries
	ULONG	RelVar_custom1_flag
	ULONG	RelVar_custom2_flag
	ULONG	RelVar_custom3_flag
	ULONG	RelVar_custom4_flag
	ULONG	RelVar_custom5_flag
	ULONG   RelVar_filecache_flag
	ULONG	RelVar_pal_flag
	ULONG	RelVar_ntsc_flag
	ULONG	RelVar_delay_cdinit_flag
	ULONG	RelVar_cdfreeze_flag
	ULONG	RelVar_nobuffercheck_flag
	ULONG	RelVar_readdelay_value
	ULONG	RelVar_debug_flag
	ULONG	RelVar_cdreadspeedx1_flag
	ULONG	RelVar_retrydelay_value
	ULONG	RelVar_buttonwait_flag
	ULONG	RelVar_filteroff_flag
	ULONG	RelVar_d_flag
	ULONG	RelVar_novbrmove_flag
	ULONG	RelVar_mask_int_2_flag
	ULONG	RelVar_mask_int_6_flag
	ULONG	RelVar_cdio_buffer
	ULONG	RelVar_cdio_buffer_1
	ULONG	RelVar_cdio_buffer_2
	ULONG	RelVar_free_buffer
	ULONG	RelVar_free_buffer_caching_address
	ULONG	RelVar_cpucache_flag
	ULONG	RelVar_joypad_flag
	ULONG	RelVar_whd_slave_reloc_start
	ULONG	RelVar_cd_slave_reloc_start
	ULONG	RelVar_slaves_size
	ULONG	RelVar_previous_joy0_state
	ULONG	RelVar_previous_joy1_state
	ULONG	RelVar_last_joy0_state
	ULONG	RelVar_last_joy1_state
	ULONG	RelVar_maxchip
	ULONG	RelVar_extsize
	ULONG	RelVar_top_game_mem
	ULONG	RelVar_top_system_chipmem
	ULONG	RelVar_read_buffer_address
	ULONG	RelVar_attnflags
	UWORD	RelVar_whdflags
	ULONG	RelVar_eclock_freq
	ULONG	RelVar_last_io_error
	ULONG	RelVar_resload_top
	ULONG	RelVar_saved_akiko_intena   ; useless
	ULONG	RelVar_saved_akiko_dma
	ULONG	RelVar_kicksize
	ULONG	RelVar_kickstart_ptr
	ULONG	RelVar_kick_and_rtb_size
	ULONG	RelVar_loader
	ULONG	RelVar_use_fastmem
	STRUCT	RelVar_sys_ciaregs,4*6
	STRUCT	RelVar_saved_instructions,6
	UBYTE	RelVar_in_resload
	UBYTE	RelVar_pad01

	ULONG	RelVar_vm_delay
	ULONG	RelVar_vm_modifierdelay
	ULONG	RelVar_vm_currentdelay
	UWORD	RelVar_ledstate
	UWORD	RelVar_saved_dmacon
	UWORD   RelVar_system_bplcon0
	
	; function pointers for CD loading
	ULONG	RelVar_init_drive
	ULONG	RelVar_get_file_size
	ULONG	RelVar_read_file
	ULONG	RelVar_read_file_part
	ULONG	RelVar_set_current_dir
	ULONG	RelVar_reset_current_dir


	ULONG	RelVar_timeout_value
	ULONG	RelVar_counter_value
	ULONG	RelVar_autoreboot_flag
	ULONG	RelVar_resload_vbr
	;ULONG	RelVar_debugger_base
	ULONG	RelVar_game_vbl_interrupt

	; audio CD slave hooks, do not change order
	ULONG	RelVar_Decrunch_hook_address
	ULONG	RelVar_DiskLoad_hook_address
	ULONG	RelVar_LoadFile_hook_address
	ULONG	RelVar_LoadFileDecrunch_hook_address
	ULONG	RelVar_LoadFileOffset_hook_address
	ULONG	RelVar_Patch_hook_address
	ULONG	RelVar_PatchSeg_hook_address
	ULONG	RelVar_Relocate_hook_address
	; end audio CD slave hooks
	
	; this value is set by the cd_play command (2 or more)
	; and cleared by cd_stop or data cd read
	; it's used in the VBL routine so if loop is set
	; then the track plays again
	UWORD	RelVar_cd_track_playing
	UWORD	RelVar_cd_track_loop
	
	; audio CD variables
	STRUCT	RelVar_cdaudio_statusout,STATUS_OUT_SIZE
	UWORD	RelVar_cdaudio_cd_playing
	ULONG	RelVar_cdaudio_oldakikointena
	ULONG	RelVar_cdaudio_oldakikodma
	UWORD	RelVar_cdaudio_statusoffset
	UWORD	RelVar_cdaudio_statuspacket_size
	UWORD	RelVar_cdaudio_statuspacket_offset
	ULONG	RelVar_cdaudio_statuspacket_start_addr
	UWORD	RelVar_cdaudio_play_status
	UBYTE	RelVar_cdaudio_regs_saved
	UBYTE	RelVar_cdaudio_toc_total
	UBYTE	RelVar_cdaudio_toc_found
	UBYTE	RelVar_cdaudio_playing_status
	STRUCT	RelVar_cdaudio_toc_data,400 ; TOC_SIZE*100
	; misc
	UBYTE	RelVar_realcd32_flag
	UBYTE	RelVar_freeze_key
	UBYTE	RelVar_joy1_play_keycode
	UBYTE	RelVar_joy1_fwd_keycode
	UBYTE	RelVar_joy1_bwd_keycode
	UBYTE	RelVar_joy1_green_keycode
	UBYTE	RelVar_joy1_blue_keycode
	UBYTE	RelVar_joy1_yellow_keycode
	UBYTE	RelVar_joy1_fwdbwd_keycode
	UBYTE	RelVar_joy1_fwdbwd_active
	UBYTE	RelVar_joy1_red_keycode
	UBYTE	RelVar_joy1_right_keycode
	UBYTE	RelVar_joy1_left_keycode
	UBYTE	RelVar_joy1_up_keycode
	UBYTE	RelVar_joy1_down_keycode
	UBYTE	RelVar_joy0_play_keycode
	UBYTE	RelVar_joy0_fwd_keycode
	UBYTE	RelVar_joy0_bwd_keycode
	UBYTE	RelVar_joy0_green_keycode
	UBYTE	RelVar_joy0_blue_keycode
	UBYTE	RelVar_joy0_yellow_keycode
	UBYTE	RelVar_joy0_fwdbwd_keycode
	UBYTE	RelVar_joy0_fwdbwd_active
	UBYTE	RelVar_joy0_red_keycode
	UBYTE	RelVar_joy0_right_keycode
	UBYTE	RelVar_joy0_left_keycode
	UBYTE	RelVar_joy0_up_keycode
	UBYTE	RelVar_joy0_down_keycode
	UBYTE	RelVar_vk_on
	UBYTE	RelVar_vk_wason
	UBYTE	RelVar_vk_selected_character
	UBYTE	RelVar_vk_queued
	UBYTE	RelVar_vk_key_delay
	UBYTE	RelVar_vk_button
	UBYTE	RelVar_vk_keyup
	UBYTE	RelVar_vm_button
	UBYTE	RelVar_vm_enabled
	UBYTE	RelVar_vm_modifierbutton
	UBYTE	RelVar_quitkey
	UBYTE	RelVar_use_rn_loader
	UBYTE	RelVar_vbl_redirect
	UBYTE   RelVar_system_chiprev_bits
	UBYTE	RelVar_disable_file_dir_error
	UBYTE	RelVar_cdio_in_progress
	LABEL	RelVar_SIZEOF


