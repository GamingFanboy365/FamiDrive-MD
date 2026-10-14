; ====================================================================
; ----------------------------------------------------------------
; 6502 CPU
;
; mosCpu is the opcode jump table, one handler per opcode.
; emuVint in md.asm dispatches into it with an 8-bit PC-relative
; jump, so this file must be included right after it. Register
; use is described above emuLoop.
; ----------------------------------------------------------------

; ----------------------------------------------------------------
mosCpu:		dc.w mos_BRK-mosCpu	; $00
		dc.w mos_ORA_indx-mosCpu	; $01
		dc.w mos_Null-mosCpu	; $02
		dc.w mos_Null-mosCpu	; $03
		dc.w mos_Null-mosCpu	; $04
		dc.w mos_ORA_zp-mosCpu	; $05
		dc.w mos_ASL_zp-mosCpu	; $06
		dc.w mos_Null-mosCpu	; $07
		dc.w mos_PHP-mosCpu	; $08
		dc.w mos_ORA_imm-mosCpu	; $09
		dc.w mos_ASL_acc-mosCpu	; $0A
		dc.w mos_Null-mosCpu	; $0B
		dc.w mos_Null-mosCpu	; $0C
		dc.w mos_ORA_abs-mosCpu	; $0D
		dc.w mos_ASL_abs-mosCpu	; $0E
		dc.w mos_Null-mosCpu	; $0F
		dc.w mos_BPL-mosCpu	; $10
		dc.w mos_ORA_indy-mosCpu	; $11
		dc.w mos_Null-mosCpu	; $12
		dc.w mos_Null-mosCpu	; $13
		dc.w mos_Null-mosCpu	; $14
		dc.w mos_ORA_zpx-mosCpu	; $15
		dc.w mos_ASL_zpx-mosCpu	; $16
		dc.w mos_Null-mosCpu	; $17
		dc.w mos_CLC-mosCpu	; $18
		dc.w mos_ORA_absy-mosCpu	; $19
		dc.w mos_Null-mosCpu	; $1A
		dc.w mos_Null-mosCpu	; $1B
		dc.w mos_Null-mosCpu	; $1C
		dc.w mos_ORA_absx-mosCpu	; $1D
		dc.w mos_ASL_absx-mosCpu	; $1E
		dc.w mos_Null-mosCpu	; $1F
		dc.w mos_JSR-mosCpu	; $20
		dc.w mos_AND_indx-mosCpu	; $21
		dc.w mos_Null-mosCpu	; $22
		dc.w mos_Null-mosCpu	; $23
		dc.w mos_BIT_zp-mosCpu	; $24
		dc.w mos_AND_zp-mosCpu	; $25
		dc.w mos_ROL_zp-mosCpu	; $26
		dc.w mos_Null-mosCpu	; $27
		dc.w mos_PLP-mosCpu	; $28
		dc.w mos_AND_imm-mosCpu	; $29
		dc.w mos_ROL_acc-mosCpu	; $2A
		dc.w mos_Null-mosCpu	; $2B
		dc.w mos_BIT_abs-mosCpu	; $2C
		dc.w mos_AND_abs-mosCpu	; $2D
		dc.w mos_ROL_abs-mosCpu	; $2E
		dc.w mos_Null-mosCpu	; $2F
		dc.w mos_BMI-mosCpu	; $30
		dc.w mos_AND_indy-mosCpu	; $31
		dc.w mos_Null-mosCpu	; $32
		dc.w mos_Null-mosCpu	; $33
		dc.w mos_Null-mosCpu	; $34
		dc.w mos_AND_zpx-mosCpu	; $35
		dc.w mos_ROL_zpx-mosCpu	; $36
		dc.w mos_Null-mosCpu	; $37
		dc.w mos_SEC-mosCpu	; $38
		dc.w mos_AND_absy-mosCpu	; $39
		dc.w mos_Null-mosCpu	; $3A
		dc.w mos_Null-mosCpu	; $3B
		dc.w mos_Null-mosCpu	; $3C
		dc.w mos_AND_absx-mosCpu	; $3D
		dc.w mos_ROL_absx-mosCpu	; $3E
		dc.w mos_Null-mosCpu	; $3F
		dc.w mos_RTI-mosCpu	; $40
		dc.w mos_EOR_indx-mosCpu	; $41
		dc.w mos_Null-mosCpu	; $42
		dc.w mos_Null-mosCpu	; $43
		dc.w mos_Null-mosCpu	; $44
		dc.w mos_EOR_zp-mosCpu	; $45
		dc.w mos_LSR_zp-mosCpu	; $46
		dc.w mos_Null-mosCpu	; $47
		dc.w mos_PHA-mosCpu	; $48
		dc.w mos_EOR_imm-mosCpu	; $49
		dc.w mos_LSR_acc-mosCpu	; $4A
		dc.w mos_Null-mosCpu	; $4B
		dc.w mos_JMP_abs-mosCpu	; $4C
		dc.w mos_EOR_abs-mosCpu	; $4D
		dc.w mos_LSR_abs-mosCpu	; $4E
		dc.w mos_Null-mosCpu	; $4F
		dc.w mos_BVC-mosCpu	; $50
		dc.w mos_EOR_indy-mosCpu	; $51
		dc.w mos_Null-mosCpu	; $52
		dc.w mos_Null-mosCpu	; $53
		dc.w mos_Null-mosCpu	; $54
		dc.w mos_EOR_zpx-mosCpu	; $55
		dc.w mos_LSR_zpx-mosCpu	; $56
		dc.w mos_Null-mosCpu	; $57
		dc.w mos_CLI-mosCpu	; $58
		dc.w mos_EOR_absy-mosCpu	; $59
		dc.w mos_Null-mosCpu	; $5A
		dc.w mos_Null-mosCpu	; $5B
		dc.w mos_Null-mosCpu	; $5C
		dc.w mos_EOR_absx-mosCpu	; $5D
		dc.w mos_LSR_absx-mosCpu	; $5E
		dc.w mos_Null-mosCpu	; $5F
		dc.w mos_RTS-mosCpu	; $60
		dc.w mos_ADC_indx-mosCpu	; $61
		dc.w mos_Null-mosCpu	; $62
		dc.w mos_Null-mosCpu	; $63
		dc.w mos_Null-mosCpu	; $64
		dc.w mos_ADC_zp-mosCpu	; $65
		dc.w mos_ROR_zp-mosCpu	; $66
		dc.w mos_Null-mosCpu	; $67
		dc.w mos_PLA-mosCpu	; $68
		dc.w mos_ADC_imm-mosCpu	; $69
		dc.w mos_ROR_acc-mosCpu	; $6A
		dc.w mos_Null-mosCpu	; $6B
		dc.w mos_JMP_ind-mosCpu	; $6C
		dc.w mos_ADC_abs-mosCpu	; $6D
		dc.w mos_ROR_abs-mosCpu	; $6E
		dc.w mos_Null-mosCpu	; $6F
		dc.w mos_BVS-mosCpu	; $70
		dc.w mos_ADC_indy-mosCpu	; $71
		dc.w mos_Null-mosCpu	; $72
		dc.w mos_Null-mosCpu	; $73
		dc.w mos_Null-mosCpu	; $74
		dc.w mos_ADC_zpx-mosCpu	; $75
		dc.w mos_ROR_zpx-mosCpu	; $76
		dc.w mos_Null-mosCpu	; $77
		dc.w mos_SEI-mosCpu	; $78
		dc.w mos_ADC_absy-mosCpu	; $79
		dc.w mos_Null-mosCpu	; $7A
		dc.w mos_Null-mosCpu	; $7B
		dc.w mos_Null-mosCpu	; $7C
		dc.w mos_ADC_absx-mosCpu	; $7D
		dc.w mos_ROR_absx-mosCpu	; $7E
		dc.w mos_Null-mosCpu	; $7F
		dc.w mos_Null-mosCpu	; $80
		dc.w mos_STA_indx-mosCpu	; $81
		dc.w mos_Null-mosCpu	; $82
		dc.w mos_Null-mosCpu	; $83
		dc.w mos_STY_zp-mosCpu	; $84
		dc.w mos_STA_zp-mosCpu	; $85
		dc.w mos_STX_zp-mosCpu	; $86
		dc.w mos_Null-mosCpu	; $87
		dc.w mos_DEY-mosCpu	; $88
		dc.w mos_Null-mosCpu	; $89
		dc.w mos_TXA-mosCpu	; $8A
		dc.w mos_Null-mosCpu	; $8B
		dc.w mos_STY_abs-mosCpu	; $8C
		dc.w mos_STA_abs-mosCpu	; $8D
		dc.w mos_STX_abs-mosCpu	; $8E
		dc.w mos_Null-mosCpu	; $8F
		dc.w mos_BCC-mosCpu	; $90
		dc.w mos_STA_indy-mosCpu	; $91
		dc.w mos_Null-mosCpu	; $92
		dc.w mos_Null-mosCpu	; $93
		dc.w mos_STY_zpx-mosCpu	; $94
		dc.w mos_STA_zpx-mosCpu	; $95
		dc.w mos_STX_zpy-mosCpu	; $96
		dc.w mos_Null-mosCpu	; $97
		dc.w mos_TYA-mosCpu	; $98
		dc.w mos_STA_absy-mosCpu	; $99
		dc.w mos_TXS-mosCpu	; $9A
		dc.w mos_Null-mosCpu	; $9B
		dc.w mos_Null-mosCpu	; $9C
		dc.w mos_STA_absx-mosCpu	; $9D
		dc.w mos_Null-mosCpu	; $9E
		dc.w mos_Null-mosCpu	; $9F
		dc.w mos_LDY_imm-mosCpu	; $A0
		dc.w mos_LDA_indx-mosCpu	; $A1
		dc.w mos_LDX_imm-mosCpu	; $A2
		dc.w mos_Null-mosCpu	; $A3
		dc.w mos_LDY_zp-mosCpu	; $A4
		dc.w mos_LDA_zp-mosCpu	; $A5
		dc.w mos_LDX_zp-mosCpu	; $A6
		dc.w mos_Null-mosCpu	; $A7
		dc.w mos_TAY-mosCpu	; $A8
		dc.w mos_LDA_imm-mosCpu	; $A9
		dc.w mos_TAX-mosCpu	; $AA
		dc.w mos_Null-mosCpu	; $AB
		dc.w mos_LDY_abs-mosCpu	; $AC
		dc.w mos_LDA_abs-mosCpu	; $AD
		dc.w mos_LDX_abs-mosCpu	; $AE
		dc.w mos_Null-mosCpu	; $AF
		dc.w mos_BCS-mosCpu	; $B0
		dc.w mos_LDA_indy-mosCpu	; $B1
		dc.w mos_Null-mosCpu	; $B2
		dc.w mos_Null-mosCpu	; $B3
		dc.w mos_LDY_zpx-mosCpu	; $B4
		dc.w mos_LDA_zpx-mosCpu	; $B5
		dc.w mos_LDX_zpy-mosCpu	; $B6
		dc.w mos_Null-mosCpu	; $B7
		dc.w mos_CLV-mosCpu	; $B8
		dc.w mos_LDA_absy-mosCpu	; $B9
		dc.w mos_TSX-mosCpu	; $BA
		dc.w mos_Null-mosCpu	; $BB
		dc.w mos_LDY_absx-mosCpu	; $BC
		dc.w mos_LDA_absx-mosCpu	; $BD
		dc.w mos_LDX_absy-mosCpu	; $BE
		dc.w mos_Null-mosCpu	; $BF
		dc.w mos_CPY_imm-mosCpu	; $C0
		dc.w mos_CMP_indx-mosCpu	; $C1
		dc.w mos_Null-mosCpu	; $C2
		dc.w mos_Null-mosCpu	; $C3
		dc.w mos_CPY_zp-mosCpu	; $C4
		dc.w mos_CMP_zp-mosCpu	; $C5
		dc.w mos_DEC_zp-mosCpu	; $C6
		dc.w mos_Null-mosCpu	; $C7
		dc.w mos_INY-mosCpu	; $C8
		dc.w mos_CMP_imm-mosCpu	; $C9
		dc.w mos_DEX-mosCpu	; $CA
		dc.w mos_Null-mosCpu	; $CB
		dc.w mos_CPY_abs-mosCpu	; $CC
		dc.w mos_CMP_abs-mosCpu	; $CD
		dc.w mos_DEC_abs-mosCpu	; $CE
		dc.w mos_Null-mosCpu	; $CF
		dc.w mos_BNE-mosCpu	; $D0
		dc.w mos_CMP_indy-mosCpu	; $D1
		dc.w mos_Null-mosCpu	; $D2
		dc.w mos_Null-mosCpu	; $D3
		dc.w mos_Null-mosCpu	; $D4
		dc.w mos_CMP_zpx-mosCpu	; $D5
		dc.w mos_DEC_zpx-mosCpu	; $D6
		dc.w mos_Null-mosCpu	; $D7
		dc.w mos_CLD-mosCpu	; $D8
		dc.w mos_CMP_absy-mosCpu	; $D9
		dc.w mos_Null-mosCpu	; $DA
		dc.w mos_Null-mosCpu	; $DB
		dc.w mos_Null-mosCpu	; $DC
		dc.w mos_CMP_absx-mosCpu	; $DD
		dc.w mos_DEC_absx-mosCpu	; $DE
		dc.w mos_Null-mosCpu	; $DF
		dc.w mos_CPX_imm-mosCpu	; $E0
		dc.w mos_SBC_indx-mosCpu	; $E1
		dc.w mos_Null-mosCpu	; $E2
		dc.w mos_Null-mosCpu	; $E3
		dc.w mos_CPX_zp-mosCpu	; $E4
		dc.w mos_SBC_zp-mosCpu	; $E5
		dc.w mos_INC_zp-mosCpu	; $E6
		dc.w mos_Null-mosCpu	; $E7
		dc.w mos_INX-mosCpu	; $E8
		dc.w mos_SBC_imm-mosCpu	; $E9
		dc.w mos_NOP-mosCpu	; $EA
		dc.w mos_Null-mosCpu	; $EB
		dc.w mos_CPX_abs-mosCpu	; $EC
		dc.w mos_SBC_abs-mosCpu	; $ED
		dc.w mos_INC_abs-mosCpu	; $EE
		dc.w mos_Null-mosCpu	; $EF
		dc.w mos_BEQ-mosCpu	; $F0
		dc.w mos_SBC_indy-mosCpu	; $F1
		dc.w mos_Null-mosCpu	; $F2
		dc.w mos_Null-mosCpu	; $F3
		dc.w mos_Null-mosCpu	; $F4
		dc.w mos_SBC_zpx-mosCpu	; $F5
		dc.w mos_INC_zpx-mosCpu	; $F6
		dc.w mos_Null-mosCpu	; $F7
		dc.w mos_SED-mosCpu	; $F8
		dc.w mos_SBC_absy-mosCpu	; $F9
		dc.w mos_Null-mosCpu	; $FA
		dc.w mos_Null-mosCpu	; $FB
		dc.w mos_Null-mosCpu	; $FC
		dc.w mos_SBC_absx-mosCpu	; $FD
		dc.w mos_INC_absx-mosCpu	; $FE
		dc.w mos_Null-mosCpu	; $FF

; ----------------------------------------------------------------

mos_Null:
		lsr.w	#1,d4
		bra.s	*

; ----------------------------------------------------------------

mos_ADC_imm:
		move.b	(a0)+,d7
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ADC_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		ori.b	#4,d3
		move	d3,sr
		addx.b	d7,d0
		move	sr,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_imm:
		move.b	(a0)+,d7
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_AND_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		and.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_acc:
		lsl.b	#1,d0
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		lsl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		lsl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		move.b	(a2,d6.w),d7
		lsl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ASL_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		move.b	(a2,d6.w),d7
		lsl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BCC:
		move.b	(a0)+,d6
		move	d3,sr
		bcs.s	.next
		ext.w	d6
		adda.w	d6,a0
.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BCS:
		move.b	(a0)+,d6
		move	d3,sr
		bcc.s	.next
		ext.w	d6
		adda.w	d6,a0
.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BEQ:
		move.b	(a0)+,d6
		move	d3,sr
		bne.s	.next
		ext.w	d6
		adda.w	d6,a0
.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BIT_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		move.b	d7,d4
		andi.b	#$F1,d3
		lsl.b	#1,d7
		bcc.s	.no_n
		ori.b	#8,d3
.no_n:
		lsl.b	#1,d7
		bcc.s	.no_v
		ori.b	#2,d3
.no_v:
		and.b	d0,d4
		bne.s	.next
		ori.b	#4,d3
.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BIT_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		move.b	d7,d4
		andi.b	#$F1,d3
		lsl.b	#1,d7
		bcc.s	.no_n
		ori.b	#8,d3

.no_n:
		lsl.b	#1,d7
		bcc.s	.no_v
		ori.b	#2,d3

.no_v:
		and.b	d0,d4
		bne.s	.next
		ori.b	#4,d3

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BMI:
		move.b	(a0)+,d6
		move	d3,sr
		bpl.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BNE:
		move.b	(a0)+,d6
		move	d3,sr
		beq.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BPL:
		move.b	(a0)+,d6
		move	d3,sr
		bmi.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $00 - BRK
; ----------------------------------------------------------------

mos_BRK:
		addq.l	#1,a0			; skip the padding byte
		bsr	famiGetP		; P with B set
		swap	d3			; push PC, P
		move.w	a0,d4
		move.b	d4,d6
		lsr.w	#8,d4
		or.b	#$80,d4
		move.b	d4,(a2,d3.w)
		subq.b	#1,d3
		move.b	d6,(a2,d3.w)
		subq.b	#1,d3
		move.b	d5,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		move.w	#1,cpuModeIntDis(a4)

		lea 	(RAM_Fami_ROM),a5
		move.w	#cpuIRQ,d6		; go to IRQ
		add.w	d6,a5
		moveq	#0,d6
		move.b	1(a5),d6
		lsl.w	#8,d6
		move.b	(a5),d6
		and.w	#$7FFF,d6
		movea.l	a1,a0
		add.l	d6,a0
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BVC:
		move.b	(a0)+,d6
		move	d3,sr
		bvs.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_BVS:
		move.b	(a0)+,d6
		move	d3,sr
		bvc.s	.next
		ext.w	d6
		adda.w	d6,a0

.next:
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CLC:
		andi.b	#$EE,d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; CLD - Clear Decimal mode
; ----------------------------------------------------------------

mos_CLD:
		move.w	#0,cpuModeDec(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; CLI - Clear Interrupt disable
; ----------------------------------------------------------------

mos_CLI:
		move.w	#0,cpuModeIntDis(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------

mos_CLV:
		andi.b	#$FD,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_imm:
		move.b	(a0)+,d7
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_indx:
		clr.w	d5
		clr.w	d4
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CMP_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		cmp.b	d7,d0
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPX_imm:
		move.b	(a0)+,d7
		cmp.b	d7,d1
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPX_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		cmp.b	d7,d1
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPX_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		cmp.b	d7,d1
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPY_imm:
		move.b	(a0)+,d7
		cmp.b	d7,d2
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPY_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		cmp.b	d7,d2
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_CPY_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		cmp.b	d7,d2
		move	sr,d5
		andi.w	#$D,d5
		eori.b	#1,d5
		andi.b	#2,d3
		or.b	d5,d3
		andi.b	#1,d5
		lsl.b	#4,d5
		or.b	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEC_zp:
		clr.w	d6
		move.b	(a0)+,d6
		subq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEC_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		subq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEC_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		subq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEC_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		subq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEX:
		subq.b	#1,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_DEY:
		subq.b	#1,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_imm:
		move.b	(a0)+,d7
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_EOR_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		eor.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INC_zp:
		clr.w	d6
		move.b	(a0)+,d6
		addq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INC_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		addq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INC_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		addq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INC_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		addq.b	#1,(a2,d6.w)
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INX:
		addq.b	#1,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_INY:
		addq.b	#1,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; $4C - JMP $xxxx
; ----------------------------------------------------------------

mos_JMP_abs:
		moveq	#0,d6
		move.b	1(a0),d6
		lsl.w	#8,d6
		move.b	(a0),d6
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $6C - JMP ($xxxx)
; ----------------------------------------------------------------

mos_JMP_ind:
		moveq	#0,d4
		move.b	1(a0),d6
		lsl.w	#8,d6
		move.b	(a0),d6
		move.b	(a2,d6.w),d4
		add.b	#1,d6
		move.b	(a2,d6.w),d6
		lsl.w	#8,d6
		or.b	d4,d6

	; TODO: Check for more jump locations
		tst.w	d6
		bmi.s	.to_rom
		move.l	a2,a0
		adda	d6,a0
		jmp	(RAM_EmuLoop).l
.to_rom:
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $20 - JSR $xxxx
; ----------------------------------------------------------------

mos_JSR:
		moveq	#0,d6
		move.b	(a0)+,d4
		move.b	(a0),d6
		lsl.w	#8,d6
		move.b	d4,d6

		swap	d3
		move.w	a0,d4
		move.b	d4,d5
		lsr.w	#8,d4
		or.b	#$80,d4
		move.b	d4,(a2,d3.w)
		subq.b	#1,d3
		move.b	d5,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; $A9 - LDA #$xx
; ----------------------------------------------------------------

mos_LDA_imm:
		move.b	(a0)+,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_abs:
		clr.w	d4
		clr.w	d6
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; LDA (oper,X)

mos_LDA_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDA_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_imm:
		move.b	(a0)+,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_zpy:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d2,d6
		move.b	(a2,d6.w),d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		move.b	d7,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDX_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_imm:
		move.b	(a0)+,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		move.b	d7,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LDY_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		move.b	d7,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_acc:
		lsr.b	#1,d0
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		lsr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		lsr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		move.b	(a2,d6.w),d7
		lsr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_LSR_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		move.b	(a2,d6.w),d7
		lsr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; $EA - nop

mos_NOP:
		nop
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_imm:
		move.b	(a0)+,d7
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ORA_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		or.b	d7,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_PHA:
		swap	d3
		move.b	d0,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $08 - PHP
; ----------------------------------------------------------------

mos_PHP:
		bsr	famiGetP
		swap	d3
		move.b	d5,(a2,d3.w)
		subq.b	#1,d3
		swap	d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; Convert between the 6502 P register and the emulator's flags
;
; N, Z, V and C live in the 68k CCR (low byte of d3, X mirrors C),
; I and D live in cpuModeIntDis and cpuModeDec.
; d3 must not be swapped when calling these.
; ----------------------------------------------------------------

; Build P in d5 (bits 5 and 4 set; clear bit 4 for NMI/IRQ)
; Uses: d5, a5
famiGetP:
		lea	tblCcrToP(pc),a5
		move.w	d3,d5
		andi.w	#$0F,d5
		move.b	(a5,d5.w),d5
		tst.w	cpuModeIntDis(a4)
		beq.s	.no_i
		ori.b	#$04,d5
.no_i:
		tst.w	cpuModeDec(a4)
		beq.s	.no_d
		ori.b	#$08,d5
.no_d:
		rts

; Load flags from P in d5
; Uses: d5, a5
famiSetP:
		lea	tblPToCcr(pc),a5
		andi.w	#$FF,d5
		andi.b	#$E0,d3
		or.b	(a5,d5.w),d3
		clr.w	cpuModeIntDis(a4)
		btst	#2,d5
		beq.s	.no_i
		move.w	#1,cpuModeIntDis(a4)
.no_i:
		clr.w	cpuModeDec(a4)
		btst	#3,d5
		beq.s	.no_d
		move.w	#1,cpuModeDec(a4)
.no_d:
		rts

; CCR (N Z V C) -> P (N V 1 B . . Z C)
tblCcrToP:
.ccr := 0
		rept 16
		dc.b $30|((.ccr&8)<<4)|((.ccr&4)>>1)|((.ccr&2)<<5)|(.ccr&1)
.ccr := .ccr+1
		endm

; P -> CCR (X N Z V C, X = C)
tblPToCcr:
.p := 0
		rept 256
		dc.b ((.p&$80)>>4)|((.p&$40)>>5)|((.p&2)<<1)|((.p&1)*$11)
.p := .p+1
		endm
		align 2
; ----------------------------------------------------------------

mos_PLA:
		addi.l	#$10000,d3
		move.l	d3,d5
		swap	d5
		move.b	(a2,d5.w),d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $28 - PLP
; ----------------------------------------------------------------

mos_PLP:
		swap	d3
		addq.b	#1,d3
		move.b	(a2,d3.w),d5
		swap	d3
		bsr	famiSetP
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_acc:
		move	d3,sr
		roxl.b	#1,d0
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROL_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxl.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_acc:
		move	d3,sr
		roxr.b	#1,d0
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_abs:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_ROR_absx:
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		lsl.w	#8,d6
		move.b	d4,d6
		add.w	d1,d6
		move.b	(a2,d6.w),d7
		move	d3,sr
		roxr.b	#1,d7
		move	sr,d5
		andi.w	#$1D,d5
		andi.b	#$E2,d3
		or.w	d5,d3
		move.b	d7,(a2,d6.w)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $40 - RTI
; 
; NOTE: Interrupt exit
; ----------------------------------------------------------------

mos_RTI:
		tst.w	cpuFamiVint(a4)
		beq.s	.nonint
		
		swap	d3			; Restore SR, PC
		moveq	#0,d6
		addq.b	#1,d3
		move.b	(a2,d3.w),d5
		addq.b	#1,d3
		move.b	(a2,d3.w),d4
		addq.b	#1,d3
		move.b	(a2,d3.w),d6
		lsl.w	#8,d6
		move.b	d4,d6
		swap	d3
		bsr	famiSetP
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0

		move.l	#emuLoop,(RAM_EmuLoop+2).l
		move.w	#0,cpuFamiVint(a4)
		tst.w	vbLate(a4)		; a VBlank came while the handler ran:
		beq.s	.on_time		; the next NMI now, not a frame later
		clr.w	vbLate(a4)
		move.w	#1,FamiMdVint(a4)
.on_time:
		jmp	(RAM_EmuLoop).l

.nonint:
		swap	d3
		moveq	#0,d6
		addq.b	#1,d3
		move.b	(a2,d3.w),d5
		addq.b	#1,d3
		move.b	(a2,d3.w),d4
		addq.b	#1,d3
		move.b	(a2,d3.w),d6
		lsl.w	#8,d6
		move.b	d4,d6
		swap	d3
		bsr	famiSetP
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; $60 - RTS
; ----------------------------------------------------------------

mos_RTS:
		swap	d3
		moveq	#0,d6
		addq.b	#1,d3
		move.b	(a2,d3.w),d4
		addq.b	#1,d3
		move.b	(a2,d3.w),d6
		lsl.w	#8,d6
		move.b	d4,d6
		swap	d3
		addq.w	#1,d6
		and.l	#$7FFF,d6
		movea.l a1,a0
		add.l 	d6,a0
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_imm:
		move.b	(a0)+,d7
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_zp:
		clr.w	d6
		move.b	(a0)+,d6
		move.b	(a2,d6.w),d7
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_zpx:
		clr.w	d6
		move.b	(a0)+,d6
		add.b	d1,d6
		move.b	(a2,d6.w),d7
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_absy:
		clr.w	d4
		clr.w	d5
		clr.b	d7
		move.b	(a0)+,d4
		move.b	(a0)+,d6
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_indx:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6

		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SBC_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		bsr	addr_Read
		eori.b	#$11,d3
		ori.b	#4,d3
		move	d3,sr
		subx.b	d7,d0
		move	sr,d3
		eori.b	#$11,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_SEC:
		ori.b	#$11,d3
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; SED - Set Decimal mode
; ----------------------------------------------------------------

mos_SED:
		move.w	#1,cpuModeDec(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; SEI - Set Interrupt disable
; ----------------------------------------------------------------

mos_SEI:
		move.w	#1,cpuModeIntDis(a4)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------

mos_STA_zp:
		clr.w	d4
		move.b	(a0)+,d4
		move.b	d0,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STA_zpx:
		clr.w	d4
		move.b	(a0)+,d4
		add.b	d1,d4
		move.b	d0,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STA_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STA_absx:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d1,d4
		addx.b	d7,d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------

mos_STA_absy:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------
; STA (oper,X)

mos_STA_indx:
		clr.w	d5
		clr.w	d4
		clr.w	d6
		move.b	(a0)+,d5
		add.b	d1,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------

mos_STA_indy:
		clr.w	d4
		clr.w	d5
		clr.w	d6
		move.b	(a0)+,d5
		move.b	(a2,d5.w),d4
		add.b	#1,d5
		move.b	(a2,d5.w),d6
		clr.b	d7
		add.b	d2,d4
		addx.b	d7,d6
		move.b	d0,d7
		bra	addr_Write
; ----------------------------------------------------------------

mos_STX_zp:
		clr.w	d4
		move.b	(a0)+,d4
		move.b	d1,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STX_zpy:
		clr.w	d4
		move.b	(a0)+,d4
		add.b	d2,d4
		move.b	d1,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STX_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		move.b	d1,d7
		bra	addr_Write
; ----------------------------------------------------------------
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STY_zp:
		clr.w	d4
		move.b	(a0)+,d4
		move.b	d2,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STY_zpx:
		clr.w	d4
		move.b	(a0)+,d4
		add.b	d1,d4
		move.b	d2,(a2,d4.w)
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_STY_abs:
		clr.w	d4
		move.b	(a0)+,d4
		clr.w	d6
		move.b	(a0)+,d6
		move.b	d2,d7
		bra	addr_Write
; ----------------------------------------------------------------
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TAX:
		move.b	d0,d1
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TAY:
		move.b	d0,d2
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------
; TSX

mos_TSX:
		swap	d3
		move.b	d3,d1
		swap	d3
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TXA:
		move.b	d1,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TXS:
		swap	d3
		move.b	d1,d3
		swap	d3
		jmp	(RAM_EmuLoop).l
; ----------------------------------------------------------------

mos_TYA:
		move.b	d2,d0
		move	sr,d5
		andi.w	#$C,d5
		andi.b	#$F3,d3
		or.w	d5,d3
		jmp	(RAM_EmuLoop).l
