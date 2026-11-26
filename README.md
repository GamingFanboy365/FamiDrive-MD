# FamiDrive-MD

A NES emulator that runs on the SEGA Genesis / Mega Drive. It is a modification of
Nemul, originally made by Mairtrus. Credit to Mairtrus for the original work.

**ROMs are not included in the source.**

## Features

- Runs on real hardware (the original Nemul did not)
- Passes nestest's tests for all official 6502 opcodes
- Mappers 0 (NROM), 1 (MMC1, with the last PRG bank fixed as Mega Man 2 uses it, or 32 KB at a
  time as the hack Super Mario Unlimited Deluxe does), 2 (UxROM),
  3 (CNROM), 4 (MMC3, the ways Super Mario Bros. 2 and 3 and Mega Man 3 use it) and 71 (Camerica),
  with CHR-ROM or CHR-RAM, and PRG RAM at $6000-$7FFF for mappers 1, 2, 4 and 71
- Working vertical scrolling using both scroll layers (the NES map height differs from the MD's)
- Horizontal scroll changes partway down the screen (such as a still status bar above a scrolling
  level) use the MD's line scroll
- A split at the MMC3's scanline interrupt, below which the game shows other nametable rows with
  other tiles (such as Super Mario Bros. 3's status bar), uses the MD's window plane
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
speed (60) while you play. Games with banked PRG-ROM (mappers 2, 4 and 71) are translated a bank at a
time: Super Mario Bros. 2 goes from about 6 to 60 game frames per second in most of its levels, and
Super Mario Bros. 3, whose MMC3 switches 8 KB banks at $A000 and $C000 apart, from about 6 to 60
in World 1-1's quieter parts and while it scrolls, and to about 55-58 in its busiest moments.

When a game's frame needs a little more time than an MD frame, its next NMI waits until the game
is ready for it (up to a frame), so the game runs a little slower instead of at half speed. NMIs
still come once per VBlank on average, so music keeps its tempo. The game is ready where it loops
waiting for the NMI: a few instructions polling a flag, or a loop like Mega Man 3's that looks
through its tasks for one ready to run.

The interpreter holds NMIs in a like way. On a NES an NMI handler takes a fraction of a frame;
interpreted, it can take most of one, or more, and the next NMI then came before the game's own
loop had done its work, or in the middle of it. Where the handler leaves it little of the frame,
the next NMI now waits until that loop waits for it again (up to a frame).

The translated code goes to `out/recomp.asm`. It is the game's code in another form, so like the
built ROM it stays out of git and shouldn't be published. Code the recompiler can't find ahead of
time (for example, reached only through jump tables it doesn't recognise) still runs, through the
interpreter, just slower. Besides the jump tables it can follow from the code that reads them, it
looks through the bytes no code covers for tables of routines' addresses (as Contra's and Life
Force's objects' routines are listed, and read through a pointer).

#### FPS counter

`./build.sh --recompile --fps path/to/game.nes` adds a counter in the top right corner showing how
many frames per second the game finishes (60 is full speed). Press X, Y or Z on a 6-button pad to
hide or show it. Builds without `--fps` don't contain it.

- It counts the times the game leaves the small loop where it waits for VBlank, which it does once
  per frame. While a game polls something without waiting for VBlank, its frames don't advance and
  the counter reads 0 (Pinball does this while the ball waits to be launched).
- It's drawn with two sprites, taking the last two NES sprite slots (62 and 63) while it's shown,
  and it disappears when the game turns sprites off.

#### Another NES palette

`./build.sh --palette path/to/colors.pal path/to/game.nes` (with `--recompile` or without) builds
with the NES colors of a palette file instead of the built-in ones: a `.pal` file as NES emulators
use them, 64 colors of 3 bytes each (red, green, blue), 192 bytes in all (of a 1536-byte file, with
the colors for each emphasis setting, the first 64 are used). Each color becomes the closest of the
Mega Drive's 512 (`tools/mkpalette.py`).

### Supported NES ROMs

- iNES format (`.nes`)
- Mapper 0 (NROM), 1 (MMC1), 2 (UxROM), 3 (CNROM), 4 (MMC3) or 71 (Camerica)
- 16 KB or 32 KB of PRG-ROM, or with mappers 1, 2, 4 and 71, 32 KB to 512 KB (MMC1: 256 KB)
- CHR-ROM or CHR-RAM

Anything else shows an error screen saying what isn't supported. MMC1 games work in its PRG
mode 3, a 16 KB bank at $8000 and the last at $C000 (as at power on), or if every 32 KB bank has
the same vectors at its top, as a game that switches 32 KB at a time needs, in its 32 KB modes;
with vertical or horizontal mirroring, and CHR-ROM in 8 KB or 4 KB banks. Its mode with the first
bank fixed shows an error screen, and its one-screen mirroring isn't supported. Mapper 71 picks the PRG bank with a
write anywhere at $8000-$FFFF but $9000-$9FFF, as FCEUX does: Camerica's own games write it at
$C000-$FFFF, and some dumped as mapper 71 at $8000 (Dooly Bravo Land). Its one-screen mirroring at
$9000-$9FFF (the BF9097 board, which Fire Hawk uses) isn't supported. MMC3 games work if they switch
PRG-ROM at $8000-$BFFF in 16 KB pairs, as Super Mario Bros. 2 does, or switch its two 8 KB banks one
at a time, at $A000 and $C000 in PRG mode 1, as Super Mario Bros. 3 does, or at $8000 and $A000 in
PRG mode 0, as Mega Man 3 and Panic Restaurant do (but not both modes in one game). Its scanline
interrupt is taken when the NMI handler returns, and again in the same frame, up to four times, when
its handler leaves it on for a line further down. What the frame's last handler sets up for the
screen below its line (other nametable rows, other CHR banks) shows in the MD's window plane, from
the first whole cell row below that line; the planes under it are blank, so that the level doesn't
show through a status bar whose inside is the backdrop color (as The Flintstones' is), unless a
strip of other rows above it already uses the one change of the planes' vertical scroll a frame
has. What an earlier one sets up is for the lines down to the
next: its horizontal scroll, other nametable rows (the planes' vertical scroll, set by a line
interrupt), and sprites hidden if it switched their tiles, but not other background tiles. If the
last one points the PPU at no other rows, the window shows the rows an earlier one pointed it at,
from that one's line, with the tiles as the last one leaves them, and if it turns the background
off, the screen is blank from its line (as Code Name: Viper's status bar does both).

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
| `emu/ppu.asm` | PPU register writes, nametable and palette drawing, CHR conversion, the split below the MMC3's scanline interrupt |
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
  and its attract demo runs at about 99.5% (it drops the odd frame)
- Recompiled Super Mario Bros. runs at 60 game frames per second while you play, World 4-1 with
  Lakitu and several Spinies on screen included, but the black screen before a level lasts about a
  tenth of a second longer than on a NES (6 frames, 8 on an AtGames handheld). As a level
  restarts after a death, one frame shows the screen half cleared where the NES shows plain sky
- Ice Climber's pause while it builds a mountain lasts about a quarter of a second longer than on
  a NES
- Graphics glitches from timing inaccuracy. The emulator can't tell which line the NES would be
  drawing, so it goes by what the game does: sprite 0 hit is reported when the game polls for
  it (in a loop that reads $2002 in one place or two), a poll that sees the hit flag clear marks
  the top of the screen (scroll changes before it are the top's), a new BG pattern table is the
  screen's where the NES would start drawing with it (with the background on, the NMI handler's
  RTI, that poll), and delay loops count as the NES time they would take. Split-screen effects timed any other way can be off by a few
  lines, and only horizontal splits are supported, besides the MMC3 scanline interrupt's and, in
  MMC3 games, a switch of the BG pattern table after a sprite 0 hit (as Deja Vu's)
- Sound is approximate: no DMC (sample) channel, the PSG only plays 50% squares so pulse duty is
  approximated by volume, pulse notes below about 109 Hz play an octave up, and timing assumes
  an NTSC console
- Recompiled Super Mario Bros. 2 runs at 60 game frames per second while you play, as far as tried
  (the first parts of World 4-1, with several Flurries on screen, and of 2-1, 5-1 and 6-1,
  measured in Genesis Plus GX as a Mega Drive and changed to act like an AtGames handheld, whose
  frames are shorter). As the player dies, or goes through a door or jar to another area, it
  slows to about 51-57 for a moment. Interpreted, it runs at about a tenth of full speed, and its
  story screen garbles some text lines: its menu code assumes it never runs late
- Super Mario Bros. 3 splits the screen more than once a frame in its levels with water along the
  bottom or a water line, and in its spade bonus game: of those, World 3-2, 3-3 and the spade game
  were tried. Sprites that are partly below its status bar's top line, or a water line, show
  whole or not at all. Recompiled, World
  1-1 runs at 60 game frames per second where it's quiet and while it scrolls, and about 55-58
  where several enemies are on screen (its status bar's split costs about 2-3 of those where it's
  busiest), and the black screen before a level lasts about 50 frames (20 on a NES).
  Interpreted, it runs at about a tenth of full speed and can't enter a level: its NMI handler
  outlasts a frame, and the next NMI reads the pads again before the game takes the A button.
  Interpreted, skipping its intro with Start while the curtain rises also leaves part of the
  title screen undrawn
- Life Force (mapper 2) plays recompiled, at about 55-60 game frames per second at the start of
  its first stage (47-55 before the recompiler found the routines its objects reach through
  tables). Its vertical stage shows no status bar (seen in the attract demo, not looked into
  yet), and only the start of its first stage and the demo were tried
- Mega Man 3 (MMC3) plays recompiled, so far at about 40-50 game frames per second in Top Man's
  stage where it's busy (60 where it's quiet, and on its title screen), its music at full
  speed; that stage is the only one tried. Interpreted, it runs at about 12, and its title
  screen misses some of its tiles
- Tiny Toon Adventures (MMC3) plays recompiled, at about 60 game frames per second in its first
  stage, the only one tried; the iris wipe when you lose a life closes in steps of 8 lines.
  Interpreted, it runs at a few frames per second
- Deja Vu (MMC3) plays recompiled at full speed, as far as its first rooms were tried. The menu
  and text below its picture use the other BG pattern table, switched after a sprite 0 hit:
  shown in the window plane, from the first whole 8-line row there
- Code Name: Viper (MMC3) plays recompiled, as far as its first stage was tried. Its status bar shows
  2 lines lower than on a NES (from the first whole 8-line row below its split), and where it's busy
  and runs late, a frame now and then misses some of its sprites. Interpreted, it reaches its
  first stage now (it stayed on a black screen after its title), slowly
- Dooly Bravo Land (mapper 71) plays recompiled, at 60 game frames per second in its first stage,
  the only one tried. Interpreted, it's far too slow to play: its intro spends most of its time in
  delay loops, which the interpreter runs an instruction at a time, and recompiled code in one step
- Panic Restaurant (MMC3) plays recompiled, at 60 game frames per second in most of its first stage,
  the only one tried, with dips to about 35-48 for a second or two now and then. The FPS counter
  shows 00 in it: its wait loop calls a routine, which the counter doesn't take for a wait loop.
  Interpreted, it stays on a black screen: it takes one NMI and no more (not looked into further)
- The Flintstones: The Rescue of Dino & Hoppy and The Surprise at Dinosaur Peak (MMC3) play
  recompiled, as far as the start of their first stages was tried (their status bars showed the
  level's tiles behind their text before)
- Star Wars: The Empire Strikes Back (MMC3) plays recompiled, as far as the start of its first
  stage was tried. Thin lines and a short bar show along the very top of its screen as it
  scrolls; whether a NES shows them there too (they're in lines a TV's overscan hides) isn't
  checked yet
- Mega Man 2 (MMC1) plays recompiled, at 60 game frames per second in Bubble Man's stage, dipping
  to about 40-45 where its big frogs are, the only stage tried. Interpreted, it's too slow to
  play; it gets as far as its stage select, the last screen tried (it used to stop before it: an
  NMI came while it played the sound an earlier NMI held back, and switched banks under it)
- Super Mario Unlimited Deluxe (a hack, MMC1 switching 32 KB at a time) plays recompiled, at 60
  game frames per second in World 1-1, the only level tried
- Castlevania (UxROM, CHR-RAM) plays recompiled, at 60 game frames per second in its first stage
  with dips to about 50-55, as far as the castle's hall. Contra (UxROM, CHR-RAM) plays
  recompiled, at 60 game frames per second in its first stage with a dip to about 53 now and
  then, as far as the jungle's wall sensors, the only part tried; its attract demos run at
  about 45-60 (both had their background tiles change from frame to frame before, and ran at
  10-11; Contra then ran at 25-50, most of its objects' code interpreted)
- Dig Dug (NROM) plays recompiled at full speed. As it starts, its title's screen showed half
  drawn for some frames; one such frame is left. Its NMI handler draws that screen with
  rendering off, which takes several frames here: the screen now goes off too from the second,
  as it does where other games draw a screen that way (Super Mario Bros. as a level starts,
  Castlevania between areas), which showed them half drawn too
- Pac-Man (Tengen, NROM) plays, recompiled at full speed and interpreted at about 33-35 game
  frames per second (it stayed on a black screen interpreted, and its recompiled build didn't
  assemble). A short orange line at the top left corner of its screen is the last row of the
  sprites it parks at the top of the screen, lines a TV's overscan hides
- Some games do not work
- Tested in emulators (Genesis Plus GX, BlastEm) and on an AtGames handheld, not on an original Mega Drive
- An AtGames handheld seems to draw frames a little faster than a Mega Drive (about 61.7 a second by its
  YM2612's clock), so games and their music would run about 3% fast on it

See [TODO.md](TODO.md) for smaller known bugs and planned work.
