#!/usr/bin/env python3
"""nesinfo.py NES_ROM OUT_ASM -- writes what md.asm needs to know about the NES ROM as it's
assembled: its mapper, its PRG-ROM size (for the banked PRG images, see PRG_IMAGES in md.asm)
and its CHR-ROM size (for the CHR banks' mask).
Fami_LoadRom checks the ROM again as it starts, and shows an error screen for what isn't
supported; for a ROM too broken to read here, this writes zeros.

For an MMC3 game with CHR-ROM it also writes chr_md.bin next to OUT_ASM: the CHR-ROM as MD
tiles, for the BG and then for sprites (CHR_MD in md.asm), which its bank switches copy
instead of converting; then a word for each tile, its ID: the number of the first tile
like it (CHR_ID), by which they tell the tiles that change (chrUpdate in emu/ppu.asm).

For an MMC3 game it also tells, from its code, whether it puts the MMC3 in PRG mode 1
(8 KB banks at $A000 and $C000, as Super Mario Bros. 3) or switches the 8 KB banks at
$8000 and $A000 apart in mode 0 (as Mega Man 3; either way PRG_8K in md.asm, a frame for
each 8 KB bank instead of an image for each 16 KB pair), and whether it turns the scanline
IRQ on (MMC3_IRQ).

And for any game, whether its NMI handler puts another return address in its own
interrupt frame, to go on there after its RTI (as Mega Man 3: NMI_TAIL in md.asm)."""
import os
import re
import sys


def mmc3_use(prg):
    """(PRG mode 1, R6 and R7 apart in PRG mode 0, IRQ): in the code, an immediate
    value with bit 6 set stored to $8000 (bank select: LDA/LDX/LDY #, STA/STX/STY);
    without that, R6 or R7 picked that way (#$06, #$07) and its bank loaded from
    memory or as a constant right after and stored to $8001 (as Mega Man 3: LDA #$06,
    STA $8000, LDA $F4, STA $8001; a zero page store may follow each load), which a
    game that only switches them as a 16 KB pair (Super Mario Bros. 2: the second
    is the first, ORA #$01) doesn't do; and a store to $E001 (IRQ enable).
    (tools/recomp6502.py looks for the same.)"""
    mode1 = any(m.group(1)[0] & 0x40 for m in re.finditer(rb'[\xA9\xA2\xA0](.)[\x8D\x8E\x8C]\x00\x80', prg, re.S))
    apart = not mode1 and re.search(rb'\xA9[\x06\x07](?:\x85.)?\x8D\x00\x80(?:\xA5.|\xAD..|\xA9.)(?:\x85.)?\x8D\x01\x80',
                                    prg, re.S) is not None
    irq = re.search(rb'[\x8D\x8E\x8C]\x01\xE0', prg) is not None
    return mode1, apart, irq


def nmi_tail(prg):
    """Where an interrupt handler goes on after its RTI, 0 if nowhere: the address it puts
    in its own interrupt frame, a constant's two bytes stored to neighbouring bytes of the
    stack by X (after TSX: LDA #>addr, STA $0107,X, LDA #<addr, STA $0106,X, as Mega Man 3,
    whose NMI handler leaves its sound code for after the RTI that way).
    (tools/recomp6502.py looks for the same.)"""
    for m in re.finditer(rb'\xA9(.)\x9D(.)\x01\xA9(.)\x9D(.)\x01', prg, re.S):
        v1, o1, v2, o2 = (m.group(k)[0] for k in (1, 2, 3, 4))
        if abs(o1 - o2) == 1 and min(o1, o2) >= 3 and max(o1, o2) <= 8:
            addr = (v1 << 8 | v2) if o1 > o2 else (v2 << 8 | v1)
            if addr >= 0x8000:
                return addr
    return 0


rom = open(sys.argv[1], 'rb').read()
mapper = prg16 = chr8 = 0
if len(rom) >= 16 and rom[:4] == b'NES\x1a':
    # As Fami_LoadRom: byte 7 has the mapper's high bits, but old dumps can have junk (such as
    # "DiskDude!") in bytes 7-15, so it's ignored then unless the header is NES 2.0
    high = rom[7] & 0xF0
    if (rom[7] & 0x0C) != 0x08 and any(rom[12:16]):
        high = 0
    mapper = (rom[6] >> 4) | high
    prg16 = rom[4]
    chr8 = rom[5]
    if len(rom) < 16 + prg16 * 0x4000:          # cut short: no images (the error screen says why)
        prg16 = 0

with open(sys.argv[2], 'w') as out:
    out.write('; written by tools/nesinfo.py from %s\n' % sys.argv[1])
    out.write('NES_MAPPER\tequ %d\n' % mapper)
    out.write('NES_PRG16\tequ %d\t\t; PRG-ROM in 16 KB banks\n' % prg16)
    out.write('NES_CHR8\tequ %d\t\t; CHR-ROM in 8 KB banks (0: CHR-RAM)\n' % chr8)
    mode1, apart, irq = mmc3_use(rom[16:16 + prg16 * 0x4000]) if mapper == 4 and prg16 else (False, False, False)
    out.write('NES_MMC3_PRG1\tequ %d\t\t; MMC3 PRG mode 1: banks at $A000 and $C000\n' % mode1)
    out.write('NES_MMC3_PRG8\tequ %d\t\t; MMC3 PRG mode 0, its banks at $8000 and $A000 switched apart\n' % apart)
    out.write('NES_MMC3_IRQ\tequ %d\t\t; MMC3 scanline IRQ\n' % irq)
    out.write('NES_NMI_TAIL\tequ $%04X\t\t; where the NMI handler goes on after its RTI (0: nowhere)\n'
              % (nmi_tail(rom[16:16 + prg16 * 0x4000]) if prg16 else 0))

# MD tiles: 4 bits a pixel, the leftmost in the high bits (as ppuChrSpread in
# emu/ppu_tables.asm makes them); NES colors 0-3, sprites' opaque ones +8
if mapper == 4 and chr8 and len(rom) >= 16 + prg16 * 0x4000 + chr8 * 0x2000:
    chr_rom = rom[16 + prg16 * 0x4000:16 + prg16 * 0x4000 + chr8 * 0x2000]
    spread = [sum((b >> k & 1) << (4 * k) for k in range(8)) for b in range(256)]
    bg, spr = bytearray(), bytearray()
    for t in range(0, len(chr_rom), 16):
        for y in range(8):
            p0, p1 = chr_rom[t + y], chr_rom[t + y + 8]
            row = spread[p0] | spread[p1] << 1
            bg += row.to_bytes(4, 'big')
            spr += (row | spread[p0 | p1] << 3).to_bytes(4, 'big')
    first, ids = {}, bytearray()
    for t in range(0, len(chr_rom), 16):
        ids += first.setdefault(chr_rom[t:t + 16], t // 16).to_bytes(2, 'big')
    with open(os.path.join(os.path.dirname(sys.argv[2]), 'chr_md.bin'), 'wb') as out:
        out.write(bg + spr + ids)
