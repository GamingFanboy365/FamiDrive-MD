#!/usr/bin/env python3
# ======================================================================
# recomp6502: translate a NES game's 6502 code into 68000 code
#
# usage: recomp6502.py [--entries FILE] game.nes out.asm
#
# Code is found by following jumps from the reset/NMI/IRQ vectors.
# Code only reached through computed jumps can be listed in FILE
# (hex addresses, one per line); anything not found is interpreted.
#
# Banked PRG-ROM (mappers 2 and 4: a 16 KB bank at $8000, the last at
# $C000) is translated a bank at a time (see Prg and main): the fixed
# bank's code once, and each bank's at $8000 once, with labels B<n>_...
# The fixed bank calls into a bank through rcDispatch, which goes by the
# bank at $8000 then (emu/recomp.asm); a bank calls the fixed bank's
# code directly (its routines' jsr copies, checking after one that may
# switch banks that its own is still there). PRG RAM ($6000-$7FFF) is
# read and written directly.
#
# MMC3 in PRG mode 1 (8 KB banks at $A000 and $C000 that switch apart,
# the last two at $8000 and $E000) is translated likewise (mode1): the
# fixed banks' code once, and each bank's at the slot its own JSRs and
# JMPs point at (slot_homes), with labels A<n>_... and C<n>_...; a
# bank's code goes to the other slot's through rcDispatch, as the fixed
# code goes to both.
#
# The output is included by md.asm when building with RECOMP=1 (see
# build.sh --recompile). It uses the interpreter's register layout so
# the PPU, APU and input code is shared:
#
#   d0 A, d1 X, d2 Y (bytes, upper bits kept zero)
#   d3 6502 stack pointer (high word) | flags as a 68k CCR (low byte)
#   a0 PRG-ROM copy + $8000 (so (a0,d6.w) reads 6502 address d6 >= $8000)
#   a1 PRG-ROM copy (banked PRG: the image of the bank at $8000; MMC3
#      PRG mode 1: R7's frame, and $C000-$DFFF is read through R6's)
#   a2 NES RAM, a3 PPU buffer, a4 emulator vars
#   a6 vdp_data;  d4-d7, a5 are scratch (a5 can stay pointing into RAM
#   from one instruction to the next: Gen.a5_ix)
#
# Flags are only stored into d3 where a later instruction can read them
# (liveness analysis: across units, and through calls by summaries of the
# routines called). A flag test right after the instruction that set
# it uses the 68000's own condition codes; where they're read after the
# test too, each way out puts them in d3, as constants where the test
# decides them (split_plan). NMIs are checked on backward jumps; indirect
# jumps (RTS, RTI, JMP (ind)) go through rcTable.
#
# Hot code gets second copies: routines that return normally are called
# with the 68000's jsr (routine_body), or put in place of the call when
# small (emit_inline), and loops reading through a (zp),Y pointer get a
# guarded fast copy, unrolled when short (version_plan). Fill loops
# become straight stores (fill_plan).
#
# The output contains the game's code in another form: don't publish
# it, keep it in out/ like the built ROM.
# ======================================================================

import functools
import re
import sys

ALL = 0xF					# flag sets: N Z C V bits
DYN_COPY_MAX = 64				# MMC3 PRG mode 1: the most instructions a copy for calls from the other slot has
N, Z, C, V = 1, 2, 4, 8
FLAG_OF = {'BPL': N, 'BMI': N, 'BNE': Z, 'BEQ': Z, 'BCC': C, 'BCS': C, 'BVC': V, 'BVS': V}
CC68 = {'BPL': 'pl', 'BMI': 'mi', 'BNE': 'ne', 'BEQ': 'eq', 'BCC': 'cc', 'BCS': 'cs', 'BVC': 'vc', 'BVS': 'vs'}
INVERT = {'eq': 'ne', 'ne': 'eq', 'pl': 'mi', 'mi': 'pl', 'cc': 'cs', 'cs': 'cc', 'vc': 'vs', 'vs': 'vc'}
# 68000 cycles of the lines Gen.split_fix makes
FIX_CYCLES = {'move': 6, 'scc': 5, 'andi.w': 8, 'andi.b': 8, 'ori.b': 8, 'or.b': 4}
# 68000 instructions that go on to the next line and leave a5 alone
# when it isn't their destination (Gen.a5_ram)
A5_KEEPS = {'move', 'moveq', 'movea', 'movep', 'lea', 'add', 'addq', 'addi', 'addx', 'adda',
	    'sub', 'subq', 'subi', 'subx', 'suba', 'cmp', 'cmpi', 'cmpa', 'tst', 'and', 'andi',
	    'or', 'ori', 'eor', 'eori', 'not', 'neg', 'negx', 'clr', 'ext', 'swap', 'lsl', 'lsr',
	    'asl', 'asr', 'rol', 'ror', 'roxl', 'roxr', 'btst', 'bset', 'bclr', 'bchg'} | \
	   {p + cc for p in 'bs' for cc in ('hi', 'ls', 'cc', 'cs', 'ne', 'eq', 'vc', 'vs',
					    'pl', 'mi', 'ge', 'lt', 'gt', 'le')}
INSN_LABEL = re.compile(r'([A-Za-z0-9_]+):\s+; \$([0-9A-F]{4})  ')	# an instruction's label line

# ----------------------------------------------------------------------
# 6502 decoding
# ----------------------------------------------------------------------

OPS = {}
for base, m in ((0x00, 'ORA'), (0x20, 'AND'), (0x40, 'EOR'), (0x60, 'ADC'),
		(0x80, 'STA'), (0xA0, 'LDA'), (0xC0, 'CMP'), (0xE0, 'SBC')):
	for off, mode in ((1, 'indx'), (5, 'zp'), (9, 'imm'), (0xD, 'abs'),
			  (0x11, 'indy'), (0x15, 'zpx'), (0x19, 'absy'), (0x1D, 'absx')):
		if not (m == 'STA' and mode == 'imm'):
			OPS[base + off] = (m, mode)
for base, m in ((0x00, 'ASL'), (0x20, 'ROL'), (0x40, 'LSR'), (0x60, 'ROR')):
	OPS[base + 0x0A] = (m, 'acc')
	for off, mode in ((6, 'zp'), (0x16, 'zpx'), (0xE, 'abs'), (0x1E, 'absx')):
		OPS[base + off] = (m, mode)
for op, m, mode in (
		(0xC6, 'DEC', 'zp'), (0xD6, 'DEC', 'zpx'), (0xCE, 'DEC', 'abs'), (0xDE, 'DEC', 'absx'),
		(0xE6, 'INC', 'zp'), (0xF6, 'INC', 'zpx'), (0xEE, 'INC', 'abs'), (0xFE, 'INC', 'absx'),
		(0xA2, 'LDX', 'imm'), (0xA6, 'LDX', 'zp'), (0xB6, 'LDX', 'zpy'), (0xAE, 'LDX', 'abs'), (0xBE, 'LDX', 'absy'),
		(0xA0, 'LDY', 'imm'), (0xA4, 'LDY', 'zp'), (0xB4, 'LDY', 'zpx'), (0xAC, 'LDY', 'abs'), (0xBC, 'LDY', 'absx'),
		(0x86, 'STX', 'zp'), (0x96, 'STX', 'zpy'), (0x8E, 'STX', 'abs'),
		(0x84, 'STY', 'zp'), (0x94, 'STY', 'zpx'), (0x8C, 'STY', 'abs'),
		(0xE0, 'CPX', 'imm'), (0xE4, 'CPX', 'zp'), (0xEC, 'CPX', 'abs'),
		(0xC0, 'CPY', 'imm'), (0xC4, 'CPY', 'zp'), (0xCC, 'CPY', 'abs'),
		(0x24, 'BIT', 'zp'), (0x2C, 'BIT', 'abs'),
		(0x4C, 'JMP', 'abs'), (0x6C, 'JMP', 'ind'), (0x20, 'JSR', 'abs')):
	OPS[op] = (m, mode)
for op, m in ((0x10, 'BPL'), (0x30, 'BMI'), (0x50, 'BVC'), (0x70, 'BVS'), (0x90, 'BCC'),
	      (0xB0, 'BCS'), (0xD0, 'BNE'), (0xF0, 'BEQ')):
	OPS[op] = (m, 'rel')
for op, m in ((0x00, 'BRK'), (0x40, 'RTI'), (0x60, 'RTS'), (0x08, 'PHP'), (0x28, 'PLP'),
	      (0x48, 'PHA'), (0x68, 'PLA'), (0x88, 'DEY'), (0xA8, 'TAY'), (0xC8, 'INY'),
	      (0xE8, 'INX'), (0x18, 'CLC'), (0x38, 'SEC'), (0x58, 'CLI'), (0x78, 'SEI'),
	      (0x98, 'TYA'), (0xB8, 'CLV'), (0xD8, 'CLD'), (0xF8, 'SED'), (0x8A, 'TXA'),
	      (0x9A, 'TXS'), (0xAA, 'TAX'), (0xBA, 'TSX'), (0xCA, 'DEX'), (0xEA, 'NOP')):
	OPS[op] = (m, None)
assert len(OPS) == 151

SIZE = {'imm': 2, 'zp': 2, 'zpx': 2, 'zpy': 2, 'indx': 2, 'indy': 2, 'rel': 2,
	'abs': 3, 'absx': 3, 'absy': 3, 'ind': 3, 'acc': 1, None: 1}

# flags used / defined by each mnemonic
USES = {'ADC': C, 'SBC': C, 'ROL': C, 'ROR': C, 'PHP': ALL, 'BRK': ALL}
USES.update({b: f for b, f in FLAG_OF.items()})


def uses(i):
	"""Flags instruction i reads: ADC and SBC don't read a carry known
	where they are (Insn.cin)."""
	return USES.get(i.m, 0) & ~(C if i.cin else 0)

DEFS = {m: N | Z for m in ('LDA', 'LDX', 'LDY', 'TAX', 'TAY', 'TXA', 'TYA', 'TSX', 'PLA',
			   'INX', 'INY', 'DEX', 'DEY', 'INC', 'DEC', 'AND', 'ORA', 'EOR')}
DEFS.update({'ADC': ALL, 'SBC': ALL, 'CMP': N | Z | C, 'CPX': N | Z | C, 'CPY': N | Z | C,
	     'ASL': N | Z | C, 'LSR': N | Z | C, 'ROL': N | Z | C, 'ROR': N | Z | C,
	     'BIT': N | Z | V, 'CLC': C, 'SEC': C, 'CLV': V, 'PLP': ALL, 'RTI': ALL})


class Insn:
	def __init__(self, pc, op, prg):
		self.pc, self.op = pc, op
		self.m, self.mode = OPS[op]
		self.n = SIZE[self.mode]
		b = [prg.byte(pc + 1), prg.byte(pc + 2)]
		if self.n == 2:
			self.arg = b[0]
			if self.mode == 'rel':
				self.arg = (pc + 2 + (b[0] - 256 if b[0] > 127 else b[0])) & 0xFFFF
		elif self.n == 3:
			self.arg = b[0] | b[1] << 8
		else:
			self.arg = None
		self.succ = []			# successor addresses, None = unknown
		self.decided = None		# for branches: 'taken' / 'not' if the flags are known
		self.cin = None			# ADC/SBC: (carry in, where it became known) if known
		self.table = None		# a JSR to a jump engine: the table after it

	def text(self):
		f = {'imm': '#$%02X', 'zp': '$%02X', 'zpx': '$%02X,X', 'zpy': '$%02X,Y', 'indx': '($%02X,X)',
		     'indy': '($%02X),Y', 'abs': '$%04X', 'absx': '$%04X,X', 'absy': '$%04X,Y', 'ind': '($%04X)',
		     'rel': '$%04X', 'acc': 'A', None: ''}[self.mode]
		return (self.m + ' ' + (f % self.arg if '%' in f else f)).strip()


@functools.lru_cache(maxsize=4)
def mmc3_mode1(prg):
	"""Does the code put the MMC3 in PRG mode 1: an immediate value with
	bit 6 set stored to $8000 (LDA/LDX/LDY #, STA/STX/STY)? As
	NES_MMC3_PRG1 from tools/nesinfo.py, which looks for the same."""
	return any(m.group(1)[0] & 0x40 for m in re.finditer(rb'[\xA9\xA2\xA0](.)[\x8D\x8E\x8C]\x00\x80', prg, re.S))


@functools.lru_cache(maxsize=4)
def mmc3_irq(prg):
	"""Does the code turn MMC3's scanline IRQ on: a store to $E001
	(STA/STX/STY)? As NES_MMC3_IRQ from tools/nesinfo.py (MMC3_IRQ in
	md.asm), which looks for the same."""
	return re.search(rb'[\x8D\x8E\x8C]\x01\xE0', prg) is not None


class Prg:
	"""PRG-ROM as one translation unit's code sees it.
	NROM and CNROM (unit None): all of $8000-$FFFF, one unit.
	Banked PRG (mappers 2, 4: a 16 KB bank at $8000, the last at $C000,
	see PRG_IMAGES in md.asm): the fixed bank is unit 'F', and each bank
	n at $8000 is unit n, which sees the fixed bank too (its code calls
	and reads it). The fixed bank's code can't know which bank is at
	$8000: those addresses are other units' (bank units go by the bank
	at $8000 when they're called, rcDispatch).
	MMC3 in PRG mode 1 (mode1, as Super Mario Bros. 3: R7's 8 KB bank at
	$A000 and R6's at $C000 switch apart, the second to last bank is at
	$8000 and the last at $E000, see PRG_FRAMES in md.asm): the fixed
	banks are unit 'F', and each bank b at $A000 and at $C000 is unit
	('A', b) and ('C', b). Each sees the fixed banks, but not the other
	slot: like the fixed code's, its calls there go by the bank there."""
	def __init__(self, rom, unit=None):
		if rom[:4] != b'NES\x1a':
			sys.exit('recomp6502: not an iNES file')
		hi = rom[7] & 0xF0
		if rom[7] & 0x0C != 0x08 and any(rom[12:16]):
			hi = 0			# junk in old headers ("DiskDude!"), as md.asm does
		self.mapper = rom[6] >> 4 | hi
		if self.mapper not in (0, 2, 3, 4):
			sys.exit('recomp6502: mapper %d is not supported' % self.mapper)
		self.banked = self.mapper in (2, 4)
		prg = rom[16:16 + rom[4] * 0x4000]
		self.mode1 = self.mapper == 4 and mmc3_mode1(prg)
		self.irq = self.mapper == 4 and mmc3_irq(prg)
		self.banks = len(prg) // 0x4000
		self.banks8 = len(prg) // 0x2000
		self.unit = unit
		if self.mode1:
			self.fixed = prg[-0x4000:]	# $8000-$9FFF, then $E000-$FFFF
			if unit in (None, 'F'):
				self.data, self.slot = self.fixed, 'F'
				self.regions = [(0x8000, 0x9FFF), (0xE000, 0xFFFF)]
			else:
				self.slot, b = unit
				self.data = prg[b * 0x2000:(b + 1) * 0x2000]
				lo = 0xA000 if self.slot == 'A' else 0xC000
				self.regions = [(lo, lo + 0x1FFF)]
			self.lo, self.hi = self.regions[0][0], self.regions[-1][1]
			self.mask = len(self.data) - 1
			self.peers = []
			return
		self.fixed = prg[-0x4000:]
		if not self.banked or unit is None:	# (banked: only the header is read)
			self.data, self.lo = prg, 0x8000	# (16 KB is at $8000 and $C000)
		elif unit == 'F':
			self.data, self.lo = self.fixed, 0xC000
		else:
			self.data, self.lo = prg[unit * 0x4000:(unit + 1) * 0x4000], 0x8000
		self.mask = len(self.data) - 1
		self.hi = 0xFFFF if not self.banked or unit == 'F' else 0xBFFF
		self.regions = [(self.lo, self.hi)]
		self.slot = 'F' if not self.banked or unit in (None, 'F') else 'B'
		self.peers = []			# other units, for plausible_code

	def region(self, a):
		"""Which code is at a ($8000-$FFFF): 'F', the fixed code's, or
		'B' (the bank at $8000), 'A' or 'C' (MMC3 PRG mode 1: the bank
		at $A000 or at $C000)."""
		if self.mode1:
			return 'F' if a < 0xA000 or a >= 0xE000 else 'A' if a < 0xC000 else 'C'
		return 'F' if not self.banked or a >= 0xC000 else 'B'

	def byte(self, a):
		"""The byte at a, if this unit can know it."""
		if a < 0x8000:
			return None
		if self.mode1:
			if a > 0xFFFF:
				return None
			if a < 0xA000:
				return self.fixed[a - 0x8000]
			if a >= 0xE000:
				return self.fixed[a - 0xC000]
			lo = self.regions[0][0]
			return self.data[a - lo] if self.slot != 'F' and lo <= a < lo + 0x2000 else None
		if not self.banked:
			return self.data[a & self.mask]
		if a > 0xFFFF:
			return None
		if a >= 0xC000:
			return self.fixed[a - 0xC000]
		return self.data[a - 0x8000] if self.unit != 'F' else None

	def word(self, a):
		return self.byte(a) | self.byte(a + 1) << 8

	def has(self, a):
		"""Is a in this unit's own code?"""
		return any(lo <= a <= hi for lo, hi in self.regions)

	def const(self, a):
		"""Is a's byte the same whatever bank is at $8000, while this
		unit's code runs?"""
		return self.byte(a) is not None

# ----------------------------------------------------------------------
# Code discovery
# ----------------------------------------------------------------------

# PPU register handlers ($2000-$2007, emu/memory.asm and emu/ppu.asm),
# called directly rather than through rdFrom_PPU/wrTo_PPU
PPU_READ = ('rdPPU_OpenBus', 'rdPPU_OpenBus', 'rdPPU_Status', 'rdPPU_OpenBus',
	    'rdPPU_OamData', 'rdPPU_OpenBus', 'rdPPU_OpenBus', 'rdPPU_Data')
PPU_WRITE = ('wrPPU_Ctrl', 'wrPPU_Mask', 'wrPPU_Status', 'wrPPU_OamAddr',
	     'wrPPU_OamData', 'wrPPU_Scroll', 'wrPPU_Addr', 'wrPPU_Data')


def inline_table_routine(prg, f):
	"""Does the routine at f pull its own return address and jump
	through a pointer (a "jump engine")? Then the bytes after each JSR
	to it are a table of addresses, not code."""
	pulls, pc = 0, f
	for _ in range(24):
		op = prg.byte(pc) if pc >= 0x8000 else None
		if op not in OPS:
			return False
		m, mode = OPS[op]
		if m == 'PLA':
			pulls += 1
		elif m == 'JMP' and mode == 'ind':
			return pulls >= 2
		elif m in ('RTS', 'RTI', 'BRK', 'JSR', 'JMP', 'PHA', 'PHP', 'TSX', 'TXS') or mode == 'rel':
			return False
		pc += SIZE[mode]
	return False


def engine_pattern(prg, f):
	"""(zp1, zp2) if the routine at f is the usual jump engine: ASL A,
	TAY, PLA, STA zp1, PLA, STA zp1+1, INY, LDA (zp1),Y, STA zp2, INY,
	LDA (zp1),Y, STA zp2+1, JMP (zp2). A JSR to it then becomes a direct
	jump (Gen.emit_engine_call)."""
	b = [prg.byte(f + k) for k in range(22)] if f >= 0x8000 and f + 22 <= 0x10000 else []
	if len(b) < 22 or b[:3] != [0x0A, 0xA8, 0x68]:
		return None
	z1 = b[4]
	want = [0x0A, 0xA8, 0x68, 0x85, z1, 0x68, 0x85, (z1 + 1) & 0xFF, 0xC8, 0xB1, z1, 0x85, b[12],
		0xC8, 0xB1, z1, 0x85, (b[12] + 1) & 0xFF, 0x6C, b[12], 0x00]
	if b[:21] != want or z1 == 0xFF or b[12] == 0xFF:
		return None
	return z1, b[12]


def inline_table(prg, at):
	"""Targets of an address table right after a JSR to a jump engine."""
	found = []
	while len(found) < 128 and at + 1 <= 0xFFFF and prg.const(at) and prg.const(at + 1):
		a = prg.word(at)
		if a < 0x8000 or not plausible_code(prg, a):
			break
		found.append(a)
		at += 2
	return found


def discover(prg, extra=()):
	vectors = [prg.word(0xFFFA), prg.word(0xFFFC), prg.word(0xFFFE)] if prg.has(0xFFFA) else []
	insns = {}
	forced = set()			# decided branches whose fall-through turned out reachable
	engines = {}			# jump engine routines (inline_table_routine)
	while True:
		insns.clear()
		tables = set()
		work = list(vectors) + list(extra)
		while work:
			pc = work.pop()
			known = {}		# flag -> (value, where it became known), along this straight run
			while pc not in insns and prg.has(pc):
				op = prg.byte(pc)
				if op not in OPS:
					print('recomp6502: unofficial opcode $%02X at $%04X: left to the interpreter' % (op, pc), file=sys.stderr)
					break
				i = Insn(pc, op, prg)
				insns[pc] = i
				nxt = (pc + i.n) & 0xFFFF
				m = i.m
				if i.mode == 'rel':
					f = FLAG_OF[m]
					want = {'BPL': 0, 'BMI': 1, 'BNE': 0, 'BEQ': 1, 'BCC': 0, 'BCS': 1, 'BVC': 0, 'BVS': 1}[m]
					if f in known and pc not in forced:
						i.decided = 'taken' if known[f][0] == want else 'not'
						i.known_from = known[f][1]
					i.succ = ([i.arg] if i.decided != 'not' else []) + ([nxt] if i.decided != 'taken' else [])
				elif m == 'JMP':
					i.succ = [i.arg] if i.mode == 'abs' else [None]
				elif m == 'JSR':
					i.succ = [i.arg] if i.arg >= 0x8000 else [None]
					if i.arg >= 0x8000 and engines.setdefault(i.arg, inline_table_routine(prg, i.arg)):
						t = inline_table(prg, nxt)	# no return point: a table
						tables.update(t)
						work += t
						i.table = t
					else:
						work.append(nxt)	# return point
				elif m in ('RTS', 'RTI', 'BRK'):
					i.succ = [None]
					if m == 'BRK' and prg.has(0xFFFE):
						work.append(prg.word(0xFFFE))
				else:
					i.succ = [nxt]
				for s in i.succ:
					if s is not None and s != nxt:
						work.append(s)
				if m in ('ADC', 'SBC') and C in known:
					i.cin = known[C]
				# track flags known from immediates and branches, for
				# branches always or never taken
				if m in ('LDA', 'LDX', 'LDY') and i.mode == 'imm':
					known = {N: (i.arg >> 7, pc), Z: (int(i.arg == 0), pc),
						 **{k: v for k, v in known.items() if k in (C, V)}}
				elif m == 'SEC': known[C] = (1, pc)
				elif m == 'CLC': known[C] = (0, pc)
				elif m == 'CLV': known[V] = (0, pc)
				elif m in DEFS: known = {k: v for k, v in known.items() if not (DEFS[m] & k)}
				if i.mode == 'rel' and i.decided is None:
					known = {**known, f: (1 - want, pc)}	# falling through: the flag is the other way
				if nxt not in i.succ:
					break
				pc = nxt
		# a decided branch is only safe if nothing else jumps into the
		# run from where its flag became known
		targets = {s for i in insns.values() for s in i.succ if s is not None and s != i.pc + i.n}
		targets |= {i.pc + 3 for i in insns.values() if i.m == 'JSR'} | set(extra) | set(tables) | set(vectors)
		bad = {i.pc for i in insns.values() if i.decided and
		       any(t in targets for t in range(i.known_from + 1, i.pc + 1))} - forced
		if not bad:
			for i in insns.values():	# (and a carry in likewise)
				if i.cin and any(t in targets for t in range(i.cin[1] + 1, i.pc + 1)):
					i.cin = None
			return insns, vectors, tables
		forced |= bad

def jump_tables(prg, insns, foreign=None, loads=None):
	"""Addresses found in jump tables:
	- a table of low bytes and one of high bytes (or one table of both,
	  interleaved), stored into a RAM pointer for JMP (ptr), or after a
	  JMP opcode written to RAM
	- tables pushed high/low before an RTS (target - 1)
	Returns all of them, and those reached by RTS. MMC3 PRG mode 1: the
	tables this unit loads from the other slot, whose bank it can't know,
	go into foreign, as (low bytes, high bytes, 1 for RTS tables) (mode1
	reads them in each bank there: slot_table), and into loads where it
	loads anything there indexed (where such a table must end)."""
	order = sorted(insns)
	prev = {order[k]: insns[order[k - 1]] for k in range(1, len(order))}

	def readable(a):
		return prg.const(a) or (foreign is not None and prg.mode1 and prg.region(a) in ('A', 'C') and
					prg.region(a) != prg.slot)

	def table_load(i):
		p = prev.get(i.pc)
		if p and p.m in ('LDA', 'LDX', 'LDY') and p.mode in ('absx', 'absy') and readable(p.arg):
			return p.arg
		return None

	slots = set()			# RAM address of a jump pointer's low byte
	for i in insns.values():
		if i.m == 'JMP' and i.mode == 'ind' and i.arg < 0x800:
			slots.add(i.arg)
		if i.m in ('JSR', 'JMP') and i.mode == 'abs' and i.arg < 0x800:
			slots.add(i.arg + 1)
	WRITES = {'A': ('LDA', 'PLA', 'TXA', 'TYA', 'ADC', 'SBC', 'AND', 'ORA', 'EOR'),
		  'X': ('LDX', 'TAX', 'TSX', 'INX', 'DEX'), 'Y': ('LDY', 'TAY', 'INY', 'DEY')}

	def stored_to(i):
		"""Where a table load's value is stored: followed a few
		instructions on, through JMPs, until stored or changed."""
		r, pc = i.m[2], i.pc + i.n
		for _ in range(8):
			j = insns.get(pc)
			if j is None or j.mode == 'rel' or j.m in ('JSR', 'RTS', 'RTI', 'BRK') or \
			   (j.m == 'JMP' and j.mode != 'abs'):
				return None
			if j.m == 'ST' + r and j.mode in ('zp', 'abs'):
				return j.arg
			if j.m in WRITES[r] or (r == 'A' and j.mode == 'acc'):
				return None
			pc = j.arg if j.m == 'JMP' else pc + j.n
		return None

	lo, hi = {}, {}			# slot -> {table: loads' addresses}
	for i in insns.values():
		if loads is not None and i.mode in ('absx', 'absy') and readable(i.arg) and not prg.const(i.arg):
			loads.add(i.arg)
		if i.m in ('LDA', 'LDX', 'LDY') and i.mode in ('absx', 'absy') and readable(i.arg):
			s = stored_to(i)
			if s is not None:
				if s in slots: lo.setdefault(s, {}).setdefault(i.arg, set()).add(i.pc)
				if s - 1 in slots: hi.setdefault(s - 1, {}).setdefault(i.arg, set()).add(i.pc)

	def near(l, h, slot):
		"""MMC3 PRG mode 1: are a load of the low bytes and one of the high
		bytes 24 bytes apart at most, as code making one jump does? (A RAM
		pointer games use everywhere gets its bytes from many tables.)"""
		return not prg.mode1 or any(abs(a - b) <= 24 for a in lo[slot][l] for b in hi[slot][h])
	pairs = []
	for slot in lo:
		same = set(lo[slot]) & set(hi.get(slot, {}))	# LDA t,Y / INY / LDA t,Y: interleaved
		pairs += [(t, t + 1, 0) for t in same]
		pairs += [(l, h, 0) for l in set(lo[slot]) - same for h in set(hi.get(slot, {})) - same if near(l, h, slot)]
	# RTS tables: LDA hi,X / PHA / LDA lo,X / PHA ... RTS
	for k, pc in enumerate(order):
		i = insns[pc]
		if i.m == 'PHA' and table_load(i) is not None:
			for j in order[k + 1:k + 4]:
				if insns[j].m == 'PHA' and table_load(insns[j]) is not None:
					pairs.append((table_load(insns[j]), table_load(i), 1))
					break
	found, rts = set(), set()
	for l, h, add in pairs:
		if not (prg.const(l) and prg.const(h)):
			if not (prg.const(l) or prg.const(h)) and prg.region(l) == prg.region(h):
				foreign.append((l, h, add))
			continue
		step = 1
		if h == l + 1:			# interleaved: low, high, low, high...
			step, n = 2, 64
		else:
			n = h - l if 0 < h - l <= 128 else 64
		for k in range(0, n * step, step):
			if not (prg.const(l + k) and prg.const(h + k)):
				break
			a = ((prg.byte(l + k) | prg.byte(h + k) << 8) + add) & 0xFFFF
			if not plausible_code(prg, a):
				break			# end of the table
			found.add(a)
			if add:
				rts.add(a)
	return found, rts


def plausible_code(prg, a, count=12):
	"""Do the bytes at a decode as a run of legal instructions? Outside
	the unit's own code (banked PRG): do they in one of its peers?"""
	if not prg.has(a):
		return any(plausible_code(p, a, count) for p in prg.peers if p.has(a))
	return plausible_run(prg, a, count)


def plausible_run(prg, a, count):
	"""plausible_code in the unit's own code, going on at the target of a
	branch a constant loaded before it makes always taken (taken)."""
	nz = None
	for _ in range(count):
		if not prg.has(a) or prg.byte(a) not in OPS:
			return False
		m, mode = OPS[prg.byte(a)]
		if m in ('RTS', 'RTI', 'JMP'):
			return True
		if m == 'JSR' and prg.const(a + 1) and prg.const(a + 2) and \
		   inline_table_routine(prg, prg.word(a + 1)):
			return True		# a table follows
		if taken(m, nz) and prg.has(a + 1):
			a, nz = rel_target(prg, a), None
			continue
		nz = nz_after(prg, a, m, mode, nz)
		a += SIZE[mode]
	return True


# instructions that leave N and Z as they are
NZ_KEEP = {'STA', 'STX', 'STY', 'CLC', 'SEC', 'CLI', 'SEI', 'CLV', 'CLD', 'SED', 'NOP', 'PHA', 'PHP', 'TXS',
	   'BCC', 'BCS', 'BVC', 'BVS', 'BEQ', 'BNE', 'BPL', 'BMI'}


def nz_after(prg, a, m, mode, nz):
	"""The constant N and Z come from after the instruction at a (LDA,
	LDX or LDY #n), or None."""
	if m in ('LDA', 'LDX', 'LDY') and mode == 'imm':
		return prg.byte(a + 1)
	return nz if m in NZ_KEEP else None


def taken(m, nz):
	"""Is branch m always taken, with N and Z from constant nz?"""
	if nz is None:
		return False
	return {'BEQ': nz == 0, 'BNE': nz != 0, 'BPL': nz < 0x80, 'BMI': nz >= 0x80}.get(m, False)


def rel_target(prg, a):
	"""Where the branch at a goes."""
	d = prg.byte(a + 1)
	return (a + 2 + (d - 256 if d > 127 else d)) & 0xFFFF


def sane_address(a):
	"""Could code use absolute address a: RAM, the PPU's and APU's
	registers, PRG RAM or PRG-ROM (not mirrors or open bus)?"""
	return a < 0x800 or 0x2000 <= a <= 0x2007 or 0x4000 <= a <= 0x4017 or a >= 0x6000


def code_at(prg, a, count=10):
	"""A stricter plausible_code, for code going into a slot that holds
	one of many banks (MMC3 PRG mode 1): legal instructions, no BRK or
	RTI, and absolute addresses code uses. As there, a JSR to a jump
	engine ends it (a table follows), and it goes on at the target of a
	branch always taken (taken), or followed by what can't be code."""
	nz = None
	for _ in range(count):
		op = prg.byte(a)
		if op not in OPS or op in (0x00, 0x40):	# (BRK, RTI)
			return False
		m, mode = OPS[op]
		if SIZE[mode] == 3 and not (prg.const(a + 1) and prg.const(a + 2) and sane_address(prg.word(a + 1))):
			return False
		if m in ('RTS', 'RTI', 'JMP'):
			return True
		if m == 'JSR' and inline_table_routine(prg, prg.word(a + 1)):
			return True
		if mode == 'rel' and prg.const(a + 1) and \
		   (taken(m, nz) or prg.byte(a + 2) not in OPS or prg.byte(a + 2) in (0x00, 0x40)):
			a, nz = rel_target(prg, a), None
			continue
		nz = nz_after(prg, a, m, mode, nz)
		a += SIZE[mode]
	return True


def slot_table(b, l, h, add, end=0x10000):
	"""MMC3 PRG mode 1: a jump table another unit loads from b's slot
	(jump_tables' foreign), read in bank unit b's bytes, as jump_tables
	reads one, if it is one there: four of its entries or more go to
	b's own code (as the code loading it from that slot expects). Ends
	at the first that isn't an address in PRG, or not code (code_at) in
	b's slot or the fixed banks', or at end (where the code loading it
	loads something else). Returns its targets in b's slot, in the fixed
	banks' and in the other slot (which bank is there isn't known
	here)."""
	step, n = (2, 64) if h == l + 1 else (1, h - l if 0 < h - l <= 128 else 64)
	own, fixed, other = [], [], []
	for k in range(0, n * step, step):
		if not (b.has(l + k) and b.has(h + k)) or l + k >= end:
			break
		a = ((b.byte(l + k) | b.byte(h + k) << 8) + add) & 0xFFFF
		if a < 0x8000:
			break
		r = b.region(a)
		if r in (b.slot, 'F'):
			if not code_at(b, a):
				break
			(own if r == b.slot else fixed).append(a)
		else:
			other.append(a)
	return (own, fixed, other) if len(own) >= 4 else ([], [], [])


def slot_homes(rom):
	"""MMC3 PRG mode 1: the slot each bank's code runs in ('A': $A000,
	'C': $C000), or None for a bank with no sign of code. (Not the last
	two, always at $8000 and $E000.) A bank's JSRs and JMPs into its own
	slot go to its code, those into the other slot to another bank's:
	there its bytes are as likely data. A slot scores the JSRs and JMPs
	into it whose target looks like code here (code_at), less those
	whose target doesn't. A bank with no sign of code that way (Super
	Mario Bros. 3's level styles, whose code calls only the fixed
	banks' and the other slot's) scores in each slot, as well, the
	addresses that look like code in the tables after its JSRs to a jump
	engine in the fixed banks (inline_table_routine): in the slot, or in
	the other slot in a bank found to be there (table_code)."""
	fixed = Prg(rom, 'F')
	engine = {}
	homes, scores, tables = {}, {}, {}
	for b in range(rom[4] * 2 - 2):
		score = {}
		for s in 'AC':
			u = Prg(rom, (s, b))
			score[s] = 0
			tables[b, s] = []
			for k in range(len(u.data) - 2):
				t = u.data[k + 1] | u.data[k + 2] << 8
				if u.data[k] in (0x20, 0x4C) and u.has(t):
					score[s] += 1 if code_at(u, t) else -1
				elif u.data[k] == 0x20 and fixed.has(t):
					if t not in engine:
						engine[t] = inline_table_routine(fixed, t)
					if engine[t]:
						tables[b, s].append(u.lo + k + 3)
		best = max('AC', key=lambda s: score[s])
		homes[b] = best if score[best] > 0 else None
		scores[b] = score
	for b in [b for b in homes if homes[b] is None]:
		score = scores[b]
		for s in 'AC':
			u = Prg(rom, (s, b))
			other = 'C' if s == 'A' else 'A'
			there = [Prg(rom, (other, c)) for c in homes if homes[c] == other]
			for at in tables[b, s]:
				score[s] += table_code(u, at, there)
		best = max('AC', key=lambda s: score[s])
		homes[b] = best if score[best] > 0 else None
	return homes


def table_code(u, at, there):
	"""slot_homes: how many addresses in the table at at look like code
	(code_at) in u's slot, or in the other slot in one of the banks
	there, up to the first in u's slot that doesn't, or one not in PRG
	(64 at most)."""
	n = 0
	for _ in range(64):
		if not (u.has(at) and u.has(at + 1)):
			break
		a = u.word(at)
		if a < 0x8000 or (u.has(a) and not code_at(u, a)):
			break
		n += u.has(a) or any(p.has(a) and code_at(p, a) for p in there)
		at += 2
	return n

# ----------------------------------------------------------------------
# Value ranges of A, X and Y (to prove zp,X / zp,Y can't wrap)
# ----------------------------------------------------------------------

TOP = (0, 255)
RET_CACHES = [0]			# return caches given out (RAM_RcRet: 120)
NEST = [True]				# NMIs taken in routine copies come back to them (nest_ok)


def nest_ok(prg, u):
	"""Can an NMI taken in a routine's copy come back to it (rcNmiIn in
	emu/recomp.asm), so the copy's caller needn't push the 6502 return
	address? Its handler runs meanwhile, with the 6502 stack as the
	copies left it, and its RTI (or that of the IRQ taken right after
	it) has to be translated code's (rcRti) to come back. So not if
	the handlers' code from the NMI vector, and the IRQ's where the
	mapper has an IRQ (or the code runs BRK), in this unit (the fixed
	code) and the routines it calls there, reads the stack pointer
	(TSX: it might look below its own frame, where a light copy's
	caller pushed no return address) or goes to code the interpreter
	runs (RAM, or its own that isn't translated). A computed jump there
	may go to any jump table's code it has."""
	insns, vec = u['insns'], u['vectors']
	work, seen = [vec[0]] + ([vec[2]] if prg.irq else []), set()
	while work:
		pc = work.pop()
		if pc in seen:
			continue
		seen.add(pc)
		if pc < 0x8000:
			return False			# (RAM)
		if not prg.has(pc):
			continue			# a bank's code, translated there
		i = insns.get(pc)
		if i is None or i.m == 'TSX':
			return False
		work += [t for t in i.succ if t is not None]
		if i.m == 'JSR':
			work.append(i.arg)
		elif i.m == 'BRK':
			work.append(vec[2])
		elif i.m == 'JMP' and i.mode == 'ind':
			work += list(u['tables'])
	return True


def join(a, b):
	if a is None: return b
	if b is None: return a
	return (min(a[0], b[0]), max(a[1], b[1]))


def meet(a, lo, hi):
	r = (max(a[0], lo), min(a[1], hi))
	return r if r[0] <= r[1] else None


def ranges(insns, entries):
	"""Interval of each register at the start of each instruction.
	Entries (vectors, return points, jump table targets) start unknown."""
	REG = {'A': 0, 'X': 1, 'Y': 2}
	state = {pc: None for pc in insns}
	for e in entries:
		if e in state: state[e] = (TOP, TOP, TOP)
	visits = {}
	work = [e for e in entries if e in state]
	order = sorted(insns)
	prev = {order[k]: insns[order[k - 1]] for k in range(1, len(order))}
	ways = {}				# how many instructions go to each one
	for i in insns.values():
		for s in i.succ:
			ways[s] = ways.get(s, 0) + 1
	while work:
		pc = work.pop()
		i = insns[pc]
		st = list(state[pc])
		visits[pc] = visits.get(pc, 0) + 1
		if visits[pc] > 64:		# slow to converge: give up on it
			st = [TOP, TOP, TOP]
		m, a = i.m, i.arg
		r = None			# register written, and its new range
		if m in ('LDA', 'LDX', 'LDY'):
			r = (m[2], (a, a) if i.mode == 'imm' else TOP)
		elif m in ('TAX', 'TAY'): r = (m[2], st[0])
		elif m in ('TXA', 'TYA'): r = ('A', st[REG[m[1]]])
		elif m in ('INX', 'INY', 'DEX', 'DEY'):
			v = st[REG[m[2]]]; d = 1 if m[0] == 'I' else -1
			r = (m[2], (v[0] + d, v[1] + d) if 0 <= v[0] + d and v[1] + d <= 255 else TOP)
		elif m == 'AND' and i.mode == 'imm': r = ('A', (0, min(st[0][1], a)))
		elif m == 'ORA' and i.mode == 'imm': r = ('A', (max(st[0][0], a), min(255, st[0][1] + a)))
		elif m == 'TSX': r = ('X', TOP)
		elif m in ('ADC', 'SBC', 'ORA', 'EOR', 'AND', 'PLA') or (m in ('ASL', 'LSR', 'ROL', 'ROR') and i.mode == 'acc'):
			r = ('A', TOP)
		if r: st[REG[r[0]]] = r[1]
		for s in i.succ:
			if s is None or s not in insns:
				continue
			out = list(st)
			if i.mode == 'rel':		# refine on the branch's condition
				p = prev.get(pc)
				taken = (s == i.arg)
				reg = None
				if p and p.pc + p.n == pc:
					if p.m in ('LDA', 'LDX', 'LDY', 'INX', 'INY', 'DEX', 'DEY', 'TAX', 'TAY', 'TXA', 'TYA'):
						reg = {'LDA': 'A', 'TXA': 'A', 'TYA': 'A'}.get(p.m, p.m[2] if p.m[0] in 'LTID' else None)
						if p.m in ('TAX', 'TAY'): reg = p.m[2]
						if p.m in ('INX', 'DEX'): reg = 'X'
						if p.m in ('INY', 'DEY'): reg = 'Y'
						cond = {'BPL': (0, 127), 'BMI': (128, 255)}.get(i.m)
						if cond and reg:
							k = REG[reg]
							lo, hi = cond if taken else ((128, 255) if i.m == 'BPL' else (0, 127))
							parts = [out[k]]
							if p.m in ('INX', 'INY', 'DEX', 'DEY') and state[p.pc] and ways.get(pc) == 1 and \
							   pc not in entries:	# (only from it: its range before, stepped)
								parts = steps(state[p.pc][k], 1 if p.m[0] == 'I' else -1)
							parts = [x for x in (meet(x, lo, hi) for x in parts) if x]
							out[k] = None
							for x in parts:
								out[k] = join(out[k], x)
					elif p.m in ('CPX', 'CPY', 'CMP') and p.mode == 'imm' and i.m in ('BCC', 'BCS'):
						k = REG[{'CPX': 'X', 'CPY': 'Y', 'CMP': 'A'}[p.m]]
						lt = (i.m == 'BCC') == taken	# register < operand
						out[k] = meet(out[k], 0, p.arg - 1) if lt else meet(out[k], p.arg, 255)
				if None in out:
					continue	# edge can't be taken
			new = tuple(join(o, n) for o, n in zip(state[s], out)) if state[s] else tuple(out)
			if new != state[s]:
				state[s] = new
				work.append(s)
			elif m in ('INX', 'INY', 'DEX', 'DEY') and insns[s].mode == 'rel':
				work.append(s)		# (its refinement reads this one's range)
	return state


def steps(v, d):
	"""The values of a register in range v after INX/DEX (d 1/-1),
	as up to two ranges: those that didn't wrap, and the one that did."""
	if d < 0:
		return ([(max(v[0], 1) - 1, v[1] - 1)] if v[1] >= 1 else []) + ([(255, 255)] if v[0] == 0 else [])
	return ([(v[0] + 1, min(v[1], 254) + 1)] if v[0] <= 254 else []) + ([(0, 0)] if v[1] == 255 else [])

# ----------------------------------------------------------------------
# Flag liveness
# ----------------------------------------------------------------------

def rts_walk(insns, f):
	"""The RTSs a routine at f returns through: {pc: stack depths (bytes
	pushed since f began) it's reached at}, the instructions on the way,
	and whether the routine moves the stack (TSX, TXS). A JSR returns to
	the instruction after it, or a jump engine's to its table's entries
	(the engine pulls the return address the JSR pushed)."""
	seen, work, found, unsure = set(), [(f, 0)], {}, False
	while work:
		pc, d = work.pop()
		if pc not in insns or (pc, d) in seen or not -4 <= d <= 4:
			continue
		seen.add((pc, d))
		i = insns[pc]
		if i.m == 'RTS':
			found.setdefault(pc, set()).add(d)
			continue
		d += {'PHA': 1, 'PHP': 1, 'PLA': -1, 'PLP': -1}.get(i.m, 0)
		if i.m in ('TSX', 'TXS'):
			unsure = True
		if i.m == 'JSR':
			work += [(t, d) for t in i.table] if i.table else [(pc + 3, d)]
		else:
			work += [(s, d) for s in i.succ if s is not None]
	return found, {pc for pc, d in seen}, unsure


def rts_returns(insns, tables=(), strict=False, ext_calls=None):
	"""For each RTS, the return points of the JSRs that can reach it.
	A JSR into RAM may call any jump table target. An RTS reached with
	two more bytes pulled than pushed (a routine dropping its return
	address) also goes where its caller returns; other depths would
	return to a garbage address, so those paths are taken as never
	happening. strict: leave out RTSs of routines that move the stack.
	ext_calls: JSRs in other code to this code's routines, by routine."""
	calls = {}
	for i in insns.values():
		if i.m == 'JSR' and not i.table:
			for f in [i.arg] if i.arg in insns else tables if i.arg < 0x800 else ():
				calls.setdefault(f, set()).add(i.pc)
	for f, sites in (ext_calls or {}).items():
		calls.setdefault(f, set()).update(sites)
	body, ends = {}, {}
	unsure = set()
	for f in calls:
		ends[f], body[f], u = rts_walk(insns, f)
		if u:
			unsure.add(f)
	returns, bad = {}, set()
	for f, sites in calls.items():
		for pc, ds in ends[f].items():
			rets = returns.setdefault(pc, set())
			if 0 in ds or not ds - {-2}:
				rets |= {s + 3 for s in sites}
			if -2 in ds:			# returns for the routine that called f
				for g in calls:
					if sites & body[g]:
						rets |= {s + 3 for s in calls[g]}
			if f in unsure or not ds & {0, -2}:
				bad.add(pc)
	if strict:
		return {pc: r for pc, r in returns.items() if pc not in bad}
	return returns


def copy_liveness(insns, body, ctx, live_in, sums):
	"""Flags live after each instruction of a routine's copy (called with
	the 68000's jsr, Gen.emit_routine): as liveness() found them, but its
	RTSs only return to its own callers, where ctx is live. (Where the
	copy leaves for the normal code, through rcDispatch, that code goes
	the same way on from there, reading no flag the copy didn't keep.)"""
	inn = {pc: 0 for pc in body}
	out_of = {}
	changed = True
	while changed:
		changed = False
		for pc in sorted(body, reverse=True):
			i = insns[pc]
			if i.m == 'RTS':
				out = new = ctx
			elif i.m == 'JSR' and i.table and all(t in body for t in i.table):
				out = 0				# a jump engine: to its table's entries
				for t in i.table:
					out |= inn[t]
				new = out & ~(N | Z | C)
			elif i.m == 'JSR' and pc + 3 in body and i.arg in sums:
				g, k = sums[i.arg]
				out = new = g | (inn[pc + 3] & ~k)
			elif i.m in ('JSR', 'PHP') or any(s is None or s not in body for s in i.succ):
				out, new = i.live_out, live_in[pc]	# as the whole program sees it
			else:
				out = 0
				for s in i.succ:
					out |= inn[s]
				new = uses(i) | (out & ~DEFS.get(i.m, 0))
			out_of[pc] = out
			if new != inn[pc]:
				inn[pc] = new
				changed = True
	return out_of


def mapper_write(i):
	"""Can i write to $8000-$FFFF, a mapper's registers?"""
	return i.m in ('STA', 'STX', 'STY', 'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR') and \
	       i.mode in ('abs', 'absx', 'absy') and i.arg + (0 if i.mode == 'abs' else 255) >= 0x8000


def clean_routines(insns, switching=(), ext_sum=()):
	"""Routines (JSR targets) that only ever return to their caller, by
	an RTS at the stack depth they began with: no stack tricks, computed
	jumps, bank switches (switching), or other units' code but routines
	summarized there (ext_sum), and the routines they call are like
	them. Returns their instructions."""
	cand = {}
	for f in {i.arg for i in insns.values() if i.m == 'JSR' and not i.table and i.arg in insns}:
		found, body, unsure = rts_walk(insns, f)
		ok = not unsure and all(ds == {0} for ds in found.values())
		for pc in body if ok else ():
			i = insns[pc]
			if pc in switching or i.m in ('RTI', 'BRK', 'TSX', 'TXS') or \
			   (i.m == 'JSR' and not i.table and (pc + 3 not in insns or (i.arg not in insns and i.arg not in ext_sum))) or \
			   (i.m == 'JSR' and i.table and any(t not in insns for t in i.table)) or \
			   (i.m not in ('JSR', 'RTS') and any(s is None or s not in insns for s in i.succ)):
				ok = False
				break
		if ok:
			cand[f] = body
	while True:
		bad = {f for f, body in cand.items() if any(insns[pc].m == 'JSR' and not insns[pc].table and
							     insns[pc].arg in insns and insns[pc].arg not in cand for pc in body)}
		if not bad:
			return cand
		for f in bad:
			del cand[f]


def routine_kills(insns, clean, ext_sum=()):
	"""The flags each clean routine writes on every way to its RTSs.
	Starts from none and grows: each round is safe to stop at."""
	kill = {f: 0 for f in clean}
	changed = True
	while changed:
		changed = False
		for f in clean:
			d, work = {f: 0}, [f]	# flags written on every way to each instruction
			while work:
				pc = work.pop()
				i, w = insns[pc], d[pc]
				if i.m == 'RTS':
					continue
				if i.m == 'JSR' and i.table:		# a jump engine
					w, nxt = w | N | Z | C, i.table
				elif i.m == 'JSR':
					w, nxt = w | (kill[i.arg] if i.arg in insns else ext_sum[i.arg][1]), [pc + 3]
				else:
					w, nxt = w | DEFS.get(i.m, 0), i.succ
				for s in nxt:
					v = d[s] & w if s in d else w
					if v != d.get(s):
						d[s] = v
						work.append(s)
			k = ALL
			for pc in clean[f]:
				if insns[pc].m == 'RTS' and pc in d:
					k &= d[pc]
			if k != kill[f]:
				kill[f] = k
				changed = True
	return kill


def liveness(insns, returns=(), tables=(), rts_targets=(), ext=(), others=(), ext_live=None, ext_ret=None,
	     ext_sum=None, switching=()):
	"""returns: where an RTS can go (JSR return points, RTS jump table
	targets); an RTS's live flags are the union of those of the JSRs
	that reach it and rts_targets (RTS jump tables, unknown entries), or
	of all of them.
	tables: jump table targets, where JMP (ptr) and JSRs into RAM go.
	ext: routines another unit calls (banked PRG). What its code reads
	after they return is ext_ret[routine] (all flags if not given), and
	an RTS only they reach (not the routines this unit calls, nor
	others: its other entries) returns just there.
	ext_live: flags live at other units' code this unit's code goes to
	(all if not given).
	A JSR to a routine that only returns to its caller (clean_routines)
	goes by a summary of it: the flags it reads before writing them
	(gen), and those it writes on every way back (kill). What's live
	after this call then doesn't count for the routine's other calls,
	as it would through its RTS. ext_sum: summaries of other units'
	routines (switching: mapper writes, which make a routine unclean).
	PHP pushes the flags that are live after the PLPs that pull them,
	unless a PLA may pull them instead.
	Returns the flags live at each instruction, and the summaries."""
	ext_live = ext_live or {}
	ext_ret = ext_ret or {}
	ext_sum = ext_sum or {}
	clean = clean_routines(insns, switching, ext_sum)
	kill = routine_kills(insns, clean, ext_sum)
	local = {pc: 0 for pc in insns}		# live flags if RTSs returned nowhere
	live_in = {pc: 0 for pc in insns}
	returns = [r for r in returns if r in insns]
	tables = [t for t in tables if t in insns]
	rts = {pc: sorted((r | set(rts_targets)) & set(insns)) for pc, r in rts_returns(insns, tables, True).items()}
	# RTSs of code entered other than by a JSR (vectors, jump tables)
	# return to wherever the code that went there was called from
	inline = {t for i in insns.values() if i.table for t in i.table}
	unknown = set()
	for f in set(others) | (set(tables) - inline):
		unknown |= set(rts_walk(insns, f)[0])
	ext_out = {}			# RTS -> flags read where other units' calls return
	for f in ext:
		found, _, unsure = rts_walk(insns, f)
		for pc, ds in found.items():
			if unsure or -2 in ds:		# (-2: where its caller's caller returns)
				v = ALL
			elif 0 in ds:			# other depths: as rts_returns
				v = ext_ret.get(f, ALL)
			elif 2 in ds:			# maybe a jump pushed before the RTS
				unknown.add(pc)
				continue
			else:				# would return to garbage: not a routine
				continue
			ext_out[pc] = ext_out.get(pc, 0) | v
	ext_only = set(ext_out) - unknown - set(rts_returns(insns, tables))
	whole = set()			# PHPs whose byte may be pulled by PLA
	pulls = {}			# the others: the PLPs that pull their byte
	for i in insns.values():
		if i.m == 'PHP':
			seen, work, pulls[i.pc] = set(), [i.pc + 1], set()
			while work:		# every path must reach a PLP soon
				pc = work.pop()
				j = insns.get(pc)
				if j is None or len(seen) > 32 or j.m in ('PLA', 'PHP', 'JSR', 'RTS', 'RTI', 'BRK', 'TSX', 'TXS'):
					whole.add(i.pc)
					break
				if j.m == 'PLP':
					pulls[i.pc].add(pc)
				if pc in seen or j.m == 'PLP':
					continue
				seen.add(pc)
				work += j.succ
	def step(i, inn, whole_prog):
		"""(live out, live in) of i, from the live-in flags inn of the
		instructions after it. whole_prog False: RTSs return nowhere."""
		pc = i.pc
		if i.m == 'RTS':
			if not whole_prog:
				return 0, 0
			rs = [] if pc in ext_only else returns if pc in unknown or pc not in rts else rts[pc]
			out = ext_out.get(pc, 0)
			for r in rs:
				out |= live_in[r]
			if not rs and pc not in ext_out:
				out = ALL
			return out, out
		if i.m == 'JSR' and i.table:		# a jump engine: to its table's entries
			out = 0
			for t in i.table:
				out |= inn[t] if t in insns else ALL
			return out, out & ~(N | Z | C)
		if i.m == 'JSR' and pc + 3 in insns and (i.arg in clean or (i.arg not in insns and i.arg in ext_sum)):
			g, k = (local[i.arg], kill[i.arg]) if i.arg in clean else ext_sum[i.arg]
			v = g | (inn[pc + 3] & ~k)
			return v, v
		if i.m == 'JSR' and not whole_prog:
			return live_in[pc], live_in[pc]	# as the whole program sees it
		out = 0
		for s in i.succ:
			if s is None and tables and (i.m == 'JSR' or (i.m == 'JMP' and i.mode == 'ind')):
				out |= jumped
			elif s is None:
				out = ALL
			else:
				out |= inn[s] if s in insns else ext_live.get(s, ALL)
		u = uses(i)
		if i.m == 'PHP' and pc not in whole:
			u = 0
			for q in pulls[pc]:
				u |= getattr(insns[q], 'live_out', ALL)
		return out, u | (out & ~DEFS.get(i.m, 0))

	changed = True
	while changed:
		changed = False
		jumped = 0
		for t in tables:
			jumped |= live_in[t]
		for pc in sorted(insns, reverse=True):
			i = insns[pc]
			out, new = step(i, live_in, True)
			if getattr(i, 'live_out', None) != out:
				changed = True
			i.live_out = out
			if new != live_in[pc]:
				live_in[pc] = new
				changed = True
			new = step(i, local, False)[1]
			if new != local[pc]:
				local[pc] = new
				changed = True
	return live_in, {f: (local[f], kill[f]) for f in clean}

# ----------------------------------------------------------------------
# Code generation
# ----------------------------------------------------------------------

def lab(a):
	return 'L_%04X' % a


class Unroll(Exception):
	pass


class Gen:
	def __init__(self, prg, insns, ext=()):
		self.prg, self.insns = prg, insns
		self.ext = set(ext)		# translated in another unit, jumped to directly
		self.ext_routines = {}		# the fixed bank's routine copies a bank's code calls: (heavy, switches)
		self.copies_for = ()		# (the fixed bank's: routines banks' code calls, to have copies of)
		self.ext_ret = {}		# flags live where other units' calls return (cross_flags)
		self.ext_calls = {}		# (a bank's: the fixed bank's JSRs to its routines)
		self.dyn = {}			# MMC3 PRG mode 1: routines called in the other slot, (slot, index)
		self.dyn_copies = set()		# and this bank's that are (copies of them, if small: DYN_COPY_MAX)
		self.sj = 0			# slot_jump's labels
		self.tails = {}			# routine -> its JMPs that are tail calls (routine_body)
		self.engine_tails = {}		# routine -> its jump engine calls whose entries' copies it tail-calls (routine_body)
		self.engine_entries = set()	# and those entries (copies that keep every flag: emit_routine)
		self.double_rts = {}		# routine -> its PLA PLA RTSs' second PLAs: its copy returns from its caller there
		self.inline = set()		# small routines put in place of their calls (emit_inline)
		self.out, self.stubs = [], []
		self.fast = None
		self.split_next = None		# flags a branch puts in d3 by way (split_plan)
		self.ccr_d3 = None		# (pc, output length) where the CCR still holds d3's flags
		self.fused_next = None		# an LSR A done with the LDA $4016 before it (pad_lsr)
		self.addr_firsts, self.addr_seconds = {}, {}	# $2006 stores two at a time (pairs_2006)
		self.addr_pending = set()	# and (zp),Y reads between them

	def e(self, *lines):
		for l in lines:
			self.out.append('\t\t' + l)
			self.track_x(l)

	# The 68000's X flag often holds the 6502 carry: shifts and ADC set
	# it, and moves, loads, stores and logic ops leave it alone. While
	# it does (self.xc), a carry reader can skip reloading it from d3.
	def track_x(self, l):
		t = l.split()[0] if l.split() else ''
		if t.endswith(':'):
			self.xc = False			# a join: other paths may differ
		elif t in ('lsl.b', 'lsr.b', 'roxl.b', 'roxr.b') and l.split()[1].startswith('#1,'):
			self.xc = True
		elif t == 'addx.b':
			self.xc = True
		elif t in ('jsr', 'bsr') or t.startswith(('add', 'sub', 'neg', 'lsl', 'lsr', 'asl', 'asr', 'roxl', 'roxr')):
			self.xc = False
		elif t == 'move' and l.rstrip().endswith(('ccr', 'sr')):
			self.xc = False

	def x_safe(self, i):
		"""Does this instruction's code leave the X flag alone?"""
		if i.m not in ('LDA', 'LDX', 'LDY', 'STA', 'STX', 'STY', 'AND', 'ORA', 'EOR', 'BIT',
			       'TAX', 'TAY', 'TXA', 'TYA', 'NOP'):
			return False
		m, a = i.mode, i.arg
		st = i.m in ('STA', 'STX', 'STY')	# to PRG: the mapper, through rcWrite16
		if m in ('imm', 'zp', None):
			return True
		if m == 'abs':
			return a < 0x2000 or (a >= 0x8000 and not st) or self.wram(a)
		if m in ('absx', 'absy'):
			return a + 255 < 0x800 or (a >= 0x8000 and a + 255 <= 0xFFFF and not st) or self.wram(a, 255)
		if m in ('zpx', 'zpy'):
			return not self.zp_wraps(i)
		return False

	def check_carry(self):
		if self.c_skipped and not self.xc:
			raise RuntimeError('recomp6502: carry lost before $%04X' % self.c_skipped)
		self.c_skipped = 0

	def carry_in_x(self, i):
		"""After i sets the carry, is the next carry reader a ROL/ROR/ADC
		reached in straight-line code that keeps X? Then the carry
		needn't be stored in d3."""
		if self.fast and 'ptr' in self.fast:
			return False		# keep d3 right for exits into the normal copy
		pc = i.pc + i.n
		while True:
			n = self.insns.get(pc)
			if n is None or pc in self.targets:
				return False
			if n.m in ('ROL', 'ROR', 'ADC'):
				return n.mode in ('acc', 'imm', 'zp') or (n.mode == 'abs' and n.arg < 0x2000)
			if not self.x_safe(n):
				return False
			pc += n.n

	# ---- operands -----------------------------------------------------

	def src(self, i, dst=None):
		"""Setup lines and a 68k source EA for the operand value.
		dst: register the value is wanted in, if the setup can load it there."""
		m, a = i.mode, i.arg
		if m == 'imm':
			return [], '#$%02X' % a
		if m == 'zp':
			return [], '$%02X(a2)' % a
		if m in ('zpx', 'zpy'):
			return self.zp_indexed(i)
		if m == 'abs':
			if a < 0x2000:
				return [], '$%04X(a2)' % (a & 0x7FF)
			if self.prg.const(a):
				return [], '#$%02X' % self.prg.byte(a)	# this PRG never changes
			if a >= 0x8000:			# the bank there now
				setup, base = self.prg_frame(a, a)
				return setup, '$%04X(%s)' % (a & 0x7FFF, base)
			if self.wram(a):
				return [], 'rcWram+$%04X(a4)' % a
			return self.io_read(a)
		if m in ('absx', 'absy'):
			r = 'd1' if m == 'absx' else 'd2'
			if a + 255 < 0x2000:
				return self.ram_indexed(i, r)
			f = self.prg_frame(a, a + self.index_hi(i)) if a >= 0x8000 and a + self.index_hi(i) <= 0xFFFF else None
			if f:
				return f[0] + ['lea $%04X(%s),a5' % (a & 0x7FFF, f[1])], '(a5,%s.w)' % r
			if self.wram(a, self.index_hi(i)):
				return ['lea rcWram+$%04X(a4),a5' % a], '(a5,%s.w)' % r
			if self.wram(a):		# unless the index takes it past $7FFF
				return self.wram_checked(i, r, dst)
			if a in (0x4016, 0x4017):	# a controller port, by the index
				return ['move.w %s,d4' % r] + (['addq.w #1,d4'] if a & 1 else []) + \
				       ['jsr rcReadPad'], 'd7'
			return ['move.w #$%04X,d6' % a, 'add.w %s,d6' % r, 'jsr rcRead16'], 'd7'
		if m == 'indy' and self.fast and 'ptr' in self.fast:
			return [], self.ix(0, 'd2', 'a5')	# pointer checked and loaded into a5
		if m == 'indy':
			rn, rs, rd = (self.tag(x, i.pc) for x in ('Rn', 'Rs', 'Rd'))
			r = dst or 'd7'
			# PRG (the usual case) falls through; RAM and I/O out of line
			self.stubs += [rn + ':', '\t\tcmpi.w #$800,d6', '\t\tbcc.s ' + rs,
				       '\t\tmove.b (a2,d6.w),%s' % r, '\t\tjmp ' + rd, rs + ':']
			if self.prg.banked:		# PRG RAM
				ri = self.tag('Ri', i.pc)
				self.stubs += ['\t\tcmpi.w #$6000,d6', '\t\tbcs.s ' + ri,
					       '\t\tlea (RAM_Fami_WRAM-$6000).l,a5', '\t\tmove.b (a5,d6.w),%s' % r,
					       '\t\tjmp ' + rd, ri + ':']
			self.stubs += ['\t\tjsr ' + ('rcRead16P' if i.pc in self.addr_pending else 'rcRead16')] + \
				      (['\t\tmove.b d7,%s' % r] if r != 'd7' else []) + ['\t\tjmp ' + rd]
			prg = ['bpl.w ' + rn]
			if self.prg.mode1:		# $C000-$DFFF: R6's bank (rcFrameC)
				rp, rc = self.tag('Rp', i.pc), self.tag('Rc', i.pc)
				prg += ['cmpi.w #$C000,d6', 'bcs.s ' + rp, 'cmpi.w #$E000,d6', 'bcs.w ' + rc, rp + ':']
				self.stubs += [rc + ':', '\t\tmovea.l rcFrameC(a4),a5', '\t\tmove.b (a5,d6.w),%s' % r,
					       '\t\tjmp ' + rd]
			return self.indy_addr(a) + prg + ['move.b (a0,d6.w),%s' % r, rd + ':'], r
		if m == 'indx':
			return self.indx_addr(a) + ['jsr rcRead16'], 'd7'
		raise ValueError(m)

	def wram_checked(self, i, r, dst=None):
		"""abs,X / abs,Y in PRG RAM where the index register (r) may take
		it past $7FFF: an index that keeps it in PRG RAM reads or writes
		there, others go through rcRead16 or rcWrite16, out of line. A
		read's value ends in dst (or d7): (setup, it). A store's value
		comes in d7: its lines."""
		a = i.arg
		far, done = self.tag('Ef', i.pc), self.tag('Ed', i.pc)
		check = ['cmpi.b #$%02X,%s' % (0x7FFF - a, r), 'bhi.w ' + far, 'lea rcWram+$%04X(a4),a5' % a]
		addr = ['\t\tmove.w #$%04X,d6' % a, '\t\tadd.w %s,d6' % r]
		if i.m in ('STA', 'STX', 'STY'):
			self.stubs += [far + ':'] + addr + ['\t\tjsr rcWrite16'] + \
				      ['\t\t' + l if not l.endswith(':') else l for l in self.after_switch(i)] + ['\t\tjmp ' + done]
			return check + ['move.b d7,(a5,%s.w)' % r, done + ':']
		v = dst or 'd7'
		self.stubs += [far + ':'] + addr + ['\t\tjsr rcRead16'] + \
			      (['\t\tmove.b d7,%s' % v] if v != 'd7' else []) + ['\t\tjmp ' + done]
		return check + ['move.b (a5,%s.w),%s' % (r, v), done + ':'], v

	def index_hi(self, i):
		"""Highest value of an abs,X / abs,Y instruction's index register."""
		rng = self.ranges.get(i.pc)
		return rng[1 if i.mode == 'absx' else 2][1] if rng else 255

	def ram_indexed(self, i, r):
		"""abs,X / abs,Y in RAM: setup and EA. Past $07FF the address
		wraps into the RAM mirrors, unless the index register's range
		shows it can't get there."""
		a = i.arg & 0x7FF
		if a + self.index_hi(i) < 0x800:
			if a < 0x80:
				return [], self.ix(a, r)
			return self.a5_ix(a, r, '$%04X' % a)
		if self.fast and 'off' in self.fast and self.fast['off'][r]:
			raise Unroll
		return ['move.w %s,d6' % r, 'addi.w #$%04X,d6' % a, 'andi.w #$7FF,d6'], '(a2,d6.w)'

	def ix(self, a, r, base='a2'):
		"""a(base,r.w); in an unrolled loop r is off by a known amount."""
		if self.fast and 'off' in self.fast:
			a += self.fast['off'][r]
			if not -128 <= a <= 127:
				raise Unroll
			return '%d(%s,%s.w)' % (a, base, r)
		return '$%02X(a2,%s.w)' % (a, r) if base == 'a2' else '(%s,%s.w)' % (base, r)

	def a5_ix(self, a, r, text):
		"""RAM at a, indexed by r, through a5: by the lea already in a5
		if it points near enough, else by a lea of its own. Code that
		goes on with the a5 of code before it gets in at its label (other
		than by falling in) through a stub that sets a5 first."""
		found = self.a5_ram()
		if found is None or not -128 <= a - found[0] <= 127:
			return ['lea %s(a2),a5' % text], '(a5,%s.w)' % r
		b, labels = found
		for k in labels:
			name = INSN_LABEL.match(self.out[k]).group(1)
			self.out[k] = self.out[k].replace(name + ':', name + '_a:', 1)
			self.stubs += [name + ':', '\t\tlea $%04X(a2),a5' % b, '\t\tjmp %s_a' % name]
		return [], '%d(a5,%s.w)' % (a - b, r)

	def a5_ram(self):
		"""Where in RAM a5 points here, if a lea $nnnn(a2),a5 before this,
		in code that falls through, still holds: (the address, the
		indices in self.out of the instructions' labels since, still to
		be given stubs); else None. Branch targets stop it (a stub there
		would slow down the branches)."""
		labels = []
		for k in range(len(self.out) - 1, max(len(self.out) - 64, 0) - 1, -1):
			l = self.out[k]
			t = l.split()
			if not t or t[0].startswith(';'):
				continue
			if not l[0].isspace() or t[0].endswith(':'):
				m = INSN_LABEL.match(l)
				if not m or int(m.group(2), 16) in self.targets:
					return None		# a join, or an internal label
				if not m.group(1).endswith('_a'):	# (one with its stub already)
					labels.append(k)
				continue
			op, arg = t[0].split('.')[0], t[1] if len(t) > 1 else ''
			if op == 'lea' and arg.startswith('$') and arg.endswith('(a2),a5'):
				return int(arg[1:-7], 16), labels
			if op not in A5_KEEPS or arg.endswith('a5') or '(a5)+' in arg or '-(a5)' in arg:
				return None
		return None

	def zp_wraps(self, i):
		"""Can a zp,X / zp,Y address wrap within the zero page? Not if
		the index register's range shows it can't."""
		rng = self.ranges.get(i.pc)
		hi = rng[1 if i.mode == 'zpx' else 2][1] if rng else 255
		if self.fast and i.pc in self.fast.get('direct', ()):
			hi = 0			# the loop's guard checked the range
		return not (i.arg == 0 or i.arg + hi <= 0xFF)

	def zp_indexed(self, i):
		"""zp,X / zp,Y: the address wraps within the zero page, unless
		the index register's range shows it can't."""
		a = i.arg
		r = 'd1' if i.mode == 'zpx' else 'd2'
		if not self.zp_wraps(i):
			if a <= 0x7F:
				return [], self.ix(a, r)
			return self.a5_ix(a, r, '$%02X' % a)
		if a <= 0x7F:				# (moveq clears d6's upper bits)
			return ['moveq #%d,d6' % a, 'add.b %s,d6' % r], '(a2,d6.w)'
		return ['move.w %s,d6' % r, 'addi.b #$%02X,d6' % a], '(a2,d6.w)'

	def io_read(self, a):
		if a in (0x4016, 0x4017):		# a controller: its next bit (as rcReadPad)
			pad = 'cpuInputData+%d(a4)' % (2 * (a - 0x4016))
			return ['move.w %s,d7' % pad, 'andi.w #1,d7', 'lsr %s' % pad], 'd7'
		if a < 0x4000:
			return ['jsr ' + PPU_READ[a & 7]], 'd7'
		if a < 0x4100:
			return ['moveq #0,d4', 'move.b #$%02X,d4' % (a & 0xFF), 'jsr rdFrom_APU'], 'd7'
		return ['move.w #$%04X,d6' % a, 'jsr rcRead16'], 'd7'

	def indy_addr(self, zp):
		# high byte through the stack: a byte push fills the upper half
		# of a word, cheaper than shifting
		return ['move.b $%02X(a2),-(sp)' % ((zp + 1) & 0xFF), 'move.w (sp)+,d6',
			'move.b $%02X(a2),d6' % zp, 'add.w d2,d6']

	def indx_addr(self, zp):
		return ['move.w d1,d5', 'addi.b #$%02X,d5' % zp, 'move.b (a2,d5.w),d4',
			'addq.b #1,d5', 'move.b (a2,d5.w),d6', 'lsl.w #8,d6', 'move.b d4,d6']

	def wram(self, a, hi=0):
		"""Are a to a+hi in PRG RAM? With banked PRG it's always there
		(md.asm), read and written directly: rcWram+a(a4)."""
		return self.prg.banked and 0x6000 <= a and a + hi < 0x8000

	def switches(self, i):
		"""Can i, in a bank's code, write to the mapper (and switch the
		bank it runs in)? MMC3 PRG mode 1: R7 switches $A000's bank, R6
		$C000's (mmc3_regs)."""
		if self.prg.unit == 'F' or not self.prg_switch(i):
			return False
		regs = self.mmc3_regs(i) if self.prg.mode1 else None
		return regs is None or {'A': 7, 'C': 6}[self.prg.slot] in regs

	def prg_switch(self, i):
		"""Can i switch the bank at $8000? With MMC3, only its $8001 can
		(in PRG mode 1, not when it goes to R0-R5, CHR: mmc3_regs)."""
		if not (self.prg.banked and mapper_write(i)):
			return False
		if i.mode == 'abs' and self.prg.mapper == 4 and i.arg & 0xE001 != 0x8001:
			return False
		regs = self.mmc3_regs(i) if self.prg.mode1 else None
		return regs is None or max(regs) >= 6

	def mmc3_regs(self, i):
		"""The MMC3 registers (0-7) a store to $8001 can go to, from what
		$8000 holds there (mmc3_select), or None if that isn't known."""
		if not (i.mode == 'abs' and self.prg.mapper == 4 and i.arg >= 0x8000 and i.arg & 0xE001 == 0x8001):
			return None
		sel = self.mmc3_select(i)
		if sel is None or sel[0] >> 3 != sel[1] >> 3:
			return None
		return set(range(sel[0] & 7, (sel[1] & 7) + 1))

	def after_switch(self, i):
		"""After a mapper write in a bank's code: if the bank at $8000 is
		another one now, go on in its code."""
		if not self.switches(i):
			return []
		k = self.tag('Sw', i.pc)
		return self.own_bank(k) + ['move.w #$%04X,d4' % ((i.pc + i.n) & 0xFFFF), 'jmp rcDispatch', k + ':']

	def slot_jump(self, t):
		"""Lines that go to t, in the $A000 or $C000 slot (MMC3 PRG mode 1)
		where the bank isn't known here: its code in that bank's table, as
		rcDispatch looks it up (rcCurTable: R7's, less $8000; rcCurTableC:
		R6's), or rcDispatch where it has none (it interprets). Leaving a
		routine copy, the 68000's returns go (as rcDispatch drops them).
		None for anywhere else (rcDispatch)."""
		s = self.prg.region(t) if self.prg.mode1 else None
		if s not in ('A', 'C'):
			return None
		self.sj += 1
		miss, k = 'Sj%d' % self.sj, (t & 0x1FFF) * 4
		lines = ['movea.l (RAM_RcStack).w,sp'] if self.fast and (self.fast.get('routine') or self.fast.get('rf')) else []
		if s == 'A':
			lines += ['movea.l rcCurTable(a4),a5', 'lea $7FFF(a5),a5', 'move.l %d(a5),d5' % (k + 1)]
		else:
			lines += ['movea.l rcCurTableC(a4),a5', 'move.l %d(a5),d5' % k]
		return lines + ['beq.s ' + miss, 'movea.l d5,a5', 'jmp (a5)', miss + ':', 'move.w #$%04X,d4' % t,
				'jmp rcDispatch']

	def own_bank(self, k):
		"""Lines that go to k if this bank is still where its code runs
		(the bank at $8000; MMC3 PRG mode 1: R7's at $A000, R6's at $C000)."""
		if not self.prg.mode1:
			return ['cmpa.l #PRG_IMAGES+$%X,a1' % (self.prg.unit * 0x8000), 'beq.s ' + k]
		frame = 'PRG_FRAMES+$%X' % (self.prg.unit[1] * 0x8000)
		if self.prg.slot == 'A':
			return ['cmpa.l #%s,a1' % frame, 'beq.s ' + k]
		return ['cmpi.l #%s,prgFrameC(a4)' % frame, 'beq.s ' + k]

	def prg_frame(self, lo, hi):
		"""Setup and the address register to read PRG at lo to hi through,
		where it isn't constant here: a1, the image of the bank at $8000.
		MMC3 PRG mode 1: a1 is R7's frame (PRG_FRAMES), right but at $C000-
		$DFFF, and R6's (prgFrameC) is right but at $A000-$BFFF: None if
		lo to hi is in both."""
		if not self.prg.mode1 or not (lo <= 0xDFFF and hi >= 0xC000):
			return [], 'a1'
		if lo <= 0xBFFF and hi >= 0xA000:
			return None
		return ['movea.l prgFrameC(a4),a5'], 'a5'

	def dst(self, i):
		"""Setup and a 68k destination EA, or None for a generic write
		(value in d7, then the returned 'post' lines)."""
		m, a = i.mode, i.arg
		if m == 'zp':
			return [], '$%02X(a2)' % a, []
		if self.fast and i.pc in self.fast.get('check', ()):
			return self.alias_check(i, self.dst_plain(i))
		return self.dst_plain(i)

	def alias_check(self, i, d):
		"""In a loop's fast copy, a write that may hit the pointer goes
		back to the normal copy (which reloads the pointer) instead."""
		setup, ea, post = d
		ptr = self.fast['ptr']
		if ea is None or ea.startswith('(') or '(a5,' in ea:
			if ea != '(a2,d6.w)':
				return d		# a5 or a call: copy_of gives up on the copy
		if ea == '(a2,d6.w)':
			reg, vals = 'd6', ptr
		else:
			base, reg = int(ea[1:ea.index('(')], 16), ea[-5:-3]
			vals = [p - base for p in ptr if 0 <= p - base <= 255]
		chk = []
		for v in vals:
			chk += ['cmpi.b #$%02X,%s' % (v, reg), 'beq.w %s' % self.olab(i.pc)]
		return setup + chk, ea, post

	def dst_plain(self, i):
		m, a = i.mode, i.arg
		if m in ('zpx', 'zpy'):
			setup, ea = self.zp_indexed(i)
			return setup, ea, []
		if m == 'abs':
			if a < 0x2000:
				return [], '$%04X(a2)' % (a & 0x7FF), []
			if 0x2000 <= a < 0x4000:
				return [], None, ['jsr ' + PPU_WRITE[a & 7]]
			if 0x4000 <= a < 0x4020:
				return [], None, ['moveq #$%02X,d4' % (a & 0xFF), 'jsr wrTo_APU']
			if self.wram(a):
				return [], 'rcWram+$%04X(a4)' % a, []
			if a >= 0x8000 and self.prg.mapper == 4:	# MMC3's registers (emu/memory.asm)
				regs = {0x8000: 'mmc3WrSelect', 0x8001: 'mmc3WrData', 0xA000: 'mmc3WrMirror'}
				if self.prg.irq:		# and the scanline IRQ's (MMC3_IRQ)
					regs.update({0xC000: 'mmc3WrIrqLatch', 0xC001: 'mmc3WrIrqReload',
						     0xE000: 'mmc3WrIrqOff', 0xE001: 'mmc3WrIrqOn'})
				reg = regs.get(a & 0xE001)
				return [], None, (['jsr ' + reg] if reg else []) + self.after_switch(i)
			if a >= 0x8000 and self.prg.mapper == 2:
				return [], None, ['jsr mapper2Write'] + self.after_switch(i)
			return [], None, ['move.w #$%04X,d6' % a, 'jsr rcWrite16'] + self.after_switch(i)
		if m in ('absx', 'absy'):
			r = 'd1' if m == 'absx' else 'd2'
			if a + 255 < 0x2000:
				setup, ea = self.ram_indexed(i, r)
				return setup, ea, []
			if self.wram(a, self.index_hi(i)):
				return ['lea rcWram+$%04X(a4),a5' % a], '(a5,%s.w)' % r, []
			if self.wram(a) and i.m in ('STA', 'STX', 'STY'):	# unless the index takes it past $7FFF
				return [], None, self.wram_checked(i, r)
			return [], None, ['move.w #$%04X,d6' % a, 'add.w %s,d6' % r, 'jsr rcWrite16'] + self.after_switch(i)
		if m == 'indy':
			# RAM (the usual case) inline; mirrors, I/O and PRG out of line
			wn, wd = self.tag('Wn', i.pc), self.tag('Wd', i.pc)
			self.stubs += [wn + ':']
			if self.prg.banked:		# PRG RAM
				wi = self.tag('Wi', i.pc)
				self.stubs += ['\t\tcmpi.w #$6000,d6', '\t\tbcs.s ' + wi, '\t\ttst.w d6', '\t\tbmi.s ' + wi,
					       '\t\tlea (RAM_Fami_WRAM-$6000).l,a5', '\t\tmove.b d7,(a5,d6.w)',
					       '\t\tjmp ' + wd, wi + ':']
			self.stubs += ['\t\tjsr rcWrite16', '\t\tjmp ' + wd]
			return [], None, self.indy_addr(a) + ['cmpi.w #$800,d6', 'bcc.w ' + wn,
							      'move.b d7,(a2,d6.w)', wd + ':']
		if m == 'indx':
			return [], None, self.indx_addr(a) + ['jsr rcWrite16']
		raise ValueError(m)

	# ---- flags ----------------------------------------------------------

	def save_nz(self):
		self.e('move sr,d5', 'andi.w #$C,d5', 'andi.b #$F3,d3', 'or.b d5,d3')

	def save_nzc(self):			# shifts: X N Z C, keep V
		self.e('move sr,d5', 'andi.w #$1D,d5', 'andi.b #$E2,d3', 'or.b d5,d3')

	# ---- control flow ---------------------------------------------------

	def return_points(self):
		"""For each RTS, the return points of the JSRs that can reach it,
		up to 4 in this code, then up to 2 in the fixed bank's code (from
		a bank's). Only a prediction: RTS still checks the address it
		pulled."""
		mine = rts_returns(self.insns, self.tables)
		every = rts_returns(self.insns, self.tables, ext_calls=self.ext_calls) if self.ext_calls else mine
		found = {}
		for pc, r in every.items():
			own = mine.get(pc, set())
			if len(own) <= 4:
				ext = sorted(r - own)
				found[pc] = sorted(own) + (ext if len(ext) <= 2 else [])
		return found

	def idle_loops(self):
		"""Loops that wait for VBlank, for the FPS counter (emu/fps.asm):
		a few loads, compares and branches with nothing stored, like
		LDA flag / BEQ back. Leaving one ends a game frame, whether it
		had to wait or not: returns the closing branches. A JMP to itself
		(a game that runs in its NMI handler) counts the NMIs taken
		there instead: returns those too."""
		exits, jmps = set(), set()
		for b in self.insns.values():
			if b.m == 'JMP' and b.mode == 'abs' and b.arg == b.pc:
				jmps.add(b.pc)
			if b.mode != 'rel' or b.decided or b.arg > b.pc or b.pc - b.arg > 8:
				continue
			pc, ok = b.arg, True
			while pc < b.pc and ok:
				i = self.insns.get(pc)
				ok = i is not None and (i.mode == 'rel' or (
					i.m in ('LDA', 'LDX', 'LDY', 'BIT', 'CMP', 'CPX', 'CPY', 'AND', 'ORA', 'EOR')
					and i.mode in ('imm', 'zp', 'abs')))
				pc += i.n if i else 0
			if ok and pc == b.pc:
				exits.add(b.pc)
		return exits, jmps

	def nmi_check(self, t):
		"""The NMI check before a backward jump to t: in a loop that waits
		for VBlank, for any NMI due; elsewhere, for one that can't wait
		(rcNmi in emu/recomp.asm). In a routine's copy (or a loop's fast
		copy in one), an NMI taken there comes back to it (rcNmiIn,
		nest_ok)."""
		k = 'In' if NEST[0] and self.fast and (self.fast.get('routine') or self.fast.get('rf')) else ''
		if t in self.idle_jmps:
			return 'tst.w nmiWaitDue(a4)', 'jsr rcNmiIdle' + k
		if t in self.idle_heads:
			return 'tst.w nmiWaitDue(a4)', 'jsr rcNmiWait' + k
		return 'tst.w FamiMdVint(a4)', 'jsr rcNmi' + k

	def rti_next(self, i):
		"""An RTI right after i, in its 8 KB (so in its bank). Nothing
		between them can take an interrupt."""
		j = self.insns.get(i.pc + 1)
		return j is not None and j.m == 'RTI' and (i.pc + 1) & 0x1FFF != 0

	def php_pairs(self):
		"""PHPs whose byte only a PLP pulls, and those PLPs: from the
		PHP, every way reaches a PLP soon, with no other stack use, SEI,
		CLI, SED or CLD on the way, and nothing else jumps into the code
		between them. The PHP can push d3's flags as they are, and the
		PLP take them back (I and D are as they were)."""
		return self.stack_pairs('PHP', 'PLP')

	def pha_pairs(self):
		"""PHAs whose byte only a PLA pulls, and those PLAs, as php_pairs,
		with no jump back on the way (an NMI check there can leave through
		rcDispatch) and no bank switch: the byte can go on the 68000's
		stack, which nothing between them changes. (The 6502's stack
		isn't written: as with routines called with the 68000's jsr.)"""
		return self.stack_pairs('PHA', 'PLA', lambda i: not self.switches(i) and
					all(s is None or s > i.pc for s in i.succ))

	def pairs_2006(self):
		"""Stores to $2006 two at a time: from the first, straight code
		that only moves values between registers and RAM leads to the
		second, and nothing else comes into it (as stack_pairs). The
		first leaves its byte on the 68000's stack (right before the
		second, in its register), and the second writes both
		(wrPPU_AddrPair), as the two writes would: nothing between them
		sees the PPU, or a (zp),Y read there that does writes the first
		before it (rcRead16P) and leaves the second to write alone.
		{first: (second, read)}, {second: (first, read)} and those reads."""
		def addr(i):
			return i.m in ('STA', 'STX', 'STY') and i.mode == 'abs' and 0x2000 <= i.arg < 0x4000 and \
			       i.arg & 7 == 6

		def plain(i):			# no call, jump, PPU or 68000 stack
			if i.m in ('TAX', 'TAY', 'TXA', 'TYA', 'INX', 'INY', 'DEX', 'DEY', 'CLC', 'SEC', 'CLV', 'NOP'):
				return True
			if i.m not in ('LDA', 'LDX', 'LDY', 'STA', 'STX', 'STY', 'ORA', 'AND', 'EOR', 'ADC', 'SBC',
				       'CMP', 'CPX', 'CPY', 'BIT', 'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR'):
				return False
			if i.mode in ('imm', 'acc', 'zp', 'zpx', 'zpy'):
				return True
			if i.mode == 'indy':
				return i.m not in ('STA', 'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR')
			return i.mode in ('abs', 'absx', 'absy') and i.arg + (0 if i.mode == 'abs' else 255) < 0x2000

		outside = self.targets | set(self.tables)
		firsts, seconds, reads = {}, {}, set()
		for p in sorted(self.insns):
			i = self.insns[p]
			if not addr(i) or p in seconds or i.succ != [p + 3]:
				continue
			pc, between = p + 3, []
			for _ in range(8):
				q = self.insns.get(pc)
				if q is None or pc in outside:
					break
				if addr(q):
					ind = [b.pc for b in between if b.mode == 'indy']
					firsts[p], seconds[pc] = (pc, bool(ind)), (p, bool(ind))
					reads |= set(ind)
					break
				if not plain(q) or q.succ != [pc + q.n]:
					break
				between.append(q)
				pc += q.n
		return firsts, seconds, reads

	def stack_pairs(self, push, pull, also=lambda i: True):
		"""(Pushes in between are fine where every way pulls them again
		first, as Super Mario Bros. 3's PHP PHP ... PLP PHA ... PLA PLP:
		the walk keeps how many bytes are on the push's.)"""
		preds = {pc: set() for pc in self.insns}
		for i in self.insns.values():
			for s in i.succ:
				if s in preds:
					preds[s].add(i.pc)
		outside = set(self.entries) | set(self.tables) | {i.pc + 3 for i in self.insns.values() if i.m == 'JSR'}
		found = set()
		for p in self.insns.values():
			if p.m != push:
				continue
			depth, pulls, work, ok = {}, set(), [(p.pc + 1, 0)], True
			while work and ok:
				pc, d = work.pop()
				i = self.insns.get(pc)
				if i is None or len(depth) > 32 or i.m in ('JSR', 'RTS', 'RTI', 'BRK', 'TSX', 'TXS', 'SEI', 'CLI',
									    'SED', 'CLD') or None in i.succ or not also(i):
					ok = False
				elif pc in depth:
					ok = depth[pc] == d	# (each way gets there with as many on top)
				else:
					depth[pc] = d
					d += {'PHA': 1, 'PHP': 1, 'PLA': -1, 'PLP': -1}.get(i.m, 0)
					if d >= 0:
						work += [(s, d) for s in i.succ]
					elif i.m == pull:	# pulls the push's byte
						pulls.add(pc)
					else:
						ok = False
			walk = set(depth)
			if ok and pulls and not (walk & outside) and all(preds[pc] <= walk | {p.pc} for pc in walk):
				found |= {p.pc} | pulls
		return found

	def loop_edges(self):
		"""Backward branches and jumps that close a loop: their target
		can come back to them. Only those need an NMI check (a branch
		back to an RTS doesn't). Through a computed jump or code that
		isn't translated here, it might: those count as loops."""
		found = set()
		for b in self.insns.values():
			if not ((b.mode == 'rel' and b.decided != 'not') or (b.m == 'JMP' and b.mode == 'abs')) or b.arg > b.pc:
				continue
			seen, work = set(), [b.arg]
			while work:
				pc = work.pop()
				if pc == b.pc or pc not in self.insns or len(seen) > 2000:
					found.add(b.pc)
					break
				if pc in seen:
					continue
				seen.add(pc)
				i = self.insns[pc]
				if i.m == 'JSR':
					work += list(i.table) if i.table else [pc + 3]
				elif i.m not in ('RTS', 'RTI'):
					if None in i.succ:
						found.add(b.pc)
						break
					work += i.succ
		return found

	def back(self, i, t):
		"""Does going from i to t close a loop (and need an NMI check)?"""
		return t <= i.pc and (i.pc in self.loopy or i.mode not in ('rel', 'abs'))

	def counted_loops(self):
		"""Back edges of short counted loops, which don't need an NMI
		check: an innermost loop closed by a branch on a register that
		DEX/DEY/INX/INY just changed, with no other write to it and no
		calls or jumps inside. It ends within 256 turns, so the NMI is
		only delayed a little and taken at the next check."""
		writes = {'X': ('LDX', 'TAX', 'TSX', 'INX', 'DEX'), 'Y': ('LDY', 'TAY', 'INY', 'DEY')}
		found = set()
		for b in self.insns.values():
			if b.mode != 'rel' or b.decided or b.arg > b.pc:
				continue
			p = self.insns.get(b.pc - 1)
			p = p or self.insns.get(b.pc - 2)
			if p and p.pc + p.n != b.pc:
				continue
			if p and p.m in ('INC', 'DEC') and p.mode == 'zp':
				reg = p.arg		# counter in zero page
			elif p and p.m in ('INX', 'DEX', 'INY', 'DEY'):
				reg = p.m[2]
			else:
				continue
			# the loop: what is on a way from its head back to b, in
			# its range (a way out, as an RTS when a search finds what
			# it looks for, isn't), every way to b through p
			fwd, work, ok = set(), [b.arg], True
			while work and ok:
				pc = work.pop()
				if pc in fwd or not b.arg <= pc < b.pc:
					continue
				i = self.insns.get(pc)
				if i is None:
					ok = False
					break
				fwd.add(pc)
				work += [s for s in i.succ if s is not None]
			back, work = {b.pc}, [b.pc]
			while work and ok:
				t = work.pop()
				for pc in fwd:
					if pc not in back and t in self.insns[pc].succ:
						back.add(pc)
						work.append(pc)
			pcs = sorted(fwd & back)
			body = [self.insns[pc] for pc in pcs]
			if ok and (not pcs or pcs[0] != b.arg or p.pc not in back or
				   any(b.pc in i.succ and i is not p for i in body) or
				   any(i.m in ('JSR', 'JMP', 'RTS', 'RTI', 'BRK') or None in i.succ or
				       (i.mode == 'rel' and i.arg <= i.pc) for i in body)):
				ok = False		# (a call, a jump, an inner loop)
			pc = b.pc
			if isinstance(reg, int):
				n = sum(1 for i in body if i.mode == 'zp' and i.arg == reg and
					i.m in ('STA', 'STX', 'STY', 'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR'))
			else:
				# one write, or a run of the same INX/INY/DEX/DEY just
				# before the branch (a stride of 2, 4...)
				ws = [i for i in body if i.m in writes[reg]]
				n = 1 if ws and all(w.m == p.m for w in ws) and ws == body[-len(ws):] else len(ws)
			if ok and pc == b.pc and n == 1:
				found.add(b.pc)
		return found

	def lab(self, a):
		"""Label of a 6502 address; inside a loop's fast copy (see
		version_plan) the loop's own instructions have their own labels."""
		if self.fast and a in self.fast['pcs']:
			return '%s_%04X' % (self.fast['prefix'], a)
		return self.olab(a)

	def olab(self, a):
		"""Label in the code around a loop's fast copy."""
		o = self.fast.get('outer') if self.fast else None
		return '%s_%04X' % (o, a) if o else lab(a)

	def tag(self, tag, pc):
		return '%s%s_%04X' % (self.fast['prefix'] if self.fast else '', tag, pc)

	def goto(self, i, target, tag='K'):
		"""Unconditional jump; backward jumps check for an NMI first."""
		back = self.back(i, target)
		if back and i.pc in self.counted and target in self.insns:
			self.e('jmp %s' % self.lab(target))
			return
		if back and target in self.prologued and not self.fast:
			self.e('jmp C_%04X' % target)
			return
		if back:
			flag, call = self.nmi_check(target)
			self.e(flag, 'beq.s %s' % self.tag(tag, i.pc), 'move.w #$%04X,d4' % target, call)
			self.out.append('%s:' % self.tag(tag, i.pc))
		if target in self.insns:
			self.e('jmp %s' % self.lab(target))
		elif target in self.ext:
			self.e('jmp %s' % lab(target))
		else:
			self.e(*(self.slot_jump(target) or ['move.w #$%04X,d4' % target, 'jmp rcDispatch']))

	def branch(self, i, cc, tag='S'):
		"""Conditional branch on 68k condition cc (flags already in the CCR).
		Out-of-line stubs (tag 'T') are far from their targets: jmp there."""
		t, nxt = i.arg, i.pc + 2
		back = self.back(i, t)
		if back and i.pc in self.counted and t in self.insns and tag != 'T':
			self.e('b%s.w %s' % (cc, self.lab(t)))
			return
		if back and t in self.prologued and tag != 'T' and not self.fast:
			self.e('b%s.w C_%04X' % (cc, t))
			return
		if back or t not in self.insns or tag == 'T':
			self.e('b%s.w %s' % (INVERT[cc], self.tag(tag, i.pc)))
			self.goto(i, t, 'J' if tag == 'T' else 'K')
			self.out.append('%s:' % self.tag(tag, i.pc))
		else:
			self.e('b%s.w %s' % (cc, self.lab(t)))

	# ---- one instruction ---------------------------------------------------

	def inc_run(self, i):
		"""INX/INY/DEX/DEY: the run of the same instruction that i starts
		(none of the others a jump target), or [] when i continues one."""
		delay = self.delays | self.delay_skip
		if i.m not in ('INX', 'INY', 'DEX', 'DEY') or self.fast or i.pc in delay:
			return [i]
		p = self.insns.get(i.pc - 1)
		if p is not None and p.m == i.m and i.pc not in self.targets:
			return []
		run = [i]
		while len(run) < 8:
			n = self.insns.get(run[-1].pc + 1)
			if n is None or n.m != i.m or n.pc in self.targets or n.pc in delay:
				break
			run.append(n)
		return run

	def emit(self, i, nxt_i):
		if self.fused_next == i.pc:
			self.fused_next = self.direct_next = self.split_next = None
			return
		self.fused_next = None
		m = i.m
		run = self.inc_run(i)
		if not run:
			return			# counted in by the first of its run
		if len(run) > 1:		# flags and branch as after the last
			i, nxt_i = run[-1], self.insns.get(run[-1].pc + 1)
		live = i.live_out
		defs = DEFS.get(m, 0)
		need = defs & live
		# can the next instruction (a branch) test our flags directly?
		direct = None
		self.split_next = None
		if (nxt_i is not None and nxt_i.mode == 'rel' and nxt_i.decided is None
		    and FLAG_OF[nxt_i.m] & defs):
			if not (defs & nxt_i.live_out):
				direct = nxt_i
			else:			# read after it: into d3 on the way out (split_plan)
				self.split_next = self.split_plan(i, m, nxt_i, defs)
				if self.split_next:
					direct, need = nxt_i, 0
		self.direct_next = None

		def nz_done(kind='nz'):
			if direct and kind:
				self.direct_next = kind
			elif need:
				self.save_nz()

		if i.pc in self.delay_skip:
			pass			# in the nested delay loop at its LDX/LDY
		elif i.pc in self.delays2:
			# two nested delay loops (see run), timed in NES cycles: a
			# turn of the inner one is 5, of the outer DEX and BNE 5
			kind, n = self.delays2[i.pc]
			ri, ro = ('d1', 'd2') if m[2] == 'X' else ('d2', 'd1')
			if self.fast and (self.fast.get('off', {}).get(ri) or self.fast.get('off', {}).get(ro)):
				raise Unroll
			if kind == 'A':		# outer turns: LDY, n inner turns, DEX, BNE
				self.e('move.w %s,d4' % ro, 'move.w #%d,d5' % (5 * n + 6), 'moveq #-1,d6', 'jsr rcDelay')
			else:			# n turns, then the outer ones with 256
				self.e('moveq #%d,d4' % (n & 0xFF) if n < 128 else 'move.w #%d,d4' % (n & 0xFF),
				       'moveq #5,d5', 'moveq #-1,d6', 'jsr rcDelay',
				       'move.w %s,d4' % ro, 'move.w #1284,d5', 'move.w #-1280,d6', 'jsr rcDelay')
			self.e('clr.b %s' % ri, 'clr.b %s' % ro)
			self.save_nz()
		elif i.pc in self.delays:
			# a delay loop (to time a raster effect): its NES time moves
			# the frame's clock on, and it takes none here
			r = 'd1' if m[2] == 'X' else 'd2'
			if self.fast and self.fast.get('off', {}).get(r):
				raise Unroll
			self.e('move.w %s,d4' % r, 'moveq #5,d5', 'moveq #-1,d6', 'jsr rcDelay', 'clr.b %s' % r)
			nz_done()
		elif m == 'LDA' and self.pad_lsr(i, nxt_i):
			# LDA $4016 / LSR A, a controller's next bit into the carry:
			# the bit is shifted straight out of the data into X and C,
			# and A is 0 (rcReadPad and the others read only bit 0)
			self.e('moveq #0,d0', 'lsr cpuInputData+%d(a4)' % (2 * (i.arg - 0x4016)))
			self.xc = True
			need = DEFS['LSR'] & nxt_i.live_out
			if need & C and self.carry_in_x(nxt_i):
				need &= ~C			# carried in X instead
				self.c_skipped = nxt_i.pc
			if need:			# N 0, Z 1, X and C from the CCR
				self.e(*['move sr,d5', 'andi.w #$11,d5'] * bool(need & C),
				       'andi.b #$%02X,d3' % (~((8 if need & N else 0) | (4 if need & Z else 0) |
							      (0x11 if need & C else 0)) & 0xFF),
				       *['ori.b #4,d3'] * bool(need & Z), *['or.b d5,d3'] * bool(need & C))
			self.fused_next = nxt_i.pc
		elif m in ('LDA', 'LDX', 'LDY'):
			r = {'LDA': 'd0', 'LDX': 'd1', 'LDY': 'd2'}[m]
			setup, s = self.src(i, r)
			self.e(*setup)
			if s.startswith('#') and (int(s[2:], 16) < 0x80 or r == 'd0'):
				v = int(s[2:], 16)	# moveq: X/Y must stay zero-extended
				self.e('moveq #%d,%s' % (v - 256 if v >= 0x80 else v, r))
			elif s != r:
				self.e('move.b %s,%s' % (s, r))
			nz_done()
		elif m in ('STA', 'STX', 'STY') and (self.mmc3_store(i, {'STA': 'd0', 'STX': 'd1', 'STY': 'd2'}[m]) or
						     self.apu_store(i, {'STA': 'd0', 'STX': 'd1', 'STY': 'd2'}[m]) or
						     self.ppu_store(i, {'STA': 'd0', 'STX': 'd1', 'STY': 'd2'}[m]) or
						     self.addr_store(i, {'STA': 'd0', 'STX': 'd1', 'STY': 'd2'}[m])):
			pass
		elif m in ('STA', 'STX', 'STY'):
			r = {'STA': 'd0', 'STX': 'd1', 'STY': 'd2'}[m]
			setup, d, post = self.dst(i)
			self.e(*setup)
			if d is not None:
				self.e('move.b %s,%s' % (r, d))
			else:
				self.e('move.b %s,d7' % r, *post)
		elif m in ('TAX', 'TAY', 'TXA', 'TYA'):
			s, d = {'TAX': ('d0', 'd1'), 'TAY': ('d0', 'd2'), 'TXA': ('d1', 'd0'), 'TYA': ('d2', 'd0')}[m]
			self.e('move.b %s,%s' % (s, d))
			nz_done()
		elif m == 'TSX':
			self.e('swap d3', 'move.b d3,d1', 'swap d3', 'tst.b d1')
			nz_done()
		elif m == 'TXS':
			self.e('swap d3', 'move.b d1,d3', 'swap d3')
		elif self.fast and i.pc in self.fast.get('skip', ()):
			if m in ('INX', 'INY', 'DEX', 'DEY'):	# unrolled: register is off by one more
				self.fast['off']['d1' if m[2] == 'X' else 'd2'] += 1 if m[0] == 'I' else -1
		elif m in ('INX', 'INY', 'DEX', 'DEY'):
			r = 'd1' if m[2] == 'X' else 'd2'
			self.e('%s.b #%d,%s' % ('addq' if m[0] == 'I' else 'subq', len(run), r))
			nz_done()
		elif m in ('INC', 'DEC'):
			op = 'addq' if m == 'INC' else 'subq'
			setup, d, post = self.dst(i)
			if d is not None:
				self.e(*setup)
				self.e('%s.b #1,%s' % (op, d))
				nz_done()
			else:
				self.rmw_generic(i, ['%s.b #1,d7' % op], need, 'nz')
		elif m in ('AND', 'ORA', 'EOR'):
			setup, s = self.src(i)
			self.e(*setup)
			op = {'AND': 'and', 'ORA': 'or', 'EOR': 'eor'}[m]
			if m == 'EOR' and not s.startswith('#') and s != 'd7':
				self.e('move.b %s,d7' % s)
				s = 'd7'
			if s.startswith('#'):
				self.e('%si.b %s,d0' % (op, s))
			else:
				self.e('%s.b %s,d0' % (op, s))
			nz_done()
		elif m in ('ADC', 'SBC'):
			setup, s = self.src(i)
			self.e(*setup)
			if m == 'ADC':
				self.check_carry()
			op = 'add' if m == 'ADC' else 'sub'
			plain = i.cin and i.cin[0] == (m == 'SBC')	# CLC / ADC, SEC / SBC
			if i.cin and not plain and not need:	# SEC / ADC, CLC / SBC, no flags read: and the 1
				self.e(('%si.b %s,d0' if s.startswith('#') else '%s.b %s,d0') % (op, s), '%sq.b #1,d0' % op)
				return
			# (addx and subx only clear Z: set it first if it's read)
			zero = bool(need & Z)
			if plain:			# a plain add or subtract
				self.e(('%si.b %s,d0' if s.startswith('#') else '%s.b %s,d0') % (op, s))
				if m == 'ADC':
					self.xc = True		# (X: the carry)
			else:
				if s != 'd7':
					self.e('move.b %s,d7' % s)
				if i.cin:			# SEC / ADC, CLC / SBC: X set (and Z)
					self.e('move #$14,ccr', '%sx.b d7,d0' % op)
				elif m == 'ADC' and self.xc:	# carry already in X
					self.e(*['ori #4,ccr'] * zero, 'addx.b d7,d0')
				elif m == 'ADC':
					self.e(*['ori.b #4,d3'] * zero, 'move d3,ccr', 'addx.b d7,d0')
				else:
					self.e('eori.b #$11,d3', *['ori.b #4,d3'] * zero, 'move d3,ccr', 'subx.b d7,d0')
			# the flags are in the CCR (after SBC, C is the borrow): a branch
			# right after them reads them there
			if direct:
				self.direct_next = op
			elif need:
				self.e('move sr,d3', *['eori.b #$11,d3'] * (m == 'SBC'))
				if m == 'ADC' and nxt_i is not None and nxt_i.mode == 'rel' and nxt_i.decided is None:
					self.direct_next = 'flags'	# also still in the CCR
		elif m in ('CMP', 'CPX', 'CPY'):
			if need or direct:
				r = {'CMP': 'd0', 'CPX': 'd1', 'CPY': 'd2'}[m]
				setup, s = self.src(i)
				self.e(*setup)
				if need and not direct:
					# r + ~s + 1 carries like the 6502's compare (X too)
					if s.startswith('#'):	# (handlers expect d7's upper bits clear)
						self.e('move.b #$%02X,d7' % (~int(s[2:], 16) & 0xFF))
					else:
						self.e('move.b %s,d7' % s, 'not.b d7')
					self.e('move.b %s,d6' % r, 'move #$14,ccr', 'addx.b d7,d6')
					if live & V:		# X N Z C into d3, V as it was
						self.e('move sr,d5', 'andi.b #$1D,d5', 'andi.b #$E2,d3', 'or.b d5,d3')
					else:
						self.e('move sr,d3')
						if nxt_i is not None and nxt_i.mode == 'rel' and nxt_i.decided is None:
							self.direct_next = 'flags'	# also still in the CCR
					return
				self.e(('cmpi.b %s,%s' if s.startswith('#') else 'cmp.b %s,%s') % (s, r))
				self.direct_next = 'cmp'	# only the branch after it reads them
		elif m == 'BIT':
			setup, s = self.src(i)
			self.e(*setup)
			if direct or need:
				if s != 'd7':
					self.e('move.b %s,d7' % s)	# N from bit 7
			if direct:
				f = FLAG_OF[direct.m]
				if f == Z:
					self.e('and.b d0,d7')
				elif f == V:
					self.e('btst #6,d7')
				elif s == 'd7':
					self.e('tst.b d7')	# read by a handler, which can leave any flags
				self.direct_next = 'bitv' if f == V else 'nz'
			elif need:			# the flags read: N bit 7, V bit 6, Z of A AND it
				self.e('andi.b #$%02X,d3' % (~((8 if need & N else 0) | (2 if need & V else 0) |
								(4 if need & Z else 0)) & 0xFF))
				if need & N:
					self.e('tst.b d7', 'bpl.s *+6', 'ori.b #8,d3')
				if need & V:
					self.e('btst #6,d7', 'beq.s *+6', 'ori.b #2,d3')
				if need & Z:
					self.e('and.b d0,d7', 'bne.s *+6', 'ori.b #4,d3')
		elif m in ('ASL', 'LSR', 'ROL', 'ROR'):
			op = {'ASL': 'lsl', 'LSR': 'lsr', 'ROL': 'roxl', 'ROR': 'roxr'}[m]
			if m in ('ROL', 'ROR'):
				self.check_carry()
			def pre():		# the carry into X (after the address: it may change X)
				return ['move d3,ccr'] if m in ('ROL', 'ROR') and not self.xc else []
			skip = bool(need & C) and self.carry_in_x(i)
			if skip:
				need &= ~C			# carried in X instead
				save = self.save_nz
			else:
				save = self.save_nzc
			if i.mode == 'acc':
				self.e(*pre())
				self.e('%s.b #1,d0' % op)
				if direct:
					self.direct_next = 'shift'
				elif need:
					save()
				if skip: self.c_skipped = i.pc
			else:
				setup, d, post = self.dst(i)
				if d is not None:
					self.e(*setup)
					self.e('move.b %s,d7' % d, *pre())
					self.e('%s.b #1,d7' % op)
					if need:
						save()
					self.e('move.b d7,%s' % d)
					if skip: self.c_skipped = i.pc
				else:
					self.rmw_generic(i, ['move d3,ccr'] * (m in ('ROL', 'ROR')) + ['%s.b #1,d7' % op],
							 need | (DEFS[m] & i.live_out), 'shift')
		elif m == 'CLC':
			if need: self.e('andi.b #$EE,d3')
		elif m == 'SEC':
			if need: self.e('ori.b #$11,d3')
		elif m == 'CLV':
			if need: self.e('andi.b #$FD,d3')
		elif m in ('CLI', 'SEI'):
			self.e('move.w #%d,cpuModeIntDis(a4)' % (m == 'SEI'))
			if m == 'CLI':
				self.irq_check(i)
		elif m in ('CLD', 'SED'):
			self.e('move.w #%d,cpuModeDec(a4)' % (m == 'SED'))
		elif m == 'NOP':
			pass
		elif m == 'PHA' and i.pc in self.pha_paired:	# only its PLA reads it
			self.e('move.b d0,-(sp)')
		elif m == 'PHA':
			self.e('swap d3', 'move.b d0,(a2,d3.w)', 'subq.b #1,d3', 'swap d3')
		elif m == 'PHP' and i.pc in self.paired:	# only its PLP reads it: d3's flags as they are
			self.e('move.b d3,d5', 'swap d3', 'move.b d5,(a2,d3.w)', 'subq.b #1,d3', 'swap d3')
		elif m == 'PHP':
			self.e('jsr famiGetP', 'swap d3', 'move.b d5,(a2,d3.w)', 'subq.b #1,d3', 'swap d3')
		elif m == 'PLA' and i.pc in self.pha_paired:
			self.e('move.b (sp)+,d0')
			nz_done()
		elif m == 'PLA':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d0', 'swap d3', 'tst.b d0')
			nz_done()
			if self.double_exit(i):		# and the RTS after it, as the caller's
				self.e('addq.l #4,sp', 'swap d3', 'addq.b #2,d3', 'swap d3', 'rts')
		elif m == 'PLP' and self.rti_next(i):	# the RTI pulls all P sets (flags, I, D)
			self.e('swap d3', 'addq.b #1,d3', 'swap d3')
		elif m == 'PLP' and i.pc in self.paired:
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d5', 'swap d3', 'move.b d5,d3')
		elif m == 'PLP':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d5', 'swap d3', 'jsr famiSetP')
		elif m == 'JMP' and self.fast and i.pc in self.tails.get(self.fast.get('f', self.fast.get('rf')), ()):
			if not self.fast.get('routine'):
				raise Unroll		# (a loop's fast copy in a routine's: no calls there)
			heavy, sw, label = self.ext_routines[i.arg][:3]
			self.e('jsr ' + label)		# a tail call (routine_body): the copy, then back as RTS goes
			if self.fast.get('inline'):
				self.e('bra.w %s' % self.fast['inline'])
			else:
				if self.fast['heavy'] and not heavy:
					self.e('swap d3', 'addq.b #2,d3', 'swap d3')	# (a heavy copy drops it itself)
				self.e('rts')
		elif m == 'JMP':
			if i.mode == 'abs':
				self.goto(i, i.arg)
			else:
				p = i.arg
				hi = (p & 0xFF00) | ((p + 1) & 0xFF)	# 6502 page wrap bug
				if self.prg.const(p) and self.prg.const(hi):
					self.goto(i, self.prg.byte(p) | self.prg.byte(hi) << 8)
				elif p >= 0x8000:
					setup, base = self.prg_frame(min(p, hi), max(p, hi))
					self.e(*setup, 'move.b $%04X(%s),d4' % (hi & 0x7FFF, base), 'lsl.w #8,d4',
					       'move.b $%04X(%s),d4' % (p & 0x7FFF, base), 'jmp rcDispatch')
				else:
					hi = (p & 0xFF00) | ((p + 1) & 0xFF)	# 6502 page wrap bug
					self.e('move.b $%04X(a2),d4' % (hi & 0x7FF), 'lsl.w #8,d4',
					       'move.b $%04X(a2),d4' % (p & 0x7FF), 'jmp rcDispatch')
		elif m == 'JSR' and not (self.fast and not self.fast.get('routine')) and i.arg in self.engines and \
		     (i.arg in self.insns or i.arg in self.ext) and self.engine_table(i):
			self.emit_engine_call(i)
		elif m == 'JSR' and i.arg in self.inline and (not self.fast or self.fast.get('routine')):
			self.emit_inline(i)
		elif m == 'JSR' and i.arg in self.callable and (i.arg not in self.double_rts or
								 self.fast and self.fast.get('routine') and not self.fast.get('inline')):
			if self.callable[i.arg][1]:
				ret = i.pc + 2
				self.e('swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
				       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3', 'swap d3')
			self.e('jsr R%04X_%04X' % (i.arg, i.arg))	# see routine_body
			self.called.add(i.arg)
		elif m == 'JSR' and i.arg in self.ext_routines and not i.table:
			heavy, sw, label = self.ext_routines[i.arg][:3]
			if heavy:
				ret = i.pc + 2
				self.e('swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
				       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3', 'swap d3')
			self.e('jsr ' + label)		# the fixed bank's copy
			if sw:				# it may have switched this bank out
				k = self.tag('Sw', i.pc)
				self.e(*self.own_bank(k), 'move.w #$%04X,d4' % ((i.pc + 3) & 0xFFFF), 'jmp rcDispatch')
				self.out.append(k + ':')
		elif m == 'JSR' and self.dyn_target(i):
			self.emit_dyn_call(i)
		elif m == 'JSR':
			ret = i.pc + 2
			self.e('swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
			       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3', 'swap d3')
			if self.fast and self.fast.get('routine'):	# leaving a copy: drop the 68000's returns
				if i.arg >= 0x8000 and (not self.prg.banked or i.arg in self.insns or i.arg in self.ext):
					self.e('movea.l (RAM_RcStack).w,sp', 'jmp %s' % lab(i.arg))
				else:
					self.e(*(self.slot_jump(i.arg) or ['move.w #$%04X,d4' % i.arg, 'jmp rcDispatch']))
			elif i.arg >= 0x8000 and (not self.prg.banked or i.arg in self.insns or i.arg in self.ext):
				self.e('jmp %s' % lab(i.arg))
			else:
				self.e(*(self.slot_jump(i.arg) or ['move.w #$%04X,d4' % i.arg, 'jmp rcDispatch']))
		elif m == 'RTS' and self.fast and self.fast.get('inline'):
			if self.fast['last'] != i.pc:		# (the last one falls into the code after the call)
				self.e('bra.w %s' % self.fast['inline'])
		elif m == 'RTS' and self.fast and self.fast.get('routine'):
			if self.fast['heavy']:
				self.e('swap d3', 'addq.b #2,d3', 'swap d3')	# drop the return address
			self.e('rts')
		elif m == 'RTS':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d6', 'addq.b #1,d3',
			       'move.b (a2,d3.w),-(sp)', 'swap d3', 'move.w (sp)+,d4', 'move.b d6,d4',
			       'addq.w #1,d4')
			# usually it goes back to one of a few known callers
			for r in self.returns.get(i.pc, ()):
				self.e('cmpi.w #$%04X,d4' % r, 'bne.s *+8', 'jmp (%s).l' % lab(r))
			if self.returns.get(i.pc) or (self.fast and not self.fast.get('routine')) or RET_CACHES[0] == 120:
				self.e('jmp rcDispatch')
			else:				# where it went the last two times (rcDispatchC)
				self.e('lea (RAM_RcRet+%d).w,a5' % (12 * RET_CACHES[0]), 'cmp.w (a5)+,d4', 'bne.s *+6',
				       'movea.l (a5),a5', 'jmp (a5)', 'cmp.w 4(a5),d4', 'bne.s *+8', 'movea.l 6(a5),a5', 'jmp (a5)',
				       'jmp ' + self.dispatch_c())
				RET_CACHES[0] += 1
		elif m == 'RTI':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d5', 'addq.b #1,d3',
			       'move.b (a2,d3.w),d6', 'addq.b #1,d3', 'move.b (a2,d3.w),d4', 'swap d3',
			       'jsr famiSetP', 'lsl.w #8,d4', 'move.b d6,d4', 'jmp rcRti')
		elif m == 'BRK':
			ret = i.pc + 2
			self.e('jsr famiGetP', 'swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
			       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3',
			       'move.b d5,(a2,d3.w)', 'subq.b #1,d3', 'swap d3',
			       'move.w #1,cpuModeIntDis(a4)', 'move.w #$%04X,d4' % self.prg.word(0xFFFE),
			       'jmp rcDispatch')
		elif i.mode == 'rel':
			pass				# emitted with the previous instruction or below
		else:
			raise ValueError(m)

	def dispatch_c(self):
		"""The rcDispatchC (emu/recomp.asm) of this unit's RTSs: one that
		doesn't keep returns to a switched bank's code but its own (the
		bank at $8000's for the fixed bank's code; MMC3 PRG mode 1: the
		$A000 and $C000 banks' for the fixed code's, the other slot's for
		a bank's)."""
		if not self.prg.banked:
			return 'rcDispatchC'
		if not self.prg.mode1:
			return 'rcDispatchCF' if self.prg.unit == 'F' else 'rcDispatchC'
		return {'F': 'rcDispatchCF', 'A': 'rcDispatchCA', 'C': 'rcDispatchCC'}[self.prg.slot]

	def engine_table(self, i):
		"""Targets of the address table after a JSR to a jump engine,
		if they are all translated."""
		t = inline_table(self.prg, i.pc + 3)
		return t if t and all(a in self.insns or a in self.ext for a in t) else None

	def emit_engine_call(self, i):
		"""JSR to a jump engine (engine_pattern) with entry A of the table
		after it: straight to the entry, leaving what the engine would, from
		a copy of the table in the 68000 code. (Not the return address it
		pushes and pulls again, below the stack pointer: as with routines
		called with the 68000's jsr, nothing is pushed.)"""
		z1, z2 = self.engines[i.arg]
		t = self.engine_table(i)
		ret = i.pc + 2
		g, jw, jt = self.tag('Jg', i.pc), self.tag('Jw', i.pc), self.tag('Jt', i.pc)
		self.e('cmpi.b #%d,d0' % len(t), 'bcc.w ' + g)	# not in the table: the engine
		# the return address it pulled, in zp1
		if z1 & 1:
			self.e('move.b #$%02X,$%02X(a2)' % (ret & 0xFF, z1), 'move.b #$%02X,$%02X(a2)' % (ret >> 8, z1 + 1))
		else:
			self.e('move.w #$%04X,$%02X(a2)' % ((ret & 0xFF) << 8 | ret >> 8, z1))
		self.e('moveq #0,d6', 'move.b d0,d6', 'add.w d6,d6',	# ASL A, TAY
		       'move.b d6,d2', 'addq.b #2,d2',			# two INY
		       'lea %s(pc),a5' % jw)
		# the entry in zp2, and its high byte in A
		if z2 & 1:
			self.e('move.b (a5,d6.w),$%02X(a2)' % z2, 'move.b 1(a5,d6.w),d0', 'move.b d0,$%02X(a2)' % (z2 + 1))
		else:
			self.e('move.w (a5,d6.w),d5', 'move.w d5,$%02X(a2)' % z2, 'move.b d5,d0')
		if i.live_out & (N | Z | C):		# (as the table's entries need them)
			self.e('andi.b #$E2,d3', 'ori.b #8,d3')	# the high byte: N set, Z clear; C from ASL: 0
		self.e('add.w d6,d6')
		if len(t) <= 63:			# (the addresses right after the entries)
			self.e('movea.l %d(a5,d6.w),a5' % (2 * len(t)), 'jmp (a5)')
		else:
			self.e('lea %s(pc),a5' % jt, 'movea.l (a5,d6.w),a5', 'jmp (a5)')
		self.xc = False
		self.stubs += [jw + ':'] + ['\t\tdc.b $%02X,$%02X' % (a & 0xFF, a >> 8) for a in t]
		if self.fast and self.fast.get('routine') and i.pc in self.engine_tails.get(self.fast.get('f'), ()):
			# a heavy copy's (routine_body): the entry's own copy, as a tail
			# call. A heavy one drops the return address its caller pushed
			# itself; a light one is called, then that is dropped
			labs, light = [], []
			for k, a in enumerate(t):
				self.called.add(a)
				if self.callable[a][1]:
					labs.append('R%04X_%04X' % (a, a))
				else:
					labs.append(self.tag('Je%d' % k, i.pc))
					light += [labs[-1] + ':', '\t\tjsr R%04X_%04X' % (a, a), '\t\tswap d3', '\t\taddq.b #2,d3',
						  '\t\tswap d3', '\t\trts']
			self.stubs += [jt + ':'] + ['\t\tdc.l %s' % l for l in labs] + light
		else:
			self.stubs += [jt + ':'] + ['\t\tdc.l %s' % self.lab(a) for a in t]
		self.stubs += [g + ':', '\t\tswap d3', '\t\tmove.b #$%02X,(a2,d3.w)' % (ret >> 8), '\t\tsubq.b #1,d3',
			       '\t\tmove.b #$%02X,(a2,d3.w)' % (ret & 0xFF), '\t\tsubq.b #1,d3', '\t\tswap d3']
		if self.fast:				# leaving a copy: drop the 68000's returns
			self.stubs += ['\t\tmove.w #$%04X,d4' % i.arg, '\t\tjmp rcDispatch']
		else:
			self.stubs += ['\t\tjmp %s' % self.lab(i.arg)]

	def irq_check(self, i):
		"""After a CLI, with MMC3's scanline IRQ (MMC3_IRQ): the IRQ if
		it waits (rcIrqCli in emu/recomp.asm), its RTI coming back to the
		next instruction (a target, see run)."""
		if self.prg.irq:
			k = self.tag('Iq', i.pc)
			self.e('tst.w irqOn(a4)', 'beq.s ' + k, 'move.w #$%04X,d4' % ((i.pc + i.n) & 0xFFFF),
			       'jsr rcIrqCli', k + ':')

	def mmc3_store(self, i, r):
		"""A store of r to MMC3's $8000 or $8001 that the code around it
		says enough about, in place of mmc3WrSelect or mmc3WrData (emu/
		memory.asm): $8000 when bit 7 (CHR mode) is known, the handler only
		if that changes; $8001 right after a known value went to $8000,
		R0-R5 (CHR) the handler only if the bank changes, R6 and R7 (PRG
		mode 0) the value put there, then mmc3Pair, and in PRG mode 1 the
		bank's code and frame (prg1_switch) if it changes."""
		if not (self.prg.mapper == 4 and i.mode == 'abs' and i.arg >= 0x8000):
			return False
		rng = self.ranges.get(i.pc)
		v = rng[{'STA': 0, 'STX': 1, 'STY': 2}[i.m]] if rng else TOP
		if i.arg & 0xE001 == 0x8000:
			if v[1] < 0x80:
				cc = 'mi'			# CHR mode 0: was it 1?
			elif v[0] >= 0x80:
				cc = 'pl'
			else:
				return False
			back, slow = self.tag('Mb', i.pc), self.tag('Ms', i.pc)
			self.e('tst.b mmc3Select+1(a4)', 'b%s.w %s' % (cc, slow), 'move.b %s,mmc3Select+1(a4)' % r,
			       back + ':')		# (a join: X too)
			self.stubs += [slow + ':', '\t\tmove.b %s,d7' % r, '\t\tjsr mmc3WrSelect', '\t\tjmp ' + back]
			return True
		if i.arg & 0xE001 == 0x8001:
			sel = self.mmc3_select(i)
			if sel is None:
				return False
			lo, hi = sel
			same = self.tag('Mb', i.pc)
			irq, call = [], ['move.b %s,d7' % r, 'jsr mmc3WrData', same + ':']
			if self.prg.irq and lo >> 3 == hi >> 3 and hi & 7 < 6:
				# R0-R5 with the scanline IRQ (MMC3_IRQ): in the IRQ handler,
				# the handler, which knows where those go
				slow = self.tag('Mi', i.pc)
				irq, call = ['tst.w cpuInIrq(a4)', 'bne.s ' + slow], [slow + ':'] + call
			if lo == hi and lo & 7 < 6 and irq:	# R0-R5, MMC3_IRQ: in the IRQ handler,
				self.e('tst.w cpuInIrq(a4)', 'bne.s ' + slow,	# mmc3RegsSplit (as mmc3WrData)
				       'cmp.b mmc3Regs+%d(a4),%s' % (lo & 7, r), 'beq.s ' + same, 'move.b %s,d7' % r,
				       'jsr mmc3WrData', 'bra.s ' + same, slow + ':',
				       'move.b %s,mmc3RegsSplit+%d(a4)' % (r, lo & 7), same + ':')
			elif lo == hi and lo & 7 < 6:	# R0-R5
				self.e(*irq, 'cmp.b mmc3Regs+%d(a4),%s' % (lo & 7, r), 'beq.s ' + same, *call)
			elif lo >> 3 == hi >> 3 and hi & 7 < 6:	# one of R0-R5: the register from $8000
				self.e(*irq, 'moveq #7,d5', 'and.b mmc3Select+1(a4),d5', 'lea mmc3Regs(a4),a5',
				       'cmp.b (a5,d5.w),%s' % r, 'beq.s ' + same, *call)
			elif lo == hi and not lo & 0x40 and not self.prg.mode1:	# R6, R7 in PRG mode 0
				self.e('move.b %s,mmc3Regs+%d(a4)' % (r, lo & 7), 'jsr mmc3Pair', *self.after_switch(i))
			elif lo == hi and self.prg.mode1:	# R7 ($A000's bank), R6 ($C000's) in PRG mode 1
				n = lo & 7
				self.e('cmp.b mmc3Regs+%d(a4),%s' % (n, r), 'beq.s ' + same, 'move.b %s,mmc3Regs+%d(a4)' % (r, n),
				       *self.prg1_switch(n, r), *self.after_switch(i), same + ':')
			else:
				return False
			return True
		return False

	def prg1_switch(self, n, r):
		"""MMC3 PRG mode 1: R7 (n 7, $A000) or R6 now holds r's bank. What
		rcDispatch, the call tables and PRG reads go by comes from the
		bank's record (rcBankRecsA, rcBankRecsC: mode1): its code there,
		the copies of its routines other code calls (emit_dyn_call), its
		frame and the frame +$8000."""
		s = 'A' if n == 7 else 'C'
		lines = ['moveq #prgBank8Mask,d6', 'and.b %s,d6' % r, 'lsl.w #4,d6', 'lea (rcBankRecs%s).l,a5' % s,
			 'adda.w d6,a5']
		if s == 'A':		# (the frame in a1 and cpuPrgImg, a0 the frame +$8000)
			return lines + ['move.l (a5)+,rcCurTable(a4)', 'move.l (a5)+,rcCurCallA(a4)', 'movea.l (a5)+,a1',
					'move.l a1,cpuPrgImg(a4)', 'movea.l (a5),a0']
		return lines + ['move.l (a5)+,rcCurTableC(a4)', 'move.l (a5)+,rcCurCallC(a4)', 'move.l (a5)+,prgFrameC(a4)',
				'move.l (a5),rcFrameC(a4)']

	def apu_store(self, i, r):
		"""A store of r to an APU register ($4000-$401F), in place of
		wrTo_APU and its table (emu/memory.asm): the register and its
		written flag as apuStore does them, the pads latched as APU_Input
		does, APU_OAMDMA called directly; nothing for $4018-$401F."""
		if i.mode != 'abs' or not 0x4000 <= i.arg < 0x4020:
			return False
		n = i.arg & 0x1F
		if n == 0x14:
			self.e('move.b %s,d7' % r, 'jsr APU_OAMDMA')
		elif n == 0x16:
			zero = self.tag('Ap', i.pc)
			self.e('tst.b %s' % r, 'beq.s ' + zero, 'move.l padState(a4),cpuInputData(a4)', zero + ':')
		elif n < 0x18:
			self.e('move.b %s,(RAM_Fami_Apu+apuRegs+$%02X).w' % (r, n), 'st (RAM_Fami_Apu+apuWrote+$%02X).w' % n)
		return True

	def ppu_store(self, i, r):
		"""A store of r to $2007: wrPPU_Data's address step and where
		the address is, and for a nametable byte or palette entry
		written as it is (games rewrite their status bars, palettes and
		such each frame), nothing more; else the rest of wrPPU_Data for
		a palette entry, a nametable byte or CHR RAM (emu/ppu.asm)."""
		if i.mode != 'abs' or not 0x2000 <= i.arg < 0x4000 or i.arg & 7 != 7:
			return False
		kind = self.fast and self.fast.get('ppu_run')
		if kind:
			# a loop's copy whose guard found every store's address in the
			# nametables or every one in the palette (emit_versioned): the
			# address in d4, the step in d6, kept around the handler
			chg, back = self.tag('Pn', i.pc), self.tag('Pb', i.pc)
			if kind == 'nt':
				self.e('cmp.b (a3,d4.w),%s\t; (ppu run)' % r)
				call = ['\t\tmove.b %s,d7' % r, '\t\tjsr wrPPU_DataNt\t; (a5 kept) (ppu run)']
			else:
				self.e('move.w d4,d5\t; (ppu run)', 'andi.w #$3F1F,d5', 'moveq #$3F,d7', 'and.b %s,d7' % r,
				       'cmp.b (a3,d5.w),d7')
				call = ['\t\tmove.w d5,d4\t; (ppu run)', '\t\tjsr wrPPU_DataPal\t; (a5 kept) (ppu run)']
			self.e('bne.w %s' % chg, back + ':', 'add.w d6,d4\t; (ppu run)')
			self.stubs += [chg + ':', '\t\tmovem.l d4/d6/a5,-(sp)\t; (a5 kept) (ppu run)', *call,
				       '\t\tmovem.l (sp)+,d4/d6/a5\t; (a5 kept) (ppu run)', '\t\tbra.w ' + back]
			return True
		pal, chr_, done = self.tag('Pp', i.pc), self.tag('Pc', i.pc), self.tag('Pd', i.pc)
		call = self.kept_a5
		self.e('move.w ppuAddrBase(a4),d4', 'move.w ppuAddrIncr(a4),d6', 'add.w d6,ppuAddrBase(a4)',
		       'andi.w #$3FFF,d4', 'cmpi.w #$3F00,d4', 'bcc.s ' + pal, 'cmpi.w #$2000,d4', 'bcs.s ' + chr_,
		       'cmp.b (a3,d4.w),%s' % r, 'beq.s ' + done, 'move.b %s,d7' % r, *call('wrPPU_DataNt'), 'bra.s ' + done,
		       pal + ':', 'andi.w #$3F1F,d4', 'moveq #$3F,d7', 'and.b %s,d7' % r, 'cmp.b (a3,d4.w),d7',
		       'beq.s ' + done, *call('wrPPU_DataPal'), 'bra.s ' + done,
		       chr_ + ':', 'move.b %s,d7' % r, *call('ppuChrRamWrite'), done + ':')
		return True

	def addr_store(self, i, r):
		"""A store to $2006 of a pair (pairs_2006)."""
		if i.pc in self.addr_firsts:
			second, read = self.addr_firsts[i.pc]
			if read:		# (a word, its bit 15 set once written: rcRead16P)
				self.e('moveq #0,d7', 'move.b %s,d7' % r,
				       'move.w d7,-(sp)\t; (for the $2006 store at $%04X)' % second)
			elif second != i.pc + 3:
				self.e('move.b %s,-(sp)\t; (for the $2006 store at $%04X)' % (r, second))
			return True
		if i.pc not in self.addr_seconds:
			return False
		p, read = self.addr_seconds[i.pc]
		if read:
			one, back = self.tag('Aw', i.pc), self.tag('Ab', i.pc)
			self.e('move.w (sp)+,d7', 'bmi.w ' + one)
			self.stubs += [one + ':', '\t\tmove.b %s,d7' % r, '\t\tjsr wrPPU_Addr', '\t\tjmp ' + back]
		else:
			first = {'STA': 'd0', 'STX': 'd1', 'STY': 'd2'}[self.insns[p].m]
			self.e('move.b %s,d7' % first if p + 3 == i.pc else 'move.b (sp)+,d7')
		self.e('move.b %s,d6' % r, 'jsr wrPPU_AddrPair', *([back + ':'] if read else []))
		return True

	def kept_a5(self, routine):
		"""A call to a handler that may use a5: in a loop's fast copy,
		where a5 holds the pointer the loop reads through (copy_of), with
		a5 kept around it."""
		if not self.fast or self.fast.get('routine'):
			return ['jsr ' + routine]
		return ['move.l a5,-(sp)\t; (a5 kept)', 'jsr %s\t; (a5 kept)' % routine, 'movea.l (sp)+,a5\t; (a5 kept)']

	def mmc3_select(self, i):
		"""What MMC3's $8000 holds at a store to $8001 (its range): what
		was stored there just before, in code that falls through with no
		jump into it, no call and no other mapper write."""
		pc = i.pc
		for _ in range(8):
			if pc in self.targets:
				return None
			p = self.fall_from.get(pc)
			if p is None or p.mode == 'rel' or p.m in ('JSR', 'JMP', 'RTS', 'RTI', 'BRK'):
				return None
			if p.m in ('STA', 'STX', 'STY') and p.mode == 'abs' and p.arg >= 0x8000 and p.arg & 0xE001 == 0x8000:
				rng = self.ranges.get(p.pc)
				return rng[{'STA': 0, 'STX': 1, 'STY': 2}[p.m]] if rng else TOP
			if mapper_write(p):
				return None
			pc = p.pc
		return None

	def rmw_generic(self, i, ops, need, kind):
		"""Read-modify-write on an I/O or computed address."""
		m, a = i.mode, i.arg
		if m == 'abs':
			addr = ['move.w #$%04X,d6' % a]
		elif m in ('absx', 'zpx'):
			addr = ['move.w #$%04X,d6' % a, 'add.w d1,d6']
			if m == 'zpx':
				addr = ['move.w d1,d6', 'addi.b #$%02X,d6' % a]
		else:
			raise ValueError(m)
		self.e(*addr, 'move.w d6,-(sp)', 'jsr rcRead16')
		self.e(*ops)
		if need:
			(self.save_nzc if kind == 'shift' else self.save_nz)()
		self.e('move.w (sp)+,d6', 'jsr rcWrite16', *self.after_switch(i))

	def pad_lsr(self, i, l):
		"""LDA $4016 (or $4017) and then LSR A, which no jump goes to, nor a
		branch on its flags follows: emitted together (see emit)."""
		if i.mode != 'abs' or i.arg not in (0x4016, 0x4017) or l is None or l.m != 'LSR' or \
		   l.mode != 'acc' or l.pc in self.targets or self.fast and l.pc in self.fast.get('skip', ()):
			return False
		b = self.insns.get(l.pc + 1)
		return not (b is not None and b.mode == 'rel' and b.decided is None and FLAG_OF[b.m] & (N | Z | C))

	def live_at(self, pc):
		"""Flags live where pc begins, in the liveness in force (a routine
		copy's own while one is emitted); for a JSR or PHP, maybe more."""
		s = self.insns.get(pc)
		if s is None:
			return ALL
		if s.m == 'PHP':
			return self.live_in.get(pc, ALL)
		if s.m == 'JSR':
			return s.live_out
		return uses(s) | (s.live_out & ~DEFS.get(s.m, 0))

	def split_plan(self, i, m, b, defs):
		"""i's flags are read after the branch b that tests them: b tests
		them in the CCR, and each way out that reads them puts them in d3
		(split_fix). The way often decides them (after CMP, BEQ taken: N 0,
		Z 1, C 1) or doesn't read them. For loads, logic ops, INX..., PLA,
		compares and shifts of A; None where saving them before b, as
		otherwise, costs less."""
		if self.fast and i.pc in self.fast.get('skip', ()) or i.pc in self.delays or i.pc in self.delays2:
			return None
		kind = 'cmp' if m in ('CMP', 'CPX', 'CPY') else \
		       'shift' if m in ('ASL', 'LSR', 'ROL', 'ROR') and i.mode == 'acc' else \
		       'nz' if m in ('LDA', 'LDX', 'LDY', 'TAX', 'TAY', 'TXA', 'TYA', 'AND', 'ORA', 'EOR',
				     'INX', 'INY', 'DEX', 'DEY', 'PLA') else None
		if kind is None:
			return None
		f = FLAG_OF[b.m]
		taken = 1 if b.m in ('BMI', 'BEQ', 'BCS', 'BVS') else 0
		fix, cost = [], 0
		for pc, v in ((b.arg, taken), (b.pc + 2, 1 - taken)):
			known = {f: v}
			if f in (N, Z) and v:		# zero: not negative, and the other way
				known[Z if f == N else N] = 0
			if kind == 'cmp' and f == Z and v:
				known[C] = 1		# equal: no borrow
			if kind == 'cmp' and f == C and not v:
				known[Z] = 0		# below: not equal
			if m == 'LSR':
				known[N] = 0
			lines = self.split_fix(kind, defs & self.live_at(pc), known)
			fix.append(lines)
			cost += sum(FIX_CYCLES[l.split()[0]] for l in lines) + (12 if lines and pc == b.arg else 0)
		# otherwise: saved before b (CMP: by the slower ADDX form, with V
		# kept if it's live), and b reloads them
		now = 38 if kind != 'cmp' else 58 if i.live_out & V else 26
		return {'b': b, 'fix': fix} if cost < 2 * now else None

	@staticmethod
	def split_fix(kind, need, known):
		"""d3's flags in need, on a way out of a branch that tested them in
		the CCR: those the way decides as constants, the others from the
		CCR (after CMP, its C is the 6502's inverted)."""
		ccr = {N: 8, Z: 4, V: 2, C: 0x11}
		unk = need & ~sum(known)
		if not need:
			return []
		sel = sum(ccr[g] for g in (N, Z, V, C) if unk & g and not (g == C and kind == 'cmp'))
		borrow = kind == 'cmp' and unk & C	# carry clear: the 6502's C set
		lines = ['move sr,d5'] * bool(sel) + ['scc d4'] * bool(borrow) + \
			['andi.w #$%X,d5' % sel] * bool(sel) + ['andi.b #$11,d4'] * bool(borrow) + \
			['or.b d4,d5'] * bool(sel and borrow)
		lines.append('andi.b #$%02X,d3' % (~sum(ccr[g] for g in (N, Z, V, C) if need & g) & 0xFF))
		const = sum(ccr[g] for g, x in known.items() if need & g and x)
		if const:
			lines.append('ori.b #$%02X,d3' % const)
		if unk:
			lines.append('or.b %s,d3' % ('d5' if sel else 'd4'))
		return lines

	def emit_branch(self, i, direct_kind):
		cc = CC68[i.m]
		if i.decided:
			self.ccr_d3 = None
		if i.decided == 'taken':
			self.goto(i, i.arg)
			return
		if i.decided == 'not':
			return
		if direct_kind in ('cmp', 'sub') and i.m in ('BCC', 'BCS'):
			cc = INVERT[cc]			# (C: the borrow)
		elif direct_kind == 'bitv':
			cc = {'BVS': 'ne', 'BVC': 'eq'}[i.m]
		elif direct_kind is None and (self.ccr_d3 != (i.pc, len(self.out) - 1) or i.pc in self.targets):
			self.e('move d3,ccr')		# (not right after a branch that loaded it)
		sp, self.split_next = self.split_next, None
		if sp and sp['b'] is not i:
			sp = None
		if sp and sp['fix'][0]:			# the taken way puts the flags in d3 first
			self.e('b%s.w %s' % (INVERT[cc], self.tag('Sp', i.pc)))
			self.e(*sp['fix'][0])
			self.goto(i, i.arg)
			self.out.append('%s:' % self.tag('Sp', i.pc))
		else:
			self.branch(i, cc)
		if sp:
			self.e(*sp['fix'][1])
		self.ccr_d3 = (i.pc + 2, len(self.out)) if direct_kind is None else None
		if i.pc in self.idle_exits:		# a frame done (FPS counter)
			self.out += ['\t\tif FPS']
			self.e('addq.w #1,fpsIdle(a4)')
			self.out += ['\t\tendif']
		# entry from elsewhere: flags are in d3
		if direct_kind is not None:
			self.stubs += ['%s:' % self.lab(i.pc), '\t\tmove d3,ccr']
			save, self.out = self.out, []
			self.branch(i, CC68[i.m], 'T')
			self.stubs += self.out
			self.stubs += ['\t\tjmp %s' % self.lab(i.pc + 2)] if i.pc + 2 in self.insns else \
				      ['\t\tmove.w #$%04X,d4' % (i.pc + 2), '\t\tjmp rcDispatch']
			self.out = save

	# ---- loop versioning ----------------------------------------------------

	def entry_value(self, t, what):
		"""Constant value of a register ('A', 'X', 'Y') or zero page byte
		when straight-line code falls into t, or None."""
		seq, pc = [], t
		while len(seq) < 32:
			q = next((c for c in (self.insns.get(pc - n) for n in (1, 2, 3))
				  if c and c.pc + c.n == pc and pc in c.succ), None)
			if q is None:
				break
			seq.append(q)
			if q.pc in self.targets:
				break			# everything after it runs on every path
			pc = q.pc
		regs, mem = {}, {}
		for q in reversed(seq):
			m = q.m
			if m in ('LDA', 'LDX', 'LDY'):
				regs[m[2]] = q.arg if q.mode == 'imm' else None
			elif m in ('TAX', 'TAY', 'TXA', 'TYA'):
				regs[m[2]] = regs.get(m[1])
			elif m in ('INX', 'INY', 'DEX', 'DEY'):
				v = regs.get(m[2])
				regs[m[2]] = None if v is None else (v + (1 if m[0] == 'I' else -1)) & 0xFF
			elif m in ('STA', 'STX', 'STY') and q.mode == 'zp':
				mem[q.arg] = regs.get(m[2])
			else:
				if m in ('ADC', 'SBC', 'AND', 'ORA', 'EOR', 'PLA') or q.mode == 'acc':
					regs['A'] = None
				if m == 'TSX':
					regs['X'] = None
				if m in ('STA', 'STX', 'STY', 'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR'):
					if q.mode == 'zp':
						mem[q.arg] = None
					elif q.mode != 'acc':
						mem.clear()
		return regs.get(what) if isinstance(what, str) else mem.get(what)

	def trip_count(self, b, body):
		"""Most turns a counted loop (see counted_loops) makes when
		entered by falling into it, or None."""
		if b.pc not in self.counted or len(body) < 2:
			return None
		p = body[-2]
		ctr = p.arg if p.mode == 'zp' else p.m[2]
		v = self.entry_value(body[0].pc, ctr)
		if v is None:
			return None
		dec = p.m in ('DEC', 'DEX', 'DEY')
		if b.m == 'BNE':
			return (v or 256) if dec else 256 - v
		if b.m == 'BPL' and dec and v <= 0x7F:
			return v + 1
		return None

	def version_plan(self, b):
		"""An innermost loop reading through one (zp),Y pointer it never
		writes gets a second, fast copy: a guard at its entry loads the
		pointer into a5 once and checks the index registers' ranges, so
		zp,X needs no wrap-around and stores can't hit the pointer.
		Stores the guard couldn't clear check their address instead."""
		t = b.arg
		body, pc = [], t
		while pc <= b.pc and pc in self.insns:
			body.append(self.insns[pc])
			pc += self.insns[pc].n
		if pc != b.pc + 2:
			return None
		W = ('STA', 'STX', 'STY', 'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR')
		ptr = None
		for i in body:
			if i.m in ('JSR', 'JMP', 'RTS', 'RTI', 'BRK', 'PHA', 'PLA', 'PHP', 'PLP', 'TXS'):
				return None
			if i.mode == 'rel' and i is not b and i.arg <= i.pc:
				return None
			if i.mode == 'indy':
				if i.m == 'STA' or ptr not in (None, i.arg):
					return None
				ptr = i.arg
		if ptr is None:
			return None
		# the furthest index the (zp),Y reads reach, from the registers at
		# entry (emit_versioned): Y if the loop doesn't change it; Y plus
		# the turns if one INY (taken or not) is all that changes it and X
		# counts the turns (DEX, then BNE); Y if Y counts them (DEY, then
		# BNE); else Y plus 255
		ys = [i for i in body if i.m in ('INY', 'DEY', 'LDY', 'TAY')]
		xs = [i for i in body if i.m in ('INX', 'DEX', 'LDX', 'TAX', 'TSX')]
		cnt = body[-2] if b.pc in self.counted and b.m == 'BNE' and len(body) > 1 else None
		reach = None
		if not ys:
			reach = 'Y'
		elif cnt is not None and cnt.m == 'DEY' and ys == [cnt]:
			reach = 'Y counts'
		elif cnt is not None and cnt.m == 'DEX' and xs == [cnt] and len(ys) == 1 and ys[0].m == 'INY':
			reach = 'Y + X'
		ptrs = [ptr, (ptr + 1) & 0xFF]
		for i in body:
			if i.m in W and (i.mode == 'zp' or (i.mode == 'abs' and i.arg < 0x2000)) \
			   and i.arg & 0x7FF in ptrs:
				return None
		# index registers: step per turn, if one INX/DEX (INY/DEY) always runs
		cond = set()
		for i in body:
			if i.mode == 'rel' and i is not b and i.arg <= b.pc:
				cond |= {j.pc for j in body if i.pc < j.pc < i.arg}
		n = self.trip_count(b, body)
		ctr = body[-2] if b.pc in self.counted else None
		alias = ptrs + ([ctr.arg] if ctr and ctr.mode == 'zp' else [])
		step, spos = {}, {}
		for r, inc, dec, other in (('X', 'INX', 'DEX', ('LDX', 'TAX', 'TSX')),
					   ('Y', 'INY', 'DEY', ('LDY', 'TAY'))):
			ws = [i for i in body if i.m in (inc, dec) + other]
			if not ws:
				step[r], spos[r] = 0, 0x10000
			elif len(ws) == 1 and ws[0].m in (inc, dec) and ws[0].pc not in cond:
				step[r], spos[r] = (1 if ws[0].m == inc else -1), ws[0].pc
			else:
				step[r] = None
		acc = {'X': [], 'Y': []}		# (insn, base, is zp, is write)
		for i in body:
			if i.mode in ('zpx', 'zpy', 'absx', 'absy'):
				zp = i.mode in ('zpx', 'zpy')
				if zp or i.arg + 255 < 0x800:
					acc['X' if i.mode[-1] == 'x' else 'Y'].append((i, i.arg, zp, i.m in W))
		direct, check, guard = set(), set(), {}
		for r in 'XY':
			ok = []
			if n is not None and step[r] is not None and acc[r]:
				for r0 in range(256):
					good = True
					for i, base, zp, wr in acc[r]:
						lo = r0 + (step[r] if spos[r] < i.pc else 0)
						hi = lo + step[r] * (n - 1)
						lo, hi = min(lo, hi), max(lo, hi)
						if lo < 0 or hi > 255 or (zp and base + hi > 0xFF) or \
						   (wr and any((base + v) & (0xFF if zp else 0xFFFF) in alias
							       for v in range(lo, hi + 1))):
							good = False
							break
					if good:
						ok.append(r0)
			runs = []
			for v in ok:
				if runs and runs[-1][1] == v - 1:
					runs[-1][1] = v
				else:
					runs.append([v, v])
			if runs and len(runs) <= 2:
				guard[r] = runs
				direct |= {i.pc for i, base, zp, wr in acc[r] if zp}
			else:
				check |= {i.pc for i, base, zp, wr in acc[r] if wr}
		plan = {'t': t, 'b': b, 'body': body, 'pcs': {i.pc for i in body}, 'ptr': ptrs,
			'direct': direct, 'check': check, 'guard': guard, 'reach': reach}
		# $2007 stores and no other PPU access, X or Y counting the turns
		# down (one DEX or DEY all that changes it), and no way out but
		# the last turn (no branch to the BNE either: its copy for entries
		# with the flags in d3 leaves as it is): copies that keep the PPU
		# address in d4 (emit_versioned). (stores a turn, the counter)
		ppu = [i for i in body if i.mode in ('abs', 'absx', 'absy') and i.arg < 0x4000 and
		       i.arg + (255 if i.mode != 'abs' else 0) >= 0x2000]
		if ppu and all(i.mode == 'abs' and i.m in ('STA', 'STX', 'STY') and i.arg & 7 == 7 for i in ppu) and \
		   cnt is not None and cnt.m in ('DEX', 'DEY') and (xs if cnt.m == 'DEX' else ys) == [cnt] and \
		   not check and all(t <= i.arg < b.pc for i in body if i.mode == 'rel' and i is not b):
			plan['ppu'] = (len(ppu), 'd1' if cnt.m == 'DEX' else 'd2')
		# a short loop of known length is unrolled: the index registers
		# become displacements and the counter is set once at the end
		if n is None or n > 16 or check or \
		   any(i.mode == 'rel' and i.arg > b.pc for i in body) or \
		   any(acc[r] and r not in guard for r in 'XY') or \
		   any(step[r] is None and any(i.mode == 'indy' for i in body) for r in 'Y'):
			return plan
		skip = set()
		for i in body:
			if i.m in ('STX', 'STY', 'TXA', 'TYA', 'CPX', 'CPY', 'TXS') or i.mode == 'indx':
				return plan
			if i.m in ('INX', 'DEX', 'INY', 'DEY'):
				if i is not ctr and i.live_out & (N | Z):
					return plan
				skip.add(i.pc)
			if ctr.mode == 'zp' and i is not ctr and i.mode == 'zp' and i.arg == ctr.arg:
				return plan
		if ctr.mode == 'zp':
			skip.add(ctr.pc)
		plan['unroll'] = {'n': n, 'skip': skip, 'ctr': ctr, 'final': 0 if b.m == 'BNE' else 0xFF}
		return plan

	def pad_plan(self, b):
		"""A loop that reads the pads a bit a turn, 8 turns, as Super Mario
		Bros. 2 and 3 do. For each port, once a turn:

			LDA $4016	; or $4017, or $4016,X/Y with X/Y the port
			LSR A
			ROL m		; the button, into m (RAM)
			LSR A		; and maybe the next bit (a Famicom
			ROL m2		; expansion port pad's) into m2

		then DEX or DEY, BNE back, the count 8 where code falls in.
		emit_pads puts what the 8 turns do in its place."""
		t = b.arg
		if b.m != 'BNE' or b.pc not in self.counted:
			return None
		body, pc = [], t
		while pc <= b.pc and pc in self.insns:
			body.append(self.insns[pc])
			pc += self.insns[pc].n
		if pc != b.pc + 2 or len(body) < 5:
			return None
		cnt = body[-2]
		if cnt.m not in ('DEX', 'DEY') or self.trip_count(b, body) != 8:
			return None
		groups, k, ins = [], 0, body[:-2]
		while k < len(ins):
			i = ins[k]
			if i.m != 'LDA' or (i.mode, i.arg) not in (('abs', 0x4016), ('abs', 0x4017), ('absx', 0x4016),
								    ('absy', 0x4016)) or i.mode[-1:] == cnt.m[2].lower():
				return None
			k, dests = k + 1, []
			while k + 1 < len(ins) and ins[k].m == 'LSR' and ins[k].mode == 'acc' and ins[k + 1].m == 'ROL' and \
			      (ins[k + 1].mode == 'zp' or (ins[k + 1].mode == 'abs' and ins[k + 1].arg < 0x800)):
				dests.append(ins[k + 1].arg)
				k += 2
			if not 1 <= len(dests) <= 2:
				return None
			groups.append((i, dests))
		ports = [g.arg if g.mode == 'abs' else None for g, d in groups]
		dests = [m for g, d in groups for m in d]
		if len(set(dests)) != len(dests) or (len(groups) > 1 and (None in ports or len(set(ports)) != len(ports))):
			return None
		return {'t': t, 'b': b, 'pads': groups, 'cnt': cnt}

	def emit_pads(self, plan):
		"""What a pad_plan loop's 8 turns do: each port's next 8 bits (its
		latch, cpuInputData: the next in bit 0, as rcReadPad reads them,
		0 or 1) go to its button byte, the first in bit 7 (rcPadBits
		reverses them), and its latch moves on 8 bits; a second byte
		gets 0s. A and the count end 0 (Z set, N clear), and C is what
		the last ROL took out: bit 0 of its byte as it was. A port read
		through X or Y that isn't $4016 or $4017 runs the loop."""
		t, b = plan['t'], plan['b']
		self.out.append('\t\t\t\t\t\t; $%04X  pads, 8 turns' % t)
		for g, dests in plan['pads']:
			if g.mode != 'abs':
				self.e('cmpi.b #1,%s' % ('d1' if g.mode == 'absx' else 'd2'), 'bhi.w ' + self.lab(t))
		live = b.live_out
		if live & C:
			self.e('moveq #1,d5', 'and.b $%02X(a2),d5' % plan['pads'][-1][1][-1])
		for g, dests in plan['pads']:
			if g.mode == 'abs':
				self.e('lea cpuInputData+%d(a4),a5' % (2 * (g.arg - 0x4016)))
			else:
				self.e('move.w %s,d4' % ('d1' if g.mode == 'absx' else 'd2'), 'add.w d4,d4',
				       'lea cpuInputData(a4,d4.w),a5')
			self.e('moveq #0,d7', 'move.b 1(a5),d7', 'move.b (a5),1(a5)', 'clr.b (a5)',
			       'lea (rcPadBits).l,a5', 'move.b (a5,d7.w),$%02X(a2)' % dests[0])
			if len(dests) > 1:
				self.e('clr.b $%02X(a2)' % dests[1])
		self.e('moveq #0,d0', 'moveq #0,%s' % ('d1' if plan['cnt'].m == 'DEX' else 'd2'))
		if live & (N | Z | C):
			self.e('andi.b #$%02X,d3' % (0xFF & ~(0x0C if live & (N | Z) else 0) & ~(0x11 if live & C else 0)))
			if live & (N | Z):
				self.e('ori.b #$04,d3')
			if live & C:
				self.e('or.b d5,d3', 'lsl.b #4,d5', 'or.b d5,d3')
		self.xc = False
		f = b.pc + 2
		self.e(*(['jmp %s' % self.lab(f)] if f in self.insns else ['move.w #$%04X,d4' % f, 'jmp rcDispatch']))

	def fill_plan(self, b):
		"""STA base,X / DEX / BPL (or the INX, Y and BNE forms, or a run of
		DEX for a stride of 2, 4...) with a known start value fills
		memory: stores replace the loop where code falls into it."""
		t = b.arg
		s = self.insns.get(t)
		if not s or s.m != 'STA' or s.mode not in ('zpx', 'absx', 'absy') or b.pc not in self.counted:
			return None
		steps, pc = [], s.pc + s.n
		while pc < b.pc and pc in self.insns and self.insns[pc].m in ('INX', 'DEX', 'INY', 'DEY'):
			steps.append(self.insns[pc])
			pc += 1
		d = steps[-1] if steps else None
		if pc != b.pc or not d or any(x.m != d.m for x in steps) or s.mode[-1] != d.m[2].lower() \
		   or b.m not in ('BNE', 'BPL'):
			return None
		y = self.entry_value(t, d.m[2])
		if y is None:
			return None
		ys = []
		while True:
			ys.append(y)
			y = (y + len(steps) * (1 if d.m[0] == 'I' else -1)) & 0xFF
			if (y == 0 if b.m == 'BNE' else y & 0x80) or len(ys) > 256:
				break
		addrs = sorted(s.arg + v for v in ys)
		if len(ys) > 256 or addrs[-1] >= (0x100 if s.mode == 'zpx' else 0x800):
			return None
		return {'t': t, 'b': b, 'addrs': addrs, 'reg': 'd1' if d.m[2] == 'X' else 'd2', 'end': y}

	def emit_fill(self, plan):
		runs = []
		for a in plan['addrs']:
			if runs and runs[-1][1] + 1 == a:
				runs[-1][1] = a
			else:
				runs.append([a, a])
		step = runs[1][0] - runs[0][0] if len(runs) > 1 else 1
		self.out.append('\t\t\t\t\t\t; $%04X  fill $%04X-$%04X%s' % (plan['t'], runs[0][0], runs[-1][1],
								     ' every %d' % step if step > 1 else ''))
		if any(hi - lo >= 1 for lo, hi in runs):	# A in all four bytes of d5
			self.e('move.b d0,d5', 'lsl.w #8,d5', 'move.b d0,d5', 'move.w d5,d6', 'swap d5', 'move.w d6,d5')
		for lo, hi in runs:
			a = lo
			while a <= hi:
				if a & 1 or a == hi:
					self.e('move.b d0,$%04X(a2)' % a); a += 1
				elif a + 3 <= hi:
					self.e('move.l d5,$%04X(a2)' % a); a += 4
				else:
					self.e('move.w d5,$%04X(a2)' % a); a += 2
		self.e('move.b #$%02X,%s' % (plan['end'], plan['reg']))
		if plan['b'].live_out & (N | Z):
			self.e('tst.b %s' % plan['reg'])
			self.save_nz()
		f = plan['b'].pc + 2
		self.e(*(['jmp %s' % self.lab(f)] if f in self.insns else ['move.w #$%04X,d4' % f, 'jmp rcDispatch']))

	def copy_of(self, plan, turns, run=None):
		"""Code for a loop's fast copy, or None if it would need a5 or a
		call. turns: None for a loop, else (turns, off) to unroll. run:
		'nt' or 'pal' for a copy whose $2007 stores all go to the
		nametables or all to the palette (version_plan's ppu), with
		their address in d4 and step in d6, and d4 back in ppuAddrBase
		where it leaves: None if anything else in it uses those."""
		t, b = plan['t'], plan['b']
		outer = self.fast
		base = outer['prefix'] if outer else ''
		save = self.out, self.stubs, self.xc, self.c_skipped
		self.out, self.stubs, self.xc, self.c_skipped = [], [], False, 0
		self.ccr_d3 = None
		f = b.pc + 2
		exit = ['jmp %s' % self.lab(f)] if f in self.insns else ['move.w #$%04X,d4' % f, 'jmp rcDispatch']
		try:
			off = {'d1': 0, 'd2': 0}
			for k in range(turns['n'] if turns else 1):
				self.fast = dict(plan, prefix=base + ({'nt': 'N', 'pal': 'Q'}[run] if run else 'U%d' % k if k else 'F'),
						 outer=outer and base, rf=outer.get('f') if outer and outer.get('routine') else None,
						 ppu_run=run)
				if turns:
					self.fast.update(off=off, skip=turns['skip'])
				dk = None
				for i in plan['body']:
					if turns and i is b:
						self.out.append('%s:' % self.lab(i.pc))
						continue
					if not (i.mode == 'rel' and dk is not None):
						self.out.append('%s:\t\t\t\t\t; $%04X  %s' % (self.lab(i.pc), i.pc, i.text()))
					if i.mode == 'rel':
						self.emit_branch(i, dk)
						dk = None
					else:
						self.emit(i, self.insns.get(i.pc + i.n))
						dk = self.direct_next
						if DEFS.get(i.m, 0) & C and i.m not in ('ASL', 'LSR', 'ROL', 'ROR', 'ADC'):
							self.xc = False
			if turns:			# registers and counter as after the last turn
				self.fast = None
				for r, o in sorted(off.items()):
					if o:
						self.e(('%s.b #%d,%s' % ('addq' if o > 0 else 'subq', abs(o), r)) if abs(o) <= 8 else
						       'addi.b #$%02X,%s' % (o & 0xFF, r))
				ctr = turns['ctr']
				loc = '$%02X(a2)' % ctr.arg if ctr.mode == 'zp' else None
				if loc:
					self.e('move.b #$%02X,%s' % (turns['final'], loc))
				if b.live_out & (N | Z):
					self.e('tst.b %s' % (loc or ('d1' if ctr.m[2] == 'X' else 'd2')))
					self.save_nz()
			if run:			# (nothing else uses d4 or d6, or calls what may)
				if any((re.search(r'\bd[46]\b', l) or 'jsr' in l) and '(ppu run)' not in l
				       for l in self.out + self.stubs):
					raise Unroll
				self.e('move.w d4,ppuAddrBase(a4)\t; (ppu run)')
			self.e(*exit)
			fast = self.out + self.stubs
		except Unroll:
			fast = None
		finally:
			self.fast = outer
			self.out, self.stubs, self.xc, self.c_skipped = save
			self.ccr_d3 = None
		if fast and any((',a5' in l or ('jsr' in l and 'rcNmi' not in l)) and '(a5 kept)' not in l for l in fast):
			fast = None
		return fast

	def emit_versioned(self, plan):
		"""Guard and fast copy of a loop, placed where code falls into
		it; the normal copy follows at L_xxxx. Returns False (emitting
		nothing) if the fast copy would need a5 or a call."""
		t, b = plan['t'], plan['b']
		fast = None
		if 'unroll' in plan:
			fast = self.copy_of(plan, plan['unroll'])
		if fast is None:
			fast = self.copy_of(plan, None)
		if fast is None:
			return False
		slow = self.lab(t)
		v = self.fast['prefix'] if self.fast else ''
		g = [v + 'V_%04X:' % t, '\t\tmove.b $%02X(a2),-(sp)' % plan['ptr'][1], '\t\tmove.w (sp)+,d6',
		     '\t\tmove.b $%02X(a2),d6' % plan['ptr'][0]]
		for r, runs in plan['guard'].items():
			reg = 'd1' if r == 'X' else 'd2'
			def within(lo, hi):
				return (['\t\tcmpi.b #$%02X,%s' % (lo, reg), '\t\tbcs.w %s' % slow] if lo > 0 else []) + \
				       (['\t\tcmpi.b #$%02X,%s' % (hi, reg), '\t\tbhi.w %s' % slow] if hi < 255 else [])
			if len(runs) == 1:
				g += within(*runs[0])
			else:
				hi_lab, ok_lab = v + 'VH%s_%04X' % (r, t), v + 'VO%s_%04X' % (r, t)
				g += ['\t\tcmpi.b #$%02X,%s' % (runs[0][1], reg), '\t\tbhi.s %s' % hi_lab]
				g += within(runs[0][0], 255) + ['\t\tbra.s %s' % ok_lab, hi_lab + ':']
				g += within(runs[1][0], runs[1][1]) + [ok_lab + ':']
		# d7: the last byte the reads reach (version_plan's reach), in the
		# same memory as the first (d6)
		y = '%sVY_%04X' % (v, t)
		g += {'Y': ['\t\tmoveq #0,d7', '\t\tmove.b d2,d7'],
		      'Y counts': ['\t\tmoveq #0,d7', '\t\tmove.b d2,d7', '\t\tbne.s ' + y,
				   '\t\tmove.w #$FF,d7', y + ':'],		# (Y = 0: 256 turns)
		      'Y + X': ['\t\tmoveq #0,d7', '\t\tmove.b d1,d7', '\t\tbeq.w ' + slow,	# (X = 0: 256 turns)
				'\t\tmoveq #0,d5', '\t\tmove.b d2,d5', '\t\tadd.w d5,d7',
				'\t\tcmpi.w #$100,d7', '\t\tbcc.w ' + slow],		# (Y would wrap)
		      None: ['\t\tmove.w #$FF,d7']}[plan['reach']]
		g += ['\t\tadd.w d6,d7', '\t\tbcs.w ' + slow]	# (not past $FFFF)
		g += ['\t\tcmpi.w #$800,d7', '\t\tbcs.s %sVR_%04X' % (v, t)]	# RAM
		if self.prg.banked:		# PRG RAM
			g += ['\t\tcmpi.w #$6000,d6', '\t\tbcs.w %s' % slow,
			      '\t\tcmpi.w #$8000,d7', '\t\tbcs.s %sVW_%04X' % (v, t)]
		g += ['\t\tcmpi.w #$8000,d6', '\t\tbcs.w %s' % slow]		# PRG
		if self.prg.mode1:		# R7's frame (a0) but at $C000-$DFFF: R6's
			ok = '%sVP_%04X' % (v, t)
			g += ['\t\tcmpi.w #$C000,d7', '\t\tbcs.s ' + ok, '\t\tcmpi.w #$E000,d6', '\t\tbcc.s ' + ok,
			      '\t\tcmpi.w #$C000,d6', '\t\tbcs.w %s' % slow, '\t\tcmpi.w #$E000,d7', '\t\tbcc.w %s' % slow,
			      '\t\tmovea.l rcFrameC(a4),a5', '\t\tadda.w d6,a5', '\t\tbra.s %sF_%04X' % (v, t), ok + ':']
		g += ['\t\tlea (a0,d6.w),a5', '\t\tbra.s %sF_%04X' % (v, t)]
		if self.prg.banked:
			g += ['%sVW_%04X:' % (v, t), '\t\tlea (RAM_Fami_WRAM-$6000).l,a5', '\t\tadda.w d6,a5',
			      '\t\tbra.s %sF_%04X' % (v, t)]
		g += ['%sVR_%04X:' % (v, t), '\t\tlea (a2,d6.w),a5']
		nt = pal = None
		if 'ppu' in plan and 'unroll' not in plan:
			nt = self.copy_of(plan, None, 'nt')
			pal = nt and self.copy_of(plan, None, 'pal')
		if pal:
			# the copies that keep the $2007 stores' address in d4 and their
			# step in d6, if every store's (from ppuAddrBase to it plus the
			# turns, X or Y, times the stores a turn, times the step) is in
			# the nametables ($2000-$3EFF) or every one in the palette
			# ($3F00-$3FFF)
			k, reg = plan['ppu']
			F, G = '%sF_%04X' % (v, t), '%sG_%04X' % (v, t)
			g = [l.replace('bra.s ' + F, 'bra.s ' + G) for l in g]
			g += [G + ':', '\t\tmove.w ppuAddrBase(a4),d4', '\t\tcmpi.w #$2000,d4', '\t\tbcs.w ' + F,
			      '\t\tmoveq #0,d7', '\t\tmove.b %s,d7' % reg, '\t\tbeq.w ' + F] + \
			     (['\t\tmulu #%d,d7' % k] if k > 1 else []) + \
			     ['\t\tmove.w ppuAddrIncr(a4),d6', '\t\tmulu d6,d7', '\t\tcmpi.l #$1F00,d7', '\t\tbhi.w ' + F,
			      '\t\tadd.w d4,d7', '\t\tbcs.w ' + F, '\t\tcmpi.w #$3F00,d4', '\t\tbcc.s %sGq_%04X' % (v, t),
			      '\t\tcmpi.w #$3F00,d7', '\t\tbls.w %sN_%04X' % (v, t), '\t\tbra.w ' + F,
			      '%sGq_%04X:' % (v, t), '\t\tcmpi.w #$4000,d7', '\t\tbls.w %sQ_%04X' % (v, t)]
			fast += nt + pal
		self.out += g + fast
		return True

	# ---- routines called with the 68000's jsr -------------------------------

	def dyn_target(self, i):
		"""MMC3 PRG mode 1: is i a JSR into the other slot (from the fixed
		code: into either), to a routine some bank there may have a copy
		of (mode1: dyn)?"""
		return self.prg.mode1 and i.m == 'JSR' and not i.table and i.arg in self.dyn and \
			self.dyn[i.arg][0] != self.prg.slot

	def emit_dyn_call(self, i):
		"""A dyn_target JSR: which bank is in that slot isn't known here, so
		the copy of the routine in the one there now, from its call table
		(rcCurCallA, rcCurCallC: emu/recomp.asm, rcPrgSlot), called with
		the 68000's jsr, the 6502 return address in d4: a light copy's
		entry is the copy, a heavy one's pushes it first (mode1). Where
		that bank has none, the return address pushed, rcDispatch, as
		before. A bank's code checks after the call that its own bank is
		still there (the routine may switch it)."""
		s, k = self.dyn[i.arg]
		ret = i.pc + 2
		slow = self.tag('Ds', i.pc)
		self.e('move.w #$%04X,d4' % ret, 'movea.l rcCurCall%s(a4),a5' % s, 'move.l %d(a5),d5' % (4 * k),
		       'beq.w ' + slow, 'movea.l d5,a5', 'jsr (a5)')
		self.stubs += [slow + ':', '\t\tswap d3', '\t\tmove.b #$%02X,(a2,d3.w)' % (ret >> 8), '\t\tsubq.b #1,d3',
			       '\t\tmove.b #$%02X,(a2,d3.w)' % (ret & 0xFF), '\t\tsubq.b #1,d3', '\t\tswap d3'] + \
			      ['\t\t' + l if not l.endswith(':') else l for l in self.slot_jump(i.arg)]
		if self.prg.unit != 'F':
			back = self.tag('Dr', i.pc)
			self.e(*self.own_bank(back), 'move.w #$%04X,d4' % ((i.pc + 3) & 0xFFFF), 'jmp rcDispatch',
			       back + ':')

	def dyn_worth(self, f):
		"""Is a copy of routine f for calls from the other slot (dyn_copies)
		worth its room? Small (DYN_COPY_MAX), and likely this bank's own
		routine, not bytes that only look like one (the call may be for
		another bank in this slot): its code goes there too (own_refs), and
		its code is clean: none of it goes where nothing was decoded."""
		body = self.callable[f][0]
		return len(body) <= DYN_COPY_MAX and f in self.refs and \
			all(t is None or t in self.insns for pc in body for t in self.insns[pc].succ)

	def routine_body(self, f, memo):
		"""(instructions, heavy) of a routine that can be called with the
		68000's jsr, or None. Its copy returns with rts, so every path
		must reach RTS with the stack as it was, and the routines it
		calls must be like it.
		A light routine stays in translated code: its call doesn't push
		the return address. (Its own pushes and pulls then go where the
		return address would be, as nothing can look at the stack
		meanwhile; an NMI it takes comes back to its copy, nest_ok.) A
		heavy one may leave its copy through rcDispatch (a bank switch, a
		computed jump, a routine with no copy, or an NMI where they can't
		come back): its call pushes the 6502 return address like JSR
		does, and rcDispatch drops the 68000 return addresses and the
		normal code takes over."""
		if f in memo:
			return memo[f]
		memo[f] = None			# recursion: not callable
		depth, work, heavy, sw = {}, [(f, 0)], False, False
		while work:
			pc, d = work.pop()
			i = self.insns[pc]
			if pc in depth:
				if depth[pc] != d:
					return None
				continue
			if len(depth) >= 500 or i.m in ('RTI', 'BRK', 'TSX', 'TXS'):
				return None
			depth[pc] = d
			if self.switches(i):
				heavy = True		# may go on in another bank, through rcDispatch
			if i.m == 'CLI' and self.prg.irq:
				heavy = True		# MMC3's IRQ, through rcDispatch (irq_check)
			sw |= self.prg_switch(i)	# (the fixed bank's: its callers in banks check)
			if i.m in ('PHA', 'PHP', 'PLA', 'PLP'):
				d += 1 if i.m[1] == 'H' else -1
				if d < 0:
					# PLA PLA RTS with nothing else pushed: a check that returns
					# from its caller too. Its copy is heavy, and so is its
					# caller's, which calls it with nothing pushed: it drops the
					# 68000 return address into that, and returns as that would
					# (the RTS may be another way's too: the copy returns after
					# the second PLA)
					b, c = self.insns.get(pc + 1), self.insns.get(pc + 2)
					if not (d == -1 and i.m == 'PLA' and b is not None and b.m == 'PLA' and
						c is not None and c.m == 'RTS') or depth.get(pc + 1, -1) != -1:
						return None
					depth[pc + 1] = -1
					self.double_rts.setdefault(f, set()).add(pc + 1)
					heavy = True
					continue
			if i.m == 'RTS':
				if d:
					return None
				continue
			if self.tail_call(i, d):
				h, s = self.ext_routines[i.arg][:2]
				heavy |= h			# (its copy may leave through rcDispatch: so may this one)
				sw |= s
				self.tails.setdefault(f, set()).add(pc)
				continue
			if i.m == 'JSR' and i.table:
				heavy = True			# past the table: the engine, through rcDispatch
				if i.arg in self.engines and self.engine_table(i) and all(t in self.insns for t in i.table):
					# with nothing pushed, the entries' own copies if they all
					# have one: tail calls (emit_engine_call), else their code here
					subs = [self.routine_body(t, memo) for t in i.table] if d == 0 else None
					if subs and all(subs) and not any(t in self.double_rts for t in i.table):
						sw |= any(x[2] for x in subs)
						self.engine_tails.setdefault(f, set()).add(pc)
					else:
						work += [(t, d) for t in i.table]
				continue
			if i.m == 'JSR':
				sub = self.routine_body(i.arg, memo) if i.arg in self.insns else None
				if sub and i.arg in self.double_rts:
					if d:
						return None
					heavy = True		# (it may return from this one: double_rts)
				if sub:
					heavy |= sub[1]
					sw |= sub[2]
				elif i.arg in self.ext_routines:
					h, s = self.ext_routines[i.arg][:2]
					heavy |= h or s		# a switch goes on through rcDispatch
					sw |= s
				elif i.arg < 0x800:
					heavy = True	# a jump table in RAM, through rcDispatch
				elif self.dyn_target(i):
					heavy = sw = True	# the other slot's bank's copy, or rcDispatch (emit_dyn_call)
				else:
					heavy = True	# a routine with no copy: the normal code, through rcDispatch
					continue
				work.append((pc + 3, d))
				continue
			for t in i.succ:
				if t is None or t not in self.insns:
					heavy = True	# through rcDispatch
				else:
					if self.back(i, t) and not (i.mode == 'rel' and i.decided is None and pc in self.counted) \
					   and not NEST[0]:
						heavy = True	# NMI check (with NEST, it comes back: rcNmiIn)
					work.append((t, d))
		memo[f] = (set(depth), heavy, sw)
		return memo[f]

	def switch_slots(self, f, memo=None):
		"""The slots a callable routine (with those it calls) may switch
		the bank of: 'A' ($A000, R7) and 'C' ($C000, R6) in MMC3 PRG mode
		1, both where that isn't known (or another mapper's bank)."""
		memo = {} if memo is None else memo
		if f in memo:
			return memo[f]
		memo[f] = {'A', 'C'}			# (recursion: not known)
		out = set()
		for pc in self.callable[f][0]:
			i = self.insns[pc]
			if self.prg_switch(i):
				regs = self.mmc3_regs(i) if self.prg.mode1 else None
				out |= {'A', 'C'} if regs is None else {s for s, r in (('A', 7), ('C', 6)) if r in regs}
			if i.m == 'JSR':
				out |= self.switch_slots(i.arg, memo) if not i.table and i.arg in self.callable else {'A', 'C'}
		memo[f] = out
		return out

	def tail_call(self, i, d):
		"""Is i (at stack depth d in a routine) a JMP to a routine of the
		fixed bank's that has a copy (ext_routines), which can't switch
		this code's bank out: so the same as calling the copy and
		returning? MMC3 PRG mode 1 only (another mapper's bank switches
		where the copy doesn't know)."""
		if not (self.prg.mode1 and i.m == 'JMP' and i.mode == 'abs' and d == 0 and i.arg not in self.insns):
			return False
		r = self.ext_routines.get(i.arg)
		return r is not None and self.prg.slot not in r[3]

	def copy_label(self, f):
		"""The label of the copy of the fixed bank's routine f that the
		banks' code calls: a copy of its own (X) where they need more
		flags kept than this unit's calls do."""
		mine, calls = 0, False
		for i in self.insns.values():
			if i.m == 'JSR' and i.arg == f and i.pc + 3 in self.insns:
				mine |= self.live_in[i.pc + 3]
				calls = True
		return ('X%04X_%04X' if calls and self.ext_ret.get(f, ALL) & ~mine else 'R%04X_%04X') % (f, f)

	def emit_routine(self, f, prefix='R'):
		pcs = sorted(self.callable[f][0])
		self.fast = {'pcs': set(pcs), 'prefix': '%s%04X' % (prefix, f), 'routine': True, 'heavy': self.callable[f][1],
			     'f': f}
		self.xc, self.c_skipped = False, 0
		self.out.append('')
		# its own liveness: it returns only to its callers (the banks', for X)
		ctx = self.ext_ret.get(f, ALL) if prefix == 'X' or self.copy_label(f)[0] == 'R' and f in self.copies_for else 0
		for i in self.insns.values():
			if i.m == 'JSR' and i.arg == f and i.pc + 3 in self.insns and prefix == 'R':
				ctx |= self.live_in[i.pc + 3]
		if f in self.engine_entries or f in self.double_rts:	# (it returns to the callers of copies that
			ctx = ALL						# tail-call it, or two levels up)
		saved = {pc: self.insns[pc].live_out for pc in pcs}
		for pc, out in copy_liveness(self.insns, set(pcs), ctx, self.live_in, self.sums).items():
			self.insns[pc].live_out = out
		try:
			self.emit_routine_body(pcs)
		finally:
			for pc, out in saved.items():
				self.insns[pc].live_out = out

	def emit_inline(self, i):
		"""A JSR to a small light routine: its code in place, with its own
		liveness (it returns here only). Its own calls are put in place or
		called as usual."""
		f = i.arg
		pcs = sorted(self.callable[f][0])
		outer, end = self.fast, self.tag('Ie', i.pc)
		saved = {pc: self.insns[pc].live_out for pc in pcs}
		for pc, out in copy_liveness(self.insns, set(pcs), self.live_in[i.pc + 3], self.live_in, self.sums).items():
			self.insns[pc].live_out = out
		last = max(pcs, key=lambda pc: pc + self.insns[pc].n)
		self.fast = {'pcs': set(pcs), 'prefix': '%sI%04X' % (outer['prefix'] if outer else '', i.pc), 'routine': True,
			     'heavy': False, 'inline': end, 'last': last if self.insns[last].m == 'RTS' else None, 'f': f}
		if pcs[0] != f:				# code before its start: go in at its start
			self.e('bra.w %s' % self.lab(f))
		try:
			self.emit_routine_body(pcs, False)
		finally:
			for pc, out in saved.items():
				self.insns[pc].live_out = out
			self.fast = outer
		self.out.append(end + ':')
		self.xc = False

	def emit_routine_body(self, pcs, whole=True):
		dk = None
		for k, pc in enumerate(pcs):
			i = self.insns[pc]
			if pc in self.targets:
				self.xc = False
			if pc in self.plans and k and dk is None:
				self.loop_entry(pcs[k - 1], self.plans[pc])
			if not (i.mode == 'rel' and dk is not None):
				self.out.append('%s:\t\t\t\t; $%04X  %s' % (self.lab(pc), pc, i.text()))
			if i.mode == 'rel':
				self.emit_branch(i, dk)
				dk = None
			else:			# (the next instruction if it comes next, as in run)
				self.emit(i, self.insns.get(pc + i.n) if pcs[k + 1:k + 2] == [pc + i.n] else None)
				dk = self.direct_next
				if DEFS.get(i.m, 0) & C and i.m not in ('ASL', 'LSR', 'ROL', 'ROR', 'ADC'):
					self.xc = False
			self.fall_through(i, pcs, k)
		if whole:
			self.out += self.stubs
			self.stubs = []
			self.fast = None

	def double_exit(self, i):
		"""In a routine's copy, is i the second PLA of a PLA PLA RTS that
		returns from its caller too (routine_body)?"""
		return bool(self.fast and self.fast.get('routine') and i.pc in self.double_rts.get(self.fast.get('f'), ()))

	def fall_through(self, i, pcs, k):
		"""Jump to the next instruction if it isn't next in the output."""
		if self.double_exit(i):
			return
		if i.mode == 'rel':
			if i.decided == 'taken':
				return
		elif i.m in ('JMP', 'RTS', 'RTI', 'BRK') or (i.m == 'JSR' and i.arg not in self.callable and
							     (i.table or i.arg not in self.ext_routines)):
			return
		f = i.pc + i.n
		if k + 1 >= len(pcs) or pcs[k + 1] != f:
			self.e(*(['jmp %s' % self.lab(f)] if f in self.insns else ['jmp %s' % lab(f)] if f in self.ext else
				 ['move.w #$%04X,d4' % f, 'jmp rcDispatch']))

	def loop_entry(self, prev, plan):
		"""Fill, pad reads or fast copy where the previous instruction falls
		into a loop."""
		p = self.insns[prev]
		pc = plan['t']
		if p.pc + p.n == pc and pc in p.succ:
			if 'addrs' in plan:
				self.emit_fill(plan)
				self.versioned.append(pc)
			elif 'pads' in plan:
				self.emit_pads(plan)
				self.versioned.append(pc)
			elif self.emit_versioned(plan):
				self.versioned.append(pc)

	def run(self, vectors):
		pcs = sorted(self.insns)
		# delay loops, DEX/DEY then BNE back to it: rcDelay instead
		self.delays, self.delays2, self.delay_skip = set(), {}, set()
		for i in self.insns.values():
			b = self.insns.get(i.pc + 1)
			if i.m in ('DEX', 'DEY') and b is not None and b.m == 'BNE' and b.arg == i.pc and b.decided is None:
				self.delays.add(i.pc)
				b.decided, b.succ = 'not', [b.pc + 2]
		# and two nested, the outer branch back to the LDY (A) or to the
		# inner loop (B): LDY #n, [DEY, BNE], DEX, BNE
		ext = {}
		for j in self.insns.values():
			for t in j.succ:
				if t is not None and t != j.pc + j.n:
					ext.setdefault(t, set()).add(j.pc)
		for i in self.insns.values():
			if i.m not in ('LDX', 'LDY') or i.mode != 'imm' or i.pc + 2 not in self.delays:
				continue
			d, b = self.insns.get(i.pc + 5), self.insns.get(i.pc + 6)
			if not (d is not None and d.m in ('DEX', 'DEY') and d.m[2] != i.m[2] and self.insns[i.pc + 2].m[2] == i.m[2]
				and b is not None and b.m == 'BNE' and b.decided is None and b.arg in (i.pc, i.pc + 2)):
				continue
			inside = {i.pc + 2, i.pc + 3, i.pc + 5, i.pc + 6}
			if any(ext.get(t, set()) - {i.pc + 3, i.pc + 6} for t in inside):
				continue	# entered partway from elsewhere
			if b.arg == i.pc:	# A: each outer turn LDY (2), the inner loop, DEX and BNE (5)
				self.delays2[i.pc] = ('A', i.arg or 256)
			else:			# B: later inner passes run 256 turns
				self.delays2[i.pc] = ('B', i.arg or 256)
			self.delay_skip |= {i.pc + 2, i.pc + 5}
			b.decided, b.succ = 'not', [b.pc + 2]
		self.out.append('rcCode:')
		self.prologued = set()
		self.xc = False
		self.c_skipped = 0
		self.targets = set(vectors) | set(self.entries)
		for i in self.insns.values():
			self.targets |= {t for t in i.succ if t is not None and t != i.pc + i.n}
			if i.m == 'JSR':
				self.targets.add(i.pc + 3)
		self.paired = self.php_pairs()
		if self.prg.irq:		# where MMC3's IRQ, taken after a CLI, comes back to (irq_check)
			self.targets |= {i.pc + 1 for i in self.insns.values() if i.m == 'CLI'}
		self.addr_firsts, self.addr_seconds, self.addr_pending = self.pairs_2006()
		self.counted = self.counted_loops()
		self.loopy = self.loop_edges()
		self.pha_paired = self.pha_pairs()
		self.fall_from = {i.pc + i.n: i for i in self.insns.values() if i.pc + i.n in i.succ}
		self.idle_exits, self.idle_jmps = self.idle_loops()
		self.idle_heads = {self.insns[b].arg for b in self.idle_exits}
		memo = {}
		self.callable = {}
		for i in self.insns.values():
			if i.m == 'JSR' and i.arg in self.insns and self.routine_body(i.arg, memo):
				self.callable[i.arg] = memo[i.arg]
		for f in self.copies_for:
			if f in self.insns and self.routine_body(f, memo):
				self.callable[f] = memo[f]
		work = list(self.callable)		# and the engine entries copies tail-call
		while work:
			for pc in self.engine_tails.get(work.pop(), ()):
				for t in self.insns[pc].table:
					if t not in self.callable:
						self.callable[t] = memo[t]
						work.append(t)
					self.engine_entries.add(t)
		self.refs = own_refs(self.insns)
		self.called = {f for f in self.copies_for if f in self.callable and
			       (f not in self.dyn_copies or self.dyn_worth(f))}
		self.returns = self.return_points()
		heads = set()
		for i in self.insns.values():
			if i.m == 'JMP' and i.mode == 'abs' and self.back(i, i.arg): heads.add(i.arg)
			if i.mode == 'rel' and i.decided != 'not' and self.back(i, i.arg) and i.pc not in self.counted:
				heads.add(i.arg)
		plans = {}
		for i in self.insns.values():
			if i.mode == 'rel' and i.decided is None and i.arg < i.pc and i.arg not in plans:
				plan = self.fill_plan(i) or self.version_plan(i) or self.pad_plan(i)
				if plan:
					plans[i.arg] = plan
		self.versioned = []
		self.plans = plans
		self.inline = {f for f, (body, heavy, sw) in self.callable.items() if not heavy and len(body) <= 24 and
			       not any(pc in plans for pc in body)}
		direct_kind = None
		for k, pc in enumerate(pcs):
			i = self.insns[pc]
			# the next instruction, if it comes next here (not when one
			# starts inside this one: code that jumps there decodes its
			# bytes another way)
			nxt = self.insns.get(pc + i.n) if i.mode != 'rel' and pcs[k + 1:k + 2] == [pc + i.n] else None
			if pc in self.targets:
				self.xc = False
			if pc in plans and k and direct_kind is None:
				self.loop_entry(pcs[k - 1], plans[pc])
			if not (i.mode == 'rel' and direct_kind is not None):
				if pc in heads:		# loop head: NMI check for the back edges
					self.prologued.add(pc)
					flag, call = self.nmi_check(pc)
					self.out += ['C_%04X:' % pc, '\t\t' + flag, '\t\tbeq.s %s' % lab(pc),
						     '\t\tmove.w #$%04X,d4' % pc, '\t\t' + call]
				self.out.append('%s:\t\t\t\t\t; $%04X  %s' % (lab(pc), pc, i.text()))
			else:
				self.out.append('\t\t\t\t\t\t; $%04X  %s' % (pc, i.text()))
			if i.mode == 'rel':
				self.emit_branch(i, direct_kind)
				direct_kind = None
			else:
				self.emit(i, nxt)
				direct_kind = self.direct_next
				if DEFS.get(i.m, 0) & C and i.m not in ('ASL', 'LSR', 'ROL', 'ROR', 'ADC'):
					self.xc = False		# carry changed, X didn't
			# fall through into code that isn't next in address order
			self.fall_through(i, pcs, k)
			# out-of-line entries go at the next point code doesn't fall
			# through, so branches to them stay short
			if self.stubs and self.out[-1].strip().split()[0] in ('jmp', 'bra'):
				self.out += self.stubs
				self.stubs = []
		self.out += self.stubs
		self.stubs = []
		done = set()
		while self.called - done:
			f = min(self.called - done)
			done.add(f)
			self.emit_routine(f)
			if f in self.copies_for and self.copy_label(f)[0] == 'X':
				self.emit_routine(f, 'X')
		# dispatch table: PRG offset -> code, and before it, rcSafe's
		# address, less its first byte's index (see below)
		size = len(self.prg.data)
		addrs = [a for lo, hi in self.prg.regions for a in range(lo, hi + 1)] if self.prg.banked else \
			[0x10000 - size + o for o in range(size)]	# (MMC3 PRG mode 1's fixed code: $8000, $E000)
		safe_bit = (lambda a: a & 0x3FFF) if self.prg.banked else (lambda a: a & self.prg.mask)
		first = min(safe_bit(a) for a in addrs) & ~7
		self.out += ['', '\t\talign 4', '\t\tdc.l rcSafe-$%X' % (first >> 3), 'rcTable:']
		for off in range(0, size, 8):
			row = []
			for a in addrs[off:off + 8]:
				row.append(lab(a) if a in self.insns else '0')
			self.out.append('\t\tdc.l ' + ','.join(row))
		# where code coming from the interpreter may go on in this code
		# (rcInterpStep): a bit for each address (by its offset as in
		# rcDispatch, and in a byte by its low 3 bits), set at entries.
		# Elsewhere the code may count on what the code before it left
		# (the carry in X, a5, a value range, a PHA's byte on the 68000's
		# stack...), which the interpreter doesn't.
		bits = bytearray((max(safe_bit(a) for a in addrs) - first) // 8 + 1)
		inside = set(addrs)
		for a in self.entries:
			if a in self.insns and a in inside:
				k = safe_bit(a) - first
				bits[k >> 3] |= 1 << (k & 7)
		self.out.append('rcSafe:')
		for off in range(0, len(bits), 16):
			self.out.append('\t\tdc.b ' + ','.join('$%02X' % b for b in bits[off:off + 16]))
		self.out.append('\t\talign 2')
		if vectors:
			self.out += ['rcPrgMask\tequ $%04X' % self.prg.mask,
				     'rcVecNmi\tequ $%04X' % vectors[0], 'rcVecReset\tequ $%04X' % vectors[1],
				     'rcVecIrq\tequ $%04X' % vectors[2]]
			# the NMI's and IRQ's way in (rcNmiDue, rcIrq): their code, as
			# rcDispatch would find it there
			for name, v in (('rcVecNmiGo', vectors[0]), ('rcVecIrqGo', vectors[2])):
				self.out += [name + ':', '\t\tmovea.l (RAM_RcStack).w,sp']
				if v in self.insns and self.prg.region(v) == 'F':
					self.out += ['\t\tjmp (%s).l' % lab(v)]
				else:
					self.out += ['\t\tmove.w #$%04X,d4' % v, '\t\tjmp rcDispatch']


def long_jumps(out):
	"""JMP/JSR to labels in the translated code with absolute long
	addresses. Left to it, the assembler picks absolute short for labels
	below $8000, and the translated code spans $8000: a jump to a label
	near it can switch size from pass to pass, and the assembly never
	settles (as the FPS counter build of SMB didn't)."""
	defined = {l.split(':')[0].strip() for l in out if re.match(r'\s*[A-Za-z_][A-Za-z0-9_]*:', l)}
	pat = re.compile(r'^(\s*)(jmp|jsr) ([A-Za-z_][A-Za-z0-9_]*)$')
	res = []
	for l in out:
		m = pat.match(l)
		if m and m.group(3) in defined:
			l = '%s%s (%s).l' % m.groups()
		res.append(l)
	return res


def analyze(prg, extra, entries=()):
	"""A unit's code: from its vectors, extra entry points (--entries),
	entries from other units' code, and the jump tables found in it.
	Jump tables may list other units' code too (banked PRG): 'tables'
	keeps those, for outside()."""
	user = list(extra)
	extra = list(extra) + sorted(set(entries) - set(extra))
	insns, vectors, inline = discover(prg, extra)
	while True:
		foreign, loads = [], set()
		found, rts = jump_tables(prg, insns, foreign, loads)
		more = {a for a in found if prg.has(a)} - set(insns)
		if not more:
			break
		extra = list(extra) + sorted(more)
		insns, vectors, inline = discover(prg, extra)
	extra = list(extra) + sorted({a for a in inline if prg.has(a)} - set(extra))
	tables = sorted(found | inline)
	return {'insns': insns, 'vectors': vectors, 'extra': extra, 'tables': tables, 'user': user,
		'rts': {a for a in rts if prg.has(a)}, 'entries': set(entries), 'banked': prg.banked,
		'slot': prg.slot, 'region': prg.region, 'foreign': sorted(set(foreign)), 'loads': loads}


def own_refs(insns):
	"""Where code goes from its own instructions: JSRs, JMPs and branches."""
	return {i.arg for i in insns.values() if i.m in ('JSR', 'JMP') and i.mode == 'abs'} | \
		{t for i in insns.values() if i.mode == 'rel' for t in i.succ if t is not None}


def outside(u, lo, hi):
	"""Where a unit's code goes in lo..hi-1: calls, jumps, jump tables."""
	return {i.arg for i in u['insns'].values() if i.m in ('JSR', 'JMP') and i.mode == 'abs' and lo <= i.arg < hi} | \
	       {a for a in u['tables'] if lo <= a < hi}


def unit_liveness(u, ext_entries=(), facts=(None, None, None)):
	"""liveness() of a unit's code. facts: cross_flags' for it."""
	insns = u['insns']
	switching = {i.pc for i in insns.values() if u['banked'] and mapper_write(i)}
	return liveness(insns, {i.pc + 3 for i in insns.values() if i.m == 'JSR'} | set(u['extra']), u['tables'],
			u['user'] + sorted(u['rts']), ext_entries, set(u['vectors']) | set(u['user']) | u['rts'],
			*facts, switching)


def cross_flags(us, lives):
	"""Banked PRG: what each unit's flag liveness needs from the others'.
	us[0] is the fixed bank's unit, us[1:] the banks'; lives their
	liveness() results. Returns, per unit: the flags live where its code
	goes into another unit's (ext_live), those live where other units'
	calls of its routines return (ext_ret), and summaries of the other
	units' routines it calls (ext_sum; the fixed bank's calls into the
	banks go to whichever bank is there). MMC3 PRG mode 1: us[0] is the
	fixed banks' unit, the others the slots' banks'; each unit's code
	goes to its own at its own slot, else to any bank's there."""
	ext_live, ext_ret, ext_sum = [{} for _ in us], [{} for _ in us], [{} for _ in us]
	def units(k, a):		# whose code unit k's code reaches at a
		r = us[k]['region'](a)
		if r == us[k]['slot']:
			return []		# (its own)
		return [j for j in range(len(us)) if us[j]['slot'] == r and a in us[j]['insns']]
	for k, u in enumerate(us):
		for i in u['insns'].values():
			for s in i.succ:
				if s is None or s in u['insns']:
					continue
				js = units(k, s)
				v = 0
				for j in js:
					v |= lives[j][0][s]
				ext_live[k][s] = v if js else ALL
				r = i.pc + 3		# a jump returns where its routine's caller does
				back = lives[k][0][r] if i.m == 'JSR' and not i.table and r in u['insns'] else ALL
				for j in js:
					ext_ret[j][s] = ext_ret[j].get(s, 0) | back
				if i.m == 'JSR' and js and all(s in lives[j][1] for j in js):
					g, kl = 0, ALL
					for j in js:
						g, kl = g | lives[j][1][s][0], kl & lives[j][1][s][1]
					ext_sum[k][s] = (g, kl)
		for t in u['tables']:
			for j in units(k, t) if t not in u['insns'] else ():
				ext_ret[j][t] = ALL
	return ext_live, ext_ret, ext_sum


def generate(prg, u, ext_entries=(), ext_insns=(), facts=(None, None, None), copies_for=(), ext_routines=None,
	     ext_calls=None, dyn=None, dyn_copies=()):
	"""A unit's 68000 code. ext_entries: its code that other units' code
	goes to; ext_insns: other units' code it can jump to directly; facts:
	cross_flags' for it. The fixed bank's: copies_for, the routines the
	banks' code calls (copies of them, Gen.routine_body, if they can
	have one). A bank's: ext_routines, those copies ((heavy, switches)
	by address); ext_calls, the fixed bank's JSRs to its routines (where
	their RTSs can return straight to). MMC3 PRG mode 1: dyn, the
	routines code calls in the other slot (Gen.emit_dyn_call), and a bank's
	dyn_copies, its own of them (copies with every flag kept where they
	return, as who calls them isn't known)."""
	insns, vectors, extra, tables = u['insns'], u['vectors'], u['extra'], u['tables']
	g = Gen(prg, insns, ext_insns)
	g.live_in, g.sums = unit_liveness(u, ext_entries, facts)
	g.copies_for, g.ext_routines, g.ext_ret = tuple(copies_for) + tuple(sorted(dyn_copies)), ext_routines or {}, \
		dict(facts[1] or {})
	g.ext_ret.update({f: ALL for f in dyn_copies})
	g.dyn, g.dyn_copies = dyn or {}, set(dyn_copies)
	g.ext_calls = ext_calls or {}
	g.tables = tables
	g.engines = {}
	for i in insns.values():
		if i.m == 'JSR' and i.arg not in g.engines:
			g.engines[i.arg] = engine_pattern(prg, i.arg)
	g.engines = {a: z for a, z in g.engines.items() if z}
	entries = set(vectors) | set(extra) | {i.pc + 3 for i in insns.values() if i.m == 'JSR'}
	g.ranges = ranges(insns, entries)
	g.entries = entries
	g.run(vectors)
	return g


def prefixed(out, pre):
	"""A bank's code with its labels prefixed: every bank's code is at
	$8000-$BFFF. Labels it uses from the fixed bank's code stay."""
	names = set()
	for l in out:
		m = re.match(r'([A-Za-z_][A-Za-z0-9_]*):', l.strip())
		if m:
			names.add(m.group(1))
	tok = re.compile(r'(?<![\w$.])[A-Za-z_][A-Za-z0-9_]*\b')
	return [tok.sub(lambda m: pre + m.group(0) if m.group(0) in names else m.group(0), l) for l in out]


def mode1(rom, extra):
	"""MMC3 in PRG mode 1: the fixed banks' code, and each bank's at its
	slot (slot_homes) from where other units' code goes there: the fixed
	code's and the other slot's banks' (wherever the bank's bytes look
	like code, code_at: which bank is there isn't known here), and from
	the jump tables they load from its slot, as they are in the bank
	(slot_table), until no unit's code goes anywhere new. Returns the
	output and the units."""
	homes = slot_homes(rom)
	fixed = Prg(rom, 'F')
	slots = [Prg(rom, (s, b)) for s in 'AC' for b in sorted(homes) if homes[b] == s]
	fixed.peers = slots
	for b in slots:
		b.peers = [fixed] + [p for p in slots if p.slot != b.slot]
	win = {'F': ((0x8000, 0xA000), (0xE000, 0x10000)), 'A': ((0xA000, 0xC000),), 'C': ((0xC000, 0xE000),)}
	into = {s: set() for s in 'FAC'}
	tab = {b.unit: set() for b in slots}	# and into each bank, from its jump tables other units load
	while True:
		uf = analyze(fixed, extra, into['F'])
		us = [uf] + [analyze(b, [], sorted({a for a in into[b.slot] if code_at(b, a)} | tab[b.unit])) for b in slots]
		new = {s: set() for s in 'FAC'}
		newtab = {b.unit: set() for b in slots}
		for u in us:
			for s in 'FAC':
				for lo, hi in win[s] if s != u['slot'] else ():
					new[s] |= outside(u, lo, hi)
			for l, h, add in u['foreign']:	# (slot_table)
				end = min([a for a in u['loads'] if a > max(l, h)] + [0x10000])
				for b in slots:
					if b.region(l) == b.slot:
						own, fx, other = slot_table(b, l, h, add, end)
						newtab[b.unit] |= set(own)
						new['F'] |= set(fx)
						new['C' if b.slot == 'A' else 'A'] |= set(other)
		if all(new[s] <= into[s] for s in 'FAC') and all(newtab[k] <= tab[k] for k in tab):
			break
		for s in 'FAC':
			into[s] |= new[s]
		for k in tab:
			tab[k] |= newtab[k]
	# flags live where one unit's code goes to another's (as for banks
	# at $8000, main)
	ents = [into['F']] + [u['entries'] for u in us[1:]]
	facts = [(None, None, None) for _ in us]
	for _ in range(10):
		lives = [unit_liveness(u, e, f) for u, e, f in zip(us, ents, facts)]
		new = list(zip(*cross_flags(us, lives)))
		if new == facts:
			break
		facts = new
	# the banks' code calls the fixed banks' routines' copies
	calls = {i.arg for u in us[1:] for i in u['insns'].values()
		 if i.m == 'JSR' and not i.table and i.arg >= 0x8000 and fixed.region(i.arg) == 'F'}
	# and code calls the routines of the bank in the other slot (the fixed
	# code's: in either) through that bank's table of their copies (Gen.
	# emit_dyn_call): an index for each, by slot
	# (only routines a bank there goes to from its own code too: other
	# addresses there are seldom its code, Gen.dyn_worth)
	refs = {s: set().union(*[own_refs(u['insns']) & set(u['insns']) for u in us[1:] if u['slot'] == s])
		for s in 'AC'}
	dyn = {}
	for s in 'AC':
		ts = sorted({i.arg for u in us for i in u['insns'].values() if i.m == 'JSR' and not i.table and
			     i.arg >= 0x8000 and fixed.region(i.arg) == s and u['slot'] != s} & refs[s])
		dyn.update((t, (s, k)) for k, t in enumerate(ts))
	NEST[0] = nest_ok(fixed, uf)
	g = generate(fixed, uf, into['F'], (), facts[0], calls, dyn=dyn)
	copies = {f: g.callable[f][1:] + (g.copy_label(f), g.switch_slots(f)) for f in calls
		  if f in g.callable and f not in g.double_rts}
	out, units = list(g.out), [(uf, g)]
	for b, u, fb in zip(slots, us[1:], facts[1:]):
		if not u['insns']:
			continue
		ext_calls = {}		# (the fixed code is always there to return to)
		for i in uf['insns'].values():
			if i.m == 'JSR' and not i.table and i.arg in u['insns'] and i.pc + 3 in uf['insns']:
				ext_calls.setdefault(i.arg, set()).add(i.pc)
		gb = generate(b, u, u['entries'], uf['insns'], fb, (), copies, ext_calls, dyn,
			      {t for t, (s, k) in dyn.items() if s == b.slot and t in u['insns']})
		# its call table: a copy's address by index (a heavy one's entry
		# pushes the 6502 return address the call brings in d4 first:
		# Gen.emit_dyn_call), 0 where it has none
		table, entries = [], []
		for t in sorted(t for t, (s, k) in dyn.items() if s == b.slot):
			if t in gb.dyn_copies and t in gb.called and t not in gb.double_rts:
				lab = gb.copy_label(t)
				if gb.callable[t][1]:
					entries += ['H%04X:' % t, '\t\tswap d3', '\t\tmove.w d4,d6', '\t\tlsr.w #8,d6',
						    '\t\tmove.b d6,(a2,d3.w)', '\t\tsubq.b #1,d3', '\t\tmove.b d4,(a2,d3.w)',
						    '\t\tsubq.b #1,d3', '\t\tswap d3', '\t\tjmp (%s).l' % lab]
					lab = 'H%04X' % t
				table.append(lab)
			else:
				table.append('0')
		gb.out += [''] + entries + ['\t\talign 4', 'rcCalls:'] + \
			['\t\tdc.l ' + ','.join(table[k:k + 8]) for k in range(0, len(table), 8)]
		out += [''] + prefixed(gb.out, '%s%d_' % b.unit)
		units.append((u, gb))
	# a record for each bank at each slot, by the bank there (Gen.prg1_switch,
	# rcPrgSlot): its code there (rcDispatch; the $A000 slot's less $8000:
	# its offsets come with bit 15 set), the routines of it that code
	# elsewhere calls (Gen.emit_dyn_call), its frame and the frame +$8000
	have = {b.unit for b, u in zip(slots, us[1:]) if u['insns']}
	n = 1
	while n < fixed.banks8:
		n *= 2			# (the banks, rounded up as prgBank8Mask in md.asm)
	out += ['', '; each bank\'s code at $A000 and at $C000, by the bank there: its record', '\t\talign 4']
	for s, less in (('A', '-$8000'), ('C', '')):
		out += ['rcBankRecs%s:' % s] + ['\t\tdc.l %s%s,%s,PRG_FRAMES+$%X,PRG_FRAMES+$%X' % (
			'%s%d_rcTable' % (s, b) if (s, b) in have else 'rcNoTable', less,
			'%s%d_rcCalls' % (s, b) if (s, b) in have else 'rcNoCalls', b * 0x8000, b * 0x8000 + 0x8000)
			for b in range(n)]
	out += ['rcNoTable:', '\t\trept $2000/8', '\t\tdc.l 0,0,0,0,0,0,0,0', '\t\tendm']	# (a bank with no code there)
	out += ['rcNoCalls:', '\t\trept %d' % max([k + 1 for s, k in dyn.values()] + [1]), '\t\tdc.l 0', '\t\tendm']
	return out, units


def main():
	args = sys.argv[1:]
	extra = []
	if args[:1] == ['--entries']:
		extra = [int(l.split()[0], 16) for l in open(args[1]) if l.strip() and not l.startswith('#')]
		args = args[2:]
	if len(args) != 2:
		sys.exit('usage: recomp6502.py [--entries FILE] game.nes out.asm')
	sys.argv[1:] = args
	rom = open(sys.argv[1], 'rb').read()
	prg = Prg(rom)
	if not prg.banked:
		u = analyze(prg, extra)
		NEST[0] = nest_ok(prg, u)
		g = generate(prg, u)
		out, units = g.out, [(u, g)]
	elif prg.mode1:
		out, units = mode1(rom, extra)
	else:
		# Banked PRG: the fixed bank's code, and each bank's at $8000
		# from where the fixed bank's code goes there (wherever the
		# bank's bytes look like code: which bank is there isn't known
		# here). The banks' code goes back to the fixed bank's, which is
		# looked at again with those as entries: for any of it that its
		# own search missed, and so nothing assumes, where the banks' code
		# comes in, what only its own code going there would make so.
		fixed = Prg(rom, 'F')
		banks = [Prg(rom, n) for n in range(fixed.banks)]
		fixed.peers = banks[:-1]	# (the last one is at $C000)
		for b in banks:
			b.peers = [fixed]
		back = set()
		while True:
			uf = analyze(fixed, extra, back)
			into = outside(uf, 0x8000, 0xC000)
			ubs = [analyze(b, [], [a for a in sorted(into) if plausible_code(b, a)] if b in fixed.peers else [])
			       for b in banks]
			more = set().union(*(outside(ub, 0xC000, 0x10000) for ub in ubs)) - back
			if not more:
				break
			back |= more
		back = set().union(*(outside(ub, 0xC000, 0x10000) for ub in ubs))
		# flags live where one unit's code goes to another's: each unit's
		# liveness with the others' from the last round, until it settles
		us, ents = [uf] + ubs, [back] + [ub['entries'] for ub in ubs]
		facts = [(None, None, None) for _ in us]
		for _ in range(10):
			lives = [unit_liveness(u, e, f) for u, e, f in zip(us, ents, facts)]
			new = list(zip(*cross_flags(us, lives)))
			if new == facts:
				break
			facts = new
		# the banks' code calls the fixed bank's routines' copies
		calls = {i.arg for ub in ubs for i in ub['insns'].values() if i.m == 'JSR' and not i.table and i.arg >= 0xC000}
		NEST[0] = nest_ok(fixed, uf)
		g = generate(fixed, uf, back, (), facts[0], calls)
		copies = {f: g.callable[f][1:] + (g.copy_label(f), g.switch_slots(f)) for f in calls
			  if f in g.callable and f not in g.double_rts}
		out, units = list(g.out), [(uf, g)]
		for n, (b, ub) in enumerate(zip(banks, ubs)):
			ext_calls = {}		# (the fixed bank's code is always there to return to)
			for i in uf['insns'].values():
				if i.m == 'JSR' and not i.table and i.arg in ub['insns'] and i.pc + 3 in uf['insns']:
					ext_calls.setdefault(i.arg, set()).add(i.pc)
			gb = generate(b, ub, ub['entries'], uf['insns'], facts[n + 1], (), copies, ext_calls)
			out += [''] + prefixed(gb.out, 'B%d_' % n)
			units.append((ub, gb))
		out += ['', '; each bank\'s code, by the bank at $8000 (rcDispatch)', '\t\talign 4', 'rcBankTables:'] + \
		       ['\t\tdc.l B%d_rcTable' % n for n in range(len(banks))]
	with open(sys.argv[2], 'w') as f:
		f.write('; generated by tools/recomp6502.py from %s -- do not publish\n' % sys.argv[1].split('/')[-1])
		f.write('\n'.join(long_jumps(out)) + '\n')
	print('recomp6502: %d instructions, %d bytes of 6502 code, %d loops versioned%s' %
	      (sum(len(u['insns']) for u, g in units), sum(i.n for u, g in units for i in u['insns'].values()),
	       sum(len(g.versioned) for u, g in units), '' if NEST[0] else ', NMIs leave routine copies (nest_ok)'))


if __name__ == '__main__':
	main()
