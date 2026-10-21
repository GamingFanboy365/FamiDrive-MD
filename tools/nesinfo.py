#!/usr/bin/env python3
"""nesinfo.py NES_ROM OUT_ASM -- writes what md.asm needs to know about the NES ROM as it's
assembled: its mapper, its PRG-ROM size (for the banked PRG images, see PRG_IMAGES in md.asm)
and its CHR-ROM size (for the CHR banks' mask).
Fami_LoadRom checks the ROM again as it starts, and shows an error screen for what isn't
supported; for a ROM too broken to read here, this writes zeros."""
import sys

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
