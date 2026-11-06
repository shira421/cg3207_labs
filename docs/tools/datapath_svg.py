#!/usr/bin/env python3
"""datapath_svg.py - draws docs/media/pipeline_datapath.svg, the block diagram of the Assignment 4 CPU."""
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'media', 'pipeline_datapath.svg')
W, H = 1280, 600
STAGE = {'F': '#4C78A8', 'D': '#72B7B2', 'E': '#F58518', 'M': '#E45756', 'W': '#54A24B'}
INK, MUTED, LINE = '#1f2328', '#57606a', '#24292f'
FWD, WB, RED = '#d4700a', '#3d8b37', '#cf222e'
COLS = {'F': (20, 240, 'Fetch'), 'D': (270, 470, 'Decode'), 'E': (500, 780, 'Execute'),
        'M': (810, 1010, 'Memory'), 'W': (1040, 1240, 'Write-back')}
REGS = [(248, 'F/D'), (478, 'D/E'), (788, 'E/M'), (1018, 'M/W')]

out = []


def add(s):
    out.append(s)


def text(x, y, s, size=13, weight='normal', fill=INK, anchor='middle', extra=''):
    add('<text x="%g" y="%g" font-size="%g" font-weight="%s" fill="%s" text-anchor="%s" %s>%s</text>'
        % (x, y, size, weight, fill, anchor, extra, s))


def box(x, y, w, h, lines, stage, title_size=14):
    add('<rect x="%g" y="%g" width="%g" height="%g" rx="7" fill="%s" stroke="%s" stroke-width="1.6"/>'
        % (x, y, w, h, tint(STAGE[stage]), STAGE[stage]))
    n = len(lines)
    y0 = y + h / 2 - (n - 1) * 8.5 + 4
    for i, l in enumerate(lines):
        text(x + w / 2, y0 + i * 17, l, size=title_size if i == 0 else 11, weight='bold' if i == 0 else 'normal',
             fill=INK if i == 0 else MUTED)


def mux(xl, yt, yb, xr, inset, label=None):
    add('<polygon points="%g,%g %g,%g %g,%g %g,%g" fill="#ffffff" stroke="%s" stroke-width="1.6"/>'
        % (xl, yt, xr, yt + inset, xr, yb - inset, xl, yb, LINE))
    if label:
        cx, cy = (xl + xr) / 2, (yt + yb) / 2
        text(cx, cy + 3, label, size=9, fill=MUTED, extra='transform="rotate(-90 %g %g)"' % (cx, cy))


def tint(hexc, a=0.13):
    r, g, b = int(hexc[1:3], 16), int(hexc[3:5], 16), int(hexc[5:7], 16)
    mix = lambda c: int(255 - (255 - c) * a)
    return '#%02x%02x%02x' % (mix(r), mix(g), mix(b))


def wire(pts, colour=LINE, dash=None, arrow=True, width=1.6):
    d = 'M' + ' L'.join('%g,%g' % p for p in pts)
    add('<path d="%s" fill="none" stroke="%s" stroke-width="%g" %s %s/>'
        % (d, colour, width, ('stroke-dasharray="%s"' % dash) if dash else '',
           ('marker-end="url(#a-%s)"' % colour[1:]) if arrow else ''))


def dot(x, y, colour=LINE):
    add('<circle cx="%g" cy="%g" r="3" fill="%s"/>' % (x, y, colour))


def label(x, y, s, colour=MUTED, anchor='start', size=10.5):
    text(x, y, s, size=size, fill=colour, anchor=anchor)


add('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" '
    'font-family="Inter, Segoe UI, Helvetica, Arial, sans-serif">' % (W, H, W, H))
add('<defs>')
for c in (LINE, FWD, WB, RED):
    add('<marker id="a-%s" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="%s"/></marker>' % (c[1:], c))
add('</defs>')
add('<rect width="%d" height="%d" fill="#ffffff"/>' % (W, H))

# stage headers and pipeline registers
for s, (x0, x1, name) in COLS.items():
    add('<rect x="%g" y="14" width="%g" height="34" rx="6" fill="%s"/>' % (x0, x1 - x0, STAGE[s]))
    text((x0 + x1) / 2, 37, '%s · %s' % (s, name), size=15, weight='bold', fill='#ffffff')
for x, name in REGS:
    add('<rect x="%g" y="96" width="14" height="338" rx="3" fill="#8c959f"/>' % x)
    text(x + 7, 90, name, size=10, fill=MUTED)

# ---------------------------------------------------------------- F
mux(30, 125, 215, 56, 12, 'next PC')
box(76, 145, 46, 50, ['PC'], 'F')
box(142, 115, 84, 110, ['IROM', '4 KB'], 'F')
box(100, 255, 126, 72, ['BTB', '32 entries: tag,', 'target, 2-bit ctr'], 'F', 13)
box(24, 330, 40, 28, ['+4'], 'F', 12)
wire([(56, 170), (76, 170)])
wire([(122, 170), (142, 170)])
wire([(226, 170), (248, 170)])
label(229, 163, 'instr', size=9.5)
wire([(110, 195), (110, 255)])
dot(110, 195)
wire([(88, 195), (88, 344), (64, 344)])
wire([(44, 330), (44, 210)])
wire([(100, 285), (52, 285), (52, 206)])
label(57, 280, 'predicted', size=9.5)

# ---------------------------------------------------------------- D
box(290, 92, 160, 58, ['Decoder', '+ mret, mulsr'], 'D')
box(290, 163, 160, 42, ['Extend (immediate)'], 'D', 12.5)
box(290, 222, 160, 108, ['Register file', 'x0-x31, 2 read / 1 write', 'write-through W → D'], 'D')
wire([(262, 170), (276, 170)], arrow=False)
wire([(276, 121), (276, 276)], arrow=False)
for y in (121, 184, 276):
    wire([(276, y), (290, y)])
wire([(450, 121), (478, 121)])
label(452, 114, 'control', size=9.5)
wire([(450, 184), (478, 184)])
label(452, 177, 'imm', size=9.5)
wire([(450, 255), (478, 255)])
label(452, 248, 'RD1', size=9.5)
wire([(450, 300), (478, 300)])
label(452, 293, 'RD2', size=9.5)

# ---------------------------------------------------------------- E
mux(515, 235, 280, 540, 10, 'fwd A')
mux(515, 285, 330, 540, 10, 'fwd B')
box(565, 235, 85, 80, ['ALU'], 'E')
box(680, 105, 92, 70, ['Branch check', 'outcome, target,', 'prediction right?'], 'E', 12.5)
box(680, 240, 92, 60, ['MCycle', 'div, 33 cycles'], 'E', 13)
box(565, 340, 207, 52, ['PipeMulE', 'radix-4 Booth, CSA tree 18 → 4 rows'], 'E', 13)
wire([(492, 255), (515, 255)])
wire([(492, 300), (515, 300)])
wire([(540, 257), (565, 257)])
wire([(540, 307), (565, 295)])
wire([(492, 184), (592, 184), (592, 235)])
wire([(625, 235), (625, 140), (680, 140)])
wire([(550, 257), (550, 355), (565, 355)])
dot(550, 257)
wire([(556, 307), (556, 377), (565, 377)])
dot(556, 307)
wire([(650, 275), (665, 275), (665, 320), (788, 320)])
wire([(772, 270), (778, 270), (778, 320)], arrow=False)
dot(778, 320)
label(682, 314, 'ExecResult', size=9.5)
wire([(772, 366), (788, 366)])

# ---------------------------------------------------------------- M
box(840, 140, 145, 120, ['DMEM 4 KB', '+ MMIO: OLED, LEDs,', '7-seg, accelerometer,', 'CPU_CTRL, INT_EN', 'StoreAlign: sb, sh'], 'M', 13)
box(840, 340, 145, 52, ['PipeMulM', '2 CSA, add, [k+31:k]'], 'M', 13)
wire([(802, 320), (1018, 320)])
wire([(822, 320), (822, 205), (840, 205)])
dot(822, 320)
label(826, 197, 'addr', size=9.5)
wire([(802, 366), (840, 366)])
wire([(985, 366), (1018, 366)])
label(988, 359, 'product', size=9.5)
wire([(985, 205), (1018, 205)])
label(988, 198, 'data', size=9.5)

# ---------------------------------------------------------------- W
box(1060, 180, 88, 50, ['LoadExtend', 'lb lh lbu lhu'], 'W', 12.5)
mux(1172, 185, 385, 1202, 15, 'result')
wire([(1032, 205), (1060, 205)])
wire([(1148, 205), (1172, 205)])
wire([(1032, 320), (1172, 320)])
wire([(1032, 366), (1172, 366)])
wire([(1202, 285), (1225, 285), (1225, 425), (370, 425), (370, 332)], colour=WB, width=2)
label(1225, 447, 'Result_W → register file (D reads it in the same cycle)', colour=WB, size=10.5, anchor='end')

# forwarding (M from ExecResult_M, W from the write-back value)
wire([(826, 320), (826, 405), (534, 405), (534, 324)], colour=FWD, dash='6 4', width=1.8)
dot(826, 320, FWD)
label(600, 418, 'forward from M (ExecResult_M)', colour=FWD)
wire([(522, 425), (522, 328)], colour=WB, dash='6 4', width=1.8)
dot(522, 425, WB)
label(512, 418, 'forward from W', colour=WB, anchor='end')

# redirect from E back to the next-PC mux
wire([(726, 105), (726, 76), (43, 76), (43, 129)], colour=RED, width=2)
label(70, 69, 'Redirect_E: mispredicted branch or jal, any jalr, mret → correct PC, flush D and E.  '
              'An interrupt goes to 0x00400004 the same way.', colour=RED)

# hazard unit
add('<rect x="240" y="468" width="800" height="46" rx="7" fill="#f6f8fa" stroke="#8c959f" stroke-width="1.4"/>')
text(640, 488, 'Hazard unit', size=14, weight='bold')
text(640, 505, 'forward select (M before W) · load / multiply-use stall · flush on redirect or interrupt · '
               'MCycle stall', size=11, fill=MUTED)
for x, _ in REGS:
    wire([(x + 7, 468), (x + 7, 436)], colour='#8c959f', dash='3 3', arrow=False, width=1.2)

# legend
lx, ly = 20, 552
items = [(LINE, None, 'datapath'), (FWD, '6 4', 'forwarding'), (WB, None, 'write-back'),
         (RED, None, 'redirect (next PC)')]
for colour, dash, name in items:
    wire([(lx, ly), (lx + 34, ly)], colour=colour, dash=dash, width=2)
    label(lx + 42, ly + 4, name, colour=INK, size=12)
    lx += 60 + len(name) * 7
add('<rect x="%g" y="%g" width="10" height="22" rx="2" fill="#8c959f"/>' % (lx, ly - 11))
label(lx + 18, ly + 4, 'pipeline register (stall = hold, flush = bubble)', colour=INK, size=12)
label(20, 585, 'Control signals travel with each instruction through the same pipeline registers. '
               'Every multiply starts in E and finishes in M, one per cycle.', colour=MUTED, size=11.5)

add('</svg>')
open(OUT, 'w').write('\n'.join(out))
print('wrote', os.path.normpath(OUT))
