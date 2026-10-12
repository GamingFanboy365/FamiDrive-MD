#!/usr/bin/env python3
# ======================================================================
# p2bin: convert an AS assembler .p file to a flat binary
#
# usage: p2bin.py input.p output.bin
# ======================================================================

import struct
import sys

P_MAGIC = 0x1489


def fail(msg):
	print("p2bin: " + msg, file=sys.stderr)
	sys.exit(1)


def read(f, size, what):
	data = f.read(size)
	if len(data) != size:
		fail("unexpected end of file while reading " + what)
	return data


def convert(in_path, out_path):
	try:
		src = open(in_path, "rb")
	except OSError as e:
		fail("can't open %s: %s" % (in_path, e.strerror))

	with src, open(out_path, "wb") as dst:
		magic, = struct.unpack("<H", read(src, 2, "header"))
		if magic != P_MAGIC:
			fail("%s is not an AS .p file" % in_path)

		while True:
			rec = read(src, 1, "record type")[0]
			if rec == 0x00:
				break				# creator string follows; done
			elif rec == 0x80:
				read(src, 4, "entry point")	# entry point, unused
				continue
			elif rec == 0x81:
				read(src, 3, "record header")	# CPU, segment, granularity
			elif rec > 0x81:
				fail("unknown record type $%02X at offset $%X" % (rec, src.tell() - 1))
			# $01-$7F: legacy record, the type byte is the CPU

			start, length = struct.unpack("<IH", read(src, 6, "record address"))
			dst.seek(start)
			dst.write(read(src, length, "record data"))


if __name__ == "__main__":
	if len(sys.argv) != 3:
		print("usage: p2bin.py input.p output.bin", file=sys.stderr)
		sys.exit(2)
	convert(sys.argv[1], sys.argv[2])
