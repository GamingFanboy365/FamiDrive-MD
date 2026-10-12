#!/bin/bash
# usage: ./build.sh [nes_rom]    (default: roms/nestest.nes)
set -e
ROM=${1:+$(realpath -m "$1")}
cd "$(dirname "$0")"
ROM=${ROM:-roms/nestest.nes}

if [ ! -f "$ROM" ]; then
	echo "build: $ROM not found (see README)" >&2
	exit 1
fi
mkdir -p out
cp "$ROM" out/nes_rom.bin

# MD ROM
echo "** MEGA DRIVE **"
tools/AS/linux/asl md.asm -q -xx -c -A -olist out/rom_md.lst -A -L -D MCD=0,MARS=0,MARSCD=0
python3 tools/p2bin.py md.p out/rom_md.bin
rm -f md.p md.h
