; ====================================================================
; ----------------------------------------------------------------
; CPU memory map
;
; Reads and writes from 6502 code: RAM, PRG-ROM and the
; mapper, APU/controller registers, and PPU register
; reads (kept next to addr_Read so its branches stay
; short). PPU register writes are in ppu.asm.
; ----------------------------------------------------------------

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
		cmp.b	#$60,d6		; $6000
		bge	rdFrom_WRAM
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

; $6000-$7FFF: PRG RAM, when there is some (cpuWram). Without it,
; as $4000-$5FFF.
rdFrom_WRAM:
		tst.w	cpuWram(a4)
		beq.s	rdFrom_APU
		lsl.w	#8,d6
		move.b	d4,d6
		andi.w	#$1FFF,d6
		lea	(RAM_Fami_WRAM).l,a5
		move.b	(a5,d6.w),d7
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

	; Sprite 0 hit. The NES sets the flag on sprite 0's first opaque line
	; (sp0FirstRow) and clears it at the pre-render line; hidden sprites
	; (Y >= $EF) never hit. FamiDrive's frames don't keep the NES's
	; timing (code runs at other speeds, a game frame can span several
	; MD frames), so it goes by what the game does instead: a read from
	; the same place as the last one (a loop waiting for the flag to
	; change) moves ppuSp0State on, 0 (VBlank: set from the last frame)
	; -> 1 (clear: the screen is being drawn) -> 2 (set: sprite 0 hit).
	; Other reads, such as resetting the address latch before $2006
	; writes, see it as it is. Scroll changes after the hit are splits
	; (ppuXChanged), timed from sprite 0's line.
		move.w	#$2700,sr
		move.w	ppuSp0Ypos(a4),d4
		cmpi.w	#$EF,d4
		bcc.w	.no_hit
		move.l	d5,-(sp)
		move.l	4(sp),d5		; the caller's return address, plus the
		add.l	a0,d5			; 6502 PC when interpreted: which read
		move.w	ppuSp0State(a4),d6
		cmp.l	ppuRdSite(a4),d5
		beq.s	.again
		move.l	d5,ppuRdSite(a4)
		cmpi.w	#1,d6			; a first read: as it is
		beq.s	.no_hit_d5
		bra.s	.hit
.again:
		cmpi.w	#1,d6			; read again: let it change
		bhi.s	.hit			; (once hit, it stays set)
		beq.s	.to_hit
		tst.b	ppuRdLast+1(a4)		; the last read had VBlank's flag (now
		bmi.s	.hit			; clear): a loop waiting for that ends,
						; one for the hit flag reads again
		move.w	#1,ppuSp0State(a4)	; VBlank is over: the hit flag clears,
		bsr.w	ppuLine			; and the NES is at the top of the
		add.w	vNmi(a4),d5		; screen, line 0 (Excitebike's scroll
		bpl.s	.top_lo			; splits are timed from here)
		add.w	mdLines(a4),d5
.top_lo:
		cmp.w	mdLines(a4),d5
		bcs.s	.top_ok
		sub.w	mdLines(a4),d5
.top_ok:
		move.w	d5,vNmi(a4)
		bra.s	.no_hit_d5
.to_hit:
		move.w	#2,ppuSp0State(a4)
		move.w	hsCurN(a4),hsHitN(a4)	; (its split comes next: hsChoose)
	; The NES is on sprite 0's line now: the frame's line count
	; (ppuLine, from vNmi) goes from here.
		bsr.w	ppuLine
		sub.w	d4,d5
		subq.w	#1,d5			; lines from sprite 0's (Y+1)
		add.w	vNmi(a4),d5
		bpl.s	.not_before
		add.w	mdLines(a4),d5
.not_before:
		cmp.w	mdLines(a4),d5
		bcs.s	.in_frame
		sub.w	mdLines(a4),d5
.in_frame:
		move.w	d5,vNmi(a4)
.hit:
		ori.w	#$40,d7
.no_hit_d5:
		move.l	(sp)+,d5
.no_hit:

		tst.w	FamiPPUVint(a4)
		beq.s	.novflag
		clr.w	FamiPPUVint(a4)
		
; 		move.w	(vdp_ctrl),d4
; 		btst	#bitVint,d4
; 		beq.s	.novflag
		ori.w	#$80,d7
.novflag:
		move.w	d7,ppuRdLast(a4)
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
		cmpi.w	#$2000,d4
		bcs.s	.pattern
.copy:
		move.b	(a3,d4.w),ppuDataLast+1(a4)
.next:
		move.w	ppuAddrIncr(a4),d4
		add.w	d4,ppuAddrBase(a4)
		rts
.pattern:
		move.w	d4,d5			; MMC3: a 1 KB the copy is out of
		rol.w	#6,d5			; date for (chrStale; bits 2-0 =
		btst	d5,chrStale+1(a4)	; d4 / 1 KB)? Then from its bank
		beq.s	.copy
		andi.w	#7,d5
		lsl.w	#2,d5
		lea	chrSlotPtr(a4),a5
		movea.l	(a5,d5.w),a5
		andi.w	#$3FF,d4
		move.b	(a5,d4.w),ppuDataLast+1(a4)
		bra.s	.next

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
		cmp.b	#$60,d6		; $6000
		bge	wrTo_WRAM
		cmp.b	#$40,d6		; $4000
		bge.w	wrTo_APU
		cmp.b	#$20,d6		; $2000
		bge.w	wrTo_PPU

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
; WRITE request to PRG RAM ($6000-$7FFF), when there is some
; (cpuWram). Without it, as $4000-$5FFF.
; ----------------------------------------------------------------

wrTo_WRAM:
		tst.w	cpuWram(a4)
		beq.w	wrTo_APU
		lsl.w	#8,d6
		move.b	d4,d6
		andi.w	#$1FFF,d6
		lea	(RAM_Fami_WRAM).l,a5
		move.b	d7,(a5,d6.w)
		jmp	(RAM_EmuLoop).l

; ====================================================================
; ----------------------------------------------------------------
; WRITE request to ROM area, mappers
; ----------------------------------------------------------------

wrTo_PRG:
		move.w	cpuMapper(a4),d5
		subq.w	#2,d5
		beq.s	mapper2Write
		subq.w	#1,d5
		beq.s	.mapper_3
		subq.w	#1,d5
		beq.w	mmc3Write
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
		bsr.w	Nemul_LoadChr
		jmp	(RAM_EmuLoop).l

; --------------------------------------------------------
; Mapper $02, UxROM: any write picks the 16 KB PRG bank at $8000
; (the last is at $C000). Recompiled code calls this directly.
; --------------------------------------------------------

mapper2Write:
		moveq	#0,d5
		move.b	d7,d5
		bsr.w	prgSwitch
		jmp	(RAM_EmuLoop).l

; --------------------------------------------------------
; Mapper $04, MMC3. Its registers go by address bits 14-13 and 0:
; $8000 bank select (bits 2-0: the register $8001 sets, bit 6: PRG
; mode, bit 7: CHR mode), $8001 bank data, $A000 mirroring, $A001
; PRG RAM protect (PRG RAM stays on), $C000-$E001 the scanline IRQ
; (not emulated).
;
; PRG: R6 at $8000 and R7 at $A000 (8 KB banks), the last two banks
; at $C000. Only R6 and R7 as a 16 KB pair (R6 even, R7 = R6+1) are
; supported, the way games such as Super Mario Bros. 2 use them:
; PRG_IMAGES has an image for each pair. The pair is switched once
; both registers make one (the game writes them one at a time).
;
; Recompiled code calls the handlers of $8000, $8001 and $A000
; directly (mmc3WrSelect, mmc3WrData, mmc3WrMirror, value in d7), or
; does their work itself where it knows enough (mmc3_store in
; tools/recomp6502.py), with mmc3Pair for R6 and R7.
; --------------------------------------------------------

mmc3Write:
		btst	#6,d6			; $C000-$FFFF: the IRQ
		bne.s	mmc3Ignore
		btst	#0,d4
		bne.s	.odd
		btst	#5,d6
		bne.s	mmc3WrMirror
		bra.s	mmc3WrSelect
.odd:
		btst	#5,d6			; $A001: PRG RAM protect
		beq.s	mmc3WrData
mmc3Ignore:
		jmp	(RAM_EmuLoop).l

mmc3WrMirror:
		moveq	#1,d5			; $A000 bit 0: 0 vertical, 1
		and.w	d5,d7			; horizontal (ppuMirror: 1, 0)
		eor.w	d5,d7
		bsr.w	ppuSetMirror
		jmp	(RAM_EmuLoop).l

mmc3WrSelect:
		move.b	mmc3Select+1(a4),d5	; $8000
		move.b	d7,mmc3Select+1(a4)
		eor.b	d7,d5			; a new CHR mode (bit 7): all the
		bmi.s	.chr_all		; CHR banks moved
		jmp	(RAM_EmuLoop).l
.chr_all:
		moveq	#6-1,d5
.chr_bank:
		move.w	d5,-(sp)
		bsr.s	mmc3Chr
		move.w	(sp)+,d5
		dbf	d5,.chr_bank
		jmp	(RAM_EmuLoop).l

mmc3WrData:
		move.w	mmc3Select(a4),d5	; $8001: bank data
		andi.w	#7,d5
		lea	mmc3Regs(a4),a5
		cmpi.w	#6,d5
		bcc.s	.prg
		cmp.b	(a5,d5.w),d7		; R0-R5: CHR, a new bank
		beq.s	.done			; (games set them every frame)
		move.b	d7,(a5,d5.w)
		bsr.s	mmc3Chr
.done:
		jmp	(RAM_EmuLoop).l
.prg:
		move.b	d7,(a5,d5.w)
		moveq	#0,d5
		move.b	6(a5),d5		; R6, R7: PRG
		lsr.b	#1,d5
		bcs.s	.done
		move.b	7(a5),d6
		lsr.b	#1,d6
		bcc.s	.done
		cmp.b	d5,d6
		bne.s	.done
		btst	#6,mmc3Select+1(a4)	; PRG mode 1: R6 at $C000
		bne.s	.prg_mode_1
		bsr.w	prgSwitch
		jmp	(RAM_EmuLoop).l
.prg_mode_1:
		lea	(errStrMmc3Prg).l,a0
		jmp	(MD_ShowError).l

; --------------------------------------------------------
; MMC3: a CHR bank register -> the MD tiles that show its bank
; (chrUpdate), and chrSlotPtr, the bank each 1 KB of the pattern
; tables shows. The copy of them (a3) is left as it was: chrStale
; has the 1 KB parts it's out of date for (chrSync). CHR mode 0:
; R0, R1 are 2 KB at $0000, $0800, R2-R5 1 KB at $1000-$1C00;
; mode 1 swaps the halves.
;
; d5.w - the register, 0-5
; --------------------------------------------------------

mmc3Chr:
		tst.w	ppuChrRam(a4)		; CHR-RAM: the registers do nothing
		bne.s	.done
		movem.l	d0/a0,-(sp)
		lea	mmc3Regs(a4),a5
		moveq	#0,d0
		move.b	(a5,d5.w),d0		; the bank, in 1 KB
		cmpi.w	#2,d5
		bcc.s	.one_kb
		andi.b	#$FE,d0			; R0, R1: 2 KB
		move.w	d5,d4
		ror.w	#5,d4			; * $800
		move.w	#$800,d6
		bra.s	.place
.one_kb:
		move.w	d5,d4			; R2-R5: 1 KB
		subq.w	#2,d4
		lsl.w	#8,d4
		lsl.w	#2,d4
		addi.w	#$1000,d4
		move.w	#$400,d6
.place:
		tst.b	mmc3Select+1(a4)	; mode 1
		bpl.s	.mode_0
		eori.w	#$1000,d4
.mode_0:
		andi.w	#chrBankMask,d0
		lsl.l	#8,d0			; * 1 KB
		lsl.l	#2,d0
		movea.l	emuChrRom(a4),a0
		adda.l	d0,a0
		bsr.w	chrUpdate
		move.w	d4,d5			; and the pattern tables show a0 there:
		rol.w	#6,d5			; d5 = d4 / 1 KB (d4 is whole KB)
		bset	d5,chrStale+1(a4)
		lea	chrSlotPtr(a4),a5
		lsl.w	#2,d5
		move.l	a0,(a5,d5.w)
		cmpi.w	#$400,d6		; 2 KB: the next 1 KB too
		beq.s	.slots
		lea	$400(a0),a0
		move.l	a0,4(a5,d5.w)
		lsr.w	#2,d5
		addq.w	#1,d5
		bset	d5,chrStale+1(a4)
.slots:
		movem.l	(sp)+,d0/a0
.done:
		rts

; --------------------------------------------------------
; Banked PRG (PRG_BANKED): switch the 16 KB bank at $8000.
; a1 moves to the bank's image in PRG_IMAGES, and so does the PC
; (a0), unless it's in RAM. Recompiled code keeps a1+$8000 in a0,
; which moves too, and its dispatch goes by the bank's rcTable.
;
; d5.l - bank
; --------------------------------------------------------

prgSwitch:
		if PRG_BANKED
		andi.l	#prgBankMask,d5
		cmpi.w	#NES_PRG16,d5
		bcs.s	.bank_ok
		subi.w	#NES_PRG16,d5
.bank_ok:
		move.l	d5,d6			; image: bank * $8000
		swap	d6
		lsr.l	#1,d6
		addi.l	#PRG_IMAGES,d6
		cmpa.l	d6,a1			; there already (games often pick
		beq.s	.done			; the bank they're in)
		if RECOMP
		lsl.w	#2,d5			; the bank's code (emu/recomp.asm)
		lea	(rcBankTables).l,a5
		move.l	(a5,d5.w),rcCurTable(a4)
		endif
		move.l	a0,d5
		sub.l	a1,d5
		cmpi.l	#$8000,d5
		bhi.s	.pc_elsewhere
		movea.l	d6,a0
		adda.l	d5,a0
.pc_elsewhere:
		movea.l	d6,a1
		move.l	d6,cpuPrgImg(a4)
.done:
		endif
		rts

		if RECOMP
; Recompiled code that knows $8000 picked R6 or R7 (PRG mode 0) puts
; the value there itself, then calls this: the pair, as mmc3WrData.
mmc3Pair:
		moveq	#0,d5
		move.b	mmc3Regs+6(a4),d5
		lsr.b	#1,d5
		bcs.s	.done
		move.b	mmc3Regs+7(a4),d6
		lsr.b	#1,d6
		bcc.s	.done
		cmp.b	d5,d6
		beq.s	prgSwitch
.done:
		rts
		endif

; ====================================================================
; ----------------------------------------------------------------
; WRITE to APU
; ----------------------------------------------------------------

wrTo_APU:
		cmpi.b	#$1F,d4
		bhi.s	APU_Null
		move.w	d4,d5			; register, for apuStore
		add.w	d4,d4
		move.w	wrAPU_Table(pc,d4.w),d4
		jmp	wrAPU_Table(pc,d4.w)

; ----------------------------------------------------------------
wrAPU_Table:	dc.w apuStore-wrAPU_Table	; $4000
		dc.w apuStore-wrAPU_Table	; $4001
		dc.w apuStore-wrAPU_Table	; $4002
		dc.w apuStore-wrAPU_Table	; $4003
		dc.w apuStore-wrAPU_Table	; $4004
		dc.w apuStore-wrAPU_Table	; $4005
		dc.w apuStore-wrAPU_Table	; $4006
		dc.w apuStore-wrAPU_Table	; $4007
		dc.w apuStore-wrAPU_Table	; $4008
		dc.w apuStore-wrAPU_Table	; $4009
		dc.w apuStore-wrAPU_Table	; $400A
		dc.w apuStore-wrAPU_Table	; $400B
		dc.w apuStore-wrAPU_Table	; $400C
		dc.w apuStore-wrAPU_Table	; $400D
		dc.w apuStore-wrAPU_Table	; $400E
		dc.w apuStore-wrAPU_Table	; $400F
		dc.w apuStore-wrAPU_Table	; $4010
		dc.w apuStore-wrAPU_Table	; $4011
		dc.w apuStore-wrAPU_Table	; $4012
		dc.w apuStore-wrAPU_Table	; $4013
		dc.w APU_OAMDMA-wrAPU_Table	; $4014
		dc.w apuStore-wrAPU_Table	; $4015
		dc.w APU_Input-wrAPU_Table	; $4016
		dc.w apuStore-wrAPU_Table	; $4017
		dc.w APU_Null-wrAPU_Table	; $4018
		dc.w APU_Null-wrAPU_Table	; $4019
		dc.w APU_Null-wrAPU_Table	; $401A
		dc.w APU_Null-wrAPU_Table	; $401B
		dc.w APU_Null-wrAPU_Table	; $401C
		dc.w APU_Null-wrAPU_Table	; $401D
		dc.w APU_Null-wrAPU_Table	; $401E
		dc.w APU_Null-wrAPU_Table	; $401F

APU_Null:
		jmp	(RAM_EmuLoop).l


; Strobe: latch the buttons read at the last VBlank
APU_Input:
		tst.b	d7
		beq.s	APU_Null
		move.l	padState(a4),cpuInputData(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; Read both pads into padState, once per frame from MD_Vint
;
; A 6-button pad counts TH changes and, after more than one read
; within about 1.5 ms, answers with its extra buttons (X Y Z Mode)
; in place of the d-pad. Games may strobe $4016 many times a frame,
; so the pads are read here, one TH cycle per frame, and the strobe
; only latches the result.
; ----------------------------------------------------------------

readInput:
		lea	($A10003).l,a3
		lea	padState(a4),a5
		bsr	.this_pad
		if FPS
		jsr	(readXyz).l			; pad 1's X Y Z toggle the FPS counter
		endif
		addq.w	#2,a3

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


; ----------------------------------------------------------------
; Sprite 0's Y for the hit, from OAM at a5: the NES only reports the
; hit where sprite 0 has an opaque pixel, so start at its first row
; that has one (rows of a flipped sprite count from the bottom). A
; sprite with no opaque pixel never hits.
;
; a3 - PPU buffer (pattern tables at the start, see chrStale)
; ----------------------------------------------------------------

sp0FirstRow:
		moveq	#0,d4
		move.b	1(a5),d4		; tile
		moveq	#8-1,d5			; rows - 1
		tst.w	ppuSprWide(a4)
		beq.s	.small
		moveq	#16-1,d5		; 8x16: bit 0 picks the table
		lsr.w	#1,d4
		bcc.s	.big
		addi.w	#$1000/32,d4
.big:
		lsl.w	#5,d4
		bra.s	.addr
.small:
		lsl.w	#4,d4
		btst	#6,ppuChrBank+1(a4)	; $2000 bit 3: sprites at $1000
		beq.s	.addr
		addi.w	#$1000,d4
.addr:
		movem.l	d0-d1/a0,-(sp)
		lea	(a3,d4.w),a0
		move.w	d4,d0			; MMC3: a 1 KB the copy is out of
		rol.w	#6,d0			; date for (chrStale; bits 2-0 =
		btst	d0,chrStale+1(a4)	; d4 / 1 KB)? Then from its bank
		beq.s	.copy
		andi.w	#7,d0
		lsl.w	#2,d0
		lea	chrSlotPtr(a4),a0
		movea.l	(a0,d0.w),a0
		andi.w	#$3FF,d4
		adda.w	d4,a0
.copy:
		moveq	#0,d0			; row
.row:
		move.w	d0,d1			; row -> byte: rows 8-15 are the next tile
		btst	#3,d1
		beq.s	.top_half
		addq.w	#8,d1
.top_half:
		move.b	(a0,d1.w),d4		; plane 0
		or.b	8(a0,d1.w),d4		; plane 1
		bne.s	.opaque
		addq.w	#1,d0
		dbf	d5,.row
		move.w	#$FF,ppuSp0Ypos(a4)	; all transparent
		bra.s	.done
.opaque:
		tst.b	2(a5)			; vertically flipped: count from the bottom
		bpl.s	.down
		move.w	ppuSprWide(a4),d4	; last row: 7 or 15
		lsr.w	#5,d4
		addq.w	#7,d4
.last:
		move.w	d4,d1
		btst	#3,d1
		beq.s	.top_half2
		addq.w	#8,d1
.top_half2:
		move.b	(a0,d1.w),d0
		or.b	8(a0,d1.w),d0
		bne.s	.flipped
		subq.w	#1,d4
		bpl.s	.last
.flipped:
		move.w	ppuSprWide(a4),d0
		lsr.w	#5,d0
		addq.w	#7,d0
		sub.w	d4,d0			; rows below the last opaque one
.down:
		moveq	#0,d4
		move.b	(a5),d4			; Y
		add.w	d0,d4
		cmpi.w	#$EE,d4
		bls.s	.y_ok
		move.w	#$EE,d4
		cmpi.b	#$EF,(a5)		; hidden stays hidden
		bcs.s	.y_ok
		move.w	#$FF,d4
.y_ok:
		move.w	d4,ppuSp0Ypos(a4)
.done:
		movem.l	(sp)+,d0-d1/a0
		rts

APU_OAMDMA:
		movem.l	d0-d3/d7/a3/a6,-(sp)	; d7: handlers leave its upper bits clear
		lsl.w	#8,d7
		move.w	ppuOamUnk(a4),d6
		eori.w	#1,d6
		move.b	ppuOamAddr(a4,d6.w),d7
		lea	(a2,d7.w),a5
		bsr	sp0FirstRow

	; NES OAM (Y, tile, attributes, X) to the MD's sprite table. Only
	; sprites that can show are listed (the NES hides Y >= $EF, the MD
	; shows NES lines up to 231), so the list and its DMA are shorter.
	; It goes in the table for this game frame (sprWrite): MD_Vint shows
	; the previous frame's sprites while it shows that frame's scroll.
		lea	vdpSprData(a4),a3
		adda.w	sprWrite(a4),a3
		lea	(oamAttr).l,a6		; MD tiles $100: table 0, $200: table 1
		moveq	#1,d4			; 8x16: tile bit 0 picks the table
		tst.w	ppuSprWide(a4)
		bne.s	.tall
		moveq	#0,d4			; 8x8: $2000 bit 3 does
		btst	#6,ppuChrBank+1(a4)
		beq.s	.tall
		lea	(oamAttr1).l,a6
.tall:
		move.w	ppuSprWide(a4),d6
		addq.w	#1,d6			; size, and the link to the next sprite
		moveq	#$79,d0			; NES line L+1 is MD line L-8, +128
		move.w	#$80,d1
		moveq	#0,d2
		moveq	#$E7-$100,d5		; Y $E7 on: hidden
	; unrolled: a hidden sprite (most of them, often) is a load, a
	; compare and a branch
oamSpr		set	0
		rept	64
		if (oamSpr==62)&&FPS
		tst.w	fpsOn(a4)		; the counter takes the last two slots
		bne.w	.listed
		endif
		move.b	oamSpr*4(a5),d2		; Y
		cmp.b	d5,d2
		bcc.s	+
		move.w	d2,d7
		add.w	d0,d7
		move.w	d7,(a3)+
		move.w	d6,(a3)+
		addq.w	#1,d6
		move.b	oamSpr*4+1(a5),d2	; tile
		move.w	d2,d7			; 8x16, an odd one: table 1 ($100
		and.w	d4,d7			; on) and the even tile, + $FF
		neg.b	d7
		add.w	d2,d7
		moveq	#0,d3
		move.b	oamSpr*4+2(a5),d3	; attributes
		add.w	d3,d3
		add.w	(a6,d3.w),d7
		move.w	d7,(a3)+
		move.b	oamSpr*4+3(a5),d2	; X
		move.w	d2,d7
		add.w	d1,d7
		move.w	d7,(a3)+
+
oamSpr		set	oamSpr+1
		endm
.listed:
		lea	vdpSprData(a4),a6
		adda.w	sprWrite(a4),a6
		cmpa.l	a6,a3
		bne.s	.end_list
		clr.l	(a3)+			; none: one sprite above the screen
		clr.l	(a3)+
.end_list:
		sf	-5(a3)			; the last one ends the list,
		if FPS
		tst.w	fpsOn(a4)
		beq.s	.no_counter
		move.b	#fpsSprite,-5(a3)	; or links to the FPS counter
.no_counter:
		endif
		suba.l	a6,a3
		move.l	a3,d7
		lsr.w	#1,d7
		move.w	d7,vdpSprWords-vdpSprData(a6)	; for the DMA (MD_Vint)
		move.w	sprWrite(a4),sprLatest(a4)
		movem.l	(sp)+,d0-d3/d7/a3/a6
		jmp	(RAM_EmuLoop).l

; NES sprite attributes to the MD's: priority (inverted: the NES's bit
; puts the sprite behind the background), palette, vertical and
; horizontal flip, and the first tile of the sprite tile set: $100
; for table 0 (and 8x16 sprites, added to the tile), $200 for table 1
oamAttrs	macro tiles
oamAttrI	set	0
		rept	256
		dc.w	tiles|(((~oamAttrI)&$20)<<10)|((oamAttrI&3)<<13)|((oamAttrI&$C0)<<5)
oamAttrI	set	oamAttrI+1
		endm
		endm
oamAttr:	oamAttrs $100
oamAttr1:	oamAttrs $200
