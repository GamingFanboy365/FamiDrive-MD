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
		
	; PPU VRAM BG bank/Sprites bank
		move.b	d7,d6
		andi.w	#$C0,d6
		move.w	ppuChrBank(a4),d5
		eor.w	d6,d5			; the tables that changed
		beq.s	.no_reload
		move.w	d6,ppuChrBank(a4)
		move.w	d5,d6
		bsr	Nemul_LoadChrSets	; convert those tile sets again
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
		bsr	ppuXChanged
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
; the screen, after waiting for sprite 0 hit. Until the game has seen
; the hit this frame (ppuSp0State), a change sets the scroll from the
; top: whatever runs before is the NES's VBlank work, however long it
; takes here (VRAM addresses written to $2006 pass through the scroll
; on the NES too, and games set it again after). After the hit, a
; change starts a split at the line the NES would be on (ppuLine),
; unless it comes from $2006. Changes at about the same line (the X,
; then $2000's nametable bit) make one split. hsBuild turns them into
; the MD's line scroll table.
;
; d6.w - 0: don't start a split
; Uses d4-d6, a5. Call with interrupts off.
; ----------------------------------------------------------------

ppuXChanged:
		movem.l	d0/d5,-(sp)
		move.w	d6,d0
		move.w	ppuTX(a4),d4
		neg.w	d4
		cmp.w	vdpScrlX(a4),d4
		beq.w	.done
		cmpi.w	#2,ppuSp0State(a4)	; before the game saw sprite 0 hit
		bne.s	.top
		tst.w	ppuMaskOn(a4)
		beq.s	.top
		tst.w	d0			; $2006 mid-screen: leave the scroll
		beq.w	.done			; (games set it right after)
		bsr	ppuLine
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
		addq.w	#2,d6
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
.top:
		move.w	d4,hsTopCur(a4)
		move.w	d4,hsTopCur+2(a4)
.set:
		move.w	d4,vdpScrlX(a4)
		move.w	d4,vdpScrlX+2(a4)
.done:
		movem.l	(sp)+,d0/d5
		rts

; ----------------------------------------------------------------
; Time within the game's frame
;
; FamiDrive runs some games slower than the NES, so a game frame can
; outlast an MD frame. Raster effects (sprite 0 hit, scroll splits)
; are timed from when the game's frame began, at its NMI: the NES
; line the game would be on, if each MD line is one NES line.
;
; ppuClock: d5.w = MD line, counted from the start of VBlank (0-261,
; roughly: the V counter repeats a few values in VBlank)
; ppuLine: d5.w = NES line now (negative: still in VBlank), from
; the lines since ppuFrameStart; 20 VBlank lines follow the NMI, and
; a frame that outlasts 262 lines goes round again
; Call with interrupts off.
; ----------------------------------------------------------------

ppuClock:
		move.w	8(a6),d5		; V counter
		lsr.w	#8,d5
		subi.w	#$E0,d5			; lines since the MD's VBlank began
		bcc.s	.vblank
		addi.w	#$E0+262-224,d5
.vblank:
		rts

ppuLine:
		bsr.s	ppuClock
		sub.w	vNmi(a4),d5		; lines since, less whole frames: the
		bpl.s	.ahead			; NES keeps drawing frames meanwhile
		addi.w	#262,d5
.ahead:
		subi.w	#21,d5			; pre-render line: NES line 0 starts after it
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
		bsr.s	ppuClock
		move.w	d5,vNmi(a4)
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
		move.w	(sp)+,sr
		movem.l	(sp)+,d0/d5/a0-a1
		rts

; ----------------------------------------------------------------
; Set the MD's horizontal scroll, once per frame from MD_Vint (in
; VBlank). It shows the current game frame once its scroll from the
; top is set (its NMI handler returned, or the game saw sprite 0 hit:
; the screen is being drawn) and it has as many splits as the previous
; frame; else the previous frame (a slow game frame spans MD frames).
; Without splits it is one scroll for the screen, else the line scroll
; table at $B800 is written line by line. Nothing is written while the
; scroll stays the same (hsShown).
;
; a6 - VDP ports, auto-increment 2
; ----------------------------------------------------------------

hsApply:
		lea	hsTopCur(a4),a1
		tst.w	cpuFamiVint(a4)		; NMI handler returned
		beq.s	.top_set
		cmpi.w	#2,ppuSp0State(a4)	; or past sprite 0 hit
		bne.s	.done_frame
.top_set:
		move.w	hsCurN(a4),d0
		cmp.w	hsDoneN(a4),d0
		bcc.s	.use
.done_frame:
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
		dc.w $666,$820,$A00,$A02,$804,$406,$006,$024	; $00-$07
		dc.w $022,$040,$040,$040,$440,$000,$000,$000	; $08-$0F
		dc.w $AAA,$C60,$E44,$E26,$C2A,$62A,$22A,$048	; $10-$17
		dc.w $066,$082,$080,$280,$860,$000,$000,$000	; $18-$1F
		dc.w $EEE,$EA6,$E88,$E6C,$E6E,$C6E,$68E,$2AE	; $20-$27
		dc.w $0CA,$0C8,$2E4,$8C4,$CC4,$444,$000,$000	; $28-$2F
		dc.w $EEE,$ECC,$ECC,$ECE,$ECE,$ECE,$CCE,$ACE	; $30-$37
		dc.w $8EE,$8EC,$AEC,$CEA,$EEA,$AAA,$000,$000	; $38-$3F

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


; ----------------------------------------------------------------
; Pattern tables (the copy in a3) -> MD tiles, a row at a time
; through ppuChrSpread
;
; a6 - $C00000
; a4 - RAM_Fami_Emu
; ----------------------------------------------------------------

Nemul_LoadChr:
		moveq	#-1,d6			; both tile sets

; d6 - bit 7: the BG set (MD tiles $000-$0FF), bit 6: the sprite set
; ($100-$1FF, colors +8), each from the pattern table ppuChrBank picks
Nemul_LoadChrSets:
		move.w	#$2700,sr
		move.w	#$8F02,4(a6)
		move.w	d6,-(sp)
		tst.b	d6
		bpl.s	.sprites
		move.l	#$40000000,4(a6)	; VRAM $0000
		moveq	#0,d5
		move.w	ppuChrBank(a4),d6
		bsr.w	.make_chr
.sprites:
		move.w	(sp)+,d6
		btst	#6,d6
		beq.s	.done
		move.l	#$60000000,4(a6)	; VRAM $2000
		moveq	#8,d5
		move.w	ppuChrBank(a4),d6
		lsl.b	#1,d6
		bsr.w	.make_chr
.done:
		move.w	#$2000,sr
		rts

.make_chr:
		movea.l	a3,a5
		lsl.b	#1,d6
		bcc.s	.got_table
		adda.l	#$1000,a5
.got_table:
		movem.l	d0-d3/d7/a0,-(sp)
		lea	(ppuChrSpread).l,a0
		move.w	#256-1,d7		; tiles
.tile:
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
		addq.l	#8,a5
		dbf	d7,.tile
		movem.l	(sp)+,d0-d3/d7/a0
		rts
