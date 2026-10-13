#!/usr/bin/env python3
# ======================================================================
# recomp6502: translate an NROM game's 6502 code into 68000 code
#
# usage: recomp6502.py [--entries FILE] game.nes out.asm
#
# Code is found by following jumps from the reset/NMI/IRQ vectors.
# Code only reached through computed jumps can be listed in FILE
# (hex addresses, one per line); anything not found is interpreted.
#
# The output is included by md.asm when building with RECOMP=1 (see
# build.sh --recompile). It uses the interpreter's register layout so
# the PPU, APU and input code is shared:
#
#   d0 A, d1 X, d2 Y (bytes, upper bits kept zero)
#   d3 6502 stack pointer (high word) | flags as a 68k CCR (low byte)
#   a1 PRG-ROM copy, a2 NES RAM, a3 PPU buffer, a4 emulator vars
#   a6 vdp_data;  d4-d7, a0, a5 are scratch
#
# Flags are only stored into d3 where a later instruction can read them
# (liveness analysis). A flag test right after the instruction that set
# it uses the 68000's own condition codes. NMIs are checked on backward
# jumps; indirect jumps (RTS, RTI, JMP (ind)) go through rcTable.
#
# The output contains the game's code in another form: don't publish
# it, keep it in out/ like the built ROM.
# ======================================================================

import sys

ALL = 0xF					# flag sets: N Z C V bits
N, Z, C, V = 1, 2, 4, 8
FLAG_OF = {'BPL': N, 'BMI': N, 'BNE': Z, 'BEQ': Z, 'BCC': C, 'BCS': C, 'BVC': V, 'BVS': V}
CC68 = {'BPL': 'pl', 'BMI': 'mi', 'BNE': 'ne', 'BEQ': 'eq', 'BCC': 'cc', 'BCS': 'cs', 'BVC': 'vc', 'BVS': 'vs'}
INVERT = {'eq': 'ne', 'ne': 'eq', 'pl': 'mi', 'mi': 'pl', 'cc': 'cs', 'cs': 'cc', 'vc': 'vs', 'vs': 'vc'}

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

	def text(self):
		f = {'imm': '#$%02X', 'zp': '$%02X', 'zpx': '$%02X,X', 'zpy': '$%02X,Y', 'indx': '($%02X,X)',
		     'indy': '($%02X),Y', 'abs': '$%04X', 'absx': '$%04X,X', 'absy': '$%04X,Y', 'ind': '($%04X)',
		     'rel': '$%04X', 'acc': 'A', None: ''}[self.mode]
		return (self.m + ' ' + (f % self.arg if '%' in f else f)).strip()


class Prg:
	def __init__(self, rom):
		if rom[:4] != b'NES\x1a':
			sys.exit('recomp6502: not an iNES file')
		mapper = rom[6] >> 4 | (rom[7] & 0xF0)
		if mapper not in (0, 3):
			sys.exit('recomp6502: mapper %d is not supported' % mapper)
		self.data = rom[16:16 + rom[4] * 0x4000]
		self.mask = len(self.data) - 1

	def byte(self, a):
		return self.data[a & self.mask] if a >= 0x8000 else None

	def word(self, a):
		return self.byte(a) | self.byte(a + 1) << 8

# ----------------------------------------------------------------------
# Code discovery
# ----------------------------------------------------------------------

def discover(prg, extra=()):
	vectors = [prg.word(0xFFFA), prg.word(0xFFFC), prg.word(0xFFFE)]
	insns = {}
	forced = set()			# decided branches whose fall-through turned out reachable
	while True:
		insns.clear()
		work = list(vectors) + list(extra)
		while work:
			pc = work.pop()
			known = {}		# flag -> value, known along this straight run
			while pc not in insns and pc >= 0x8000:
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
						i.decided = 'taken' if known[f] == want else 'not'
					i.succ = ([i.arg] if i.decided != 'not' else []) + ([nxt] if i.decided != 'taken' else [])
				elif m == 'JMP':
					i.succ = [i.arg] if i.mode == 'abs' else [None]
				elif m == 'JSR':
					i.succ = [i.arg] if i.arg >= 0x8000 else [None]
					work.append(nxt)	# return point
				elif m in ('RTS', 'RTI', 'BRK'):
					i.succ = [None]
					if m == 'BRK':
						work.append(prg.word(0xFFFE))
				else:
					i.succ = [nxt]
				for s in i.succ:
					if s is not None and s != nxt:
						work.append(s)
				# track flags known from immediates, for always-taken branches
				if m in ('LDA', 'LDX', 'LDY') and i.mode == 'imm':
					known = {N: i.arg >> 7, Z: int(i.arg == 0), **{k: v for k, v in known.items() if k in (C, V)}}
				elif m == 'SEC': known[C] = 1
				elif m == 'CLC': known[C] = 0
				elif m == 'CLV': known[V] = 0
				elif m in DEFS: known = {k: v for k, v in known.items() if not (DEFS[m] & k)}
				if i.mode == 'rel' and i.decided is None:
					known = {}
				if nxt not in i.succ:
					break
				pc = nxt
		# a decided branch is only safe if nothing else jumps to it
		targets = {s for i in insns.values() for s in i.succ if s is not None and s != i.pc + i.n}
		targets |= {i.pc + 3 for i in insns.values() if i.m == 'JSR'}
		bad = {i.pc for i in insns.values() if i.decided and i.pc in targets} - forced
		if not bad:
			return insns, vectors
		forced |= bad

def jump_tables(prg, insns):
	"""Addresses found in jump tables:
	- a table of low bytes and one of high bytes, stored into a RAM
	  pointer for JMP (ptr), or after a JMP opcode written to RAM
	- tables pushed high/low before an RTS (target - 1)"""
	order = sorted(insns)
	prev = {order[k]: insns[order[k - 1]] for k in range(1, len(order))}

	def table_load(i):
		p = prev.get(i.pc)
		if p and p.m in ('LDA', 'LDX', 'LDY') and p.mode in ('absx', 'absy') and p.arg >= 0x8000:
			return p.arg
		return None

	slots = set()			# RAM address of a jump pointer's low byte
	for i in insns.values():
		if i.m == 'JMP' and i.mode == 'ind' and i.arg < 0x800:
			slots.add(i.arg)
		if i.m in ('JSR', 'JMP') and i.mode == 'abs' and i.arg < 0x800:
			slots.add(i.arg + 1)
	lo, hi = {}, {}
	for i in insns.values():
		if i.m in ('STA', 'STX', 'STY') and i.mode in ('zp', 'abs'):
			t = table_load(i)
			if t is not None:
				if i.arg in slots: lo.setdefault(i.arg, set()).add(t)
				if i.arg - 1 in slots: hi.setdefault(i.arg - 1, set()).add(t)
	pairs = [(l, h, 0) for slot in lo for l in lo[slot] for h in hi.get(slot, ())]
	# RTS tables: LDA hi,X / PHA / LDA lo,X / PHA ... RTS
	for k, pc in enumerate(order):
		i = insns[pc]
		if i.m == 'PHA' and table_load(i) is not None:
			for j in order[k + 1:k + 4]:
				if insns[j].m == 'PHA' and table_load(insns[j]) is not None:
					pairs.append((table_load(insns[j]), table_load(i), 1))
					break
	found = set()
	for l, h, add in pairs:
		step = 1
		if h == l + 1:			# interleaved: low, high, low, high...
			step, n = 2, 64
		else:
			n = h - l if 0 < h - l <= 128 else 64
		for k in range(0, n * step, step):
			a = ((prg.byte(l + k) | prg.byte(h + k) << 8) + add) & 0xFFFF
			if not plausible_code(prg, a):
				break			# end of the table
			found.add(a)
	return found


def plausible_code(prg, a, count=12):
	"""Do the bytes at a decode as a run of legal instructions?"""
	for _ in range(count):
		if a < 0x8000 or prg.byte(a) not in OPS:
			return False
		m, mode = OPS[prg.byte(a)]
		if m in ('RTS', 'RTI', 'JMP'):
			return True
		a += SIZE[mode]
	return True

# ----------------------------------------------------------------------
# Flag liveness
# ----------------------------------------------------------------------

def liveness(insns):
	live_in = {pc: 0 for pc in insns}
	changed = True
	while changed:
		changed = False
		for pc in sorted(insns, reverse=True):
			i = insns[pc]
			out = 0
			for s in i.succ:
				out |= ALL if s is None or s not in insns else live_in[s]
			i.live_out = out
			new = USES.get(i.m, 0) | (out & ~DEFS.get(i.m, 0))
			if new != live_in[pc]:
				live_in[pc] = new
				changed = True
	return live_in

# ----------------------------------------------------------------------
# Code generation
# ----------------------------------------------------------------------

def lab(a):
	return 'L_%04X' % a


class Gen:
	def __init__(self, prg, insns):
		self.prg, self.insns = prg, insns
		self.out, self.stubs = [], []

	def e(self, *lines):
		self.out.extend('\t\t' + l for l in lines)

	# ---- operands -----------------------------------------------------

	def src(self, i):
		"""Setup lines and a 68k source EA for the operand value."""
		m, a = i.mode, i.arg
		if m == 'imm':
			return [], '#$%02X' % a
		if m == 'zp':
			return [], '$%02X(a2)' % a
		if m in ('zpx', 'zpy'):
			r = 'd1' if m == 'zpx' else 'd2'
			if a == 0:
				return [], '(a2,%s.w)' % r
			return ['move.w %s,d6' % r, 'addi.b #$%02X,d6' % a], '(a2,d6.w)'
		if m == 'abs':
			if a < 0x2000:
				return [], '$%04X(a2)' % (a & 0x7FF)
			if a >= 0x8000:
				return [], '#$%02X' % self.prg.byte(a)	# NROM: PRG never changes
			return self.io_read(a)
		if m in ('absx', 'absy'):
			r = 'd1' if m == 'absx' else 'd2'
			if a + 255 < 0x800:
				if a < 0x80:
					return [], '$%02X(a2,%s.w)' % (a, r)
				return ['lea $%04X(a2),a5' % a], '(a5,%s.w)' % r
			if a >= 0x8000 and a + 255 <= 0xFFFF:
				return ['lea $%04X(a1),a5' % (a & 0x7FFF)], '(a5,%s.w)' % r
			return ['move.w #$%04X,d6' % a, 'add.w %s,d6' % r, 'jsr rcRead16'], 'd7'
		if m == 'indy':
			return self.indy_addr(a) + ['jsr rcRead16'], 'd7'
		if m == 'indx':
			return self.indx_addr(a) + ['jsr rcRead16'], 'd7'
		raise ValueError(m)

	def io_read(self, a):
		if a < 0x4000:
			return ['moveq #$%02X,d4' % (a & 7), 'jsr rdFrom_PPU'], 'd7'
		if a < 0x4100:
			return ['moveq #0,d4', 'move.b #$%02X,d4' % (a & 0xFF), 'jsr rdFrom_APU'], 'd7'
		return ['move.w #$%04X,d6' % a, 'jsr rcRead16'], 'd7'

	def indy_addr(self, zp):
		return ['move.b $%02X(a2),d6' % ((zp + 1) & 0xFF), 'lsl.w #8,d6',
			'move.b $%02X(a2),d6' % zp, 'add.w d2,d6']

	def indx_addr(self, zp):
		return ['move.w d1,d5', 'addi.b #$%02X,d5' % zp, 'move.b (a2,d5.w),d4',
			'addq.b #1,d5', 'move.b (a2,d5.w),d6', 'lsl.w #8,d6', 'move.b d4,d6']

	def dst(self, i):
		"""Setup and a 68k destination EA, or None for a generic write
		(value in d7, then the returned 'post' lines)."""
		m, a = i.mode, i.arg
		if m == 'zp':
			return [], '$%02X(a2)' % a, []
		if m in ('zpx', 'zpy'):
			r = 'd1' if m == 'zpx' else 'd2'
			if a == 0:
				return [], '(a2,%s.w)' % r, []
			return ['move.w %s,d6' % r, 'addi.b #$%02X,d6' % a], '(a2,d6.w)', []
		if m == 'abs':
			if a < 0x2000:
				return [], '$%04X(a2)' % (a & 0x7FF), []
			if 0x2000 <= a < 0x4000:
				return [], None, ['moveq #$%02X,d4' % (a & 7), 'jsr wrTo_PPU']
			if 0x4000 <= a < 0x4020:
				return [], None, ['moveq #$%02X,d4' % (a & 0xFF), 'jsr wrTo_APU']
			return [], None, ['move.w #$%04X,d6' % a, 'jsr rcWrite16']
		if m in ('absx', 'absy'):
			r = 'd1' if m == 'absx' else 'd2'
			if a + 255 < 0x800:
				if a < 0x80:
					return [], '$%02X(a2,%s.w)' % (a, r), []
				return ['lea $%04X(a2),a5' % a], '(a5,%s.w)' % r, []
			return [], None, ['move.w #$%04X,d6' % a, 'add.w %s,d6' % r, 'jsr rcWrite16']
		if m == 'indy':
			return [], None, self.indy_addr(a) + ['jsr rcWrite16']
		if m == 'indx':
			return [], None, self.indx_addr(a) + ['jsr rcWrite16']
		raise ValueError(m)

	# ---- flags ----------------------------------------------------------

	def save_nz(self):
		self.e('move sr,d5', 'andi.w #$C,d5', 'andi.b #$F3,d3', 'or.b d5,d3')

	def save_nzc(self):			# shifts: X N Z C, keep V
		self.e('move sr,d5', 'andi.w #$1D,d5', 'andi.b #$E2,d3', 'or.b d5,d3')

	def save_cmp(self):			# N Z, C = no borrow (and X), keep V
		self.e('move sr,d5', 'andi.w #$D,d5', 'eori.b #1,d5', 'andi.b #2,d3', 'or.b d5,d3',
		       'andi.b #1,d5', 'lsl.b #4,d5', 'or.b d5,d3')

	# ---- control flow ---------------------------------------------------

	def goto(self, i, target, tag='K'):
		"""Unconditional jump; backward jumps check for an NMI first."""
		if target <= i.pc:
			self.e('tst.w FamiMdVint(a4)', 'beq.s %s_%04X' % (tag, i.pc),
			       'move.w #$%04X,d4' % target, 'jsr rcNmi')
			self.out.append('%s_%04X:' % (tag, i.pc))
		if target not in self.insns:
			self.e('move.w #$%04X,d4' % target, 'jmp rcDispatch')
		else:
			self.e('jmp %s' % lab(target))

	def branch(self, i, cc, tag='S'):
		"""Conditional branch on 68k condition cc (flags already in the CCR).
		Out-of-line stubs (tag 'T') are far from their targets: jmp there."""
		t, nxt = i.arg, i.pc + 2
		if t <= i.pc or t not in self.insns or tag == 'T':
			self.e('b%s.w %s_%04X' % (INVERT[cc], tag, i.pc))
			self.goto(i, t, 'J' if tag == 'T' else 'K')
			self.out.append('%s_%04X:' % (tag, i.pc))
		else:
			self.e('b%s.w %s' % (cc, lab(t)))

	# ---- one instruction ---------------------------------------------------

	def emit(self, i, nxt_i):
		m = i.m
		live = i.live_out
		defs = DEFS.get(m, 0)
		need = defs & live
		# can the next instruction (a branch) test our flags directly?
		direct = None
		if (nxt_i is not None and nxt_i.mode == 'rel' and nxt_i.decided is None
		    and FLAG_OF[nxt_i.m] & defs and not (defs & nxt_i.live_out)):
			direct = nxt_i
		self.direct_next = None

		def nz_done(kind='nz'):
			if direct and kind:
				self.direct_next = kind
			elif need:
				self.save_nz()

		if m in ('LDA', 'LDX', 'LDY'):
			r = {'LDA': 'd0', 'LDX': 'd1', 'LDY': 'd2'}[m]
			setup, s = self.src(i)
			self.e(*setup)
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
		elif m in ('INX', 'INY', 'DEX', 'DEY'):
			r = 'd1' if m[2] == 'X' else 'd2'
			self.e('%s.b #1,%s' % ('addq' if m[0] == 'I' else 'subq', r))
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
			if s != 'd7':
				self.e('move.b %s,d7' % s)
			if m == 'ADC':
				if need:
					self.e('ori.b #4,d3', 'move d3,ccr', 'addx.b d7,d0', 'move sr,d3')
				else:
					self.e('move d3,ccr', 'addx.b d7,d0')
			else:
				if need:
					self.e('eori.b #$11,d3', 'ori.b #4,d3', 'move d3,ccr', 'subx.b d7,d0',
					       'move sr,d3', 'eori.b #$11,d3')
				else:
					self.e('eori.b #$11,d3', 'move d3,ccr', 'subx.b d7,d0')
		elif m in ('CMP', 'CPX', 'CPY'):
			if need or direct:
				r = {'CMP': 'd0', 'CPX': 'd1', 'CPY': 'd2'}[m]
				setup, s = self.src(i)
				self.e(*setup)
				self.e(('cmpi.b %s,%s' if s.startswith('#') else 'cmp.b %s,%s') % (s, r))
				if direct:
					self.direct_next = 'cmp'
				else:
					self.save_cmp()
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
				self.direct_next = 'bitv' if f == V else 'nz'
			elif need:
				self.e('move.b d7,d4', 'andi.b #$F1,d3',
				       'lsl.b #1,d7', 'bcc.s *+6', 'ori.b #8,d3',
				       'lsl.b #1,d7', 'bcc.s *+6', 'ori.b #2,d3',
				       'and.b d0,d4', 'bne.s *+6', 'ori.b #4,d3')
		elif m in ('ASL', 'LSR', 'ROL', 'ROR'):
			op = {'ASL': 'lsl', 'LSR': 'lsr', 'ROL': 'roxl', 'ROR': 'roxr'}[m]
			pre = ['move d3,ccr'] if m in ('ROL', 'ROR') else []
			if i.mode == 'acc':
				self.e(*pre)
				self.e('%s.b #1,d0' % op)
				if direct:
					self.direct_next = 'shift'
				elif need:
					self.save_nzc()
			else:
				setup, d, post = self.dst(i)
				if d is not None:
					self.e(*setup)
					self.e('move.b %s,d7' % d, *pre)
					self.e('%s.b #1,d7' % op)
					if need:
						self.save_nzc()
					self.e('move.b d7,%s' % d)
				else:
					self.rmw_generic(i, pre + ['%s.b #1,d7' % op], need, 'shift')
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
		elif m == 'PHA':
			self.e('swap d3', 'move.b d0,(a2,d3.w)', 'subq.b #1,d3', 'swap d3')
		elif m == 'PHP':
			self.e('jsr famiGetP', 'swap d3', 'move.b d5,(a2,d3.w)', 'subq.b #1,d3', 'swap d3')
		elif m == 'PLA':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d0', 'swap d3', 'tst.b d0')
			nz_done()
		elif m == 'PLP':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d5', 'swap d3', 'jsr famiSetP')
		elif m == 'JMP':
			if i.mode == 'abs':
				self.goto(i, i.arg)
			else:
				p = i.arg
				if p >= 0x8000:
					self.goto(i, self.prg.word(p))
				else:
					hi = (p & 0xFF00) | ((p + 1) & 0xFF)	# 6502 page wrap bug
					self.e('move.b $%04X(a2),d4' % (hi & 0x7FF), 'lsl.w #8,d4',
					       'move.b $%04X(a2),d4' % (p & 0x7FF), 'jmp rcDispatch')
		elif m == 'JSR':
			ret = i.pc + 2
			self.e('swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
			       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3', 'swap d3')
			if i.arg >= 0x8000:
				self.e('jmp %s' % lab(i.arg))
			else:
				self.e('move.w #$%04X,d4' % i.arg, 'jmp rcDispatch')
		elif m == 'RTS':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d6', 'addq.b #1,d3',
			       'move.b (a2,d3.w),d4', 'swap d3', 'lsl.w #8,d4', 'move.b d6,d4',
			       'addq.w #1,d4', 'jmp rcDispatch')
		elif m == 'RTI':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d5', 'addq.b #1,d3',
			       'move.b (a2,d3.w),d6', 'addq.b #1,d3', 'move.b (a2,d3.w),d4', 'swap d3',
			       'jsr famiSetP', 'lsl.w #8,d4', 'move.b d6,d4', 'clr.w cpuFamiVint(a4)',
			       'jmp rcDispatch')
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
		self.e('move.w (sp)+,d6', 'jsr rcWrite16')

	def emit_branch(self, i, direct_kind):
		cc = CC68[i.m]
		if i.decided == 'taken':
			self.goto(i, i.arg)
			return
		if i.decided == 'not':
			return
		if direct_kind == 'cmp' and i.m in ('BCC', 'BCS'):
			cc = INVERT[cc]
		elif direct_kind == 'bitv':
			cc = {'BVS': 'ne', 'BVC': 'eq'}[i.m]
		elif direct_kind is None:
			self.e('move d3,ccr')
		self.branch(i, cc)
		# entry from elsewhere: flags are in d3
		if direct_kind is not None:
			self.stubs += ['%s:' % lab(i.pc), '\t\tmove d3,ccr']
			save, self.out = self.out, []
			self.branch(i, CC68[i.m], 'T')
			self.stubs += self.out
			self.stubs += ['\t\tjmp %s' % lab(i.pc + 2)] if i.pc + 2 in self.insns else \
				      ['\t\tmove.w #$%04X,d4' % (i.pc + 2), '\t\tjmp rcDispatch']
			self.out = save

	def run(self, vectors):
		pcs = sorted(self.insns)
		self.out.append('rcCode:')
		direct_kind = None
		for k, pc in enumerate(pcs):
			i = self.insns[pc]
			nxt = self.insns.get(pc + i.n) if i.mode != 'rel' else None
			if not (i.mode == 'rel' and direct_kind is not None):
				self.out.append('%s:\t\t\t\t\t; $%04X  %s' % (lab(pc), pc, i.text()))
			else:
				self.out.append('\t\t\t\t\t\t; $%04X  %s' % (pc, i.text()))
			if i.mode == 'rel':
				self.emit_branch(i, direct_kind)
				direct_kind = None
			else:
				self.emit(i, nxt)
				direct_kind = self.direct_next
			# fall through into code that isn't next in address order
			if i.mode != 'rel' and i.m not in ('JMP', 'JSR', 'RTS', 'RTI', 'BRK'):
				f = pc + i.n
				if k + 1 >= len(pcs) or pcs[k + 1] != f:
					self.e(*(['jmp %s' % lab(f)] if f in self.insns else ['move.w #$%04X,d4' % f, 'jmp rcDispatch']))
			elif i.mode == 'rel' and i.decided != 'taken':
				f = pc + 2
				if k + 1 >= len(pcs) or pcs[k + 1] != f:
					self.e(*(['jmp %s' % lab(f)] if f in self.insns else ['move.w #$%04X,d4' % f, 'jmp rcDispatch']))
		self.out.append('; ---- out-of-line entries ----')
		self.out += self.stubs
		# dispatch table: PRG offset -> code
		self.out += ['', '\t\talign 4', 'rcTable:']
		size = len(self.prg.data)
		for off in range(0, size, 8):
			row = []
			for o in range(off, off + 8):
				a = 0x10000 - size + o
				row.append(lab(a) if a in self.insns else '0')
			self.out.append('\t\tdc.l ' + ','.join(row))
		self.out += ['rcPrgMask\tequ $%04X' % self.prg.mask,
			     'rcVecNmi\tequ $%04X' % vectors[0], 'rcVecReset\tequ $%04X' % vectors[1]]


def main():
	args = sys.argv[1:]
	extra = []
	if args[:1] == ['--entries']:
		extra = [int(l.split()[0], 16) for l in open(args[1]) if l.strip() and not l.startswith('#')]
		args = args[2:]
	if len(args) != 2:
		sys.exit('usage: recomp6502.py [--entries FILE] game.nes out.asm')
	sys.argv[1:] = args
	prg = Prg(open(sys.argv[1], 'rb').read())
	insns, vectors = discover(prg, extra)
	while True:
		more = jump_tables(prg, insns) - set(insns)
		if not more:
			break
		extra = list(extra) + sorted(more)
		insns, vectors = discover(prg, extra)
	liveness(insns)
	g = Gen(prg, insns)
	g.run(vectors)
	with open(sys.argv[2], 'w') as f:
		f.write('; generated by tools/recomp6502.py from %s -- do not publish\n' % sys.argv[1].split('/')[-1])
		f.write('\n'.join(g.out) + '\n')
	print('recomp6502: %d instructions, %d bytes of 6502 code' % (len(insns), sum(i.n for i in insns.values())))


if __name__ == '__main__':
	main()
