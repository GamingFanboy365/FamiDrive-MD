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

1. Put the NES ROM you want to embed at `roms/nestest.nes`. To use a different file name, change the
   `binclude` line at the bottom of `md.asm`.
2. On Linux, run:

   ```sh
   ./build.sh
   ```

3. The Mega Drive ROM is written to `out/rom_md.bin`, with an assembly listing in `out/rom_md.lst`.

There is no Windows build script yet, but `tools/AS/win32/asw.exe` takes the same arguments as the
`asl` line in `build.sh`.

### Supported NES ROMs

- iNES format (`.nes`)
- Mapper 0 (NROM) or mapper 3 (CNROM)
- 16 KB or 32 KB of PRG-ROM
- CHR-ROM (games that use CHR-RAM are not supported yet)

Other mappers are not rejected. They run as if they were NROM and usually fail.

## Known issues

- **Slow.** Emulating a 6502 plus the PPU on a 68000 is a stretch.
- Graphics glitches from timing inaccuracy, which also affects sprite 0 hit
- No sound, and no plans for it
- 8x16 sprite mode is not implemented (it works differently from the MD's 8x16 sprites)
- Controller reading is not 6-button pad safe
- Some games do not work

See [TODO.md](TODO.md) for the full list of known bugs and planned cleanup.
