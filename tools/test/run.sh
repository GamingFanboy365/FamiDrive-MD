#!/bin/bash
# usage: tools/test/run.sh -- checks that FamiDrive still works on an AtGames Genesis handheld
# (see tools/hwtest/README.md), whose VDP differs from a Mega Drive's in what FamiDrive depends on.
#
# It builds Genesis Plus GX (libretro) twice: as it is, and changed to act like the handheld
# (gpgx_atgames.py). It runs FamiDrive on both, interpreted and recompiled, with a small game it
# writes (nrom.py), and checks what FamiDrive measured and did (check.py). GitHub runs it on
# every push and pull request (.github/workflows/build.yml).
#
# Needs git, make, a C compiler and Python 3, and the first time, the internet (to fetch
# Genesis Plus GX). Its work goes in out/test/; your own build in out/ is kept.
set -e
cd "$(dirname "$0")/../.."
GPGX_URL=https://github.com/libretro/Genesis-Plus-GX
GPGX_COMMIT=aa74d79634cd230f65cce4180e92688e53883d2f
W=out/test
mkdir -p $W

# Genesis Plus GX, built again only when GPGX_COMMIT or gpgx_atgames.py changes
stamp="$GPGX_COMMIT $(sha1sum tools/test/gpgx_atgames.py | cut -d' ' -f1)"
if [ "$(cat $W/cores/stamp 2>/dev/null)" != "$stamp" ]; then
	echo "** Genesis Plus GX **"
	rm -rf $W/gpgx $W/cores
	git init -q $W/gpgx
	git -C $W/gpgx fetch -q --depth 1 $GPGX_URL $GPGX_COMMIT
	git -C $W/gpgx checkout -q FETCH_HEAD
	mkdir -p $W/cores
	gpgx_make() {
		make -C $W/gpgx -f Makefile.libretro -j"$(nproc)" > $W/gpgx.log 2>&1 ||
			{ tail -20 $W/gpgx.log; echo "(the whole log: $W/gpgx.log)"; exit 1; }
	}
	gpgx_make
	cp $W/gpgx/genesis_plus_gx_libretro.so $W/cores/md.so
	python3 tools/test/gpgx_atgames.py $W/gpgx
	gpgx_make
	cp $W/gpgx/genesis_plus_gx_libretro.so $W/cores/atgames.so
	echo "$stamp" > $W/cores/stamp
fi

# FamiDrive with the test game. build.sh builds into out/: keep what's there
keep="rom_md.bin rom_md.lst nes_rom.bin recomp.asm"
rm -rf $W/keep && mkdir -p $W/keep
for f in $keep; do [ -f out/$f ] && cp out/$f $W/keep/; done
restore() { for f in $keep; do rm -f out/$f; [ -f $W/keep/$f ] && cp $W/keep/$f out/; done; true; }
trap restore EXIT

python3 tools/test/nrom.py $W/test.nes
status=0
python3 tools/test/check.py source || status=1
for build in interpreted recompiled; do
	opt=; [ $build = recompiled ] && opt=--recompile
	./build.sh $opt $W/test.nes >/dev/null
	cp out/rom_md.bin $W/$build.bin
	cp out/rom_md.lst $W/$build.lst
	for core in md atgames; do
		python3 tools/test/libretro.py $W/cores/$core.so $W/$build.bin 600 $W/$build-$core.ram
	done
	python3 tools/test/check.py $build $W/$build.lst $W/$build-md.ram $W/$build-atgames.ram || status=1
done
[ $status = 0 ] && echo "All AtGames checks passed"
exit $status
