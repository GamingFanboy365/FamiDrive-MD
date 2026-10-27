; ====================================================================
; ----------------------------------------------------------------
; PPU
;
; PPU register writes, nametable/palette drawing and CHR
; conversion to MD tiles. Register reads are in memory.asm.
; ----------------------------------------------------------------

; ----------------------------------------------------------------
; PPU register writes ($2000-$2007)
; ----------------------------------------------------------------

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
		
	; Pattern tables: BG (bit 7 here), 8x8 sprites (bit 6). The sprite
	; tile sets hold both tables (Nemul_LoadChr), so only a new BG
	; table is converted again
		move.b	d7,d6
		andi.w	#$C0,d6
		move.w	ppuChrBank(a4),d5
		move.w	d6,ppuChrBank(a4)
		eor.b	d6,d5
		bpl.s	.no_reload
		bsr.w	chrLoadBg
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

	; Bit 0 is bit 8 of the X scroll (ppuXChanged)
		move.w	#$2700,sr
		move.w	ppuTX(a4),d4
		andi.w	#$FF,d4
		btst	#6,d7
		beq.s	.nt_x0
		ori.w	#$100,d4
.nt_x0:
		move.w	d4,ppuTX(a4)
		moveq	#1,d6
		bsr.w	ppuXChanged
		move.w	#$2000,sr
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $2001 - PPU MASK
; ----------------------------------------------------------------

wrPPU_Mask:
		move.w	d7,d6
		andi.w	#$18,d6			; background or sprites shown
		move.w	d6,ppuMaskOn(a4)
	; The VDP side waits for VBlank: a game running slower than the NES
	; can write $2001 (rendering off for its VRAM updates) mid-screen,
	; which on the MD would blank the lines being drawn.
		move.b	d7,d6
		ori.w	#$8000,d6
		move.w	d6,ppuMaskNew(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; ppuMaskApply: set the VDP for the last $2001 write (from VBlank)
; ----------------------------------------------------------------

ppuMaskApply:
		move.w	ppuMaskNew(a4),d7
		bpl.s	.none
		clr.w	ppuMaskNew(a4)

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
.none:
		rts

; ----------------------------------------------------------------
; $2005 - PPU SCROLL
; -----------------------------------------------------------------

wrPPU_Scroll:
		move.w	d7,d4
		andi.w	#$FF,d4
		move.w	ppuNTblBase(a4),d6
		eori.w	#1,ppuAddrLatch(a4)
		beq.s	.vertical
		move.w	#$2700,sr
		andi.w	#$100,ppuTX(a4)		; keep the nametable bit
		or.w	d4,ppuTX(a4)
		moveq	#1,d6
		bsr	ppuXChanged
		move.w	#$2000,sr
		jmp	(RAM_EmuLoop).l

.vertical:
		move.w	#1,ppuScrollSet(a4)
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
; The horizontal scroll (ppuTX) changed
;
; Games keep a status bar still by changing the scroll partway down
; the screen, after waiting for sprite 0 hit, or after a delay loop
; once their VBlank work and its scroll are done (Balloon Fight's
; Balloon Trip). Until the game has polled $2002 (ppuSp0State) or set
; both bytes of $2005 this frame, a change sets the scroll from the
; top: whatever runs before is the NES's VBlank work, however long it
; takes here (VRAM addresses written to $2006 pass through the scroll
; on the NES too, and games set it again after). After that, a
; change starts a split at the line the NES would be on (ppuLine),
; unless it comes from $2006. Changes within 4 lines (the X, then
; $2000's nametable bit) make one split. hsBuild turns them into
; the MD's line scroll table.
;
; d6.w - 0: don't start a split
; Uses d4-d6, a5. Call with interrupts off.
; ----------------------------------------------------------------

ppuXChanged:
		move.w	ppuTX(a4),d4
		neg.w	d4
		cmp.w	vdpScrlX(a4),d4
		bne.s	.changed
.same:
		rts
.changed:
		tst.w	ppuSp0State(a4)		; the game polled $2002 this frame,
		bne.s	.split_ok
		tst.w	ppuScrollSet(a4)	; or set the whole scroll already
		beq.w	.top			; (both $2005 bytes): else from the top
.split_ok:
		tst.w	ppuMaskOn(a4)
		beq.w	.top
		tst.w	d6			; $2006 mid-screen: leave the scroll
		beq.s	.same			; (games set it right after)
		movem.l	d0/d5,-(sp)
		bsr.w	ppuLine
		tst.w	d5			; past the bottom (a very slow frame)
		bmi.s	.set
		move.w	d4,vdpScrlX(a4)
		move.w	d4,vdpScrlX+2(a4)
		subq.w	#8,d5			; NES line L is MD line L-8
		bpl.s	.line_ok
		moveq	#0,d5
.line_ok:
		lea	hsCur(a4),a5
		move.w	hsCurN(a4),d0
		beq.s	.append
		lsl.w	#2,d0
		move.w	-4(a5,d0.w),d6		; the last split's line
		addq.w	#4,d6
		cmp.w	d6,d5
		bhi.s	.after
		move.w	d4,-2(a5,d0.w)		; same moment: same split
		move.w	hsTopCur(a4),d6		; back to the scroll before it: no split
		cmpi.w	#4,d0
		beq.s	.before
		move.w	-6(a5,d0.w),d6
.before:
		cmp.w	d4,d6
		bne.s	.done
		subq.w	#1,hsCurN(a4)
		bra.s	.done
.after:
		lsr.w	#2,d0
.append:
		cmpi.w	#8,d0
		bcc.s	.done
		lsl.w	#2,d0
		move.w	d5,(a5,d0.w)
		move.w	d4,2(a5,d0.w)
		addq.w	#1,hsCurN(a4)
		bra.s	.done
.set:
		move.w	d4,vdpScrlX(a4)
		move.w	d4,vdpScrlX+2(a4)
.done:
		movem.l	(sp)+,d0/d5
		rts
.top:
		move.w	d4,hsTopCur(a4)
		move.w	d4,hsTopCur+2(a4)
		move.w	d4,vdpScrlX(a4)
		move.w	d4,vdpScrlX+2(a4)
		rts

; ----------------------------------------------------------------
; Time within the game's frame
;
; FamiDrive runs some games slower than the NES, so a game frame can
; outlast an MD frame. Raster effects (sprite 0 hit, scroll splits)
; are timed from when the game's frame began, at its NMI: the NES
; line the game would be on, if each MD line is one NES line.
;
; ppuClock: d5.w = MD line, counted from the start of VBlank (0 to
; mdLines-1; on a Mega Drive the V counter repeats a few values in
; VBlank, which count from their first time)
; ppuLine: d5.w = NES line now (negative: still in VBlank), from
; the lines since ppuFrameStart; 20 VBlank lines follow the NMI, and
; a frame that outlasts the MD's goes round again
; Call with interrupts off.
; ----------------------------------------------------------------

ppuClock:
		moveq	#0,d5
		move.b	8(a6),d5		; V counter
.read:
		cmp.b	8(a6),d5		; the same again? AtGames' VDP can return a
		beq.s	.stable			; mix of the old and new count when it reads
		move.b	8(a6),d5		; it as it changes (7F, 81, 80)
		bra.s	.read
.stable:
		tst.w	vOddLine(a4)		; a console whose V counter reads odd
		bpl.s	.odd			; values in VBlank (ppuMeasureLines)?
.table:
		add.w	d5,d5			; lines since the MD's VBlank began
		addi.w	#vLineTbl,d5		; (ppuMeasureLines)
		move.w	(a4,d5.w),d5
		rts
.odd:
		cmpi.b	#$10,d5			; a line of the screen with the VBlank
		bcs.s	.table			; flag on: one of VBlank's last lines
		cmpi.b	#$D0,d5			; (AtGames: $7E, $7F)
		bcc.s	.table
		btst	#3,5(a6)
		beq.s	.table
		move.w	vOddLine(a4),d5
		rts

ppuLine:
		bsr.w	ppuClock
		sub.w	vNmi(a4),d5		; lines since, less whole frames: the
		bpl.s	.ahead			; NES keeps drawing frames meanwhile
		add.w	mdLines(a4),d5
.ahead:
		subi.w	#21,d5			; pre-render line: NES line 0 starts after it
		rts

; ----------------------------------------------------------------
; At startup: the lines the console draws a frame (mdLines) and the
; line each V counter value means (vLineTbl), for ppuClock. A Mega
; Drive's are known; a clone's are measured (vlMeasure): an AtGames
; handheld draws 246.
;
; a6 - VDP ports. Leaves the display off with VBlank interrupts on,
; as Fami_InitVideo did.
; ----------------------------------------------------------------

ppuMeasureLines:
		movem.l	d0-d7/a0-a5,-(sp)
		lea	(RAM_Fami_Emu).l,a4
		move.w	#$8144,4(a6)		; display on (all black), no VBlank interrupts
		move.w	#$8A63,4(a6)		; line interrupts every 100 lines
		move.w	#$8014,4(a6)		; on
		move.w	#$2300,sr
		lea	vLineTbl(a4),a0
		lea	(RAM_HintCount).w,a1
		jsr	vlMeasure
		move.w	d2,vOddLine(a4)		; odd V values in VBlank: their line
		move.w	#$2700,sr
		move.w	#$8004,4(a6)		; line interrupts off
		move.w	#$8ADF,4(a6)
		move.w	#$8124,4(a6)
		cmpi.w	#200,d0			; none came, or nothing like a frame:
		bcs.s	.mega_drive		; as on a Mega Drive
		cmpi.w	#320,d0
		bhi.s	.mega_drive
		tst.w	d2			; odd V values in VBlank: a clone
		bpl.s	.clone
		move.w	d0,d1
		subi.w	#262-2,d1
		cmpi.w	#4,d1			; 262 give or take 2: a Mega Drive
		bls.s	.mega_drive
.clone:
		move.w	d0,mdLines(a4)		; a clone: as measured
		bra.s	.done
.mega_drive:
		move.w	#262,mdLines(a4)
		move.w	#-1,vOddLine(a4)
		lea	vLineTbl(a4),a0		; $E0 on: lines since VBlank began,
		moveq	#0,d1			; the rest after the 38 lines of VBlank
.line:
		move.w	d1,d0
		subi.w	#$E0,d0
		bcc.s	.vblank
		addi.w	#262,d0
.vblank:
		move.w	d0,(a0)+
		addq.w	#1,d1
		cmpi.w	#256,d1
		bne.s	.line
.done:
		movem.l	(sp)+,d0-d7/a0-a5
		rts

; ----------------------------------------------------------------
; The game's frame begins (NMI taken, or MD VBlank with NMIs off)
;
; The splits of the frame that just ended become hsDone; the new one
; starts from the scroll in effect now.
; ----------------------------------------------------------------

ppuFrameStart:
		movem.l	d0/d5/a0-a1,-(sp)
		move.w	sr,-(sp)
		move.w	#$2700,sr
		bsr.w	ppuClock
		move.w	d5,vNmi(a4)
		addq.w	#1,hsFrame(a4)
		move.w	sprLatest(a4),d0	; the frame before is done: its sprites
		move.w	d0,sprDone(a4)		; and vertical scroll (MD_Vint), and
		eori.w	#sprTable2,d0		; this frame's sprites go in the other
		move.w	d0,sprWrite(a4)		; table
		move.l	vdpScrlY(a4),vsDone(a4)
		lea	hsTopCur(a4),a0
		lea	hsTopDone(a4),a1
		move.l	(a0)+,(a1)+		; top
		move.w	(a0)+,d0		; splits
		move.w	d0,(a1)+
		moveq	#8-1,d0
.copy:
		move.l	(a0)+,(a1)+
		dbf	d0,.copy
		move.l	vdpScrlX(a4),hsTopCur(a4)
		clr.w	hsCurN(a4)
		clr.w	ppuSp0State(a4)
		clr.l	ppuRdSite(a4)
		clr.w	ppuScrollSet(a4)
		move.w	(sp)+,sr
		movem.l	(sp)+,d0/d5/a0-a1
		rts

; ----------------------------------------------------------------
; Which game frame MD_Vint shows: the current one once its scroll from
; the top is set (its NMI handler returned, or the game saw sprite 0
; hit: the screen is being drawn, wrote the split that follows the hit,
; and is well past its last split) and it has as many splits as the
; previous frame; else the previous frame (a slow game frame spans MD
; frames). Frames shown go up one at a time when they can: if the game
; has begun two or more since the one shown last, the previous one
; rather than a skip (which a repeat would follow when the game's
; frames end around VBlank: judder). Its sprites and vertical scroll go
; with it: a game uploads its sprites before it sets the scroll, so
; showing them with the previous frame's would put them a frame ahead.
;
; hsShowDone: 0 - the current frame, 1 - the previous one
; ----------------------------------------------------------------

hsChoose:
		move.w	hsFrame(a4),d0		; frames since the one shown last:
		sub.w	hsShownF(a4),d0		; none, show it again; two or more,
		beq.s	.this_frame		; the one before this (a step of
		subq.w	#1,d0			; one, not a skip and a repeat)
		bne.s	.done_frame
		tst.w	cpuFamiVint(a4)		; NMI handler returned
		beq.s	.top_set
		cmpi.w	#2,ppuSp0State(a4)	; or past sprite 0 hit, with the
		bne.s	.done_frame		; split that follows it, and well
		move.w	hsCurN(a4),d0		; past its last split: one split
		cmp.w	hsHitN(a4),d0		; can take writes a few lines
		beq.s	.done_frame		; apart (Excitebike: $2000, then
		tst.w	d0			; $2005)
		beq.s	.top_set
		lsl.w	#2,d0
		lea	hsCur(a4),a0
		move.w	-4(a0,d0.w),d1		; (an MD line: NES line - 8)
		addi.w	#8+8,d1
		bsr.w	ppuLine
		cmp.w	d1,d5
		blt.s	.done_frame
.top_set:
		move.w	hsCurN(a4),d0
		cmp.w	hsDoneN(a4),d0
		bcc.s	.this_frame
.done_frame:
		move.w	#1,hsShowDone(a4)
		move.w	hsFrame(a4),d0
		subq.w	#1,d0
		move.w	d0,hsShownF(a4)
		rts
.this_frame:
		clr.w	hsShowDone(a4)
		move.w	hsFrame(a4),hsShownF(a4)
		rts

; ----------------------------------------------------------------
; Set the MD's horizontal scroll, once per frame from MD_Vint (in
; VBlank), for the game frame hsChoose picked.
; Without splits it is one scroll for the screen, else the line scroll
; table at $B800 is written line by line. Nothing is written while the
; scroll stays the same (hsShown).
;
; a6 - VDP ports, auto-increment 2
; ----------------------------------------------------------------

hsApply:
		lea	hsTopCur(a4),a1
		tst.w	hsShowDone(a4)
		beq.s	.use
		lea	hsTopDone(a4),a1
.use:
	; the same as last time?
		lea	hsShown(a4),a0
		move.l	(a1)+,d1		; scroll from the top
		move.w	(a1)+,d0		; splits
		cmp.l	(a0)+,d1
		bne.s	.changed
		cmp.w	(a0)+,d0
		bne.s	.changed
		move.w	d0,d2
		beq.s	.same
		subq.w	#1,d2
		movea.l	a1,a2
.compare:
		cmpm.l	(a2)+,(a0)+
		bne.s	.changed
		dbf	d2,.compare
.same:
		tst.w	hsShownOk(a4)
		bne.s	.done
.changed:
		lea	hsShown(a4),a0		; keep it for next time
		move.l	d1,(a0)+
		move.w	d0,(a0)+
		move.w	d0,d2
		beq.s	.copied
		subq.w	#1,d2
		movea.l	a1,a2
.copy:
		move.l	(a2)+,(a0)+
		dbf	d2,.copy
.copied:
		move.w	#1,hsShownOk(a4)
		tst.w	d0
		bne.s	.lines
		move.w	#$8B00,4(a6)		; one scroll for the screen
		move.l	#$78000002,4(a6)	; HScroll table at $B800
		move.l	d1,(a6)
.done:
		rts
.lines:
		move.w	#$8B03,4(a6)		; per line
		move.l	#$78000002,4(a6)
		moveq	#0,d2			; line
		bra.s	.next
.split:
		move.w	(a1)+,d3		; split line
		move.w	(a1)+,d4		; and its scroll
		bsr.w	.fill_to
		move.w	d4,d1
		swap	d1
		move.w	d4,d1
.next:
		dbf	d0,.split
		move.w	#224,d3
		bsr.w	.fill_to
		rts

.fill_to:				; lines d2 to d3 (to 224 at most)
		cmpi.w	#224,d3
		bls.s	.to_ok
		move.w	#224,d3
.to_ok:
		move.w	d3,d5
		sub.w	d2,d5
		bgt.s	.fill_go
		rts
.fill_go:
		move.w	d3,d2
		add.w	d5,d5			; 2 bytes per move
		neg.w	d5
		lea	.fill_end(pc),a2
		jmp	(a2,d5.w)
		rept 224
		move.l	d1,(a6)
		endm
.fill_end:
		rts

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

	; It shares the PPU's t register with the scroll: the high byte
	; sets the nametable bits, the low byte coarse X (ppuXChanged)
		move.w	#$2700,sr
		move.w	ppuTX(a4),d6
		tst.w	d4
		bne.s	.low
		andi.w	#$FF,d6
		btst	#2,d7
		beq.s	.set
		ori.w	#$100,d6
		bra.s	.set
.low:
		andi.w	#$107,d6		; nametable, fine X
		move.w	d7,d4
		andi.w	#$1F,d4
		lsl.w	#3,d4
		or.w	d4,d6
.set:
		move.w	d6,ppuTX(a4)
		moveq	#0,d6			; never a split by itself
		bsr	ppuXChanged
		clr.l	ppuRdSite(a4)		; a $2002 read before this one was for
					; the latch, not a wait for sprite 0
		move.w	#$2000,sr
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

wrPPU_Data:
		move.w	ppuAddrBase(a4),d4
		move.w	ppuAddrIncr(a4),d6
		add.w	d6,ppuAddrBase(a4)
		andi.w	#$3FFF,d4
		cmpi.w	#$2000,d4
		bcs.w	ppuChrRamWrite
		cmpi.w	#$3F00,d4
		bcc.s	.palette
		cmp.b	(a3,d4.w),d7		; unchanged: its cells already show it
		bne.s	.changed		; (VRAM is kept in step with the copy
		jmp	(RAM_EmuLoop).l		; from the start, see Fami_InitVideo)
.palette:
		move.b	d7,(a3,d4.w)
		bra.w	ppuSetColor
.changed:
		move.b	d7,(a3,d4.w)
		move.w	ppuNtXor(a4),d5		; and the mirrored nametable's copy
		eor.w	d4,d5
		move.b	d7,(a3,d5.w)

; ----------------------------------------------------------------
; Nametable byte -> its MD plane cell, in both copies of a mirrored
; nametable (see ppuCellTbl in ppu_tables.asm). The palette comes
; from the attribute byte in the copy of the nametables (a3, kept
; mirrored by wrPPU_Data): VRAM is only written, never read back.
;
; d4 - PPU address ($2000-$3EFF), d7 - tile or attribute byte
; ----------------------------------------------------------------

ppuDrwCell:
		move.w	d4,d6
		andi.w	#$FFF,d6
		lsl.w	#3,d6
		lea	(ppuCellTbl).l,a5
		adda.w	d6,a5
		move.l	(a5)+,d6		; VDP command for the cell
		beq.w	ppuDrwCellPal		; none: an attribute byte
		move.w	(a5)+,d4		; its attribute byte's address
		move.w	(a5),d5			; and the table for its 2 bits
		move.b	(a3,d4.w),d5
		add.w	d5,d5
		lea	(ppuAttrPal).l,a5
		move.w	(a5,d5.w),d5		; palette, high priority
		move.b	d7,d5			; and the tile
		move.w	#$2700,sr
		move.l	d6,4(a6)
		move.w	d5,(a6)
		move.l	ppuCmdXor(a4),d7	; the mirrored copy
		eor.l	d7,d6
		move.l	d6,4(a6)
		move.w	d5,(a6)
		move.w	#$2000,sr
		moveq	#0,d7
		jmp	(RAM_EmuLoop).l
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
		st	vdpPalDirty(a4)		; DMAed at the next VBlank
		and.w	#$F,d6
		bne.s	.no_bgpal
		bchg	#4,d4
		move.w	ppuVdpColors(pc,d5.w),vdpPalette(a4,d4.w)
		
.no_bgpal:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

; NES palette $00-$3F as MD colors, generated by tools/mkpalette.py
ppuVdpColors:
		dc.w $666,$820,$A02,$A04,$806,$406,$006,$026	; $00-$07
		dc.w $022,$040,$040,$040,$442,$000,$000,$000	; $08-$0F
		dc.w $AAA,$C40,$E24,$E26,$C0A,$60A,$22A,$048	; $10-$17
		dc.w $066,$082,$080,$280,$A80,$000,$000,$000	; $18-$1F
		dc.w $EEE,$EA6,$E88,$E6C,$E6E,$C6E,$68E,$2AE	; $20-$27
		dc.w $2CC,$0C8,$4E6,$6C2,$CC4,$444,$000,$000	; $28-$2F
		dc.w $EEE,$ECA,$ECC,$ECE,$ECE,$ECE,$CCE,$ACE	; $30-$37
		dc.w $AEE,$AEC,$AEC,$CEA,$EEC,$AAA,$000,$000	; $38-$3F

; ----------------------------------------------------------------
; Attribute byte -> the palettes of its 4x4 cells, in both copies of
; a mirrored nametable. The cells are rebuilt from the tiles in the
; copy of the nametables (a3), a row of 4 at a time: VRAM is only
; written. The last attribute row covers NES rows 28-31, but rows
; 30-31 hold the attribute bytes themselves: only 28-29 are cells.
;
; d4 - PPU address of the attribute byte, d7 - the byte
; ----------------------------------------------------------------

ppuDrwCellPal:
		movem.l	d0-d3/a0,-(sp)
		move.w	d4,-(sp)
		moveq	#0,d5
		move.b	d7,d5			; the attribute byte
	; the first cell: NES address, its tiles, its MD plane offset
		move.w	d4,d6
		andi.w	#$38,d6
		lsl.w	#4,d6			; first row * 32
		move.w	d4,d7
		andi.w	#7,d7
		lsl.w	#2,d7			; first column
		andi.w	#$2C00,d4		; the nametable
		or.w	d7,d4
		or.w	d6,d4
		lea	(a3,d4.w),a0		; the first cell's tile
		lsl.w	#2,d6			; row * 128
		add.w	d7,d7
		add.w	d7,d6			; + column * 2
		btst	#11,d4
		beq.s	.plane_a
		addi.w	#$2000,d6
.plane_a:
		btst	#10,d4
		beq.s	.left
		addi.w	#$40,d6
.left:
		move.w	#$40,d4			; the mirror: the other half
		tst.w	ppuMirror(a4)
		beq.s	.other
		move.w	#$2000,d4		; or the other plane
.other:
		move.w	#$2700,sr
		move.w	d5,d0			; top left, top right
		bsr.s	.palettes
		bsr.s	.two_rows
		move.w	(sp),d7
		andi.w	#$38,d7
		cmpi.w	#$38,d7			; the last attribute row
		beq.s	.done
		move.w	d5,d0			; bottom left, bottom right
		lsr.w	#4,d0
		bsr.s	.palettes
		bsr.s	.two_rows
.done:
		move.w	#$2000,sr
		addq.w	#2,sp
		movem.l	(sp)+,d0-d3/a0
		moveq	#0,d7
		jmp	(RAM_EmuLoop).l

; d0 - attribute bits: 1-0 left, 3-2 right -> d0, d1: MD cell bits
.palettes:
		move.w	d0,d1
		lsr.w	#2,d1
		andi.w	#3,d0
		andi.w	#3,d1
		ror.w	#3,d0
		ror.w	#3,d1
		ori.w	#$8000,d0
		ori.w	#$8000,d1
		rts

; two rows of 4 cells, left two with palette d0, right two with d1
; a0 - tiles, d6 - MD plane offset, d4 - the mirror's offset (eor)
.two_rows:
		bsr.w	.one_row		; (the next instruction: .s can't reach it)
.one_row:
		moveq	#0,d2
		move.b	(a0),d2
		or.w	d0,d2
		swap	d2
		move.w	d0,d2
		or.b	1(a0),d2		; cells 0, 1
		moveq	#0,d3
		move.b	2(a0),d3
		or.w	d1,d3
		swap	d3
		move.w	d1,d3
		or.b	3(a0),d3		; cells 2, 3
		move.w	d6,d7
		ori.w	#$4000,d7
		move.w	d7,4(a6)
		move.w	#3,4(a6)
		move.l	d2,(a6)
		move.l	d3,(a6)
		move.w	d6,d7
		eor.w	d4,d7
		ori.w	#$4000,d7
		move.w	d7,4(a6)
		move.w	#3,4(a6)
		move.l	d2,(a6)
		move.l	d3,(a6)
		lea	32(a0),a0
		addi.w	#128,d6
		rts

; ----------------------------------------------------------------
; $2007 write to the pattern tables ($0000-$1FFF)
;
; Ignored for CHR-ROM. For CHR-RAM, store the byte and re-convert
; that row of the tile in each MD tile set showing this table: MD
; tiles $000-$0FF hold the BG table, and for sprites $100-$1FF
; table 0 and $200-$2FF table 1, with colors +8 (Nemul_LoadChr).
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

	; the sprite set for its table ($2000, $4000), nonzero pixels +8
		move.l	d0,d6
		lsr.l	#1,d6
		or.l	d0,d6
		andi.l	#$11111111,d6
		lsl.l	#3,d6
		or.l	d6,d0
		moveq	#0,d5
		move.w	d3,d5
		addi.w	#$2000,d5
		tst.b	d1
		beq.s	.spr0
		addi.w	#$2000,d5
.spr0:
		lsl.l	#2,d5			; VDP command: VRAM write
		lsr.w	#2,d5
		swap	d5
		ori.l	#$40000000,d5
		move.l	d5,4(a6)
		move.l	d0,(a6)
		move.w	#$2000,sr
		movem.l	(sp)+,d0-d3
.done:
		jmp	(RAM_EmuLoop).l


; ----------------------------------------------------------------
; The mapper changed the nametables' mirroring (MMC3 $A000): the NES's
; second nametable moves in the copy of the nametables (a3), and both
; MD planes are drawn again from it
;
; d7.w - 0: horizontal, 1: vertical (as ppuMirror)
; ----------------------------------------------------------------

ppuSetMirror:
		cmp.w	ppuMirror(a4),d7
		beq.s	.same
		move.w	d7,ppuMirror(a4)
		movem.l	d0/a0/a5,-(sp)
		lea	$2000(a3),a5		; the first nametable stays
		tst.w	d7
		bne.s	.vertical
	; horizontal: the second from $2400 to $2800 ($2C00 has it too),
	; then the first to $2400
		move.w	#$400,ppuNtXor(a4)
		move.l	#$00400000,ppuCmdXor(a4)
		lea	$400(a5),a0
		bsr.s	.copy_second
		bra.s	.redraw
	; vertical: the second from $2800 to $2400, the first to $2800
.vertical:
		move.w	#$800,ppuNtXor(a4)
		move.l	#$20000000,ppuCmdXor(a4)
		lea	$800(a5),a0
		bsr.s	.copy_second
.redraw:
		bsr.s	ppuRedrawPlanes
		movem.l	(sp)+,d0/a0/a5
.same:
		rts

; a0 - where the second nametable is now (it goes to a0 xor $C00, the
; first to a0)
.copy_second:
		move.l	a0,d0			; the second to its new place
		eori.w	#$C00,d0
		exg	d0,a0
		movea.l	d0,a5
		move.w	#$400/4-1,d0
.second:
		move.l	(a5)+,(a0)+
		dbf	d0,.second
		lea	-$400(a5),a0		; the first where the second was
		lea	$2000(a3),a5
		move.w	#$400/4-1,d0
.first:
		move.l	(a5)+,(a0)+
		dbf	d0,.first
		rts

; ----------------------------------------------------------------
; Both MD planes, drawn from the copy of the nametables (a3): plane
; A has nametables 0 and 1 side by side, B 2 and 3 (see ppuCellTbl)
; ----------------------------------------------------------------

ppuRedrawPlanes:
		movem.l	d0-d7/a0-a1/a5,-(sp)
		move.w	sr,-(sp)
		lea	(ppuAttrPal).l,a1
		moveq	#0,d0			; nametable * $400
.nametable:
		moveq	#0,d1			; row
.row:
		move.w	d1,d7			; VRAM: row * 128,
		lsl.w	#7,d7
		btst	#10,d0			; + $40 for 1 and 3,
		beq.s	.left
		addi.w	#$40,d7
.left:
		addi.w	#$C000,d7		; plane A or B
		btst	#11,d0
		beq.s	.plane_a
		addi.w	#$2000,d7
.plane_a:
		moveq	#0,d6			; -> VDP command
		move.w	d7,d6
		lsl.l	#2,d6
		lsr.w	#2,d6
		swap	d6
		ori.l	#$40000000,d6
		move.w	d0,d7			; the row's tiles
		addi.w	#$2000,d7
		move.w	d1,d5
		lsl.w	#5,d5
		add.w	d7,d5
		lea	(a3,d5.w),a5
		move.w	d1,d5			; and its attribute bytes
		lsr.w	#2,d5
		lsl.w	#3,d5
		addi.w	#$3C0,d5
		add.w	d7,d5
		lea	(a3,d5.w),a0
		move.w	d1,d4			; the bottom 2 rows of each 4:
		andi.w	#2,d4			; the attribute's fields 2, 3
		lsl.w	#8,d4			; (ppuAttrPal tables 2, 3: $400)
		add.w	d4,d4
		move.w	#$2700,sr
		move.w	#$8F02,4(a6)
		move.l	d6,4(a6)
		moveq	#8-1,d3			; 8 groups of 4 cells
.group:
		moveq	#0,d2
		move.b	(a0)+,d2		; attribute byte
		add.w	d2,d2
		add.w	d4,d2
		move.w	(a1,d2.w),d5		; left 2 cells: palette, priority
		addi.w	#$200,d2
		move.w	(a1,d2.w),d6		; right 2
		move.w	d5,d7
		move.b	(a5)+,d7
		move.w	d7,(a6)
		move.b	(a5)+,d5
		move.w	d5,(a6)
		move.w	d6,d7
		move.b	(a5)+,d7
		move.w	d7,(a6)
		move.b	(a5)+,d6
		move.w	d6,(a6)
		dbf	d3,.group
		move.w	(sp),sr
		addq.w	#1,d1
		cmpi.w	#30,d1
		bcs.w	.row
		addi.w	#$400,d0
		cmpi.w	#$1000,d0
		bcs.w	.nametable
		addq.w	#2,sp
		movem.l	(sp)+,d0-d7/a0-a1/a5
		rts

; ----------------------------------------------------------------
; Pattern tables (the copy in a3, chrSync) -> MD tiles. MD tiles $000-$0FF
; hold the BG table (the one $2000 bit 4 picks), and for sprites,
; $100-$1FF table 0 and $200-$2FF table 1, with their opaque pixels'
; colors +8 (the sprite palettes, see ppuSetColor). Both tables are
; there for sprites since 8x16 ones take theirs from the tile number.
;
; a6 - $C00000
; a4 - RAM_Fami_Emu
; ----------------------------------------------------------------

Nemul_LoadChr:
		movem.l	d4/d6,-(sp)
		moveq	#0,d4			; the sprite sets: both tables
		move.w	#$2000,d6
		bsr.s	chrToSprites
		bsr.s	chrLoadBg
		movem.l	(sp)+,d4/d6
		rts

; The BG set, from the table $2000 bit 4 picks (ppuChrBank bit 7)
chrLoadBg:
		movem.l	d4/d6,-(sp)
		moveq	#0,d4
		tst.b	ppuChrBank+1(a4)
		bpl.s	.table
		move.w	#$1000,d4
.table:
		move.w	#$1000,d6
		bsr.s	chrToBg
		movem.l	(sp)+,d4/d6
		rts

; ----------------------------------------------------------------
; Pattern bytes that changed -> the MD tile sets that show them
;
; d4.w - pattern table address (whole tiles, $0000-$1FFF)
; d6.w - bytes (whole tiles, within one table)
; ----------------------------------------------------------------

chrRefresh:
		bsr.s	chrToBg
		bra.s	chrToSprites

; Into the BG set, if they're in its table
chrToBg:
		movem.l	d4/d6-d7/a5,-(sp)
		move.w	d4,d7
		lsr.w	#5,d7			; their table ($1000) -> bit 7
		move.b	ppuChrBank+1(a4),d5	; the BG's: bit 7
		eor.b	d7,d5
		bmi.s	.not_bg
		bsr.w	chrSync
		lea	(a3,d4.w),a5
		andi.w	#$FFF,d4		; VRAM: tile * 32
		add.w	d4,d4
		lsr.w	#4,d6
		move.w	d6,d7
		moveq	#0,d5			; BG colors
		bsr.s	chrConvert
.not_bg:
		movem.l	(sp)+,d4/d6-d7/a5
		rts

; Into the sprite set for their table
chrToSprites:
		movem.l	d4/d6-d7/a5,-(sp)
		bsr.w	chrSync
		lea	(a3,d4.w),a5
		add.w	d4,d4			; VRAM: $2000 + tile * 32
		addi.w	#$2000,d4
		lsr.w	#4,d6
		move.w	d6,d7
		moveq	#8,d5			; sprite colors
		bsr.s	chrConvert
		movem.l	(sp)+,d4/d6-d7/a5
		rts

; ----------------------------------------------------------------
; NES tiles -> MD tiles through ppuChrSpread, a tile at a time with
; interrupts off (MD_Vint uses the VDP too) so that converting many
; doesn't hold up the VBlank interrupt
;
; a5 - first tile, d7.w - tiles, d4.w - VRAM address of the first,
; d5.b - 8: sprites (opaque pixels +8), 0: BG
; ----------------------------------------------------------------

chrConvert:
		if (NES_MAPPER=4)&&(NES_CHR8<>0)
		bsr.w	chrFlush		; the queued tiles first (chrUpdate)
		endif
		movem.l	d0-d3/d6-d7/a0,-(sp)
		move.w	sr,-(sp)
		lea	(ppuChrSpread).l,a0
		subq.w	#1,d7
.tile:
		moveq	#0,d6			; VDP command: VRAM write at d4
		move.w	d4,d6
		lsl.l	#2,d6
		lsr.w	#2,d6
		swap	d6
		ori.l	#$40000000,d6
		move.w	#$2700,sr
		move.w	#$8F02,4(a6)
		move.l	d6,4(a6)
		moveq	#8-1,d3			; rows
.row:
		moveq	#0,d1
		move.b	(a5)+,d1		; plane 0: bit 0 of each pixel
		add.w	d1,d1
		add.w	d1,d1
		move.l	(a0,d1.w),d0
		moveq	#0,d1
		move.b	7(a5),d1		; plane 1 (8 bytes on): bit 1
		add.w	d1,d1
		add.w	d1,d1
		move.l	(a0,d1.w),d2
		tst.b	d5
		beq.s	.colors
		move.l	d0,d1			; sprites: opaque pixels +8
		or.l	d2,d1
		lsl.l	#3,d1
		or.l	d1,d0
.colors:
		add.l	d2,d2
		or.l	d2,d0
		move.l	d0,(a6)
		dbf	d3,.row
		move.w	(sp),sr
		addq.l	#8,a5
		addi.w	#32,d4
		dbf	d7,.tile
		addq.w	#2,sp
		movem.l	(sp)+,d0-d3/d6-d7/a0
		rts

; ----------------------------------------------------------------
; MMC3: the copy of the pattern tables (a3) up to date, before it's
; read whole: chrUpdate leaves it as it was, chrSlotPtr has the
; CHR-ROM data each 1 KB of the tables shows now, and chrStale those
; the copy is out of date for (bit 0: $0000-$03FF, and so on).
; ----------------------------------------------------------------

chrSync:
		tst.w	chrStale(a4)
		bne.s	.stale
		rts
.stale:
		movem.l	d0-d1/a0-a1/a5,-(sp)
		move.w	chrStale(a4),d1
		clr.w	chrStale(a4)
		lea	chrSlotPtr(a4),a5
		movea.l	a3,a1
.slot:
		lsr.w	#1,d1
		bcs.s	.stale_kb
		lea	$400(a1),a1		; up to date
		bra.s	.next
.stale_kb:
		movea.l	(a5),a0
		moveq	#$400/16-1,d0
.copy:
		move.l	(a0)+,(a1)+
		move.l	(a0)+,(a1)+
		move.l	(a0)+,(a1)+
		move.l	(a0)+,(a1)+
		dbf	d0,.copy
.next:
		addq.w	#4,a5
		tst.w	d1
		bne.s	.slot
		movem.l	(sp)+,d0-d1/a0-a1/a5
		rts

; ----------------------------------------------------------------
; New CHR-ROM data for part of the pattern tables (MMC3): the MD
; tiles of those of its tiles that differ from the ones there now,
; made as the ROM was built (CHR_MD in md.asm), into a queue for
; VRAM (the copy of the tables in a3 stays as it was: mmc3Chr,
; chrSync). MD_Vint copies those by DMA in VBlank (chrVblank),
; when the VDP takes them ten times as fast as while it draws.
; A game that switches banks to animate tiles changes few of them
; (Super Mario Bros. 2: 20 to 40 of a 2 KB bank's 128). Tiles are
; told apart by their IDs (CHR_ID, made with the ROM), and
; RAM_Fami_ChrIds has those of the tiles in the pattern tables.
;
; a0 - the new data, d4.w - where it goes ($0000-$1FFF),
; d6.w - bytes (whole tiles, within one table)
; ----------------------------------------------------------------

chrUpdate:
		movem.l	d0-d3/d5-d7/a1-a2/a5,-(sp)
		move.l	a0,d3			; the new tiles' IDs
		sub.l	emuChrRom(a4),d3
		move.l	d3,d2
		lsr.l	#3,d2
		lea	(CHR_ID).l,a1
		adda.l	d2,a1
		add.l	d3,d3			; d3: their MD tiles, from CHR_MD
		move.w	d4,d2			; the IDs of the tiles there now
		lsr.w	#3,d2
		lea	(RAM_Fami_ChrIds).l,a2
		adda.w	d2,a2
		moveq	#-1,d7			; d7: VRAM for the first in the BG
		move.w	d4,d2			; set, if it's the BG's table
		lsr.w	#5,d2			; (their table ($1000) -> bit 7,
		move.b	ppuChrBank+1(a4),d1	; the BG's: bit 7)
		eor.b	d2,d1
		bmi.s	.not_bg
		move.w	d4,d7
		andi.w	#$FFF,d7
		add.w	d7,d7
.not_bg:
		lea	(RAM_Fami_ChrDma).l,a5
		lsr.w	#4,d6			; tiles
		move.w	d6,d0
		subq.w	#1,d0
.scan:
		cmpm.w	(a1)+,(a2)+		; the same tile?
		dbne	d0,.scan
		beq.s	.done
		move.w	d6,d1			; no: a run of new ones from it,
		sub.w	d0,d1			; tiles d1 to d2-1, with up to two
		subq.w	#1,d1			; the same in a row in it (another
.new:						; DMA costs more than them)
		move.w	-2(a1),-2(a2)
		move.w	d6,d2
		sub.w	d0,d2
		moveq	#2,d5
.next:
		subq.w	#1,d0
		bmi.s	.last
		cmpm.w	(a1)+,(a2)+
		bne.s	.new
		dbf	d5,.next
		bsr.s	.flush			; three the same: it ends before them
		dbf	d0,.scan
		bra.s	.done
.last:
		bsr.s	.flush
.done:
		movem.l	(sp)+,d0-d3/d5-d7/a1-a2/a5
		rts

	; tiles d1 to d2-1: their MD tiles queued
.flush:
		movem.l	d0/a0-a1,-(sp)
		sub.w	d1,d2			; d2: tiles
		lsl.w	#5,d1			; d1: the first's offset in MD tiles
		lsl.w	#4,d2			; words: 16 a tile
		tst.w	d7
		bmi.s	.sprites
		lea	(CHR_MD).l,a0		; into the BG set
		move.w	d7,d0
		bsr.s	.queue
.sprites:
		lea	(CHR_MD+NES_CHR8*$4000).l,a0	; into the sprite set for their
		move.w	d4,d0				; table: VRAM $2000 + tile * 32
		add.w	d0,d0
		addi.w	#$2000,d0
		bsr.s	.queue
		movem.l	(sp)+,d0/a0-a1
		rts

	; d2 words from a0+d3+d1 to VRAM d0+d1, into the queue
	; (RAM_Fami_ChrDma, 128 of 16 bytes: the DMA's VDP register words
	; $93 $94 (words), $97 $96 $95 (source / 2), the VRAM write with
	; DMA (two words), and the words)
.queue:
		adda.l	d3,a0
		adda.w	d1,a0
		add.w	d1,d0
		move.w	d6,-(sp)
		move.w	chrDmaTail(a4),d5
		lea	(a5,d5.w),a1
		move.w	#$9300,d6
		move.b	d2,d6
		move.w	d6,(a1)+
		move.w	d2,d6
		lsr.w	#8,d6
		ori.w	#$9400,d6
		move.w	d6,(a1)+
		move.l	#$97009600,(a1)
		move.w	#$9500,4(a1)
		move.l	a0,d6
		lsr.l	#1,d6
		movep.w	d6,3(a1)		; bits 15-8 to $96, 7-0 to $95
		swap	d6
		move.b	d6,1(a1)		; 23-16 to $97
		addq.w	#6,a1
		move.w	d0,d6
		andi.w	#$3FFF,d6
		ori.w	#$4000,d6
		move.w	d6,(a1)+
		move.w	d0,d6
		rol.w	#2,d6
		andi.w	#3,d6
		ori.w	#$80,d6
		move.w	d6,(a1)+
		move.w	d2,(a1)
		move.w	(sp)+,d6
		addi.w	#16,d5
		andi.w	#$7FF,d5
		cmp.w	chrDmaHead(a4),d5
		bne.s	.queued
		bsr.s	chrFlush		; full: copy the others now
.queued:
		move.w	d5,chrDmaTail(a4)
		rts

; ----------------------------------------------------------------
; Queued MD tiles (chrUpdate) -> VRAM, all of them now, wherever the
; VDP is: before tiles are written another way (chrConvert), or when
; the queue is full
; ----------------------------------------------------------------

chrFlush:
		movem.l	d0/d5,-(sp)
		move.w	chrDmaHead(a4),d5
		cmp.w	chrDmaTail(a4),d5
		beq.s	.none
		move.w	sr,-(sp)
		move.w	#$2700,sr
		move.w	#$0100,(z80_bus).l
.wait:
		btst	#0,(z80_bus).l
		bne.s	.wait
		move.w	#$8F02,4(a6)
		moveq	#-1,d0
		bsr.s	chrDma
		move.w	#0,(z80_bus).l
		move.w	(sp)+,sr
.none:
		movem.l	(sp)+,d0/d5
		rts

; ----------------------------------------------------------------
; In VBlank (MD_Vint): as many queued MD tiles as there's time for
; before the screen starts (the rest go in the next VBlank)
; ----------------------------------------------------------------

chrVblank:
		move.w	chrDmaHead(a4),d0
		cmp.w	chrDmaTail(a4),d0
		beq.s	.none
		bsr.w	ppuClock		; lines left in VBlank, less a margin
		move.w	mdLines(a4),d0
		subi.w	#224+2,d0
		sub.w	d5,d0
		bgt.s	.time
.none:
		rts
.time:
		lsl.w	#7,d0			; bytes: 128 a line (the VDP takes 166)

; ----------------------------------------------------------------
; Queued MD tiles -> VRAM by DMA, with the Z80 off the bus and
; interrupts off
;
; d0.w - bytes there's time for (-1: all)
; ----------------------------------------------------------------

chrDma:
		movem.l	d1-d3/a0/a5,-(sp)
		lea	(RAM_Fami_ChrDma).l,a5
.entry:
		move.w	chrDmaHead(a4),d1
		cmp.w	chrDmaTail(a4),d1
		beq.s	.done			; none left
		lea	(a5,d1.w),a0
		move.w	14(a0),d2		; words
		tst.w	d0
		bmi.s	.all
		move.w	d0,d3			; words there's time for: whole tiles
		lsr.w	#1,d3
		andi.w	#$FFF0,d3
		beq.s	.done
		cmp.w	d2,d3
		bcs.s	.part
.all:
		move.l	(a0)+,4(a6)		; length,
		move.l	(a0)+,4(a6)		; source,
		move.l	(a0)+,4(a6)		; and the VRAM write with DMA: the
		move.w	(a0),4(a6)		; word that starts it, from RAM
		addi.w	#16,d1
		andi.w	#$7FF,d1
		move.w	d1,chrDmaHead(a4)
		tst.w	d0
		bmi.s	.entry
		add.w	d2,d2
		sub.w	d2,d0
		bgt.s	.entry
.done:
		movem.l	(sp)+,d1-d3/a0/a5
		rts

	; d3 words of the entry at a0 now, the rest next time
.part:
		andi.l	#$FFFF,d3
		move.w	#$9300,d1
		move.b	d3,d1
		move.w	d1,4(a6)
		move.w	d3,d1
		lsr.w	#8,d1
		ori.w	#$9400,d1
		move.w	d1,4(a6)
		move.l	4(a0),4(a6)
		move.l	8(a0),4(a6)
		move.w	12(a0),4(a6)
		sub.w	d3,d2			; the rest: fewer words,
		move.w	d2,14(a0)
		move.b	d2,1(a0)
		lsr.w	#8,d2
		move.b	d2,3(a0)
		movep.l	3(a0),d1		; the source on (bits 31-24: $94's)
		add.l	d3,d1
		movep.w	d1,7(a0)
		swap	d1
		move.b	d1,5(a0)
		move.w	12(a0),d2		; and VRAM on
		ror.w	#2,d2
		andi.w	#$C000,d2
		move.w	10(a0),d1
		andi.w	#$3FFF,d1
		or.w	d2,d1
		add.w	d3,d1
		add.w	d3,d1
		move.w	d1,d2
		andi.w	#$3FFF,d1
		ori.w	#$4000,d1
		move.w	d1,10(a0)
		rol.w	#2,d2
		andi.w	#3,d2
		ori.w	#$80,d2
		move.w	d2,12(a0)
		bra.w	.done
