# FamiDrive-MD

A NES emulator for the Mega Drive / Genesis, in 68000 assembly for the AS macro assembler.
README.md describes the features, the build and the source layout; TODO.md lists known bugs.

## Building

- `./build.sh [--recompile] [--fps] game.nes` (Linux) or `build.bat ...` (Windows) writes
  `out/rom_md.bin`, with a listing (and symbol table) in `out/rom_md.lst`.
- `tools/hwtest/build.sh` builds the hardware test ROM, `out/hwtest.bin`.
- The two scripts run different builds of AS: `tools/AS/linux/asl` is 1.42 Bld 118 and
  `tools/AS/win32/asw.exe` is 1.42 Bld 142. They must make byte-identical ROMs, and GitHub
  checks that they do. Bld 142 takes an `org` inside a `phase` as the phased address, so the
  `struct`/`finish` macros in `system/macros.asm` end the phase before restoring the address.
- `md.asm` and `build.bat` have CRLF line endings, `emu/*.asm` and `system/macros.asm` LF.
  Keep each file's endings.
- Give branches and calls to labels further on an explicit size when they're far (`bsr.w`,
  `jsr (label).l` past $8000). AS takes them as short in its first pass, and if the code then
  grows, a short forward branch it checks with first-pass addresses fails ("jump distance too
  big" on a `.s` branch that isn't far, or "addressing mode not allowed" on a `(pc,dN)` jump
  table). Build all three variants (plain, `--recompile`, `--recompile --fps`) after changing
  code: they lay it out differently.

## Never commit

NES ROMs, built ROMs, anything in `out/` (`out/recomp.asm` is a game's code, translated),
or disassemblies and other reference material for games (`reference/`, gitignored).

## AtGames handheld support: keep it

An AtGames Genesis handheld's VDP differs from a Mega Drive's in what FamiDrive depends on
(`tools/hwtest/README.md` has its measurements): it draws 246 lines a frame, not 262; in VBlank
its V counter reads $E0, $F3/$F4-$FF and then $7E/$7F, values of the middle of the screen, for
VBlank's last 9 lines; its VBlank flag stays on until V $01/$02; and a read as the counter
changes can return a mix of the old and new value. Before FamiDrive handled these, Excitebike's
scroll split jumped about on it. These pieces handle them, and must stay:

- `ppuClock` (`emu/ppu.asm`) reads the V counter until two reads agree.
- At startup `ppuMeasureLines` (`emu/ppu.asm`) measures, with `vlMeasure` (`emu/vlines.asm`),
  the lines a frame (`mdLines`) and the line each V counter value means (`vLineTbl`), and where
  to put values of the screen read with the VBlank flag on (`vOddLine`). `ppuClock` looks the
  line up in `vLineTbl`, and returns `vOddLine` for those.
- A frame is `mdLines(a4)` lines everywhere (`ppuLine`, `MD_Vint`, `rdPPU_Status`,
  `emu/recomp.asm`), never 262.
- On a Mega Drive (262 lines, give or take 2, and no odd values) `ppuMeasureLines` fills the
  table with the old formula, so FamiDrive behaves there exactly as before.

`tools/test/run.sh` checks all of this: it runs FamiDrive, interpreted and recompiled, on
Genesis Plus GX as it is and changed to act like the handheld (`tools/test/gpgx_atgames.py`),
and it fails if any piece above is undone. GitHub runs it on every push and pull request; run
it yourself after changing `ppuClock`, `ppuLine`, `ppuMeasureLines`, `emu/vlines.asm`,
`MD_Vint`, `MD_Hint`, `rdPPU_Status`, `ppuXChanged` or anything else that times the NES's lines
from the V counter. If a change makes it fail, fix the change rather than the check, unless the
check itself is wrong.
