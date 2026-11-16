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
- [ ] **MMC3: more of it.** R6's and R7's 8 KB banks are switched one at a
  time where the game's code does that (PRG_FRAMES, `mmc3Prg1`: in PRG mode 1,
  at $C000 and $A000, as Super Mario Bros. 3; in mode 0, at $8000 and $A000,
  as Mega Man 3), and as a 16 KB pair otherwise (PRG_IMAGES, as Super Mario
  Bros. 2), but a game can't switch between the modes. The scanline IRQ is taken when the NMI
  handler returns, and again in the same frame where its handler leaves it
  on (`splitNext`: Super Mario Bros. 3's 32-pixel partition, water line and
  spade game), not by a count of lines: a handler's own time before it sets
  the counter again isn't known, so an IRQ after a `$C001` reload is put at
  the next cell row's first line. What the frame's last handler sets up
  below its line shows in the window plane, from the first whole cell row
  (`splitDone`); an earlier one's X scroll, `$2006` rows (one such strip a
  frame, by a line interrupt: `MD_Hint`) and hidden sprites show down to the
  next, its background tiles don't. If the last points the PPU at no rows,
  the window shows those of the last that did, from its line (`winV`), and
  if one leaves the background off, the window is blank from its line, and
  the planes under the window too (`splitBlank`; what it pointed the PPU at
  after turning it off is for `$2007`). The line interrupt's vertical scroll
  is from the next line in Genesis Plus GX; on a console it may come a
  line later. Not yet: a horizontal scroll below the last split, and other
  sprite tiles below a split (sprites there are hidden when the handler
  switches them).
  The IRQ comes earlier in the frame than on a NES, so a handler's `$2000`
  increment is only kept for its own `$2007` writes, and one that a late
  VBlank or the I flag holds off just doesn't come that frame: the window
  stays as the last one left it, unless the I flag held it off as the NMI
  handler returned two frames running (`irqHeld`, `splitMiss`: Code Name:
  Viper turns it on every frame, but off its stages keeps the I flag set).
  Tiny Toon Adventures runs its game in its NMI handler, which often
  outlasts an MD frame, so its IRQ is skipped in many frames.
  Recompiled, Super Mario Bros. 3's split costs about 4% of the time (2-3
  frames a second where it's busiest), most of it the handler's own code
  and its PPU and mapper writes: `splitDone` only works when something it
  reads changed.
- [ ] **Mega Man 3: what's left.** It plays now (MMC3 PRG mode 0 with 8 KB
  banks apart; NMIs held while its NMI handler's sound work after its RTI
  runs, or the game's own code does that work: NMI_TAIL, `nmiTailStart`,
  `nmiTailEnd`, `nmiTailR6`). Recompiled, Top Man's stage runs at about
  40-50 game frames a second where it's busy, 60 where it's quiet, its
  music at full speed: an NMI that comes while its main task runs waits
  for its task loop ($FEAD, a wait loop to the recompiler: `wait_heads`),
  up to a frame, and those due still come (`nmiCredit`: after the
  handler's sound work, `nmiTailEnd`; in the handler, which turns NMIs
  off while it runs, they count too). A game frame there takes about 1.2
  MD frames of work (with each NMI held until the game waits for it: 320
  lines from the NMI to its frame done on average, 12% of frames within
  one MD frame), the main task's and each NMI's (its handler, its sound
  driver, and FamiDrive's PPU, APU and sprite work). 60 throughout would
  need about a fifth less. Its sound driver's jump
  engine ($8023: `engine_pattern2`) and multiply ($8006: `rcMul8`) are
  translated directly now, and its sprite routine's loop at $F230 reads
  through both its pointers. The biggest parts left: the sound driver
  (about a tenth of the work), bank switches ($FF6B, about 25 a frame: its
  callers push a return address because its sound path, rarely taken,
  leaves its copy), and calls and returns in general. Interpreted (about
  12), its title screen misses some tiles. Only Top Man's stage was tried.
  The recompiler takes some of its banks' data for code (its unofficial
  opcode warnings).
- [ ] **Life Force: what's left.** It plays now, recompiled (an NMI taken
  in its NMI handler where it waits for a sprite 0 hit that can't come:
  `rdPPU_Status`, `ppuSp0Wait`; its sprites off below the status bar's
  split: `wrPPU_Mask`). Its first stage runs at about 47-51 game frames a
  second: it does its whole frame in the NMI handler, which here takes
  longer than an MD frame. Its vertical stage, as far as the attract demo
  shows it, has no status bar (not looked into; only horizontal scroll
  splits are supported). Sprite 0, a blue block at the status bar's left end, shows,
  though its attributes put it behind the background. Only the first
  stage and the demo were looked at.
- [ ] **Code Name: Viper: what's left.** Its IRQ handler runs three times a
  frame: the first points the PPU at the status bar's rows (`$2006`) and
  switches all the CHR banks to blank ones, the second, 5 lines on,
  switches R0 and R1 to its font, and the third, 24 lines on, turns the
  background off and writes a column of the level (`$2000` with +32, then
  `$2007`). The window shows the first one's rows with the font, from the
  first whole cell row, 2 lines lower than on a NES. Only its first stage
  was tried.
- [ ] **Jump tables read too far.** After a JSR to a jump engine,
  `inline_table` takes entries until one doesn't look like code (up to 128);
  some of Tiny Toon Adventures' run on into the code after them, which is
  then translated from wrong places too (its unofficial opcode warnings).
  An entry that points just past its table could end it.
- [ ] **An NMI during the NMI handler, elsewhere.** A VBlank that comes
  while the NMI handler runs is held until its RTI (`famiVInt`, `rcNmiDue`:
  `.late`), so a slow frame here isn't a lag frame to the game. The one
  let through is for a handler polling $2002 with sprite 0 hidden (Life
  Force). A game that counts on one anywhere else (a handler that never
  returns, say) still waits.
- [ ] **Other CHR switches.** MMC3 bank switches copy tiles made with the ROM
  (`chrUpdate`), but a new BG pattern table (`chrLoadBg`) and CNROM's 8 KB
  switches still convert every tile, which takes several frames.

## Sound

- [ ] **DMC channel (on hold for now).** Sample playback (`$4010`-`$4013`)
  and direct output (`$4011`) are ignored. Sample playback could use the
  YM2612 DAC: the Z80 only runs its startup stub and channel 6 is free, so
  a small Z80 player could decode the samples from the ROM. Open questions:
  the 68000 takes the Z80's bus each VBlank (sound writes, DMA), which
  would make samples stutter; the fastest sample rates are tight for a
  Z80; and how the DAC sounds on an AtGames handheld isn't known. Of the
  games tried, Super Mario Bros. 3 plays samples (its drums); Mega Man 3
  and Life Force don't.
- [ ] **Low pulse notes.** Pulse notes below the PSG's range (about 109 Hz)
  fold up an octave in `apuPulseOut`. They could move to a spare FM channel.
- [ ] **Pulse duty.** The PSG only plays 50% squares; 12.5%/25% pulses lose
  their even harmonics. An FM voice per pulse would get closer, at the cost
  of the PSG's exact pitch.
- [ ] **PAL consoles.** `tools/mkapu.py` assumes NTSC PSG/FM clocks and 60 Hz
  frames, so on PAL pitch is about 1% low and envelopes run 17% slow.

## Recompiler

- [ ] **More speed.** Recompiled Pinball plays as fast as on a NES, and its
  attract demo at about 99.5%. Next steps: `(zp),Y` reads through RAM
  pointers outside versioned loops take a slow path (placing NES RAM next to
  the PRG copy would let one `(a0,d6.w)` read both); versioning loops that
  call routines; keeping hot zero-page variables in registers.
- [ ] **Banked games' calls into banks.** The fixed bank's code calls a
  bank's code, and returns into it, through `rcDispatch` (a few times a
  frame in Super Mario Bros. 2): which bank is at $8000 isn't known where
  the fixed bank calls it. Super Mario Bros. 2 runs at 60 while you play,
  as far as tried, but slows for a moment (to about 51-57 frames a second,
  on a Mega Drive and an AtGames handheld) as the player dies or goes to
  another area; what's left is spread out:
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

- [ ] **Test on an original Mega Drive.** Changes are tested in emulators
  (Genesis Plus GX, and BlastEm for the 6-button pad fix). An AtGames
  Genesis handheld has run the hardware test ROM (`tools/hwtest`) and
  FamiDrive, which its results led to the handheld's fixes for; an
  original Mega Drive hasn't.

## Cleanup

- [ ] **Unused leftovers.** The `trap #2` in `romGrabPrg` can't be reached
  now that `Fami_LoadRom` checks the PRG size.
