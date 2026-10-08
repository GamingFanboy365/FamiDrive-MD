# TODO

Known issues and cleanup, roughly in priority order.

## Emulation

- [ ] **6502 status register layout.** PHP, PLP, NMI (`doVint`), BRK and RTI
  push/pull the raw 68k CCR (`X N Z V C`) instead of the 6502 `NV-BDIZC`
  layout, and the B flag is never set. Games that PHP then PLA and inspect the
  bits get wrong values. Convert on push/pull (see the TODO above `emuLoop`).
- [ ] **Sprite 0 hit when off-screen.** `rdPPU_Status` reports a hit whenever
  sprite 0 Y >= `$E0`; real hardware never does. Fix it, or document it if it
  is an intentional anti-hang hack.
- [ ] **`$2007` read address not masked.** `rdPPU_Data` indexes the PPU buffer
  with an unmasked `ppuAddrBase`; `wrPPU_Data` already masks to `$3FFF`.

## ROM loading

- [ ] **Errors for unsupported ROMs.** Unknown mappers silently run as NROM,
  PRG sizes other than 16/32 KB hit `trap #2` (silent hang), and a bad iNES
  header hangs at `bne.s *`. Show a short message on screen instead.
- [ ] **CHR-RAM games (0 CHR banks).** `Fami_LoadRom` always copies 8 KB of CHR
  from after the PRG data; with CHR-RAM it should clear the pattern tables and
  let `$2007` writes fill them.
- [ ] **ROM path.** The ROM is hard-coded to `roms/nestest.nes` (gitignored).
  Document where to put a ROM in the README and/or make the path a `build.sh`
  argument.

## Repo and build

- [ ] **Untrack build output.** `out/rom_md.bin` and `out/rom_md.lst` are
  tracked despite `.gitignore` (the `.bin` also embeds `nestest.nes`). KDE
  `.directory` files are tracked in six folders.
- [ ] **Dead code.** `system/md/{system,video,sound,head}.asm` are never
  included; `video.asm` references a nonexistent `engine/shared/*.bin`.
- [ ] **Build scripts.** `build.sh` should use `python3` and stop on failure
  (`set -e`); add a Windows script for the bundled `asw.exe`. `p2bin.py` should
  print clear errors and exit non-zero on failure.

## Readability

- [ ] **Disassembler labels.** Replace `loc_XXXX`/`off_XXXX` labels and
  `DATA XREF` comments with named opcode handlers (`op_PHP`, `op_SBC_imm`, ...).
- [ ] **Split `md.asm`** into CPU, PPU, APU/input and mapper files.
