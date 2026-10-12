#!/bin/bash
set -e
cd "$(dirname "$0")"

if [ ! -f roms/nestest.nes ]; then
	echo "build: roms/nestest.nes not found (see README)" >&2
	exit 1
fi
mkdir -p out

# MD ROM
echo "** MEGA DRIVE **"
tools/AS/linux/asl md.asm -q -xx -c -A -olist out/rom_md.lst -A -L -D MCD=0,MARS=0,MARSCD=0
python3 tools/p2bin.py md.p out/rom_md.bin
rm -f md.p md.h
