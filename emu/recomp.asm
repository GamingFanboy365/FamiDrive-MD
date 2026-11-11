; ====================================================================
; ----------------------------------------------------------------
; Recompiled code support (RECOMP=1)
;
; tools/recomp6502.py translates the game's 6502 code into 68000
; code (out/recomp.asm) that runs instead of the interpreter. It
; keeps the interpreter's registers (see emuLoop) and calls the
; same memory, PPU and APU handlers, which end with an rts in this
; build (emuNext); so do the interpreter's instructions' routines,
; which rcInterpStep calls in turn. (RAM_EmuLoop is an rts too.)
;
; Banked PRG (PRG_BANKED): each bank's code has its own rcTable,
; for $8000-$BFFF while it's at $8000 (rcCurTable, set by
; prgSwitch); the fixed bank's rcTable is for $C000-$FFFF.
; MMC3 in PRG mode 1 (PRG_MODE1): a bank's code at $A000 has an
; rcTable for $A000-$BFFF (rcCurTable, less $8000) and one at $C000
; for $C000-$DFFF (rcCurTableC), set by rcPrgSlot; the fixed code's
; is for $8000-$9FFF, then $E000-$FFFF. Translated code reads PRG
; through R7's frame (a1, a0 = a1+$8000), but at $C000-$DFFF
; through R6's (prgFrameC, rcFrameC = prgFrameC+$8000).
; Translated code reads and writes PRG RAM at rcWram+addr(a4).
; ----------------------------------------------------------------

rcWram		equ RAM_Fami_WRAM-RAM_Fami_Emu-$6000

rcStart:
		move.l	sp,(RAM_RcStack).l
		clr.w	rcNestPc(a4)		; no copy's NMI out (rcNmiIn)
		move.w	#$4E75,(RAM_EmuLoop).l	; rts
		lea	(RAM_RcRet).w,a5	; return caches: none kept (an RTS to
		move.w	#2*120-1,d5		; $0000 would find rcDispatch)
.ret_cache:
		clr.w	(a5)+
		move.l	#rcDispatch,(a5)+
		dbf	d5,.ret_cache
		if PRG_MODE1
		moveq	#7,d5			; the code of R7's bank at $A000 and
		move.l	a1,d6			; of R6's at $C000 (and rcFrameC)
		bsr.s	.slot
		moveq	#6,d5
		move.l	prgFrameC(a4),d6
		bsr.s	.slot
		movea.l	a1,a0			; translated code reads PRG through a0
		adda.l	#$8000,a0
		bra.s	.go
.slot:
		subi.l	#PRG_FRAMES,d6		; its bank: frame / 32 KB
		add.l	d6,d6
		swap	d6
		bra.w	rcPrgSlot
.go:
		elseif PRG_BANKED
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
		movea.l	(RAM_RcStack).w,sp
		if PRG_MODE1
		moveq	#0,d5
		move.w	d4,d5
		bpl.s	.ram			; below $8000
		lsl.w	#2,d5			; the offset in 8 KB, x 4 (and bit 15
		bcs.s	.c_e			; for $A000 and $E000); out went bit
		bmi.s	.a			; 14 (C) and bit 13 is bit 15 (N)
.fixed:
		lea	(rcTable).l,a5		; $8000-$9FFF, $E000-$FFFF: the fixed code
		bra.s	.look
.c_e:
		bmi.s	.fixed
		movea.l	rcCurTableC(a4),a5	; $C000-$DFFF: R6's bank's code
		bra.s	.look
.a:
		movea.l	rcCurTable(a4),a5	; $A000-$BFFF: R7's (less $8000)
.look:
		move.l	(a5,d5.l),d5
		beq.s	.interpret
		movea.l	d5,a5
		jmp	(a5)
.interpret:
		move.w	d4,d6			; not translated: interpret it, in its
		andi.w	#$7FFF,d6		; frame (prgPc)
		bsr.w	prgPc
		bra.w	rcInterp
		elseif PRG_BANKED
		moveq	#0,d5
		move.w	d4,d5
		bpl.s	.ram			; below $8000
		lsl.w	#2,d5			; the offset in a 16 KB bank, x 4
		bcs.s	.fixed			; (out went bit 14)
		movea.l	rcCurTable(a4),a5	; $8000-$BFFF: the bank at $8000's
		move.l	(a5,d5.l),d5
		beq.s	.interpret
		movea.l	d5,a5
		jmp	(a5)
.fixed:
		lea	(rcTable).l,a5		; $C000-$FFFF: the fixed bank's code
		move.l	(a5,d5.l),d5
		beq.s	.interpret
		movea.l	d5,a5
		jmp	(a5)
.interpret:
		andi.l	#$7FFF,d4		; not translated: interpret it, in
		movea.l	a1,a0			; the image
		adda.l	d4,a0
		bra.s	rcInterp
		else
		cmpi.w	#$8000,d4
		bcs.s	.ram
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
; until it reaches an entry of translated code (rcSafe): elsewhere
; the translated code may count on what the code before it left,
; such as the carry in the X flag.
;
; a0 - 6502 PC (in the PRG copy or RAM, like the interpreter)
; ----------------------------------------------------------------

rcInterp:					; (each instruction's routine is called,
rcInterpStep:					; and returns: emuNext)
		if PRG_MODE1
		move.l	a0,d4			; 6502 address of the next instruction:
		cmpi.l	#$400000,d4		; in PRG (not RAM), a0's low 15 bits
		bcc.s	.in_ram			; (its frame is 32 KB aligned)
		ori.w	#$8000,d4
		tst.w	FamiMdVint(a4)
		bne.s	.vblank
		moveq	#0,d5			; translated? (as rcDispatch)
		move.w	d4,d5
		lsl.w	#2,d5
		bcs.s	.c_e
		bmi.s	.a
.fixed:
		lea	(rcTable).l,a5
		bra.s	.look
.c_e:
		bmi.s	.fixed
		movea.l	rcCurTableC(a4),a5
		bra.s	.look
.a:
		movea.l	rcCurTable(a4),a5	; (less $8000: its rcSafe at $7FFC)
		move.l	(a5,d5.l),d6
		beq.s	.step
		movea.l	$7FFC(a5),a5
		bra.s	.safe
.look:
		else
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
		endif
		move.l	(a5,d5.l),d6		; translated,
		beq.s	.step
		movea.l	-4(a5),a5		; and an entry? (rcSafe: a bit for
.safe:						; each address, by its offset, set at
		move.w	d4,d5			; entries)
		if PRG_BANKED
		andi.w	#$3FFF,d5
		else
		andi.w	#rcPrgMask,d5
		endif
		lsr.w	#3,d5
		btst	d4,(a5,d5.w)
		bne.s	.translated
.step:
		clr.w	d4
		move.b	(a0)+,d4
		add.w	d4,d4
		lea	(mosCpu).l,a5
		move.w	(a5,d4.w),d6
		jsr	(a5,d6.w)
		bra.w	rcInterpStep

.in_ram:
		move.l	a0,d4
		sub.l	a2,d4
		tst.w	FamiMdVint(a4)
		beq.s	.step
.vblank:					; rcNmi may enter translated code
		move.w	rcNmiInterp(a4),-(sp)	; (and its RTI go on interpreting
		move.w	#1,rcNmiInterp(a4)	; here, rcRti; one the NMI handler
		move.l	a0,-(sp)		; is in keeps its own), which reads
		if PRG_BANKED			; PRG through a0, as .translated
		movea.l	a1,a0
		adda.l	#$8000,a0
		else
		lea	(RAM_Fami_ROM+$8000).l,a0
		endif
		jsr	rcNmi
		movea.l	(sp)+,a0		; no NMI taken: carry on
		move.w	(sp)+,rcNmiInterp(a4)
		bra.w	rcInterp

.translated:
		if PRG_BANKED
		movea.l	a1,a0
		adda.l	#$8000,a0
		else
		lea	(RAM_Fami_ROM+$8000).l,a0
		endif
		movea.l	d6,a5
		jmp	(a5)

; ----------------------------------------------------------------
; An RTS with a return cache (one tools/recomp6502.py can't guess the
; returns of): as rcDispatch, keeping the code it finds there for the
; next time, unless that can change: below $8000, or for an RTS in the
; fixed bank's code (rcDispatchCF), $8000-$BFFF, whose code goes by
; the bank there then. (A bank's RTS returns to its own code there.)
; A cache keeps the last two: an address and its code, twice; the new
; one goes first, the first second.
;
; d4.w - 6502 address
; a5 - its cache + 2: the first address before, its code at (a5)
; ----------------------------------------------------------------

		if PRG_MODE1
; MMC3 PRG mode 1: the fixed code's RTSs (rcDispatchCF) keep none
; to $A000-$DFFF, an $A000 bank's (rcDispatchCA) none to $C000-
; $DFFF, a $C000 bank's (rcDispatchCC) none to $A000-$BFFF.
rcDispatchCF:
		move.w	d4,d5			; (as rcDispatch: C bit 14, N bit 13)
		lsl.w	#2,d5
		bcs.s	.c_e
		bmi.w	rcDispatch		; $A000-$BFFF
		bra.s	rcDispatchC
.c_e:
		bpl.w	rcDispatch		; $C000-$DFFF
		bra.s	rcDispatchC
rcDispatchCA:
		move.w	d4,d5
		lsl.w	#2,d5
		bcc.s	rcDispatchC
		bpl.w	rcDispatch		; $C000-$DFFF
		bra.s	rcDispatchC
rcDispatchCC:
		move.w	d4,d5
		lsl.w	#2,d5
		bcs.s	rcDispatchC
		bmi.w	rcDispatch		; $A000-$BFFF
		else
rcDispatchCF:
		if PRG_BANKED
		btst	#14,d4
		beq.w	rcDispatch
		endif
		endif
rcDispatchC:
		tst.w	d4
		bpl.w	rcDispatch
		move.l	a5,d6
		movea.l	(RAM_RcStack).w,sp
		moveq	#0,d5
		move.w	d4,d5
		if PRG_MODE1
		lsl.w	#2,d5			; (as rcDispatch)
		bcs.s	.c_e
		bmi.s	.a
.fixed:
		lea	(rcTable).l,a5
		bra.s	.look
.c_e:
		bmi.s	.fixed
		movea.l	rcCurTableC(a4),a5
		bra.s	.look
.a:
		movea.l	rcCurTable(a4),a5
.look:
		elseif PRG_BANKED
		lsl.w	#2,d5
		bcs.s	.fixed
		movea.l	rcCurTable(a4),a5
		bra.s	.look
.fixed:
		lea	(rcTable).l,a5
.look:
		else
		andi.w	#rcPrgMask,d5
		lsl.l	#2,d5
		lea	(rcTable).l,a5
		endif
		move.l	(a5,d5.l),d5
		beq.w	rcDispatch		; not translated
		movea.l	d6,a5
		move.w	-2(a5),4(a5)
		move.l	(a5),6(a5)
		move.w	d4,-2(a5)
		move.l	d5,(a5)
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
;
; In a routine's copy, called with the 68000's jsr, the checks are
; rcNmiIn, rcNmiWaitIn and rcNmiIdleIn (Gen.nmi_check): an NMI taken
; there comes back to the copy when its handler's RTI (or that of the
; IRQ rcRti takes right after it) goes on where the check was, at the
; same 6502 stack (rcNestPc), so the copy's caller needn't have pushed
; the 6502 return address. a5 is kept (a loop's fast copy reads
; through it), and rcDispatch in the handlers keeps the copy's 68000
; stack (RAM_RcStack). A handler that goes on anywhere else leaves the
; copy behind, as an NMI taken outside one does: the next NMI forgets
; it.
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
		bra.s	rcNmiTop
rcNmi:
		moveq	#0,d5
rcNmiTop:
		moveq	#0,d7			; (taken: not returning)
		bra.s	rcNmiDue

rcNmiIdleIn:
		if FPS
		tst.w	cpuFamiVint(a4)
		bne.s	rcNmiWaitIn
		tst.w	ppuNmiFlag(a4)
		beq.s	rcNmiWaitIn
		addq.w	#1,fpsIdle(a4)
		endif
rcNmiWaitIn:
		moveq	#1,d5
		moveq	#1,d7			; (taken: back to the copy)
		bra.s	rcNmiDue
rcNmiIn:
		moveq	#0,d5
		moveq	#1,d7
rcNmiDue:
		clr.w	FamiMdVint(a4)
		clr.w	nmiWaitDue(a4)
		move.w	#$80,ppuStatus(a4)
		tst.w	cpuFamiVint(a4)		; already in the NMI handler: the
		bne.w	.late			; next NMI when it returns (rcRti)
		tst.w	ppuNmiFlag(a4)
		beq.w	.none
		move.w	d5,nmiHold(a4)
		subq.w	#1,nmiCredit(a4)	; (one for each VBlank)
		bpl.s	.take
		clr.w	nmiCredit(a4)
.take:
		tst.w	rcNestPc(a4)		; a copy's NMI whose handler went on
		beq.s	.fresh			; elsewhere: what rcDispatch goes
		move.l	a5,d6			; back to as it was before it
		movea.l	(RAM_RcStack).w,a5
		move.l	(a5),(RAM_RcStack).w
		movea.l	d6,a5
		clr.w	rcNestPc(a4)
.fresh:
		tst.w	d7
		bne.s	.nest
		addq.l	#4,sp			; not returning
		bra.s	.go
.nest:
		move.l	a5,-(sp)		; a routine's copy: kept, with a5,
		move.l	(RAM_RcStack).w,-(sp)	; under where rcDispatch goes back
		move.l	sp,(RAM_RcStack).w	; to (and that, for rcRti)
		move.w	d4,rcNestPc(a4)		; and where the RTI that comes back
		move.l	d3,d6			; to it goes on
		swap	d6
		move.w	d6,rcNestSp(a4)
.go:
		move.w	#1,cpuFamiVint(a4)
		if MMC3_IRQ
		move.w	cpuInIrq(a4),irqNmiSave(a4)	; (the NMI handler's writes are above the split)
		clr.w	cpuInIrq(a4)
		endif
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
		jmp	(rcVecNmiGo).l		; (its code, recomp6502.py)
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
		if MMC3_IRQ
		tst.w	cpuFamiVint(a4)		; the IRQ handler's (MMC3_IRQ): what's
		bne.s	.nmi			; below its line, as it set it
		tst.w	cpuInIrq(a4)
		beq.s	.resume
		clr.w	cpuInIrq(a4)
		jsr	splitDone
		move.w	irqInterp(a4),rcNmiInterp(a4)	; (on as the NMI handler's RTI went)
		bra.s	.resume
.nmi:
		endif
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
		if MMC3_IRQ
		move.w	irqNmiSave(a4),cpuInIrq(a4)	; (one that came in the IRQ handler
		bne.s	.resume				; goes back to it) MMC3's IRQ, as
.irq_due:						; irqDue takes it (emu/cpu.asm)
		tst.w	irqOn(a4)
		beq.s	.resume
		tst.w	ppuMaskOn(a4)
		beq.s	.resume
		tst.w	cpuModeIntDis(a4)
		beq.s	rcIrq
.resume:
		endif
		tst.w	rcNestPc(a4)		; where a routine's copy took the NMI
		beq.s	.dispatch		; (rcNmiIn), at the same 6502 stack:
		cmp.w	rcNestPc(a4),d4		; back into the copy
		bne.s	.dispatch
		move.l	d3,d6
		swap	d6
		cmp.w	rcNestSp(a4),d6
		bne.s	.dispatch
		clr.w	rcNestPc(a4)
		movea.l	(RAM_RcStack).w,sp
		move.l	(sp)+,(RAM_RcStack).w
		movea.l	(sp)+,a5
		rts
.dispatch:
		tst.w	rcNmiInterp(a4)		; taken while interpreting (rcInterpStep):
		beq.w	rcDispatch		; go on interpreting there, as the code
		clr.w	rcNmiInterp(a4)		; there may be translated but not an
		tst.w	d4			; entry
		bpl.w	rcDispatch		; (in RAM: rcDispatch interprets it)
		if PRG_MODE1
		move.w	d4,d6
		andi.w	#$7FFF,d6
		bsr.w	prgPc
		elseif PRG_BANKED
		andi.l	#$7FFF,d4
		movea.l	a1,a0
		adda.l	d4,a0
		else
		andi.l	#rcPrgMask,d4
		movea.l	a1,a0
		adda.l	d4,a0
		endif
		bra.w	rcInterp

		if MMC3_IRQ
; ----------------------------------------------------------------
; MMC3's scanline IRQ (MMC3_IRQ), as irqDue and irqTake take it (emu/
; cpu.asm): from rcRti, or where translated code clears the I flag
; with CLI (rcIrqCli). Its RTI goes on at d4, where the code would
; have, and interprets there if it would have (irqInterp)
; ----------------------------------------------------------------

rcIrqCli:
		tst.w	ppuMaskOn(a4)
		beq.s	.no
		tst.w	cpuModeIntDis(a4)
		bne.s	.no
		tst.w	cpuInIrq(a4)
		bne.s	.no
		tst.w	cpuFamiVint(a4)
		bne.s	.no
		addq.l	#4,sp			; taken: not returning
		bra.s	rcIrq
.no:
		rts

rcIrq:
		move.w	rcNmiInterp(a4),irqInterp(a4)
		clr.w	rcNmiInterp(a4)
		swap	d3			; push the PC
		move.w	d4,d6
		lsr.w	#8,d6
		move.b	d6,(a2,d3.w)
		subq.b	#1,d3
		move.b	d4,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		jsr	famiGetP		; and P, B clear
		andi.b	#$EF,d5
		swap	d3
		move.b	d5,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		move.w	#1,cpuModeIntDis(a4)
		jsr	splitBegin
		jmp	(rcVecIrqGo).l		; (its code, recomp6502.py)
		endif

; ----------------------------------------------------------------
; Read/write at a computed address
;
; d6.w - 6502 address
; d7 - value read / to write
;
; rcRead16P: rcRead16 for a (zp),Y read between two $2006 stores
; that translated code makes at once (recomp6502.py, Gen.pairs_2006).
; The first's byte is still to be written: the low byte of the word on
; the stack where the read's code calls this, unless bit 15 says it
; was. A PPU register sees it written first.
; ----------------------------------------------------------------

rcRead16P:
		cmpi.w	#$2000,d6
		bcs.w	rcRead16
		cmpi.w	#$4000,d6
		bcc.w	rcRead16
		tst.w	4(sp)
		bmi.w	rcRead16
		bset	#7,4(sp)		; (the second store writes alone)
		move.b	5(sp),d7
		move.w	d6,-(sp)
		jsr	wrPPU_Addr
		move.w	(sp)+,d6

rcRead16:
		cmpi.w	#$2000,d6
		bcc.s	.not_ram
		andi.w	#$7FF,d6
		move.b	(a2,d6.w),d7
		rts
.not_ram:
		tst.w	d6
		bpl.s	.io
		if PRG_MODE1
		cmpi.w	#$C000,d6		; $C000-$DFFF: R6's bank, through
		bcs.s	.prg			; rcFrameC
		cmpi.w	#$E000,d6
		bcc.s	.prg
		movea.l	rcFrameC(a4),a5
		move.b	(a5,d6.w),d7
		rts
.prg:
		endif
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
		bra	addr_Write		; (its handlers return: emuNext)

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
; Each byte with its bits the other way round: a pad's 8 buttons as a
; game's 8 reads put them together, the first in bit 7 (a loop that
; reads the pads, tools/recomp6502.py: Gen.emit_pads)
; ----------------------------------------------------------------

rcPadBits:
		dc.b $00,$80,$40,$C0,$20,$A0,$60,$E0,$10,$90,$50,$D0,$30,$B0,$70,$F0
		dc.b $08,$88,$48,$C8,$28,$A8,$68,$E8,$18,$98,$58,$D8,$38,$B8,$78,$F8
		dc.b $04,$84,$44,$C4,$24,$A4,$64,$E4,$14,$94,$54,$D4,$34,$B4,$74,$F4
		dc.b $0C,$8C,$4C,$CC,$2C,$AC,$6C,$EC,$1C,$9C,$5C,$DC,$3C,$BC,$7C,$FC
		dc.b $02,$82,$42,$C2,$22,$A2,$62,$E2,$12,$92,$52,$D2,$32,$B2,$72,$F2
		dc.b $0A,$8A,$4A,$CA,$2A,$AA,$6A,$EA,$1A,$9A,$5A,$DA,$3A,$BA,$7A,$FA
		dc.b $06,$86,$46,$C6,$26,$A6,$66,$E6,$16,$96,$56,$D6,$36,$B6,$76,$F6
		dc.b $0E,$8E,$4E,$CE,$2E,$AE,$6E,$EE,$1E,$9E,$5E,$DE,$3E,$BE,$7E,$FE
		dc.b $01,$81,$41,$C1,$21,$A1,$61,$E1,$11,$91,$51,$D1,$31,$B1,$71,$F1
		dc.b $09,$89,$49,$C9,$29,$A9,$69,$E9,$19,$99,$59,$D9,$39,$B9,$79,$F9
		dc.b $05,$85,$45,$C5,$25,$A5,$65,$E5,$15,$95,$55,$D5,$35,$B5,$75,$F5
		dc.b $0D,$8D,$4D,$CD,$2D,$AD,$6D,$ED,$1D,$9D,$5D,$DD,$3D,$BD,$7D,$FD
		dc.b $03,$83,$43,$C3,$23,$A3,$63,$E3,$13,$93,$53,$D3,$33,$B3,$73,$F3
		dc.b $0B,$8B,$4B,$CB,$2B,$AB,$6B,$EB,$1B,$9B,$5B,$DB,$3B,$BB,$7B,$FB
		dc.b $07,$87,$47,$C7,$27,$A7,$67,$E7,$17,$97,$57,$D7,$37,$B7,$77,$F7
		dc.b $0F,$8F,$4F,$CF,$2F,$AF,$6F,$EF,$1F,$9F,$5F,$DF,$3F,$BF,$7F,$FF

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

		if PRG_MODE1
; ----------------------------------------------------------------
; MMC3 PRG mode 1: R6 or R7 picked a bank (mmc3Prg1, rcStart): the
; code of that bank at $C000 or at $A000 (rcCurTableC, rcCurTable)
; and the copies of its routines other code calls (rcCurCallC,
; rcCurCallA: tools/recomp6502.py, Gen.dyn_call), and for R6 rcFrameC.
; Each bank's record (rcBankRecsC, rcBankRecsA: tools/recomp6502.py,
; mode1) holds those and its frame (prgFrameC; a1 and cpuPrgImg) and
; the frame +$8000 (rcFrameC; a0): translated code that switches a
; bank takes them all from it (Gen.prg1_switch).
;
; d5.w - 6 or 7
; d6.w - the bank (kept)
; ----------------------------------------------------------------

rcPrgSlot:
		move.w	d6,d4
		lsl.w	#4,d4			; (16 bytes a bank)
		cmpi.w	#7,d5
		beq.s	.r7
		lea	(rcBankRecsC).l,a5
		adda.w	d4,a5
		move.l	(a5)+,rcCurTableC(a4)
		move.l	(a5)+,rcCurCallC(a4)
		move.l	4(a5),rcFrameC(a4)
		rts
.r7:
		lea	(rcBankRecsA).l,a5
		adda.w	d4,a5
		move.l	(a5)+,rcCurTable(a4)
		move.l	(a5),rcCurCallA(a4)
		rts
		endif
