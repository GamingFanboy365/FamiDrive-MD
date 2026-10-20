#!/usr/bin/env python3
"""nrom.py OUT -- writes a small NROM game for FamiDrive's checks (no NES ROM is in the repo).

It turns on NMIs and rendering, then loops. Its NMI handler sets the scroll (both bytes of
$2005, so FamiDrive takes later scroll changes as possible splits), waits a different time
each frame (0-63 turns of a DEX/BNE loop, by the frame count), and sets a new X scroll. The
waits spread that write over VBlank; it should never become a split low on the screen, as it
did on an AtGames handheld whose V counter reads $7E/$7F in VBlank's last lines.
"""
import sys

RESET = [
    0x78,                   # C000 SEI
    0xD8,                   # C001 CLD
    0xA2, 0xFF,             # C002 LDX #$FF
    0x9A,                   # C004 TXS
    0xA9, 0x18,             # C005 LDA #$18
    0x8D, 0x01, 0x20,       # C007 STA $2001      background and sprites on
    0xA9, 0x80,             # C00A LDA #$80
    0x8D, 0x00, 0x20,       # C00C STA $2000      NMIs on
    0x4C, 0x0F, 0xC0,       # C00F JMP $C00F
]
NMI = [
    0xE6, 0x00,             # C020 INC $00        frames
    0xA9, 0x00,             # C022 LDA #0
    0x8D, 0x05, 0x20,       # C024 STA $2005      X
    0x8D, 0x05, 0x20,       # C027 STA $2005      Y
    0xA5, 0x00,             # C02A LDA $00
    0x29, 0x3F,             # C02C AND #$3F
    0xAA,                   # C02E TAX
    0xF0, 0x03,             # C02F BEQ $C034
    0xCA,                   # C031 DEX
    0xD0, 0xFD,             # C032 BNE $C031
    0xA5, 0x00,             # C034 LDA $00
    0x8D, 0x05, 0x20,       # C036 STA $2005      a new X
    0xA9, 0x00,             # C039 LDA #0
    0x8D, 0x05, 0x20,       # C03B STA $2005
    0x40,                   # C03E RTI
]

prg = bytearray([0xEA] * 0x4000)            # 16 KB at $C000 (NOPs)
prg[0x0000:len(RESET)] = bytes(RESET)
prg[0x0020:0x0020 + len(NMI)] = bytes(NMI)
prg[0x3FFA:0x4000] = bytes([0x20, 0xC0,     # NMI   $C020
                            0x00, 0xC0,     # RESET $C000
                            0x3E, 0xC0])    # IRQ   $C03E (RTI)
chr_rom = bytes(0x2000)
header = b'NES\x1a' + bytes([1, 1, 0, 0]) + bytes(8)

with open(sys.argv[1], 'wb') as f:
    f.write(header + prg + chr_rom)
