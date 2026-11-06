#!/usr/bin/env python3
"""
make_figures.py - draws the charts and waveform figures in docs/media.

  python3 make_figures.py [--vcd enh.vcd] [--out ../media]

Without --vcd only the charts that need no simulation are drawn (pipeline timing, performance).
The VCD comes from the Assignment 4 enhancement testbench run with Icarus Verilog plus a dump module:

  module dump; initial begin $dumpfile("enh.vcd"); $dumpvars(0, tb_all_enhancements.CLK);
    $dumpvars(1, tb_all_enhancements.fast.dut); $dumpvars(1, tb_all_enhancements.slow.dut);
    $dumpvars(1, tb_all_enhancements.nopred.dut); end endmodule

  iverilog -g2012 -s tb_all_enhancements -s dump -o all.vvp tb_all_enhancements.v dump.v <CPU .v files>
  vvp -n all.vvp        (with AA_IROM.mem / AA_DMEM.mem in the current directory)

Needs matplotlib.
"""
import argparse
import os
import re

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Polygon, Rectangle, FancyArrowPatch  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, '..', '..')
ASM = os.path.join(REPO, 'lab_assignments', 'as4', 'testbench_enhancements.asm')

STAGE = {'F': '#4C78A8', 'D': '#72B7B2', 'E': '#F58518', 'M': '#E45756', 'W': '#54A24B'}
INK = '#1f2328'
MUTED = '#656d76'
GRID = '#d0d7de'
HL = '#fde2c4'        # highlighted bus segment
BUS = '#eef1f4'

plt.rcParams.update({
    'font.family': 'DejaVu Sans', 'font.size': 10, 'axes.edgecolor': GRID, 'text.color': INK,
    'axes.labelcolor': INK, 'xtick.color': MUTED, 'ytick.color': MUTED, 'savefig.facecolor': 'white',
})


def save(fig, out, name):
    path = os.path.join(out, name)
    fig.savefig(path, dpi=200, bbox_inches='tight', pad_inches=0.15)
    plt.close(fig)
    print('wrote', path)


# ------------------------------------------------------------------ pipeline timing charts
def pipeline_charts(out):
    """Forwarding, load-use stall and a mispredicted branch, as cycle-by-stage grids."""
    panels = [
        ('Forwarding: no cycles lost', [
            ('add  x1, x2, x3', 'FDEMW', 0),
            ('sub  x4, x1, x5', 'FDEMW', 1),
            ('or   x6, x1, x7', 'FDEMW', 2),
            ('and  x8, x1, x9', 'FDEMW', 3),
        ], {1: 'x1 forwarded from M', 2: 'x1 forwarded from W', 3: 'x1 read in D as W writes it'}, 9),
        ('Load-use (also mul / mulsr): 1 cycle lost', [
            ('lw   x1, 0(x2)', 'FDEMW', 0),
            ('add  x3, x1, x4', 'FDsEMW', 1),
            ('next', 'FsDEMW', 2),
        ], {1: 'waits in D, then x1 from W'}, 9),
        ('Mispredicted branch: 2 cycles lost', [
            ('beq  (taken)', 'FDEMW', 0),
            ('wrong path +4', 'FDx', 1),
            ('wrong path +8', 'Fx', 2),
            ('branch target', 'FDEMW', 3),
        ], {0: 'predicted not taken, resolved in E', 3: 'fetched after the redirect'}, 9),
    ]
    fig, axes = plt.subplots(len(panels), 1, figsize=(10.5, 7.6),
                             gridspec_kw={'height_ratios': [len(p[1]) + 1.2 for p in panels], 'hspace': 0.55})
    for ax, (title, rows, arrows, ncyc) in zip(axes, panels):
        n = len(rows)
        label_w = 3.2
        ax.set_xlim(-label_w, ncyc + 2.6)
        ax.set_ylim(n, -1.0)
        ax.axis('off')
        ax.set_title(title, loc='left', fontsize=11, fontweight='bold', color=INK, pad=4)
        for c in range(ncyc - 1):
            ax.text(c + 0.5, -0.55, str(c + 1), ha='center', va='center', color=MUTED, fontsize=8.5)
        pos = {}
        for r, (text, stages, start) in enumerate(rows):
            ax.text(-label_w + 0.1, r + 0.5, text, ha='left', va='center', family='DejaVu Sans Mono', fontsize=9)
            c = start
            prev = None
            for s in stages:
                if s == 's':                 # stall: the previous stage again
                    ax.add_patch(Rectangle((c + 0.04, r + 0.08), 0.92, 0.84, facecolor='white',
                                           edgecolor=STAGE[prev], hatch='////', lw=1.2))
                    ax.text(c + 0.5, r + 0.5, prev, ha='center', va='center', color=STAGE[prev], fontweight='bold')
                elif s == 'x':               # flushed
                    ax.add_patch(Rectangle((c + 0.04, r + 0.08), 0.92, 0.84, facecolor='#f6f8fa',
                                           edgecolor=GRID, lw=1))
                    ax.text(c + 0.5, r + 0.5, 'flush', ha='center', va='center', color=MUTED, fontsize=8)
                    break
                else:
                    ax.add_patch(Rectangle((c + 0.04, r + 0.08), 0.92, 0.84, facecolor=STAGE[s], edgecolor='none'))
                    ax.text(c + 0.5, r + 0.5, s, ha='center', va='center', color='white', fontweight='bold')
                    pos[(r, s)] = c
                    prev = s
                c += 1
        for r, note in arrows.items():
            end = rows[r][2] + len(rows[r][1].split('x')[0]) + (1 if 'x' in rows[r][1] else 0)
            ax.text(end + 0.15, r + 0.5, note, ha='left', va='center', fontsize=8.5, color=MUTED)
    save(fig, out, 'pipeline_timing.png')


# ------------------------------------------------------------------ performance chart
PERF = [  # (label, cycles per frame) from simulation of the demo, same program, switches flipped live
    ('Everything on', 953_584),
    ('SW1: no branch prediction', 1_154_544),
    ('SW0: no forwarding', 1_449_056),
    ('SW0 + SW1', 1_573_600),
    ('SW3: no mulsr (mul + mulh + shifts)', 1_967_776),
    ('SW2: A3 multi-cycle multiplier', 8_862_960),
    ('SW2 + SW1 + SW0', 9_400_592),
    ('SW3 + SW2', 17_786_016),
    ('All four off', 18_880_880),
]


def perf_chart(out):
    fig, ax = plt.subplots(figsize=(9.2, 4.4))
    labels = [p[0] for p in PERF][::-1]
    vals = [p[1] / 1e6 for p in PERF][::-1]
    base = PERF[0][1]
    colours = ['#54A24B' if l == 'Everything on' else ('#E45756' if ('SW2' in l or 'All' in l) else '#F58518') for l in labels]
    bars = ax.barh(labels, vals, color=colours, height=0.62)
    for b, (l, v) in zip(bars, zip(labels, vals)):
        cyc = v * 1e6
        fps = 50e6 / cyc
        ax.text(b.get_width() + 0.25, b.get_y() + b.get_height() / 2,
                '%.1fx   %.1f fps' % (cyc / base, fps), va='center', fontsize=9, color=INK)
    ax.set_xlabel('cycles per frame (millions)   ·   fps at 50 MHz')
    ax.set_xlim(0, 24)
    ax.spines[['top', 'right', 'left']].set_visible(False)
    ax.tick_params(axis='y', length=0, labelsize=9.5, labelcolor=INK)
    ax.grid(axis='x', color=GRID, lw=0.6)
    ax.set_axisbelow(True)
    ax.set_title('One 96x64 fractal frame, same program and bitstream, enhancements switched off live',
                 loc='left', fontsize=11, fontweight='bold')
    save(fig, out, 'performance.png')


# ------------------------------------------------------------------ waveforms
def asm_names():
    names = {}
    for line in open(ASM):
        m = re.search(r'#\s*PC=0x([0-9a-fA-F]+)', line)
        if not m:
            continue
        code, _, comment = line.partition('#')
        code = code.strip()
        extra = re.search(r';\s*(mulsr[^;]*)', comment)
        if code.startswith('.word') and extra:
            code = extra.group(1).strip()
        parts = code.replace(',', ' ').split()
        if not parts:
            continue
        short = parts[0] if len(parts) == 1 or parts[0] in ('j', 'nop') else '%s %s' % (parts[0], parts[1])
        names[int(m.group(1), 16)] = short
    return names


class Cycles:
    """Values sampled once per clock cycle (just after each rising edge)."""

    def __init__(self, v, core, t0_ns, t1_ns, period=10, edge=5):
        self.v, self.core = v, core
        first = t0_ns - ((t0_ns - edge) % period)
        self.edges = list(range(int(first), int(t1_ns), period))
        self.period = period

    def s(self, sig, e):
        return self.v.value('tb_all_enhancements.%s.dut.%s' % (self.core, sig), int((e + 1) * 1000))


def draw_bus(ax, y, segs, h=0.34, fontsize=8.5):
    """segs: [(t0, t1, label or None, highlighted)] merged where equal."""
    merged = []
    for s in segs:
        if merged and merged[-1][2] == s[2] and merged[-1][3] == s[3] and merged[-1][1] == s[0]:
            merged[-1] = (merged[-1][0], s[1], s[2], s[3])
        else:
            merged.append(s)
    for t0, t1, lab, hi in merged:
        d = min(1.2, (t1 - t0) / 4)
        poly = [(t0, y), (t0 + d, y + h), (t1 - d, y + h), (t1, y), (t1 - d, y - h), (t0 + d, y - h)]
        ax.add_patch(Polygon(poly, closed=True, facecolor=HL if hi else (BUS if lab else 'white'),
                             edgecolor=INK if lab else GRID, lw=0.9))
        if lab:
            ax.text((t0 + t1) / 2, y, lab, ha='center', va='center', fontsize=fontsize,
                    family='DejaVu Sans Mono', color=INK, clip_on=True)


def draw_bit(ax, y, segs, h=0.3, colour=INK):
    xs, ys = [], []
    for t0, t1, val in segs:
        yy = y - h if val else y + h
        xs += [t0, t1]
        ys += [yy, yy]
    ax.plot(xs, ys, color=colour, lw=1.4, drawstyle='default', solid_joinstyle='miter')
    for t0, t1, val in segs:
        if val:
            ax.add_patch(Rectangle((t0, y - h), t1 - t0, 2 * h, facecolor=colour, alpha=0.12, edgecolor='none'))


def draw_clock(ax, y, t0, t1, edge=5, period=10, h=0.3):
    xs, ys = [], []
    t = t0
    while t < t1:
        phase = (t - edge) % period
        level = phase < period / 2
        nxt = t + (period / 2 - phase if level else period - phase)
        nxt = min(nxt, t1)
        xs += [t, nxt]
        ys += [y - h if level else y + h] * 2
        t = nxt
    ax.plot(xs, ys, color=MUTED, lw=1.1)


def wave_axes(rows, t0, t1, width=9.4, row_h=0.42, title=None):
    fig, ax = plt.subplots(figsize=(width, row_h * len(rows) + 0.9))
    ax.set_xlim(t0, t1)
    ax.set_ylim(len(rows) - 0.4, -0.9)
    ax.set_yticks(range(len(rows)))
    ax.set_yticklabels(rows, family='DejaVu Sans Mono', fontsize=9)
    ax.tick_params(axis='y', length=0, labelcolor=INK)
    ax.xaxis.tick_top()
    ax.spines[['bottom', 'right', 'left']].set_visible(False)
    ax.grid(axis='x', color=GRID, lw=0.5)
    ax.set_axisbelow(True)
    ax.tick_params(axis='x', labelsize=8)
    if title:
        fig.suptitle(title, x=0.01, ha='left', fontsize=11, fontweight='bold', y=1.0)
    return fig, ax


def fig_multiplier(v, out, names):
    t0, t1 = 185, 285
    c = Cycles(v, 'fast', t0, t1)
    rows = ['CLK', 'E: instruction', 'M: MulResult_M', 'W: write-back', 'StallD', 'FlushE', 'Busy']
    fig, ax = wave_axes(rows, t0, t1, title='Pipelined multiplier (testbench, core with everything on)')
    draw_clock(ax, 0, t0, t1)
    e_segs, m_segs, w_segs = [], [], []
    bits = {k: [] for k in ('StallD', 'FlushE', 'Busy')}
    for e in c.edges:
        a, b = max(e, t0), min(e + c.period, t1)
        pc, valid = c.s('PC_E', e), c.s('Valid_E', e)
        lab = names.get(pc, '%x' % pc) if valid else 'bubble'
        e_segs.append((a, b, lab, valid and c.s('IsMul_E', e) == 1))
        if c.s('IsMul_M', e):
            m_segs.append((a, b, str(c.s('MulResult_M', e)), True))
        else:
            m_segs.append((a, b, None, False))
        rd, we = c.s('rd_W', e), c.s('RegWrite_W', e)
        if we and rd:
            w_segs.append((a, b, 'x%d=%d' % (rd, c.s('Result_W', e)), bool(c.s('IsMul_W', e))))
        else:
            w_segs.append((a, b, None, False))
        for k in bits:
            bits[k].append((a, b, c.s(k, e)))
    draw_bus(ax, 1, e_segs)
    draw_bus(ax, 2, m_segs)
    draw_bus(ax, 3, w_segs)
    draw_bit(ax, 4, bits['StallD'], colour=STAGE['E'])
    draw_bit(ax, 5, bits['FlushE'], colour=STAGE['E'])
    draw_bit(ax, 6, bits['Busy'], colour=STAGE['M'])
    ax.text(247, 2, 'one finished product per cycle', ha='left', va='center', fontsize=8.5, color=INK)
    ax.text(237, 4.0, 'addi needs x13 at once: 1 bubble',
            ha='left', va='center', fontsize=8.5, color=INK)
    ax.text(267, 5.0, 'j', ha='left', va='center', fontsize=8.5, color=MUTED)
    ax.text(t1 - 1, 6.0, 'Busy stays 0: the pipeline never freezes', ha='right', va='center', fontsize=8.5,
            color=MUTED)
    ax.set_xlabel('ns', fontsize=8, color=MUTED)
    save(fig, out, 'wave_multiplier.png')


def fig_multiplier_vs_slow(v, out):
    t0, t1 = 185, 1600
    rows = ['pipelined: Busy', 'pipelined: product written', 'A3 MCycle: Busy', 'A3 MCycle: product written']
    fig, ax = wave_axes(rows, t0, t1, row_h=0.55,
                        title='Same five instructions: pipelined multiplier vs the Assignment 3 multi-cycle unit')
    ax.set_ylim(len(rows) - 0.2, -0.9)
    for i, core in enumerate(('fast', 'slow')):
        c = Cycles(v, core, t0, t1)
        busy, done, y = [], None, 2 * i + 1
        for e in c.edges:
            if e > (1400 if core == 'fast' else 1560):   # by then the core has moved on to the div test
                break
            busy.append((max(e, t0), min(e + 10, t1), c.s('Busy', e)))
            rd, we = c.s('rd_W', e), c.s('RegWrite_W', e)
            if we and rd in (10, 11, 12, 13, 14):
                ax.plot([e + 5, e + 5], [y - 0.3, y + 0.3], color=STAGE['W'], lw=2.2)
                if core == 'slow' and rd != 14:
                    ax.text(e + 9, y - 0.05, 'x%d=%d' % (rd, c.s('Result_W', e)), fontsize=8.5, va='center',
                            family='DejaVu Sans Mono')
                if rd == 14:
                    done = e + 10
        draw_bit(ax, 2 * i, busy, colour=STAGE['M'])
        if core == 'fast':
            ax.text(290, y, 'x10=35  x11=99  x12=234  x13=17  x14=18,  all five done at %d ns' % done,
                    fontsize=8.5, va='center', family='DejaVu Sans Mono')
            ax.text(290, 2 * i, 'Busy never rises for a multiply', fontsize=8.5, va='center', color=MUTED)
        else:
            ax.text(done, y + 0.55, 'all five done at %d ns' % done, fontsize=8.5, color=INK,
                    fontweight='bold', ha='right', va='center')
            ax.text(360, 2 * i - 0.55, '33 cycles per multiply, pipeline frozen', fontsize=8.5, va='center',
                    color=MUTED, ha='center')
    ax.set_xlabel('ns', fontsize=8, color=MUTED)
    save(fig, out, 'wave_multiplier_vs_mcycle.png')


def fig_branch(v, out, names):
    t0, t1 = 755, 1075
    rows = ['BTB on:  E', 'BTB on:  Redirect_E', '', 'BTB off: E', 'BTB off: Redirect_E']
    fig, ax = wave_axes(rows, t0, t1, width=11.5, row_h=0.55,
                        title='Branch prediction: the 8-iteration loop  addi x20, x20, 1 / blt x20, x21, loop')
    ax.set_ylim(len(rows) - 0.2, -0.9)
    for i, core in enumerate(('fast', 'nopred')):
        c = Cycles(v, core, t0, t1)
        segs, red, n = [], [], 0
        for e in c.edges:
            a, b = max(e, t0), min(e + 10, t1)
            pc, valid = c.s('PC_E', e), c.s('Valid_E', e)
            lab = (names.get(pc, '%x' % pc).split()[0] if valid else '') or None
            segs.append((a, b, lab, valid and pc == 0x40018c))
            r = c.s('Redirect_E', e)
            red.append((a, b, r))
            n += bool(r) and pc == 0x40018c
        draw_bus(ax, 3 * i, segs, fontsize=7.5)
        draw_bit(ax, 3 * i + 1, red, colour=STAGE['E'])
        ax.text(t1 - 1, 3 * i + 1.75, '%d redirects by the blt' % n, ha='right', fontsize=8.5,
                color=INK, fontweight='bold', va='center')
    ax.text(t0 + 1, 1.75, 'first pass and loop exit mispredict; in between, a loop pass every 2 cycles',
            fontsize=8.5, color=MUTED, va='center')
    ax.text(t0 + 1, 4.75, 'every taken blt is a redirect: 2 wrong-path instructions flushed each time',
            fontsize=8.5, color=MUTED, va='center')
    ax.set_xlabel('ns', fontsize=8, color=MUTED)
    save(fig, out, 'wave_branch.png')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--vcd')
    ap.add_argument('--out', default=os.path.join(REPO, 'docs', 'media'))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    pipeline_charts(args.out)
    perf_chart(args.out)
    if args.vcd:
        from vcd import VCD
        v = VCD(args.vcd)
        names = asm_names()
        fig_multiplier(v, args.out, names)
        fig_multiplier_vs_slow(v, args.out)
        fig_branch(v, args.out, names)


if __name__ == '__main__':
    main()
