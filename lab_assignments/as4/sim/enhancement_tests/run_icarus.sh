#!/bin/sh
# Run both enhancement testbenches with Icarus Verilog (sudo apt install iverilog).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../../as4.srcs/sources_1/imports/as2
CPU="RV HazardUnit BranchPredictor LoadStore PipeMul ALU Shifter Decoder Extend PC_Logic RegFile ProgramCounter MCycle"
WORK=${WORK:-/tmp/as4_enh}
mkdir -p "$WORK" && cd "$WORK" && cp "$SRC/AA_IROM.mem" "$SRC/AA_DMEM.mem" .
iverilog -g2012 -o all.vvp -s tb_all_enhancements "$HERE/tb_all_enhancements.v" $(for f in $CPU; do echo "$SRC/$f.v"; done)
vvp -n all.vvp | grep -E "ERROR|RESULTS|Completion|redirects|PASS|FAIL"
iverilog -g2012 -o sys.vvp -s tb_system_enhancements "$HERE/tb_system_enhancements.v" "$SRC/Wrapper.v" $(for f in $CPU; do echo "$SRC/$f.v"; done)
vvp -n sys.vvp | grep -E "ERROR|PIXEL|PASS|FAIL"
