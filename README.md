# FamiDrive-MD

A NES emulator that runs on the SEGA Genesis / Mega Drive. It is a modification of
Nemul, originally made by Mairtrus. Credit to Mairtrus for the original work.

**ROMs are not included in the source.**

## Features

- Runs on real hardware (the original Nemul did not)
- Passes nestest's tests for all official 6502 opcodes
- Mappers 0 (NROM) and 3 (CNROM), with CHR-ROM or CHR-RAM
- Working vertical scrolling using both scroll layers (the NES map height differs from the MD's)
- Shows an error screen, instead of a black screen, for unsupported ROMs and 68000 crashes

## Building

The build uses the [AS macro assembler](http://john.ccac.rwth-aachen.de:8000/as/), which is bundled in
`tools/AS/`, and Python 3 for `tools/p2bin.py`.

1. Pass the NES ROM you want to embed to the build script: `./build.sh path/to/game.nes` on Linux,
   or `build.bat path\to\game.nes` on Windows. With no argument it uses `roms/nestest.nes`.
2. The Mega Drive ROM is written to `out/rom_md.bin`, with an assembly listing in `out/rom_md.lst`.
   Build output is not tracked in git.

### Supported NES ROMs

- iNES format (`.nes`)
- Mapper 0 (NROM) or mapper 3 (CNROM)
- 16 KB or 32 KB of PRG-ROM
- CHR-ROM or CHR-RAM

Anything else shows an error screen saying what isn't supported.

## Source layout

| File | Contents |
|---|---|
| `md.asm` | ROM header, Mega Drive init and interrupts, NES ROM loading, emulator main loop |
| `emu/cpu.asm` | 6502 CPU: opcode table and handlers |
| `emu/memory.asm` | CPU memory map: RAM, PRG-ROM and mappers, APU/controller registers, PPU register reads |
| `emu/ppu.asm` | PPU register writes, nametable and palette drawing, CHR conversion |
| `system/md/error.asm` | Error screen |
| `system/` | Assembler macros and Mega Drive hardware definitions |

## Known issues

- **Slow.** Emulating a 6502 plus the PPU on a 68000 is a stretch.
- Graphics glitches from timing inaccuracy. Sprite 0 hit is approximated from the MD's scanline
  counter, so split-screen effects can be off by a few lines
- No sound, and no plans for it
- 8x16 sprites show the wrong tiles (NES 8x16 sprites work differently from the MD's)
- Controller reading is not 6-button pad safe
- Some games do not work
- The fixes made in October 2026 were tested in an emulator (Genesis Plus GX), not on real hardware

See [TODO.md](TODO.md) for smaller known bugs and planned work.
