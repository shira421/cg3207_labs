#!/usr/bin/env python3
"""
build.py - compile / assemble a program for the CG3207 Assignment 4 CPU into AA_IROM.mem and AA_DMEM.mem.

  python3 build.py demo/breakout.c                    -> build/ (+ copies into the Vivado project)
  python3 build.py prog.s --out somewhere --no-install

Needs the GNU RISC-V toolchain (Linux or WSL):  sudo apt install gcc-riscv64-unknown-elf
(.s files alone only need binutils-riscv64-unknown-elf.)

What it does
  1. crt0.s + your .c/.s files -> ELF (link.ld: .text in IROM at 0x00400000, everything else in DMEM at
     0x10010000, stack at the top of DMEM). C is compiled with -march=rv32im -Os.
  2. .text -> AA_IROM.mem, .data (constants, variables, zeroed bss) -> AA_DMEM.mem, one word per line.
  3. Writes the disassembly (program.lst) and, for each .c file, the generated assembly (<name>.s),
     which is what the submission asks for.
  4. Checks that the program only uses instructions this CPU implements and fits in IROM / DMEM.
  5. Unless --no-install: copies the .mem files to as4.srcs/sources_1/imports/as2 and sim_1/imports/as2.

AI assistance declaration (CG3207 lab manual): written with Claude (Anthropic), Claude Opus 5.5, Nov 2026.
"""
import argparse
import os
import re
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AS4 = os.path.dirname(HERE)
PREFIX = 'riscv64-unknown-elf-'
IROM_BYTES = 4096          # IROM_DEPTH_BITS = 12 in Wrapper.v
DMEM_BYTES = 4096          # DMEM_DEPTH_BITS = 12

# Every instruction the CPU executes (pseudo-instructions as objdump prints them map onto these).
SUPPORTED = set('''
lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu sb sh sw
addi slti sltiu xori ori andi slli srli srai add sub sll slt sltu xor srl sra or and
mul mulh mulhu div divu rem remu mret mulsr
nop li mv not neg seqz snez sltz sgtz beqz bnez blez bgez bltz bgtz bgt ble bgtu bleu j jr ret call tail
'''.split())


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(' '.join(cmd) + '\n' + r.stdout + r.stderr)
        sys.exit(1)
    return r.stdout


def words(data):
    data += b'\0' * (-len(data) % 4)
    return ['%08x' % w for w in struct.unpack('<%dI' % (len(data) // 4), data)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sources', nargs='+')
    ap.add_argument('--out', default=os.path.join(HERE, 'build'))
    ap.add_argument('--no-install', action='store_true', help='do not copy the .mem files into the Vivado project')
    ap.add_argument('--cflags', default='', help='extra compiler flags')
    ap.add_argument('--no-crt0', action='store_true', help='the program has its own _start in section .text.init')
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    elf = os.path.join(args.out, 'program.elf')
    common = ['-march=rv32im', '-mabi=ilp32']
    cflags = common + ['-Os', '-ffreestanding', '-fno-builtin', '-Wall', '-msmall-data-limit=0'] + args.cflags.split()

    srcs = ([] if args.no_crt0 else [os.path.join(HERE, 'crt0.s')]) + args.sources
    run([PREFIX + 'gcc'] + cflags + ['-nostdlib', '-nostartfiles', '-Wl,--no-relax', '-T', os.path.join(HERE, 'link.ld'),
                                     '-o', elf] + srcs + ['-lgcc'])
    for s in args.sources:
        if s.endswith('.c'):
            out_s = os.path.join(args.out, os.path.splitext(os.path.basename(s))[0] + '.s')
            run([PREFIX + 'gcc'] + cflags + ['-S', '-o', out_s, s])

    text_bin = os.path.join(args.out, 'text.bin')
    data_bin = os.path.join(args.out, 'data.bin')
    run([PREFIX + 'objcopy', '-O', 'binary', '-j', '.text', elf, text_bin])
    run([PREFIX + 'objcopy', '-O', 'binary', '-j', '.data', elf, data_bin])
    text = open(text_bin, 'rb').read()
    data = open(data_bin, 'rb').read()
    irom = os.path.join(args.out, 'AA_IROM.mem')
    dmem = os.path.join(args.out, 'AA_DMEM.mem')
    # Padded to the full memory size, so that every word has a defined initial value
    # (and Vivado / the simulator do not warn about a short file).
    iw, dw = words(text), words(data)
    iw += ['00000013'] * max(0, IROM_BYTES // 4 - len(iw))     # nops
    dw += ['00000000'] * max(0, DMEM_BYTES // 4 - len(dw))
    open(irom, 'w').write('\n'.join(iw) + '\n')
    open(dmem, 'w').write('\n'.join(dw) + '\n')

    lst = run([PREFIX + 'objdump', '-d', '-M', 'no-aliases', elf])
    open(os.path.join(args.out, 'program.lst'), 'w').write(run([PREFIX + 'objdump', '-d', '-S', elf]))
    bad = {}
    for line in lst.splitlines():
        m = re.match(r'\s*[0-9a-f]+:\s+[0-9a-f]{8}\s+(\S+)', line)
        if m and m.group(1) == '.insn':                 # custom-0: mulsr (funct3 000, funct7 = k < 32)
            w = int(re.search(r':\s+([0-9a-f]{8})', line).group(1), 16)
            if (w & 0x7F) == 0x0B and ((w >> 12) & 7) == 0 and (w >> 25) < 32:
                continue
        if m and m.group(1) not in SUPPORTED:
            bad.setdefault(m.group(1), line.strip())
    syms = run([PREFIX + 'nm', elf])
    stack_room = DMEM_BYTES - len(data)

    print('IROM: %d of %d bytes   DMEM: %d of %d bytes (%d left for the stack)' %
          (len(text), IROM_BYTES, len(data), DMEM_BYTES, stack_room))
    ok = True
    if bad:
        ok = False
        print('ERROR: instructions this CPU does not implement:')
        for k, v in bad.items():
            print('   ', v)
    if len(text) > IROM_BYTES or stack_room < 256:
        ok = False
        print('ERROR: program too large for IROM / DMEM (change *_DEPTH_BITS in Wrapper.v, link.ld and here)')
    if not ok:
        sys.exit(1)

    if not args.no_install:
        for sub in ('sources_1', 'sim_1'):
            d = os.path.join(AS4, 'as4.srcs', sub, 'imports', 'as2')
            shutil.copy(irom, d)
            shutil.copy(dmem, d)
        print('Copied AA_IROM.mem / AA_DMEM.mem into as4.srcs/{sources_1,sim_1}/imports/as2')
        print('In Vivado: re-run synthesis (it does not notice changed .mem files by itself).')


if __name__ == '__main__':
    main()
