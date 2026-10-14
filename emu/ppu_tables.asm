; ====================================================================
; ----------------------------------------------------------------
; PPU lookup tables (used by ppu.asm). Kept at the end
; of the code: they're big, and would put branches between the
; routines around them out of range.
; ----------------------------------------------------------------

; ----------------------------------------------------------------
; For each nametable byte ($2000-$2FFF, 8 bytes each):
;
; long - VDP command to write its cell on the MD planes (plane A:
;        nametables 0, 1; plane B: 2, 3; 1 and 3 in the right half),
;        or 0 for an attribute byte
; word - the address of the attribute byte for the cell
; word - which of its 2-bit fields: offset of the ppuAttrPal table
;        for it / 2
; ----------------------------------------------------------------

ppuCellTbl:
ppuCellI	set 0
		rept 4096
ppuCellO	set ppuCellI&$3FF
		if ppuCellO<$3C0
		dc.l	$40000003|((((ppuCellI&$800)<<2)|((ppuCellI&$400)>>4)|((ppuCellO&$3E0)<<2)|((ppuCellO&$1F)<<1))<<16)
		dc.w	$2000|(ppuCellI&$C00)|$3C0|((ppuCellO>>4)&$38)|((ppuCellO>>2)&7)
		dc.w	(((ppuCellO>>5)&2)|((ppuCellO>>1)&1))<<8
		else
		dc.l	0
		dc.w	0,0
		endif
ppuCellI	set ppuCellI+1
		endm

; ----------------------------------------------------------------
; Attribute byte -> MD cell bits (high priority, palette) for each
; of its four 2-bit fields: 4 tables of 256 words
; ----------------------------------------------------------------

ppuAttrPal:
ppuAttrI	set 0
		rept 1024
		dc.w	$8000|((((ppuAttrI&$FF)>>((ppuAttrI>>8)*2))&3)<<13)
ppuAttrI	set ppuAttrI+1
		endm

; ----------------------------------------------------------------
; NES pattern byte (one bit plane of a tile row) -> its 8 bits, one
; per nibble of an MD tile row, left pixel in the top nibble
; (Nemul_LoadChr)
; ----------------------------------------------------------------

ppuChrSpread:
ppuSpreadI	set 0
		rept 256
		dc.l	((ppuSpreadI&$80)<<21)|((ppuSpreadI&$40)<<18)|((ppuSpreadI&$20)<<15)|((ppuSpreadI&$10)<<12)|((ppuSpreadI&8)<<9)|((ppuSpreadI&4)<<6)|((ppuSpreadI&2)<<3)|(ppuSpreadI&1)
ppuSpreadI	set ppuSpreadI+1
		endm
