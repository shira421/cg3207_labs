#!/usr/bin/env python3
"""
make_submission.py - pack the Assignment 4 submission as the lab asks:
  .v/.vhd created/modified (RTL + testbenches), .c/.h, .bit, .s/.asm, .ppt(x)
into GroupXX_Monday/Friday_Lab4.zip (not the whole project folder).

  python3 make_submission.py --bit path/to/TOP.bit [--group 39 --day Friday]

Run sw/build.py first if the program changed, so that the .mem/.s files are the ones used in the demo.
"""
import argparse
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'as4.srcs', 'sources_1', 'imports', 'as2')

FILES = [
    # RTL created or modified for Assignment 4 (and earlier assignments' modules the CPU uses)
    (SRC, ['RV.v', 'HazardUnit.v', 'BranchPredictor.v', 'LoadStore.v', 'PipeMul.v', 'Decoder.v', 'RegFile.v', 'Wrapper.v',
           'ALU.v', 'Shifter.v', 'Extend.v', 'PC_Logic.v', 'ProgramCounter.v', 'MCycle.v',
           'TOP_Nexys.vhd', 'pmodoledrgb_bitmap.vhd',
           'test_Wrapper.v', 'test_MCycle.v', 'AA_IROM.mem', 'AA_DMEM.mem']),
    (os.path.join(HERE, 'sim'), ['tb_cpu.v']),
    # program
    (os.path.join(HERE, 'sw', 'demo'), ['fractal.c', 'fractal_tables.h']),
    (os.path.join(HERE, 'sw', 'build'), ['fractal.s']),
    (os.path.join(HERE, 'sw'), ['crt0.s']),
    # slides
    (HERE, ['Lab4_Slides.pptx']),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bit', help='the bitstream used in the demo (TOP.bit from as4.runs/impl_1)')
    ap.add_argument('--group', default='39')
    ap.add_argument('--day', default='Friday')
    args = ap.parse_args()

    name = 'Group%s_%s_Lab4.zip' % (args.group, args.day)
    missing = []
    with zipfile.ZipFile(os.path.join(HERE, name), 'w', zipfile.ZIP_DEFLATED) as z:
        for d, files in FILES:
            for f in files:
                p = os.path.join(d, f)
                if os.path.exists(p):
                    z.write(p, f)
                else:
                    missing.append(p)
        if args.bit and os.path.exists(args.bit):
            z.write(args.bit, os.path.basename(args.bit))
        else:
            missing.append('the .bit file (--bit)')
    print('wrote', name)
    for m in missing:
        print('  missing:', m)
    if missing:
        sys.exit(1)


if __name__ == '__main__':
    main()
