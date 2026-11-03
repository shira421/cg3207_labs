#!/usr/bin/env python3
"""
run_tests.py - regression for the CG3207 Assignment 4 pipelined CPU.

Every test program is run on the RTL (Icarus Verilog, tb_cpu.v + the Vivado sources) and on the
reference model (iss.py). The final registers, the whole of DMEM and every MMIO store (address,
byte enables, data) must match exactly.

  python3 run_tests.py                 directed tests + 200 random programs, in every CPU mode
  python3 run_tests.py --fuzz 1000     more random programs
  python3 run_tests.py --keep          keep the work folders (waveform-free, but with all logs)

CPU modes (CPU_CTRL, forced by the testbench):
  0 everything on   1 no forwarding   2 no branch prediction   3 neither
  toggle: CPU_CTRL changed at random every few cycles while the program runs
  plus the HAZARD_UNIT = 0 pipeline (compulsory task), with every program padded with nops.

Random programs (fuzz.py) mix every implemented instruction, dependent chains, load-use pairs,
byte/half-word accesses, MMIO stores, mul/div, forward branches, counted loops, calls and jalr.

AI assistance declaration (CG3207 lab manual): written with Claude (Anthropic), Claude Opus 5.5, Nov 2026.
"""
import argparse
import glob
import os
import random
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
AS4 = os.path.dirname(HERE)
SRC = os.path.join(AS4, 'as4.srcs', 'sources_1', 'imports', 'as2')
sys.path.insert(0, HERE)
import iss            # noqa: E402
import fuzz           # noqa: E402

RTL = ['Wrapper.v', 'RV.v', 'HazardUnit.v', 'BranchPredictor.v', 'LoadStore.v', 'ALU.v', 'Shifter.v',
       'Decoder.v', 'Extend.v', 'PC_Logic.v', 'RegFile.v', 'ProgramCounter.v', 'MCycle.v']


def sh(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(' '.join(cmd) + '\n' + r.stdout + r.stderr)
    return r.stdout


def compile_rtl(work, nohazard):
    out = os.path.join(work, 'tb_nohazard.vvp' if nohazard else 'tb.vvp')
    cmd = ['iverilog', '-g2012', '-o', out, '-s', 'tb_cpu'] + (['-DNOHAZARD'] if nohazard else [])
    sh(cmd + [os.path.join(HERE, 'tb_cpu.v')] + [os.path.join(SRC, f) for f in RTL])
    return out


def build(src, d, crt0=False):
    os.makedirs(d, exist_ok=True)
    cmd = [sys.executable, os.path.join(AS4, 'sw', 'build.py'), src, '--no-install', '--out', d]
    if not crt0:
        cmd.append('--no-crt0')
    sh(cmd)


def run_rtl(vvp, d, plusargs=()):
    for f in ('mmio.txt', 'regs.txt', 'dmem.txt', 'stats.txt'):
        if os.path.exists(os.path.join(d, f)):
            os.remove(os.path.join(d, f))
    sh(['vvp', '-n', vvp] + list(plusargs), cwd=d)
    stats = {}
    for line in open(os.path.join(d, 'stats.txt')):
        k, v = line.split()
        stats[k] = int(v.replace('x', '0').replace('z', '0'), 16) if k in ('sevenseg', 'led') else int(v)
    return stats


def compare(d, ref, dmem_words=None, skip_mmio=()):
    errs = []
    regs = [int(l, 16) if 'x' not in l and 'z' not in l else -1 for l in open(os.path.join(d, 'regs.txt'))]
    for i in range(32):
        if regs[i] != ref.x[i]:
            errs.append('x%d = %08x, expected %08x' % (i, regs[i], ref.x[i]))
    dm = [int(l, 16) if 'x' not in l and 'z' not in l else -1 for l in open(os.path.join(d, 'dmem.txt'))]
    for i, (a, b) in enumerate(list(zip(dm, ref.dmem))[:dmem_words]):
        if a != b:
            errs.append('DMEM[0x%08x] = %08x, expected %08x' % (iss.DMEM_BASE + 4 * i, a & 0xFFFFFFFF, b))
            if len(errs) > 12:
                break
    log = []
    for l in open(os.path.join(d, 'mmio.txt')):
        a, m, v = l.split()
        log.append((int(a, 16), int(m, 16), int(v, 16)))
    log = [e for e in log if e[0] not in skip_mmio]
    if log != ref.mmio_log:
        for k, (x, y) in enumerate(zip(log + [None] * len(ref.mmio_log), ref.mmio_log + [None] * len(log))):
            if x != y:
                errs.append('MMIO store #%d: got %s, expected %s' % (k, x, y))
                break
    return errs


def check(name, src_dir, vvps, modes, max_steps, results):
    ref = iss.ISS(src_dir)
    if not ref.run(max_steps):
        results.append((name, 'reference model did not halt'))
        return None
    stats_all = {}
    for mode in modes:
        vvp = vvps['nohazard'] if mode == 'nohazard' else vvps['normal']
        plus = ['+max=%d' % (ref.cycles * 45 + 2000), '+haltpc=%08x' % ref.pc]
        if mode == 'toggle':
            plus.append('+toggle')
        elif mode != 'nohazard':
            plus.append('+cpuctrl=%d' % mode)
        st = run_rtl(vvp, src_dir, plus)
        errs = [] if st['halted'] else ['did not halt in %d cycles' % st['cycles']]
        errs += compare(src_dir, ref)
        if errs:
            results.append(('%s [mode %s]' % (name, mode), '; '.join(errs[:6])))
        stats_all[mode] = st
    return stats_all


def check_irq(seed, work, vvps, results):
    """A random program interrupted by push-button presses at random times. The handler saves
    and restores what it uses, so everything the program computes must come out exactly as
    without interrupts, and the handler must have run once per press."""
    d = os.path.join(work, 'irq_%d' % seed)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, 'prog.s'), 'w').write(fuzz.generate(seed, irq=True))
    build(os.path.join(d, 'prog.s'), d)
    ref = iss.ISS(d)
    if not ref.run(200000):
        results.append(('irq seed %d' % seed, 'reference model did not halt'))
        return 0
    rnd = random.Random(seed)
    presses, t = [], 60 + rnd.randrange(40)
    while t < ref.cycles:                   # the RTL takes well over 1 cycle per instruction
        presses.append(t)
        t += 120 + rnd.randrange(200)
    script = os.path.join(d, 'pb.txt')
    with open(script, 'w') as f:
        for t in presses:
            f.write('%d %d\n%d 0\n' % (t, 1 << rnd.randrange(3), t + 12 + rnd.randrange(20)))
    buf_words = fuzz.BUF // 4
    for mode in (0, 1, 2, 3, 'toggle'):
        st = run_rtl(vvps['normal'], d, ['+max=%d' % (ref.cycles * 60 + 5000), '+haltpc=%08x' % ref.pc,
                                          '+toggle' if mode == 'toggle' else '+cpuctrl=%d' % mode, '+pb=pb.txt'])
        errs = [] if st['halted'] else ['did not halt']
        errs += compare(d, ref, dmem_words=buf_words, skip_mmio=(0xFFFF0078,))
        count = int(open(os.path.join(d, 'dmem.txt')).read().split()[buf_words], 16)
        if count != len(presses) or st['interrupts'] != len(presses):
            errs.append('%d presses, handler ran %d times, %d interrupts taken' % (len(presses), count, st['interrupts']))
        if errs:
            results.append(('irq seed %d [mode %s]' % (seed, mode), '; '.join(errs[:6])))
    return len(presses)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--fuzz', type=int, default=200)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--irq', type=int, default=40, help='number of random programs run with interrupts')
    ap.add_argument('--keep', action='store_true')
    ap.add_argument('--only', default=None, help='run only directed tests whose name contains this')
    args = ap.parse_args()

    work = tempfile.mkdtemp(prefix='as4_tests_')
    vvps = {'normal': compile_rtl(work, False), 'nohazard': compile_rtl(work, True)}
    results = []
    totals = {}

    # Directed tests (tests/*.s); each is also run padded with nops on the HAZARD_UNIT = 0 pipeline
    for src in sorted(glob.glob(os.path.join(HERE, 'tests', '*.s'))):
        name = os.path.splitext(os.path.basename(src))[0]
        if args.only and args.only not in name:
            continue
        d = os.path.join(work, name)
        build(src, d)
        st = check(name, d, vvps, [0, 1, 2, 3], 200000, results)
        if st:
            print('%-24s cycles: all on %6d | no fwd %6d | no BP %6d | neither %6d   (%d instructions)' %
                  (name, st[0]['cycles'], st[1]['cycles'], st[2]['cycles'], st[3]['cycles'], st[0]['instructions']))
        padded = os.path.join(work, name + '_nops.s')
        open(padded, 'w').write(fuzz.pad_with_nops(open(src).read()))
        d2 = os.path.join(work, name + '_nops')
        build(padded, d2)
        check(name + ' (HAZARD_UNIT=0, nops)', d2, vvps, ['nohazard'], 200000, results)

    # Interrupts
    if not args.only:
        rnd = random.Random(args.seed + 1000)
        n = sum(check_irq(rnd.randrange(1 << 30), work, vvps, results) for _ in range(args.irq))
        print('Interrupt tests: %d programs, %d button presses, %d failures' % (args.irq, n, len(results)))

    # Random programs
    if not args.only:
        rnd = random.Random(args.seed)
        for k in range(args.fuzz):
            seed = rnd.randrange(1 << 30)
            prog = fuzz.generate(seed)
            d = os.path.join(work, 'fuzz_%d' % seed)
            os.makedirs(d, exist_ok=True)
            open(os.path.join(d, 'prog.s'), 'w').write(prog)
            build(os.path.join(d, 'prog.s'), d)
            if k % 4 == 0:
                open(os.path.join(d, 'prog_nops.s'), 'w').write(fuzz.pad_with_nops(prog))
                d2 = d + '_nops'
                try:
                    build(os.path.join(d, 'prog_nops.s'), d2)
                    check('fuzz seed %d (nops)' % seed, d2, vvps, ['nohazard'], 200000, results)
                except RuntimeError as e:      # 4x longer with the nops: may not fit in IROM
                    if 'overflowed' not in str(e):
                        raise
            st = check('fuzz seed %d' % seed, d, vvps, [0, 1, 2, 3, 'toggle'], 200000, results)
            if st:
                for m, s in st.items():
                    if m == 'toggle':
                        continue
                    t = totals.setdefault(m, [0, 0])
                    t[0] += s['cycles']
                    t[1] += s['instructions']
            if not args.keep and not any(seed_s in r[0] for r in results for seed_s in [str(seed)]):
                shutil.rmtree(d, ignore_errors=True)
                shutil.rmtree(d + '_nops', ignore_errors=True)
            if (k + 1) % 50 == 0:
                print('  %d random programs done, %d failures so far' % (k + 1, len(results)))
        if totals:
            print('Random programs, CPI: ' + ', '.join(
                '%s %.3f' % ({0: 'all on', 1: 'no fwd', 2: 'no BP', 3: 'neither'}[m], c / max(i, 1))
                for m, (c, i) in sorted(totals.items())))

    print()
    if results:
        print('FAILURES (%d):' % len(results))
        for n, e in results[:30]:
            print('  ', n, ':', e)
        print('work folder:', work)
        sys.exit(1)
    print('ALL PASS')
    if args.keep:
        print('work folder:', work)
    else:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main()
