# Hardware test ROM

`hwtest.asm` is a small Mega Drive ROM that measures what FamiDrive depends on, for consoles that aren't a Mega Drive, such as AtGames' handhelds and other clones. It shows each result next to a Mega Drive's, so whatever differs stands out. FamiDrive's support for the AtGames handheld came from this ROM's results.

## Building and running

Run `tools/hwtest/build.sh` from anywhere; it writes `out/hwtest.bin`. Load that on the console the same way as a game and wait about two seconds for the measurements.

The **THIS** column is the console you're running it on. The **MD** column is a Mega Drive's value, as Genesis Plus GX and BlastEm both give it; real hardware can differ from it by one or two.

Left and right on the d-pad switch between the two pages. A plays a tone on the YM2612 (FamiDrive's sound for the NES triangle channel) and B the same note on the PSG; C stops them, and START measures everything again. The red and blue stripes at the bottom are scrolled line by line the way FamiDrive scrolls a split screen: the top two rows should slide smoothly and the bottom row stay still.

## Page 1: the line counter

FamiDrive works out which line of the NES screen a game is on from the VDP's V counter, so this page is about the V counter and VBlank.

| Row | What it is | Mega Drive |
|---|---|---|
| VERSION REG | The version register at $A10001 ($A0: an NTSC console sold outside Japan) | A0 |
| CAL LINES/FRAME | Lines a frame, as FamiDrive measures it at startup (`emu/vlines.asm`) | 262 |
| CAL V READ | Different V counter values read in a frame | 256 |
| CAL FIRST UNREAD | The first V value from $E0 on that never came up | -- |
| CAL ODD V LINE | Where FamiDrive puts V counter values it can't trust: ones of the screen ($10-$CF) read with the VBlank flag on | -- |
| V JUMP 1, 2 | The first two places the V counter doesn't count up by one, as FROM>TO | EA>E5 |
| VINT AT V | The V counter when the VBlank interrupt comes | E0 |
| VBLANK ON AT V, OFF AT V | The V counter when the VDP's VBlank flag comes on and goes off | E0, FE |
| TORN V READS | Reads in one frame where the V counter changed by something other than one | 0 |

Below these, the V counter's values through VBlank are listed in the order they came, each as VALUE:LINE, with the line counted from VBlank's start. On a Mega Drive the list goes E0 to EA and then back to E5, which is how an NTSC Mega Drive fits 262 lines into an 8-bit counter. A value that shows one ahead for a moment and then settles (n, n+2, n+1, which the AtGames handheld does) is left out.

## Page 2: speed and sound

| Row | What it is | Mega Drive |
|---|---|---|
| CPU LOOPS/FRAME | Turns of a 26-cycle loop in one frame: the 68000's speed against the frame rate | 4840 |
| LINES BY HINT | Lines a frame, timed with line interrupts rather than the V counter | 262 |
| YM TICKS/60 FR | YM2612 timer A overflows (one every 64 samples) in 60 frames: 834 is 59.9 frames a second if the YM2612 runs at its usual rate | 834 |
| WRITE 2KB ON, OFF | Screen lines taken to write 2 KB to VRAM with the CPU, with the display on and off | 128, 55 |
| WRITE ERRORS ON, OFF | Words of those writes that don't read back the same | 0, 0 |
| DMA 1KB ON, OFF | Screen lines taken by a 1 KB DMA from RAM to VRAM, display on and off | 64, 6 |
| DMA ERRORS | Words of those that don't read back the same | 0 |
| Z80 BUS LOOPS | Loops until the Z80 bus is granted | 0 |
| YM STATUS | The YM2612's status before a write | 00 |
| YM BUSY LOOPS | Loops the YM2612 shows busy after a register write | 4 |

## What an AtGames handheld showed

These come from an AtGames Genesis handheld. Where two values are given, they varied between runs.

| Row | AtGames handheld |
|---|---|
| VERSION REG | A0 |
| CAL LINES/FRAME | 246 |
| CAL V READ | 238, 239 |
| CAL FIRST UNREAD | E1, E2 |
| CAL ODD V LINE | 16 |
| V JUMP 1, 2 | 80>82, 82>81 (and 7F>81, 81>80): the counter shows one ahead for a moment as it changes |
| VINT AT V, VBLANK ON AT V | E0, E0 |
| VBLANK OFF AT V | 01, 02 |
| TORN V READS | 259 |
| V in VBlank | E0, then F3 to FF, then 7E or 7F for VBlank's last 9 lines |
| CPU LOOPS/FRAME | 5886 |
| LINES BY HINT | 246 |
| YM TICKS/60 FR | 811 (about 61.7 frames a second) |
| WRITE 2KB ON, OFF | 52, 52 |
| DMA 1KB ON, OFF | 1, 1 |
| WRITE and DMA ERRORS | 0 |
| Z80 BUS LOOPS, YM STATUS, YM BUSY LOOPS | 0, 00, 0 |

So the handheld draws a shorter frame (246 lines, VBlank 22 lines long) a little faster than a Mega Drive. Its 68000 does about 20% more work a frame, its VDP writes VRAM and runs DMA far faster, and its YM2612 never shows busy. Its V counter is the part that matters to FamiDrive. It skips from $E0 to $F3, reads $7E or $7F (values of the middle of the screen) for VBlank's last 9 lines, and briefly shows one value ahead as it changes. FamiDrive measures the line count and every V value's line at startup, and takes those $7E/$7F reads with the VBlank flag on for line 16, halfway through them; before it did, scroll writes made during VBlank were taken for splits partway down the screen.

## Imitating the handheld's V counter in an emulator

FamiDrive can be tested against a V counter like the handheld's in a build of Genesis Plus GX (libretro) with a few lines added to `vdp_hvc_r` in `core/vdp_ctrl.c`, after the V counter for the current line (`vc`) is worked out:

```c
  /* an AtGames handheld's V counter in VBlank: $E0, then $F4-$FF,
     then 9 lines of $7E/$7F (this frame has 16 more: $E1-$F0) */
  if (vc >= 225 && vc < lines_per_frame && !interlaced)
  {
    if (vc <= 236) vc = 0xF4 + (vc - 225);
    else if (vc <= 245) vc = 0x7E | ((cycles >> 9) & 1);
    else vc = 0xE1 + (vc - 246);
    data |= ((vc & 0xff) << 8);
    return (data);
  }
```

The frame stays 262 lines long, so the line count isn't imitated, but the V counter's odd values are. In an Excitebike race on that build, FamiDrive before it handled them showed 107 out-of-step frames in 2,000 (the bottom panel moving with the track, the stands out of step), and none after.
