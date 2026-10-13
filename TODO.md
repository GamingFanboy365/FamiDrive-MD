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
- [ ] **8x16 sprites.** `$2000` bit 5 makes MD sprites two tiles tall
  (`ppuSprWide`), but NES 8x16 sprites take their pattern table from bit 0 of
  the tile number and use the even/odd tile pair, so they show the wrong tiles.

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

## Hardware

- [ ] **6-button pads.** `readInput` reads the pad with a simple two-step TH
  sequence that isn't safe for 6-button controllers.
- [ ] **Test on real hardware.** The fixes in #1 to #6 were tested in Genesis
  Plus GX only.

## Cleanup

- [ ] **Unused leftovers.** `cpuFlag2` is never read, and the `trap #2` in
  `romGrabPrg` can't be reached now that `Fami_LoadRom` checks the PRG size.
