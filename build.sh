#!/bin/bash
# usage: ./build.sh [--recompile] [nes_rom]    (default: roms/nestest.nes)
#
# --recompile translates the game's 6502 code to 68000 code at build
# time (tools/recomp6502.py) instead of interpreting it. Much faster,
# NROM/CNROM games only.
set -e
RECOMP=0
if [ "$1" = "--recompile" ]; then
	RECOMP=1
	shift
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
if [ $RECOMP = 1 ]; then
	python3 tools/recomp6502.py out/nes_rom.bin out/recomp.asm
fi

# MD ROM
echo "** MEGA DRIVE **"
tools/AS/linux/asl md.asm -q -xx -c -A -olist out/rom_md.lst -A -L -D MCD=0,MARS=0,MARSCD=0,RECOMP=$RECOMP
python3 tools/p2bin.py md.p out/rom_md.bin
rm -f md.p md.h
