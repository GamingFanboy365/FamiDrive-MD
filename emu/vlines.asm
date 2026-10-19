; ====================================================================
; ----------------------------------------------------------------
; Lines a frame, and the line each V counter value means
;
; A Mega Drive draws 262 lines a frame (NTSC). A clone can draw a
; different number: an AtGames handheld draws 246, and its V counter
; reads a line ahead for a moment as it changes. ppuClock counts the
; lines since VBlank began from the V counter, so it takes both from
; here.
;
; A loop that takes the same time each turn runs from VBlank's start
; to the next, noting the turn it last read each V value on: the end
; of its line. Line interrupts every 100 lines time a line: the two
; in the frame are 100 lines apart. (Not the gap from one frame's
; last to the next's first: emulators reload the line counter in
; VBlank differently.) Lines are counted from a change of the V
; counter, VBlank's second line, as the VBlank flag needn't change
; where the V counter does in a line.
;
; a0 - table: 256 words, for each V value the lines since VBlank
;      began; a value never read gets the one before's + 1
; a1 - word the line interrupt handler adds 1 to
; a6 - VDP data port
; Line interrupts every 100 lines on, VBlank interrupts off, the
; display on (so the VBlank flag is VBlank's), and the interrupt
; mask 3 or lower.
;
; Returns d0.w: lines a frame (0: it couldn't tell), d1.w: V values
; read in the frame, d7.w: the first value from $E0 on never read
; ($FFFF: none). Uses d0-d7, a2-a3, a5.
; ----------------------------------------------------------------

vlMeasure:
		movea.l	a0,a2
		move.w	#256-1,d0
.clear:
		move.w	#$FFFF,(a2)+		; never read
		dbf	d0,.clear
		lea	8(a6),a3		; V counter
		lea	4(a6),a5		; status: the VBlank flag
		subq.l	#6,sp			; the frame's two line interrupts, and
		moveq	#0,d1			; V as VBlank begins
.sync:
		bsr.w	.wait			; to VBlank's start
		bcs.w	.fail
		tst.w	d0
		beq.s	.sync
		tst.w	d6
		beq.s	.sync
		move.w	d1,d4			; d4: VBlank began
		moveq	#0,d0
		move.b	(a3),d0
		move.w	d0,4(sp)
		moveq	#0,d5			; line interrupts
.frame:
		bsr.w	.wait
		bcs.w	.fail
		tst.w	d0
		bne.s	.flag
		cmpi.w	#2,d5
		bcc.s	.frame
		add.w	d5,d5
		move.w	d1,(sp,d5.w)
		lsr.w	#1,d5
		addq.w	#1,d5
		bra.s	.frame
.flag:
		tst.w	d6
		beq.s	.frame			; VBlank ended
		cmpi.w	#2,d5			; it began again: a frame
		bcs.w	.fail
		move.w	d1,d5
		sub.w	d4,d5			; d5: turns a frame
		move.w	2(sp),d2
		sub.w	(sp),d2			; d2: turns in 100 lines
		beq.w	.fail
		moveq	#0,d0
		move.w	d5,d0
		mulu	#100,d0
		move.w	d2,d3
		lsr.w	#1,d3
		add.l	d3,d0
		divu	d2,d0			; lines a frame, rounded
		bvs.w	.fail
		move.w	d0,d6			; d6: lines a frame

	; Lines are timed from the end of VBlank's second line, not from
	; the VBlank flag: the flag needn't change where the V counter
	; does in a line. That line's value is the one read last soonest,
	; but for the value VBlank began with (read again at the end).
		move.w	4(sp),d3
		movea.l	a0,a2
		move.w	#$FFFF,d0
		moveq	#0,d7
.ref:
		move.w	(a2)+,d1
		cmp.w	d3,d7
		beq.s	.ref_next
		cmp.w	d4,d1
		bcs.s	.ref_next		; (read before the frame timed)
		cmp.w	d0,d1
		bcc.s	.ref_next
		move.w	d1,d0
.ref_next:
		addq.w	#1,d7
		cmpi.w	#256,d7
		bne.s	.ref
		cmpi.w	#$FFFF,d0
		beq.w	.fail
		move.w	d0,d2			; d2: when line 1 ended

	; each value read: line 1 + whole lines from there to the end of
	; its line, rounded
		move.w	d5,d0
		lsr.w	#1,d0
		movea.w	d0,a3			; half a frame's turns: half a line x lines
		movea.l	a0,a2
		moveq	#0,d1			; values read
		move.w	#256-1,d7
.line:
		move.w	(a2),d0
		cmpi.w	#$FFFF,d0
		beq.s	.unread
		cmp.w	d4,d0
		bcs.s	.unread			; read before the frame timed
		addq.w	#1,d1
		sub.w	d2,d0
		bcc.s	.after
		moveq	#0,d0			; (the value VBlank began with: below)
.after:
		mulu	d6,d0
		add.l	a3,d0
		divu	d5,d0
		addq.w	#1,d0
		cmp.w	d6,d0
		bcs.s	.in_frame
		sub.w	d6,d0			; (the next VBlank's first line)
		cmp.w	d6,d0
		bcs.s	.in_frame
		move.w	d6,d0
		subq.w	#1,d0
.in_frame:
		move.w	d0,(a2)+
		dbf	d7,.line
		bra.s	.fill
.unread:
		move.w	#$FFFF,(a2)+
		dbf	d7,.line

	; V as VBlank began is its first line, though read again as the
	; next one began
.fill:
		move.w	4(sp),d3
		add.w	d3,d3
		clr.w	(a0,d3.w)

	; values never read: the one before's line + 1
		moveq	#-1,d7
		move.w	#$E0*2,d3
		move.w	(a0,d3.w),d0
		cmpi.w	#$FFFF,d0
		bne.s	.fill_from
		moveq	#0,d0			; ($E0 is VBlank's first line on a
		move.w	d0,(a0,d3.w)		; Mega Drive)
		move.w	#$E0,d7
.fill_from:
		move.w	#255-1,d4
.fill_next:
		addq.w	#2,d3
		andi.w	#$1FE,d3
		cmpi.w	#$FFFF,(a0,d3.w)
		bne.s	.fill_read
		tst.w	d7
		bpl.s	.fill_line
		move.w	d3,d7
		lsr.w	#1,d7			; the first one
.fill_line:
		addq.w	#1,d0
		cmp.w	d6,d0
		bcs.s	.fill_set
		move.w	d6,d0
		subq.w	#1,d0
.fill_set:
		move.w	d0,(a0,d3.w)
		bra.s	.fill_on
.fill_read:
		move.w	(a0,d3.w),d0
.fill_on:
		dbf	d4,.fill_next
		addq.l	#6,sp
		move.w	d6,d0
		rts

.fail:
		addq.l	#6,sp
		moveq	#0,d0
		moveq	#0,d1
		moveq	#-1,d7
		rts

; Turns of the loop to the next event, each noting the V value it
; read: d0 = 0, a line interrupt; d0 = 1, the VBlank flag changed
; (d6: it now, 8 or 0). cs: neither came. d1: turns; d2-d3 used
.wait:
		move.w	(a1),d2
		moveq	#8,d6
		and.w	(a5),d6
.turn:
		moveq	#0,d3
		move.b	(a3),d3
		add.w	d3,d3
		move.w	d1,(a0,d3.w)
		addq.w	#1,d1
		beq.s	.none
		moveq	#8,d3
		and.w	(a5),d3
		cmp.w	d3,d6
		bne.s	.vblank
		cmp.w	(a1),d2
		beq.s	.turn
		moveq	#0,d0			; (and carry clear)
		rts
.vblank:
		move.w	d3,d6
		moveq	#1,d0
		rts
.none:
		ori	#1,ccr
		rts
