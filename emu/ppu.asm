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
