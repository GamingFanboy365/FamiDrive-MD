#!/usr/bin/env python3
"""Checks that FamiDrive still works on an AtGames Genesis handheld, whose VDP differs from a Mega
Drive's in what FamiDrive depends on (tools/hwtest/README.md). tools/test/run.sh runs it.

check.py source
    Checks the source for two of the fixes that the runs below can't see.

check.py NAME LISTING MD_DUMP ATGAMES_DUMP
    Checks a build (its listing, for the RAM addresses) from its runs on Genesis Plus GX as it is
    (a Mega Drive) and as changed by gpgx_atgames.py (like the handheld), as libretro.py dumped
    them. The game (nrom.py) only writes the scroll in its NMI handler, at a time spread over
    VBlank: none of those writes should become a split partway down the screen.
"""
import glob
import re
import struct
import sys

DUMP_BASE, DUMP_SIZE = 0xFF8000, 0x1000         # libretro.py's dump: FamiDrive's variables
WHY = 'see tools/hwtest/README.md and CLAUDE.md'
failures = []


def fail(msg):
    failures.append(msg)
    print('  FAIL: ' + msg)


def ok(msg):
    print('  ok: ' + msg)


def finish():
    if failures:
        print('%d check(s) failed (%s)' % (len(failures), WHY))
        sys.exit(1)


# ----------------------------------------------------------------------------------------------
def check_source():
    print('source:')
    # ppuClock reads the V counter until two reads agree: the handheld's can read a mix of the
    # old and new count as it changes (7F, 81, 80)
    src = open('emu/ppu.asm').read()
    m = re.search(r'^ppuClock:(.*?)^\s+rts\b', src, re.M | re.S)
    if not m:
        fail('no ppuClock routine in emu/ppu.asm')
    elif not re.search(r'^\s+cmp\.b\s+8\(a6\),d\d', strip_comments(m.group(1)), re.M):
        fail('ppuClock (emu/ppu.asm) no longer reads the V counter until two reads agree; '
             "an AtGames handheld's can read wrong as it changes")
    else:
        ok('ppuClock reads the V counter until two reads agree')

    # A frame's lines are mdLines, which ppuMeasureLines measures: 246 on the handheld. A 262 in
    # the code is a Mega Drive's frame (only ppuMeasureLines may use it)
    found = []
    for path in ['md.asm'] + sorted(glob.glob('emu/*.asm')):
        routine = None
        for n, line in enumerate(open(path, newline=None), 1):
            m = re.match(r'([A-Za-z_]\w*):', line)
            if m:
                routine = m.group(1)
            if re.search(r'\b262\b', strip_comments(line)) and routine != 'ppuMeasureLines':
                found.append('%s:%d' % (path, n))
    if found:
        more = ' and %d more' % (len(found) - 4) if len(found) > 4 else ''
        fail('262 (a Mega Drive\'s lines a frame) in the code at %s%s: use mdLines(a4), the lines '
             'the console draws (246 on an AtGames handheld). If it means the NES\'s frame, give '
             'it a name (equ)' % (', '.join(found[:4]), more))
    else:
        ok('frame arithmetic uses mdLines, not 262')


def strip_comments(text):
    return re.sub(r';.*', '', text)


# ----------------------------------------------------------------------------------------------
def symbols(listing):
    """The listing's symbol table: name (upper case) -> value"""
    table, started = {}, False
    for line in open(listing, errors='replace'):
        if not started:
            started = 'symbol table' in line
            continue
        for part in line.split('|'):
            m = re.match(r'\s*\*?\s*([A-Za-z_.][\w.]*)\s*:\s*([0-9A-F]+)\s', part)
            if m:
                table[m.group(1).upper()] = int(m.group(2), 16)
    return table


class Run:
    def __init__(self, path, sym):
        data = open(path, 'rb').read()
        self.frames = [data[i:i + DUMP_SIZE] for i in range(0, len(data) - DUMP_SIZE + 1, DUMP_SIZE)]
        base = sym['RAM_FAMI_EMU'] & 0xFFFFFF
        self.at = {name: (base + sym[name.upper()]) - DUMP_BASE for name in
                   ('mdLines', 'vOddLine', 'vLineTbl', 'hsFrame', 'hsCurN', 'hsCur', 'hsDoneN', 'hsDone')
                   if name.upper() in sym}

    def word(self, frame, name, index=0):
        return struct.unpack_from('>H', self.frames[frame], self.at[name] + 2 * index)[0]

    def splits(self):
        """(frame, line) for each split FamiDrive set up: the frame it was drawing and the one
        before it (hsCur, hsDone: up to 8 of line, scroll)"""
        out = []
        for f in range(len(self.frames)):
            for count, table in (('hsCurN', 'hsCur'), ('hsDoneN', 'hsDone')):
                for i in range(min(self.word(f, count), 8)):
                    out.append((f, self.word(f, table, 2 * i)))
        return out


def check_build(name, listing, md_dump, atgames_dump):
    sym = symbols(listing)
    missing = [s for s in ('RAM_FAMI_EMU', 'HSFRAME', 'HSCURN', 'HSCUR', 'HSDONEN', 'HSDONE')
               if s not in sym]
    if missing:
        print(name + ':')
        fail('not in the listing: ' + ', '.join(missing))
        return
    md, atg = Run(md_dump, sym), Run(atgames_dump, sym)
    last = -1
    measured = all(s in sym for s in ('MDLINES', 'VODDLINE', 'VLINETBL'))
    if not measured:
        print(name + ':')
        fail('mdLines, vOddLine or vLineTbl is not in the listing: has the line measurement '
             '(ppuMeasureLines, emu/ppu.asm) gone?')

    for run, console in ((md, 'Mega Drive'), (atg, 'AtGames-like')):
        print('%s, %s:' % (name, console))
        frames, begun = len(run.frames), run.word(last, 'hsFrame')
        if frames < 300 or begun < frames - 60:
            fail('the game began %d frames in %d: it should begin one a frame' % (begun, frames))
            continue
        ok('the game began %d frames in %d' % (begun, frames))
        if not measured:
            continue
        lines, odd = run.word(last, 'mdLines'), run.word(last, 'vOddLine')
        table = [run.word(last, 'vLineTbl', v) for v in range(256)]

        if run is md:
            # The Mega Drive path: exactly what FamiDrive did before it measured anything
            expect('lines a frame (mdLines)', lines, 262)
            expect('line for odd V values (vOddLine)', odd, 0xFFFF, 'none ($FFFF)')
            formula = [v - 0xE0 if v >= 0xE0 else v + 38 for v in range(256)]
            wrong = [v for v in range(256) if table[v] != formula[v]]
            if wrong:
                fail('vLineTbl differs from a Mega Drive\'s at V=' + ', '.join('$%02X' % v for v in wrong[:8]))
            else:
                ok('vLineTbl is a Mega Drive\'s (V+38, $E0 on: V-$E0)')
        else:
            # The handheld: 246 lines; VBlank is $E0, $F4-$FF (lines 1-12), then $7E/$7F (13-21)
            expect('lines a frame (mdLines)', lines, range(244, 249), '246 (give or take 2)')
            expect('line for odd V values (vOddLine)', odd, range(13, 22), 'one of 13-21, '
                   'where VBlank\'s V counter reads $7E/$7F')
            spots = {0xE0: 0, 0xF4: 1, 0xFF: 12, 0x00: 22, 0x70: 134, 0xDF: 245}
            wrong = ['$%02X: %d, not %d' % (v, table[v], l) for v, l in spots.items()
                     if abs(table[v] - l) > (0 if v == 0xE0 else 2)]
            if wrong:
                fail('vLineTbl has the wrong lines for V values: ' + '; '.join(wrong))
            else:
                ok('vLineTbl has the lines measured for V $E0, $F4, $FF, $00, $70 and $DF')

    # The splits: the game writes the scroll only in VBlank (and, interpreted, at the top of the
    # screen as its NMI handler runs on), so on the handheld its splits should be where they are
    # on a Mega Drive. FamiDrive taking VBlank's $7E/$7F for lines of the screen put them halfway
    # down (Excitebike's track and stands out of step)
    print('%s, splits:' % name)
    md_low = max([line for _, line in md.splits()], default=0)
    atg_splits = atg.splits()
    low = [(f, line) for f, line in atg_splits if line > md_low + 8]
    if low:
        fail('on the AtGames-like console, %d of %d splits are more than 8 lines below the lowest '
             'on a Mega Drive (line %d): lines %s, first in frame %d. FamiDrive took a scroll write '
             'in VBlank for one partway down the screen (ppuClock, emu/ppu.asm)'
             % (len(low), len(atg_splits), md_low, sorted({l for _, l in low})[:6], low[0][0]))
    else:
        ok('%d splits on the AtGames-like console, the lowest at line %d (on a Mega Drive: %d)'
           % (len(atg_splits), max([l for _, l in atg_splits], default=0), md_low))


def expect(what, value, want, want_text=None):
    good = value in want if isinstance(want, range) else value == want
    if good:
        ok('%s is %d' % (what, value) if value != 0xFFFF else '%s is none' % what)
    else:
        fail('%s is %d, not %s' % (what, value, want_text or want))


# ----------------------------------------------------------------------------------------------
if len(sys.argv) == 2 and sys.argv[1] == 'source':
    check_source()
elif len(sys.argv) == 5:
    check_build(*sys.argv[1:])
else:
    sys.exit(__doc__)
finish()
