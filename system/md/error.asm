; ====================================================================
; ----------------------------------------------------------------
; Error screen
;
; Shows a message on a blank screen and stops. Used for ROMs the
; emulator can't run and for 68000 exceptions.
; ----------------------------------------------------------------

errTileBase	equ $200		; font tile for ' ', after the NES CHR tiles
errPlaneA	equ $C000

; --------------------------------------------------------
; MD_ShowError
;
; a0 - message: uppercase ASCII, 0-terminated.
;      $0A starts a new line (one blank row between),
;      '%' prints d1.b in decimal
; d1 - value for '%'
; --------------------------------------------------------

MD_ShowError:
		move.w	#$2700,sr
		suba.l	sp,sp			; the stack may be what broke
		lea	(vdp_data).l,a6
		lea	errVdpRegs(pc),a5
		moveq	#((errVdpRegs_end-errVdpRegs)/2)-1,d7
.regs:
		move.w	(a5)+,4(a6)
		dbf	d7,.regs

		move.l	#$C0000000,4(a6)	; black background, white text
		move.w	#$000,(a6)
		move.w	#$EEE,(a6)
		move.l	#$40000010,4(a6)	; no scrolling
		move.l	#0,(a6)
		move.l	#$78000002,4(a6)	; VRAM $B800: H scroll
		move.l	#0,(a6)
		move.l	#$7C000002,4(a6)	; VRAM $BC00: one hidden sprite
		move.l	#0,(a6)
		move.l	#0,(a6)

	; 1bpp font -> 4bpp tiles at VRAM $4000
		move.l	#$40000001,4(a6)
		lea	errFont(pc),a5
		move.w	#(64*8)-1,d7
.font:
		move.b	(a5)+,d5
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

	; clear the planes ($C000-$FFFF)
		move.l	#$40000003,4(a6)
		move.w	#$2000-1,d7
.clear:
		move.w	#errTileBase,(a6)
		dbf	d7,.clear

	; print
		move.w	#((10*64)+2)*2,d2	; row 10, column 2
.newline:
		bsr.s	.setaddr
.next:
		moveq	#0,d5
		move.b	(a0)+,d5
		beq.s	.done
		cmpi.b	#$0A,d5
		bne.s	.not_nl
		addi.w	#64*2*2,d2
		bra.s	.newline
.not_nl:
		cmpi.b	#'%',d5
		beq.s	.number
		addi.w	#errTileBase-$20,d5
		move.w	d5,(a6)
		bra.s	.next
.done:
		bra.s	.done

.number:
		moveq	#0,d4
		move.b	d1,d4
		moveq	#0,d6
.div:
		divu	#10,d4
		swap	d4
		move.w	d4,-(sp)		; digits, lowest first
		clr.w	d4
		swap	d4
		addq.w	#1,d6
		tst.w	d4
		bne.s	.div
		subq.w	#1,d6
.digit:
		move.w	(sp)+,d5
		addi.w	#errTileBase-$20+'0',d5
		move.w	d5,(a6)
		dbf	d6,.digit
		bra.s	.next

; d2 - offset in plane A
.setaddr:
		move.w	d2,d4
		addi.w	#errPlaneA,d4
		moveq	#0,d5
		move.w	d4,d5
		andi.w	#$3FFF,d5
		ori.w	#$4000,d5
		swap	d5
		rol.w	#2,d4
		andi.w	#3,d4
		move.w	d4,d5
		move.l	d5,4(a6)
		rts

; ----------------------------------------------------------------

errVdpRegs:
		dc.w $8004			; no H interrupt
		dc.w $8144			; display on, no V interrupt
		dc.w $8200|(errPlaneA>>10)	; plane A at $C000
		dc.w $8334			; window at $D000
		dc.w $8407			; plane B at $E000
		dc.w $855E			; sprites at $BC00
		dc.w $8700			; background color 0
		dc.w $8B00			; full screen scrolling
		dc.w $8C81			; H40
		dc.w $8D2E			; H scroll at $B800
		dc.w $8F02			; auto-increment 2
		dc.w $9001			; 64x32 planes
		dc.w $9100			; no window
		dc.w $9200
errVdpRegs_end:

errStrException:
		dc.b "68000 EXCEPTION",0
errStrBadHeader:
		dc.b "NOT AN INES ROM (BAD HEADER)",0
errStrMapper:
		dc.b "MAPPER % IS NOT SUPPORTED",$0A
		dc.b "SUPPORTED: 0 (NROM), 3 (CNROM)",0
errStrPrgSize:
		dc.b "% X 16 KB PRG-ROM IS NOT SUPPORTED",$0A
		dc.b "SUPPORTED: 16 KB OR 32 KB",0
		align 2

; 1bpp 8x8 font, ASCII $20-$5F
errFont:
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; ' '
		dc.b $10,$10,$10,$10,$10,$00,$10,$00	; '!'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '"'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '#'
		dc.b $10,$3C,$50,$38,$14,$78,$10,$00	; '$'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '%'
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '&'
		dc.b $10,$10,$00,$00,$00,$00,$00,$00	; 'quote'
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
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '='
		dc.b $00,$00,$00,$00,$00,$00,$00,$00	; '>'
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
