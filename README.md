# FamiDrive-MD

A NES emulator that runs on the SEGA Genesis / Mega Drive. It is a modification of
Nemul, originally made by Mairtrus. Credit to Mairtrus for the original work.

**ROMs are not included in the source.**

## Features

- Runs on real hardware (the original Nemul did not)
- Passes nestest's tests for all official 6502 opcodes
- Mappers 0 (NROM), 2 (UxROM), 3 (CNROM) and 4 (MMC3, the way Super Mario Bros. 2 uses it), with
  CHR-ROM or CHR-RAM, and PRG RAM at $6000-$7FFF for mappers 2 and 4
- Working vertical scrolling using both scroll layers (the NES map height differs from the MD's)
- Horizontal scroll changes partway down the screen (such as a still status bar above a scrolling
  level) use the MD's line scroll
- Shows an error screen, instead of a black screen, for unsupported ROMs and 68000 crashes
- Sound: the NES pulse, triangle and noise channels are played on the MD's PSG and YM2612

## Building

The build uses the [AS macro assembler](http://john.ccac.rwth-aachen.de:8000/as/), which is bundled in
`tools/AS/`, and Python 3 for `tools/p2bin.py`.

1. Pass the NES ROM you want to embed to the build script: `./build.sh path/to/game.nes` on Linux,
   or `build.bat path\to\game.nes` on Windows. With no argument it uses `roms/nestest.nes`.
2. The Mega Drive ROM is written to `out/rom_md.bin`, with an assembly listing in `out/rom_md.lst`.
   Build output is not tracked in git.

### Recompiling (faster)

`./build.sh --recompile path/to/game.nes` (or `build.bat --recompile ...`) translates the game's
6502 code into 68000 code at build time with `tools/recomp6502.py`, instead of interpreting it
while the game runs. Games that use a lot of CPU run many times faster: Pinball's gameplay goes
from about 3.5 to about 55 game frames per second, as fast as on a NES (which also drops frames
when the game is busy). Super Mario Bros., Balloon Fight, Ice Climber and Excitebike run at full
speed (60) while you play. Games with banked PRG-ROM (mappers 2 and 4) are translated a bank at a
time: Super Mario Bros. 2 goes from about 6 to 60 game frames per second in most of its levels.

When a game's frame needs a little more time than an MD frame, its next NMI waits until the game
is ready for it (up to a frame), so the game runs a little slower instead of at half speed. NMIs
still come once per VBlank on average, so music keeps its tempo.

The translated code goes to `out/recomp.asm`. It is the game's code in another form, so like the
built ROM it stays out of git and shouldn't be published. Code the recompiler can't find ahead of
time (for example, reached only through jump tables it doesn't recognise) still runs, through the
interpreter, just slower.

#### FPS counter

`./build.sh --recompile --fps path/to/game.nes` adds a counter in the top right corner showing how
many frames per second the game finishes (60 is full speed). Press X, Y or Z on a 6-button pad to
hide or show it. Builds without `--fps` don't contain it.

- It counts the times the game leaves the small loop where it waits for VBlank, which it does once
  per frame. While a game polls something without waiting for VBlank, its frames don't advance and
  the counter reads 0 (Pinball does this while the ball waits to be launched).
- It's drawn with two sprites, taking the last two NES sprite slots (62 and 63) while it's shown,
  and it disappears when the game turns sprites off.

### Supported NES ROMs

- iNES format (`.nes`)
- Mapper 0 (NROM), 2 (UxROM), 3 (CNROM) or 4 (MMC3)
- 16 KB or 32 KB of PRG-ROM, or with mappers 2 and 4, 32 KB to 512 KB
- CHR-ROM or CHR-RAM

Anything else shows an error screen saying what isn't supported. MMC3 games work if they switch
PRG-ROM at $8000-$BFFF in 16 KB pairs and don't use its scanline interrupt, as Super Mario Bros. 2
does. Games that switch its 8 KB banks one at a time, or time a split screen with the interrupt
(Super Mario Bros. 3's status bar), don't work yet.

### Checks

GitHub builds FamiDrive on every push and pull request, with `build.sh` on Linux and `build.bat` on
Windows, and checks that the two make the same ROM. It also runs `tools/test/run.sh`, which you can
run yourself on Linux (it needs git, make, a C compiler and Python 3). That script builds FamiDrive
with a small test game and runs it on Genesis Plus GX, both as it is and changed to act like an
AtGames handheld, whose VDP differs from a Mega Drive's. It fails if FamiDrive stops handling the
handheld's differences.

## Source layout

| File | Contents |
|---|---|
| `md.asm` | ROM header, Mega Drive init and interrupts, NES ROM loading, emulator main loop |
| `emu/cpu.asm` | 6502 CPU: opcode table and handlers |
| `emu/memory.asm` | CPU memory map: RAM, PRG-ROM and mappers, APU/controller registers, PPU register reads |
| `emu/ppu.asm` | PPU register writes, nametable and palette drawing, CHR conversion |
| `emu/ppu_tables.asm` | Lookup tables for nametable drawing and CHR conversion |
| `emu/vlines.asm` | Measures at startup how many lines the console draws a frame, and which line each V counter value means (clones such as AtGames' differ from a Mega Drive) |
| `emu/apu.asm` | APU: NES sound translated to the PSG and YM2612 once per frame |
| `emu/apu_tables.asm` | Sound lookup tables, generated by `tools/mkapu.py` |
| `emu/recomp.asm` | Support code for recompiled games (dispatch, NMI, interpreter fallback) |
| `emu/fps.asm` | FPS counter (`--fps` builds) |
| `tools/recomp6502.py` | The 6502-to-68000 recompiler |
| `tools/nesinfo.py` | Reads the NES ROM's header as it's built (md.asm lays out banked PRG-ROM from it), and for MMC3 games turns the CHR-ROM into MD tiles, which bank switches copy |
| `tools/hwtest/` | A test ROM that shows what a console does differently from a Mega Drive in what FamiDrive depends on (see its README) |
| `tools/test/` | Checks that FamiDrive still works on an AtGames handheld (`run.sh`, see Checks above) |
| `system/md/error.asm` | Error screen |
| `system/` | Assembler macros and Mega Drive hardware definitions |

## Known issues

- **Slow when interpreted.** Emulating a 6502 plus the PPU on a 68000 is a stretch. Games that
  use a lot of CPU run far below full speed when interpreted (Pinball's gameplay runs at about
  6%), and their music slows down with them. Recompile them: Pinball then plays at NES speed,
  though its attract demo still runs at about 97%
- Recompiled Super Mario Bros. can drop the odd frame in its busiest scenes (about 2% of frames in
  World 4-1, with Lakitu and several enemies on screen), and the black screen before a level
  lasts about a tenth of a second longer than on a NES. As a level restarts after a death, one
  frame shows the screen half cleared where the NES shows plain sky
- Ice Climber's pause while it builds a mountain lasts about a third of a second longer than on
  a NES
- Graphics glitches from timing inaccuracy. The emulator can't tell which line the NES would be
  drawing, so it goes by what the game does: sprite 0 hit is reported when the game polls for
  it, a poll that sees the hit flag clear marks the top of the screen, and delay loops count as
  the NES time they would take. Split-screen effects timed any other way can be off by a few
  lines, and only horizontal splits are supported
- Sound is approximate: no DMC (sample) channel, the PSG only plays 50% squares so pulse duty is
  approximated by volume, pulse notes below about 109 Hz play an octave up, and timing assumes
  an NTSC console
- Recompiled Super Mario Bros. 2 slows to about 50-58 game frames per second in the busiest moments
  of its horizontally scrolling levels (such as 6-1). Interpreted, it runs at about a tenth of
  full speed, and its story screen garbles some text lines: its menu code assumes it never runs
  late
- Some games do not work
- Tested in emulators (Genesis Plus GX, BlastEm) and on an AtGames handheld, not on an original Mega Drive
- An AtGames handheld seems to draw frames a little faster than a Mega Drive (about 61.7 a second by its
  YM2612's clock), so games and their music would run about 3% fast on it

See [TODO.md](TODO.md) for smaller known bugs and planned work.
