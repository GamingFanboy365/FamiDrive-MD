; ===========================================================================
; +-----------------------------------------------------------------+
; FamiDrive beta
; A Modification of Nemul by Mairtrus
; 
; Now works on real hardware
; +-----------------------------------------------------------------+

		include	"system/macros.asm"	; Assembler macros

		ifndef RECOMP
RECOMP		equ 0			; 1: run recompiled code (build.sh --recompile)
		endif
		ifndef FPS
FPS		equ 0			; 1: FPS counter (build.sh --fps, needs RECOMP)
		endif
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
RAM_RcStack	ds.l 1			; recompiled code: stack at dispatch (emu/recomp.asm)
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
padState	ds.w 2			; pads as NES buttons, read each VBlank
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
fpsIdle		ds.w 1			; FPS counter (emu/fps.asm)
fpsTick		ds.w 1
fpsShow		ds.w 1
fpsOn		ds.w 1
fpsWasOn	ds.w 1
padXyz		ds.w 1
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

	; Clear all of VRAM: a real console (and some emulators, like
	; AtGames') starts with garbage there, and the planes below use
	; tile $200, past the NES CHR tiles, as the blank tile
		move.l	#$40000000,4(a6)
		move.w	#($10000/4)-1,d7
.clrvram:
		move.l	#0,(a6)
		dbf	d7,.clrvram

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
		move.b	#$40,($A10003).l		; TH high between reads
		move.b	#$40,($A10005).l
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
		if FPS
		jsr	fpsUpdate
		endif

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
		bsr	apuUpdate			; needs the Z80 bus
		move.w	#0,(z80_bus).l			; Release Z80
		bsr	readInput

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
; Copy PRG-ROM to RAM
;
; d7 - PRG-ROM size in 16 KB units (1 or 2)
; a0 - iNES file
; ----------------------------------------------------------------

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
		bsr	apuInit
		lea 	(RAM_Fami_Emu),a4
		lea	(RAM_Fami_PPU).w,a3
		lea	(RAM_Fami_RAM).w,a2
		if FPS
		jsr	fpsInit
		endif
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
		if RECOMP
		jmp	rcStart
		endif
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

		
; ====================================================================

		include	"emu/cpu.asm"		; 6502 CPU, must follow emuVint
		include	"emu/memory.asm"	; CPU memory map
		include	"emu/ppu.asm"		; PPU
		include	"emu/apu.asm"		; APU (sound)
		if RECOMP
		include	"emu/recomp.asm"	; recompiled code support
		include	"out/recomp.asm"	; from tools/recomp6502.py
		endif
		if FPS
		include	"emu/fps.asm"		; FPS counter
		endif

; ====================================================================

		include	"system/md/error.asm"	; Error screen

; ====================================================================

		align $8000
EndOfRom:

; ====================================================================
; ----------------------------------------------------------------
; ROM are here
; ----------------------------------------------------------------

ROM_FILE:	binclude "out/nes_rom.bin"	; copied here by build.sh
