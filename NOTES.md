# Working notes

How the work on FamiDrive-MD gets done and checked, for whoever picks it up next, people or AI
assistants alike. CLAUDE.md has the rules for this repo, README.md what works, TODO.md the known
bugs; this file is the method: the order to work in, the checks that keep a fix from breaking
another game, and the traps that cost time before. Follow the checklists step by step: most of
the bugs found here were found by them, not by looking at screenshots.

## The owner's standing requests

- Do it right rather than fast. Find the cause, fix that, and say in the commit what it was.
- Commit and push at each milestone (a container can be cleared). Open a pull request only when
  asked. Never force-push or rewrite pushed history.
- At the end of a piece of work, attach test ROMs: recompiled, without the FPS counter, named
  `FamiDrive_<Game>_<commit>.bin` (the commit the ROM was built from).
- Give a short progress note every so often during long work.
- Never commit NES ROMs, built ROMs, `out/`, or disassemblies and other reference material for
  games (`reference/` is gitignored for this).
- No model names in commits, pull requests or code, beyond the attribution lines.
- Don't build third-party code fetched from GitHub, other than what `tools/test/run.sh` does.
- On hold for now: Super Mario Bros. 3 Mix (hack), the DMC channel.
- In wiki articles, prose rather than bullet lists.

## Conventions

- Commit messages: a subject like `Area: what it does now` (`Recompiler: ...`, `MMC3: ...`,
  `README, TODO: ...`), then prose that gives the cause, the fix, what was measured and how the
  other games were checked. Wrap at about 72 columns. Pull request bodies: what changed (by
  commit), limits, testing.
- `md.asm` and `build.bat` have CRLF line endings; everything else LF. Edit CRLF files with a tool
  that keeps them (Python with `newline=''`).
- After a pull request is merged (merge commits), bring the branch up to date with
  `git fetch origin main && git merge --ff-only origin/main` before new work.
- Before pushing more commits to a branch whose pull request was open, check that it hasn't
  been merged in the meantime (the owner merges as soon as it's ready). If it has, the new
  commits need a new pull request, and the merged one's description stays as it was merged.
- README's Known issues has a line for each game that was tried: how far, how fast, what's off.
  TODO.md names the routines involved in backticks.

## How a problem gets solved

1. Reproduce it headless: build the game, run it in Genesis Plus GX with scripted input, take
   screenshots (see the test harness below). Look at a grid of frames, not one frame.
2. Decide whether the recompiler or the emulation is at fault. Build the game interpreted and
   recompiled, both with NMIs paced (an NMI only every N VBlanks, so the game always finishes its
   frame first and input goes by NMI count), and compare NES RAM at every NMI. Different RAM
   means translated code does something the 6502 code doesn't: find the first NMI that differs,
   then the routine. Same RAM in both means the emulation (or timing) is at fault, or the game
   does that on a NES too.
3. Narrow it down with a logging build: a patch that adds a ring buffer of events (an NMI taken,
   an IRQ, a mapper write, a sprite DMA's sprite count...) in free MD RAM, read back each frame.
   Logging what happened beats guessing from screenshots.
4. Fix the cause, then run the regression checks below. Explain every difference they show before
   committing.
5. Update README and TODO, commit, push, deliver test ROMs.

## Checks before committing

- Every test game builds in all three variants (plain, `--recompile`, `--recompile --fps`);
  layout differences between them catch short branches that went out of range.
- Games the change shouldn't touch build byte-identical ROMs, when the change is conditional
  (an `if MMC3_IRQ` block, one mapper).
- Paced regression: the previous source and the new one, recompiled (and interpreted for a few
  games), random input by NMI count, NES RAM and the screen compared at every NMI, for all test
  games. Expect the same; some differences are known and harmless:
  - a game's idle-loop random seed differs whenever its speed does, even by a NOP's worth (Life
    Force's `$2D`; Tiny Toon's, Excitebike's, Ice Climber's, Castlevania's `$6F`, Panic
    Restaurant's `$18`, the Flintstones' random generator at `$0659`-`$0660` (the second
    game's at `$0686`-`$068D`), Contra's `$34`, which its objects then follow (`STA $34` at
    $C05B); test copies with that store or call NOPed out avoid it);
  - a screen shown a frame apart (timing), with the same RAM.
  A game that takes few NMIs (Deja Vu: 5 in the whole run) isn't tested by this: compare it in
  real time, with input that gets into the game (Deja Vu: A at the file screen, then A again
  through its text).
- Real-time comparison of old and new builds (frame hashes over a few thousand frames): where
  they part, look at the frames and say why.
- Speed: Super Mario Bros. 3, World 1-1, game frames a second in 60-frame windows, two input
  seeds: expect 60 with dips to 56-58 and one window at 33-34, the same old and new.
- `tools/test/run.sh` (AtGames handheld checks; GitHub runs it too).
- After pushing, check that GitHub's build passed (Linux and Windows builds must match).

## Test harness

None of this is in the repo; it was written as scratch tools, and the owner keeps a copy of
them (`FamiDrive_dev_tools.zip`): ask for it in a new environment. The pieces, so they can be
made again too:

- **Cores.** `tools/test/run.sh` builds Genesis Plus GX (libretro) twice, as a Mega Drive
  (`out/test/cores/md.so`) and changed to act like an AtGames handheld (`atgames.so`). A third
  build, for profiling, adds to `core/m68k/m68kcpu.c` two arrays of 0x200000 counters (68000
  cycles and instructions by PC/2), filled after each instruction while on, and two exported
  functions, `retro_prof_enable(int)` and `retro_prof_dump(path)`, which writes both arrays.
- **Runner** (Python, ctypes): loads a core, feeds it the ROM, runs N frames. Input: a list of
  `frame:button:length` presses; buttons map to the RetroPad, where B is the MD's B (NES A) and Y
  the MD's A (NES B). Output: screenshots (PNG, from the video callback), a hash of each frame,
  MD RAM bytes after each frame (`retro_get_memory_data(2)`, words in host byte order: swap each
  pair), NES RAM (MD RAM `$9000`-`$97FF`). It can also count game frames by a counter in MD RAM
  and press buttons by game frame instead of MD frame.
- **Paced NMIs** (a patch applied to a copy of the source before building): `MD_Vint` makes an
  NMI due only every N VBlanks; as each NMI is taken it copies NES RAM to `$FFFF6800`, the PRG
  RAM to `$FFFF7000` (folded to 2 KB) and counts NMIs at `$FFFF7800`; the pads are read there,
  so input goes by NMI count. Recompiled, an NMI that is late still waits for the game's wait
  loop. N = 4 recompiled, 16-32 interpreted. (NROM games need other addresses: their PRG-ROM is
  copied to `$FFFF0000`-`$FFFF7FFF`.) Where the interpreter can't finish a game frame in N
  VBlanks (Panic Restaurant's screen clears), it falls behind and every NMI after compares
  different frames: rather than a huge N, hold the NMI while the game's own "busy" flag is set
  (a `tst.b` of that NES RAM byte before the NMI is made due; Panic Restaurant's is `$02`).
- **Free MD RAM for logs**: in MMC3 games, `$FFFF6800`-`$FFFF7EFF` (the CHR cache ends at
  `$67FF`, the split's variables start at `$7F00`); the paced patch uses `$6800`-`$7FFF`. In
  banked games `$FFFF0000`-`$FFFF1FFF` is the PRG RAM, free if the game doesn't use it.
- **Traces** for a game that crashes: a ring buffer of the 6502 PC with A, X, Y and S at each
  interpreted instruction (a hook at `emuVint`, or in a recompiled build at `rcInterpStep`'s
  `.step`), and of every `rcDispatch` target (`d4`), frozen when `mos_Null` (an illegal opcode)
  runs. In PRG_8K builds the PC is `a0`'s low 15 bits plus `$8000`. The last dispatches before
  the interpreter took over show where the game went astray.
- **Hooks** in logging builds: save and restore the CCR (`move.w sr,-(sp)` ...
  `move.w (sp)+,ccr`) and every register used; translated code keeps 6502 flags in the CCR and
  `d3`. To hook translated code, run `tools/nesinfo.py` and `tools/recomp6502.py` yourself, add
  lines after labels in `out/recomp.asm`, then assemble as `build.sh` does.
- **Profiling**: run the profiling core over a stretch of frames, then add up cycles by the
  label each PC falls under in the listing (`out/rom_md.lst`): translated units (`L_`, `B<n>_`,
  `R...` copies, `I...` inlines) and runtime routines show where the time goes.
- **Disassembly** for reading a game's code: `tools/recomp6502.py`'s own decoder (`Prg`, `Insn`)
  prints a bank straight; the translated `out/recomp.asm` labels each instruction with its 6502
  address and text, which is quicker to search.

## Traps

- Shell: a removal through a variable (`rm -rf $DIR/x`) is refused by a safety check; write
  `"${DIR:?}"/x` or a literal path. Cleaning up by name pattern can hit source files:
  `recomp*.asm` matches `emu/recomp.asm`. Make source snapshots with `git archive`.
- Background jobs: `cd dir && (a) & (b) &` only runs `a` in `dir`; put the `cd` first, alone.
- The AS assembler: `(d8,An,Xn)` has an 8-bit displacement; `pea ($8001).w` is refused (a short
  address from `$8000` is negative); a short forward branch AS sized in its first pass can fail
  later ("jump distance too big"): give far branches `.w`.
- Interpreted builds are slow, and some games barely run interpreted: Code Name: Viper stays on
  a black screen after its title, Dooly Bravo Land's intro crawls (delay loops), Super Mario
  Bros. 3 can't enter a level. Use them for the NMI-by-NMI comparison with a large N, not for
  playing.
- Scripted input drifts with speed: a schedule by MD frame reaches a different place in a faster
  build. Press by game frame or NMI count when comparing builds.
- A ROM's header can be wrong: Dooly Bravo Land is dumped as mapper 71 but switches banks as
  UxROM does. Check what the game's code actually writes.
- An MMC3 game's PRG layout is guessed from its code (`NES_MMC3_PRG1` and `NES_MMC3_PRG8` in
  `out/nes_info.asm`, from `tools/nesinfo.py`). A wrong guess runs the game with the wrong bank
  at $8000 or $A000 after a switch: Panic Restaurant, which picks R6 and R7 through `ORA $44`,
  sat on a black screen, interpreted and recompiled alike. Check those lines first when an MMC3
  game gets lost early.
- `mos_Null` at the top of a profile is the interpreter stopped on an illegal opcode (it spins
  in place): the 6502 jumped into data. Trace it (above).
- Recompiled code can't be compared instruction by instruction, but paced RAM comparison with the
  interpreter finds its bugs. Two found that way: flags tested after a jump past a misdecoded
  instruction, and a loop fill's start taken from the wrong path. A third, an NMI held for a
  wait loop delivered where the game only passed one, showed up by logging where NMIs land.

## Where things are

- NMI timing: `MD_Vint` (`md.asm`) makes NMIs due (`FamiMdVint`, `nmiWaitDue`, `nmiCredit`).
  Recompiled, `rcNmiDue` (`emu/recomp.asm`) takes one or holds it: until the game waits again
  (`nmiHold`, up to a frame), until the NMI handler's RTI (`vbLate`), until MMC3's IRQ handler's
  last RTI (`irqVbls`, up to 8); `rcRti` takes what's waiting. Interpreted: `famiVInt` (`md.asm`),
  `mos_RTI` (`emu/cpu.asm`).
- Recompiler (`tools/recomp6502.py`): units (the fixed bank, each switchable bank), `targets`
  (joins: a branch there reloads flags from `d3`), `idle_heads` (wait loops: their NMI check is
  on the way back, not on the way in), `plans` (fills, versioned loops; `body_plan` in routine
  copies), routine copies and inlined routines, `rcDelay` for delay loops. Where code starts:
  `analyze` (vectors, `jump_tables` from the code that reads them, `data_tables` from the bytes
  no code covers); every table target is an entry (`extra`: `rcDispatch` goes there with
  nothing the code before it left, and `rcSafe` lets the interpreter go on there).
- Mappers: `wrTo_PRG` (`emu/memory.asm`) by `cpuMapper`; the loader's list in `Fami_LoadRom`
  (`md.asm`); the recompiler's `Prg` and its store translation (`mapper2Write`, `mmc1Write`,
  `mmc3...`). MMC1's state shares `mmc3Regs`' bytes: the emulator's variables are full in
  MMC3 builds with 8 KB banks (an assembler error says so). MMC1 switching 32 KB at a time
  (MMC1_32K): each bank a unit of its own (`prg32`), dispatch by `rcCurTable` for all of
  $8000-$FFFF. CHR-ROM bank switches (MMC1, MMC3: CHR_BANKED) go through `chrUpdate`.
- MMC3 split: `splitBegin`, `splitNext`, `splitDone`, the window plane (`emu/ppu.asm`).
- CHR-RAM: `ppuChrRamWrite` (each `$2007` write); CHR-ROM bank switches: `chrUpdate`. The BG
  pattern table: `wrPPU_Ctrl` keeps the one wanted, `chrBgSet`/`chrBgDue` convert it where the
  NES would draw with it (`ppuChrBank`: bit 7 the BG set's table, bit 15 the wanted one).
- Sprite 0 and the top of the screen: `rdPPU_Status` (`ppuSp0State`, the read sites
  `ppuRdSite` and `ppuRdSite2`, the latter in `vLineTbl`'s scratch half).

## Open requests

From players' reports (games still to try, with what was seen):

- The Flintstones (both, MMC3): the HUD is glitched, maybe the level's bottom layer.
- Pac-Man (Tengen, NROM): starts, then freezes or takes no input. Recompiled it plays (its
  build didn't assemble before); interpreted it stays on a black screen, not looked into yet.
  A small orange dash shows at the top left corner of its screen.
- Star Wars: The Empire Strikes Back (MMC3): slight graphics issues. Dig Dug (NROM): a glitch
  at boot only.
- Custom palette support.
