; ====================================================================
; ----------------------------------------------------------------
; APU (sound)
;
; 6502 writes to $4000-$4017 are only stored (apuStore), so the
; emulation loop stays fast. Once per frame, from MD_Vint, apuUpdate
; applies the writes, runs the APU frame sequencer (envelopes,
; length counters, sweep, triangle linear counter) and sets the
; MD sound chips:
;
; Pulse 1 - PSG tone 0
; Pulse 2 - PSG tone 1
; Triangle - YM2612 channel 1, a single sine operator
; Noise - PSG noise, clocked by PSG tone 2 (kept silent)
;
; The PSG only plays 50% squares, so pulse duty is approximated
; by volume. DMC is not emulated.
; ----------------------------------------------------------------

RAM_Fami_Apu	equ RAM_Fami_Emu+$A00	; cleared by emuStart

; APU state, offsets from RAM_Fami_Apu
apuRegs		equ $00			; $18 bytes: last value written to $4000-$4017
apuWrote	equ $18			; $18 bytes: nonzero if written since last frame
apuCh1		equ $30			; pulse 1 channel state (apuCh_*)
apuCh2		equ $38			; pulse 2
apuChN		equ $40			; noise
apuTriLength	equ $48
apuTriLinear	equ $49
apuTriReload	equ $4A			; linear counter reload flag
apuFmKey	equ $4B			; triangle key is on
apuFmFreq	equ $4C			; word: last block/fnum written
apuNoiseCtl	equ $4E			; last PSG noise control byte
apuReady	equ $4F			; set by apuInit

; channel state, offsets from apuCh1/apuCh2/apuChN
apuCh_EnvStart	equ 0
apuCh_EnvDiv	equ 1
apuCh_EnvDecay	equ 2
apuCh_Length	equ 3
apuCh_SweepDiv	equ 4
apuCh_SweepLoad	equ 5			; sweep reload flag
apuCh_Period	equ 6			; word: timer period

psg_port	equ $11			; from vdp_data
ym_addr1	equ $A04000		; YM2612 part I (Z80 bus needed)
ym_data1	equ $A04001
apuTriLevel	equ $0B			; triangle operator TL (volume), matched to the NES mix

; ----------------------------------------------------------------
; $4000-$4013, $4015, $4017 write
;
; d5 - register ($00-$17)
; d7 - value
; ----------------------------------------------------------------

apuStore:
		lea	(RAM_Fami_Apu).l,a5
		move.b	d7,apuRegs(a5,d5.w)
		st	apuWrote(a5,d5.w)
		jmp	(RAM_EmuLoop).l

; ----------------------------------------------------------------
; Set up the YM2612 triangle voice and silence the PSG
;
; a6 - vdp_data
; ----------------------------------------------------------------

apuInit:
		lea	(RAM_Fami_Apu).l,a5
		move.b	#$9F,psg_port(a6)	; PSG: all channels off
		move.b	#$BF,psg_port(a6)
		move.b	#$DF,psg_port(a6)
		move.b	#$FF,psg_port(a6)
		move.w	#$100,(z80_bus).l
.wait_bus:
		btst	#0,(z80_bus).l
		bne.s	.wait_bus
		lea	apuFmSetup(pc),a1
.setup:
		move.b	(a1)+,d0
		cmpi.b	#$FF,d0
		beq.s	.done
		move.b	(a1)+,d1
		bsr	apuYmWrite
		bra.s	.setup
.done:
		move.w	#0,(z80_bus).l
		st	apuReady(a5)
		rts

; YM2612 register/value pairs, $FF ends
apuFmSetup:
		dc.b $22,$00			; LFO off
		dc.b $27,$00			; channel 3 normal mode
		dc.b $2B,$00			; DAC off
		dc.b $28,$00,$28,$01,$28,$02	; all keys off
		dc.b $28,$04,$28,$05,$28,$06
		dc.b $B0,$07			; channel 1: algorithm 7 (all carriers), no feedback
		dc.b $B4,$C0			; left + right
		dc.b $30,$01,$34,$01,$38,$01,$3C,$01	; MUL 1
		dc.b $40,$7F,$44,$7F,$48,$7F		; operators 1-3 silent
		dc.b $4C,apuTriLevel			; operator 4 plays
		dc.b $50,$1F,$54,$1F,$58,$1F,$5C,$1F	; fastest attack
		dc.b $60,$00,$64,$00,$68,$00,$6C,$00	; no decay
		dc.b $70,$00,$74,$00,$78,$00,$7C,$00
		dc.b $80,$0F,$84,$0F,$88,$0F,$8C,$0F	; sustain full, fast release
		dc.b $90,$00,$94,$00,$98,$00,$9C,$00	; no SSG-EG
		dc.b $FF
		align 2

; ----------------------------------------------------------------
; YM2612 part I write
;
; d0 - register, d1 - value
; Z80 bus must be held
; ----------------------------------------------------------------

apuYmWrite:
		btst	#7,(ym_addr1).l
		bne.s	apuYmWrite
		move.b	d0,(ym_addr1).l
.wait:
		btst	#7,(ym_addr1).l
		bne.s	.wait
		move.b	d1,(ym_data1).l
		rts

; ----------------------------------------------------------------
; Once per frame, from MD_Vint
;
; a6 - vdp_data
; Z80 bus must be held
; ----------------------------------------------------------------

apuUpdate:
		lea	(RAM_Fami_Apu).l,a5
		tst.b	apuReady(a5)
		bne.s	.ready
		rts
.ready:

	; $4015: disabling a channel clears its length counter
		tst.b	apuWrote+$15(a5)
		beq.s	.no_status
		sf	apuWrote+$15(a5)
		move.b	apuRegs+$15(a5),d0
		btst	#0,d0
		bne.s	.on1
		sf	apuCh1+apuCh_Length(a5)
.on1:
		btst	#1,d0
		bne.s	.on2
		sf	apuCh2+apuCh_Length(a5)
.on2:
		btst	#2,d0
		bne.s	.on3
		sf	apuTriLength(a5)
.on3:
		btst	#3,d0
		bne.s	.no_status
		sf	apuChN+apuCh_Length(a5)
.no_status:

	; register writes
		lea	apuCh1(a5),a0
		lea	apuRegs+$00(a5),a1
		lea	apuWrote+$00(a5),a2
		moveq	#0,d6
		bsr.w	apuPulseWrites
		lea	apuCh2(a5),a0
		lea	apuRegs+$04(a5),a1
		lea	apuWrote+$04(a5),a2
		moveq	#1,d6
		bsr.w	apuPulseWrites

		tst.b	apuWrote+$0B(a5)	; triangle length / linear reload
		beq.s	.no_tri
		sf	apuWrote+$0B(a5)
		st	apuTriReload(a5)
		btst	#2,apuRegs+$15(a5)
		beq.s	.no_tri
		move.b	apuRegs+$0B(a5),d0
		lsr.b	#3,d0
		andi.w	#$1F,d0
		lea	apuLengthTbl(pc),a1
		move.b	(a1,d0.w),apuTriLength(a5)
.no_tri:
		tst.b	apuWrote+$0F(a5)	; noise length / envelope restart
		beq.s	.no_noise
		sf	apuWrote+$0F(a5)
		st	apuChN+apuCh_EnvStart(a5)
		btst	#3,apuRegs+$15(a5)
		beq.s	.no_noise
		move.b	apuRegs+$0F(a5),d0
		lsr.b	#3,d0
		andi.w	#$1F,d0
		lea	apuLengthTbl(pc),a1
		move.b	(a1,d0.w),apuChN+apuCh_Length(a5)
.no_noise:

	; frame sequencer, 4-step mode: quarter frames at 240 Hz,
	; half frames at 120 Hz. One MD frame = Q, Q+H, Q, Q+H. The units
	; don't affect each other, so each is clocked its 4 or 2 times in
	; one go.
		bsr.w	apuSequence

	; outputs
		lea	apuCh1(a5),a0
		move.b	apuRegs+$00(a5),d0
		move.b	apuRegs+$01(a5),d5
		moveq	#1,d2
		moveq	#$00,d6			; PSG tone 0
		bsr.w	apuPulseOut
		lea	apuCh2(a5),a0
		move.b	apuRegs+$04(a5),d0
		move.b	apuRegs+$05(a5),d5
		moveq	#0,d2
		moveq	#$20,d6			; PSG tone 1
		bsr.w	apuPulseOut
		bsr.w	apuNoiseOut
		bra.w	apuTriOut

; ----------------------------------------------------------------
; Pulse register writes
;
; a0 - channel state, a1 - its registers, a2 - its written flags
; d6 - its bit in $4015
; ----------------------------------------------------------------

apuPulseWrites:
		sf	(a2)			; $4000: read directly
		tst.b	1(a2)			; $4001: reload the sweep
		beq.s	.no_sweep
		sf	1(a2)
		st	apuCh_SweepLoad(a0)
.no_sweep:
		tst.b	2(a2)			; $4002: period low
		beq.s	.no_low
		sf	2(a2)
		move.b	2(a1),apuCh_Period+1(a0)
.no_low:
		tst.b	3(a2)			; $4003: period high, length, restart
		beq.s	.done
		sf	3(a2)
		move.b	3(a1),d0
		move.b	d0,d1
		andi.b	#7,d1
		move.b	d1,apuCh_Period(a0)
		st	apuCh_EnvStart(a0)
		btst	d6,apuRegs+$15(a5)
		beq.s	.done
		lsr.b	#3,d0
		andi.w	#$1F,d0
		lea	apuLengthTbl(pc),a1
		move.b	(a1,d0.w),apuCh_Length(a0)
.done:
		rts

; ----------------------------------------------------------------
; One MD frame of the frame sequencer: four quarter frames (envelopes,
; triangle linear counter), two half frames (length counters, sweep)
; ----------------------------------------------------------------

apuSequence:
		lea	apuCh1(a5),a0
		move.b	apuRegs+$00(a5),d0
		bsr.w	apuEnvelope4
		lea	apuCh2(a5),a0
		move.b	apuRegs+$04(a5),d0
		bsr.w	apuEnvelope4
		lea	apuChN(a5),a0
		move.b	apuRegs+$0C(a5),d0
		bsr.w	apuEnvelope4

		move.b	apuRegs+$08(a5),d0	; triangle linear counter
		move.b	apuTriLinear(a5),d1
		tst.b	apuTriReload(a5)
		beq.s	.count4
		move.b	d0,d1			; reloaded: on each clock while the
		andi.b	#$7F,d1			; control flag is set, else on the
		tst.b	d0			; first, then counted down
		bmi.s	.linear
		sf	apuTriReload(a5)
		subq.b	#3,d1
		bcc.s	.linear
		moveq	#0,d1
		bra.s	.linear
.count4:
		subq.b	#4,d1
		bcc.s	.linear
		moveq	#0,d1
.linear:
		move.b	d1,apuTriLinear(a5)

	; two half frames: length counters
		lea	apuCh1(a5),a0
		move.b	apuRegs+$00(a5),d0
		bsr.s	apuLength2
		lea	apuCh2(a5),a0
		move.b	apuRegs+$04(a5),d0
		bsr.s	apuLength2
		lea	apuChN(a5),a0
		move.b	apuRegs+$0C(a5),d0
		bsr.s	apuLength2
		tst.b	apuRegs+$08(a5)		; triangle halt is bit 7
		bmi.s	.tri_halt
		move.b	apuTriLength(a5),d1
		subq.b	#2,d1
		bcc.s	.tri_left
		moveq	#0,d1
.tri_left:
		move.b	d1,apuTriLength(a5)
.tri_halt:
	; and sweep
		lea	apuCh1(a5),a0
		move.b	apuRegs+$01(a5),d0
		moveq	#1,d2
		bsr.s	apuSweep2
		lea	apuCh2(a5),a0
		move.b	apuRegs+$05(a5),d0
		moveq	#0,d2
		bra.s	apuSweep2

; two half-frame clocks of a length counter
; a0 - channel state, d0 - its volume register (bit 5 halts)
apuLength2:
		btst	#5,d0
		bne.s	.halted
		move.b	apuCh_Length(a0),d1
		subq.b	#2,d1
		bcc.s	.left
		moveq	#0,d1
.left:
		move.b	d1,apuCh_Length(a0)
.halted:
		rts

; two half-frame clocks of a sweep unit
; a0 - channel state, d0 - its sweep register (EPPP NSSS)
; d2 - 1 for pulse 1 (it negates with one's complement)
apuSweep2:
		tst.b	d0
		bpl.s	.divider_only		; disabled
		moveq	#7,d1
		and.b	d0,d1
		bne.s	.sweep
.divider_only:					; or no shift: the period stays
		move.b	d0,d1
		lsr.b	#4,d1
		andi.b	#7,d1			; the divider's period
		move.b	apuCh_SweepDiv(a0),d5
		tst.b	apuCh_SweepLoad(a0)
		beq.s	.clock1
		sf	apuCh_SweepLoad(a0)	; reload flag: reloaded on the first
		move.b	d1,d5
		bra.s	.clock2
.clock1:
		subq.b	#1,d5			; at 0: reloaded, else counted down
		bcc.s	.clock2
		move.b	d1,d5
.clock2:
		subq.b	#1,d5
		bcc.s	.div_done
		move.b	d1,d5
.div_done:
		move.b	d5,apuCh_SweepDiv(a0)
		rts
.sweep:
		move.w	apuCh_Period(a0),d4
		move.b	apuCh_SweepDiv(a0),d5
		move.b	apuCh_SweepLoad(a0),d6
		move.b	d0,d1
		andi.w	#7,d1			; shift
		moveq	#2-1,d7
.clock:
		move.w	d4,d3			; target period
		lsr.w	d1,d3
		btst	#3,d0
		beq.s	.add
		neg.w	d3
		sub.w	d2,d3
.add:
		add.w	d4,d3
		tst.b	d5			; divider at 0, enabled, shift not 0,
		bne.s	.divider		; period and target in range: update
		tst.b	d0
		bpl.s	.divider
		tst.w	d1
		beq.s	.divider
		cmpi.w	#8,d4
		bcs.s	.divider
		cmpi.w	#$7FF,d3
		bhi.s	.divider
		move.w	d3,d4
.divider:
		tst.b	d6
		bne.s	.reload
		tst.b	d5
		beq.s	.reload
		subq.b	#1,d5
		bra.s	.next
.reload:
		moveq	#0,d6
		move.b	d0,d5
		lsr.b	#4,d5
		andi.b	#7,d5
.next:
		dbf	d7,.clock
		move.w	d4,apuCh_Period(a0)
		move.b	d5,apuCh_SweepDiv(a0)
		move.b	d6,apuCh_SweepLoad(a0)
		rts

; four quarter-frame clocks of an envelope
; a0 - channel state, d0 - its volume register (--LC VVVV)
apuEnvelope4:
		tst.b	apuCh_EnvStart(a0)
		bne.s	.clocks			; restarting: clock by clock
		move.b	apuCh_EnvDiv(a0),d2
		subq.b	#4,d2			; the divider not at 0 on any clock:
		bcs.s	.reloads		; just counted down
		move.b	d2,apuCh_EnvDiv(a0)
		rts
.reloads:
		moveq	#$0F,d1			; else apuEnvTbl has the divider after
		and.b	d0,d1			; and the reloads, by the divider
		addq.b	#4,d2			; (0-3) and the period
		lsl.b	#4,d2
		or.b	d1,d2
		andi.w	#$3F,d2
		add.w	d2,d2
		move.b	apuEnvTbl(pc,d2.w),apuCh_EnvDiv(a0)
		move.b	apuEnvTbl+1(pc,d2.w),d2
		move.b	apuCh_EnvDecay(a0),d3
		sub.b	d2,d3			; the decay level, down one a reload:
		bcc.s	.decayed		; past 0, it loops from 15 or stays 0
		andi.b	#$0F,d3
		btst	#5,d0
		bne.s	.decayed
		moveq	#0,d3
.decayed:
		move.b	d3,apuCh_EnvDecay(a0)
		rts
.clocks:
		move.b	d0,d1
		andi.b	#$0F,d1			; period
		move.b	apuCh_EnvStart(a0),d5
		move.b	apuCh_EnvDiv(a0),d2
		move.b	apuCh_EnvDecay(a0),d3
		moveq	#4-1,d4
.clock:
		tst.b	d5
		beq.s	.run
		moveq	#0,d5			; restart
		moveq	#15,d3
		move.b	d1,d2
		bra.s	.next
.run:
		subq.b	#1,d2			; divider
		bcc.s	.next
		move.b	d1,d2
		subq.b	#1,d3			; decay level
		bcc.s	.next
		moveq	#0,d3
		btst	#5,d0			; loop
		beq.s	.next
		moveq	#15,d3
.next:
		dbf	d4,.clock
		move.b	d5,apuCh_EnvStart(a0)
		move.b	d2,apuCh_EnvDiv(a0)
		move.b	d3,apuCh_EnvDecay(a0)
		rts

; four clocks of an envelope's divider that reaches 0 in them: by its
; value (0-3) and period, the divider after them and the reloads
apuEnvTbl:
apuEnvD		set	0
		rept	4
apuEnvP		set	0
		rept	16
		dc.b	apuEnvP-((3-apuEnvD)-(3-apuEnvD)/(apuEnvP+1)*(apuEnvP+1)), 1+(3-apuEnvD)/(apuEnvP+1)
apuEnvP		set	apuEnvP+1
		endm
apuEnvD		set	apuEnvD+1
		endm

; In: a0 - channel state, d0 - sweep register, d2 - pulse 1 flag
; Out: d4 - period, d3 - sweep target period
apuSweepTarget:
		move.w	apuCh_Period(a0),d4
		move.b	d0,d1
		andi.w	#7,d1
		move.w	d4,d3
		lsr.w	d1,d3
		btst	#3,d0
		beq.s	.add
		neg.w	d3
		sub.w	d2,d3
.add:
		add.w	d4,d3
		rts

; ----------------------------------------------------------------
; Pulse -> PSG tone channel
;
; a0 - channel state, d0 - volume register, d5 - sweep register
; d2 - pulse 1 flag, d6 - PSG channel << 5
; ----------------------------------------------------------------

apuPulseOut:
		tst.b	apuCh_Length(a0)
		beq.s	.mute
		exg	d0,d5
		bsr.s	apuSweepTarget
		exg	d0,d5
		cmpi.w	#8,d4			; too high to hear
		bcs.s	.mute
		btst	#3,d5
		bne.s	.audible
		cmpi.w	#$7FF,d3		; sweep would overflow
		bhi.s	.mute
.audible:
	; PSG period = NES period + 1. Notes a little below the PSG's
	; range are clamped, lower ones fold up an octave.
		addq.w	#1,d4
		cmpi.w	#1075,d4
		bcc.s	.fold
		cmpi.w	#$3FF,d4
		bls.s	.in_range
		move.w	#$3FF,d4
		bra.s	.in_range
.fold:
		lsr.w	#1,d4
		cmpi.w	#$3FF,d4
		bhi.s	.fold
.in_range:
		move.b	d4,d3
		andi.b	#$0F,d3
		or.b	d6,d3
		ori.b	#$80,d3
		move.b	d3,psg_port(a6)
		lsr.w	#4,d4
		move.b	d4,psg_port(a6)

		moveq	#0,d1			; volume: constant or envelope
		btst	#4,d0
		beq.s	.envelope
		move.b	d0,d1
		andi.b	#$0F,d1
		bra.s	.volume
.envelope:
		move.b	apuCh_EnvDecay(a0),d1
.volume:
		lea	apuAttTbl(pc),a1
		move.b	(a1,d1.w),d3
		rol.b	#2,d0			; duty -> bits 1-0
		andi.w	#3,d0
		lea	apuDutyAttTbl(pc),a1
		add.b	(a1,d0.w),d3
		cmpi.b	#15,d3
		bls.s	.set_volume
.mute:
		moveq	#15,d3
.set_volume:
		or.b	d6,d3
		ori.b	#$90,d3
		move.b	d3,psg_port(a6)
		rts

; ----------------------------------------------------------------
; Noise -> PSG noise, rate from PSG tone 2
; ----------------------------------------------------------------

apuNoiseOut:
		move.b	apuRegs+$0E(a5),d0	; M--- PPPP
		moveq	#0,d1
		move.b	d0,d1
		andi.b	#$0F,d1
		tst.b	d0
		bpl.s	.white
		addi.b	#16,d1
.white:
		add.w	d1,d1
		lea	apuNoiseTbl(pc),a1
		move.w	(a1,d1.w),d4
		move.b	d4,d3			; PSG tone 2 period
		andi.b	#$0F,d3
		ori.b	#$C0,d3
		move.b	d3,psg_port(a6)
		lsr.w	#4,d4
		move.b	d4,psg_port(a6)

		move.b	#$E3,d3			; noise control: rate = tone 2
		tst.b	d0
		bmi.s	.periodic
		ori.b	#$04,d3			; white noise
.periodic:
		cmp.b	apuNoiseCtl(a5),d3	; writing it resets the noise,
		beq.s	.same			; so only on a change
		move.b	d3,apuNoiseCtl(a5)
		move.b	d3,psg_port(a6)
.same:
		moveq	#15,d3
		tst.b	apuChN+apuCh_Length(a5)
		beq.s	.set_volume
		move.b	apuRegs+$0C(a5),d0
		moveq	#0,d1
		btst	#4,d0
		beq.s	.envelope
		move.b	d0,d1
		andi.b	#$0F,d1
		bra.s	.volume
.envelope:
		move.b	apuChN+apuCh_EnvDecay(a5),d1
.volume:
		lea	apuAttTbl(pc),a1
		move.b	(a1,d1.w),d3
		tst.b	apuRegs+$0E(a5)		; white noise is louder on the PSG
		bmi.s	.set_volume		; than periodic noise: balance them
		cmpi.b	#15,d3
		beq.s	.set_volume
		addq.b	#1,d3
.set_volume:
		ori.b	#$F0,d3
		move.b	d3,psg_port(a6)
		rts

; ----------------------------------------------------------------
; Triangle -> YM2612 channel 1
; ----------------------------------------------------------------

apuTriOut:
		tst.b	apuTriLength(a5)
		beq.s	.off
		tst.b	apuTriLinear(a5)
		beq.s	.off
		moveq	#0,d4
		move.b	apuRegs+$0B(a5),d4
		andi.b	#7,d4
		lsl.w	#8,d4
		move.b	apuRegs+$0A(a5),d4
		cmpi.w	#2,d4			; ultrasonic, NES games use it as silence
		bcs.s	.off
		add.w	d4,d4
		lea	apuFmTbl(pc),a1
		move.w	(a1,d4.w),d4
		cmp.w	apuFmFreq(a5),d4
		beq.s	.same_freq
		move.w	d4,apuFmFreq(a5)
		move.w	d4,d1
		lsr.w	#8,d1
		move.w	#$A4,d0
		bsr	apuYmWrite
		move.b	d4,d1
		move.w	#$A0,d0
		bsr	apuYmWrite
.same_freq:
		tst.b	apuFmKey(a5)
		bne.s	.done
		st	apuFmKey(a5)
		moveq	#$28,d0
		move.b	#$F0,d1
		bra	apuYmWrite
.off:
		tst.b	apuFmKey(a5)
		beq.s	.done
		sf	apuFmKey(a5)
		moveq	#$28,d0
		moveq	#$00,d1
		bra	apuYmWrite
.done:
		rts

; ----------------------------------------------------------------

		include	"emu/apu_tables.asm"
		align 2
