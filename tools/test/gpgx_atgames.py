#!/usr/bin/env python3
"""gpgx_atgames.py SOURCE_DIR -- changes a Genesis Plus GX (libretro) source tree to imitate, for
FamiDrive's checks, what an AtGames Genesis handheld does differently from a Mega Drive in what
FamiDrive depends on (see tools/hwtest/README.md):

- an NTSC frame is 246 lines long (224 shown, 22 of VBlank) rather than 262
- in VBlank the V counter reads $E0, then $F4-$FF, then $7E or $7F (values of the middle of the
  screen) for VBlank's last 9 lines
- the VBlank flag stays on until the screen's second line (V $01)
"""
import sys


def patch(path, changes, count=1):
    src = open(path, newline='').read()
    nl = '\r\n' if '\r\n' in src else '\n'
    for old, new in changes:
        old, new = old.replace('\n', nl), new.replace('\n', nl)
        if src.count(old) != count:
            sys.exit('gpgx_atgames.py: ' + path + ' is not as expected (looking for: '
                     + old.strip().splitlines()[0].strip() + ')')
        src = src.replace(old, new)
    open(path, 'w', newline='').write(src)


src_dir = sys.argv[1]

patch(src_dir + '/core/vdp_ctrl.c', [
    ('  lines_per_frame = vdp_pal ? 313: 262;\n',
     '  lines_per_frame = vdp_pal ? 313: 246;\n'),

    # the V counter
    ('''  /* Cycle-accurate VCounter */
  vc = v_counter;
  if ((cycles - mcycles_vdp) >= MCYCLES_PER_LINE)
  {
    vc = (vc + 1) % lines_per_frame;
  }
''', '''  /* Cycle-accurate VCounter */
  vc = v_counter;
  if ((cycles - mcycles_vdp) >= MCYCLES_PER_LINE)
  {
    vc = (vc + 1) % lines_per_frame;
  }

  /* FamiDrive check: an AtGames handheld's V counter in VBlank */
  if (vc >= 225 && !vdp_pal && !interlaced)
  {
    vc = (vc <= 236) ? 0xF4 + (vc - 225) : 0x7E | ((cycles >> 9) & 1);
    data |= ((vc & 0xff) << 8);
    return (data);
  }
'''),

    # the VBlank flag, as the 68000 reads it
    ('''  /* Adjust cycle count relatively to start of line */
  cycles -= mcycles_vdp;

  /* Cycle-accurate VINT flag (Ex-Mutants, Tyrant / Mega-Lo-Mania, Marvel Land, Pacman 2 - New Adventures / Pac-Jr minigame) */
''', '''  /* Adjust cycle count relatively to start of line */
  cycles -= mcycles_vdp;

  /* FamiDrive check: an AtGames handheld's VBLANK flag stays on through the frame's last line
     and the screen's first (this one clears it as the last line starts) */
  if (!vdp_pal && (v_counter == lines_per_frame - 1 || (v_counter == 0 && cycles < MCYCLES_PER_LINE)))
  {
    temp |= 0x08;
  }

  /* Cycle-accurate VINT flag (Ex-Mutants, Tyrant / Mega-Lo-Mania, Marvel Land, Pacman 2 - New Adventures / Pac-Jr minigame) */
'''),
])

patch(src_dir + '/libretro/libretro.c', [         # where the region changes
    ('lines_per_frame = vdp_pal ? 313 : 262;\n',
     'lines_per_frame = vdp_pal ? 313 : 246;\n'),
], count=2)
