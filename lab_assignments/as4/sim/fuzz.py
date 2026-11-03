#!/usr/bin/env python3
"""
fuzz.py - random test programs for the Assignment 4 CPU (used by run_tests.py).

Each program is valid and terminating by construction: it only branches forward, except for
counted loops (counter in x8) and calls (link in x6) whose bodies cannot touch those registers.
Sources are biased towards registers written by the previous few instructions, so that there are
plenty of back-to-back dependencies for forwarding and load-use stalls, and loads/stores of every
size go to a buffer in DMEM (base x9) and to the 7-segment / LED registers (base x7).
Every pseudo-instruction used expands to exactly one instruction, so pad_with_nops() can make any
program safe for the HAZARD_UNIT = 0 pipeline.

  python3 fuzz.py SEED      print one program

AI assistance declaration (CG3207 lab manual): written with Claude (Anthropic), Claude Opus 5.5, Nov 2026.
"""
import random
import re
import sys

RESERVED = {0, 6, 7, 8, 9}          # x6 link, x7 MMIO base, x8 loop counter, x9 DMEM buffer base
FREE = [r for r in range(1, 32) if r not in RESERVED]
BUF = 512                           # bytes of the DMEM test buffer

R_OPS = ['add', 'sub', 'and', 'or', 'xor', 'sll', 'srl', 'sra', 'slt', 'sltu']
I_OPS = ['addi', 'andi', 'ori', 'xori', 'slti', 'sltiu']
SH_OPS = ['slli', 'srli', 'srai']
M_OPS = ['mul', 'mulh', 'mulhu', 'div', 'divu', 'rem', 'remu']
BR_OPS = ['beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu']
LOADS = [('lb', 1), ('lh', 2), ('lw', 4), ('lbu', 1), ('lhu', 2)]
STORES = [('sb', 1), ('sh', 2), ('sw', 4)]


class Gen:
    def __init__(self, seed, free=FREE):
        self.free = free
        self.r = random.Random(seed)
        self.out = []
        self.recent = []
        self.label = 0
        self.subs = []

    def lab(self):
        self.label += 1
        return 'L%d' % self.label

    def emit(self, s):
        self.out.append('    ' + s)

    def dst(self, exclude=()):
        d = self.r.choice([x for x in self.free if x not in exclude])
        self.recent = ([d] + self.recent)[:4]
        return d

    def src(self):
        if self.recent and self.r.random() < 0.6:
            return self.r.choice(self.recent)
        return self.r.choice(self.free + [0])

    def imm12(self):
        return self.r.choice([0, 1, -1, 2047, -2048, self.r.randint(-2048, 2047), self.r.randint(-16, 16)])

    def simple(self, exclude=()):
        """One instruction that does not change control flow."""
        r = self.r
        k = r.random()
        if k < 0.25:
            s1, s2 = self.src(), self.src()
            self.emit('%s x%d, x%d, x%d' % (r.choice(R_OPS), self.dst(exclude), s1, s2))
        elif k < 0.42:
            s1 = self.src()
            self.emit('%s x%d, x%d, %d' % (r.choice(I_OPS), self.dst(exclude), s1, self.imm12()))
        elif k < 0.48:
            s1 = self.src()
            self.emit('%s x%d, x%d, %d' % (r.choice(SH_OPS), self.dst(exclude), s1, r.randint(0, 31)))
        elif k < 0.52:
            self.emit('lui x%d, 0x%x' % (self.dst(exclude), r.randrange(1 << 20)))
        elif k < 0.54:
            self.emit('auipc x%d, 0x%x' % (self.dst(exclude), r.randrange(1 << 20)))
        elif k < 0.62:
            s1, s2 = self.src(), self.src()
            self.emit('%s x%d, x%d, x%d' % (r.choice(M_OPS), self.dst(exclude), s1, s2))
        elif k < 0.78:
            op, size = r.choice(LOADS)
            d = self.dst(exclude)
            self.emit('%s x%d, %d(x9)' % (op, d, r.randrange(0, BUF, size)))
            if r.random() < 0.5:        # load-use
                s2 = self.src()
                self.emit('%s x%d, x%d, x%d' % (r.choice(R_OPS), self.dst(exclude), d, s2))
        elif k < 0.92:
            op, size = r.choice(STORES)
            self.emit('%s x%d, %d(x9)' % (op, self.src(), r.randrange(0, BUF, size)))
        else:
            op, size = r.choice(STORES)
            off = r.choice([0x80, 0x60]) + r.randrange(0, 4, size)
            self.emit('%s x%d, %d(x7)' % (op, self.src(), off))

    def block(self, n, depth=0, exclude=()):
        r = self.r
        for _ in range(n):
            k = r.random()
            if k < 0.10:                          # forward branch over a few instructions
                L = self.lab()
                self.emit('%s x%d, x%d, %s' % (r.choice(BR_OPS), self.src(), self.src(), L))
                for _ in range(r.randint(0, 3)):
                    self.simple(exclude)
                self.out.append(L + ':')
            elif k < 0.15 and depth == 0:         # counted loop
                L = self.lab()
                self.emit('addi x8, x0, %d' % r.randint(1, 7))
                self.out.append(L + ':')
                self.block(r.randint(1, 6), depth + 1, exclude)
                self.emit('addi x8, x8, -1')
                self.emit('bne x8, x0, %s' % L)
            elif k < 0.18 and depth == 0:         # call a subroutine
                L = 'S%d' % len(self.subs)
                self.subs.append(L)
                self.emit('jal x6, %s' % L)
            elif k < 0.20:                        # jal forward
                L = self.lab()
                self.emit('jal x%d, %s' % (self.dst(exclude), L))
                self.simple(exclude)
                self.out.append(L + ':')
            else:
                self.simple(exclude)

    def program(self, irq=False):
        r = self.r
        o = self.out
        o += ['    .section .text.init, "ax"', '    .globl _start', '_start:']
        if irq:
            # interrupt vector at _start + 4; sp (x2) is reserved for the handler's stack
            o += ['    j main', '    j isr', 'main:',
                  '    lui x2, %hi(stack_top)', '    addi x2, x2, %lo(stack_top)',
                  '    lui x7, 0xFFFF0', '    addi x5, x0, 7', '    sw x5, 0x74(x7)']   # INT_EN = all buttons
        o += ['    lui x9, %hi(buf)', '    addi x9, x9, %lo(buf)', '    lui x7, 0xFFFF0']
        for x in self.free:                       # random register values
            self.emit('lui x%d, 0x%x' % (x, r.randrange(1 << 20)))
            self.emit('addi x%d, x%d, %d' % (x, x, r.randint(-2048, 2047)))
        self.block(r.randint(200, 400) if irq else r.randint(30, 90))
        o.append('end:')
        self.emit('j end')
        for L in self.subs:
            o.append(L + ':')
            self.block(r.randint(1, 8), 1, exclude=(6,))
            if r.random() < 0.5:
                self.emit('addi x6, x6, 0')       # jalr right after its base is computed
            self.emit('jalr x0, 0(x6)')
        if irq:
            # The handler must leave every register as it was: it uses the stack, counts the
            # interrupts in irq_count and acknowledges every button.
            o += ['isr:',
                  '    addi x2, x2, -12', '    sw x5, 0(x2)', '    sw x6, 4(x2)', '    sw x7, 8(x2)',
                  '    lui x5, %hi(irq_count)', '    addi x5, x5, %lo(irq_count)',
                  '    lw x6, 0(x5)', '    addi x6, x6, 1', '    sw x6, 0(x5)',
                  '    lui x7, 0xFFFF0', '    addi x6, x0, 7', '    sw x6, 0x78(x7)',
                  '    lw x7, 8(x2)', '    lw x6, 4(x2)', '    lw x5, 0(x2)', '    addi x2, x2, 12',
                  '    mret']
        o += ['', '    .data', 'buf:']
        o += ['    .word 0x%08x' % r.randrange(1 << 32) for _ in range(BUF // 4)]
        if irq:
            o += ['irq_count: .word 0', '    .space 256', 'stack_top:']
        return '\n'.join(o) + '\n'


def generate(seed, irq=False):
    if irq:
        return Gen(seed, [x for x in FREE if x != 2]).program(irq=True)
    return Gen(seed).program()


def pad_with_nops(text, n=3):
    """3 nops after every instruction: enough for every hazard on the HAZARD_UNIT = 0 pipeline
    (dependent instructions 3 apart; the 2 instructions after a taken branch are nops)."""
    out, in_text = [], True
    for line in text.splitlines():
        out.append(line)
        s = line.split('#')[0].strip()
        if s.startswith('.'):
            if s.startswith('.data') or s.startswith('.section .data'):
                in_text = False
            elif s.startswith('.text') or s.startswith('.section .text'):
                in_text = True
            continue
        if in_text and s and not re.match(r'^[\w.]+:$', s):
            out += ['    nop'] * n
    return '\n'.join(out) + '\n'


if __name__ == '__main__':
    print(generate(int(sys.argv[1]) if len(sys.argv) > 1 else 1))
