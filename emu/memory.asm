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

	; sprite 0 hit: set from sprite 0's first line until the end of
	; the display. A sprite at Y starts on NES line Y+1, and NES line L
	; is shown on MD line L-8. Sprites below the MD's 224 lines hit on
	; the last line so games waiting for the hit don't hang.
	; Hidden sprites (Y >= $EF) never hit.
		move.w	#$2700,sr
		move.w	ppuSp0Ypos(a4),d4
		cmpi.w	#$EF,d4
		bcc.s	.no_hit
		subq.w	#7,d4
		bpl.s	.sp0_top
		moveq	#0,d4
.sp0_top:
		cmpi.w	#$DF,d4
		bls.s	.sp0_bottom
		move.w	#$DF,d4
.sp0_bottom:
		move.w	8(a6),d5		; MD V counter
		lsr.w	#8,d5
		cmpi.w	#$E0,d5
		bcc.s	.no_hit		; vblank
		cmp.w	d4,d5
		bcs.s	.no_hit		; above sprite 0
		ori.w	#$40,d7
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
		add.w	d4,d4
		move.w	wrAPU_Table(pc,d4.w),d4
		jmp	wrAPU_Table(pc,d4.w)

; ----------------------------------------------------------------
wrAPU_Table:	dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_OAMDMA-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Input-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table
		dc.w APU_Null-wrAPU_Table

APU_Null:
		jmp	(RAM_EmuLoop).l


APU_Input:
		tst.b	d7
		beq.s	APU_Null
		bsr	readInput
		jmp	(RAM_EmuLoop).l


readInput:
		move.l	a3,-(sp)
		lea	($A10003).l,a3
		lea	cpuInputData(a4),a5
		bsr	.this_pad
		addq.w	#2,a3
		bsr	.this_pad		
		move.l	(sp)+,a3
		rts
		
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


APU_OAMDMA:
		move.l	d7,-(sp)
		move.l	a3,-(sp)
		
		lsl.w	#8,d7
		move.w	ppuOamUnk(a4),d6
		eori.w	#1,d6
		move.b	ppuOamAddr(a4,d6.w),d7
		lea	(a2,d7.w),a5
		move.b	(a5),ppuSp0Ypos+1(a4)		; sprite 0 ypos

		lea 	vdpSprData(a4),a3
		moveq	#$3F,d5
		moveq	#0,d7
.lp_sprnormal:
		move.b	(a5)+,d7
		move.w	d7,d6
		addi.w	#$79,d6
		move.w	d6,(a3)+

		moveq	#64,d6
		sub.b	d5,d6
		or.w	ppuSprWide(a4),d6
		move.w	d6,(a3)+
		
		move.b	(a5)+,d7
		move.w	d7,d6
		ori.w	#$100,d6

		move.b	(a5)+,d7
		move.w	d7,d4
		rol.b	#2,d4
		lsl.w	#1,d4
		lsl.b	#3,d4
		lsl.w	#7,d4
		or.w	d6,d4
		eori.w	#$8000,d4
		move.w	d4,(a3)+

		move.b	(a5)+,d7
		move.w	d7,d6
		addi.w	#$80,d6
		move.w	d6,(a3)+

		dbf	d5,.lp_sprnormal
		move.l	(sp)+,a3
		move.l	(sp)+,d7
		jmp	(RAM_EmuLoop).l
