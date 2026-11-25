#!/bin/bash
# usage: ./build.sh [--recompile] [--fps] [--palette file.pal] [nes_rom]    (default: roms/nestest.nes)
#
# --recompile translates the game's 6502 code to 68000 code at build
# time (tools/recomp6502.py) instead of interpreting it. Much faster.
# --fps adds a frames-per-second counter (needs --recompile); X, Y or
# Z on a 6-button pad hides or shows it.
# --palette uses the NES colors of a palette file (64 colors, 3 bytes
# each, as emulators use them) instead of the built-in ones.
set -e
RECOMP=0
FPS=0
PALETTE=0
PAL=
while [ "${1#--}" != "$1" ]; do
	case "$1" in
	--recompile) RECOMP=1 ;;
	--fps) FPS=1 ;;
	--palette)
		shift
		if [ -z "$1" ]; then echo "build: --palette needs a file" >&2; exit 1; fi
		PAL=$(realpath -m "$1")
		PALETTE=1 ;;
	*) echo "build: unknown option $1" >&2; exit 1 ;;
	esac
	shift
done
if [ $FPS = 1 ] && [ $RECOMP = 0 ]; then
	echo "build: --fps needs --recompile" >&2
	exit 1
fi
ROM=${1:+$(realpath -m "$1")}
cd "$(dirname "$0")"
ROM=${ROM:-roms/nestest.nes}

if [ ! -f "$ROM" ]; then
	echo "build: $ROM not found (see README)" >&2
	exit 1
fi
mkdir -p out
cp "$ROM" out/nes_rom.bin
python3 tools/nesinfo.py out/nes_rom.bin out/nes_info.asm
if [ $RECOMP = 1 ]; then
	python3 tools/recomp6502.py out/nes_rom.bin out/recomp.asm
fi
if [ $PALETTE = 1 ]; then
	python3 tools/mkpalette.py "$PAL" > out/palette.asm
fi

# MD ROM
echo "** MEGA DRIVE **"
tools/AS/linux/asl md.asm -q -xx -c -A -olist out/rom_md.lst -A -L -D MCD=0,MARS=0,MARSCD=0,RECOMP=$RECOMP,FPS=$FPS,PALETTE=$PALETTE
python3 tools/p2bin.py md.p out/rom_md.bin
rm -f md.p md.h
