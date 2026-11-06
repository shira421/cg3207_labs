#!/usr/bin/env python3
"""
render_frames.py - run the Assignment 4 demo program on the reference model (sim/iss.py) and save
every OLED frame it presents as a PNG, plus an optional animated GIF.

The pictures in the READMEs come from here. The model executes the same AA_IROM.mem / AA_DMEM.mem
that goes into the bitstream, and decodes the program's OLED writes the way Wrapper.v does
(16-bit 5-6-5 colour, auto-advance along the rows, CTRL = 0x08 presents the frame). Frame 1 is
pixel-identical to the frame the RTL testbench (sim/tb_cpu.v +frames) writes for the same program.

  python3 render_frames.py <dir with AA_IROM.mem/AA_DMEM.mem> <out dir>
        [--frames N] [--dip 0x40] [--hold-btnr] [--gif out.gif] [--scale 4] [--fps 12]

The .mem files are built with sw/build.py, e.g. for the zoom flight in the README:
  cd lab_assignments/as4/sw
  python3 build.py demo/fractal.c --out /tmp/zoom --no-install --cflags=-DPICTURE=3
  python3 ../../../docs/tools/render_frames.py /tmp/zoom /tmp/zoom/png --frames 72 --dip 0x40 \
        --hold-btnr --gif zoom.gif

Needs Pillow (pip install pillow).
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'lab_assignments', 'as4', 'sim'))
from iss import ISS, MMIO_BASE  # noqa: E402

from PIL import Image  # noqa: E402

W, H = 96, 64


class OledISS(ISS):
    """The reference model plus a frame buffer fed by the program's OLED MMIO writes."""

    def __init__(self, d, **kw):
        super().__init__(d, **kw)
        self.col = self.row = 0
        self.fb = [[(0, 0, 0)] * W for _ in range(H)]
        self.frames = []

    def write(self, a, mask, data):
        super().write(a, mask, data)
        if a < MMIO_BASE:
            return
        off = a & 0xFC
        if off == 0x20:
            self.col = data % W
        elif off == 0x24:
            self.row = data % H
        elif off == 0x28:                         # sh: 16-bit colour (in both lanes), then auto-advance
            v = data & 0xFFFF
            self.col += 1
            if self.col == W:
                self.col = 0
                self.row = (self.row + 1) % H
            r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
            self.fb[self.row][self.col] = (r << 3, g << 2, b << 3)
        elif off == 0x2C and data & 0x08:         # present
            self.frames.append([row[:] for row in self.fb])


def to_image(fb, scale):
    img = Image.new('RGB', (W, H))
    img.putdata([p for row in fb for p in row])
    return img.resize((W * scale, H * scale), Image.NEAREST) if scale > 1 else img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mem_dir')
    ap.add_argument('out_dir')
    ap.add_argument('--frames', type=int, default=3)
    ap.add_argument('--dip', type=lambda s: int(s, 0), default=0)
    ap.add_argument('--hold-btnr', action='store_true', help='hold BTNR (zoom in) the whole time')
    ap.add_argument('--skip', type=int, default=0, help='frames to drop at the start')
    ap.add_argument('--scale', type=int, default=4)
    ap.add_argument('--gif')
    ap.add_argument('--fps', type=int, default=12)
    ap.add_argument('--max-steps', type=int, default=2_000_000_000)
    args = ap.parse_args()

    s = OledISS(args.mem_dir, dip=args.dip, pb=1 if args.hold_btnr else 0)
    os.makedirs(args.out_dir, exist_ok=True)
    done = 0
    for _ in range(args.max_steps // 100000):
        for _ in range(100000):
            s.step()
        while done < len(s.frames):
            to_image(s.frames[done], args.scale).save(os.path.join(args.out_dir, 'frame_%03d.png' % done))
            print('frame', done, 'at', s.cycles, 'instructions', flush=True)
            done += 1
        if done >= args.frames:
            break
    if args.gif:
        imgs = [to_image(f, args.scale) for f in s.frames[args.skip:args.frames]]
        imgs = [im.convert('P', palette=Image.ADAPTIVE, colors=128) for im in imgs]
        imgs[0].save(args.gif, save_all=True, append_images=imgs[1:], duration=int(1000 / args.fps),
                     loop=0, optimize=True)
        print('wrote', args.gif)


if __name__ == '__main__':
    main()
