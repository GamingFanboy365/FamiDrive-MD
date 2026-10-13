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
#   a0 PRG-ROM copy + $8000 (so (a0,d6.w) reads 6502 address d6 >= $8000)
#   a1 PRG-ROM copy, a2 NES RAM, a3 PPU buffer, a4 emulator vars
#   a6 vdp_data;  d4-d7, a5 are scratch
#
# Flags are only stored into d3 where a later instruction can read them
# (liveness analysis). A flag test right after the instruction that set
# it uses the 68000's own condition codes. NMIs are checked on backward
# jumps; indirect jumps (RTS, RTI, JMP (ind)) go through rcTable.
#
# Hot code gets second copies: routines that return normally are called
# with the 68000's jsr (routine_body), and loops reading through a
# (zp),Y pointer get a guarded fast copy, unrolled when short
# (version_plan). Fill loops become straight stores (fill_plan).
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
	- tables pushed high/low before an RTS (target - 1)
	Returns all of them, and those reached by RTS."""
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
	found, rts = set(), set()
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
			if add:
				rts.add(a)
	return found, rts


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
							out[k] = meet(out[k], lo, hi)
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
	return state

# ----------------------------------------------------------------------
# Flag liveness
# ----------------------------------------------------------------------

def rts_returns(insns, tables=(), strict=False):
	"""For each RTS, the return points of the JSRs that can reach it.
	A JSR into RAM may call any jump table target. An RTS reached with
	two more bytes pulled than pushed (a routine dropping its return
	address) also goes where its caller returns; other depths would
	return to a garbage address, so those paths are taken as never
	happening. strict: leave out RTSs of routines that move the stack."""
	calls = {}
	for i in insns.values():
		if i.m == 'JSR':
			for f in [i.arg] if i.arg in insns else tables if i.arg < 0x800 else ():
				calls.setdefault(f, set()).add(i.pc)
	body, ends = {}, {}
	unsure = set()
	for f in calls:
		seen, work, found = set(), [(f, 0)], {}
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
				unsure.add(f)
			if i.m == 'JSR':
				work.append((pc + 3, d))	# the callee returns here
			else:
				work += [(s, d) for s in i.succ if s is not None]
		body[f], ends[f] = {pc for pc, d in seen}, found
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


def liveness(insns, returns=(), tables=(), rts_targets=()):
	"""returns: where an RTS can go (JSR return points, RTS jump table
	targets); an RTS's live flags are the union of those of the JSRs
	that reach it and rts_targets (RTS jump tables, unknown entries), or
	of all of them.
	tables: jump table targets, where JMP (ptr) and JSRs into RAM go.
	PHP pushes the flags that are live after the PLPs that pull them,
	unless a PLA may pull them instead."""
	live_in = {pc: 0 for pc in insns}
	returns = [r for r in returns if r in insns]
	tables = [t for t in tables if t in insns]
	rts = {pc: sorted((r | set(rts_targets)) & set(insns)) for pc, r in rts_returns(insns, tables, True).items()}
	plp = [i for i in insns.values() if i.m in ('PLP', 'RTI')]
	whole = set()			# PHPs whose byte may be pulled by PLA
	for i in insns.values():
		if i.m == 'PHP':
			seen, work = set(), [i.pc + 1]
			while work:		# every path must reach a PLP soon
				pc = work.pop()
				j = insns.get(pc)
				if j is None or len(seen) > 32 or j.m in ('PLA', 'PHP', 'JSR', 'RTS', 'RTI', 'BRK', 'TSX', 'TXS'):
					whole.add(i.pc)
					break
				if pc in seen or j.m == 'PLP':
					continue
				seen.add(pc)
				work += j.succ
	changed = True
	while changed:
		changed = False
		pulled = 0
		for i in plp:
			pulled |= getattr(i, 'live_out', ALL)
		jumped = 0
		for t in tables:
			jumped |= live_in[t]
		for pc in sorted(insns, reverse=True):
			i = insns[pc]
			out = 0
			if i.m == 'RTS' and returns:
				for r in rts.get(pc, returns):
					out |= live_in[r]
			else:
				for s in i.succ:
					if s is None and tables and (i.m == 'JSR' or (i.m == 'JMP' and i.mode == 'ind')):
						out |= jumped
					else:
						out |= ALL if s is None or s not in insns else live_in[s]
			if getattr(i, 'live_out', None) != out:
				changed = True
			i.live_out = out
			uses = USES.get(i.m, 0)
			if i.m == 'PHP' and pc not in whole:
				uses = pulled
			new = uses | (out & ~DEFS.get(i.m, 0))
			if new != live_in[pc]:
				live_in[pc] = new
				changed = True
	return live_in

# ----------------------------------------------------------------------
# Code generation
# ----------------------------------------------------------------------

def lab(a):
	return 'L_%04X' % a


class Unroll(Exception):
	pass


class Gen:
	def __init__(self, prg, insns):
		self.prg, self.insns = prg, insns
		self.out, self.stubs = [], []
		self.fast = None

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
		if m in ('imm', 'zp', None):
			return True
		if m == 'abs':
			return a < 0x2000 or a >= 0x8000
		if m in ('absx', 'absy'):
			return a + 255 < 0x800 or (a >= 0x8000 and a + 255 <= 0xFFFF)
		if m in ('zpx', 'zpy'):
			return 'addi' not in ' '.join(self.zp_indexed(i)[0])
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
			if a >= 0x8000:
				return [], '#$%02X' % self.prg.byte(a)	# NROM: PRG never changes
			return self.io_read(a)
		if m in ('absx', 'absy'):
			r = 'd1' if m == 'absx' else 'd2'
			if a + 255 < 0x800:
				if a < 0x80:
					return [], self.ix(a, r)
				return ['lea $%04X(a2),a5' % a], '(a5,%s.w)' % r
			if a >= 0x8000 and a + 255 <= 0xFFFF:
				return ['lea $%04X(a1),a5' % (a & 0x7FFF)], '(a5,%s.w)' % r
			return ['move.w #$%04X,d6' % a, 'add.w %s,d6' % r, 'jsr rcRead16'], 'd7'
		if m == 'indy' and self.fast and 'ptr' in self.fast:
			return [], self.ix(0, 'd2', 'a5')	# pointer checked and loaded into a5
		if m == 'indy':
			rn, rs, rd = (self.tag(x, i.pc) for x in ('Rn', 'Rs', 'Rd'))
			r = dst or 'd7'
			# PRG (the usual case) falls through; RAM and I/O out of line
			self.stubs += [rn + ':', '\t\tcmpi.w #$800,d6', '\t\tbcc.s ' + rs,
				       '\t\tmove.b (a2,d6.w),%s' % r, '\t\tjmp ' + rd,
				       rs + ':', '\t\tjsr rcRead16'] + \
				      (['\t\tmove.b d7,%s' % r] if r != 'd7' else []) + ['\t\tjmp ' + rd]
			return self.indy_addr(a) + ['bpl.w ' + rn, 'move.b (a0,d6.w),%s' % r,
						    rd + ':'], r
		if m == 'indx':
			return self.indx_addr(a) + ['jsr rcRead16'], 'd7'
		raise ValueError(m)

	def ix(self, a, r, base='a2'):
		"""a(base,r.w); in an unrolled loop r is off by a known amount."""
		if self.fast and 'off' in self.fast:
			a += self.fast['off'][r]
			if not -128 <= a <= 127:
				raise Unroll
			return '%d(%s,%s.w)' % (a, base, r)
		return '$%02X(a2,%s.w)' % (a, r) if base == 'a2' else '(%s,%s.w)' % (base, r)

	def zp_indexed(self, i):
		"""zp,X / zp,Y: the address wraps within the zero page, unless
		the index register's range shows it can't."""
		a = i.arg
		r = 'd1' if i.mode == 'zpx' else 'd2'
		rng = self.ranges.get(i.pc)
		hi = rng[1 if i.mode == 'zpx' else 2][1] if rng else 255
		if self.fast and i.pc in self.fast.get('direct', ()):
			hi = 0			# the loop's guard checked the range
		if a == 0 or a + hi <= 0xFF:
			if a <= 0x7F:
				return [], self.ix(a, r)
			return ['lea $%02X(a2),a5' % a], '(a5,%s.w)' % r
		return ['move.w %s,d6' % r, 'addi.b #$%02X,d6' % a], '(a2,d6.w)'

	def io_read(self, a):
		if a < 0x4000:
			return ['moveq #$%02X,d4' % (a & 7), 'jsr rdFrom_PPU'], 'd7'
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
				return [], None, ['moveq #$%02X,d4' % (a & 7), 'jsr wrTo_PPU']
			if 0x4000 <= a < 0x4020:
				return [], None, ['moveq #$%02X,d4' % (a & 0xFF), 'jsr wrTo_APU']
			return [], None, ['move.w #$%04X,d6' % a, 'jsr rcWrite16']
		if m in ('absx', 'absy'):
			r = 'd1' if m == 'absx' else 'd2'
			if a + 255 < 0x800:
				if a < 0x80:
					return [], self.ix(a, r), []
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

	def return_points(self):
		"""For each RTS, the return points of the JSRs that can reach it.
		Only a prediction: RTS still checks the address it pulled."""
		return {pc: r for pc, r in rts_returns(self.insns, self.tables).items() if len(r) <= 4}

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
				n = sum(1 for i in body if i.m in writes[reg])
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
		if target <= i.pc and i.pc in self.counted and target in self.insns:
			self.e('jmp %s' % self.lab(target))
			return
		if target <= i.pc and target in self.prologued and not self.fast:
			self.e('jmp C_%04X' % target)
			return
		if target <= i.pc:
			self.e('tst.w FamiMdVint(a4)', 'beq.s %s' % self.tag(tag, i.pc),
			       'move.w #$%04X,d4' % target, 'jsr rcNmi')
			self.out.append('%s:' % self.tag(tag, i.pc))
		if target not in self.insns:
			self.e('move.w #$%04X,d4' % target, 'jmp rcDispatch')
		else:
			self.e('jmp %s' % self.lab(target))

	def branch(self, i, cc, tag='S'):
		"""Conditional branch on 68k condition cc (flags already in the CCR).
		Out-of-line stubs (tag 'T') are far from their targets: jmp there."""
		t, nxt = i.arg, i.pc + 2
		if t <= i.pc and i.pc in self.counted and t in self.insns and tag != 'T':
			self.e('b%s.w %s' % (cc, self.lab(t)))
			return
		if t <= i.pc and t in self.prologued and tag != 'T' and not self.fast:
			self.e('b%s.w C_%04X' % (cc, t))
			return
		if t <= i.pc or t not in self.insns or tag == 'T':
			self.e('b%s.w %s' % (INVERT[cc], self.tag(tag, i.pc)))
			self.goto(i, t, 'J' if tag == 'T' else 'K')
			self.out.append('%s:' % self.tag(tag, i.pc))
		else:
			self.e('b%s.w %s' % (cc, self.lab(t)))

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
				self.check_carry()
				if self.xc:			# carry already in X
					if need:
						self.e('ori #4,ccr', 'addx.b d7,d0', 'move sr,d3')
					else:
						self.e('addx.b d7,d0')
				elif need:
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
				if need and not direct and not live & V:
					# r + ~s + 1 carries like the 6502's compare; V is dead
					if s.startswith('#'):	# (handlers expect d7's upper bits clear)
						self.e('move.b #$%02X,d7' % (~int(s[2:], 16) & 0xFF))
					else:
						self.e('move.b %s,d7' % s, 'not.b d7')
					self.e('move.b %s,d6' % r, 'move #$14,ccr', 'addx.b d7,d6', 'move sr,d3')
					if nxt_i is not None and nxt_i.mode == 'rel' and nxt_i.decided is None:
						self.direct_next = 'flags'	# also still in the CCR
					return
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
			if m in ('ROL', 'ROR'):
				self.check_carry()
			pre = ['move d3,ccr'] if m in ('ROL', 'ROR') and not self.xc else []
			skip = bool(need & C) and self.carry_in_x(i)
			if skip:
				need &= ~C			# carried in X instead
				save = self.save_nz
			else:
				save = self.save_nzc
			if i.mode == 'acc':
				self.e(*pre)
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
					self.e('move.b %s,d7' % d, *pre)
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
		elif m == 'JSR' and i.arg in self.callable:
			if self.callable[i.arg][1]:
				ret = i.pc + 2
				self.e('swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
				       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3', 'swap d3')
			self.e('jsr R%04X_%04X' % (i.arg, i.arg))	# see routine_body
			self.called.add(i.arg)
		elif m == 'JSR':
			ret = i.pc + 2
			self.e('swap d3', 'move.b #$%02X,(a2,d3.w)' % (ret >> 8), 'subq.b #1,d3',
			       'move.b #$%02X,(a2,d3.w)' % (ret & 0xFF), 'subq.b #1,d3', 'swap d3')
			if i.arg >= 0x8000:
				self.e('jmp %s' % lab(i.arg))
			else:
				self.e('move.w #$%04X,d4' % i.arg, 'jmp rcDispatch')
		elif m == 'RTS' and self.fast and self.fast.get('routine'):
			if self.fast['heavy']:
				self.e('swap d3', 'addq.b #2,d3', 'swap d3')	# drop the return address
			self.e('rts')
		elif m == 'RTS':
			self.e('swap d3', 'addq.b #1,d3', 'move.b (a2,d3.w),d6', 'addq.b #1,d3',
			       'move.b (a2,d3.w),-(sp)', 'swap d3', 'move.w (sp)+,d4', 'move.b d6,d4',
			       'addq.w #1,d4')
			# usually it goes back to one of a few known callers
			for r in sorted(self.returns.get(i.pc, ()))[:4]:
				self.e('cmpi.w #$%04X,d4' % r, 'bne.s *+8', 'jmp (%s).l' % lab(r))
			self.e('jmp rcDispatch')
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
		"""STA base,X / DEX / BPL (or the INX, Y and BNE forms) with a
		known start value fills memory: stores replace the loop where
		code falls into it."""
		t = b.arg
		s, d = self.insns.get(t), self.insns.get(b.pc - 1)
		if not s or not d or s.pc + s.n != d.pc or s.m != 'STA' or b.pc not in self.counted:
			return None
		if d.m not in ('INX', 'DEX', 'INY', 'DEY') or s.mode not in ('zpx', 'zpy', 'absx', 'absy') \
		   or s.mode[-1] != d.m[2].lower():
			return None
		v = self.entry_value(t, d.m[2])
		if v is None:
			return None
		if d.m[0] == 'D' and b.m == 'BPL' and v <= 0x7F:
			lo, hi, end = 0, v, 0xFF
		elif d.m[0] == 'D' and b.m == 'BNE' and v:
			lo, hi, end = 1, v, 0
		elif d.m[0] == 'I' and b.m == 'BNE' and v:
			lo, hi, end = v, 0xFF, 0
		else:
			return None
		lo += s.arg
		hi += s.arg
		if hi >= (0x100 if s.mode[:2] == 'zp' else 0x800):
			return None
		return {'t': t, 'b': b, 'lo': lo, 'hi': hi, 'reg': 'd1' if d.m[2] == 'X' else 'd2', 'end': end}

	def emit_fill(self, plan):
		lo, hi = plan['lo'], plan['hi']
		self.out.append('\t\t\t\t\t\t; $%04X  fill $%04X-$%04X' % (plan['t'], lo, hi))
		if hi - lo >= 3:			# A in all four bytes of d5
			self.e('move.b d0,d5', 'lsl.w #8,d5', 'move.b d0,d5', 'move.w d5,d6', 'swap d5', 'move.w d6,d5')
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
		g += ['\t\tcmpi.w #$701,d6', '\t\tbcs.s %sVR_%04X' % (v, t),	# RAM, +255 stays below $800
		      '\t\tcmpi.w #$8000,d6', '\t\tbcs.w %s' % slow,
		      '\t\tcmpi.w #$FF01,d6', '\t\tbcc.w %s' % slow,	# PRG, +255 stays below $10000
		      '\t\tlea (a0,d6.w),a5', '\t\tbra.s %sF_%04X' % (v, t),
		      '%sVR_%04X:' % (v, t), '\t\tlea (a2,d6.w),a5']
		self.out += g + fast
		return True

	# ---- routines called with the 68000's jsr -------------------------------

	def routine_body(self, f, memo):
		"""(instructions, heavy) of a routine that can be called with the
		68000's jsr, or None. Its copy returns with rts, so every path
		must reach RTS with the stack as it was, and the routines it
		calls must be like it.
		A light routine never touches the 6502 stack, needs no NMI check
		and stays in translated code: its call doesn't push the return
		address. A heavy one may do those things: its call pushes the
		6502 return address like JSR does, and if it leaves its copy
		through rcDispatch (an NMI, a computed jump), that drops the
		68000 return addresses and the normal code takes over."""
		if f in memo:
			return memo[f]
		memo[f] = None			# recursion: not callable
		depth, work, heavy = {}, [(f, 0)], False
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
			if i.m in ('PHA', 'PHP', 'PLA', 'PLP'):
				heavy = True
				d += 1 if i.m[1] == 'H' else -1
				if d < 0:
					return None
			if i.m == 'RTS':
				if d:
					return None
				continue
			if i.m == 'JSR':
				if i.arg in self.insns:
					sub = self.routine_body(i.arg, memo)
					if sub is None:
						return None
					heavy |= sub[1]
				elif i.arg < 0x800:
					heavy = True	# a jump table in RAM, through rcDispatch
				else:
					return None
				work.append((pc + 3, d))
				continue
			for t in i.succ:
				if t is None or t not in self.insns:
					heavy = True	# through rcDispatch
				else:
					if t <= pc and not (i.mode == 'rel' and i.decided is None and pc in self.counted):
						heavy = True	# NMI check
					work.append((t, d))
		memo[f] = (set(depth), heavy)
		return memo[f]

	def emit_routine(self, f):
		pcs = sorted(self.callable[f][0])
		self.fast = {'pcs': set(pcs), 'prefix': 'R%04X' % f, 'routine': True, 'heavy': self.callable[f][1]}
		self.xc, self.c_skipped = False, 0
		self.out.append('')
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
		self.out += self.stubs
		self.stubs = []
		self.fast = None

	def fall_through(self, i, pcs, k):
		"""Jump to the next instruction if it isn't next in the output."""
		if i.mode == 'rel':
			if i.decided == 'taken':
				return
		elif i.m in ('JMP', 'RTS', 'RTI', 'BRK') or (i.m == 'JSR' and i.arg not in self.callable):
			return
		f = i.pc + i.n
		if k + 1 >= len(pcs) or pcs[k + 1] != f:
			self.e(*(['jmp %s' % self.lab(f)] if f in self.insns else ['move.w #$%04X,d4' % f, 'jmp rcDispatch']))

	def loop_entry(self, prev, plan):
		"""Fill or fast copy where the previous instruction falls into a loop."""
		p = self.insns[prev]
		pc = plan['t']
		if p.pc + p.n == pc and pc in p.succ:
			if 'lo' in plan:
				self.emit_fill(plan)
				self.versioned.append(pc)
			elif self.emit_versioned(plan):
				self.versioned.append(pc)

	def run(self, vectors):
		pcs = sorted(self.insns)
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
		memo = {}
		self.callable = {}
		for i in self.insns.values():
			if i.m == 'JSR' and i.arg in self.insns and self.routine_body(i.arg, memo):
				self.callable[i.arg] = memo[i.arg]
		self.called = set()
		self.returns = self.return_points()
		heads = set()
		for i in self.insns.values():
			if i.m == 'JMP' and i.mode == 'abs' and i.arg <= i.pc: heads.add(i.arg)
			if i.mode == 'rel' and i.decided != 'not' and i.arg <= i.pc and i.pc not in self.counted:
				heads.add(i.arg)
		plans = {}
		for i in self.insns.values():
			if i.mode == 'rel' and i.decided is None and i.arg < i.pc and i.arg not in plans:
				plan = self.fill_plan(i) or self.version_plan(i)
				if plan:
					plans[i.arg] = plan
		self.versioned = []
		self.plans = plans
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
					self.out += ['C_%04X:' % pc, '\t\ttst.w FamiMdVint(a4)', '\t\tbeq.s %s' % lab(pc),
						     '\t\tmove.w #$%04X,d4' % pc, '\t\tjsr rcNmi']
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
	user = list(extra)
	insns, vectors = discover(prg, extra)
	while True:
		found, rts = jump_tables(prg, insns)
		more = found - set(insns)
		if not more:
			break
		extra = list(extra) + sorted(more)
		insns, vectors = discover(prg, extra)
	tables = sorted(found)
	liveness(insns, {i.pc + 3 for i in insns.values() if i.m == 'JSR'} | set(extra), tables, user + sorted(rts))
	g = Gen(prg, insns)
	g.tables = tables
	entries = set(vectors) | set(extra) | {i.pc + 3 for i in insns.values() if i.m == 'JSR'}
	g.ranges = ranges(insns, entries)
	g.entries = entries
	g.run(vectors)
	with open(sys.argv[2], 'w') as f:
		f.write('; generated by tools/recomp6502.py from %s -- do not publish\n' % sys.argv[1].split('/')[-1])
		f.write('\n'.join(g.out) + '\n')
	print('recomp6502: %d instructions, %d bytes of 6502 code, %d loops versioned' %
	      (len(insns), sum(i.n for i in insns.values()), len(g.versioned)))


if __name__ == '__main__':
	main()
