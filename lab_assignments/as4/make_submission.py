#!/usr/bin/env python3
"""
make_submission.py - build the Assignment 4 submission as the lab asks:
  .v/.vhd files created/modified (RTL sources, testbenches), .c/.h files, .bit, .s/.asm, .ppt(x)
Only those files, not the project folder.

  python3 make_submission.py                       fill submissions/Group39_Friday_Lab4/
  python3 make_submission.py --bit path/to/TOP.bit also copy the bitstream in
  python3 make_submission.py --zip                 and write submissions/Group39_Friday_Lab4.zip
                                                   (refuses without TOP.bit in the folder)

The bitstream is as4.runs/impl_1/TOP.bit after Generate Bitstream (the runs folder is not in git).
Run sw/build.py first if the program changed, so that the .mem / .s files are the ones in the bitstream.
The slides are the group's deck already in the folder (CG3207_Assignment4.pptx); they are not copied.
Works with plain Windows Python.
"""
import argparse
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(HERE, 'as4.srcs', 'sources_1', 'imports', 'as2')
SIM = os.path.join(HERE, 'sim')

GROUP, DAY = '39', 'Friday'
NAME = 'Group%s_%s_Lab4' % (GROUP, DAY)
OUT = os.path.join(REPO, 'submissions', NAME)

FILES = [
    # RTL created or modified (unchanged templates such as ProgramCounter.v, Shifter.v, uart.vhd,
    # SPI_If.vhd, ADXL362Ctrl.vhd are left out; they are as given)
    (SRC, ['RV.v', 'PipeMul.v', 'HazardUnit.v', 'BranchPredictor.v', 'LoadStore.v', 'Decoder.v',
           'RegFile.v', 'Wrapper.v', 'ALU.v', 'Extend.v', 'PC_Logic.v', 'MCycle.v',
           'TOP_Nexys.vhd', 'pmodoledrgb_bitmap.vhd']),
    # testbenches
    (SRC, ['test_Wrapper.v']),
    (os.path.join(SIM, 'enhancement_tests'), ['tb_all_enhancements.v', 'tb_system_enhancements.v']),
    (SIM, ['tb_cpu.v']),
    (os.path.join(SIM, 'chip'), ['tb_chip.v', 'unisim_fake.vhd']),
    # program: C source, generated assembly, start-up code, memory images in the bitstream
    (os.path.join(HERE, 'sw', 'demo'), ['fractal.c', 'fractal_tables.h']),
    (os.path.join(HERE, 'sw', 'build'), ['fractal.s']),
    (os.path.join(HERE, 'sw'), ['crt0.s']),
    (SRC, ['AA_IROM.mem', 'AA_DMEM.mem']),
    # test program of tb_all_enhancements.v
    (HERE, ['testbench_enhancements.asm']),
]
KEEP = ['README.txt', 'CG3207_Assignment4.pptx', 'TOP.bit']   # written by hand / by Vivado


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bit', help='the bitstream used in the demo (as4.runs/impl_1/TOP.bit)')
    ap.add_argument('--zip', action='store_true', help='also write the .zip next to the folder')
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    wanted = set(KEEP)
    for d, files in FILES:
        for f in files:
            src = os.path.join(d, f)
            if not os.path.exists(src):
                sys.exit('missing: ' + src)
            shutil.copy(src, os.path.join(OUT, f))
            wanted.add(f)
    if args.bit:
        shutil.copy(args.bit, os.path.join(OUT, 'TOP.bit'))
    for f in os.listdir(OUT):                      # nothing stale left behind
        if f not in wanted:
            os.remove(os.path.join(OUT, f))
    print('filled', OUT)

    missing = [f for f in ('TOP.bit', 'CG3207_Assignment4.pptx', 'README.txt') if not os.path.exists(os.path.join(OUT, f))]
    for f in missing:
        print('  still missing:', f)
    if args.zip:
        if missing:
            sys.exit('not writing the zip until these are in the folder')
        zpath = os.path.join(REPO, 'submissions', NAME + '.zip')
        with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
            for f in sorted(os.listdir(OUT)):
                z.write(os.path.join(OUT, f), os.path.join(NAME, f))
        print('wrote', zpath)


if __name__ == '__main__':
    main()
