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
		include	"out/nes_info.asm"	; the NES ROM's mapper and PRG size (tools/nesinfo.py)
PRG_BANKED	equ (NES_MAPPER=2)||(NES_MAPPER=4)	; PRG-ROM in 16 KB banks: PRG_IMAGES
prgBankMask	set 1			; its banks, rounded up to a power of 2, -1
		while prgBankMask<NES_PRG16
prgBankMask	set prgBankMask*2
		endm
prgBankMask	set prgBankMask-1
chrBankMask	set 1			; its CHR-ROM's 1 KB banks, rounded up likewise
		while chrBankMask<NES_CHR8*8
chrBankMask	set chrBankMask*2
		endm
chrBankMask	set chrBankMask-1

; ====================================================================
; ----------------------------------------------------------------
; Emulator variables
; ----------------------------------------------------------------

; ------------------------------------------------
; RAM
; ------------------------------------------------

RAM_Fami_ROM	equ $FFFF0000		; PRG-ROM (not banked)
RAM_Fami_WRAM	equ $FFFF0000		; PRG RAM, $6000-$7FFF (banked PRG: PRG_IMAGES)
RAM_Fami_ChrDma	equ $FFFF2000		; MMC3: MD tiles for VRAM, queued for VBlank (chrUpdate, chrDma), 2 KB
RAM_Fami_ChrCache equ $FFFF2800		; MMC3: bank switches seen before, 32 lines of 512 bytes (chrUpdate)
RAM_Fami_Emu	equ $FFFF8000		; Emulator buffer
RAM_RcRet	equ RAM_Fami_Emu+$A50	; recompiled code: RTS return caches (rcDispatchC), 120 of 12 bytes
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
RAM_HintCount	ds.w 1			; line interrupts taken (MD_Hint, ppuMeasureLines)
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
vdpPalDirty	ds.b 1			; vdpPalette changed since the last DMA
		ds.b 1
vdpSprData	ds.w 4*64		; sprite tables (APU_OAMDMA), two: one for the game
vdpSprWords	ds.w 1			; frame being run, one for the frame before it,
vdpSprData2	ds.w 4*64		; each with its words in use. sprWrite etc. are
vdpSprWords2	ds.w 1			; offsets from vdpSprData: 0 or sprTable2
sprWrite	ds.w 1			; the table this game frame's OAM DMA goes to
sprLatest	ds.w 1			; the table with the newest sprites
sprDone		ds.w 1			; the previous game frame's
hsShowDone	ds.w 1			; MD_Vint shows the previous game frame (hsChoose)
hsHitN		ds.w 1			; hsCurN when the game saw sprite 0 hit (rdPPU_Status)
hsFrame		ds.w 1			; game frames begun (ppuFrameStart)
hsShownF	ds.w 1			; and the one MD_Vint showed last (hsChoose)
vsDone		ds.l 1			; and its vertical scroll
fpsIdle		ds.w 1			; FPS counter (emu/fps.asm)
fpsTick		ds.w 1
fpsShow		ds.w 1
fpsOn		ds.w 1
fpsWasOn	ds.w 1
padXyz		ds.w 1
vNmi		ds.w 1			; ppuClock when the game's frame began (ppuFrameStart)
hsTopCur	ds.l 1			; this game frame's scroll from the top (planes A, B)
hsCurN		ds.w 1			; and its splits: line, scroll
hsCur		ds.l 8
hsTopDone	ds.l 1			; the previous game frame's
hsDoneN		ds.w 1
hsDone		ds.l 8
hsShown		ds.l 1			; the scroll last set (hsApply): as hsTopCur,
		ds.w 1			; hsCurN
		ds.l 8			; and hsCur
hsShownOk	ds.w 1			; hsShown is valid
ppuTX		ds.w 1			; the PPU's horizontal scroll (t register): nametable X, coarse X, fine X
ppuMaskOn	ds.w 1			; $2001 shows the background or sprites
ppuMaskNew	ds.w 1			; $2001 write for the next VBlank (bit 15: pending)
ppuSp0State	ds.w 1			; what the game saw of sprite 0 hit this frame (rdPPU_Status)
ppuRdSite	ds.l 1			; where the last $2002 read came from (rdPPU_Status)
vbLate		ds.w 1			; a VBlank came during the NMI handler: next NMI on its RTI
rcDelayDots	ds.w 1			; NES time left over from rcDelay, in PPU dots
ppuRdLast	ds.w 1			; what the last $2002 read returned (rdPPU_Status)
ppuScrollSet	ds.w 1			; the game wrote both $2005 bytes this frame (ppuXChanged)
ppuNtXor	ds.w 1			; nametable address xor for the mirrored copy ($400 or $800)
ppuCmdXor	ds.l 1			; and VDP command xor for its cells (ppuDrwCell)
mdLines		ds.w 1			; lines the console draws a frame: 262 on a Mega Drive
vOddLine	ds.w 1			; line for odd V values in VBlank (AtGames), -1: none
vLineTbl	ds.w 512		; lines since VBlank began, for each V counter value
				; (the second half: ppuMeasureLines' scratch)
cpuPrgImg	ds.l 1			; $8000-$FFFF: RAM_Fami_ROM, or a PRG_IMAGES image (a1)
cpuWram		ds.w 1			; 1: PRG RAM at $6000-$7FFF (RAM_Fami_WRAM)
mmc3Select	ds.w 1			; MMC3 (mapper 4): the last $8000 write
mmc3Regs	ds.b 8			; and its bank registers R0-R7 (mmc3Write)
rcCurTable	ds.l 1			; recompiled banked PRG: the bank at $8000's rcTable (prgSwitch)
chrDmaHead	ds.w 1			; MMC3: the first MD tiles queued for VRAM (RAM_Fami_ChrDma)
chrDmaTail	ds.w 1			; and where the next go
nmiCredit	ds.w 1			; recompiled code: VBlanks not yet answered by an NMI (rcNmi)
nmiWaitDue	ds.w 1			; and 1: one is due where the game waits for it (rcNmiWait)
nmiHold		ds.w 1			; 1: the game took its last NMI waiting for it
chrSlotPtr	ds.l 8			; MMC3: the CHR-ROM data each 1 KB of the pattern tables shows,
chrStale	ds.w 1			; and those a3's copy is out of date for (bits 0-7, chrSync)
		finish
sprTable2	equ vdpSprData2-vdpSprData

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
		bsr.w	Sound_LoadZ80
		bsr.w	Sound_PsgInit
		bsr.w	Video_Init
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
		move.w	#$8124,4(a6)		; display off: the VDP takes VRAM writes much
						; faster (ppuMaskApply turns it on with the
						; game's rendering)
		move.w	#$8F02,4(a6)

	; Clear all of VRAM: a real console (and some emulators, like
	; AtGames') starts with garbage there
		move.l	#$40000000,4(a6)
		move.w	#($10000/4)-1,d7
.clrvram:
		move.l	#0,(a6)
		dbf	d7,.clrvram

		move.l	#$40000003,4(a6)	; plane A
		bsr.s	.plane
		move.l	#$60000003,4(a6)	; plane B
		bsr.s	.plane
		move.l	#$60000001,4(a6)	; tile $300 (VRAM $6000): blank
		moveq	#32/4-1,d7
.blank_tile:
		move.l	#0,(a6)
		dbf	d7,.blank_tile
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

; The NES nametables' rows (0-29) as the empty copy of them in RAM
; (tile 0, attribute 0) draws them, so that writing a byte that
; doesn't change can skip VRAM (wrPPU_Data); rows 30-63 (the other
; plane shows through them) with tile $300, past the NES tile sets
; ($000-$2FF, Nemul_LoadChr): blank
.plane:
		move.w	#30*64-1,d7
.cells:
		move.w	#$8000,(a6)
		dbf	d7,.cells
		move.w	#2*64+$1000/2-1,d7
.blank:
		move.w	#$300,(a6)
		dbf	d7,.blank
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
		dc.b (%000|%00)			; No ExtInt, Scroll: VSCR:full HSCR:full (per line when split, MD_Vint)
		dc.b $00			; H40, No shadow mode, Normal resolution
		dc.b (($B800)>>10)		; HScroll at VRAM $B800 (%00xxxxxx)
		dc.b $00			; Nothing
		dc.b $02			; VDP Auto increment by $02
		dc.b (%01<<4)|%01		; Layer size: V64 H64
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
		
		bra.w	emuStart

; ====================================================================
; ----------------------------------------------------------------
; VBlank
; ----------------------------------------------------------------

MD_Vint:
		movem.l	d0-d7/a0-a6,-(sp)
		lea	(RAM_Fami_Emu).l,a4		; whatever the interrupted code had there
		lea	($C00000).l,a6
		jsr	ppuClock			; when this began (see the end)
		move.w	d5,-(sp)

		tst.w	ppuNmiFlag(a4)			; no NMI (and not in the NMI handler,
		bne.s	.nmi_on				; which turns it off while it runs):
		tst.w	cpuFamiVint(a4)			; frames start at VBlank
		bne.s	.nmi_on
		jsr	ppuFrameStart
.nmi_on:
		tst.w	cpuFamiVint(a4)			; $2001 takes effect here, not
		beq.s	.mask				; mid-screen, and not while the game
		cmpi.w	#2,ppuSp0State(a4)		; is in its VBlank work (in its NMI
		bne.s	.mask_later			; handler, before sprite 0 hit):
.mask:							; that only shows from the next frame
		jsr	ppuMaskApply
.mask_later:
		jsr	hsChoose			; the game frame to show: its
		lea	vdpScrlY(a4),a0		; vertical scroll, sprites and
		move.w	sprLatest(a4),d2		; horizontal scroll (hsApply)
		tst.w	hsShowDone(a4)
		beq.s	.this_frame
		lea	vsDone(a4),a0
		move.w	sprDone(a4),d2
.this_frame:
		move.w	#$8F02,4(a6)
		move.l	#$40000010,4(a6)
		move.l	(a0),(a6)
		lea	vdpSprData(a4),a0		; its sprite table
		adda.w	d2,a0
		if FPS
		jsr	(fpsUpdate).l			; the counter's sprites, in that table
		move.l	#$94019300,4(a6)		; all 64: the counter is in the last two
		else
		move.w	vdpSprWords-vdpSprData(a0),d0	; the sprites listed
		bne.s	.spr_words
		moveq	#4,d0				; none yet
.spr_words:
		move.w	#$9300,d1
		move.b	d0,d1
		move.w	d1,4(a6)
		lsr.w	#8,d0
		ori.w	#$9400,d0
		move.w	d0,4(a6)
		endif
		move.w	#$0100,(z80_bus).l
		move.l	a0,d0				; DMA source: the table
		lsr.l	#1,d0
		move.w	#$9500,d1
		move.b	d0,d1
		move.w	d1,4(a6)
		lsr.l	#8,d0
		move.w	#$9600,d1
		move.b	d0,d1
		move.w	d1,4(a6)
		lsr.l	#8,d0
		andi.w	#$7F,d0
		ori.w	#$9700,d0
		move.w	d0,4(a6)
		move.w	#$7C00,4(a6)
		move.w	#$0002|$80,-(sp)
.wait:		btst	#0,(z80_bus).l
		bne.s	.wait
		move.w	(sp)+,4(a6)
		tst.b	vdpPalDirty(a4)			; palette, if it changed
		beq.s	.same_palette
		sf	vdpPalDirty(a4)
		move.l	#$94009340,4(a6)
		move.l	#$96009500+(((RAM_Fami_Emu+vdpPalette)<<7)&$FF0000)|(((RAM_Fami_Emu+vdpPalette)>>1)&$FF),4(a6)
		move.w	#$9700|(((RAM_Fami_Emu+vdpPalette)>>17)&$7F),4(a6)
		move.w	#$C000,4(a6)
		move.w	#$0000|$80,-(sp)
.wait2:		btst	#0,(z80_bus).l
		bne.s	.wait2
		move.w	(sp)+,4(a6)
.same_palette:
		jsr	hsApply				; horizontal scroll
		if (NES_MAPPER=4)&&(NES_CHR8<>0)
		jsr	(chrVblank).l			; MMC3: tiles that changed (chrUpdate)
		endif
		bsr.w	apuUpdate			; needs the Z80 bus
		move.w	#0,(z80_bus).l			; Release Z80
		bsr.w	readInput

		clr.w	vdpHintSp0(a4)
		if RECOMP
		move.w	#1,nmiWaitDue(a4)		; an NMI is due: at once, or when the
		tst.w	ppuNmiFlag(a4)			; game next waits for it, if it does,
		beq.s	.nmi_now			; up to a frame later (emu/recomp.asm)
		addq.w	#1,nmiCredit(a4)		; (with NMIs off, none: the checks
		tst.w	nmiHold(a4)			; just clear the flags)
		beq.s	.nmi_now
		cmpi.w	#2,nmiCredit(a4)
		bcs.s	.nmi_set
.nmi_now:
		move.w	#1,FamiMdVint(a4)
.nmi_set:
		else
		move.w	#1,FamiMdVint(a4)
		endif
		move.w	#1,FamiPPUVint(a4)

	; The game's code didn't run meanwhile: its frame's clock (vNmi,
	; for raster timing) skips the lines this took
		jsr	ppuClock
		sub.w	(sp)+,d5
		bpl.s	.took
		add.w	mdLines(a4),d5
.took:
		add.w	vNmi(a4),d5
		cmp.w	mdLines(a4),d5
		bcs.s	.vnmi_ok
		sub.w	mdLines(a4),d5
.vnmi_ok:
		move.w	d5,vNmi(a4)
		movem.l	(sp)+,d0-d7/a0-a6
		rte

; ====================================================================
; ----------------------------------------------------------------
; HBlank
; ----------------------------------------------------------------

MD_Hint:
		addq.w	#1,(RAM_HintCount).w	; only on while ppuMeasureLines runs
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
		cmpi.b	#2,d1
		beq.s	.mapper_ok
		cmpi.b	#3,d1
		beq.s	.mapper_ok
		cmpi.b	#4,d1
		beq.s	.mapper_ok
		lea	(errStrMapper).l,a0
		jmp	(MD_ShowError).l
.mapper_ok:
		move.b	4(a0),d1		; PRG-ROM size in 16 KB units
		if PRG_BANKED
		cmpi.b	#2,d1			; banked: 32 KB to 512 KB
		bcs.s	.prg_bad
		cmpi.b	#32,d1
		bls.s	.prg_ok
		else
		cmpi.b	#1,d1
		beq.s	.prg_ok
		cmpi.b	#2,d1
		beq.s	.prg_ok
		endif
.prg_bad:
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
		if PRG_BANKED
		move.l	#PRG_IMAGES,cpuPrgImg(a3) ; bank 0 at $8000 to begin with
		move.l	#$00020405,mmc3Regs(a3)	; MMC3: as the CHR copied below (the
		move.l	#$06070001,mmc3Regs+4(a3) ; first 8 KB) and PRG image 0
		move.w	#1,cpuWram(a3)
		lea	(RAM_Fami_WRAM).l,a5	; and PRG RAM, cleared
		moveq	#0,d7
		move.w	#$2000/4-1,d1
.clrwram:
		move.l	d7,(a5)+
		dbf	d1,.clrwram
		if (NES_MAPPER=4)&&(NES_CHR8<>0)
		lea	(RAM_Fami_ChrCache).l,a5 ; MMC3: no bank switches seen yet
		moveq	#32-1,d1		; (chrUpdate)
.chr_cache:
		clr.l	(a5)
		lea	512(a5),a5
		dbf	d1,.chr_cache
		endif
		movea.l	a0,a4			; CHR-ROM: after PRG-ROM (as romGrabPrg
		adda.l	#$10+NES_PRG16*$4000,a4	; leaves a4)
		else
		moveq	#0,d7			; PRG-ROM copy
		move.b	4(a0),d7
		bsr	romGrabPrg
		lea	(RAM_Fami_Emu).l,a3	; romGrabPrg uses a3
		move.l	#RAM_Fami_ROM,cpuPrgImg(a3)
		endif
		move.w	d5,cpuMapper(a3)
	
	; Mirror check
		move.w	#0,d7			; 0 - horizontal
		btst	#0,6(a0)		; PPU mirroring
		beq.s	.mirror_set
		move.w	#1,d7			; 1 - vertical
.mirror_set:
		move.w	d7,ppuMirror(a3)
		move.w	#$400,ppuNtXor(a3)	; horizontal: 0 = 1, 2 = 3, the other half
		move.l	#$00400000,ppuCmdXor(a3) ; of the plane
		tst.w	d7
		beq.s	.xor_set
		move.w	#$800,ppuNtXor(a3)	; vertical: 0 = 2, 1 = 3, the other plane
		move.l	#$20000000,ppuCmdXor(a3)
.xor_set:
		
	; COPY CHR-ROM TO RAM, or use the (cleared) buffer as CHR-RAM
		move.l	a4,emuChrRom(a3)
		tst.b	5(a0)
		bne.s	.chr_rom
		move.w	#1,ppuChrRam(a3)
		bra.s	.chr_done
.chr_rom:
		if (NES_MAPPER=4)&&(NES_CHR8<>0)
		lea	chrSlotPtr(a3),a5	; MMC3: the CHR-ROM each 1 KB of the
		move.l	a4,d7			; pattern tables shows (chrUpdate),
		moveq	#8-1,d1			; the first 8 KB as copied below
.chr_slots:
		move.l	d7,(a5)+
		addi.l	#$400,d7
		dbf	d1,.chr_slots
		endif
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
		jsr	ppuMeasureLines
		bsr.w	apuInit
		lea 	(RAM_Fami_Emu),a4
		lea	(RAM_Fami_PPU).w,a3
		lea	(RAM_Fami_RAM).w,a2
		if FPS
		jsr	(fpsInit).l
		endif
		bsr.w	Nemul_LoadChr
		movea.l	cpuPrgImg(a4),a1	; PRG at $8000-$FFFF
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
		tst.w	cpuFamiVint(a4)		; in the NMI handler: the next NMI
		bne.s	.late			; when it returns (mos_RTI)
		tst.w	ppuNmiFlag(a4)
		beq.s	emuVint

		jmp	doVint			; NMI: out of line, see after cpu.asm
.late:
		move.w	#1,vbLate(a4)
		bra.s	emuVint


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

; ------------------------------------------------
; Take the NMI (from famiVInt)
doVint:
		move.l	#emuVint,(RAM_EmuLoop+2).l
		move.w	#1,cpuFamiVint(a4)
		bsr.w	ppuFrameStart

		bsr	famiGetP		; Save PC and P (B clear)
		move.b	d5,d7
		andi.b	#$EF,d7
		swap	d3
		move.l	a0,d4
		sub.l	a1,d4
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

		movea.l	a1,a0			; PRG at $8000-$FFFF
		move.w	#cpuNMI,d6		; go to NMI
		add.w	d6,a0
		move.b	1(a0),d6
		lsl.w	#8,d6
		move.b	(a0),d6
		and.w	#$7FFF,d6
		movea.l	a1,a0
		add.w	d6,a0
		jmp	emuVint

		include	"emu/memory.asm"	; CPU memory map
		include	"emu/ppu.asm"		; PPU
		include	"emu/vlines.asm"	; lines a frame, and the V counter's
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

		include	"emu/ppu_tables.asm"	; PPU lookup tables (big: last)

; ====================================================================

		align $8000
EndOfRom:

; ====================================================================
; ----------------------------------------------------------------
; ROM are here
; ----------------------------------------------------------------

ROM_FILE:	binclude "out/nes_rom.bin"	; copied here by build.sh

; ----------------------------------------------------------------
; Banked PRG-ROM (mappers 2 and 4): a 32 KB image of $8000-$FFFF
; for each 16 KB bank at $8000, with the last bank at $C000. The
; CPU runs code and reads PRG through a1, the image's start, so a
; bank switch only moves a1 (and the PC in it, a0: prgSwitch). The
; images are 32 KB aligned: a0's low 15 bits are the PC's (mos_JSR).
; ----------------------------------------------------------------

		if PRG_BANKED
		align $8000
PRG_IMAGES:
prgImage	set 0
		rept NES_PRG16
		binclude "out/nes_rom.bin",$10+prgImage*$4000,$4000
		binclude "out/nes_rom.bin",$10+(NES_PRG16-1)*$4000,$4000
prgImage	set prgImage+1
		endm
		endif

; ----------------------------------------------------------------
; MMC3 games' CHR-ROM as MD tiles, from tools/nesinfo.py: for the
; BG, then for sprites (opaque pixels +8), 2 bytes for each byte of
; CHR-ROM. Their bank switches copy these to VRAM (chrUpdate), which
; is much faster than converting the tiles. Then a word for each
; tile, its ID: the number of the first tile like it.
; ----------------------------------------------------------------

		if (NES_MAPPER=4)&&(NES_CHR8<>0)
		rompad	(*+$1FFFF)&$FFFE0000	; 128 KB aligned (a DMA can't cross 128 KB)
CHR_MD:		binclude "out/chr_md.bin"
CHR_ID		equ CHR_MD+NES_CHR8*$8000
		else
CHR_MD		equ 0
CHR_ID		equ 0
		endif
