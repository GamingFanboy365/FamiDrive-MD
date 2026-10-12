; ===========================================================================
; +-----------------------------------------------------------------+
; FamiDrive beta
; A Modification of Nemul by Mairtrus
; 
; Now works on real hardware
; +-----------------------------------------------------------------+

		include	"system/macros.asm"	; Assembler macros
		include	"system/md/const.asm"	; RAM / Variables are here
		include	"system/md/map.asm"	; Genesis hardware map

; ====================================================================
; ----------------------------------------------------------------
; Emulator variables
; ----------------------------------------------------------------

; ------------------------------------------------
; RAM
; ------------------------------------------------

RAM_Fami_ROM	equ $FFFF0000		; PRG-ROM
RAM_Fami_Emu	equ $FFFF8000		; Emulator buffer
RAM_Fami_RAM	equ $FFFF9000		; RAM size: $800
RAM_Fami_PPU	equ $FFFFA000		; PPU size: $3EF8 (TODO: still uses negative variables)

; ----------------------------------------------------------------
; CPU
; ----------------------------------------------------------------

cpuNMI		equ $7FFA
cpuEntry	equ $7FFC
cpuIRQ		equ $7FFE

; ----------------------------------------------------------------
; Emulator
; ---------------------------------------------------------------

		struct RAM_Fami_Emu+$FF0
RAM_EmuLoop	ds.w 3
		finish

; ----------------------------------------------------------------
; Unsorted
; ----------------------------------------------------------------

		struct 0
emuPrgRom	ds.l 1
emuChrRom	ds.l 1
famiVintSave	ds.l 8
famiVintSave2	ds.w 1
cpuSprHint	ds.w 1;equ -$38
vdpReg00	ds.w 1
vdpReg01	ds.w 1;equ -$36
ppuMirror	ds.w 1;equ -$34
cpuMapper	ds.w 1;equ -$32
cpuFamiVint	ds.w 1;equ -$30
cpuInputData	ds.w 2;equ -$28
cpuModeDec	ds.w 1;equ -$22
cpuFlag2	ds.w 1;equ -$20
cpuModeIntDis	ds.w 1;equ -$1E
ppuNTblBase	ds.w 1;equ -$1A
ppuChrBank	ds.w 1;equ -$18
ppuOamAddr	ds.w 1;equ -$16
ppuAddrIncr	ds.w 1;equ -$14
ppuAddrBase	ds.w 1;equ -$12
ppuDataLast	ds.w 1;equ -$10
ppuSprWide	ds.w 1;equ -$E
ppuSp0Ypos	ds.w 1;equ -$C
ppuAddrLatch	ds.w 1;equ -$A
ppuOamUnk	ds.w 1;equ -6
ppuNmiFlag	ds.w 1;equ -4
ppuStatus	ds.w 1;equ -2
vdpHintSp0	ds.w 1
FamiMdVint	ds.w 1
FamiPPUVint	ds.w 1
ppuChrRam	ds.w 1			; 1 - pattern tables are CHR-RAM
vdpScrlX	ds.l 1
vdpScrlY	ds.l 1
vdpPalette	ds.w 64
vdpSprData	ds.w 8*64
		finish

; ====================================================================
; Header
; ====================================================================

		dc.l 0
		dc.l MD_Entry
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Hint
		dc.l MD_Error
		dc.l MD_Vint
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Error
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.l MD_Entry
		dc.b "SEGA MEGA DRIVE "
		dc.b "(C)GF64 2020.???"
		dc.b "FamiDrive                                       "
		dc.b "FamiDrive                                       "
		dc.b "GM HOMEBREW-00"
		dc.w 0
		dc.w 0
		dc.b "              "
		dc.l 0
		dc.l EndOfRom-1
		dc.l $FF0000
		dc.l $FFFFFF
		dc.l $20202020
		dc.l $20202020
		dc.l $20202020
		dc.b "                                                    "
		dc.b "JUE             "

; ====================================================================
; ----------------------------------------------------------------
; Error
; ----------------------------------------------------------------

MD_Error:
		lea	(errStrException).l,a0
		jmp	(MD_ShowError).l

; ====================================================================
; ----------------------------------------------------------------
; Entry
; ----------------------------------------------------------------

MD_Entry:
		move	#$2700,sr
		tst.l	($A10008).l
		bne.s	.reset_check
		tst.w	($A1000C).l
.reset_check:
		bne.w	MD_HotStart
		lea	(list_InitRegs).l,a5
		movem.w	(a5)+,d5-d7
		movem.l	(a5)+,a0-a4
		move.b	($A10001).l,d0
		andi.b	#$F,d0
		beq.w	old_md
		move.l	#"SEGA",($A14000).l
old_md:
		clr.l	d0
		movea.l	d0,a6
		move	a6,usp
clrstack:
		move.l	d0,-(a6)
		dbf	d6,clrstack
		bsr	Sound_LoadZ80
		bsr	Sound_PsgInit
		bsr	Video_Init
		movem.l	(a6),d0-a6
		move.b	#$40,($A10009).l
		move.b	#$40,($A1000B).l
MD_HotStart:
		bra.w	MD_Init
; ----------------------------------------------------------------
list_InitRegs:	dc.w $8000		; d5
		dc.w $3FFF		; d6
		dc.w $100		; d7
		dc.l $A00000		; a0
		dc.l $A11100		; a1
		dc.l $A11200		; a2
		dc.l $C00000		; a3
		dc.l $C00004		; a4
		dc.b $AF, 1, $D9, $1F, $11, $27, 0, $21, $26, 0, $F9, $77
		dc.b $ED, $B0, $DD, $E1, $FD, $E1, $ED,	$47, $ED, $4F
		dc.b $D1, $E1, $F1, 8, $D9, $C1, $D1, $E1, $F1,	$F9, $F3
		dc.b $ED, $56, $36, $E9, $E9, $81, 4, $8F, 1
		dc.b $9F
		dc.b $BF
		dc.b $DF
		dc.b $FF
; ----------------------------------------------------------------


Fami_InitVideo:
		move.w	#$8F02,4(a6)
		move.w	#$FFF,d7
		move.l	#$40000003,4(a6)
.loopfg:
		move.w	#$200,(a6)
		dbf	d7,.loopfg
		move.w	#$FFF,d7
		move.l	#$60000003,4(a6)
.loopbg:
		move.w	#$200,(a6)
		dbf	d7,.loopbg
		move.l	#$68000002,4(a6)
		move.l	#0,(a6)
		move.l	#$40000010,4(a6)
		move.l	#0,(a6)
		moveq	#$3F,d7
		move.l	#$C0000000,4(a6)

.clrpal:
		move.w	#0,(a6)
		dbf	d7,.clrpal
		rts


Sound_LoadZ80:
		move.w	d7,(a1)
		move.w	d7,(a2)

.wait_bus:
		btst	d0,(a1)
		bne.s	.wait_bus
		moveq	#$25,d2
.copy:
		move.b	(a5)+,(a0)+
		dbf	d2,.copy
		move.w	d0,(a2)
		move.w	d0,(a1)
		move.w	d7,(a2)
		rts


Sound_PsgInit:
		moveq	#3,d1

.psg:
		move.b	(a5)+,$11(a3)
		dbf	d1,.psg
		move.w	d0,(a2)
		rts


Video_Init:
		moveq	#$17,d0
		lea	(Video_RegList).l,a0
.regs:
		move.b	(a0)+,d5
		move.w	d5,(a4)
		add.w	d7,d5
		dbf	d0,.regs
		rts

; ----------------------------------------------------------------
Video_RegList:
		dc.b $04			; HBlank int on, HV Counter on
		dc.b $64			; Display ON, VBlank int on
		dc.b (($C000)>>10)		; ForeGrd at VRAM $C000 (%00xxx000)
		dc.b (($D000)>>10)		; Window  at VRAM $D000 (%00xxxxy0)
		dc.b (($E000)>>13)		; BackGrd at VRAM $E000 (%00000xxx)
		dc.b (($BC00)>>9)		; Sprites at VRAM $BC00 (%0xxxxxxy)
		dc.b $00			; Nothing
		dc.b $00			; Background color
		dc.b $00			; Nothing
		dc.b $00			; Nothing
		dc.b $DF			; HInt value
		dc.b (%000|%00)			; No ExtInt, Scroll: VSCR:full HSCR:full
		dc.b $00			; H40, No shadow mode, Normal resolution
		dc.b (($B800)>>10)		; HScroll at VRAM $B800 (%00xxxxxx)
		dc.b $00			; Nothing
		dc.b $02			; VDP Auto increment by $02
		dc.b (%01<<4)|%01		; Layer size: V32 H64
		dc.b $00
		dc.b $00
		align 2

; ====================================================================

MD_Init:
		move.b	#$40,($A10009).l
		move.b	#$40,($A1000B).l
		move.w	#$100,(z80_bus).l		; Stop Z80
		move.w	#$100,(z80_reset).l		; Reset cancel
.wait:
		btst	#0,(z80_bus).l			; Wait bus
		bne.s	.wait

		move.w	#0,(z80_reset).l		; Reset request
		nop
		nop
		nop
		move.w	#0,(z80_bus).l			; Start Z80
		move.w	#$100,(z80_reset).l		; Reset cancel
		
		bra	emuStart

; ====================================================================
; ----------------------------------------------------------------
; VBlank
; ----------------------------------------------------------------

MD_Vint:
		movem.l	d0-d7/a0-a6,-(sp)

		move.w	#$8F02,4(a6)
		move.l	#$78000002,4(a6)
		move.l	vdpScrlX(a4),(a6)
		move.l	#$40000010,4(a6)
		move.l	vdpScrlY(a4),(a6)
		move.l	#$94019318,4(a6)
		move.w	#$0100,(z80_bus).l
		move.l	#$96009500+(((RAM_Fami_Emu+vdpSprData)<<7)&$FF0000)|(((RAM_Fami_Emu+vdpSprData)>>1)&$FF),4(a6)
		move.w	#$9700|(((RAM_Fami_Emu+vdpSprData)>>17)&$7F),4(a6)
		move.w	#$7C00,4(a6)
		move.w	#$0002|$80,-(sp)
.wait:		btst	#0,(z80_bus).l
		bne.s	.wait
		move.w	(sp)+,4(a6)
		move.l	#$94009340,4(a6)
		move.l	#$96009500+(((RAM_Fami_Emu+vdpPalette)<<7)&$FF0000)|(((RAM_Fami_Emu+vdpPalette)>>1)&$FF),4(a6)
		move.w	#$9700|(((RAM_Fami_Emu+vdpPalette)>>17)&$7F),4(a6)
		move.w	#$C000,4(a6)
		move.w	#$0000|$80,-(sp)
.wait2:		btst	#0,(z80_bus).l
		bne.s	.wait2
		move.w	(sp)+,4(a6)
		move.w	#0,(z80_bus).l			; Release Z80

		clr.w	vdpHintSp0(a4)
		move.w	#1,FamiMdVint(a4)
		move.w	#1,FamiPPUVint(a4)
		movem.l	(sp)+,d0-d7/a0-a6
		rte

; ====================================================================
; ----------------------------------------------------------------
; HBlank
; ----------------------------------------------------------------

MD_Hint:
; 		move.w	#$2700,sr
; 		move.w	#$8ADF,4(a6)
; 		move.w	#1,vdpHintSp0(a4)
		rte

; ====================================================================
; ----------------------------------------------------------------
; Load ROM
; ----------------------------------------------------------------

Fami_LoadRom:
		cmpi.l	#$4E45531A,(a0)		; "NES",$1A
		beq.s	.header_ok
		lea	(errStrBadHeader).l,a0
		jmp	(MD_ShowError).l
.header_ok:

	; Mapper number. Old dumps can have junk (e.g. "DiskDude!") in
	; bytes 7-15, so ignore byte 7 then unless it's an NES 2.0 header.
		move.b	7(a0),d6
		move.b	d6,d7
		andi.b	#%00001100,d7
		cmpi.b	#%00001000,d7
		beq.s	.mapper_hi
		tst.l	12(a0)
		beq.s	.mapper_hi
		moveq	#0,d6
.mapper_hi:
		andi.w	#%11110000,d6
		moveq	#0,d1
		move.b	6(a0),d1
		lsr.b	#4,d1
		or.b	d6,d1
		move.w	d1,d5			; keep for cpuMapper
		beq.s	.mapper_ok
		cmpi.b	#3,d1
		beq.s	.mapper_ok
		lea	(errStrMapper).l,a0
		jmp	(MD_ShowError).l
.mapper_ok:
		move.b	4(a0),d1		; PRG-ROM size in 16 KB units
		cmpi.b	#1,d1
		beq.s	.prg_ok
		cmpi.b	#2,d1
		beq.s	.prg_ok
		lea	(errStrPrgSize).l,a0
		jmp	(MD_ShowError).l
.prg_ok:

		lea	(RAM_Fami_RAM).l,a5
		moveq	#0,d0
		move.w	#$7FF/4,d1
.clrram:
		move.l	d0,(a5)+
		dbf	d1,.clrram
		lea	(RAM_Fami_PPU).l,a5
		moveq	#0,d0
		move.w	#($4000/4)-1,d1
.clrvram:
		move.l	d0,(a5)+
		dbf	d1,.clrvram
		lea 	($C00000),a6
		bsr	Fami_InitVideo

		lea	(RAM_Fami_Emu).l,a3
		moveq	#0,d7			; PRG-ROM copy
		move.b	4(a0),d7
		bsr	romGrabPrg
		lea	(RAM_Fami_Emu).l,a3	; romGrabPrg uses a3
		move.w	d5,cpuMapper(a3)
	
	; Mirror check
		move.w	#0,d7			; 0 - horizontal
		btst	#0,6(a0)		; PPU mirroring
		beq.s	.mirror_set
		move.w	#1,d7			; 1 - vertical
.mirror_set:
		move.w	d7,ppuMirror(a3)
		
	; COPY CHR-ROM TO RAM, or use the (cleared) buffer as CHR-RAM
		move.l	a4,emuChrRom(a3)
		tst.b	5(a0)
		bne.s	.chr_rom
		move.w	#1,ppuChrRam(a3)
		bra.s	.chr_done
.chr_rom:
		lea	(RAM_Fami_PPU).l,a5
		move.l	#$7FF,d7
.copy_chr:
		move.l	(a4)+,(a5)+
		dbf	d7,.copy_chr
.chr_done:
		adda	#$10,a0
		move.l	a0,emuPrgRom(a3)
		rts

; ====================================================================
; ----------------------------------------------------------------
; Emulator start
; ----------------------------------------------------------------

emuStart:
		lea 	($FFFF8000),a0
		move.w	#$2FFF/4,d1
		moveq	#0,d0
.clrram:
		move.l	d0,(a0)+
		dbf	d1,.clrram

		lea	(ROM_FILE).l,a0
		bsr	Fami_LoadRom
		
		lea	($C00000).l,a6
		lea 	(RAM_Fami_Emu),a4
		lea	(RAM_Fami_PPU).w,a3
		lea	(RAM_Fami_RAM).w,a2
		bsr	Nemul_LoadChr
		lea 	(RAM_Fami_ROM),a1	; PRG base
		movea.l	a1,a0
		move.w	#cpuEntry,d0		; go to Entry
		add.w	d0,a0
		move.b	1(a0),d0
		lsl.w	#8,d0
		move.b	(a0),d0
		and.w	#$7FFF,d0
		movea.l	a1,a0
		adda	d0,a0
		move.w	#$8004,vdpReg00(a4)
		move.w	#$8174,vdpReg01(a4)
		move.w	#1,ppuAddrIncr(a4)		; $2000 is 0 at power on: +1
		move.w	#$4EF9,(RAM_EmuLoop).l		; JMP opcode
		move.l	#emuLoop,(RAM_EmuLoop+2).l	; default emulation loop
		moveq	#0,d0
		moveq	#0,d1
		moveq	#0,d2
		move.l	#$01002000,d3
		bra.s	emuLoop

; --------------------------------------------------------
; a0 - Fami CPU current PC
; a1 - Fami PRG address
; a2 - Fami RAM address (for zero addressing)
; a3 - Fami PPU Buffer
; a4 - Fami EMU Buffer
; a5 - Used on temporal tasks
; a6 - VDP data point
; 
; d0 - A register
; d1 - X register
; d2 - Y register
; d3 - Fami STACK Point | Current SR
; d4 - free
; d5 - free
; d6 - free
; d7 - emu temporal input/output
; --------------------------------------------------------

; The 6502's N, Z, V and C flags are kept in the 68k CCR
; (low byte of d3, with X mirroring C) so opcodes can use
; the 68k's own flag results. I and D are kept separately.
; famiGetP/famiSetP convert to and from the 6502's P byte.

; ------------------------------------------------
; VBlank
; ------------------------------------------------

famiVInt:
		clr.w	FamiMdVint(a4)
		move.w	#$80,ppuStatus(a4)
		tst.w	cpuFamiVint(a4)
		bne.s	emuVint
		tst.w	ppuNmiFlag(a4)
		beq.s	emuVint

; ------------------------------------------------
doVint:
		move.l	#emuVint,(RAM_EmuLoop+2).l
		move.w	#1,cpuFamiVint(a4)

		bsr	famiGetP		; Save PC and P (B clear)
		move.b	d5,d7
		andi.b	#$EF,d7
		swap	d3
		move.l	a0,d4
		sub.l	#RAM_Fami_ROM,d4
		move.b	d4,d5
		lsr.w	#8,d4
		or.b	#$80,d4
		move.b	d4,(a2,d3.w)
		subq.b	#1,d3
		move.b	d5,(a2,d3.w)
		subq.b	#1,d3
		move.b	d7,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		move.w	#1,cpuModeIntDis(a4)

		lea 	(RAM_Fami_ROM),a0	; PRG base
		move.w	#cpuNMI,d6		; go to NMI
		add.w	d6,a0
		move.b	1(a0),d6
		lsl.w	#8,d6
		move.b	(a0),d6
		and.w	#$7FFF,d6
		movea.l	a1,a0
		add.w	d6,a0
		bra	emuVint

; ------------------------------------------------
; Main Loop
; ------------------------------------------------

emuLoop:
		tst.w	FamiMdVint(a4)
		bne.s	famiVInt
emuVint:
		clr.w	d4
		move.b	(a0)+,d4
		add.w	d4,d4
		move.w	mosCpu(pc,d4.w),d6
		jmp	mosCpu(pc,d6.w)	; mosCpu must stay right after this

		
; ----------------------------------------------------------------
mosCpu:		dc.w mos_BRK-mosCpu	; $00
		dc.w mos_ORA_indx-mosCpu	; $01
		dc.w mos_Null-mosCpu	; $02
		dc.w mos_Null-mosCpu	; $03
		dc.w mos_Null-mosCpu	; $04
		dc.w mos_ORA_zp-mosCpu	; $05
		dc.w mos_ASL_zp-mosCpu	; $06
		dc.w mos_Null-mosCpu	; $07
		dc.w mos_PHP-mosCpu	; $08
		dc.w mos_ORA_imm-mosCpu	; $09
		dc.w mos_ASL_acc-mosCpu	; $0A
		dc.w mos_Null-mosCpu	; $0B
		dc.w mos_Null-mosCpu	; $0C
		dc.w mos_ORA_abs-mosCpu	; $0D
		dc.w mos_ASL_abs-mosCpu	; $0E
		dc.w mos_Null-mosCpu	; $0F
		dc.w mos_BPL-mosCpu	; $10
		dc.w mos_ORA_indy-mosCpu	; $11
		dc.w mos_Null-mosCpu	; $12
		dc.w mos_Null-mosCpu	; $13
		dc.w mos_Null-mosCpu	; $14
		dc.w mos_ORA_zpx-mosCpu	; $15
		dc.w mos_ASL_zpx-mosCpu	; $16
		dc.w mos_Null-mosCpu	; $17
		dc.w mos_CLC-mosCpu	; $18
		dc.w mos_ORA_absy-mosCpu	; $19
		dc.w mos_Null-mosCpu	; $1A
		dc.w mos_Null-mosCpu	; $1B
		dc.w mos_Null-mosCpu	; $1C
		dc.w mos_ORA_absx-mosCpu	; $1D
		dc.w mos_ASL_absx-mosCpu	; $1E
		dc.w mos_Null-mosCpu	; $1F
		dc.w mos_JSR-mosCpu	; $20
		dc.w mos_AND_indx-mosCpu	; $21
		dc.w mos_Null-mosCpu	; $22
		dc.w mos_Null-mosCpu	; $23
		dc.w mos_BIT_zp-mosCpu	; $24
		dc.w mos_AND_zp-mosCpu	; $25
		dc.w mos_ROL_zp-mosCpu	; $26
		dc.w mos_Null-mosCpu	; $27
		dc.w mos_PLP-mosCpu	; $28
		dc.w mos_AND_imm-mosCpu	; $29
		dc.w mos_ROL_acc-mosCpu	; $2A
		dc.w mos_Null-mosCpu	; $2B
		dc.w mos_BIT_abs-mosCpu	; $2C
		dc.w mos_AND_abs-mosCpu	; $2D
		dc.w mos_ROL_abs-mosCpu	; $2E
		dc.w mos_Null-mosCpu	; $2F
		dc.w mos_BMI-mosCpu	; $30
		dc.w mos_AND_indy-mosCpu	; $31
		dc.w mos_Null-mosCpu	; $32
		dc.w mos_Null-mosCpu	; $33
		dc.w mos_Null-mosCpu	; $34
		dc.w mos_AND_zpx-mosCpu	; $35
		dc.w mos_ROL_zpx-mosCpu	; $36
		dc.w mos_Null-mosCpu	; $37
		dc.w mos_SEC-mosCpu	; $38
		dc.w mos_AND_absy-mosCpu	; $39
		dc.w mos_Null-mosCpu	; $3A
		dc.w mos_Null-mosCpu	; $3B
		dc.w mos_Null-mosCpu	; $3C
		dc.w mos_AND_absx-mosCpu	; $3D
		dc.w mos_ROL_absx-mosCpu	; $3E
		dc.w mos_Null-mosCpu	; $3F
		dc.w mos_RTI-mosCpu	; $40
		dc.w mos_EOR_indx-mosCpu	; $41
		dc.w mos_Null-mosCpu	; $42
		dc.w mos_Null-mosCpu	; $43
		dc.w mos_Null-mosCpu	; $44
		dc.w mos_EOR_zp-mosCpu	; $45
		dc.w mos_LSR_zp-mosCpu	; $46
		dc.w mos_Null-mosCpu	; $47
		dc.w mos_PHA-mosCpu	; $48
		dc.w mos_EOR_imm-mosCpu	; $49
		dc.w mos_LSR_acc-mosCpu	; $4A
		dc.w mos_Null-mosCpu	; $4B
		dc.w mos_JMP_abs-mosCpu	; $4C
		dc.w mos_EOR_abs-mosCpu	; $4D
		dc.w mos_LSR_abs-mosCpu	; $4E
		dc.w mos_Null-mosCpu	; $4F
		dc.w mos_BVC-mosCpu	; $50
		dc.w mos_EOR_indy-mosCpu	; $51
		dc.w mos_Null-mosCpu	; $52
		dc.w mos_Null-mosCpu	; $53
		dc.w mos_Null-mosCpu	; $54
		dc.w mos_EOR_zpx-mosCpu	; $55
		dc.w mos_LSR_zpx-mosCpu	; $56
		dc.w mos_Null-mosCpu	; $57
		dc.w mos_CLI-mosCpu	; $58
		dc.w mos_EOR_absy-mosCpu	; $59
		dc.w mos_Null-mosCpu	; $5A
		dc.w mos_Null-mosCpu	; $5B
		dc.w mos_Null-mosCpu	; $5C
		dc.w mos_EOR_absx-mosCpu	; $5D
		dc.w mos_LSR_absx-mosCpu	; $5E
		dc.w mos_Null-mosCpu	; $5F
		dc.w mos_RTS-mosCpu	; $60
		dc.w mos_ADC_indx-mosCpu	; $61
		dc.w mos_Null-mosCpu	; $62
		dc.w mos_Null-mosCpu	; $63
		dc.w mos_Null-mosCpu	; $64
		dc.w mos_ADC_zp-mosCpu	; $65
		dc.w mos_ROR_zp-mosCpu	; $66
		dc.w mos_Null-mosCpu	; $67
		dc.w mos_PLA-mosCpu	; $68
		dc.w mos_ADC_imm-mosCpu	; $69
		dc.w mos_ROR_acc-mosCpu	; $6A
		dc.w mos_Null-mosCpu	; $6B
		dc.w mos_JMP_ind-mosCpu	; $6C
		dc.w mos_ADC_abs-mosCpu	; $6D
		dc.w mos_ROR_abs-mosCpu	; $6E
		dc.w mos_Null-mosCpu	; $6F
		dc.w mos_BVS-mosCpu	; $70
		dc.w mos_ADC_indy-mosCpu	; $71
		dc.w mos_Null-mosCpu	; $72
		dc.w mos_Null-mosCpu	; $73
		dc.w mos_Null-mosCpu	; $74
		dc.w mos_ADC_zpx-mosCpu	; $75
		dc.w mos_ROR_zpx-mosCpu	; $76
		dc.w mos_Null-mosCpu	; $77
		dc.w mos_SEI-mosCpu	; $78
		dc.w mos_ADC_absy-mosCpu	; $79
		dc.w mos_Null-mosCpu	; $7A
		dc.w mos_Null-mosCpu	; $7B
		dc.w mos_Null-mosCpu	; $7C
		dc.w mos_ADC_absx-mosCpu	; $7D
		dc.w mos_ROR_absx-mosCpu	; $7E
		dc.w mos_Null-mosCpu	; $7F
		dc.w mos_Null-mosCpu	; $80
		dc.w mos_STA_indx-mosCpu	; $81
		dc.w mos_Null-mosCpu	; $82
		dc.w mos_Null-mosCpu	; $83
		dc.w mos_STY_zp-mosCpu	; $84
		dc.w mos_STA_zp-mosCpu	; $85
		dc.w mos_STX_zp-mosCpu	; $86
		dc.w mos_Null-mosCpu	; $87
		dc.w mos_DEY-mosCpu	; $88
		dc.w mos_Null-mosCpu	; $89
		dc.w mos_TXA-mosCpu	; $8A
		dc.w mos_Null-mosCpu	; $8B
		dc.w mos_STY_abs-mosCpu	; $8C
		dc.w mos_STA_abs-mosCpu	; $8D
		dc.w mos_STX_abs-mosCpu	; $8E
		dc.w mos_Null-mosCpu	; $8F
		dc.w mos_BCC-mosCpu	; $90
		dc.w mos_STA_indy-mosCpu	; $91
		dc.w mos_Null-mosCpu	; $92
		dc.w mos_Null-mosCpu	; $93
		dc.w mos_STY_zpx-mosCpu	; $94
		dc.w mos_STA_zpx-mosCpu	; $95
		dc.w mos_STX_zpy-mosCpu	; $96
		dc.w mos_Null-mosCpu	; $97
		dc.w mos_TYA-mosCpu	; $98
		dc.w mos_STA_absy-mosCpu	; $99
		dc.w mos_TXS-mosCpu	; $9A
		dc.w mos_Null-mosCpu	; $9B
		dc.w mos_Null-mosCpu	; $9C
		dc.w mos_STA_absx-mosCpu	; $9D
		dc.w mos_Null-mosCpu	; $9E
		dc.w mos_Null-mosCpu	; $9F
		dc.w mos_LDY_imm-mosCpu	; $A0
		dc.w mos_LDA_indx-mosCpu	; $A1
		dc.w mos_LDX_imm-mosCpu	; $A2
		dc.w mos_Null-mosCpu	; $A3
		dc.w mos_LDY_zp-mosCpu	; $A4
		dc.w mos_LDA_zp-mosCpu	; $A5
		dc.w mos_LDX_zp-mosCpu	; $A6
		dc.w mos_Null-mosCpu	; $A7
		dc.w mos_TAY-mosCpu	; $A8
		dc.w mos_LDA_imm-mosCpu	; $A9
		dc.w mos_TAX-mosCpu	; $AA
		dc.w mos_Null-mosCpu	; $AB
		dc.w mos_LDY_abs-mosCpu	; $AC
		dc.w mos_LDA_abs-mosCpu	; $AD
		dc.w mos_LDX_abs-mosCpu	; $AE
		dc.w mos_Null-mosCpu	; $AF
		dc.w mos_BCS-mosCpu	; $B0
		dc.w mos_LDA_indy-mosCpu	; $B1
		dc.w mos_Null-mosCpu	; $B2
		dc.w mos_Null-mosCpu	; $B3
		dc.w mos_LDY_zpx-mosCpu	; $B4
		dc.w mos_LDA_zpx-mosCpu	; $B5
		dc.w mos_LDX_zpy-mosCpu	; $B6
		dc.w mos_Null-mosCpu	; $B7
		dc.w mos_CLV-mosCpu	; $B8
		dc.w mos_LDA_absy-mosCpu	; $B9
		dc.w mos_TSX-mosCpu	; $BA
		dc.w mos_Null-mosCpu	; $BB
		dc.w mos_LDY_absx-mosCpu	; $BC
		dc.w mos_LDA_absx-mosCpu	; $BD
		dc.w mos_LDX_absy-mosCpu	; $BE
		dc.w mos_Null-mosCpu	; $BF
		dc.w mos_CPY_imm-mosCpu	; $C0
		dc.w mos_CMP_indx-mosCpu	; $C1
		dc.w mos_Null-mosCpu	; $C2
		dc.w mos_Null-mosCpu	; $C3
		dc.w mos_CPY_zp-mosCpu	; $C4
		dc.w mos_CMP_zp-mosCpu	; $C5
		dc.w mos_DEC_zp-mosCpu	; $C6
		dc.w mos_Null-mosCpu	; $C7
		dc.w mos_INY-mosCpu	; $C8
		dc.w mos_CMP_imm-mosCpu	; $C9
		dc.w mos_DEX-mosCpu	; $CA
		dc.w mos_Null-mosCpu	; $CB
		dc.w mos_CPY_abs-mosCpu	; $CC
		dc.w mos_CMP_abs-mosCpu	; $CD
		dc.w mos_DEC_abs-mosCpu	; $CE
		dc.w mos_Null-mosCpu	; $CF
		dc.w mos_BNE-mosCpu	; $D0
		dc.w mos_CMP_indy-mosCpu	; $D1
		dc.w mos_Null-mosCpu	; $D2
		dc.w mos_Null-mosCpu	; $D3
		dc.w mos_Null-mosCpu	; $D4
		dc.w mos_CMP_zpx-mosCpu	; $D5
		dc.w mos_DEC_zpx-mosCpu	; $D6
		dc.w mos_Null-mosCpu	; $D7
		dc.w mos_CLD-mosCpu	; $D8
		dc.w mos_CMP_absy-mosCpu	; $D9
		dc.w mos_Null-mosCpu	; $DA
		dc.w mos_Null-mosCpu	; $DB
		dc.w mos_Null-mosCpu	; $DC
		dc.w mos_CMP_absx-mosCpu	; $DD
		dc.w mos_DEC_absx-mosCpu	; $DE
		dc.w mos_Null-mosCpu	; $DF
		dc.w mos_CPX_imm-mosCpu	; $E0
		dc.w mos_SBC_indx-mosCpu	; $E1
		dc.w mos_Null-mosCpu	; $E2
		dc.w mos_Null-mosCpu	; $E3
		dc.w mos_CPX_zp-mosCpu	; $E4
		dc.w mos_SBC_zp-mosCpu	; $E5
		dc.w mos_INC_zp-mosCpu	; $E6
		dc.w mos_Null-mosCpu	; $E7
		dc.w mos_INX-mosCpu	; $E8
		dc.w mos_SBC_imm-mosCpu	; $E9
		dc.w mos_NOP-mosCpu	; $EA
		dc.w mos_Null-mosCpu	; $EB
		dc.w mos_CPX_abs-mosCpu	; $EC
		dc.w mos_SBC_abs-mosCpu	; $ED
		dc.w mos_INC_abs-mosCpu	; $EE
		dc.w mos_Null-mosCpu	; $EF
		dc.w mos_BEQ-mosCpu	; $F0
		dc.w mos_SBC_indy-mosCpu	; $F1
		dc.w mos_Null-mosCpu	; $F2
		dc.w mos_Null-mosCpu	; $F3
		dc.w mos_Null-mosCpu	; $F4
		dc.w mos_SBC_zpx-mosCpu	; $F5
		dc.w mos_INC_zpx-mosCpu	; $F6
		dc.w mos_Null-mosCpu	; $F7
		dc.w mos_SED-mosCpu	; $F8
		dc.w mos_SBC_absy-mosCpu	; $F9
		dc.w mos_Null-mosCpu	; $FA
		dc.w mos_Null-mosCpu	; $FB
		dc.w mos_Null-mosCpu	; $FC
		dc.w mos_SBC_absx-mosCpu	; $FD
		dc.w mos_INC_absx-mosCpu	; $FE
		dc.w mos_Null-mosCpu	; $FF

; ----------------------------------------------------------------

mos_Null:
		lsr.w	#1,d4
		bra.s	*

; ----------------------------------------------------------------

mos_ADC_imm:
		move.b	(a0)+,d7
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_imm:
		move.b	(a0)+,d7
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_acc:
		lsl.b	#1,d0
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		lsl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		lsl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		move.b	(a2,d6.w),d7
		lsl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		move.b	(a2,d6.w),d7
		lsl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BCC:
		move.b	(a0)+,d6
		move	d3,sr
		bcs.s	.next
		ext.w	d6
		adda.w	d6,a0
.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BCS:
		move.b	(a0)+,d6
		move	d3,sr
		bcc.s	.next
		ext.w	d6
		adda.w	d6,a0
.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BEQ:
		move.b	(a0)+,d6
		move	d3,sr
		bne.s	.next
		ext.w	d6
		adda.w	d6,a0
.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BIT_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		move.b	d7,d4
		andi.b	#$F1,d3
		lsl.b	#1,d7
		bcc.s	.no_n
		ori.b	#8,d3
.no_n:
		lsl.b	#1,d7
		bcc.s	.no_v
		ori.b	#2,d3
.no_v:
		and.b	d0,d4
		bne.s	.next
		ori.b	#4,d3
.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BIT_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		move.b	d7,d4
		andi.b	#$F1,d3
		lsl.b	#1,d7
		bcc.s	.no_n
		ori.b	#8,d3

.no_n:
		lsl.b	#1,d7
		bcc.s	.no_v
		ori.b	#2,d3

.no_v:
		and.b	d0,d4
		bne.s	.next
		ori.b	#4,d3

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BMI:
		move.b	(a0)+,d6
		move	d3,sr
		bpl.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BNE:
		move.b	(a0)+,d6
		move	d3,sr
		beq.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BPL:
		move.b	(a0)+,d6
		move	d3,sr
		bmi.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $00 - BRK
; ----------------------------------------------------------------

mos_BRK:
		addq.l	#1,a0			; skip the padding byte
		bsr	famiGetP		; P with B set
		swap	d3			; push PC, P
		move.w	a0,d4
		move.b	d4,d6
		lsr.w	#8,d4
		or.b	#$80,d4
		move.b	d4,(a2,d3.w)
		subq.b	#1,d3
		move.b	d6,(a2,d3.w)
		subq.b	#1,d3
		move.b	d5,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		move.w	#1,cpuModeIntDis(a4)

		lea 	(RAM_Fami_ROM),a5
		move.w	#cpuIRQ,d6		; go to IRQ
		add.w	d6,a5
		moveq	#0,d6
		move.b	1(a5),d6
		lsl.w	#8,d6
		move.b	(a5),d6
		and.w	#$7FFF,d6
		movea.l	a1,a0
		add.l	d6,a0
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BVC:
		move.b	(a0)+,d6
		move	d3,sr
		bvs.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BVS:
		move.b	(a0)+,d6
		move	d3,sr
		bvc.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CLC:
		andi.b	#$EE,d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; CLD - Clear Decimal mode
; ----------------------------------------------------------------

mos_CLD:
		move.w	#0,cpuModeDec(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; CLI - Clear Interrupt disable
; ----------------------------------------------------------------

mos_CLI:
		move.w	#0,cpuModeIntDis(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------

mos_CLV:
		andi.b	#$FD,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_imm:
		move.b	(a0)+,d7
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_indx:
		clr.w	d5
		clr.w	d4
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPX_imm:
		move.b	(a0)+,d7
		cmp.b	d7,d1
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPX_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		cmp.b	d7,d1
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPX_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		cmp.b	d7,d1
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPY_imm:
		move.b	(a0)+,d7
		cmp.b	d7,d2
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPY_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		cmp.b	d7,d2
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPY_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		cmp.b	d7,d2
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEC_zp:
		clr.w	d6
		move.b	(a0)+,d6
		subq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEC_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		subq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEC_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		subq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEC_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		subq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEX:
		subq.b	#1,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEY:
		subq.b	#1,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_imm:
		move.b	(a0)+,d7
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INC_zp:
		clr.w	d6
		move.b	(a0)+,d6
		addq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INC_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		addq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INC_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		addq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INC_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		addq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INX:
		addq.b	#1,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INY:
		addq.b	#1,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; $4C - JMP $xxxx
; ----------------------------------------------------------------

mos_JMP_abs:
		moveq	#0,d6
		move.b	1(a0),d6
		lsl.w	#8,d6
		move.b	(a0),d6
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $6C - JMP ($xxxx)
; ----------------------------------------------------------------

mos_JMP_ind:
		moveq	#0,d4
		move.b	1(a0),d6
		lsl.w	#8,d6
		move.b	(a0),d6
		move.b	(a2,d6.w),d4
		add.b	#1,d6
		move.b	(a2,d6.w),d6
		lsl.w	#8,d6
		or.b	d4,d6

	; TODO: Check for more jump locations
		tst.w	d6
		bmi.s	.to_rom
		move.l	a2,a0
		adda	d6,a0
		jmp	(RAM_EmuLoop).l
.to_rom:
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $20 - JSR $xxxx
; ----------------------------------------------------------------

mos_JSR:
		moveq	#0,d6
		move.b	(a0)+,d4
		move.b	(a0),d6
		lsl.w	#8,d6
		move.b	d4,d6

		swap	d3
		move.w	a0,d4
		move.b	d4,d5
		lsr.w	#8,d4
		or.b	#$80,d4
		move.b	d4,(a2,d3.w)
		subq.b	#1,d3
		move.b	d5,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; $A9 - LDA #$xx
; ----------------------------------------------------------------

mos_LDA_imm:
		move.b	(a0)+,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_abs:
		clr.w	d4
		clr.w	d6
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; LDA (oper,X)

mos_LDA_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_imm:
		move.b	(a0)+,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_zpy:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d2,d6
		move.b	(a2,d6.w),d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		move.b	d7,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_imm:
		move.b	(a0)+,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		move.b	d7,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_acc:
		lsr.b	#1,d0
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		lsr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		lsr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		move.b	(a2,d6.w),d7
		lsr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		move.b	(a2,d6.w),d7
		lsr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; $EA - nop

mos_NOP:
		nop
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_imm:
		move.b	(a0)+,d7
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_PHA:
		swap	d3
		move.b	d0,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $08 - PHP
; ----------------------------------------------------------------

mos_PHP:
		bsr	famiGetP
		swap	d3
		move.b	d5,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; Convert between the 6502 P register and the emulator's flags
;
; N, Z, V and C live in the 68k CCR (low byte of d3, X mirrors C),
; I and D live in cpuModeIntDis and cpuModeDec.
; d3 must not be swapped when calling these.
; ----------------------------------------------------------------

; Build P in d5 (bits 5 and 4 set; clear bit 4 for NMI/IRQ)
; Uses: d5, a5
famiGetP:
		lea	tblCcrToP(pc),a5
		move.w	d3,d5
		andi.w	#$0F,d5
		move.b	(a5,d5.w),d5
		tst.w	cpuModeIntDis(a4)
		beq.s	.no_i
		ori.b	#$04,d5
.no_i:
		tst.w	cpuModeDec(a4)
		beq.s	.no_d
		ori.b	#$08,d5
.no_d:
		rts

; Load flags from P in d5
; Uses: d5, a5
famiSetP:
		lea	tblPToCcr(pc),a5
		andi.w	#$FF,d5
		andi.b	#$E0,d3
		or.b	(a5,d5.w),d3
		clr.w	cpuModeIntDis(a4)
		btst	#2,d5
		beq.s	.no_i
		move.w	#1,cpuModeIntDis(a4)
.no_i:
		clr.w	cpuModeDec(a4)
		btst	#3,d5
		beq.s	.no_d
		move.w	#1,cpuModeDec(a4)
.no_d:
		rts

; CCR (N Z V C) -> P (N V 1 B . . Z C)
tblCcrToP:
.ccr := 0
		rept 16
		dc.b $30|((.ccr&8)<<4)|((.ccr&4)>>1)|((.ccr&2)<<5)|(.ccr&1)
.ccr := .ccr+1
		endm

; P -> CCR (X N Z V C, X = C)
tblPToCcr:
.p := 0
		rept 256
		dc.b ((.p&$80)>>4)|((.p&$40)>>5)|((.p&2)<<1)|((.p&1)*$11)
.p := .p+1
		endm
		align 2
; ----------------------------------------------------------------

mos_PLA:
		addi.l	#$10000,d3
		move.l	d3,d5
		swap	d5
		move.b	(a2,d5.w),d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $28 - PLP
; ----------------------------------------------------------------

mos_PLP:
		swap	d3
		addq.b	#1,d3
		move.b	(a2,d3.w),d5
		swap	d3
		bsr	famiSetP
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_acc:
		move	d3,sr
		roxl.b	#1,d0
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_acc:
		move	d3,sr
		roxr.b	#1,d0
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $40 - RTI
; 
; NOTE: Interrupt exit
; ----------------------------------------------------------------

mos_RTI:
		tst.w	cpuFamiVint(a4)
		beq.s	.nonint
		
		swap	d3			; Restore SR, PC
		moveq	#0,d6
		addq.b	#1,d3
		move.b	(a2,d3.w),d5
		addq.b	#1,d3
		move.b	(a2,d3.w),d4
		addq.b	#1,d3
		move.b	(a2,d3.w),d6
		lsl.w	#8,d6
		move.b	d4,d6
		swap	d3
		bsr	famiSetP
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0

		move.l	#emuLoop,(RAM_EmuLoop+2).l
		move.w	#0,cpuFamiVint(a4)
		jmp	(RAM_EmuLoop).l

.nonint:
		swap	d3
		moveq	#0,d6
		addq.b	#1,d3
		move.b	(a2,d3.w),d5
		addq.b	#1,d3
		move.b	(a2,d3.w),d4
		addq.b	#1,d3
		move.b	(a2,d3.w),d6
		lsl.w	#8,d6
		move.b	d4,d6
		swap	d3
		bsr	famiSetP
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $60 - RTS
; ----------------------------------------------------------------

mos_RTS:
		swap	d3
		moveq	#0,d6
		addq.b	#1,d3
		move.b	(a2,d3.w),d4
		addq.b	#1,d3
		move.b	(a2,d3.w),d6
		lsl.w	#8,d6
		move.b	d4,d6
		swap	d3
		addq.w	#1,d6
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_imm:
		move.b	(a0)+,d7
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_absy:
		clr.w	d4
		clr.w	d5
		clr.b	d7
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6

		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SEC:
		ori.b	#$11,d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; SED - Set Decimal mode
; ----------------------------------------------------------------

mos_SED:
		move.w	#1,cpuModeDec(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; SEI - Set Interrupt disable
; ----------------------------------------------------------------

mos_SEI:
		move.w	#1,cpuModeIntDis(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------

mos_STA_zp:
		clr.w	d4
		move.b	(a0)+,d4
		move.b	d0,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STA_zpx:
		clr.w	d4
		move.b	(a0)+,d4
		add.b	d1,d4
		move.b	d0,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STA_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STA_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------

mos_STA_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------
; STA (oper,X)

mos_STA_indx:
		clr.w	d5
		clr.w	d4
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------

mos_STA_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------

mos_STX_zp:
		clr.w	d4
		move.b	(a0)+,d4
		move.b	d1,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STX_zpy:
		clr.w	d4
		move.b	(a0)+,d4
		add.b	d2,d4
		move.b	d1,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STX_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		move.b	d1,d7
		bra	addr_Write
; ----------------------------------------------------------------
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STY_zp:
		clr.w	d4
		move.b	(a0)+,d4
		move.b	d2,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STY_zpx:
		clr.w	d4
		move.b	(a0)+,d4
		add.b	d1,d4
		move.b	d2,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STY_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		move.b	d2,d7
		bra	addr_Write
; ----------------------------------------------------------------
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TAX:
		move.b	d0,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TAY:
		move.b	d0,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; TSX

mos_TSX:
		swap	d3
		move.b	d3,d1
		swap	d3
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TXA:
		move.b	d1,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TXS:
		swap	d3
		move.b	d1,d3
		swap	d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TYA:
		move.b	d2,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l

; ====================================================================
; ----------------------------------------------------------------
; Read request
; 
; d6 - XX00
; d4 - 00XX
; ----------------------------------------------------------------

addr_Read:
		tst.b	d6		; $8000
		bmi	rdFrom_PRG
	; TODO: $6000-$7FFF
		cmp.b	#$40,d6		; $4000
		bge	rdFrom_APU
		cmp.b	#$20,d6		; $2000
		bge	rdFrom_PPU

; ----------------------------------------------------------------

rdFrom_RAM:
		lsl.w	#8,d6
		move.b	d4,d6
		andi.w	#$7FF,d6
		move.b	(a2,d6.w),d7
		rts
; ----------------------------------------------------------------

rdFrom_PRG:
		lsl.w	#8,d6
		move.b	d4,d6
		andi.w	#$7FFF,d6
		move.b	(a1,d6.w),d7
		rts
; ----------------------------------------------------------------

rdFrom_APU:
		cmpi.b	#$1F,d4
		bhi.w	rdAPU_OpenBus

		cmp.b	#$16,d4		; $4016
		beq.s	APU_Input_1
		cmp.b	#$17,d4		; $4017
		beq.s	APU_Input_2

; ----------------------------------------------------------------

APU_Rd_Null:
		rts

; ----------------------------------------------------------------

rdAPU_OpenBus:
		move.w	d3,d7
		rts

; ----------------------------------------------------------------

APU_Input_1:
		move.w	cpuInputData(a4),d7
		andi.w	#1,d7
		lsr	cpuInputData(a4)
		rts
; ----------------------------------------------------------------

APU_Input_2:
		move.w	cpuInputData+2(a4),d7
		andi.w	#1,d7
		lsr	cpuInputData+2(a4)
		rts
; ----------------------------------------------------------------

rdFrom_PPU:
		andi.w	#7,d4
		add.w	d4,d4
		move.w	rdPPU_Table(pc,d4.w),d4
		jmp	rdPPU_Table(pc,d4.w)
; ----------------------------------------------------------------
rdPPU_Table:	dc.w rdPPU_OpenBus-rdPPU_Table		; $2000
		dc.w rdPPU_OpenBus-rdPPU_Table		; $2001
		dc.w rdPPU_Status-rdPPU_Table	; $2002
		dc.w rdPPU_OpenBus-rdPPU_Table		; $2003
		dc.w rdPPU_OamData-rdPPU_Table	; $2004
		dc.w rdPPU_OpenBus-rdPPU_Table		; $2005
		dc.w rdPPU_OpenBus-rdPPU_Table		; $2006
		dc.w rdPPU_Data-rdPPU_Table	; $2007
; ----------------------------------------------------------------

rdPPU_OpenBus:
		move.b	(a1,d3.w),d7	; byte read: d3 can be odd (word read = address error)
		rts
; ----------------------------------------------------------------

rdPPU_Status:
		move.w	#0,ppuAddrLatch(a4)
		move.w	ppuStatus(a4),d7
		move.w	#0,ppuStatus(a4)

	; sprite 0 hit: set from sprite 0's first line until the end of
	; the display. A sprite at Y starts on NES line Y+1, and NES line L
	; is shown on MD line L-8. Sprites below the MD's 224 lines hit on
	; the last line so games waiting for the hit don't hang.
	; Hidden sprites (Y >= $EF) never hit.
		move.w	#$2700,sr
		move.w	ppuSp0Ypos(a4),d4
		cmpi.w	#$EF,d4
		bcc.s	.no_hit
		subq.w	#7,d4
		bpl.s	.sp0_top
		moveq	#0,d4
.sp0_top:
		cmpi.w	#$DF,d4
		bls.s	.sp0_bottom
		move.w	#$DF,d4
.sp0_bottom:
		move.w	8(a6),d5		; MD V counter
		lsr.w	#8,d5
		cmpi.w	#$E0,d5
		bcc.s	.no_hit		; vblank
		cmp.w	d4,d5
		bcs.s	.no_hit		; above sprite 0
		ori.w	#$40,d7
.no_hit:

		tst.w	FamiPPUVint(a4)
		beq.s	.novflag
		clr.w	FamiPPUVint(a4)
		
; 		move.w	(vdp_ctrl),d4
; 		btst	#bitVint,d4
; 		beq.s	.novflag
		ori.w	#$80,d7
.novflag:
		move.w	#$2000,sr
		rts
; ----------------------------------------------------------------

rdPPU_OamData:
		rts
; ----------------------------------------------------------------

rdPPU_Data:
		move.w	ppuDataLast(a4),d7
		move.w	ppuAddrBase(a4),d4
		andi.w	#$3FFF,d4
		move.b	(a3,d4.w),ppuDataLast+1(a4)
		move.w	ppuAddrIncr(a4),d4
		add.w	d4,ppuAddrBase(a4)
		rts

; ====================================================================
; ----------------------------------------------------------------
; Write request
; 
; d6 - XX00
; d4 - 00XX
; d7 - data
; ----------------------------------------------------------------

addr_Write:
		tst.b	d6		; $8000
		bmi	wrTo_PRG
	; TODO: $6000-$7FFF
		cmp.b	#$40,d6		; $4000
		bge	wrTo_APU
		cmp.b	#$20,d6		; $2000
		bge	wrTo_PPU

; ====================================================================
; ----------------------------------------------------------------
; WRITE request to RAM
; ----------------------------------------------------------------

wrTo_RAM:
		lsl.w	#8,d6
		move.b	d4,d6
		andi.w	#$7FF,d6
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l

; ====================================================================
; ----------------------------------------------------------------
; WRITE request to ROM area, mappers
; ----------------------------------------------------------------

wrTo_PRG:
		cmp.w	#3,cpuMapper(a4)
		beq.s	.mapper_3
		jmp	(RAM_EmuLoop).l

; --------------------------------------------------------
; Mapper $03, CNROM
; 
; Bank select ($8000-$FFFF)
; 
; 7  bit  0
; ---- ----
; xxDD xxCC
;   ||   ||
;   ||   ++- Select 8 KB CHR ROM bank for PPU $0000-$1FFF
;   ++------ Security diodes config
; --------------------------------------------------------

.mapper_3:
		move.l	a4,-(sp)
		movea.l	emuChrRom(a4),a5
		move.w	d7,d4
		and.w	#%11,d4
		lsl.w	#8,d4
		lsl.w	#5,d4
		adda	d4,a5
		move.l	a3,a4
		move.w	#($2000/4)-1,d4
.copychr:
		move.l	(a5)+,(a4)+
		dbf	d4,.copychr
		move.l	(sp)+,a4
		bsr	Nemul_LoadChr
		jmp	(RAM_EmuLoop).l

; ====================================================================
; ----------------------------------------------------------------
; WRITE to APU
; ----------------------------------------------------------------

wrTo_APU:
		cmpi.b	#$1F,d4
		bhi.s	APU_Null
		add.w	d4,d4
		move.w	wrAPU_Table(pc,d4.w),d4
		jmp	wrAPU_Table(pc,d4.w)

; ----------------------------------------------------------------
wrAPU_Table:	dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_OAMDMA-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Input-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table

APU_Null:
		jmp	(RAM_EmuLoop).l


APU_Input:
		tst.b	d7
		beq.s	APU_Null
		bsr	readInput
		jmp	(RAM_EmuLoop).l


readInput:
		move.l	a3,-(sp)
		lea	($A10003).l,a3
		lea	cpuInputData(a4),a5
		bsr	.this_pad
		addq.w	#2,a3
		bsr	.this_pad		
		move.l	(sp)+,a3
		rts
		
.this_pad:
		move.b	#0,(a3)
		nop
		nop
		move.b	(a3),d5
		lsl.b	#2,d5
		andi.b	#$C0,d5
		move.b	#$40,(a3)
		nop
		nop
		move.b	(a3),d4
		andi.b	#$3F,d4
		or.b	d4,d5
		not.b	d5
		clr.w	d4
		lsl.b	#1,d5
		addx.b	d4,d4
		lsl.w	#1,d5
		lsl.b	#1,d5
		addx.b	d4,d4
		lsr.w	#1,d5
		lsl.b	#1,d5
		addx.b	d4,d4
		lsl.b	#1,d5
		addx.b	d4,d4
		or.b	d5,d4
		move.w	d4,(a5)+
		rts


APU_OAMDMA:
		move.l	d7,-(sp)
		move.l	a3,-(sp)
		
		lsl.w	#8,d7
		move.w	ppuOamUnk(a4),d6
		eori.w	#1,d6
		move.b	ppuOamAddr(a4,d6.w),d7
		lea	(a2,d7.w),a5
		move.b	(a5),ppuSp0Ypos+1(a4)		; sprite 0 ypos

		lea 	vdpSprData(a4),a3
		moveq	#$3F,d5
		moveq	#0,d7
.lp_sprnormal:
		move.b	(a5)+,d7
		move.w	d7,d6
		addi.w	#$79,d6
		move.w	d6,(a3)+

		moveq	#64,d6
		sub.b	d5,d6
		or.w	ppuSprWide(a4),d6
		move.w	d6,(a3)+
		
		move.b	(a5)+,d7
		move.w	d7,d6
		ori.w	#$100,d6

		move.b	(a5)+,d7
		move.w	d7,d4
		rol.b	#2,d4
		lsl.w	#1,d4
		lsl.b	#3,d4
		lsl.w	#7,d4
		or.w	d6,d4
		eori.w	#$8000,d4
		move.w	d4,(a3)+

		move.b	(a5)+,d7
		move.w	d7,d6
		addi.w	#$80,d6
		move.w	d6,(a3)+

		dbf	d5,.lp_sprnormal
		move.l	(sp)+,a3
		move.l	(sp)+,d7
		jmp	(RAM_EmuLoop).l


wrTo_PPU:
		andi.w	#7,d4
		add.w	d4,d4
		move.w	wrPPU_Table(pc,d4.w),d4
		jmp	wrPPU_Table(pc,d4.w)

; ----------------------------------------------------------------
wrPPU_Table:	dc.w wrPPU_Ctrl-wrPPU_Table ; $2000
		dc.w wrPPU_Mask-wrPPU_Table ; $2001
		dc.w wrPPU_Status-wrPPU_Table ; $2002
		dc.w wrPPU_OamAddr-wrPPU_Table ; $2003
		dc.w wrPPU_OamData-wrPPU_Table ; $2004
		dc.w wrPPU_Scroll-wrPPU_Table ; $2005
		dc.w wrPPU_Addr-wrPPU_Table ; $2006
		dc.w wrPPU_Data-wrPPU_Table ; $2007

; ----------------------------------------------------------------
; $2000 - PPU CTRL
; ----------------------------------------------------------------

wrPPU_Ctrl:

	; NMI on/off
		clr.w	d6
		lsl.b	#1,d7			; $80
		bcc.s	.noVintFlag
		move.b	#$80,d6			; NMI ON
.noVintFlag:
		move.w	d6,ppuNmiFlag(a4)
		
	; 8x8 or 8x16 sprites
		clr.w	d6
		lsl.b	#2,d7
		bcc.s	.spr_size
		move.w	#$100,d6
.spr_size:
		move.w	d6,ppuSprWide(a4)
		
	; PPU VRAM BG bank/Sprites bank
		move.b	d7,d6
		andi.w	#$C0,d6
		cmp.w	ppuChrBank(a4),d6
		beq.s	.no_reload
		move.w	d6,ppuChrBank(a4)
		bsr	Nemul_LoadChr
.no_reload:

	; PPU VRAM increment
		moveq	#1,d6
		lsl.b	#3,d7
		bcc.s	.nrml_incr
		moveq	#$20,d6
.nrml_incr:
		move.w	d6,ppuAddrIncr(a4)

	; PPU Name table base
		andi.w	#$C0,d7
		move.w	d7,ppuNTblBase(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $2001 - PPU MASK
; ----------------------------------------------------------------

wrPPU_Mask:
		move.w	#$2700,sr

	; Hide sprites and BG
		move.w	#$8500+(($A000)>>9),d6
		swap	d6
		move.w	vdpReg01(a4),d6		; REGISTER 81
		and.b	#$BF,d6
		btst	#3,d7
		beq.s	.hidebg
		ori.b	#$40,d6
.hidebg:
		swap	d6
		btst	#4,d7
		beq.s	.hidesp
		move.w	#$8500+(($BC00)>>9),d6
.hidesp:
		move.l	d6,4(a6)
		swap	d6
		move.w	d6,vdpReg01(a4)

		move.w	vdpReg00(a4),d6
		bset	#5,d6
		btst	#1,d7
		beq.s	.hide_bg
		bclr	#5,d6
.hide_bg:
		move.w	d6,4(a6)
		move.w	d6,vdpReg00(a4)
		move.w	#$2000,sr

		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $2005 - PPU SCROLL
; -----------------------------------------------------------------

wrPPU_Scroll:
		move.w	d7,d4
		andi.w	#$FF,d4
		move.w	ppuNTblBase(a4),d6
		eori.w	#1,ppuAddrLatch(a4)
		beq.s	.vertical
		and.w	#1,d6
		lsl.w	#8,d6
		add.w	d6,d4
		neg.w	d4
		move.w	d4,vdpScrlX(a4)
		move.w	d4,vdpScrlX+2(a4)
		jmp	(RAM_EmuLoop).l

; --------------------------------------------------------
; Vertical
; --------------------------------------------------------

.vertical:
		addq.w	#8,d4
		lsl.b	#1,d6
		bcs.s	.vert_swap
		move.w	d4,vdpScrlY(a4)
		add.w	#$110,d4
		move.w	d4,vdpScrlY+2(a4)
		jmp	(RAM_EmuLoop).l
.vert_swap:
		move.w	d4,vdpScrlY+2(a4)
		add.w	#$110,d4
		move.w	d4,vdpScrlY(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------

wrPPU_Status:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

wrPPU_OamAddr:
		move.w	ppuOamUnk(a4),d4
		move.b	d7,ppuOamAddr(a4,d4.w)
		eori.w	#1,ppuOamUnk(a4)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

wrPPU_OamData:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

wrPPU_Addr:
		move.w	ppuAddrLatch(a4),d4
		move.b	d7,ppuAddrBase(a4,d4.w)
		eori.w	#1,ppuAddrLatch(a4)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

wrPPU_Data:
		move.w	ppuAddrBase(a4),d4
		move.w	ppuAddrIncr(a4),d6
		add.w	d6,ppuAddrBase(a4)
		andi.w	#$3FFF,d4
		cmpi.w	#$2000,d4
		bcs.w	ppuChrRamWrite
		move.b	d7,(a3,d4.w)
		cmpi.w	#$3F00,d4
		bcc.s	ppuSetColor
		move.w	d4,d5
		andi.w	#$3C0,d5
		cmpi.w	#$3C0,d5
		bne.w	ppuDrwCell
		bra.w	ppuDrwCellPal
; ----------------------------------------------------------------

ppuVdpIndex:
		dc.w $0000,$0002,$0004,$0006
		dc.w $0020,$0022,$0024,$0026
		dc.w $0040,$0042,$0044,$0046
		dc.w $0060,$0062,$0064,$0066
		dc.w $0010,$0012,$0014,$0016
		dc.w $0030,$0032,$0034,$0036
		dc.w $0050,$0052,$0054,$0056
		dc.w $0070,$0072,$0074,$0076
		align 2

ppuSetColor:
		andi.w	#$1F,d4
		add.w	d4,d4
		move.w	ppuVdpIndex(pc,d4.w),d4
		move.w	d4,d6
		move.w	d7,d5
		andi.b	#$3F,d5
		add.w	d5,d5
		move.w	ppuVdpColors(pc,d5.w),vdpPalette(a4,d4.w)
		and.w	#$F,d6
		bne.s	.no_bgpal
		bchg	#4,d4
		move.w	ppuVdpColors(pc,d5.w),vdpPalette(a4,d4.w)
		
.no_bgpal:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

ppuVdpColors:	dc.w $666
		dc.w $820
		dc.w $A00
		dc.w $A04
		dc.w $806
		dc.w $406
		dc.w 6
		dc.w $26
		dc.w $44
		dc.w $40
		dc.w $60
		dc.w $40
		dc.w $440
		dc.w 0
		dc.w 0
		dc.w 0
		dc.w $AAA
		dc.w $E60
		dc.w $E40
		dc.w $E28
		dc.w $C2A
		dc.w $82C
		dc.w $24C
		dc.w $4A
		dc.w $66
		dc.w $84
		dc.w $A0
		dc.w $480
		dc.w $880
		dc.w 0
		dc.w 0
		dc.w 0
		dc.w $EEE
		dc.w $EC6
		dc.w $EAA
		dc.w $E8C
		dc.w $E6E
		dc.w $C6E
		dc.w $88E
		dc.w $2AE
		dc.w $CC
		dc.w $E8
		dc.w $4E6
		dc.w $8E4
		dc.w $EC4
		dc.w $444
		dc.w 0
		dc.w 0
		dc.w $EEE
		dc.w $EEC
		dc.w $ECC
		dc.w $ECE
		dc.w $ECE
		dc.w $ECE
		dc.w $CCE
		dc.w $AEE
		dc.w $8EE
		dc.w $AEC
		dc.w $8EC
		dc.w $CEC
		dc.w $EEC
		dc.w $CCC
		dc.w 0
		dc.w 0
; ----------------------------------------------------------------
; Set Cell character

ppuDrwCell:
	; d4 - ppu address
	; d5 - X pos
	; d6 - Y pos
	; d7 - cell 0-255

		move.w	d4,d5
		move.w	d4,d6
		and.w	#$1F,d5
		and.w	#$3E0,d6
		add.w	d5,d5
		lsl.w	#2,d6
		add.w	d5,d6

		move.w	d4,d5
		lsr.w	#8,d5
		lsr.w	#2,d5
		btst	#1,d5
		beq.s	.top_lyr
		add.w	#$2000,d6
.top_lyr:
		btst	#0,d5
		beq.s	.left_pg
		add.w	#$40,d6
.left_pg:
		and.w	#$FF,d7
		or.w	#$8000,d7
		
		move.w	#$2700,sr
		move.w	d6,4(a6)
		move.w	#3,4(a6)
		move.w	(a6),d4
		and.w	#$E000,d4
		or.w	d7,d4
		or.w	#$4000,d6
		move.w	d6,4(a6)
		move.w	#3,4(a6)
		move.w	d4,(a6)
		and.w	#$3FFF,d4

		tst.w	ppuMirror(a4)		; check horizontal mirror
		bne.s	.vermirror

		and.w	#$3FFF,d6
		bchg	#6,d6
		move.w	d6,4(a6)
		move.w	#3,4(a6)
		move.w	(a6),d4
		and.w	#$E000,d4
		or.w	d7,d4
		or.w	#$4000,d6
		move.w	d6,4(a6)
		move.w	#3,4(a6)
		move.w	d4,(a6)
		move.w	#$2000,sr
		jmp	(RAM_EmuLoop).l
.vermirror:
		and.w	#$3FFF,d6
		add.w	#$2000,d6
		move.w	d6,4(a6)
		move.w	#3,4(a6)
		move.w	(a6),d4
		and.w	#$E000,d4
		or.w	d7,d4
		or.w	#$4000,d6
		move.w	d6,4(a6)
		move.w	#3,4(a6)
		move.w	d4,(a6)

		move.w	#$2000,sr
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; Pick Tile 16x16 color

ppuDrwCellPal:
	; d4 - Page
	; d5 - X pos
	; d6 - Y pos
	; d7 - attr
		move.w	d4,d5
		move.w	d4,d6
		and.w	#%111,d5
		lsl.w	#3,d5
		and.w	#%111000,d6
		lsl.w	#6,d6
		swap	d7
		move.w	d4,d7
		and.w	#$C00,d7
		lsr.w	#8,d7
		lsr.w	#2,d7
		btst	#1,d7
		beq.s	.top_lyr
		add.w	#$2000,d6
.top_lyr:
		btst	#0,d7
		beq.s	.left_pg
		add.w	#$40,d6
.left_pg:
		swap	d7
		move.w	#$0000,d4
		add.w	d6,d4
		add.w	d5,d4

	; d4 - VDP address
	; d5 - Palette bits
		swap	d7
		move.w	d4,d7
		swap	d7
		bsr.s	.make_attr
		tst.w	ppuMirror(a4)		; check horizontal mirror
		bne	.vert_mirr
		swap	d7
		move.w	d7,d4
		swap	d7
		add.w	#$40,d4
		bsr.s	.make_attr
		jmp	(RAM_EmuLoop).l
.vert_mirr:
		swap	d7
		move.w	d7,d4
		swap	d7
		add.w	#$2000,d4
		bsr.s	.make_attr
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; d4 - VDP plane pos
; d7 - pal bits

.make_attr:
		moveq	#0,d5			; TL
		move.b	d7,d5
		and.w	#%11,d5
		lsl.w	#8,d5
		lsl.w	#5,d5
		swap	d5
		move.b	d7,d5
		and.w	#%11,d5
		lsl.w	#8,d5
		lsl.w	#5,d5
		bsr	.pick_color
		add.w	#4,d4			; TR
		moveq	#0,d5
		move.b	d7,d5
		and.w	#%1100,d5
		lsl.w	#8,d5
		lsl.w	#3,d5
		swap	d5
		move.b	d7,d5
		and.w	#%1100,d5
		lsl.w	#8,d5
		lsl.w	#3,d5
		bsr	.pick_color
		sub.w	#4,d4			; BL
		add.w	#$100,d4
		moveq	#0,d5
		move.b	d7,d5
		and.w	#%110000,d5
		lsl.w	#8,d5
		lsl.w	#1,d5
		swap	d5
		move.b	d7,d5
		and.w	#%110000,d5
		lsl.w	#8,d5
		lsl.w	#1,d5
		bsr	.pick_color
		add.w	#4,d4			; BR
		moveq	#0,d5
		move.b	d7,d5
		and.w	#%11000000,d5
		lsl.w	#7,d5
		swap	d5
		move.b	d7,d5
		and.w	#%11000000,d5
		lsl.w	#7,d5
; 		bsr	.pick_color

.pick_color:
		move.w	#$2700,sr
		move.w	d4,4(a6)
		move.w	#3,4(a6)
		move.l	(a6),d6
		and.l	#$9FFF9FFF,d6
		or.l	d5,d6
		or.w	#$4000,d4
		move.w	d4,4(a6)
		move.w	#3,4(a6)
		move.l	d6,(a6)
		and.w	#$3FFF,d4
		add.w	#$80,d4
		move.w	d4,4(a6)
		move.w	#3,4(a6)
		move.l	(a6),d6
		and.l	#$9FFF9FFF,d6
		or.l	d5,d6
		or.w	#$4000,d4
		move.w	d4,4(a6)
		move.w	#3,4(a6)
		move.l	d6,(a6)
		and.w	#$3FFF,d4
		sub.w	#$80,d4
		move.w	#$2000,sr
		rts


romGrabPrg:
		lea	$10(a0),a4
		cmpi.b	#1,d7
		beq.w	.prg_16k
		cmpi.b	#2,d7
		beq.w	.prg_32k
		trap	#2
; ----------------------------------------------------------------
.prg_16k:
		lea	(RAM_Fami_ROM).l,a5
		lea	(RAM_Fami_ROM+$4000).l,a3
		move.l	#$FFF,d7
.rom_1:
		move.l	(a4)+,d3
		move.l	d3,(a5)+
		move.l	d3,(a3)+
		dbf	d7,.rom_1
		rts
; ----------------------------------------------------------------

.prg_32k:
		lea	(RAM_Fami_ROM).l,a5
		move.l	#$1FFF,d7
.copy:
		move.l	(a4)+,(a5)+
		dbf	d7,.copy
		rts


; ----------------------------------------------------------------
; $2007 write to the pattern tables ($0000-$1FFF)
;
; Ignored for CHR-ROM. For CHR-RAM, store the byte and re-convert
; that row of the tile in each MD tile set showing this table:
; MD tiles $000-$0FF hold the BG table, $100-$1FF the sprite table
; with colors +8 (see Nemul_LoadChr).
;
; d4 - NES pattern address
; ----------------------------------------------------------------

ppuChrRamWrite:
		tst.w	ppuChrRam(a4)
		beq.w	.done
		move.b	d7,(a3,d4.w)
		movem.l	d0-d3,-(sp)

	; 2bpp row -> 4bpp, colors 0-3
		move.w	d4,d3
		andi.w	#$1FF7,d3
		move.b	(a3,d3.w),d1		; plane 0
		move.b	8(a3,d3.w),d2		; plane 1
		moveq	#0,d0
		moveq	#7,d5
.pixel:
		lsl.l	#4,d0
		moveq	#0,d6
		add.b	d2,d2
		addx.b	d6,d6
		add.b	d1,d1
		addx.b	d6,d6
		or.b	d6,d0
		dbf	d5,.pixel

	; VRAM address of the row in the first set: tile*32 + row*4
		move.w	d4,d3
		andi.w	#$0FF0,d3
		add.w	d3,d3
		move.w	d4,d5
		andi.w	#7,d5
		add.w	d5,d5
		add.w	d5,d5
		add.w	d5,d3

	; which table was written, as 0/-1 to compare with ppuChrBank bits
		moveq	#0,d1
		btst	#12,d4
		beq.s	.table0
		moveq	#-1,d1
.table0:
		move.w	ppuChrBank(a4),d2
		move.w	#$2700,sr

	; BG set: ppuChrBank bit 7 selects its table
		moveq	#0,d5
		btst	#7,d2
		beq.s	.bg0
		moveq	#-1,d5
.bg0:
		cmp.b	d1,d5
		bne.s	.no_bg
		moveq	#0,d5
		move.w	d3,d5
		swap	d5
		ori.l	#$40000000,d5
		move.l	d5,4(a6)
		move.l	d0,(a6)
.no_bg:

	; sprite set: bit 6 selects its table, nonzero pixels +8
		moveq	#0,d5
		btst	#6,d2
		beq.s	.spr0
		moveq	#-1,d5
.spr0:
		cmp.b	d1,d5
		bne.s	.no_spr
		move.l	d0,d6
		lsr.l	#1,d6
		or.l	d0,d6
		andi.l	#$11111111,d6
		lsl.l	#3,d6
		or.l	d6,d0
		moveq	#0,d5
		move.w	d3,d5
		addi.w	#$2000,d5
		swap	d5
		ori.l	#$40000000,d5
		move.l	d5,4(a6)
		move.l	d0,(a6)
.no_spr:
		move.w	#$2000,sr
		movem.l	(sp)+,d0-d3
.done:
		jmp	(RAM_EmuLoop).l


; a6 - $C00000
; a4 - RAM_Fami_Emu

Nemul_LoadChr:
		move.w	#$2700,sr
		move.w	#$8F02,4(a6)
		move.l	#$40000000,4(a6)
		moveq	#0,d5
		move.w	ppuChrBank(a4),d6
		bsr.w	.make_chr
		moveq	#8,d5
		move.w	ppuChrBank(a4),d6
		lsl.b	#1,d6
		bsr.w	.make_chr
		move.w	#$2000,sr
		rts

.make_chr:
		movea.l	a3,a5
		lsl.b	#1,d6
		bcc.s	.got_table
		adda.l	#$1000,a5
.got_table:
		movem.l	d0-d2/d3-d7,-(sp)
		move.l	#$FF,d7
.tile:
		moveq	#7,d3
.row:
		move.b	(a5),d1
		move.b	8(a5),d2
		moveq	#0,d0
		moveq	#7,d6
.planes:
		add.b	d2,d2
		addx.w	d0,d0
		add.b	d1,d1
		addx.w	d0,d0
		dbf	d6,.planes
		moveq	#0,d4
		moveq	#7,d6
.nibble:
		move.b	d0,d1
		lsr.w	#2,d0
		andi.l	#3,d1
		beq.s	.zero
		or.b	d5,d1
.zero:
		or.b	d1,d4
		ror.l	#4,d4
		dbf	d6,.nibble
		move.l	d4,(a6)
		addq.l	#1,a5
		dbf	d3,.row
		addq.l	#8,a5
		dbf	d7,.tile
		movem.l	(sp)+,d0-d2/d3-d7
		rts

; ====================================================================

		include	"system/md/error.asm"	; Error screen

; ====================================================================

		align $8000
EndOfRom:

; ====================================================================
; ----------------------------------------------------------------
; ROM are here
; ----------------------------------------------------------------

ROM_FILE:	binclude "roms/nestest.nes"
