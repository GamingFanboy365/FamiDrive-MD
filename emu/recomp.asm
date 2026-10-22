; ====================================================================
; ----------------------------------------------------------------
; Recompiled code support (RECOMP=1)
;
; tools/recomp6502.py translates the game's 6502 code into 68000
; code (out/recomp.asm) that runs instead of the interpreter. It
; keeps the interpreter's registers (see emuLoop) and calls the
; same memory, PPU and APU handlers. Those end with
; "jmp (RAM_EmuLoop).l", so rcStart turns RAM_EmuLoop into an rts.
;
; Banked PRG (PRG_BANKED): each bank's code has its own rcTable,
; for $8000-$BFFF while it's at $8000 (rcCurTable, set by
; prgSwitch); the fixed bank's rcTable is for $C000-$FFFF.
; Translated code reads and writes PRG RAM at rcWram+addr(a4).
; ----------------------------------------------------------------

rcWram		equ RAM_Fami_WRAM-RAM_Fami_Emu-$6000

rcStart:
		move.l	sp,(RAM_RcStack).l
		move.w	#$4E75,(RAM_EmuLoop).l	; rts
		if PRG_BANKED
		move.l	a1,d4			; the code of the bank at $8000
		subi.l	#PRG_IMAGES,d4
		lsr.l	#8,d4			; image / $8000 * 4
		lsr.l	#5,d4
		lea	(rcBankTables).l,a5
		move.l	(a5,d4.w),rcCurTable(a4)
		movea.l	a1,a0			; translated code reads PRG through a0
		adda.l	#$8000,a0
		else
		lea	(RAM_Fami_ROM+$8000).l,a0	; translated code reads PRG through a0
		endif
		move.w	#rcVecReset,d4		; falls into rcDispatch

; ----------------------------------------------------------------
; Jump to the code for a 6502 address
;
; d4.w - 6502 address
;
; Routines called with the 68000's jsr (see routine_body in
; tools/recomp6502.py) may leave through here, after an NMI or a
; computed jump; their return addresses are dropped.
; ----------------------------------------------------------------

rcDispatch:
		movea.l	(RAM_RcStack).l,sp
		cmpi.w	#$8000,d4
		bcs.s	.ram
		if PRG_BANKED
		andi.l	#$7FFF,d4		; offset in the image
		move.l	d4,d5
		lea	(rcTable).l,a5		; $C000-$FFFF: the fixed bank's code
		bclr	#14,d5
		bne.s	.fixed
		movea.l	rcCurTable(a4),a5	; $8000-$BFFF: the bank at $8000's
.fixed:
		lsl.l	#2,d5
		move.l	(a5,d5.l),d5
		beq.s	.interpret
		movea.l	d5,a5
		jmp	(a5)
.interpret:
		movea.l	a1,a0			; not translated: interpret it
		adda.l	d4,a0
		bra.s	rcInterp
		else
		andi.l	#rcPrgMask,d4
		lsl.l	#2,d4
		lea	(rcTable).l,a5
		move.l	(a5,d4.l),d5
		beq.s	.interpret
		movea.l	d5,a5
		jmp	(a5)
.interpret:
		lsr.l	#2,d4			; not translated: interpret it
		movea.l	a1,a0
		adda.l	d4,a0
		bra.s	rcInterp
		endif

	; code in RAM: a JMP written there (a common way to make a jump
	; table) goes straight to its target, anything else is interpreted
.ram:
		andi.w	#$7FF,d4
		cmpi.b	#$4C,(a2,d4.w)
		bne.s	.ram_code
		move.b	2(a2,d4.w),d5
		lsl.w	#8,d5
		move.b	1(a2,d4.w),d5
		move.w	d5,d4
		bra.s	rcDispatch
.ram_code:
		movea.l	a2,a0
		adda.w	d4,a0

; ----------------------------------------------------------------
; Interpret code that wasn't translated, one instruction at a time,
; until it reaches translated code again
;
; a0 - 6502 PC (in the PRG copy or RAM, like the interpreter)
; ----------------------------------------------------------------

rcInterp:
		move.w	#$4EF9,(RAM_EmuLoop).l	; handlers return to rcInterpStep
		move.l	#rcInterpStep,(RAM_EmuLoop+2).l

rcInterpStep:
		move.l	a0,d4			; 6502 address of the next instruction
		sub.l	a1,d4
		cmpi.l	#$8000,d4
		bcc.s	.in_ram
		ori.w	#$8000,d4
		tst.w	FamiMdVint(a4)
		bne.s	.vblank
		move.l	d4,d5			; translated?
		if PRG_BANKED
		lea	(rcTable).l,a5		; $C000-$FFFF: the fixed bank's code
		btst	#14,d5
		bne.s	.fixed
		movea.l	rcCurTable(a4),a5	; $8000-$BFFF: the bank at $8000's
.fixed:
		andi.l	#$3FFF,d5
		lsl.l	#2,d5
		else
		andi.l	#rcPrgMask,d5
		lsl.l	#2,d5
		lea	(rcTable).l,a5
		endif
		move.l	(a5,d5.l),d5
		bne.s	.translated
.step:
		clr.w	d4
		move.b	(a0)+,d4
		add.w	d4,d4
		lea	(mosCpu).l,a5
		move.w	(a5,d4.w),d6
		jmp	(a5,d6.w)

.in_ram:
		move.l	a0,d4
		sub.l	a2,d4
		tst.w	FamiMdVint(a4)
		beq.s	.step
.vblank:
		move.w	#$4E75,(RAM_EmuLoop).l	; rcNmi may enter translated code
		jsr	rcNmi
		bra.s	rcInterp		; no NMI taken: carry on

.translated:
		move.w	#$4E75,(RAM_EmuLoop).l
		if PRG_BANKED
		movea.l	a1,a0
		adda.l	#$8000,a0
		else
		lea	(RAM_Fami_ROM+$8000).l,a0
		endif
		movea.l	d5,a5
		jmp	(a5)

; ----------------------------------------------------------------
; NMI checks, on backward jumps
;
; d4.w - 6502 address the code continues at
; Returns if no NMI is taken, else jumps to the NMI handler.
;
; Each VBlank makes an NMI due (nmiCredit, MD_Vint). In a loop that
; waits for VBlank (one tools/recomp6502.py recognises) it's taken
; as soon as it's due: rcNmiWait (nmiWaitDue), or rcNmiIdle.
; Elsewhere (rcNmi, FamiMdVint) it comes at once, as on a NES, or,
; if the game took its last NMI waiting for it (nmiHold), when the
; game waits again, up to a frame later. A game whose frame needs a
; bit more than an MD frame then takes a bit more than one, instead
; of two: an NMI in the middle of its frame would make it wait for
; the next VBlank after finishing. NMIs keep VBlank's pace (music
; doesn't slow down): one a frame late (nmiCredit 2) comes wherever
; the game is, and the next ones come at once until the game takes
; one waiting again.
;
; rcNmiIdle is the check in a JMP-to-itself loop, where a game that
; runs in its NMI handler waits: each NMI taken there is a frame
; (FPS counter, emu/fps.asm).
; ----------------------------------------------------------------

rcNmiIdle:
		if FPS
		tst.w	cpuFamiVint(a4)
		bne.s	rcNmiWait
		tst.w	ppuNmiFlag(a4)
		beq.s	rcNmiWait
		addq.w	#1,fpsIdle(a4)
		endif
rcNmiWait:
		moveq	#1,d5			; (nmiHold, if it's taken)
		bra.s	rcNmiDue
rcNmi:
		moveq	#0,d5
rcNmiDue:
		clr.w	FamiMdVint(a4)
		clr.w	nmiWaitDue(a4)
		move.w	#$80,ppuStatus(a4)
		tst.w	cpuFamiVint(a4)		; already in the NMI handler: the
		bne.s	.late			; next NMI when it returns (rcRti)
		tst.w	ppuNmiFlag(a4)
		beq.s	.none
		move.w	d5,nmiHold(a4)
		subq.w	#1,nmiCredit(a4)	; (one for each VBlank)
		bpl.s	.take
		clr.w	nmiCredit(a4)
.take:
		addq.l	#4,sp			; not returning
		move.w	#1,cpuFamiVint(a4)
		jsr	ppuFrameStart
		swap	d3			; push PC
		move.w	d4,d6
		lsr.w	#8,d6
		move.b	d6,(a2,d3.w)
		subq.b	#1,d3
		move.b	d4,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		jsr	famiGetP		; push P, B clear
		andi.b	#$EF,d5
		swap	d3
		move.b	d5,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		move.w	#1,cpuModeIntDis(a4)
		move.w	#rcVecNmi,d4
		bra	rcDispatch
.late:
		move.w	#1,vbLate(a4)
		rts
.none:
		clr.w	nmiCredit(a4)		; NMIs off: none due
		rts

; ----------------------------------------------------------------
; RTI, after the 6502 code popped P and the PC (d4)
;
; A game whose frame outlasts an MD frame would otherwise wait for
; the VBlank after next: each frame would take two. Its next NMI
; comes as soon as the handler returns instead (vbLate: a VBlank
; came while it ran), or when the game next waits for it (one due).
; ----------------------------------------------------------------

rcRti:
		clr.w	cpuFamiVint(a4)
		tst.w	nmiCredit(a4)
		beq.s	.none_due
		move.w	#1,nmiWaitDue(a4)
		cmpi.w	#2,nmiCredit(a4)	; a frame late: wherever the game is
		bcc.s	.now
.none_due:
		tst.w	vbLate(a4)
		beq.s	.on_time
.now:
		clr.w	vbLate(a4)
		move.w	#1,FamiMdVint(a4)
		move.w	#1,nmiWaitDue(a4)
.on_time:
		bra	rcDispatch

; ----------------------------------------------------------------
; Read/write at a computed address
;
; d6.w - 6502 address
; d7 - value read / to write
; ----------------------------------------------------------------

rcRead16:
		cmpi.w	#$2000,d6
		bcc.s	.not_ram
		andi.w	#$7FF,d6
		move.b	(a2,d6.w),d7
		rts
.not_ram:
		tst.w	d6
		bpl.s	.io
		move.b	(a0,d6.w),d7		; a0 = PRG copy + $8000
		rts
.io:
		if PRG_BANKED
		cmpi.w	#$6000,d6		; PRG RAM (always there: md.asm)
		bcs.s	.regs
		lea	(RAM_Fami_WRAM-$6000).l,a5
		move.b	(a5,d6.w),d7
		rts
.regs:
		endif
		move.w	d6,d4
		andi.w	#$FF,d4
		lsr.w	#8,d6
		bra	addr_Read

rcWrite16:
		cmpi.w	#$2000,d6
		bcc.s	.not_ram
		andi.w	#$7FF,d6
		move.b	d7,(a2,d6.w)
		rts
.not_ram:
		if PRG_BANKED
		cmpi.w	#$6000,d6		; PRG RAM (always there: md.asm)
		bcs.s	.regs
		tst.w	d6
		bmi.s	.regs
		lea	(RAM_Fami_WRAM-$6000).l,a5
		move.b	d7,(a5,d6.w)
		rts
.regs:
		endif
		move.w	d6,d4
		andi.w	#$FF,d4
		lsr.w	#8,d6
		bra	addr_Write		; its handlers return through RAM_EmuLoop

; ----------------------------------------------------------------
; Read from a controller port: $4016/$4017, or $4016,X and the
; like, which games use to read either pad. Saves the trip through
; addr_Read to APU_Input_1/2.
;
; d4.w - 6502 address - $4016 (0: $4016, 1: $4017)
; d7 - value read
; ----------------------------------------------------------------

rcReadPad:
		cmpi.w	#1,d4
		bhi.s	.other
		add.w	d4,d4
		move.w	cpuInputData(a4,d4.w),d7
		andi.w	#1,d7
		lsr	cpuInputData(a4,d4.w)
		rts
.other:
		move.w	d4,d6
		addi.w	#$4016,d6
		if PRG_BANKED
		bra.w	rcRead16		; (past the PRG RAM code)
		else
		bra.s	rcRead16
		endif

; ----------------------------------------------------------------
; A delay loop: DEX or DEY, then BNE back to it, or two of them nested
; (tools/recomp6502.py)
;
; Games use these to time raster effects (Excitebike's scroll split,
; Balloon Trip's score bar). It takes no time here: the NES time it
; would take moves the game's frame clock (vNmi) on, so what comes
; after happens at the NES's line.
;
; d4.w - turns (0: 256)
; d5.w - NES cycles a turn
; d6.w - and cycles to add (-1: the last branch isn't taken)
; ----------------------------------------------------------------

rcDelay:
		andi.w	#$FF,d4
		bne.s	.turns
		move.w	#256,d4
.turns:
		mulu	d5,d4
		ext.l	d6
		add.l	d6,d4			; cycles
		move.l	d4,d5
		add.l	d4,d4
		add.l	d5,d4			; PPU dots: 3 a cycle
		moveq	#0,d5
		move.w	rcDelayDots(a4),d5	; with what was left over
		add.l	d5,d4
		divu	#341,d4			; lines, and dots left over
		move.l	d4,d5
		swap	d5
		move.w	d5,rcDelayDots(a4)
		andi.l	#$FFFF,d4
		divu	mdLines(a4),d4		; (whole frames don't change the line)
		swap	d4
		move.w	vNmi(a4),d5		; the frame began that much earlier
		sub.w	d4,d5
		bpl.s	.vnmi
		add.w	mdLines(a4),d5
.vnmi:
		move.w	d5,vNmi(a4)
		rts
