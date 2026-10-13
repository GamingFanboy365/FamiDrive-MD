; ====================================================================
; ----------------------------------------------------------------
; Recompiled code support (RECOMP=1)
;
; tools/recomp6502.py translates the game's 6502 code into 68000
; code (out/recomp.asm) that runs instead of the interpreter. It
; keeps the interpreter's registers (see emuLoop) and calls the
; same memory, PPU and APU handlers. Those end with
; "jmp (RAM_EmuLoop).l", so rcStart turns RAM_EmuLoop into an rts.
; ----------------------------------------------------------------

rcStart:
		move.l	sp,(RAM_RcStack).l
		move.w	#$4E75,(RAM_EmuLoop).l	; rts
		lea	(RAM_Fami_ROM+$8000).l,a0	; translated code reads PRG through a0
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
		andi.l	#rcPrgMask,d5
		lsl.l	#2,d5
		lea	(rcTable).l,a5
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
		lea	(RAM_Fami_ROM+$8000).l,a0
		movea.l	d5,a5
		jmp	(a5)

; ----------------------------------------------------------------
; VBlank check, called on backward jumps when FamiMdVint is set
;
; d4.w - 6502 address the code continues at
; Returns if no NMI is taken, else jumps to the NMI handler.
;
; rcNmiIdle is the check in a JMP-to-itself loop, where a game that
; runs in its NMI handler waits: each NMI taken there is a frame
; (FPS counter, emu/fps.asm).
; ----------------------------------------------------------------

rcNmiIdle:
		if FPS
		tst.w	cpuFamiVint(a4)
		bne.s	rcNmi
		tst.w	ppuNmiFlag(a4)
		beq.s	rcNmi
		addq.w	#1,fpsIdle(a4)
		endif
rcNmi:
		clr.w	FamiMdVint(a4)
		move.w	#$80,ppuStatus(a4)
		tst.w	cpuFamiVint(a4)		; already in the NMI handler
		bne.s	.none
		tst.w	ppuNmiFlag(a4)
		beq.s	.none
		addq.l	#4,sp			; not returning
		move.w	#1,cpuFamiVint(a4)
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
.none:
		rts

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
		move.w	d6,d4
		andi.w	#$FF,d4
		lsr.w	#8,d6
		bra	addr_Write		; its handlers return through RAM_EmuLoop
