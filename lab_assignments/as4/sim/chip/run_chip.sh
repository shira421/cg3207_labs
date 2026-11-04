#!/bin/sh
# Whole-chip simulation: TOP + OLED controller (course VHDL, converted to Verilog by GHDL), our
# Wrapper/CPU, and a model of the SSD1331 panel (tb_chip.v) that decodes the Pmod SPI wires into
# panel_NN.ppm pictures. Needs ghdl (4.x, with --synth) and iverilog:  sudo apt install ghdl iverilog
#
#   ./run_chip.sh            power-up without pressing reset (what happens after programming the board)
#   ./run_chip.sh reset      press BTND first
#
# The MMCM / BUFG / BUFGCE primitives are replaced by the simple models in unisim_fake.vhd.
# About 5 minutes for 2 panel frames.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../../as4.srcs/sources_1/imports/as2
WORK=${WORK:-/tmp/as4_chip}
mkdir -p "$WORK" && cd "$WORK" && rm -f *.cf
ghdl -a --std=08 -fsynopsys --work=unisim "$HERE/unisim_fake.vhd"
ghdl --synth --std=08 -fsynopsys --out=verilog "$SRC/TOP_Nexys.vhd" "$SRC/uart.vhd" "$SRC/SPI_If.vhd" \
     "$SRC/ADXL362Ctrl.vhd" "$SRC/pmodoledrgb_bitmap.vhd" -e TOP > top.v
cp "$SRC/AA_IROM.mem" "$SRC/AA_DMEM.mem" .
iverilog -g2012 -o chip.vvp -s tb_chip "$HERE/tb_chip.v" top.v $(for f in Wrapper RV HazardUnit BranchPredictor \
     LoadStore PipeMul ALU Shifter Decoder Extend PC_Logic RegFile ProgramCounter MCycle; do echo "$SRC/$f.v"; done)
if [ "$1" = "reset" ]; then vvp -n chip.vvp +frames=2; else vvp -n chip.vvp +noreset +frames=2; fi | grep -v readmem
echo "panel pictures: $WORK/panel_*.ppm"
