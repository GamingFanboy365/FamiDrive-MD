#!/bin/bash
# usage: tools/hwtest/build.sh -- builds out/hwtest.bin, the hardware test ROM
# (see tools/hwtest/README.md). It uses FamiDrive's emu/vlines.asm, so it's
# assembled from the top folder.
set -e
cd "$(dirname "$0")/../.."
mkdir -p out
tools/AS/linux/asl tools/hwtest/hwtest.asm -q -xx -A -L -olist out/hwtest.lst -o out/hwtest.p
python3 tools/p2bin.py out/hwtest.p out/hwtest.bin
rm -f out/hwtest.p
echo "out/hwtest.bin"
