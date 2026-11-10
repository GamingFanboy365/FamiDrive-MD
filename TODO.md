# TODO

Known bugs and planned work, roughly in priority order. The previous list was
finished in #1 to #6.

## Emulation

- [ ] **Controller reads after the 8th bit.** `APU_Input_1`/`APU_Input_2` shift
  in zeros, so a 9th read of `$4016`/`$4017` returns 0. A standard NES pad
  returns 1, and some games check for it. Reads while the strobe is held high
  should also keep returning the A button.
- [ ] **Palette reads through `$2007`.** `rdPPU_Data` buffers every read, but
  reads from `$3F00`-`$3FFF` should return the palette byte immediately.
- [ ] **Open bus.** Reads from write-only PPU registers return a byte of PRG-ROM
  (`rdPPU_OpenBus`), and most reads from `$4020`-`$5FFF` return the emulator's flags
  (`rdAPU_OpenBus`). Both should return the last value on the bus.
- [ ] **Code running from RAM.** `mos_JSR`, `mos_BRK` and `doVint` build the
  pushed return address from `a0` assuming it points into PRG-ROM, so JSR or an
  NMI from code in RAM pushes a wrong address.
- [ ] **Stack wrap in PLA.** `mos_PLA` increments the stack pointer with
  `addi.l #$10000,d3`, so pulling at `$01FF` reads `$0200` instead of wrapping
  to `$0100` like PLP and RTS do.
- [ ] **Reset state.** The 6502 starts with SP = `$00` and I clear; after reset
  it should be SP = `$FD` with I set.
- [ ] **MMC3: more of it.** In PRG mode 0, only R6 and R7 as a 16 KB pair are
  supported (`mmc3Write`, PRG_IMAGES); PRG mode 1, 8 KB banks at $A000 and
  $C000, is (Super Mario Bros. 3: PRG_FRAMES, `mmc3Prg1`), but a game can't
  switch between the modes. The scanline IRQ is taken once a frame, when the
  NMI handler returns, and what its handler sets up below its line shows in
  the window plane, from the first whole cell row (`splitDone`). Not yet:
  more IRQs a frame (Super Mario Bros. 3's 32-pixel partition, water line
  and spade game), a horizontal scroll below the split, and other sprite
  tiles below it (sprites there are hidden when the handler switches them).
  Recompiled, Super Mario Bros. 3's split costs about 4% of the time (2-3
  frames a second where it's busiest), most of it the handler's own code
  and its PPU and mapper writes: `splitDone` only works when something it
  reads changed.
- [ ] **Other CHR switches.** MMC3 bank switches copy tiles made with the ROM
  (`chrUpdate`), but a new BG pattern table (`chrLoadBg`) and CNROM's 8 KB
  switches still convert every tile, which takes several frames.

## Sound

- [ ] **DMC channel.** Sample playback (`$4010`-`$4013`) and direct output
  (`$4011`) are ignored. Sample playback could use the YM2612 DAC.
- [ ] **Low pulse notes.** Pulse notes below the PSG's range (about 109 Hz)
  fold up an octave in `apuPulseOut`. They could move to a spare FM channel.
- [ ] **Pulse duty.** The PSG only plays 50% squares; 12.5%/25% pulses lose
  their even harmonics. An FM voice per pulse would get closer, at the cost
  of the PSG's exact pitch.
- [ ] **PAL consoles.** `tools/mkapu.py` assumes NTSC PSG/FM clocks and 60 Hz
  frames, so on PAL pitch is about 1% low and envelopes run 17% slow.

## Recompiler

- [ ] **More speed.** Recompiled Pinball plays as fast as on a NES, but its
  attract demo runs at about 93%. Next steps: `(zp),Y` reads through RAM
  pointers outside versioned loops take a slow path (placing NES RAM next to
  the PRG copy would let one `(a0,d6.w)` read both); versioning loops that
  call routines; keeping hot zero-page variables in registers.
- [ ] **Banked games' calls into banks.** The fixed bank's code calls a
  bank's code, and returns into it, through `rcDispatch` (a few times a
  frame in Super Mario Bros. 2): which bank is at $8000 isn't known where
  the fixed bank calls it. Super Mario Bros. 2 still slows in the busiest
  moments of some levels (World 4-1 to about 54-56 frames a second on a
  Mega Drive, 50-56 on an AtGames handheld); what's left is spread out:
  calls that keep the 6502's return address (its object handlers, reached
  through its jump engine, leave with PLA PLA RTS, so they get no copies),
  nametable writes, the sound, sprite conversion and copying the tiles
  that CHR bank switches change to VRAM. `zp,X`
  addresses that may wrap cost 8 cycles more than ones the index range
  proves don't: proving it for indexes kept in RAM (Super Mario Bros. 2's
  object slot at $12) would need to know nothing else writes there (it
  doesn't hold: `ROR $12`). In MMC3 PRG mode 1 (Super Mario Bros. 3), a
  call into the other slot calls the copy of the routine in the bank
  there through its call table (`Gen.emit_dyn_call`), but only small
  routines that bank's own code goes to as well have copies (ROM room:
  every bank that slot holds gets one). Other calls into a slot go
  straight to the code in that bank's table (`Gen.slot_jump`), and their
  returns through `rcDispatch`. About 16 dispatches a game frame are left
  in World 1-1's busiest moments, about 1.3% of the time: mostly returns
  from code with no copy, which the 120 return caches (`RAM_RcRet`, given
  out in code order) don't reach, and jumps through RAM pointers. Calls
  and returns take about an eighth of the time there: about 110 calls a
  game frame push the 6502 return address, as JSR does. About 12 go to
  code with no copy: the fixed bank's calls into a slot whose bank isn't
  known that its call table has no entry for, routines of over 500
  instructions, and normal code's calls to checks that return from their
  callers too (PLA PLA RTS: only a heavy copy's calls get their copies).
  About 13 go through the other slot's call table to a heavy copy or a
  bank with none, and about 80 to copies that may leave through
  `rcDispatch` (`heavy`): mostly ones that call those (a call through the
  call table goes on in the normal code where that bank has no copy), run
  a jump engine or switch their own bank. (An NMI no longer makes a copy
  heavy: it comes back to the copy, `rcNmiIn`. A jump engine's entries
  get copies of their own, which the copies of routines that run it
  tail-call.)
- [ ] **Gameplay tests.** NES RAM is compared with Nestopia's only for the
  attract demo, up to the NES's first lag frame; gameplay checks are by eye.
  A test that replays input per game frame (not per video frame) could
  compare whole games.
- [ ] **NMI timing.** Recompiled code checks for VBlank only at loop heads and
  calls, not after every instruction, so NMIs land at slightly different
  points than on the NES.
- [ ] **Unofficial opcodes** aren't translated; code using them runs in the
  interpreter.

## Hardware

- [ ] **Test on real hardware.** Everything so far was tested in emulators
  (Genesis Plus GX, and BlastEm for the 6-button pad fix), not on a real
  console or the AtGames units this project targets.

## Cleanup

- [ ] **Unused leftovers.** `cpuFlag2` is never read, and the `trap #2` in
  `romGrabPrg` can't be reached now that `Fami_LoadRom` checks the PRG size.
