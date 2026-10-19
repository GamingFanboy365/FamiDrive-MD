; ====================================================================
; FamiDrive hardware test (tools/hwtest/build.sh: out/hwtest.bin)
;
; Measures what FamiDrive depends on, for consoles that aren't a Mega
; Drive (AtGames' and other clones): the V counter and VBlank timing,
; CPU speed, VRAM write and DMA speed (and whether writes made while
; the screen is drawn arrive intact), Z80 bus and YM2612 access. Each
; result is shown next to a Mega Drive's. Page 1: the V counter;
; page 2: speed and sound (left/right). A plays a tone on the
; YM2612, B on the PSG, C stops them, START measures again. The
; stripes at the bottom are scrolled per line as FamiDrive does: the
; top two rows move, the bottom one stays still. See README.md.
; ====================================================================

		cpu	68000
		supmode	on
		padding	off
		page	0

vdp_data	equ $C00000
vdp_ctrl	equ $C00004
vdp_hv		equ $C00008
psg_port	equ $C00011
z80_ram		equ $A00000
z80_bus		equ $A11100
z80_reset	equ $A11200
ym_a0		equ $A04000
ym_d0		equ $A04001
pad_data	equ $A10003
pad_ctrl	equ $A10009

; RAM
vFrames		equ $FFFF0000		; VBlank interrupts taken
vIntHV		equ $FFFF0002		; HV counter at the last one's start
vLive		equ $FFFF0004		; VInt does the live work
vScroll		equ $FFFF0006
padHeld		equ $FFFF0008
padNew		equ $FFFF000A
again		equ $FFFF000C		; START: measure again
hCount		equ $FFFF000E		; line interrupts taken
ev		equ $FFFF0010		; line or VBlank interrupts taken
page		equ $FFFF0012		; the page shown, 0 or 1
redraw		equ $FFFF0014		; left/right: show the other page
res		equ $FFFF0100		; results, words, in screen order
dmaBuf		equ $FFFF1000		; 1 KB DMA source

rVer		equ res+0
rLoops		equ res+2
rLines		equ res+4
rJumpN		equ res+6
rJumps		equ res+8			; up to 6 jumps: from, to
rVint		equ res+20
rVbOn		equ res+22			; $FFFF: not seen
rVbOff		equ res+24
rWrOn		equ res+26			; lines, $FFFF: a frame or more
rWrOff		equ res+28
rErrOn		equ res+30
rErrOff		equ res+32
rDmaOn		equ res+34
rDmaOff		equ res+36
rDmaErr		equ res+38
rBus		equ res+40			; $FFFF: never granted
rYmSt		equ res+42
rYmBusy		equ res+44			; $FFFF: never ready
rTorn		equ res+46
rLoops100	equ res+48		; loop turns in 100 lines
rLinesH		equ res+50		; lines per frame from them, $FFFF: none
rTimer		equ res+52		; YM2612 timer A overflows in 60 frames
rCalL		equ res+54		; FamiDrive's measure (vlMeasure): lines a frame
rCalRead	equ res+56		; V values read in the frame
rCalUnread	equ res+58		; the first from $E0 on not read, $FFFF: none
calTbl		equ $FFFF2000		; its table: line of each V value
rCalOdd		equ res+64		; the line for odd V values in VBlank, $FFFF: none
rSeqN		equ res+60		; V changes noted from VBlank's start (VSeq)
rSeqFrame	equ res+62		; and the loop's turns in the frame
seqBuf		equ $FFFF2400		; the changes: V, turn (up to 64)
seqClean	equ $FFFF2600		; the same less AtGames' n+2 between n and n+1

valCol		equ 23			; right end of the THIS column

; ====================================================================
; Header
; ====================================================================

		dc.l $FFFFFE00, Entry
		rept 26
		dc.l Trap
		endm
		dc.l HInt		; level 4
		dc.l Trap
		dc.l VInt		; level 6
		dc.l Trap
		rept 32
		dc.l Trap
		endm
		dc.b "SEGA MEGA DRIVE "
		dc.b "(C)FAMI 2026.OCT"
		dc.b "FAMIDRIVE HARDWARE TEST                         "
		dc.b "FAMIDRIVE HARDWARE TEST                         "
		dc.b "GM HWTEST00-01"
		dc.w 0
		dc.b "J               "
		dc.l 0, EndOfRom-1
		dc.l $FF0000, $FFFFFF
		dc.b "            "
		dc.b "            "
		dc.b "                                        "
		dc.b "JUE             "

Trap:
		bra.s	Trap

; ====================================================================
; Start
; ====================================================================

Entry:
		move.w	#$2700,sr
		move.b	($A10001).l,d0
		andi.b	#$0F,d0
		beq.s	.no_tmss
		move.l	#"SEGA",($A14000).l
.no_tmss:
		lea	($FFFF0000).l,a0
		move.w	#($10000/4)-1,d0
.clr_ram:
		clr.l	(a0)+
		dbf	d0,.clr_ram
		lea	($FFFFFE00).l,sp

		lea	(vdp_data).l,a6
		tst.w	4(a6)
		lea	VdpRegs(pc),a0
		moveq	#VdpRegsN-1,d0
.regs:
		move.w	(a0)+,4(a6)
		dbf	d0,.regs

		move.l	#$40000000,4(a6)	; clear VRAM
		move.w	#($10000/4)-1,d0
.clr_vram:
		move.l	#0,(a6)
		dbf	d0,.clr_vram
		move.l	#$40000010,4(a6)	; VSRAM
		move.l	#0,(a6)
		move.l	#$C0000000,4(a6)	; colours: black, white, red, blue, grey
		move.w	#$000,(a6)
		move.w	#$EEE,(a6)
		move.w	#$00E,(a6)
		move.w	#$E40,(a6)
		move.w	#$888,(a6)

	; 1bpp font -> tiles 0-63 (ASCII $20-$5F)
		move.l	#$40000000,4(a6)
		lea	Font(pc),a0
		move.w	#(64*8)-1,d7
.font:
		move.b	(a0)+,d5
		moveq	#0,d4
		moveq	#7,d6
.pixel:
		lsl.l	#4,d4
		add.b	d5,d5
		bcc.s	.blank
		addq.b	#1,d4
.blank:
		dbf	d6,.pixel
		move.l	d4,(a6)
		dbf	d7,.font
	; tile 64: red and blue stripes, 4 pixels each
		moveq	#7,d0
.stripes:
		move.l	#$22223333,(a6)
		dbf	d0,.stripes

		move.b	#$9F,$11(a6)	; PSG silent
		move.b	#$BF,$11(a6)
		move.b	#$DF,$11(a6)
		move.b	#$FF,$11(a6)

	; Z80: a halt loop, then hold its bus for the YM2612
		move.w	#$100,(z80_bus).l
		move.w	#$100,(z80_reset).l
.bus1:
		btst	#0,(z80_bus).l
		bne.s	.bus1
		move.b	#$F3,(z80_ram).l	; di
		move.b	#$18,(z80_ram+1).l	; jr $
		move.b	#$FE,(z80_ram+2).l
		move.w	#0,(z80_reset).l
		moveq	#$7F,d0
.rst:
		dbf	d0,.rst
		move.w	#$100,(z80_reset).l
		move.w	#0,(z80_bus).l

		move.b	#$40,(pad_ctrl).l

		bsr.w	DrawStatic
		move.w	#$2500,sr		; VBlank interrupts on
		move.w	#1,again

Main:
		tst.w	again
		beq.s	.measured
		clr.w	again
		clr.w	vLive
		bsr.w	Measure
		bsr.w	DrawResults
		move.w	#1,vLive
.measured:
		tst.w	redraw
		beq.s	.idle
		clr.w	redraw
		clr.w	vLive
		bsr.w	DrawStatic
		bsr.w	DrawResults
		move.w	#1,vLive
.idle:
		bsr.w	WaitFrame
		bra.s	Main

; ====================================================================
; VBlank
; ====================================================================

VInt:
		move.w	(vdp_hv).l,vIntHV
		addq.w	#1,vFrames
		addq.w	#1,ev
		tst.w	vLive
		beq.s	.out
		movem.l	d0-d7/a0-a6,-(sp)
		bsr.w	Live
		movem.l	(sp)+,d0-d7/a0-a6
.out:
		rte

HInt:
		addq.w	#1,hCount
		addq.w	#1,ev
		rte

; Line scroll as FamiDrive does it (224 longs by the CPU each frame):
; the band in rows 25-26 moves, the rest stays still. Then the pad,
; the tones and the frame count.
Live:
		lea	(vdp_data).l,a6
		move.w	#$8B03,4(a6)
		move.l	#$78000002,4(a6)	; HScroll table at $B800
		moveq	#0,d1
		move.w	#25*8-1,d0
.top:
		move.l	d1,(a6)
		dbf	d0,.top
		move.w	vScroll,d1
		neg.w	d1
		swap	d1
		clr.w	d1
		moveq	#2*8-1,d0
.band:
		move.l	d1,(a6)
		dbf	d0,.band
		moveq	#0,d1
		moveq	#1*8-1,d0
.bottom:
		move.l	d1,(a6)
		dbf	d0,.bottom
		addq.w	#1,vScroll

	; pad: A B C START, left and right (3-button read)
		lea	(pad_data).l,a0
		move.b	#$40,(a0)
		nop
		nop
		move.b	(a0),d0			; ?1CBRLDU
		move.b	#0,(a0)
		nop
		nop
		move.b	(a0),d1			; ?0SA00DU
		move.b	#$40,(a0)
		not.b	d0
		not.b	d1
		andi.w	#$3C,d0			; C B R L
		andi.w	#$30,d1			; S A
		lsl.w	#2,d1
		or.w	d1,d0			; S A C B R L in bits 7-2
		move.w	padHeld,d1
		move.w	d0,padHeld
		not.w	d1
		and.w	d1,d0
		move.w	d0,d4			; newly pressed (the sound calls use d0)
		btst	#6,d4
		beq.s	.no_a
		bsr.w	FmOn
.no_a:
		btst	#4,d4
		beq.s	.no_b
		bsr.w	PsgOn
.no_b:
		btst	#5,d4
		beq.s	.no_c
		bsr.w	SoundOff
.no_c:
		btst	#7,d4
		beq.s	.no_start
		move.w	#1,again
.no_start:
		andi.w	#$0C,d4			; left or right: the other page
		beq.s	.no_page
		eori.w	#1,page
		move.w	#1,redraw
.no_page:
		move.w	vFrames,d0
		moveq	#1,d1
		moveq	#11,d2
		moveq	#5,d3
		bsr.w	PrintDec
		rts

; ====================================================================
; Sound
; ====================================================================

FmOn:
		bsr.w	BusGet
		lea	FmVoice(pc),a1
.set:
		move.b	(a1)+,d0
		cmpi.b	#$FF,d0
		beq.s	.done
		move.b	(a1)+,d1
		bsr.w	YmWrite
		bra.s	.set
.done:
		move.w	#0,(z80_bus).l
		rts

PsgOn:
		lea	(vdp_data).l,a6
		move.b	#$8C,$11(a6)	; tone 0: $1FC, 220 Hz
		move.b	#$1F,$11(a6)
		move.b	#$90,$11(a6)
		rts

SoundOff:
		lea	(vdp_data).l,a6
		move.b	#$9F,$11(a6)
		bsr.w	BusGet
		moveq	#$28,d0
		moveq	#0,d1
		bsr.w	YmWrite
		move.w	#0,(z80_bus).l
		rts

BusGet:
		move.w	#$100,(z80_bus).l
		move.w	#$7FFF,d7
.wait:
		btst	#0,(z80_bus).l
		dbeq	d7,.wait
		rts

YmWrite:
		move.w	#$7FFF,d7
.w1:
		btst	#7,(ym_a0).l
		dbeq	d7,.w1
		move.b	d0,(ym_a0).l
		move.w	#$7FFF,d7
.w2:
		btst	#7,(ym_a0).l
		dbeq	d7,.w2
		move.b	d1,(ym_d0).l
		rts

; FamiDrive's triangle voice (one sine operator), then A3 and key on
FmVoice:
		dc.b $22,$00, $27,$00, $2B,$00, $28,$00
		dc.b $B0,$07, $B4,$C0
		dc.b $30,$01, $34,$01, $38,$01, $3C,$01
		dc.b $40,$7F, $44,$7F, $48,$7F, $4C,$08
		dc.b $50,$1F, $54,$1F, $58,$1F, $5C,$1F
		dc.b $60,$00, $64,$00, $68,$00, $6C,$00
		dc.b $70,$00, $74,$00, $78,$00, $7C,$00
		dc.b $80,$0F, $84,$0F, $88,$0F, $8C,$0F
		dc.b $90,$00, $94,$00, $98,$00, $9C,$00
		dc.b $A4,$22, $A0,$1D		; block 4, F-number 541: 220 Hz
		dc.b $28,$F0
		dc.b $FF
		align 2

; ====================================================================
; Measurements
; ====================================================================

WaitFrame:
		move.w	vFrames,d7
.wait:
		cmp.w	vFrames,d7
		beq.s	.wait
		rts

; d3.b = V counter, read until two reads agree (a read as it
; changes can mix bits of the old and new count)
ReadV:
		move.b	(vdp_hv).l,d3
.again:
		cmp.b	(vdp_hv).l,d3
		beq.s	.done
		move.b	(vdp_hv).l,d3
		bra.s	.again
.done:
		rts

; Wait until the V counter reads d0.b (3 frames at most)
WaitV:
		move.w	vFrames,d7
		addq.w	#3,d7
.wait:
		cmp.b	(vdp_hv).l,d0
		beq.s	.done
		cmp.w	vFrames,d7
		bne.s	.wait
.done:
		rts

; d6.b - V counter at the start, d5.w - vFrames then
; returns d0.w: lines since, $FFFF if a VBlank came in between
LinesSince:
		moveq	#0,d0
		move.b	(vdp_hv).l,d0
		cmp.w	vFrames,d5
		bne.s	.long
		sub.b	d6,d0
		rts
.long:
		moveq	#-1,d0
		rts

Measure:
		lea	(vdp_data).l,a6
		move.w	#$8B03,4(a6)

		moveq	#0,d0
		move.b	($A10001).l,d0
		move.w	d0,rVer

	; CPU: loop turns in one frame (26 cycles each on a 68000)
		bsr.w	WaitFrame
		bsr.w	WaitFrame
		lea	ev,a0
		move.w	(a0),d1
		moveq	#0,d0
.cpu:
		addq.l	#1,d0
		cmp.w	(a0),d1
		beq.s	.cpu
		move.w	d0,rLoops

	; Lines per frame without the V counter: loop turns between two
	; line interrupts 100 lines apart, against the turns in a frame
		move.w	#$FFFF,rLinesH
		clr.w	rLoops100
		move.w	#$8A63,4(a6)		; line interrupt every 100 lines
		move.w	#$8014,4(a6)		; line interrupts on
		move.w	#$2300,sr
		bsr.w	WaitFrame
		move.w	vFrames,d5
		lea	hCount,a1
		move.w	(a1),d1
.h1:
		cmp.w	(a1),d1
		bne.s	.h1_go
		cmp.w	vFrames,d5
		beq.s	.h1
		bra.s	.h_off			; a frame and no line interrupt
.h1_go:
		lea	ev,a0
		move.w	(a1),d2
		move.w	(a0),d1
		moveq	#0,d0
.h2:
		addq.l	#1,d0
		cmp.w	(a0),d1
		beq.s	.h2
		cmp.w	(a1),d2
		beq.s	.h_off			; VBlank came first
		move.w	d0,rLoops100
		moveq	#0,d3
		move.w	rLoops,d3
		mulu	#100,d3
		divu	d0,d3
		bvs.s	.h_off
		move.w	d3,rLinesH
.h_off:
		move.w	#$8004,4(a6)		; line interrupts off
		move.w	#$2500,sr

	; V counter over one frame, from V=$80 back to $80: lines,
	; jumps in its count, and where the VBlank flag goes on and off
		move.w	#$FFFF,rVbOn
		move.w	#$FFFF,rVbOff
		clr.w	rLines
		clr.w	rJumpN
		bsr.w	WaitFrame
		move.w	#$80,d0
		bsr.w	WaitV
		lea	(vdp_hv).l,a1
		lea	rJumps,a2
		move.w	vFrames,d1
		addq.w	#3,d1			; give up after 3 frames
		moveq	#0,d4			; lines
		moveq	#0,d5			; jumps
		bsr.w	ReadV
		move.b	d3,d2			; V
		move.w	4(a6),d6		; status
.scan:
		bsr.w	ReadV
		cmp.b	d3,d2
		beq.s	.same
		addq.w	#1,d4
		move.b	d2,d7
		addq.b	#1,d7
		cmp.b	d7,d3
		beq.s	.step
		cmpi.w	#6,d5
		bcc.s	.step
		move.b	d2,(a2)+
		move.b	d3,(a2)+
		addq.w	#1,d5
.step:
		move.b	d3,d2
		cmpi.b	#$80,d3
		bne.s	.same
		cmpi.w	#16,d4
		bcc.s	.scanned
.same:
		move.w	4(a6),d7
		move.w	d7,d0
		eor.w	d6,d0
		btst	#3,d0
		beq.s	.no_vb
		btst	#3,d7
		beq.s	.vb_off
		move.b	d2,rVbOn+1
		clr.b	rVbOn
		bra.s	.no_vb
.vb_off:
		move.b	d2,rVbOff+1
		clr.b	rVbOff
.no_vb:
		move.w	d7,d6
		cmp.w	vFrames,d1
		bne.s	.scan
.scanned:
		move.w	d4,rLines
		move.w	d5,rJumpN
		moveq	#0,d0
		move.b	vIntHV,d0
		move.w	d0,rVint

	; V counter read once at a time over a frame: changes that aren't
	; +1, less the true jumps found above, are reads mixing two counts
		bsr.w	WaitFrame
		lea	vFrames,a0
		move.w	(a0),d1
		moveq	#0,d4
		move.b	(a1),d2
.raw:
		move.b	(a1),d3
		cmp.b	d3,d2
		beq.s	.raw_same
		move.b	d2,d7
		addq.b	#1,d7
		cmp.b	d7,d3
		beq.s	.raw_step
		addq.w	#1,d4
.raw_step:
		move.b	d3,d2
.raw_same:
		cmp.w	(a0),d1
		beq.s	.raw
		sub.w	rJumpN,d4
		bcc.s	.torn_ok
		moveq	#0,d4
.torn_ok:
		move.w	d4,rTorn

	; VRAM: 2 KB written by the CPU from line 0, screen on, then off
		lea	rWrOn,a3
		move.w	#$8174,d0
		move.l	#$40000002,d1		; VRAM $8000
		bsr.w	WriteTest
		lea	rWrOff,a3
		move.w	#$8134,d0
		move.l	#$48000002,d1		; VRAM $8800
		bsr.w	WriteTest
		move.w	#$8174,4(a6)
	; and read back
		move.l	#$00000002,d1
		bsr.w	ReadCheck
		move.w	d0,rErrOn
		move.l	#$08000002,d1
		bsr.w	ReadCheck
		move.w	d0,rErrOff

	; DMA: 1 KB from RAM, from line 0, screen on, then off
		lea	(dmaBuf).l,a0
		move.w	#$2468,d1
		move.w	#512-1,d0
.fill:
		move.w	d1,(a0)+
		addi.w	#$1F3B,d1
		dbf	d0,.fill
		move.w	#$8174,d0
		move.l	#$50000082,d1		; VRAM $9000
		bsr.w	DmaTest
		move.w	d0,rDmaOn
		move.w	#$8134,d0
		move.l	#$54000082,d1		; VRAM $9400
		bsr.w	DmaTest
		move.w	d0,rDmaOff
		move.w	#$8174,4(a6)
		move.l	#$10000002,d1
		bsr.w	DmaCheck
		move.w	d0,d4
		move.l	#$14000002,d1
		bsr.w	DmaCheck
		add.w	d4,d0
		move.w	d0,rDmaErr

	; Z80 bus: loops until granted (it's released now)
		move.w	#$100,(z80_bus).l
		moveq	#0,d0
.bus:
		btst	#0,(z80_bus).l
		beq.s	.granted
		addq.w	#1,d0
		cmpi.w	#$FFFF,d0
		bne.s	.bus
.granted:
		move.w	d0,rBus
	; YM2612: status, then loops busy after a register write
		moveq	#0,d0
		move.b	(ym_a0).l,d0
		move.w	d0,rYmSt
		move.b	#$28,(ym_a0).l		; key off, channel 1
		nop
		nop
		move.b	#$00,(ym_d0).l
		moveq	#0,d0
.busy:
		btst	#7,(ym_a0).l
		beq.s	.ready
		addq.w	#1,d0
		cmpi.w	#$FFFF,d0
		bne.s	.busy
.ready:
		move.w	d0,rYmBusy

	; YM2612 timer A as a clock: overflows in 60 frames, one every 64
	; YM samples (1.2 ms on a Mega Drive)
		moveq	#$24,d0
		move.b	#$F0,d1			; timer A = 960
		bsr.w	YmWrite
		moveq	#$25,d0
		moveq	#0,d1
		bsr.w	YmWrite
		moveq	#$27,d0
		moveq	#$15,d1			; start A, flag on, flag clear
		bsr.w	YmWrite
		bsr.w	WaitFrame
		move.w	vFrames,d5
		addi.w	#60,d5
		moveq	#0,d4
.tick:
		btst	#0,(ym_a0).l
		beq.s	.no_tick
		addq.w	#1,d4
		moveq	#$27,d0
		moveq	#$15,d1
		bsr.w	YmWrite
.no_tick:
		cmp.w	vFrames,d5
		bne.s	.tick
		move.w	d4,rTimer
		moveq	#$27,d0
		moveq	#0,d1			; timers off
		bsr.w	YmWrite
		move.w	#0,(z80_bus).l

	; FamiDrive's own measure of lines a frame and each V value's line,
	; as it runs at startup (emu/vlines.asm)
		move.w	#$8144,4(a6)		; display on, no VBlank interrupts
		move.w	#$8A63,4(a6)		; line interrupts every 100 lines
		move.w	#$8014,4(a6)
		move.w	#$2300,sr
		lea	(calTbl).l,a0
		lea	hCount,a1
		jsr	vlMeasure
		move.w	#$2500,sr
		lea	(vdp_data).l,a6
		move.w	#$8004,4(a6)
		move.w	#$8174,4(a6)
		move.w	d0,rCalL
		move.w	d1,rCalRead
		move.w	d7,rCalUnread
		move.w	d2,rCalOdd
		move.w	#$8144,4(a6)		; no VBlank interrupts: VSeq polls the flag
		bsr.w	VSeq
		move.w	#$8174,4(a6)
		rts

; The V counter through VBlank, in order: each change (read twice
; the same) and the turn of a loop it came on, from VBlank's start to
; the next (a frame, to turn turns into lines)
VSeq:
		lea	(vdp_data).l,a6
		lea	(seqBuf).l,a2
		moveq	#0,d4			; changes noted
.off:
		btst	#3,5(a6)
		bne.s	.off
.on:
		btst	#3,5(a6)
		beq.s	.on			; VBlank begins: turn 0
		moveq	#0,d1
		moveq	#0,d5			; VBlank ended yet?
		bsr.w	ReadV
		move.b	d3,d2
		bsr.s	.note
.turn:
		addq.w	#1,d1
		bsr.w	ReadV
		cmp.b	d3,d2
		beq.s	.same
		move.b	d3,d2
		bsr.s	.note
.same:
		btst	#3,5(a6)
		bne.s	.vblank
		moveq	#1,d5
		bra.s	.turn
.vblank:
		tst.w	d5
		beq.s	.turn
		move.w	d1,rSeqFrame		; VBlank again: a frame
		move.w	d4,rSeqN
		rts
.note:
		cmpi.w	#64,d4
		bcc.s	.full
		moveq	#0,d0
		move.b	d2,d0
		move.w	d0,(a2)+
		move.w	d1,(a2)+
		addq.w	#1,d4
.full:
		rts

; d0 - VDP register 1 value, d1 - VRAM write command, a3 - result
WriteTest:
		move.w	d0,4(a6)
		bsr.w	WaitFrame
		moveq	#0,d0
		bsr.w	WaitV
		move.l	d1,4(a6)
		move.w	vFrames,d5
		move.b	(vdp_hv).l,d6
		move.w	#$1357,d1
		move.w	#1024-1,d0
.write:
		move.w	d1,(a6)
		addi.w	#$3B1D,d1
		dbf	d0,.write
		bsr.w	FifoEmpty
		bsr.w	LinesSince
		move.w	d0,(a3)
		rts

FifoEmpty:
		move.w	#$7FFF,d7
.wait:
		btst	#1,4(a6)		; status bit 9: FIFO empty
		dbne	d7,.wait
		rts

; d1 - VRAM read command; d0: words that don't match
ReadCheck:
		move.w	#$8134,4(a6)
		move.l	d1,4(a6)
		move.w	#$1357,d1
		moveq	#0,d2
		move.w	#1024-1,d0
.read:
		cmp.w	(a6),d1
		beq.s	.ok
		addq.w	#1,d2
.ok:
		addi.w	#$3B1D,d1
		dbf	d0,.read
		move.w	#$8174,4(a6)
		move.w	d2,d0
		rts

; d0 - VDP register 1 value, d1 - VRAM DMA command; d0: lines
DmaTest:
		move.w	d0,4(a6)
		bsr.w	WaitFrame
		move.w	#$8F02,4(a6)
		move.w	#$9300,4(a6)		; 512 words
		move.w	#$9402,4(a6)
		move.w	#$9500|((dmaBuf>>1)&$FF),4(a6)
		move.w	#$9600|((dmaBuf>>9)&$FF),4(a6)
		move.w	#$9700|((dmaBuf>>17)&$7F),4(a6)
		moveq	#0,d0
		bsr.w	WaitV
		move.w	vFrames,d5
		move.b	(vdp_hv).l,d6
		move.l	d1,4(a6)
		move.w	#$7FFF,d7
.busy:
		btst	#1,5(a6)		; status bit 1: DMA busy
		dbeq	d7,.busy
		bra.w	LinesSince

DmaCheck:
		move.w	#$8134,4(a6)
		move.l	d1,4(a6)
		move.w	#$2468,d1
		moveq	#0,d2
		move.w	#512-1,d0
.read:
		cmp.w	(a6),d1
		beq.s	.ok
		addq.w	#1,d2
.ok:
		addi.w	#$1F3B,d1
		dbf	d0,.read
		move.w	#$8174,4(a6)
		move.w	d2,d0
		rts

; ====================================================================
; Text
; ====================================================================

; d1 - row, d2 - column: set the VRAM write address in plane A
TextAt:
		move.w	d1,d6
		lsl.w	#6,d6
		add.w	d2,d6
		add.w	d6,d6
		addi.w	#$C000,d6
		moveq	#0,d5
		move.w	d6,d5
		andi.w	#$3FFF,d5
		ori.w	#$4000,d5
		swap	d5
		rol.w	#2,d6
		andi.w	#3,d6
		move.w	d6,d5
		move.l	d5,4(a6)
		rts

; a0 - text, 0-terminated, at d1 row, d2 column
Print:
		lea	(vdp_data).l,a6
		bsr.w	TextAt
.next:
		moveq	#0,d0
		move.b	(a0)+,d0
		beq.s	.done
		subi.w	#$20,d0
		move.w	d0,(a6)
		bra.s	.next
.done:
		rts

; d0 - value, d1 - row, d2 - right end column, d3 - width
PrintDec:
		lea	(vdp_data).l,a6
		movem.w	d1-d3,-(sp)
		sub.w	d3,d2
		addq.w	#1,d2
		bsr.w	TextAt
		movem.w	(sp)+,d1-d3
		andi.l	#$FFFF,d0
		lea	-8(sp),sp
		movea.l	sp,a0
		moveq	#0,d4			; digits
.div:
		divu	#10,d0
		swap	d0
		move.b	d0,(a0)+
		clr.w	d0
		swap	d0
		addq.w	#1,d4
		tst.l	d0
		bne.s	.div
		move.w	d3,d5
		sub.w	d4,d5
		bra.s	.pad_next
.pad:
		move.w	#0,(a6)
.pad_next:
		dbf	d5,.pad
		subq.w	#1,d4
.digit:
		moveq	#'0'-$20,d5
		add.b	-(a0),d5
		move.w	d5,(a6)
		dbf	d4,.digit
		lea	8(sp),sp
		rts

; d0.b as two hex digits at d1 row, d2 column
PrintHex:
		lea	(vdp_data).l,a6
		bsr.w	TextAt
		move.b	d0,d4
		lsr.b	#4,d0
		bsr.w	.nibble
		move.b	d4,d0
.nibble:
		andi.w	#$F,d0
		move.b	HexDigits(pc,d0.w),d0
		subi.w	#$20,d0
		move.w	d0,(a6)
		rts
HexDigits:
		dc.b "0123456789ABCDEF"

; ====================================================================
; Screen
; ====================================================================

DrawStatic:
		lea	(vdp_data).l,a6
		moveq	#0,d1
		moveq	#0,d2
		bsr.w	TextAt
		move.w	#25*64-1,d0
.clear:
		move.w	#0,(a6)
		dbf	d0,.clear
		lea	Rows1(pc),a1
		tst.w	page
		beq.s	.page
		lea	Rows2(pc),a1
.page:
		bsr.s	.rows
		lea	RowsBoth(pc),a1
		bsr.s	.rows
		bra.s	.band
.rows:
		moveq	#0,d1
.row:
		move.b	(a1)+,d1
		bmi.s	.rows_done
		moveq	#0,d2
		movea.l	a1,a0
		bsr.w	Print
		movea.l	a0,a1
		bra.s	.row
.rows_done:
		rts
.band:
	; rows 25-27 of stripes (tile 64)
		moveq	#25,d1
		moveq	#0,d2
		bsr.w	TextAt
		move.w	#3*64-1,d0
.stripes:
		move.w	#64,(a6)
		dbf	d0,.stripes
		rts

; d1 row: value d0 in the THIS column, decimal; $FFFF as "--"
ShowDec:
		cmpi.w	#$FFFF,d0
		beq.s	ShowNone
		move.w	#valCol,d2
		moveq	#5,d3
		bra.w	PrintDec
ShowNone:
		lea	TxtNone(pc),a0
		move.w	#valCol-4,d2
		bra.w	Print
ShowHex:
		cmpi.w	#$FFFF,d0
		beq.s	ShowNone
		move.w	#valCol-1,d2
		bra.w	PrintHex

DrawResults:
		tst.w	page
		bne.w	DrawPage2
		move.w	rVer,d0
		moveq	#3,d1
		bsr.w	ShowHex
		move.w	rCalL,d0
		moveq	#4,d1
		bsr.w	ShowDec
		move.w	rCalRead,d0
		moveq	#5,d1
		bsr.w	ShowDec
		move.w	rCalUnread,d0
		moveq	#6,d1
		bsr.w	ShowHex
		move.w	rCalOdd,d0
		moveq	#7,d1
		bsr.w	ShowDec
	; the first two jumps in the V count, as FROM>TO
		lea	rJumps,a1
		moveq	#8,d1
		move.w	rJumpN,d3
		bsr.w	ShowJump
		moveq	#9,d1
		subq.w	#1,d3
		bsr.w	ShowJump
		move.w	rVint,d0
		moveq	#10,d1
		bsr.w	ShowHex
		move.w	rVbOn,d0
		moveq	#11,d1
		bsr.w	ShowHex
		move.w	rVbOff,d0
		moveq	#12,d1
		bsr.w	ShowHex
		move.w	rTorn,d0
		moveq	#13,d1
		bsr.w	ShowDec

	; VBlank's V values: drop the n+2 of n, n+2, n+1
		lea	(seqBuf).l,a0
		lea	(seqClean).l,a1
		move.w	rSeqN,d7
		moveq	#0,d6			; kept
		moveq	#0,d5			; i
.clean:
		cmp.w	d7,d5
		bcc.s	.cleaned
		move.w	d5,d0
		lsl.w	#2,d0
		move.w	(a0,d0.w),d1		; v[i]
		tst.w	d5
		beq.s	.keep
		move.w	d5,d2
		addq.w	#1,d2
		cmp.w	d7,d2
		bcc.s	.keep
		move.w	-4(a0,d0.w),d2		; v[i-1]
		move.w	4(a0,d0.w),d3		; v[i+1]
		move.b	d2,d4
		addq.b	#2,d4
		cmp.b	d4,d1
		bne.s	.keep
		subq.b	#1,d4
		cmp.b	d4,d3
		beq.s	.drop
.keep:
		move.w	(a0,d0.w),(a1)+
		move.w	2(a0,d0.w),(a1)+
		addq.w	#1,d6
.drop:
		addq.w	#1,d5
		bra.s	.clean
.cleaned:
	; up to 25 as V:LINE, rows 15-23 every other one, five a row
		lea	(seqClean).l,a1
		moveq	#15,d1			; row
		moveq	#1,d2			; column
.entry:
		tst.w	d6
		beq.s	.entries_done
		subq.w	#1,d6
		movem.l	d1-d2/d6/a1,-(sp)
		move.w	(a1),d0
		bsr.w	PrintHex
		move.w	#':'-$20,(a6)
		movem.l	(sp)+,d1-d2/d6/a1
		moveq	#0,d0
		move.w	2(a1),d0		; turns -> lines
		move.w	rCalL,d3
		bne.s	.lines_ok
		move.w	#262,d3
.lines_ok:
		mulu	d3,d0
		move.w	rSeqFrame,d3
		beq.s	.no_frame
		moveq	#0,d4
		move.w	d3,d4
		lsr.w	#1,d4
		add.l	d4,d0
		divu	d3,d0
		bvc.s	.lined
.no_frame:
		moveq	#99,d0
.lined:
		cmpi.w	#99,d0
		bls.s	.two
		moveq	#99,d0
.two:
		movem.l	d1-d2/d6/a1,-(sp)
		addq.w	#4,d2
		moveq	#2,d3
		bsr.w	PrintDec
		movem.l	(sp)+,d1-d2/d6/a1
		addq.l	#4,a1
		addq.w	#6,d2
		cmpi.w	#31,d2
		bcs.s	.entry
		moveq	#1,d2
		addq.w	#2,d1
		cmpi.w	#24,d1
		bcs.s	.entry
.entries_done:
		rts

DrawPage2:
		move.w	rLoops,d0
		moveq	#3,d1
		bsr.w	ShowDec
		move.w	rLinesH,d0
		moveq	#4,d1
		bsr.w	ShowDec
		move.w	rTimer,d0
		moveq	#5,d1
		bsr.w	ShowDec
		lea	rWrOn,a1		; writes, DMA, Z80 bus
		moveq	#6,d1
.dec:
		move.w	(a1)+,d0
		movem.l	d1/a1,-(sp)
		bsr.w	ShowDec
		movem.l	(sp)+,d1/a1
		addq.w	#1,d1
		cmpi.w	#14,d1
		bne.s	.dec
		move.w	rYmSt,d0
		moveq	#14,d1
		bsr.w	ShowHex
		move.w	rYmBusy,d0
		moveq	#15,d1
		bra.w	ShowDec

; d3 - jumps left, a1 - next one, d1 row
ShowJump:
		tst.w	d3
		bgt.s	.jump
		lea	TxtNone(pc),a0
		move.w	#valCol-4,d2
		movem.l	d1/d3/a1,-(sp)
		bsr.w	Print
		movem.l	(sp)+,d1/d3/a1
		rts
.jump:
		movem.l	d1/d3/a1,-(sp)
		move.b	(a1),d0
		move.w	#valCol-4,d2
		bsr.w	PrintHex
		move.w	#'>'-$20,(a6)
		movem.l	(sp)+,d1/d3/a1
		move.b	1(a1),d0
		movem.l	d1/d3/a1,-(sp)
		move.w	#valCol-1,d2
		bsr.w	PrintHex
		movem.l	(sp)+,d1/d3/a1
		addq.l	#2,a1
		rts

TxtNone:
		dc.b "   --",0
		align 2

; row number, then the text; $FF ends. The MD column: a Mega Drive's
; values (BlastEm and Genesis Plus GX agree, give or take one)
Rows1:
		dc.b 0," FAMIDRIVE HARDWARE TEST",0
		dc.b 1," FRAME        L/R: PAGE 1 OF 2",0
		dc.b 2,"                    THIS    MD",0
		dc.b 3," VERSION REG          --    A0",0
		dc.b 4," CAL LINES/FRAME      --   262",0
		dc.b 5," CAL V READ           --   256",0
		dc.b 6," CAL FIRST UNREAD     --    --",0
		dc.b 7," CAL ODD V LINE       --    --",0
		dc.b 8," V JUMP 1             -- EA>E5",0
		dc.b 9," V JUMP 2             --    --",0
		dc.b 10," VINT AT V            --    E0",0
		dc.b 11," VBLANK ON AT V       --    E0",0
		dc.b 12," VBLANK OFF AT V      --    FE",0
		dc.b 13," TORN V READS         --     0",0
		dc.b 14," V IN VBLANK, IN ORDER (V:LINE)",0
		dc.b $FF
Rows2:
		dc.b 0," FAMIDRIVE HARDWARE TEST",0
		dc.b 1," FRAME        L/R: PAGE 2 OF 2",0
		dc.b 2,"                    THIS    MD",0
		dc.b 3," CPU LOOPS/FRAME      --  4840",0
		dc.b 4," LINES BY HINT        --   262",0
		dc.b 5," YM TICKS/60 FR       --   834",0
		dc.b 6," WRITE 2KB ON         --   128",0
		dc.b 7," WRITE 2KB OFF        --    55",0
		dc.b 8," WRITE ERRORS ON      --     0",0
		dc.b 9," WRITE ERRORS OFF     --     0",0
		dc.b 10," DMA 1KB ON           --    64",0
		dc.b 11," DMA 1KB OFF          --     6",0
		dc.b 12," DMA ERRORS           --     0",0
		dc.b 13," Z80 BUS LOOPS        --     0",0
		dc.b 14," YM STATUS            --    00",0
		dc.b 15," YM BUSY LOOPS        --     4",0
		dc.b 17," WRITE, DMA: SCREEN LINES TAKEN.",0
		dc.b 18," ON: WHILE THE SCREEN IS DRAWN.",0
		dc.b 19," YM TICKS: 60 FRAMES TIMED BY",0
		dc.b 20," THE YM2612 (834: 59.9 A SECOND)",0
		dc.b $FF
RowsBoth:
		dc.b 24," A:FM  B:PSG  C:OFF  START:AGAIN",0
		dc.b $FF
		align 2

VdpRegs:
		dc.w $8004		; HInt off, HV counter running
		dc.w $8174		; display on, VInt on, DMA on, mode 5
		dc.w $8230		; plane A $C000
		dc.w $8334		; window $D000
		dc.w $8407		; plane B $E000
		dc.w $855E		; sprites $BC00
		dc.w $8700
		dc.w $8AFF
		dc.w $8B03		; line scroll
		dc.w $8C00		; H32, as FamiDrive
		dc.w $8D2E		; HScroll $B800
		dc.w $8F02
		dc.w $9001		; 64x32
		dc.w $9100
		dc.w $9200
VdpRegsN	equ (*-VdpRegs)/2

; 1bpp 8x8 font, ASCII $20-$5F (FamiDrive's, with '>' and '=')
Font:
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; ' '
		dc.b $10,$10,$10,$10,$10,$00,$10,$00	; '!'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '"'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '#'
		dc.b $10,$3C,$50,$38,$14,$78,$10,$00	; '$'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '%'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '&'
		dc.b $10,$10,$00,$00,$00,$00,$00,$00	; quote
		dc.b $08,$10,$20,$20,$20,$10,$08,$00	; '('
		dc.b $20,$10,$08,$08,$08,$10,$20,$00	; ')'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '*'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '+'
		dc.b $00,$00,$00,$00,$18,$10,$20,$00	; ','
		dc.b $00,$00,$00,$7C,$00,$00,$00,$00	; '-'
		dc.b $00,$00,$00,$00,$00,$30,$30,$00	; '.'
		dc.b $04,$08,$08,$10,$20,$20,$40,$00	; '/'
		dc.b $38,$44,$4C,$54,$64,$44,$38,$00	; '0'
		dc.b $10,$30,$10,$10,$10,$10,$38,$00	; '1'
		dc.b $38,$44,$04,$08,$10,$20,$7C,$00	; '2'
		dc.b $7C,$08,$10,$08,$04,$44,$38,$00	; '3'
		dc.b $08,$18,$28,$48,$7C,$08,$08,$00	; '4'
		dc.b $7C,$40,$78,$04,$04,$44,$38,$00	; '5'
		dc.b $18,$20,$40,$78,$44,$44,$38,$00	; '6'
		dc.b $7C,$04,$08,$10,$20,$20,$20,$00	; '7'
		dc.b $38,$44,$44,$38,$44,$44,$38,$00	; '8'
		dc.b $38,$44,$44,$3C,$04,$08,$30,$00	; '9'
		dc.b $00,$30,$30,$00,$30,$30,$00,$00	; ':'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; ';'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '<'
		dc.b $00,$00,$7C,$00,$7C,$00,$00,$00	; '='
		dc.b $20,$10,$08,$04,$08,$10,$20,$00	; '>'
		dc.b $38,$44,$04,$08,$10,$00,$10,$00	; '?'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '@'
		dc.b $38,$44,$44,$7C,$44,$44,$44,$00	; 'A'
		dc.b $78,$44,$44,$78,$44,$44,$78,$00	; 'B'
		dc.b $38,$44,$40,$40,$40,$44,$38,$00	; 'C'
		dc.b $70,$48,$44,$44,$44,$48,$70,$00	; 'D'
		dc.b $7C,$40,$40,$78,$40,$40,$7C,$00	; 'E'
		dc.b $7C,$40,$40,$78,$40,$40,$40,$00	; 'F'
		dc.b $38,$44,$40,$5C,$44,$44,$3C,$00	; 'G'
		dc.b $44,$44,$44,$7C,$44,$44,$44,$00	; 'H'
		dc.b $38,$10,$10,$10,$10,$10,$38,$00	; 'I'
		dc.b $1C,$08,$08,$08,$08,$48,$30,$00	; 'J'
		dc.b $44,$48,$50,$60,$50,$48,$44,$00	; 'K'
		dc.b $40,$40,$40,$40,$40,$40,$7C,$00	; 'L'
		dc.b $44,$6C,$54,$54,$44,$44,$44,$00	; 'M'
		dc.b $44,$44,$64,$54,$4C,$44,$44,$00	; 'N'
		dc.b $38,$44,$44,$44,$44,$44,$38,$00	; 'O'
		dc.b $78,$44,$44,$78,$40,$40,$40,$00	; 'P'
		dc.b $38,$44,$44,$44,$54,$48,$34,$00	; 'Q'
		dc.b $78,$44,$44,$78,$50,$48,$44,$00	; 'R'
		dc.b $3C,$40,$40,$38,$04,$04,$78,$00	; 'S'
		dc.b $7C,$10,$10,$10,$10,$10,$10,$00	; 'T'
		dc.b $44,$44,$44,$44,$44,$44,$38,$00	; 'U'
		dc.b $44,$44,$44,$44,$44,$28,$10,$00	; 'V'
		dc.b $44,$44,$44,$54,$54,$54,$28,$00	; 'W'
		dc.b $44,$44,$28,$10,$28,$44,$44,$00	; 'X'
		dc.b $44,$44,$28,$10,$10,$10,$10,$00	; 'Y'
		dc.b $7C,$04,$08,$10,$20,$40,$7C,$00	; 'Z'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '['
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '\'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; ']'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '^'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '_'

		include	"emu/vlines.asm"	; FamiDrive's own (built from the top folder)

		org $1FFFE
		dc.w 0
EndOfRom:
