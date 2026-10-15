; ====================================================================
; ----------------------------------------------------------------
; FPS counter (build.sh --recompile --fps)
;
; Shows how many frames per second the game finishes, in the top
; right corner. X, Y or Z on a 6-button pad hides or shows it.
;
; A game ends each frame in a small loop that waits for VBlank (or
; for its NMI handler to set a flag). tools/recomp6502.py finds those
; loops and counts in fpsIdle each time one is left, which happens once
; per frame whether the game had to wait or was late. A game that runs
; entirely in its NMI handler sits in a JMP to itself instead: there
; rcNmiIdle counts the NMIs. Every 60 VBlanks fpsShow gets the count.
;
; While a game polls something without waiting for VBlank (Pinball
; waiting for the ball launch) its frames don't advance: it shows 0.
;
; The digits are two sprites. The MD has only 64 sprites in this
; video mode and NES games use all 64, so while the counter is shown
; it takes the last two NES sprite slots.
; ----------------------------------------------------------------

fpsTiles	equ $201			; digit tiles, after the blank tile $200
fpsSprite	equ 62				; first sprite slot used
fpsX		equ $80+256-8-16		; MD sprite coordinates
fpsY		equ $80+8

; ----------------------------------------------------------------
; Load the digit tiles and their colors, counter on
;
; a4 - emulator variables, a6 - VDP data port
; ----------------------------------------------------------------

fpsInit:
		move.l	#$40000000|(((fpsTiles*32)&$3FFF)<<16)|((fpsTiles*32)>>14),4(a6)
		lea	fpsFont(pc),a5
		moveq	#(10*8)-1,d6
.row:
		move.b	(a5)+,d5			; 1 bit per pixel -> color 15 on 14
		moveq	#0,d4
		moveq	#8-1,d7
.pixel:
		lsl.l	#4,d4
		addi.b	#$E,d4
		add.b	d5,d5
		bcc.s	.dark
		addq.b	#1,d4
.dark:
		dbf	d7,.pixel
		move.l	d4,(a6)
		dbf	d6,.row
		lea	vdpSprData+2(a4),a5		; link the empty sprite lists
		bsr.s	.links				; (both tables) so they reach
		lea	vdpSprData2+2(a4),a5		; the counter's slots before the
		bsr.s	.links				; game's first OAM DMA
		move.w	#$0000,vdpPalette+14*2(a4)	; colors 14 and 15 of the
		move.w	#$0EEE,vdpPalette+15*2(a4)	; first line: NES colors don't use them
		st	vdpPalDirty(a4)
		move.w	#1,fpsOn(a4)
		rts

.links:
		moveq	#1,d4
		moveq	#fpsSprite-1,d7
.link:
		move.w	d4,(a5)
		addq.w	#8,a5
		addq.w	#1,d4
		dbf	d7,.link
		rts

; ----------------------------------------------------------------
; Once per frame from MD_Vint, before the sprite table goes to VRAM:
; count the second and put the digits in the sprite table
;
; a0 - the sprite table MD_Vint shows (vdpSprData or vdpSprData2)
; ----------------------------------------------------------------

fpsUpdate:
		addq.w	#1,fpsTick(a4)
		cmpi.w	#60,fpsTick(a4)
		bcs.s	.draw
		clr.w	fpsTick(a4)
		move.w	fpsIdle(a4),fpsShow(a4)
		clr.w	fpsIdle(a4)
.draw:
		tst.w	fpsOn(a4)
		beq.s	.off
		lea	fpsSprite*8(a0),a5
		moveq	#0,d4
		move.w	fpsShow(a4),d4
		cmpi.w	#60,d4				; two wait loops can end in one frame
		bls.s	.max_60
		moveq	#60,d4
.max_60:
		divu.w	#10,d4				; tens, ones in the high word
		move.w	#fpsY,(a5)+
		move.w	#fpsSprite+1,(a5)+		; 8x8, link to the next one
		addi.w	#$8000|fpsTiles,d4		; high priority, first palette line
		move.w	d4,(a5)+
		move.w	#fpsX,(a5)+
		swap	d4
		move.w	#fpsY,(a5)+
		move.w	#0,(a5)+			; 8x8, the end of the list
		addi.w	#$8000|fpsTiles,d4
		move.w	d4,(a5)+
		move.w	#fpsX+8,(a5)+
		move.w	#1,fpsWasOn(a4)
		rts
.off:
		tst.w	fpsWasOn(a4)			; just hidden: clear the two
		beq.s	.done				; slots until the game rewrites them
		clr.w	fpsWasOn(a4)
		lea	vdpSprData+fpsSprite*8(a4),a5	; (both tables: one still
		bsr.s	.hide				; links to the counter until
		lea	vdpSprData2+fpsSprite*8(a4),a5	; the game's next OAM DMA)
.hide:
		move.w	#0,(a5)				; above the screen
		move.w	#fpsSprite+1,2(a5)
		move.w	#0,8(a5)
		move.w	#0,10(a5)
.done:
		rts

; ----------------------------------------------------------------
; Pad 1's X Y Z buttons, right after readInput's first TH cycle
;
; A 6-button pad answers with its extra buttons on the fourth TH
; cycle within about 1.5 ms. This runs once a frame, from MD_Vint, so
; the pad's counter has always reset before the next readInput.
;
; a3 - pad 1 data port
; ----------------------------------------------------------------

readXyz:
		move.b	#0,(a3)				; second cycle
		nop
		nop
		move.b	#$40,(a3)
		nop
		nop
		move.b	#0,(a3)				; third: a 6-button pad reads 0000
		nop
		nop
		move.b	(a3),d4
		move.b	#$40,(a3)			; fourth: Mode X Y Z in bits 3-0
		nop
		nop
		move.b	(a3),d5
		move.b	#0,(a3)
		nop
		nop
		move.b	#$40,(a3)
		andi.b	#$0F,d4
		beq.s	.six
		moveq	#0,d5				; 3-button pad
		bra.s	.got
.six:
		not.b	d5
		andi.w	#7,d5				; X Y Z, 1 = pressed
.got:
		move.w	padXyz(a4),d4
		move.w	d5,padXyz(a4)
		not.w	d4
		and.w	d4,d5				; just pressed
		beq.s	.same
		eori.w	#1,fpsOn(a4)
.same:
		rts

; ----------------------------------------------------------------
; Digits 0-9, 8x8, one byte per row (bit 7 = left)
; ----------------------------------------------------------------

fpsFont:
		dc.b $00,$1C,$22,$26,$2A,$32,$22,$1C	; 0
		dc.b $00,$08,$18,$08,$08,$08,$08,$1C	; 1
		dc.b $00,$1C,$22,$02,$04,$08,$10,$3E	; 2
		dc.b $00,$3E,$04,$08,$04,$02,$22,$1C	; 3
		dc.b $00,$04,$0C,$14,$24,$3E,$04,$04	; 4
		dc.b $00,$3E,$20,$3C,$02,$02,$22,$1C	; 5
		dc.b $00,$0C,$10,$20,$3C,$22,$22,$1C	; 6
		dc.b $00,$3E,$02,$04,$08,$10,$10,$10	; 7
		dc.b $00,$1C,$22,$22,$1C,$22,$22,$1C	; 8
		dc.b $00,$1C,$22,$22,$1E,$02,$04,$18	; 9
		align 2
