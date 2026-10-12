# FamiDrive-MD

A NES emulator that runs on the SEGA Genesis / Mega Drive. It is a modification of
Nemul, originally made by Mairtrus. Credit to Mairtrus for the original work.

**ROMs are not included in the source.**

## Features

- Runs on real hardware (the original Nemul did not)
- Mappers 0 (NROM) and 3 (CNROM)
- Working vertical scrolling using both scroll layers (the NES map height differs from the MD's)

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
- Graphics glitches from timing inaccuracy, which also affects sprite 0 hit
- No sound, and no plans for it
- 8x16 sprite mode is not implemented (it works differently from the MD's 8x16 sprites)
- Controller reading is not 6-button pad safe
- Some games do not work

See [TODO.md](TODO.md) for the full list of known bugs and planned cleanup.
