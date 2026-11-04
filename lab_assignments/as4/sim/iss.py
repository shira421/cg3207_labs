#!/usr/bin/env python3
"""
iss.py - instruction set simulator (reference model) for the CG3207 Assignment 4 CPU.

Runs AA_IROM.mem / AA_DMEM.mem the way the RISC-V specification says, one instruction at a time,
with the same memory map as Wrapper.v. The RTL testbench's results (registers, DMEM, every MMIO
write) are compared against this, so it is deliberately simple: no pipeline, no timing.

  python3 iss.py <dir with AA_IROM.mem and AA_DMEM.mem> [--max N] [--dip 0x1234]

AI assistance declaration (CG3207 lab manual): written with Claude (Anthropic), Claude Opus 5.5, Nov 2026.
"""
import argparse
import os
import sys

M32 = 0xFFFFFFFF
IROM_BASE, DMEM_BASE, MMIO_BASE = 0x00400000, 0x10010000, 0xFFFF0000
HALT = 0x0000006F           # j .  (jal x0, 0): the programs end with it


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def load_mem(path):
    out = []
    for line in open(path):
        line = line.split('//')[0].strip()
        if line:
            out += [int(w, 16) for w in line.split()]
    return out


class ISS:
    def __init__(self, d, irom_bits=12, dmem_bits=12, dip=0, pb=0):
        self.irom = load_mem(os.path.join(d, 'AA_IROM.mem'))
        dm = load_mem(os.path.join(d, 'AA_DMEM.mem'))
        self.dmem_words = 1 << (dmem_bits - 2)
        self.irom_words = 1 << (irom_bits - 2)
        self.dmem = (dm + [0] * self.dmem_words)[:self.dmem_words]
        self.x = [0] * 32
        self.pc = IROM_BASE
        self.dip, self.pb = dip, pb
        self.mmio_log = []      # (address, byte mask, data with only the written lanes kept)
        self.cycles = 0
        self.epc = 0

    # ---------------------------------------------------------------- memory
    def fetch(self, pc):
        i = (pc - IROM_BASE) >> 2
        if pc & 3 or not 0 <= i < self.irom_words:
            return 0x00000013
        return self.irom[i] if i < len(self.irom) else 0

    def read_word(self, a):
        if DMEM_BASE <= a < DMEM_BASE + 4 * self.dmem_words:
            return self.dmem[(a - DMEM_BASE) >> 2]
        if a >= MMIO_BASE:
            off = a & 0xFF
            return {0x64: self.dip, 0x68: self.pb, 0xA0: self.cycles & M32, 0x08: 1, 0x30: 0}.get(off, 0)
        return 0

    def write(self, a, mask, data):
        wa = a & ~3
        if DMEM_BASE <= wa < DMEM_BASE + 4 * self.dmem_words:
            i = (wa - DMEM_BASE) >> 2
            w = self.dmem[i]
            for b in range(4):
                if mask >> b & 1:
                    w = (w & ~(0xFF << 8 * b)) | (data & (0xFF << 8 * b))
            self.dmem[i] = w & M32
        elif wa >= MMIO_BASE:
            keep = sum(0xFF << 8 * b for b in range(4) if mask >> b & 1)
            self.mmio_log.append((wa, mask, data & keep))

    # ---------------------------------------------------------------- execution
    def step(self):
        pc, ins = self.pc, self.fetch(self.pc)
        x = self.x
        op, rd, f3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
        rs1, rs2, f7 = (ins >> 15) & 31, (ins >> 20) & 31, ins >> 25
        a, b = x[rs1], x[rs2]
        imm_i = sx(ins >> 20, 12)
        imm_s = sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
        imm_b = sx(((ins >> 31) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 63) << 5) | (((ins >> 8) & 15) << 1), 13)
        imm_u = ins & 0xFFFFF000
        imm_j = sx(((ins >> 31) << 20) | (((ins >> 12) & 255) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 1023) << 1), 21)
        npc = (pc + 4) & M32
        res = None

        if op == 0x37:
            res = imm_u
        elif op == 0x17:
            res = (pc + imm_u) & M32
        elif op == 0x6F:
            res, npc = (pc + 4) & M32, (pc + imm_j) & M32
        elif op == 0x67:
            res, npc = (pc + 4) & M32, (a + imm_i) & M32 & ~1
        elif op == 0x63:
            sa, sb = sx(a, 32), sx(b, 32)
            t = {0: a == b, 1: a != b, 4: sa < sb, 5: sa >= sb, 6: a < b, 7: a >= b}.get(f3, False)
            if t:
                npc = (pc + imm_b) & M32
        elif op == 0x03:
            addr = (a + imm_i) & M32
            w = self.read_word(addr & ~3)
            sh = 8 * (addr & 3)
            if f3 == 0: res = sx(w >> sh, 8) & M32
            elif f3 == 1: res = sx(w >> sh, 16) & M32
            elif f3 == 2: res = w
            elif f3 == 4: res = (w >> sh) & 0xFF
            elif f3 == 5: res = (w >> sh) & 0xFFFF
            else: res = w
        elif op == 0x23:
            addr = (a + imm_s) & M32
            if f3 == 0:
                self.write(addr, 1 << (addr & 3), (b & 0xFF) * 0x01010101)
            elif f3 == 1:
                self.write(addr, 0b1100 if addr & 2 else 0b0011, (b & 0xFFFF) * 0x00010001)
            else:
                self.write(addr, 0b1111, b)
        elif op == 0x13 or (op == 0x33 and f7 != 1):
            bb = imm_i & M32 if op == 0x13 else b
            sub = op == 0x33 and (f7 & 0x20)
            sh = bb & 31
            if f3 == 0: res = a - bb if sub else a + bb
            elif f3 == 1: res = a << sh
            elif f3 == 2: res = int(sx(a, 32) < sx(bb, 32))
            elif f3 == 3: res = int(a < (bb & M32))
            elif f3 == 4: res = a ^ bb
            elif f3 == 5: res = (sx(a, 32) >> sh) if (f7 & 0x20) else (a >> sh)
            elif f3 == 6: res = a | bb
            else: res = a & bb
            res &= M32
        elif op == 0x33 and f7 == 1:
            sa, sb = sx(a, 32), sx(b, 32)
            if f3 == 0: res = (a * b) & M32
            elif f3 == 1: res = ((sa * sb) >> 32) & M32
            elif f3 == 3: res = ((a * b) >> 32) & M32
            elif f3 == 4:
                if b == 0: res = M32
                elif sa == -2**31 and sb == -1: res = a
                else: res = int(abs(sa) // abs(sb) * (1 if (sa < 0) == (sb < 0) else -1)) & M32
            elif f3 == 5: res = M32 if b == 0 else a // b
            elif f3 == 6:
                if b == 0: res = a
                elif sa == -2**31 and sb == -1: res = 0
                else: res = int(abs(sa) % abs(sb) * (-1 if sa < 0 else 1)) & M32
            elif f3 == 7: res = a if b == 0 else a % b
            # f3 == 2 (mulhsu) is not implemented in the CPU: a NOP
        elif op == 0x0B and f3 == 0 and f7 < 32:      # mulsr rd, rs1, rs2, k = (rs1 * rs2) >> k, signed
            res = ((sx(a, 32) * sx(b, 32)) >> f7) & M32
        elif op == 0x73 and ins == 0x30200073:
            npc = self.epc
        # anything else: NOP, as the Decoder does

        if res is not None and rd:
            x[rd] = res & M32
        self.pc = npc
        self.cycles += 1
        return ins

    def run(self, max_steps=200000):
        for _ in range(max_steps):
            if self.fetch(self.pc) == HALT:
                return True
            self.step()
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir')
    ap.add_argument('--max', type=int, default=200000)
    ap.add_argument('--dip', type=lambda s: int(s, 0), default=0)
    args = ap.parse_args()
    s = ISS(args.dir, dip=args.dip)
    done = s.run(args.max)
    print('halted' if done else 'did not halt', 'after', s.cycles, 'instructions')
    for i in range(0, 32, 4):
        print('  '.join('x%-2d %08x' % (j, s.x[j]) for j in range(i, i + 4)))


if __name__ == '__main__':
    main()
