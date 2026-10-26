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
# The output is included by md.asm when building with RECOMP=1 (see
# build.sh --recompile). It uses the interpreter's register layout so
# the PPU, APU and input code is shared:
#
#   d0 A, d1 X, d2 Y (bytes, upper bits kept zero)
#   d3 6502 stack pointer (high word) | flags as a 68k CCR (low byte)
#   a0 PRG-ROM copy + $8000 (so (a0,d6.w) reads 6502 address d6 >= $8000)
#   a1 PRG-ROM copy (banked PRG: the image of the bank at $8000)
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

import re
import sys

ALL = 0xF					# flag sets: N Z C V bits
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


class Prg:
	"""PRG-ROM as one translation unit's code sees it.
	NROM and CNROM (unit None): all of $8000-$FFFF, one unit.
	Banked PRG (mappers 2, 4: a 16 KB bank at $8000, the last at $C000,
	see PRG_IMAGES in md.asm): the fixed bank is unit 'F', and each bank
	n at $8000 is unit n, which sees the fixed bank too (its code calls
	and reads it). The fixed bank's code can't know which bank is at
	$8000: those addresses are other units' (bank units go by the bank
	at $8000 when they're called, rcDispatch)."""
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
		self.banks = len(prg) // 0x4000
		self.unit = unit
		self.fixed = prg[-0x4000:]
		if not self.banked or unit is None:	# (banked: only the header is read)
			self.data, self.lo = prg, 0x8000	# (16 KB is at $8000 and $C000)
		elif unit == 'F':
			self.data, self.lo = self.fixed, 0xC000
		else:
			self.data, self.lo = prg[unit * 0x4000:(unit + 1) * 0x4000], 0x8000
		self.mask = len(self.data) - 1
		self.hi = 0xFFFF if not self.banked or unit == 'F' else 0xBFFF
		self.peers = []			# other units, for plausible_code

	def byte(self, a):
		"""The byte at a, if this unit can know it."""
		if a < 0x8000:
			return None
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
		return self.lo <= a <= self.hi

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

def jump_tables(prg, insns):
	"""Addresses found in jump tables:
	- a table of low bytes and one of high bytes (or one table of both,
	  interleaved), stored into a RAM pointer for JMP (ptr), or after a
	  JMP opcode written to RAM
	- tables pushed high/low before an RTS (target - 1)
	Returns all of them, and those reached by RTS."""
	order = sorted(insns)
	prev = {order[k]: insns[order[k - 1]] for k in range(1, len(order))}

	def table_load(i):
		p = prev.get(i.pc)
		if p and p.m in ('LDA', 'LDX', 'LDY') and p.mode in ('absx', 'absy') and prg.const(p.arg):
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

	lo, hi = {}, {}
	for i in insns.values():
		if i.m in ('LDA', 'LDX', 'LDY') and i.mode in ('absx', 'absy') and prg.const(i.arg):
			s = stored_to(i)
			if s is not None:
				if s in slots: lo.setdefault(s, set()).add(i.arg)
				if s - 1 in slots: hi.setdefault(s - 1, set()).add(i.arg)
	pairs = []
	for slot in lo:
		same = lo[slot] & hi.get(slot, set())	# LDA t,Y / INY / LDA t,Y: interleaved
		pairs += [(t, t + 1, 0) for t in same]
		pairs += [(l, h, 0) for l in lo[slot] - same for h in hi.get(slot, set()) - same]
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
	for _ in range(count):
		if not prg.has(a) or prg.byte(a) not in OPS:
			return False
		m, mode = OPS[prg.byte(a)]
		if m in ('RTS', 'RTI', 'JMP'):
			return True
		if m == 'JSR' and prg.const(a + 1) and prg.const(a + 2) and \
		   inline_table_routine(prg, prg.word(a + 1)):
			return True		# a table follows
		a += SIZE[mode]
	return True

# ----------------------------------------------------------------------
# Value ranges of A, X and Y (to prove zp,X / zp,Y can't wrap)
# ----------------------------------------------------------------------

TOP = (0, 255)


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
		self.inline = set()		# small routines put in place of their calls (emit_inline)
		self.out, self.stubs = [], []
		self.fast = None
		self.split_next = None		# flags a branch puts in d3 by way (split_plan)
		self.ccr_d3 = None		# (pc, output length) where the CCR still holds d3's flags
		self.fused_next = None		# an LSR A done with the LDA $4016 before it (pad_lsr)

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
			if a >= 0x8000:
				return [], '$%04X(a1)' % (a & 0x7FFF)	# the bank at $8000 now
			if self.wram(a):
				return [], 'rcWram+$%04X(a4)' % a
			return self.io_read(a)
		if m in ('absx', 'absy'):
			r = 'd1' if m == 'absx' else 'd2'
			if a + 255 < 0x2000:
				return self.ram_indexed(i, r)
			if a >= 0x8000 and a + self.index_hi(i) <= 0xFFFF:
				return ['lea $%04X(a1),a5' % (a & 0x7FFF)], '(a5,%s.w)' % r
			if self.wram(a, self.index_hi(i)):
				return ['lea rcWram+$%04X(a4),a5' % a], '(a5,%s.w)' % r
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
			self.stubs += ['\t\tjsr rcRead16'] + \
				      (['\t\tmove.b d7,%s' % r] if r != 'd7' else []) + ['\t\tjmp ' + rd]
			return self.indy_addr(a) + ['bpl.w ' + rn, 'move.b (a0,d6.w),%s' % r,
						    rd + ':'], r
		if m == 'indx':
			return self.indx_addr(a) + ['jsr rcRead16'], 'd7'
		raise ValueError(m)

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
		bank it runs in)?"""
		return self.prg.unit != 'F' and self.prg_switch(i)

	def prg_switch(self, i):
		"""Can i switch the bank at $8000? With MMC3, only its $8001 can."""
		if not (self.prg.banked and mapper_write(i)):
			return False
		return not (i.mode == 'abs' and self.prg.mapper == 4 and i.arg & 0xE001 != 0x8001)

	def after_switch(self, i):
		"""After a mapper write in a bank's code: if the bank at $8000 is
		another one now, go on in its code."""
		if not self.switches(i):
			return []
		k = self.tag('Sw', i.pc)
		return ['cmpa.l #PRG_IMAGES+$%X,a1' % (self.prg.unit * 0x8000), 'beq.s ' + k,
			'move.w #$%04X,d4' % ((i.pc + i.n) & 0xFFFF), 'jmp rcDispatch', k + ':']

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
		if ea is None or ea.startswith('('):
			if ea != '(a2,d6.w)':
				return d		# a5 or a call: version_plan gives up
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
				reg = {0x8000: 'mmc3WrSelect', 0x8001: 'mmc3WrData', 0xA000: 'mmc3WrMirror'}.get(a & 0xE001)
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
		(rcNmi in emu/recomp.asm)."""
		if t in self.idle_jmps:
			return 'tst.w nmiWaitDue(a4)', 'jsr rcNmiIdle'
		if t in self.idle_heads:
			return 'tst.w nmiWaitDue(a4)', 'jsr rcNmiWait'
		return 'tst.w FamiMdVint(a4)', 'jsr rcNmi'

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

	def stack_pairs(self, push, pull, also=lambda i: True):
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
			walk, work, ok = set(), [p.pc + 1], True
			while work and ok:
				pc = work.pop()
				i = self.insns.get(pc)
				if i is None or len(walk) > 32 or i.m in ('PLA', 'PHA', 'PHP', 'PLP', 'JSR', 'RTS', 'RTI', 'BRK',
									   'TSX', 'TXS', 'SEI', 'CLI', 'SED', 'CLD') and i.m != pull or \
				   None in i.succ or not also(i):
					ok = False
				elif pc not in walk:
					walk.add(pc)
					if i.m != pull:
						work += i.succ
			if ok and walk and not (walk & outside) and all(preds[pc] <= walk | {p.pc} for pc in walk):
				found |= {p.pc} | {pc for pc in walk if self.insns[pc].m == pull}
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
			body, pc, ok = [], b.arg, True
			while pc < b.pc:
				i = self.insns.get(pc)
				if i is None or i.m in ('JSR', 'JMP', 'RTS', 'RTI', 'BRK'):
					ok = False; break
				if i.mode == 'rel' and i.arg <= i.pc:
					ok = False; break		# not innermost
				body.append(i)
				pc += i.n
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
			self.e('move.w #$%04X,d4' % target, 'jmp rcDispatch')

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
		elif m == 'PLP' and i.pc in self.paired:
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d5', 'swap d3', 'move.b d5,d3')
		elif m == 'PLP':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d5', 'swap d3', 'jsr famiSetP')
		elif m == 'JMP':
			if i.mode == 'abs':
				self.goto(i, i.arg)
			else:
				p = i.arg
				hi = (p & 0xFF00) | ((p + 1) & 0xFF)	# 6502 page wrap bug
				if self.prg.const(p) and self.prg.const(hi):
					self.goto(i, self.prg.byte(p) | self.prg.byte(hi) << 8)
				elif p >= 0x8000:
					self.e('move.b $%04X(a1),d4' % (hi & 0x7FFF), 'lsl.w #8,d4',
					       'move.b $%04X(a1),d4' % (p & 0x7FFF), 'jmp rcDispatch')
				else:
					hi = (p & 0xFF00) | ((p + 1) & 0xFF)	# 6502 page wrap bug
					self.e('move.b $%04X(a2),d4' % (hi & 0x7FF), 'lsl.w #8,d4',
					       'move.b $%04X(a2),d4' % (p & 0x7FF), 'jmp rcDispatch')
		elif m == 'JSR' and not (self.fast and not self.fast.get('routine')) and i.arg in self.engines and \
		     (i.arg in self.insns or i.arg in self.ext) and self.engine_table(i):
			self.emit_engine_call(i)
		elif m == 'JSR' and i.arg in self.inline and (not self.fast or self.fast.get('routine')):
			self.emit_inline(i)
		elif m == 'JSR' and i.arg in self.callable:
			if self.callable[i.arg][1]:
				ret = i.pc + 2
				self.e('swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
				       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3', 'swap d3')
			self.e('jsr R%04X_%04X' % (i.arg, i.arg))	# see routine_body
			self.called.add(i.arg)
		elif m == 'JSR' and i.arg in self.ext_routines and not i.table:
			heavy, sw, label = self.ext_routines[i.arg]
			if heavy:
				ret = i.pc + 2
				self.e('swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
				       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3', 'swap d3')
			self.e('jsr ' + label)		# the fixed bank's copy
			if sw:				# it may have switched this bank out
				k = self.tag('Sw', i.pc)
				self.e('cmpa.l #PRG_IMAGES+$%X,a1' % (self.prg.unit * 0x8000), 'beq.s ' + k,
				       'move.w #$%04X,d4' % ((i.pc + 3) & 0xFFFF), 'jmp rcDispatch')
				self.out.append(k + ':')
		elif m == 'JSR':
			ret = i.pc + 2
			self.e('swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
			       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3', 'swap d3')
			if self.fast and self.fast.get('routine'):	# leaving a copy: drop the 68000's returns
				self.e('move.w #$%04X,d4' % i.arg, 'jmp rcDispatch')
			elif i.arg >= 0x8000 and (not self.prg.banked or i.arg in self.insns or i.arg in self.ext):
				self.e('jmp %s' % lab(i.arg))
			else:
				self.e('move.w #$%04X,d4' % i.arg, 'jmp rcDispatch')
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
			self.e('jmp rcDispatch')
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
		self.stubs += [jt + ':'] + ['\t\tdc.l %s' % self.lab(a) for a in t]
		self.stubs += [g + ':', '\t\tswap d3', '\t\tmove.b #$%02X,(a2,d3.w)' % (ret >> 8), '\t\tsubq.b #1,d3',
			       '\t\tmove.b #$%02X,(a2,d3.w)' % (ret & 0xFF), '\t\tsubq.b #1,d3', '\t\tswap d3']
		if self.fast:				# leaving a copy: drop the 68000's returns
			self.stubs += ['\t\tmove.w #$%04X,d4' % i.arg, '\t\tjmp rcDispatch']
		else:
			self.stubs += ['\t\tjmp %s' % self.lab(i.arg)]

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
		if pc != b.pc + 2 or body[0].mode == 'rel':
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
			'direct': direct, 'check': check, 'guard': guard}
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

	def copy_of(self, plan, turns):
		"""Code for a loop's fast copy, or None if it would need a5 or a
		call. turns: None for a loop, else (turns, off) to unroll."""
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
				self.fast = dict(plan, prefix=base + ('U%d' % k if k else 'F'), outer=outer and base)
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
			self.e(*exit)
			fast = self.out + self.stubs
		except Unroll:
			fast = None
		finally:
			self.fast = outer
			self.out, self.stubs, self.xc, self.c_skipped = save
			self.ccr_d3 = None
		if fast and any(',a5' in l or ('jsr' in l and 'rcNmi' not in l) for l in fast):
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
		g += ['\t\tcmpi.w #$701,d6', '\t\tbcs.s %sVR_%04X' % (v, t)]	# RAM, +255 stays below $800
		if self.prg.banked:		# PRG RAM, +255 stays below $8000
			g += ['\t\tcmpi.w #$6000,d6', '\t\tbcs.w %s' % slow,
			      '\t\tcmpi.w #$7F01,d6', '\t\tbcs.s %sVW_%04X' % (v, t)]
		g += ['\t\tcmpi.w #$8000,d6', '\t\tbcs.w %s' % slow,
		      '\t\tcmpi.w #$FF01,d6', '\t\tbcc.w %s' % slow,	# PRG, +255 stays below $10000
		      '\t\tlea (a0,d6.w),a5', '\t\tbra.s %sF_%04X' % (v, t)]
		if self.prg.banked:
			g += ['%sVW_%04X:' % (v, t), '\t\tlea (RAM_Fami_WRAM-$6000).l,a5', '\t\tadda.w d6,a5',
			      '\t\tbra.s %sF_%04X' % (v, t)]
		g += ['%sVR_%04X:' % (v, t), '\t\tlea (a2,d6.w),a5']
		self.out += g + fast
		return True

	# ---- routines called with the 68000's jsr -------------------------------

	def routine_body(self, f, memo):
		"""(instructions, heavy) of a routine that can be called with the
		68000's jsr, or None. Its copy returns with rts, so every path
		must reach RTS with the stack as it was, and the routines it
		calls must be like it.
		A light routine needs no NMI check and stays in translated code:
		its call doesn't push the return address. (Its own pushes and
		pulls then go where the return address would be, as nothing can
		look at the stack meanwhile.) A heavy one may do those things:
		its call pushes the 6502 return address like JSR does, and if it
		leaves its copy through rcDispatch (an NMI, a computed jump), that
		drops the 68000 return addresses and the normal code takes over."""
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
			if len(depth) >= 300 or i.m in ('RTI', 'BRK', 'TSX', 'TXS'):
				return None
			depth[pc] = d
			if self.switches(i):
				heavy = True		# may go on in another bank, through rcDispatch
			sw |= self.prg_switch(i)	# (the fixed bank's: its callers in banks check)
			if i.m in ('PHA', 'PHP', 'PLA', 'PLP'):
				d += 1 if i.m[1] == 'H' else -1
				if d < 0:
					return None
			if i.m == 'RTS':
				if d:
					return None
				continue
			if i.m == 'JSR' and i.table:
				heavy = True			# past the table: the engine, through rcDispatch
				if i.arg in self.engines and self.engine_table(i) and all(t in self.insns for t in i.table):
					work += [(t, d) for t in i.table]
				continue
			if i.m == 'JSR':
				sub = self.routine_body(i.arg, memo) if i.arg in self.insns else None
				if sub:
					heavy |= sub[1]
					sw |= sub[2]
				elif i.arg in self.ext_routines:
					h, s, _ = self.ext_routines[i.arg]
					heavy |= h or s		# a switch goes on through rcDispatch
					sw |= s
				elif i.arg < 0x800:
					heavy = True	# a jump table in RAM, through rcDispatch
				else:
					heavy = True	# a routine with no copy: the normal code, through rcDispatch
					continue
				work.append((pc + 3, d))
				continue
			for t in i.succ:
				if t is None or t not in self.insns:
					heavy = True	# through rcDispatch
				else:
					if self.back(i, t) and not (i.mode == 'rel' and i.decided is None and pc in self.counted):
						heavy = True	# NMI check
					work.append((t, d))
		memo[f] = (set(depth), heavy, sw)
		return memo[f]

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
		self.fast = {'pcs': set(pcs), 'prefix': '%s%04X' % (prefix, f), 'routine': True, 'heavy': self.callable[f][1]}
		self.xc, self.c_skipped = False, 0
		self.out.append('')
		# its own liveness: it returns only to its callers (the banks', for X)
		ctx = self.ext_ret.get(f, ALL) if prefix == 'X' or self.copy_label(f)[0] == 'R' and f in self.copies_for else 0
		for i in self.insns.values():
			if i.m == 'JSR' and i.arg == f and i.pc + 3 in self.insns and prefix == 'R':
				ctx |= self.live_in[i.pc + 3]
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
			     'heavy': False, 'inline': end, 'last': last if self.insns[last].m == 'RTS' else None}
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
			else:
				self.emit(i, self.insns.get(pc + i.n))
				dk = self.direct_next
				if DEFS.get(i.m, 0) & C and i.m not in ('ASL', 'LSR', 'ROL', 'ROR', 'ADC'):
					self.xc = False
			self.fall_through(i, pcs, k)
		if whole:
			self.out += self.stubs
			self.stubs = []
			self.fast = None

	def fall_through(self, i, pcs, k):
		"""Jump to the next instruction if it isn't next in the output."""
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
		"""Fill or fast copy where the previous instruction falls into a loop."""
		p = self.insns[prev]
		pc = plan['t']
		if p.pc + p.n == pc and pc in p.succ:
			if 'addrs' in plan:
				self.emit_fill(plan)
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
		self.counted = self.counted_loops()
		self.loopy = self.loop_edges()
		self.paired = self.php_pairs()
		self.pha_paired = self.pha_pairs()
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
		self.called = {f for f in self.copies_for if f in self.callable}
		self.returns = self.return_points()
		heads = set()
		for i in self.insns.values():
			if i.m == 'JMP' and i.mode == 'abs' and self.back(i, i.arg): heads.add(i.arg)
			if i.mode == 'rel' and i.decided != 'not' and self.back(i, i.arg) and i.pc not in self.counted:
				heads.add(i.arg)
		plans = {}
		for i in self.insns.values():
			if i.mode == 'rel' and i.decided is None and i.arg < i.pc and i.arg not in plans:
				plan = self.fill_plan(i) or self.version_plan(i)
				if plan:
					plans[i.arg] = plan
		self.versioned = []
		self.plans = plans
		self.inline = {f for f, (body, heavy, sw) in self.callable.items() if not heavy and len(body) <= 24 and
			       not any(pc in plans for pc in body)}
		direct_kind = None
		for k, pc in enumerate(pcs):
			i = self.insns[pc]
			nxt = self.insns.get(pc + i.n) if i.mode != 'rel' else None
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
		# dispatch table: PRG offset -> code
		self.out += ['', '\t\talign 4', 'rcTable:']
		size = len(self.prg.data)
		for off in range(0, size, 8):
			row = []
			for o in range(off, off + 8):
				a = (self.prg.lo if self.prg.banked else 0x10000 - size) + o
				row.append(lab(a) if a in self.insns else '0')
			self.out.append('\t\tdc.l ' + ','.join(row))
		if vectors:
			self.out += ['rcPrgMask\tequ $%04X' % self.prg.mask,
				     'rcVecNmi\tequ $%04X' % vectors[0], 'rcVecReset\tequ $%04X' % vectors[1]]


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
		found, rts = jump_tables(prg, insns)
		more = {a for a in found if prg.has(a)} - set(insns)
		if not more:
			break
		extra = list(extra) + sorted(more)
		insns, vectors, inline = discover(prg, extra)
	extra = list(extra) + sorted({a for a in inline if prg.has(a)} - set(extra))
	tables = sorted(found | inline)
	return {'insns': insns, 'vectors': vectors, 'extra': extra, 'tables': tables, 'user': user,
		'rts': {a for a in rts if prg.has(a)}, 'entries': set(entries), 'banked': prg.banked}


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
	banks go to whichever bank is there)."""
	ext_live, ext_ret, ext_sum = [{} for _ in us], [{} for _ in us], [{} for _ in us]
	def units(k, a):		# whose code unit k's code reaches at a
		if k == 0:
			return [j for j in range(1, len(us)) if a in us[j]['insns']] if a < 0xC000 else []
		return [0] if a in us[0]['insns'] else []
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
	     ext_calls=None):
	"""A unit's 68000 code. ext_entries: its code that other units' code
	goes to; ext_insns: other units' code it can jump to directly; facts:
	cross_flags' for it. The fixed bank's: copies_for, the routines the
	banks' code calls (copies of them, Gen.routine_body, if they can
	have one). A bank's: ext_routines, those copies ((heavy, switches)
	by address); ext_calls, the fixed bank's JSRs to its routines (where
	their RTSs can return straight to)."""
	insns, vectors, extra, tables = u['insns'], u['vectors'], u['extra'], u['tables']
	g = Gen(prg, insns, ext_insns)
	g.live_in, g.sums = unit_liveness(u, ext_entries, facts)
	g.copies_for, g.ext_routines, g.ext_ret = copies_for, ext_routines or {}, facts[1] or {}
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
		g = generate(prg, u)
		out, units = g.out, [(u, g)]
	else:
		# Banked PRG: the fixed bank's code, and each bank's at $8000
		# from where the fixed bank's code goes there (wherever the
		# bank's bytes look like code: which bank is there isn't known
		# here). The banks' code goes back to the fixed bank's, which is
		# looked at again for any of it that its own search missed.
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
			more = set().union(*(outside(ub, 0xC000, 0x10000) for ub in ubs)) - back - set(uf['insns'])
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
		g = generate(fixed, uf, back, (), facts[0], calls)
		copies = {f: g.callable[f][1:] + (g.copy_label(f),) for f in calls if f in g.callable}
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
	print('recomp6502: %d instructions, %d bytes of 6502 code, %d loops versioned' %
	      (sum(len(u['insns']) for u, g in units), sum(i.n for u, g in units for i in u['insns'].values()),
	       sum(len(g.versioned) for u, g in units)))


if __name__ == '__main__':
	main()
