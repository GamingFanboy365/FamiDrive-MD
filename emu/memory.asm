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
		bcc.s	.no_hit
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
		move.w	#1,ppuSp0State(a4)	; VBlank is over
		bra.s	.no_hit_d5
.to_hit:
		move.w	#2,ppuSp0State(a4)
	; The NES is on sprite 0's line now: the frame's line count
	; (ppuLine, from vNmi) goes from here.
		bsr	ppuLine
		sub.w	d4,d5
		subq.w	#1,d5			; lines from sprite 0's (Y+1)
		add.w	vNmi(a4),d5
		bpl.s	.not_before
		addi.w	#262,d5
.not_before:
		cmpi.w	#262,d5
		bcs.s	.in_frame
		subi.w	#262,d5
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
		jsr	readXyz			; pad 1's X Y Z toggle the FPS counter
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
; a3 - PPU buffer (pattern tables at the start)
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
		lea	vdpSprData(a4),a3
		lea	(oamAttr).l,a6
		move.w	ppuSprWide(a4),d6
		addq.w	#1,d6			; size, and the link to the next sprite
		moveq	#$79,d0			; NES line L+1 is MD line L-8, +128
		move.w	#$80,d1
		moveq	#0,d2
		moveq	#64-1,d5
.lp_sprnormal:
		move.b	(a5)+,d2		; Y
		cmpi.b	#$E7,d2
		bcc.s	.hidden
		move.w	d2,d7
		add.w	d0,d7
		move.w	d7,(a3)+
		move.w	d6,(a3)+
		addq.w	#1,d6
		move.b	(a5)+,d2		; tile
		moveq	#0,d3
		move.b	(a5)+,d3		; attributes
		add.w	d3,d3
		move.w	(a6,d3.w),d7
		or.w	d2,d7
		move.w	d7,(a3)+
		move.b	(a5)+,d2		; X
		move.w	d2,d7
		add.w	d1,d7
		move.w	d7,(a3)+
		dbf	d5,.lp_sprnormal
		bra.s	.listed
.hidden:
		addq.w	#3,a5
		dbf	d5,.lp_sprnormal
.listed:
		lea	vdpSprData(a4),a6
		cmpa.l	a6,a3
		bne.s	.end_list
		clr.l	(a3)+			; none: one sprite above the screen
		clr.l	(a3)+
.end_list:
		if FPS
		move.b	#64,-5(a3)		; the last one links to the FPS counter
		else
		sf	-5(a3)			; the last one ends the list
		endif
		suba.l	a6,a3
		move.l	a3,d7
		lsr.w	#1,d7
		move.w	d7,vdpSprWords(a4)	; for the DMA (MD_Vint)
		movem.l	(sp)+,d0-d3/d7/a3/a6
		jmp	(RAM_EmuLoop).l

; NES sprite attributes to the MD's: priority (inverted: the NES's bit
; puts the sprite behind the background), palette, vertical and
; horizontal flip; sprite tiles start at $100
oamAttr:
oamAttrI	set	0
		rept	256
		dc.w	$100|(((~oamAttrI)&$20)<<10)|((oamAttrI&3)<<13)|((oamAttrI&$C0)<<5)
oamAttrI	set	oamAttrI+1
		endm
