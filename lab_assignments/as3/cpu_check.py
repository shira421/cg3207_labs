#!/usr/bin/env python3
"""
cpu_check.py - line-level self test for the CG3207 Assignment 2 single-cycle RISC-V CPU.

AI assistance declaration (CG3207 lab manual):
  Tool   : Claude (Anthropic), model Claude Opus 5.5, via claude.ai, 2 Oct 2026
  Prompt : "can you generate a python script to test every line in the verilog code"
           (together with the group's RTL files)

What it does
  (Assignment 3 copy: MCycle.v added to the file list and RV32M to the decoder model; the
   multi-cycle instructions themselves are checked by test_MCycle.v and test_Wrapper.v.)
  1. Finds the RTL files (Shifter, ALU, Extend, Decoder, PC_Logic, RegFile, ProgramCounter, MCycle,
     RV, Wrapper) in a Vivado project folder, or any folder below --root.
  2. Writes ONE Verilog testbench that
       - tests every module on its own, with expected values from a Python model,
       - tests the RV datapath one instruction at a time (every instruction type),
       - runs a short program through the Wrapper (instruction/data memory, switches,
         buttons, LEDs, 7-segment display).
  3. Runs it with Icarus Verilog (if installed) or Vivado's xsim.
  4. If anything fails, every check knows which source lines it exercises, so the lines
     are ranked by how well they explain the failures (Ochiai score). The most likely
     lines are printed as file:line with the code, plus example failures.
  5. Optionally runs your own test_Wrapper.v with your AA_IROM.mem / AA_DMEM.mem.

Usage
  python cpu_check.py                       search the current folder and below
  python cpu_check.py --root C:\\CG3207\\as2
  python cpu_check.py --sim xsim            force Vivado's simulator (default: iverilog if found)
  python cpu_check.py --lines               print where every checked line is, then exit
  python cpu_check.py --no-demo             skip running your own test_Wrapper.v
"""
import argparse
import difflib
import glob
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

M32 = 0xFFFFFFFF
WORK_DIR_NAME = '_cpu_check_work'


# =============================================================================================
# small helpers
# =============================================================================================
def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def s32(v):
    return sx(v, 32)


def vh(v, w=32):
    """Verilog hex literal."""
    return "%d'h%x" % (w, v & ((1 << w) - 1))


# =============================================================================================
# The source lines that are checked. Each tag = one line of RTL.
#   rx      : regex that finds the line (comments are ignored)
#   anchor  : optional regex for an earlier line; rx is then searched in the 'span' lines after it
#   meaning : what the line does, shown in the report
# If a line cannot be found (because it was edited), the closest line to the original text
# (CANON, filled in below) is reported and marked "(edited?)".
# =============================================================================================
TAGS = {}


def T(name, f, rx, meaning, anchor=None, span=0):
    TAGS[name] = dict(file=f, rx=rx, meaning=meaning, anchor=anchor, span=span)


# ---- Shifter.v
T('SH_SLL', 'Shifter.v', r"2'b00\s*:\s*ShOut", 'shift left logical (sll, slli)')
T('SH_SRL', 'Shifter.v', r"2'b10\s*:\s*ShOut", 'shift right logical (srl, srli)')
T('SH_SRA', 'Shifter.v', r"2'b11\s*:\s*ShOut", 'shift right arithmetic (sra, srai)')
T('SH_DEF', 'Shifter.v', r"default\s*:\s*ShOut", 'Sh = 01 (no RISC-V instruction): pass input through')

# ---- ALU.v
T('ALU_ADDER', 'ALU.v', r"assign\s+S_wider\s*=", "the ALU's adder (add, sub, slt, sltu, branch compare)")
T('ALU_DEF_C0', 'ALU.v', r"\bC_0\s*=", 'default carry-in = 0 (used by add)', anchor=r"always\s*@", span=6)
T('ALU_DEF_A', 'ALU.v', r"Src_A_comp\s*=", 'adder input A = Src_A', anchor=r"always\s*@", span=6)
T('ALU_DEF_B', 'ALU.v', r"Src_B_comp\s*=", 'default adder input B = Src_B (used by add)', anchor=r"always\s*@", span=6)
T('ALU_ADD', 'ALU.v', r"4'b0000\s*:", 'add: ALUResult = sum')
for _op, _code, _what in (('SUB', '0001', 'sub / branch compare'), ('SLT', '0100', 'slt'), ('SLTU', '0110', 'sltu')):
    T('ALU_%s_LBL' % _op, 'ALU.v', r"4'b%s\s*:" % _code, '%s case label' % _what)
    T('ALU_%s_C0' % _op, 'ALU.v', r"\bC_0\b", '%s: carry-in = 1 (A + ~B + 1)' % _what, anchor=r"4'b%s\s*:" % _code, span=4)
    T('ALU_%s_INV' % _op, 'ALU.v', r"Src_B_comp\s*=", '%s: invert B' % _what, anchor=r"4'b%s\s*:" % _code, span=4)
    T('ALU_%s_RES' % _op, 'ALU.v', r"ALUResult\s*=", '%s: result' % _what, anchor=r"4'b%s\s*:" % _code, span=4)
T('ALU_XOR', 'ALU.v', r"4'b1000\s*:", 'xor')
T('ALU_OR', 'ALU.v', r"4'b1100\s*:", 'or')
T('ALU_AND', 'ALU.v', r"4'b1110\s*:", 'and')
T('ALU_SHIFT_LBL', 'ALU.v', r"4'b0010\s*,", 'shift case labels (sll, srl, sra)')
T('ALU_SHIFT_RES', 'ALU.v', r"ALUResult\s*=", 'shift result = ShOut', anchor=r"4'b0010\s*,", span=2)
T('ALU_N', 'ALU.v', r"assign\s+N\s*=", 'N flag (sign of A - B)')
T('ALU_Z', 'ALU.v', r"assign\s+Z\s*=", 'Z flag (A - B == 0) -> eq')
T('ALU_C', 'ALU.v', r"assign\s+C\s*=", 'C flag (carry out, 1 when A >= B unsigned)')
T('ALU_V', 'ALU.v', r"assign\s+V\s*=", 'V flag (signed overflow of A - B)')
T('ALU_LT', 'ALU.v', r"assign\s+lt\s*=", 'lt = N ^ V (signed less-than)')
T('ALU_LTU', 'ALU.v', r"assign\s+ltu\s*=", 'ltu = ~C (unsigned less-than)')
T('ALU_FLAGS', 'ALU.v', r"assign\s+ALUFlags\s*=", 'ALUFlags = {eq, lt, ltu}')
T('ALU_SH', 'ALU.v', r"assign\s+Sh\s*=", 'shift type from ALUControl')
T('ALU_SHAMT', 'ALU.v', r"assign\s+Shamt5\s*=", 'shift amount = Src_B[4:0]')
T('ALU_SHIN', 'ALU.v', r"assign\s+ShIn\s*=", 'shifter input = Src_A')

# ---- Extend.v
for _code, _n, _what in (('000', 'U', 'U-type (lui, auipc)'), ('010', 'UJ', 'UJ-type (jal)'), ('011', 'I', 'I-type (addi.., lw, jalr)'),
                         ('110', 'S', 'S-type (sw)'), ('111', 'SB', 'SB-type (branches)')):
    T('EXT_' + _n, 'Extend.v', r"3'b%s\s*:\s*ExtImm" % _code, 'immediate: ' + _what)

# ---- Decoder.v
DEC_OPS = [  # name, opcode, signals assigned inside its case block
    ('DPREG', 0x33, ['RegWrite', 'ALUControl']),
    ('DPIMM', 0x13, ['RegWrite', 'ALUSrcB', 'ImmSrc', 'ALUControl']),
    ('LOAD', 0x03, ['RegWrite', 'MemtoReg', 'ALUSrcB', 'ImmSrc']),
    ('STORE', 0x23, ['MemWrite', 'ALUSrcB', 'ImmSrc']),
    ('BRANCH', 0x63, ['PCS', 'ImmSrc', 'ALUControl']),
    ('JAL', 0x6F, ['PCS', 'RegWrite', 'ALUSrcA', 'ALUSrcB', 'ImmSrc']),
    ('JALR', 0x67, ['PCS', 'RegWrite', 'ALUSrcA', 'ALUSrcB', 'ImmSrc']),
    ('LUI', 0x37, ['RegWrite', 'ALUSrcA', 'ALUSrcB', 'ImmSrc']),
    ('AUIPC', 0x17, ['RegWrite', 'ALUSrcA', 'ALUSrcB', 'ImmSrc']),
]
DEC_SIGS = [('PCS', 2), ('RegWrite', 1), ('MemWrite', 1), ('MemtoReg', 1), ('ALUSrcA', 2), ('ALUSrcB', 2), ('ImmSrc', 3), ('ALUControl', 4)]
for _sig, _w in DEC_SIGS:
    T('DEC_DEF_' + _sig, 'Decoder.v', r"\b%s\s*=" % _sig, 'default value of %s (when an instruction does not set it)' % _sig,
      anchor=r"always\s*@", span=14)
for _name, _op, _sigs in DEC_OPS:
    T('DEC_LP_' + _name, 'Decoder.v', r"localparam\s+OP_%s\s*=" % _name, 'opcode value of OP_%s' % _name)
    T('DEC_BLK_' + _name, 'Decoder.v', r"\bOP_%s\s*:" % _name, 'case label OP_%s' % _name)
    for _sig in _sigs:
        T('DEC_%s_%s' % (_name, _sig), 'Decoder.v', r"\b%s\s*=" % _sig, 'OP_%s sets %s' % (_name, _sig),
          anchor=r"\bOP_%s\s*:" % _name, span=8)
T('DEC_DEFAULT', 'Decoder.v', r"default\s*:", 'unsupported opcode -> keep the NOP defaults', anchor=r"\bOP_AUIPC\s*:", span=12)

# ---- PC_Logic.v
T('PCL_EQ', 'PC_Logic.v', r"wire\s+eq\s*=", 'eq = ALUFlags[2]')
T('PCL_LT', 'PC_Logic.v', r"wire\s+lt\s*=", 'lt = ALUFlags[1]')
T('PCL_LTU', 'PC_Logic.v', r"wire\s+ltu\s*=", 'ltu = ALUFlags[0]')
for _code, _what in (('000', 'beq'), ('001', 'bne'), ('100', 'blt'), ('101', 'bge'), ('110', 'bltu'), ('111', 'bgeu')):
    T('PCL_F3_' + _code, 'PC_Logic.v', r"3'b%s\s*:\s*BranchTaken" % _code, '%s condition' % _what)
T('PCL_F3_DEF', 'PC_Logic.v', r"default\s*:\s*BranchTaken", 'invalid branch funct3 -> not taken')
for _code, _what in (('00', 'not a jump: PC + 4'), ('01', 'branch: PC + imm if taken'), ('10', 'jal: PC + imm'), ('11', 'jalr: rs1 + imm')):
    T('PCL_PCS_' + _code, 'PC_Logic.v', r"2'b%s\s*:\s*PCSrc" % _code, 'PCS = %s, %s' % (_code, _what))

# ---- RegFile.v
T('RF_RD1', 'RegFile.v', r"\bRD1\s*<=", 'read port 1 (rs1), x0 reads as 0')
T('RF_RD2', 'RegFile.v', r"\bRD2\s*<=", 'read port 2 (rs2), x0 reads as 0')
T('RF_WCOND', 'RegFile.v', r"if\s*\(\s*\(\s*rd", 'write only if WE and rd != x0')
T('RF_WRITE', 'RegFile.v', r"RegBank\s*\[\s*rd\s*\]\s*<=", 'write WD into RegBank[rd]')

# ---- ProgramCounter.v
T('PC_RST_IF', 'ProgramCounter.v', r"if\s*\(\s*RESET\s*\)", 'reset has priority')
T('PC_RST_LOAD', 'ProgramCounter.v', r"\bPC\s*<=", 'reset value PC_INIT', anchor=r"if\s*\(\s*RESET\s*\)", span=2)
T('PC_WE_IF', 'ProgramCounter.v', r"else\s+if\s*\(\s*WE_PC", 'update only when WE_PC')
T('PC_LOAD', 'ProgramCounter.v', r"\bPC\s*<=\s*PC_IN", 'PC <= PC_IN')

# ---- RV.v
for _n, _sig, _what in (('OPC', 'Opcode', 'Opcode = Instr[6:0]'), ('RD', 'rd', 'rd = Instr[11:7]'), ('F3', 'Funct3', 'Funct3 = Instr[14:12]'),
                        ('RS1', 'rs1', 'rs1 = Instr[19:15]'), ('RS2', 'rs2', 'rs2 = Instr[24:20]'), ('F7', 'Funct7', 'Funct7 = Instr[31:25]'),
                        ('IMM', 'InstrImm', 'InstrImm = Instr[31:7] (to Extend)'), ('WE', 'WE', 'register write enable = RegWrite'),
                        ('RESULT', 'Result', 'Result = MemtoReg ? ReadData : ALUResult'), ('WD', 'WD', 'register write data = Result'),
                        ('WRITEDATA', 'WriteData', 'store data = RD2'), ('WDOUT', 'WriteData_out', 'store data to Wrapper'),
                        ('MWOUT', 'MemWrite_out', 'byte write enables {4{MemWrite}}'), ('MEMREAD', 'MemRead', 'MemRead = MemtoReg'),
                        ('READDATA', 'ReadData', 'ReadData = ReadData_in'), ('WEPC', 'WE_PC', 'PC write enable'),
                        ('PCB', 'PC_Base', 'next-PC base: RD1 (jalr) or PC'), ('PCO', 'PC_Offset', 'next-PC offset: ExtImm or 4'),
                        ('PCSUM', 'PC_Sum', 'next-PC adder'), ('PCIN', 'PC_IN', 'PC_IN = sum with bit 0 cleared')):
    T('RV_' + _n, 'RV.v', r"assign\s+%s\s*=" % _sig, _what)
for _i, _what in ((0, 'Src_A = RD1'), (1, 'Src_A = 0 (lui)'), (2, 'Src_A = PC (auipc, jal, jalr)')):
    T('RV_SRCA%d' % _i, 'RV.v', r"2'b%s\s*:" % format(_i, '02b'), _what, anchor=r"case\s*\(\s*ALUSrcA\s*\)", span=4)
for _i, _what in ((0, 'Src_B = RD2'), (1, 'Src_B = ExtImm'), (2, 'Src_B = 4 (jal/jalr link)')):
    T('RV_SRCB%d' % _i, 'RV.v', r"2'b%s\s*:" % format(_i, '02b'), _what, anchor=r"case\s*\(\s*ALUSrcB\s*\)", span=4)

# ---- Wrapper.v
T('W_IROM_COND', 'Wrapper.v', r"Instr\s*=\s*\(", 'instruction fetch: PC range / alignment check')
T('W_IROM', 'Wrapper.v', r"IROM\s*\[\s*PC\s*\[", 'instruction fetch: IROM[PC[8:2]]')
T('W_DMEM_RANGE', 'Wrapper.v', r"ALUResult\s*\[\s*31\s*:\s*DMEM_DEPTH_BITS\s*\]\s*==", 'address decode: is it data memory?')
T('W_DMEM_DEC', 'Wrapper.v', r"dec_DMEM\s*<=\s*1'b1", 'address decode: select DMEM')
T('W_MMIO_RANGE', 'Wrapper.v', r"ALUResult\s*\[\s*31\s*:\s*MMIO_DEPTH_BITS\s*\]\s*==", 'address decode: is it a peripheral?')
for _n, _off, _what in (('DIP', 'DIP_OFF', 'switches'), ('PB', 'PB_OFF', 'push buttons'), ('LED', 'LED_OFF', 'LEDs'), ('SEG', 'SEVENSEG_OFF', '7-segment')):
    T('W_CASE_' + _n, 'Wrapper.v', r"\b%s\s*\[[^\]]*\]\s*:" % _off, 'address decode: %s' % _what)
T('W_RD_DIP_IF', 'Wrapper.v', r"if\s*\(\s*dec_DIP\s*\)", 'MMIO read select: switches')
T('W_RD_DIP', 'Wrapper.v', r"ReadData_MMIO\s*<=.*\bDIP\b", 'MMIO read data: switches')
T('W_RD_PB_IF', 'Wrapper.v', r"if\s*\(\s*dec_PB\s*\)", 'MMIO read select: buttons')
T('W_RD_PB', 'Wrapper.v', r"ReadData_MMIO\s*<=.*\bPB\b", 'MMIO read data: buttons')
T('W_RDIN_IF', 'Wrapper.v', r"if\s*\(\s*dec_DMEM_W\s*\)", 'read data mux: DMEM or MMIO')
T('W_RDIN_DMEM', 'Wrapper.v', r"ReadData_in\s*<=\s*ReadData_DMEM", 'read data mux: DMEM')
T('W_RDIN_MMIO', 'Wrapper.v', r"ReadData_in\s*<=\s*ReadData_MMIO", 'read data mux: MMIO')
T('W_DECW', 'Wrapper.v', r"dec_DMEM_W\s*<=", 'dec_DMEM_W = dec_DMEM')
T('W_DMEM_RD', 'Wrapper.v', r"ReadData_DMEM\s*<=\s*DMEM", 'asynchronous DMEM read')
T('W_MEMWRITE', 'Wrapper.v', r"assign\s+MemWrite\s*=", 'overall MemWrite = OR of byte enables')
T('W_DMEM_WR_COL', 'Wrapper.v', r"if\s*\(\s*MemWrite_out\s*\[\s*i\s*\]\s*\)", 'DMEM write: byte enable')
T('W_DMEM_WR_IF', 'Wrapper.v', r"if\s*\(\s*dec_DMEM\s*\)", 'DMEM write: only for DMEM addresses')
T('W_DMEM_WR', 'Wrapper.v', r"DMEM\s*\[\s*ALUResult[^\]]*\]\s*\]\s*\[", 'DMEM write')
T('W_LED_IF', 'Wrapper.v', r"MemWrite_out\s*\[\s*0\s*\]\s*&&\s*dec_LED", 'LED write enable')
T('W_LED_WR', 'Wrapper.v', r"LED_OUT\s*<=\s*WriteData_out", 'LED write')
T('W_SEG_IF', 'Wrapper.v', r"if\s*\(\s*dec_SEVENSEG\s*\)", '7-segment write select')
T('W_SEG_WR', 'Wrapper.v', r"SEVENSEGHEX\s*\[\s*j", '7-segment write')
T('W_LEDPC', 'Wrapper.v', r"assign\s+LED_PC\s*=", 'LED_PC = PC[8:2]')
T('W_RVINST', 'Wrapper.v', r"\bRV\s*#", 'RV instance (port order)')

# original text of every tag line, used to find a line that was edited beyond recognition
CANON = {}  # original text of each line (from the reference copy)
CANON.update({
 "SH_SLL": "2'b00: ShOut = ShIn << Shamt5 ;                 // sll",
 "SH_SRL": "2'b10: ShOut = ShIn >> Shamt5 ;                 // srl",
 "SH_SRA": "2'b11: ShOut = $signed(ShIn) >>> Shamt5 ;       // sra",
 "SH_DEF": "default: ShOut = ShIn ;",
 "ALU_ADDER": "assign S_wider = Src_A_comp + Src_B_comp + C_0 ;",
 "ALU_DEF_C0": "C_0 = 0 ;",
 "ALU_DEF_A": "Src_A_comp = {1'b0, Src_A} ;",
 "ALU_DEF_B": "Src_B_comp = {1'b0, Src_B} ;",
 "ALU_ADD": "4'b0000: ALUResult = S_wider[31:0] ;\t\t// add",
 "ALU_SUB_LBL": "4'b0001: begin\t\t\t\t\t// sub (also used for all branches)",
 "ALU_SUB_C0": "C_0[0] = 1 ;",
 "ALU_SUB_INV": "Src_B_comp = {1'b0, ~ Src_B} ;",
 "ALU_SUB_RES": "ALUResult = S_wider[31:0] ;",
 "ALU_SLT_LBL": "4'b0100: begin\t\t\t\t\t// slt: subtract, then return the signed less-than flag",
 "ALU_SLT_C0": "C_0[0] = 1 ;",
 "ALU_SLT_INV": "Src_B_comp = {1'b0, ~ Src_B} ;",
 "ALU_SLT_RES": "ALUResult = {31'd0, lt} ;",
 "ALU_SLTU_LBL": "4'b0110: begin\t\t\t\t\t// sltu: subtract, then return the unsigned less-than flag",
 "ALU_SLTU_C0": "C_0[0] = 1 ;",
 "ALU_SLTU_INV": "Src_B_comp = {1'b0, ~ Src_B} ;",
 "ALU_SLTU_RES": "ALUResult = {31'd0, ltu} ;",
 "ALU_XOR": "4'b1000: ALUResult = Src_A ^ Src_B ;\t\t// xor",
 "ALU_OR": "4'b1100: ALUResult = Src_A | Src_B ; \t\t// or",
 "ALU_AND": "4'b1110: ALUResult = Src_A & Src_B ;\t\t// and",
 "ALU_SHIFT_LBL": "4'b0010, 4'b1010, 4'b1011:\t\t\t// sll, srl, sra - all done by the Shifter",
 "ALU_SHIFT_RES": "ALUResult = ShOut ;",
 "ALU_N": "assign N = S_wider[31] ;\t\t\t\t// sign of (A - B)",
 "ALU_Z": "assign Z = ~|S_wider[31:0] ;\t\t\t\t// (A - B) == 0; a 32-input NOR, not a 32-bit comparator",
 "ALU_C": "assign C = S_wider[32] ;\t\t\t\t// carry out; for A + ~B + 1 it is 1 exactly when A >= B (unsigned)",
 "ALU_V": "assign V = (Src_A_comp[31] ~^ Src_B_comp[31]) & (Src_A_comp[31] ^ S_wider[31]) ;",
 "ALU_LT": "assign lt  = N ^ V ;\t\t\t\t\t// signed A < B",
 "ALU_LTU": "assign ltu = ~C ;\t\t\t\t\t// unsigned A < B (a borrow happened)",
 "ALU_FLAGS": "assign ALUFlags = {Z, lt, ltu} ; \t\t\t//{eq, lt, ltu}",
 "ALU_SH": "assign Sh = {ALUControl[3], ALUControl[0]} ;\t\t// 00 sll, 10 srl, 11 sra (see Shifter.v)",
 "ALU_SHAMT": "assign Shamt5 = Src_B[4:0] ;\t\t\t\t// rs2[4:0] for sll/srl/sra, imm[4:0] (shamt) for slli/srli/srai",
 "ALU_SHIN": "assign ShIn = Src_A ;",
 "EXT_U": "3'b000: ExtImm = {InstrImm[31:12], 12'h000} ;  // U type",
 "EXT_UJ": "3'b010: ExtImm = {{12{InstrImm[31]}}, InstrImm[19:12], InstrImm[20], InstrImm[30:21], 1'b0} ;   // UJ",
 "EXT_I": "3'b011: ExtImm = {{20{InstrImm[31]}}, InstrImm[31:20]} ;  // I",
 "EXT_S": "3'b110: ExtImm = {{20{InstrImm[31]}}, InstrImm[31:25], InstrImm[11:7]} ;  // S",
 "EXT_SB": "3'b111: ExtImm = {{20{InstrImm[31]}}, InstrImm[7], InstrImm[30:25], InstrImm[11:8], 1'b0} ;  // SB",
 "DEC_DEF_PCS": "PCS        = 2'b00 ;",
 "DEC_DEF_RegWrite": "RegWrite   = 1'b0 ;",
 "DEC_DEF_MemWrite": "MemWrite   = 1'b0 ;",
 "DEC_DEF_MemtoReg": "MemtoReg   = 1'b0 ;",
 "DEC_DEF_ALUSrcA": "ALUSrcA    = 2'b00 ;",
 "DEC_DEF_ALUSrcB": "ALUSrcB    = 2'b00 ;",
 "DEC_DEF_ImmSrc": "ImmSrc     = 3'bxxx ;\t// don't care unless an instruction below uses the immediate",
 "DEC_DEF_ALUControl": "ALUControl = 4'b0000 ;\t// add",
 "DEC_LP_DPREG": "localparam OP_DPREG  = 7'b0110011 ;\t// add, sub, and, or, xor, sll, srl, sra, slt, sltu",
 "DEC_BLK_DPREG": "OP_DPREG: begin\t\t// rd = rs1 op rs2",
 "DEC_DPREG_RegWrite": "RegWrite   = 1'b1 ;",
 "DEC_DPREG_ALUControl": "ALUControl = {Funct3, Funct7[5]} ;\t// Funct7[5] picks sub over add, sra over srl",
 "DEC_LP_DPIMM": "localparam OP_DPIMM  = 7'b0010011 ;\t// addi, andi, ori, xori, slli, srli, srai, slti, sltiu",
 "DEC_BLK_DPIMM": "OP_DPIMM: begin\t\t// rd = rs1 op imm",
 "DEC_DPIMM_RegWrite": "RegWrite   = 1'b1 ;",
 "DEC_DPIMM_ALUSrcB": "ALUSrcB    = 2'b01 ;",
 "DEC_DPIMM_ImmSrc": "ImmSrc     = 3'b011 ;\t\t\t// I-type",
 "DEC_DPIMM_ALUControl": "ALUControl = {Funct3, (Funct3[1:0] == 2'b01) ? Funct7[5] : 1'b0} ;",
 "DEC_LP_LOAD": "localparam OP_LOAD   = 7'b0000011 ;\t// lw",
 "DEC_BLK_LOAD": "OP_LOAD: begin\t\t// rd = mem[rs1 + imm]",
 "DEC_LOAD_RegWrite": "RegWrite   = 1'b1 ;",
 "DEC_LOAD_MemtoReg": "MemtoReg   = 1'b1 ;",
 "DEC_LOAD_ALUSrcB": "ALUSrcB    = 2'b01 ;",
 "DEC_LOAD_ImmSrc": "ImmSrc     = 3'b011 ;\t\t\t// I-type",
 "DEC_LP_STORE": "localparam OP_STORE  = 7'b0100011 ;\t// sw",
 "DEC_BLK_STORE": "OP_STORE: begin\t\t// mem[rs1 + imm] = rs2",
 "DEC_STORE_MemWrite": "MemWrite   = 1'b1 ;",
 "DEC_STORE_ALUSrcB": "ALUSrcB    = 2'b01 ;",
 "DEC_STORE_ImmSrc": "ImmSrc     = 3'b110 ;\t\t\t// S-type",
 "DEC_LP_BRANCH": "localparam OP_BRANCH = 7'b1100011 ;\t// beq, bne, blt, bge, bltu, bgeu",
 "DEC_BLK_BRANCH": "OP_BRANCH: begin\t// compare rs1 - rs2 in the ALU; PC_Logic decides; target = PC + imm",
 "DEC_BRANCH_PCS": "PCS        = 2'b01 ;",
 "DEC_BRANCH_ImmSrc": "ImmSrc     = 3'b111 ;\t\t\t// SB-type",
 "DEC_BRANCH_ALUControl": "ALUControl = 4'b0001 ;\t\t\t// sub, to produce the flags",
 "DEC_LP_JAL": "localparam OP_JAL    = 7'b1101111 ;\t// jal",
 "DEC_BLK_JAL": "OP_JAL: begin\t\t// rd = PC + 4 (computed by the ALU); target = PC + imm",
 "DEC_JAL_PCS": "PCS        = 2'b10 ;",
 "DEC_JAL_RegWrite": "RegWrite   = 1'b1 ;",
 "DEC_JAL_ALUSrcA": "ALUSrcA    = 2'b10 ;\t\t\t// PC",
 "DEC_JAL_ALUSrcB": "ALUSrcB    = 2'b10 ;\t\t\t// 4",
 "DEC_JAL_ImmSrc": "ImmSrc     = 3'b010 ;\t\t\t// UJ-type",
 "DEC_LP_JALR": "localparam OP_JALR   = 7'b1100111 ;\t// jalr",
 "DEC_BLK_JALR": "OP_JALR: begin\t\t// rd = PC + 4 (computed by the ALU); target = (rs1 + imm) & ~1",
 "DEC_JALR_PCS": "PCS        = 2'b11 ;",
 "DEC_JALR_RegWrite": "RegWrite   = 1'b1 ;",
 "DEC_JALR_ALUSrcA": "ALUSrcA    = 2'b10 ;\t\t\t// PC",
 "DEC_JALR_ALUSrcB": "ALUSrcB    = 2'b10 ;\t\t\t// 4",
 "DEC_JALR_ImmSrc": "ImmSrc     = 3'b011 ;\t\t\t// I-type",
 "DEC_LP_LUI": "localparam OP_LUI    = 7'b0110111 ;\t// lui",
 "DEC_BLK_LUI": "OP_LUI: begin\t\t// rd = 0 + (imm << 12)",
 "DEC_LUI_RegWrite": "RegWrite   = 1'b1 ;",
 "DEC_LUI_ALUSrcA": "ALUSrcA    = 2'b01 ;\t\t\t// zero",
 "DEC_LUI_ALUSrcB": "ALUSrcB    = 2'b01 ;",
 "DEC_LUI_ImmSrc": "ImmSrc     = 3'b000 ;\t\t\t// U-type",
 "DEC_LP_AUIPC": "localparam OP_AUIPC  = 7'b0010111 ;\t// auipc",
 "DEC_BLK_AUIPC": "OP_AUIPC: begin\t\t// rd = PC + (imm << 12)",
 "DEC_AUIPC_RegWrite": "RegWrite   = 1'b1 ;",
 "DEC_AUIPC_ALUSrcA": "ALUSrcA    = 2'b10 ;\t\t\t// PC",
 "DEC_AUIPC_ALUSrcB": "ALUSrcB    = 2'b01 ;",
 "DEC_AUIPC_ImmSrc": "ImmSrc     = 3'b000 ;\t\t\t// U-type",
 "DEC_DEFAULT": "default: ;\t\t// unsupported opcode: keep the NOP defaults",
 "PCL_EQ": "wire eq  = ALUFlags[2] ;",
 "PCL_LT": "wire lt  = ALUFlags[1] ;",
 "PCL_LTU": "wire ltu = ALUFlags[0] ;",
 "PCL_F3_000": "3'b000: BranchTaken = eq ;\t// beq",
 "PCL_F3_001": "3'b001: BranchTaken = ~eq ;\t// bne",
 "PCL_F3_100": "3'b100: BranchTaken = lt ;\t// blt",
 "PCL_F3_101": "3'b101: BranchTaken = ~lt ;\t// bge",
 "PCL_F3_110": "3'b110: BranchTaken = ltu ;\t// bltu",
 "PCL_F3_111": "3'b111: BranchTaken = ~ltu ;\t// bgeu",
 "PCL_F3_DEF": "default: BranchTaken = 1'b0 ;\t// 010, 011 are not valid branches: never take them",
 "PCL_PCS_00": "2'b00: PCSrc = 2'b00 ;\t\t\t// not a control instruction: PC + 4",
 "PCL_PCS_01": "2'b01: PCSrc = {1'b0, BranchTaken} ;\t// branch: PC + imm if taken, else PC + 4",
 "PCL_PCS_10": "2'b10: PCSrc = 2'b01 ;\t\t\t// jal: PC + imm",
 "PCL_PCS_11": "2'b11: PCSrc = 2'b11 ;\t\t\t// jalr: rs1 + imm",
 "RF_RD1": "RD1 <= (rs1 == 5'b00000) ? 32'd0 : RegBank[rs1] ;",
 "RF_RD2": "RD2 <= (rs2 == 5'b00000) ? 32'd0 : RegBank[rs2] ;",
 "RF_WCOND": "if((rd != 5'b00000) & (WE))",
 "RF_WRITE": "RegBank[rd] <= WD ;",
 "PC_RST_IF": "if(RESET)",
 "PC_RST_LOAD": "PC <= PC_INIT;",
 "PC_WE_IF": "else if(WE_PC)",
 "PC_LOAD": "PC <= PC_INIT;",
 "RV_OPC": "assign Opcode   = Instr[6:0] ;",
 "RV_RD": "assign rd       = Instr[11:7] ;",
 "RV_F3": "assign Funct3   = Instr[14:12] ;",
 "RV_RS1": "assign rs1      = Instr[19:15] ;",
 "RV_RS2": "assign rs2      = Instr[24:20] ;",
 "RV_F7": "assign Funct7   = Instr[31:25] ;",
 "RV_IMM": "assign InstrImm = Instr[31:7] ;\t// Extend picks the immediate bits out of this according to ImmSrc",
 "RV_WE": "assign WE     = RegWrite ;",
 "RV_RESULT": "assign Result = MemtoReg ? ReadData : ALUResult ;\t// lw writes memory data, everything else writes the ALU result",
 "RV_WD": "assign WD     = Result ;",
 "RV_WRITEDATA": "assign WriteData = RD2 ;",
 "RV_WDOUT": "assign WriteData_out = WriteData;    // Change datapath as appropriate if supporting sb/sh",
 "RV_MWOUT": "assign MemWrite_out = {4{MemWrite}}; // Change datapath as appropriate if supporting sb/sh",
 "RV_MEMREAD": "assign MemRead = MemtoReg; // This is needed for the proper functionality of some devices such as UART CONSOLE",
 "RV_READDATA": "assign ReadData = ReadData_in;       // Change datapath as appropriate if supporting lb/lbu/lh/lhu",
 "RV_WEPC": "assign WE_PC = 1 ;  // Will need to control it for multi-cycle operations (Multiplication, Division) and/or Pipelining with hazard hardware.",
 "RV_PCB": "assign PC_Base   = PCSrc[1] ? RD1 : PC ;",
 "RV_PCO": "assign PC_Offset = PCSrc[0] ? ExtImm : 32'd4 ;",
 "RV_PCSUM": "assign PC_Sum    = PC_Base + PC_Offset ;",
 "RV_PCIN": "assign PC_IN     = {PC_Sum[31:1], 1'b0} ;\t// jalr target is (rs1 + imm) & ~1. For every other case",
 "RV_SRCA0": "2'b00:   Src_A = RD1 ;\t\t// normal case: rs1",
 "RV_SRCA1": "2'b01:   Src_A = 32'd0 ;\t\t// lui:  0 + imm",
 "RV_SRCA2": "2'b10:   Src_A = PC ;\t\t// auipc: PC + imm; jal/jalr link: PC + 4",
 "RV_SRCB0": "2'b00:   Src_B = RD2 ;\t\t// DP register type, branches (compare rs1 with rs2)",
 "RV_SRCB1": "2'b01:   Src_B = ExtImm ;\t\t// DP immediate, lw/sw address, lui, auipc",
 "RV_SRCB2": "2'b10:   Src_B = 32'd4 ;\t\t// jal/jalr link value PC + 4",
 "W_IROM_COND": "Instr = ( ( PC[31:IROM_DEPTH_BITS] == IROM_BASE[31:IROM_DEPTH_BITS]) && // To check if address is in the valid range",
 "W_IROM": "IROM[PC[IROM_DEPTH_BITS-1:2]] : 32'h00000013 ; // If the address is invalid, the instruction fetched is NOP.",
 "W_DMEM_RANGE": "if(ALUResult[31:DMEM_DEPTH_BITS] == DMEM_BASE[31:DMEM_DEPTH_BITS])",
 "W_DMEM_DEC": "dec_DMEM <= 1'b1;",
 "W_MMIO_RANGE": "else if (ALUResult[31:MMIO_DEPTH_BITS] == MMIO_BASE[31:MMIO_DEPTH_BITS]) begin",
 "W_CASE_DIP": "DIP_OFF[MMIO_DEPTH_BITS-1:2]: dec_DIP <= 1'b1;",
 "W_CASE_PB": "PB_OFF[MMIO_DEPTH_BITS-1:2]: dec_PB <= 1'b1;",
 "W_CASE_LED": "LED_OFF[MMIO_DEPTH_BITS-1:2]: dec_LED <= 1'b1;",
 "W_CASE_SEG": "SEVENSEG_OFF[MMIO_DEPTH_BITS-1:2]: dec_SEVENSEG <= 1'b1;",
 "W_RD_DIP_IF": "if (dec_DIP)",
 "W_RD_DIP": "ReadData_MMIO <= { {31-N_DIPs+1{1'b0}}, DIP } ;",
 "W_RD_PB_IF": "else if (dec_PB)",
 "W_RD_PB": "ReadData_MMIO <= { {31-N_PBs+1{1'b0}}, PB } ;",
 "W_RDIN_IF": "if (dec_DMEM_W)",
 "W_RDIN_DMEM": "ReadData_in <= ReadData_DMEM ;",
 "W_RDIN_MMIO": "ReadData_in <= ReadData_MMIO ;",
 "W_DECW": "dec_DMEM_W <= dec_DMEM;",
 "W_DMEM_RD": "ReadData_DMEM <= DMEM[ALUResult[DMEM_DEPTH_BITS-1:2]] ; // async read",
 "W_MEMWRITE": "assign MemWrite = MemWrite_out[3] || MemWrite_out[2] || MemWrite_out[1] || MemWrite_out[0];",
 "W_DMEM_WR_COL": "if(MemWrite_out[i]) begin",
 "W_DMEM_WR_IF": "if( dec_DMEM ) begin",
 "W_DMEM_WR": "DMEM[ALUResult[DMEM_DEPTH_BITS-1:2]][i*COL_WIDTH +: COL_WIDTH] <= WriteData_out[i*COL_WIDTH +: COL_WIDTH];",
 "W_LED_IF": "else if( MemWrite_out[0] && dec_LED )",
 "W_LED_WR": "LED_OUT <= WriteData_out[N_LEDs_OUT-1 : 0] ;",
 "W_SEG_IF": "else if (dec_SEVENSEG)",
 "W_SEG_WR": "SEVENSEGHEX[j*COL_WIDTH +: COL_WIDTH] <= WriteData_out[j*COL_WIDTH +: COL_WIDTH];",
 "W_LEDPC": "assign LED_PC = PC[15-N_LEDs_OUT+1 : 2]; // debug showing PC",
 "W_RVINST": "RV #(.PC_INIT(PC_INIT)) RV1("
})


# =============================================================================================
# Finding files and lines
# =============================================================================================
RTL_FILES = ['Shifter.v', 'ALU.v', 'Extend.v', 'Decoder.v', 'PC_Logic.v', 'RegFile.v', 'ProgramCounter.v', 'MCycle.v', 'RV.v', 'Wrapper.v']
SKIP_DIR = re.compile(r'\.(sim|runs|cache|gen|hw|ip_user_files)$|^\.Xil$|^\.git$|^' + WORK_DIR_NAME + '$', re.I)


def find_files(root, names):
    found = {n: [] for n in names}
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if not SKIP_DIR.search(d)]
        for f in fns:
            if f in found:
                found[f].append(os.path.join(dp, f))
    return found


def pick(paths, prefer):
    if not paths:
        return None
    for p in prefer:
        for path in paths:
            if p in path.replace('\\', '/'):
                return path
    return paths[0]


def code_only(text):
    """Blank out comments but keep line numbers."""
    text = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text, flags=re.S)
    return [ln.split('//')[0] for ln in text.split('\n')]


class Source:
    def __init__(self, paths):
        self.paths = paths
        self.raw, self.code = {}, {}
        for f, p in paths.items():
            with open(p, encoding='utf-8', errors='replace') as fh:
                txt = fh.read()
            self.raw[f] = txt.split('\n')
            self.code[f] = code_only(txt)

    def locate(self, tag):
        """-> (line_number or None, line_text, status) ; status 'ok' | 'edited?' | 'missing'"""
        t = TAGS[tag]
        f = t['file']
        code, raw = self.code[f], self.raw[f]
        rng = range(len(code))
        if t['anchor']:
            a = next((i for i in rng if re.search(t['anchor'], code[i])), None)
            if a is not None:
                rng = range(a, min(a + t['span'] + 1, len(code)))
            else:
                rng = None
        if rng is not None:
            for i in rng:
                if re.search(t['rx'], code[i]):
                    return i + 1, raw[i].strip(), 'ok'
        canon = CANON.get(tag)
        if canon:
            best, best_r = None, 0.0
            search = rng if rng is not None else range(len(raw))
            for i in search:
                ln = raw[i]
                r = difflib.SequenceMatcher(None, canon, ln.strip()).ratio()
                if r > best_r:
                    best, best_r = i, r
            if best is not None and best_r > 0.6:
                return best + 1, raw[best].strip(), 'edited?'
        return None, CANON.get(tag, ''), 'missing'


# =============================================================================================
# Python reference model
# =============================================================================================
def alu_model(ctl, a, b):
    a &= M32
    b &= M32
    if ctl == 0b0000: return (a + b) & M32
    if ctl == 0b0001: return (a - b) & M32
    if ctl == 0b0100: return int(s32(a) < s32(b))
    if ctl == 0b0110: return int(a < b)
    if ctl == 0b1000: return a ^ b
    if ctl == 0b1100: return a | b
    if ctl == 0b1110: return a & b
    if ctl == 0b0010: return (a << (b & 31)) & M32
    if ctl == 0b1010: return a >> (b & 31)
    if ctl == 0b1011: return (s32(a) >> (b & 31)) & M32
    raise ValueError(ctl)


def shifter_model(sh, amt, x):
    if sh == 0: return (x << amt) & M32
    if sh == 2: return x >> amt
    if sh == 3: return (s32(x) >> amt) & M32
    return x


def extend_model(src, v25):
    ins = (v25 & ((1 << 25) - 1)) << 7
    if src == 0: return ins & 0xFFFFF000
    if src == 2: return sx((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21) & M32
    if src == 3: return sx(ins >> 20, 12) & M32
    if src == 6: return sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12) & M32
    if src == 7: return sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13) & M32
    raise ValueError(src)


def decoder_model(op, f3, f7):
    """Expected decoder outputs; ImmSrc None = don't care. For unsupported opcodes only the
    state-changing signals are returned."""
    b5 = (f7 >> 5) & 1
    o = dict(PCS=0, RegWrite=0, MemWrite=0, MemtoReg=0, ALUSrcA=0, ALUSrcB=0, ImmSrc=None, ALUControl=0)
    if op == 0x33 and f7 == 0x01:     # Assignment 3: RV32M goes to MCycle (mulhsu, funct3 010, is a NOP).
        o.update(RegWrite=0 if f3 == 2 else 1)  # MCycle itself is tested by test_MCycle.v / test_Wrapper.v
    elif op == 0x33:
        o.update(RegWrite=1, ALUControl=(f3 << 1) | b5)
    elif op == 0x13:
        o.update(RegWrite=1, ALUSrcB=1, ImmSrc=3, ALUControl=(f3 << 1) | (b5 if (f3 & 3) == 1 else 0))
    elif op == 0x03:
        o.update(RegWrite=1, MemtoReg=1, ALUSrcB=1, ImmSrc=3)
    elif op == 0x23:
        o.update(MemWrite=1, ALUSrcB=1, ImmSrc=6)
    elif op == 0x63:
        o.update(PCS=1, ImmSrc=7, ALUControl=1)
    elif op == 0x6F:
        o.update(PCS=2, RegWrite=1, ALUSrcA=2, ALUSrcB=2, ImmSrc=2)
    elif op == 0x67:
        o.update(PCS=3, RegWrite=1, ALUSrcA=2, ALUSrcB=2, ImmSrc=3)
    elif op == 0x37:
        o.update(RegWrite=1, ALUSrcA=1, ALUSrcB=1, ImmSrc=0)
    elif op == 0x17:
        o.update(RegWrite=1, ALUSrcA=2, ALUSrcB=1, ImmSrc=0)
    else:
        return {k: o[k] for k in ('PCS', 'RegWrite', 'MemWrite', 'MemtoReg')}
    return o


def pclogic_model(pcs, f3, flags):
    eq, lt, ltu = (flags >> 2) & 1, (flags >> 1) & 1, flags & 1
    taken = {0: eq, 1: 1 - eq, 4: lt, 5: 1 - lt, 6: ltu, 7: 1 - ltu}.get(f3, 0)
    return {0: 0, 1: taken, 2: 1, 3: 3}[pcs]


# ---- instruction encoders
def enc_r(f7, rs2, rs1, f3, rd, op): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def enc_i(imm, rs1, f3, rd, op): return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 31) << 7) | op


def enc_b(imm, rs2, rs1, f3, op):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
        (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | op


def enc_u(imm20, rd, op): return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


def enc_j(imm, rd, op):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | op


R_OPS = [('add', 0, 0), ('sub', 0, 0x20), ('sll', 1, 0), ('slt', 2, 0), ('sltu', 3, 0), ('xor', 4, 0), ('srl', 5, 0), ('sra', 5, 0x20), ('or', 6, 0), ('and', 7, 0)]
I_OPS = [('addi', 0), ('slti', 2), ('sltiu', 3), ('xori', 4), ('ori', 6), ('andi', 7)]
SH_OPS = [('slli', 1, 0), ('srli', 5, 0), ('srai', 5, 0x20)]
B_OPS = [('beq', 0), ('bne', 1), ('blt', 4), ('bge', 5), ('bltu', 6), ('bgeu', 7)]


def execute(ins, pc, regs, rdata):
    """One instruction on the reference model. regs: dict index->value (x0 = 0)."""
    r = lambda i: 0 if i == 0 else regs.get(i, 0)
    op, rd, f3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
    rs1, rs2, f7 = (ins >> 15) & 31, (ins >> 20) & 31, ins >> 25
    a, b = r(rs1), r(rs2)
    imm_i = sx(ins >> 20, 12) & M32
    imm_s = sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12) & M32
    imm_b = extend_model(7, ins >> 7)
    imm_j = extend_model(2, ins >> 7)
    imm_u = ins & 0xFFFFF000
    out = dict(alu=None, write=None, mem=0, memread=0, wdata=None, next=(pc + 4) & M32)
    if op == 0x33:
        out['alu'] = alu_model((f3 << 1) | ((f7 >> 5) & 1), a, b); out['write'] = out['alu']
    elif op == 0x13:
        ctl = (f3 << 1) | (((f7 >> 5) & 1) if (f3 & 3) == 1 else 0)
        out['alu'] = alu_model(ctl, a, imm_i); out['write'] = out['alu']
    elif op == 0x03:
        out['alu'] = (a + imm_i) & M32; out['write'] = rdata; out['memread'] = 1
    elif op == 0x23:
        out['alu'] = (a + imm_s) & M32; out['mem'] = 1; out['wdata'] = b
    elif op == 0x63:
        out['alu'] = (a - b) & M32
        flags = (int(a == b) << 2) | (int(s32(a) < s32(b)) << 1) | int(a < b)
        if pclogic_model(1, f3, flags):
            out['next'] = (pc + imm_b) & M32
    elif op == 0x6F:
        out['alu'] = (pc + 4) & M32; out['write'] = out['alu']; out['next'] = (pc + imm_j) & M32
    elif op == 0x67:
        out['alu'] = (pc + 4) & M32; out['write'] = out['alu']; out['next'] = (a + imm_i) & M32 & ~1
    elif op == 0x37:
        out['alu'] = imm_u; out['write'] = imm_u
    elif op == 0x17:
        out['alu'] = (pc + imm_u) & M32; out['write'] = out['alu']
    return out


# =============================================================================================
# Testbench generation
# =============================================================================================
class Suite:
    def __init__(self):
        self.checks = []
        self.v = []

    def chk(self, stage, module, expr, width, exp, desc, tags):
        cid = len(self.checks)
        self.checks.append(dict(id=cid, stage=stage, module=module, desc=desc, exp=exp, width=width, tags=sorted(set(tags))))
        self.v.append('if (%s !== %s) $display("F %d %%h", %s);' % (expr, vh(exp, width), cid, expr))

    def line(self, s):
        self.v.append(s)


def gen_shifter(S, rnd):
    vals = [0x80000001, 0x12345678, 0xF0F0F0F0, 0x7FFFFFFF] + [rnd.getrandbits(32) for _ in range(2)]
    for sh in range(4):
        tag = {0: 'SH_SLL', 1: 'SH_DEF', 2: 'SH_SRL', 3: 'SH_SRA'}[sh]
        for amt in range(32):
            x = vals[amt % len(vals)] ^ (amt * 0x01010101 if amt % 3 == 0 else 0)
            S.line('sh_Sh = 2\'d%d; sh_amt = 5\'d%d; sh_in = %s; #1;' % (sh, amt, vh(x)))
            S.chk('unit', 'Shifter', 'sh_out', 32, shifter_model(sh, amt, x),
                  'Shifter Sh=%s Shamt5=%d ShIn=%08X' % (format(sh, '02b'), amt, x), [tag])


def gen_alu(S, rnd):
    corners = [0, 1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x80000001, 0x7FFFFFFE]
    pairs = [(a, b) for a in corners for b in corners] + [(rnd.getrandbits(32), rnd.getrandbits(32)) for _ in range(40)]
    pairs += [(x, x) for x in (rnd.getrandbits(32) for _ in range(6))]
    ops = [('add', 0b0000), ('sub', 0b0001), ('sll', 0b0010), ('slt', 0b0100), ('sltu', 0b0110), ('xor', 0b1000),
           ('srl', 0b1010), ('sra', 0b1011), ('or', 0b1100), ('and', 0b1110)]
    sub_core = ['ALU_ADDER', 'ALU_DEF_A', 'ALU_SUB_LBL', 'ALU_SUB_C0', 'ALU_SUB_INV']
    for name, ctl in ops:
        for a, b in pairs:
            if name in ('sll', 'srl', 'sra') and rnd.random() < 0.5:
                b = (b & ~31) | rnd.randint(1, 31)
            S.line("alu_ctl = 4'b%s; alu_a = %s; alu_b = %s; #1;" % (format(ctl, '04b'), vh(a), vh(b)))
            signs_differ = (a >> 31) != (b >> 31)
            if name == 'add':
                tags = ['ALU_ADDER', 'ALU_DEF_A', 'ALU_DEF_B', 'ALU_DEF_C0', 'ALU_ADD']
            elif name == 'sub':
                tags = sub_core + ['ALU_SUB_RES']
            elif name in ('slt', 'sltu'):
                p = 'ALU_' + name.upper()
                tags = ['ALU_ADDER', 'ALU_DEF_A', p + '_LBL', p + '_C0', p + '_INV', p + '_RES']
                tags += (['ALU_N', 'ALU_LT'] + (['ALU_V'] if signs_differ else [])) if name == 'slt' else ['ALU_C', 'ALU_LTU']
            elif name in ('xor', 'or', 'and'):
                tags = ['ALU_' + name.upper()]
            else:
                tags = ['ALU_SHIFT_LBL', 'ALU_SHIFT_RES', 'ALU_SH', 'ALU_SHIN'] + (['ALU_SHAMT'] if b & 31 else []) + \
                       [{'sll': 'SH_SLL', 'srl': 'SH_SRL', 'sra': 'SH_SRA'}[name]]
            S.chk('unit', 'ALU', 'alu_res', 32, alu_model(ctl, a, b), 'ALU %s A=%08X B=%08X: ALUResult' % (name, a, b), tags)
            if name == 'sub':
                S.chk('unit', 'ALU', 'alu_flags[2]', 1, int(a == b), 'ALU flags (sub) A=%08X B=%08X: eq' % (a, b),
                      sub_core + ['ALU_Z', 'ALU_FLAGS'])
                S.chk('unit', 'ALU', 'alu_flags[1]', 1, int(s32(a) < s32(b)), 'ALU flags (sub) A=%08X B=%08X: lt' % (a, b),
                      sub_core + ['ALU_N', 'ALU_LT', 'ALU_FLAGS'] + (['ALU_V'] if signs_differ else []))
                S.chk('unit', 'ALU', 'alu_flags[0]', 1, int(a < b), 'ALU flags (sub) A=%08X B=%08X: ltu' % (a, b),
                      sub_core + ['ALU_C', 'ALU_LTU', 'ALU_FLAGS'])


def gen_extend(S, rnd):
    names = {0: 'EXT_U', 2: 'EXT_UJ', 3: 'EXT_I', 6: 'EXT_S', 7: 'EXT_SB'}
    for src, tag in names.items():
        vals = [0, (1 << 25) - 1, 1 << 24, (1 << 24) - 1] + [rnd.getrandbits(25) for _ in range(16)]
        for v in vals:
            S.line("ex_src = 3'b%s; ex_in = %s; #1;" % (format(src, '03b'), vh(v, 25)))
            S.chk('unit', 'Extend', 'ex_out', 32, extend_model(src, v), 'Extend ImmSrc=%s Instr[31:7]=%07X' % (format(src, '03b'), v), [tag])


def gen_decoder(S, rnd):
    by_op = {op: (name, sigs) for name, op, sigs in DEC_OPS}
    widths = dict(DEC_SIGS)
    vec = []
    for op in by_op:
        for f3 in range(8):
            for f7 in (0x00, 0x20, rnd.getrandbits(7) & ~0x20, rnd.getrandbits(7) | 0x20) + ((0x01,) if op == 0x33 else ()):
                vec.append((op, f3, f7))
    for op in range(128):
        if op not in by_op:
            vec.append((op, rnd.randint(0, 7), rnd.getrandbits(7)))
    for op, f3, f7 in vec:
        S.line("d_op = 7'b%s; d_f3 = 3'b%s; d_f7 = 7'b%s; #1;" % (format(op, '07b'), format(f3, '03b'), format(f7, '07b')))
        exp = decoder_model(op, f3, f7)
        name = by_op[op][0] if op in by_op else 'unsupported'
        for sig, val in exp.items():
            if val is None:
                continue
            if op in by_op:
                bname, sigs = by_op[op]
                # a signal left at its default is 0 whether or not the case label matched,
                # so only signals the block sets depend on the opcode value / label
                tags = ['DEC_LP_' + bname, 'DEC_BLK_' + bname, 'DEC_%s_%s' % (bname, sig)] if sig in sigs else ['DEC_DEF_' + sig]
            else:
                tags = ['DEC_DEF_' + sig, 'DEC_DEFAULT']
            S.chk('unit', 'Decoder', 'd_' + sig, widths[sig], val,
                  'Decoder opcode=%s (%s) funct3=%s funct7=%s: %s' % (format(op, '07b'), name, format(f3, '03b'), format(f7, '07b'), sig), tags)
        # Assignment 3: MCycle control (RV32M = opcode 0110011, funct7 0000001; mulhsu unsupported)
        is_m = op == 0x33 and f7 == 0x01 and f3 != 2
        mexp = dict(MStart=int(is_m), MCycleSel=int(is_m))
        if is_m:
            mexp['MCycleOp'] = {0: 0, 1: 0, 3: 1, 4: 2, 5: 3, 6: 2, 7: 3}[f3]
            mexp['MResultSel'] = {0: 0, 1: 1, 3: 1, 4: 0, 5: 0, 6: 1, 7: 1}[f3]
        for sig, val in mexp.items():
            S.chk('unit', 'Decoder', 'd_' + sig, 2 if sig == 'MCycleOp' else 1, val,
                  'Decoder opcode=%s funct3=%s funct7=%s: %s' % (format(op, '07b'), format(f3, '03b'), format(f7, '07b'), sig), ['DEC_DEFAULT'])


def gen_pclogic(S):
    flagw = {0: 'PCL_EQ', 1: 'PCL_EQ', 4: 'PCL_LT', 5: 'PCL_LT', 6: 'PCL_LTU', 7: 'PCL_LTU'}
    for pcs in range(4):
        for f3 in range(8):
            for flags in range(8):
                S.line("p_pcs = 2'b%s; p_f3 = 3'b%s; p_flags = 3'b%s; #1;" % (format(pcs, '02b'), format(f3, '03b'), format(flags, '03b')))
                tags = ['PCL_PCS_' + format(pcs, '02b')]
                if pcs == 1:
                    tags += ['PCL_F3_' + format(f3, '03b')] if f3 in flagw else ['PCL_F3_DEF']
                    tags += [flagw[f3]] if f3 in flagw else []
                S.chk('unit', 'PC_Logic', 'p_src', 2, pclogic_model(pcs, f3, flags),
                      'PC_Logic PCS=%s Funct3=%s ALUFlags{eq,lt,ltu}=%s: PCSrc' % (format(pcs, '02b'), format(f3, '03b'), format(flags, '03b')), tags)


def gen_regfile(S):
    val = lambda r: (0x9E3779B9 * r ^ (r << 27) ^ 0x5A5A0000) & M32
    S.line("rf_clk = 0; rf_we = 1;")
    for r in range(1, 32):
        S.line("rf_rd = 5'd%d; rf_wd = %s; #1 rf_clk = 1; #1 rf_clk = 0;" % (r, vh(val(r))))
    S.line("rf_we = 0;")
    for r in range(1, 32):
        r2 = 32 - r
        S.line("rf_rs1 = 5'd%d; rf_rs2 = 5'd%d; #1;" % (r, r2))
        S.chk('unit', 'RegFile', 'rf_rd1', 32, val(r), 'RegFile write x%d then read on port 1 (rs1)' % r, ['RF_RD1', 'RF_WCOND', 'RF_WRITE'])
        S.chk('unit', 'RegFile', 'rf_rd2', 32, val(r2), 'RegFile write x%d then read on port 2 (rs2)' % r2, ['RF_RD2', 'RF_WCOND', 'RF_WRITE'])
    # x0: write attempt must not change the stored value, and reads give 0
    S.line("rf_we = 1; rf_rd = 5'd0; rf_wd = 32'hdeadbeef; #1 rf_clk = 1; #1 rf_clk = 0; rf_we = 0;")
    S.line("rf_rs1 = 5'd0; rf_rs2 = 5'd0; #1;")
    S.chk('unit', 'RegFile', 'rf_rd1', 32, 0, 'RegFile x0 reads as 0 on port 1', ['RF_RD1'])
    S.chk('unit', 'RegFile', 'rf_rd2', 32, 0, 'RegFile x0 reads as 0 on port 2', ['RF_RD2'])
    S.v.append('if (u_rf.RegBank[0] === 32\'hdeadbeef) $display("F %d %%h", u_rf.RegBank[0]);' % len(S.checks))
    S.checks.append(dict(id=len(S.checks), stage='unit', module='RegFile', desc='RegFile: a write to x0 must be ignored',
                         exp='not deadbeef', width=32, tags=['RF_WCOND']))
    # WE = 0 must not write
    S.line("rf_we = 0; rf_rd = 5'd5; rf_wd = 32'h01234567; #1 rf_clk = 1; #1 rf_clk = 0;")
    S.line("rf_rs1 = 5'd5; rf_rs2 = 5'd6; #1;")
    S.chk('unit', 'RegFile', 'rf_rd1', 32, val(5), 'RegFile: WE=0 must not write x5', ['RF_WCOND'])


def gen_pc(S):
    S.line("pc_clk = 0;")
    seq = [  # rst, we, in, expected, desc, tags
        (1, 0, 0x12345678, 0x00400000, 'reset loads PC_INIT', ['PC_RST_IF', 'PC_RST_LOAD']),
        (0, 1, 0x00400010, 0x00400010, 'WE_PC=1 loads PC_IN', ['PC_WE_IF', 'PC_LOAD']),
        (0, 0, 0xAAAAAAA8, 0x00400010, 'WE_PC=0 holds PC', ['PC_WE_IF']),
        (0, 1, 0xFFFFFFFC, 0xFFFFFFFC, 'WE_PC=1 loads PC_IN', ['PC_WE_IF', 'PC_LOAD']),
        (1, 1, 0x13572468, 0x00400000, 'reset has priority over WE_PC', ['PC_RST_IF', 'PC_RST_LOAD']),
        (0, 1, 0x10010040, 0x10010040, 'WE_PC=1 loads PC_IN', ['PC_WE_IF', 'PC_LOAD']),
        (0, 0, 0x00000000, 0x10010040, 'WE_PC=0 holds PC', ['PC_WE_IF']),
    ]
    for rst, we, pin, exp, desc, tags in seq:
        S.line("pc_rst = %d; pc_we = %d; pc_in = %s; #1 pc_clk = 1; #1 pc_clk = 0;" % (rst, we, vh(pin)))
        S.chk('unit', 'ProgramCounter', 'pc_out', 32, exp, 'ProgramCounter: %s (RESET=%d WE_PC=%d PC_IN=%08X)' % (desc, rst, we, pin), tags)


def gen_rv(S, rnd):
    """Every instruction type through the RV datapath, one instruction at a time."""
    corner = [0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x80000001]
    rv = lambda: rnd.choice(corner) if rnd.random() < 0.25 else rnd.getrandbits(32)
    tests = []
    for _ in range(6):
        for n, f3, f7 in R_OPS: tests.append(('R', n, f3, f7))
        for n, f3 in I_OPS: tests.append(('I', n, f3, 0))
        for n, f3, f7 in SH_OPS: tests.append(('ISH', n, f3, f7))
        for n, f3 in B_OPS: tests.append(('B', n, f3, 0))
        for k in ('LW', 'SW', 'JAL', 'JALR', 'LUI', 'AUIPC'): tests.append((k, k.lower(), 0, 0))
    for _ in range(4):
        for n, f3 in B_OPS: tests.append(('Beq', n, f3, 0))   # equal operands -> the other outcome
    meta = {  # ALUSrcA, ALUSrcB
        'R': (0, 0), 'I': (0, 1), 'ISH': (0, 1), 'LW': (0, 1), 'SW': (0, 1), 'B': (0, 0), 'Beq': (0, 0),
        'JAL': (2, 2), 'JALR': (2, 2), 'LUI': (1, 1), 'AUIPC': (2, 1)}
    S.line("rv_rst = 0; rv_clk = 0; rv_rdata = 0;")
    for kind, name, f3, f7 in tests:
        rs1, rs2, rd = rnd.randint(1, 31), rnd.randint(1, 31), rnd.randint(1, 31)
        while rd in (rs1, rs2):
            rd = rnd.randint(1, 31)
        if kind == 'R':
            ins = enc_r(f7, rs2, rs1, f3, rd, 0x33)
        elif kind == 'I':
            ins = enc_i(rnd.choice([rnd.randint(-2048, 2047), rnd.randint(-2048, -1024), -1, 2047]), rs1, f3, rd, 0x13)
        elif kind == 'ISH':
            ins = enc_r(f7, rnd.randint(1, 31), rs1, f3, rd, 0x13)
        elif kind == 'LW':
            ins = enc_i(rnd.randint(-2048, 2047) & ~3, rs1, 2, rd, 0x03)
        elif kind == 'SW':
            ins = enc_s(rnd.randint(-2048, 2047) & ~3, rs2, rs1, 2, 0x23)
        elif kind in ('B', 'Beq'):
            ins = enc_b(rnd.randint(-2048, 2047) * 2, rs2, rs1, f3, 0x63)
        elif kind == 'JAL':
            ins = enc_j(rnd.randint(-(1 << 19), (1 << 19) - 1) * 2, rd, 0x6F)
        elif kind == 'JALR':
            ins = enc_i(rnd.randint(-2048, 2047), rs1, 0, rd, 0x67)
        elif kind == 'LUI':
            ins = enc_u(rnd.getrandbits(20), rd, 0x37)
        else:
            ins = enc_u(rnd.getrandbits(20), rd, 0x17)
        rdfield = (ins >> 7) & 31
        regs = {rs1: rv(), rs2: rv()}
        if kind == 'Beq':
            regs[rs2] = regs[rs1]
        if rdfield and rdfield not in regs:
            regs[rdfield] = rv()
        pc = rnd.getrandbits(30) << 2
        rdata = rnd.getrandbits(32)
        exp = execute(ins, pc, regs, rdata)

        asa, asb = meta[kind]
        is_branch = kind in ('B', 'Beq')
        alu_tags = ['RV_OPC', 'RV_SRCA%d' % asa, 'RV_SRCB%d' % asb] + (['RV_RS1'] if asa == 0 else []) + \
                   (['RV_RS2'] if asb == 0 else []) + (['RV_IMM'] if asb == 1 else []) + \
                   (['RV_F3'] if kind in ('R', 'I', 'ISH', 'B', 'Beq') else []) + (['RV_F7'] if kind in ('R', 'ISH') else [])
        desc = '%s (PC=%08X, instr=%08X)' % (name, pc, ins)

        # drive: set PC and registers, then a different instruction (add x0, rs1, rs2) so every
        # register read is re-evaluated and Src_A/Src_B hold non-zero values (exposes latches),
        # then the instruction under test
        S.line("rv_clk = 0; rv_instr = 32'h00000013; #1;")
        S.line("u_rv.ProgramCounter1.PC = %s;" % vh(pc))
        for i, v in regs.items():
            S.line("u_rv.RegFile1.RegBank[%d] = %s;" % (i, vh(v)))
        S.line("rv_instr = %s; #1;" % vh(enc_r(0, rs2, rs1, 0, 0, 0x33)))
        S.line("rv_rdata = %s; rv_instr = %s; #1;" % (vh(rdata), vh(ins)))
        S.chk('rv', 'RV', 'rv_alu', 32, exp['alu'], 'RV %s: ALUResult' % desc, alu_tags)
        S.chk('rv', 'RV', 'rv_mw', 4, 0xF if exp['mem'] else 0, 'RV %s: MemWrite_out' % desc, ['RV_OPC', 'RV_MWOUT'])
        S.chk('rv', 'RV', 'rv_memread', 1, exp['memread'], 'RV %s: MemRead' % desc, ['RV_OPC', 'RV_MEMREAD'])
        if exp['wdata'] is not None:
            S.chk('rv', 'RV', 'rv_wdata', 32, exp['wdata'], 'RV %s: WriteData_out (rs2)' % desc, ['RV_WRITEDATA', 'RV_WDOUT', 'RV_RS2'])
        S.line("#1 rv_clk = 1; #1;")
        pc_tags = ['RV_PCB', 'RV_PCO', 'RV_PCSUM', 'RV_PCIN', 'RV_WEPC', 'RV_OPC']
        taken = exp['next'] != ((pc + 4) & M32)
        if kind in ('JAL', 'JALR') or (is_branch and taken):
            pc_tags.append('RV_IMM')
        if kind == 'JALR':
            pc_tags.append('RV_RS1')
        if is_branch:
            pc_tags += ['RV_F3', 'RV_SRCA0', 'RV_SRCB0', 'RV_RS1', 'RV_RS2']
        S.chk('rv', 'RV', 'u_rv.ProgramCounter1.PC', 32, exp['next'], 'RV %s: next PC%s' % (desc, ' (taken)' if taken and is_branch else ''), pc_tags)
        if exp['write'] is not None:
            tags = ['RV_OPC', 'RV_RD', 'RV_WE', 'RV_RESULT', 'RV_WD'] + (['RV_READDATA'] if kind == 'LW' else alu_tags)
            S.chk('rv', 'RV', 'u_rv.RegFile1.RegBank[%d]' % rd, 32, exp['write'], 'RV %s: value written to x%d' % (desc, rd), tags)
        elif rdfield:
            S.chk('rv', 'RV', 'u_rv.RegFile1.RegBank[%d]' % rdfield, 32, regs[rdfield],
                  'RV %s: must not write a register (x%d changed)' % (desc, rdfield), ['RV_OPC', 'RV_WE', 'RV_RD'])
    S.line("rv_clk = 0; #1;")


# ---- Wrapper program
WR_DIP, WR_PB = 0xA5C3, 0b101
HALT_WORD = 45


def wrapper_program():
    p = [
        enc_u(0x10010, 8, 0x37),        # 0  lui  s0, 0x10010      s0 = 0x10010000
        enc_i(0, 8, 2, 5, 0x03),         # 1  lw   t0, 0(s0)       t0 = DMEM[0]
        enc_i(8, 8, 2, 6, 0x03),         # 2  lw   t1, 8(s0)       t1 = DMEM[2]
        enc_s(4, 6, 8, 2, 0x23),         # 3  sw   t1, 4(s0)       DMEM[1] = t1
        enc_i(4, 8, 2, 7, 0x03),         # 4  lw   t2, 4(s0)       t2 = DMEM[1]
        enc_u(0xFFFF0, 9, 0x37),         # 5  lui  s1, 0xFFFF0     s1 = 0xFFFF0000
        enc_i(0x64, 9, 2, 28, 0x03),     # 6  lw   t3, 0x64(s1)    switches
        enc_i(0x68, 9, 2, 29, 0x03),     # 7  lw   t4, 0x68(s1)    buttons
        enc_s(0x60, 5, 9, 2, 0x23),      # 8  sw   t0, 0x60(s1)    LEDs
        enc_s(0x80, 6, 9, 2, 0x23),      # 9  sw   t1, 0x80(s1)    7-segment
        enc_r(0, 29, 28, 0, 30, 0x33),   # 10 add  t5, t3, t4
        enc_s(12, 30, 8, 2, 0x23),       # 11 sw   t5, 12(s0)      DMEM[3] = t5
        enc_j(4 * (HALT_WORD - 12), 0, 0x6F),   # 12 j halt (word 45, so LED_PC uses all 7 bits)
    ]
    p += [0x00000013] * (HALT_WORD - len(p)) + [enc_j(0, 0, 0x6F)]   # halt: j halt
    dmem = [0] * 128
    dmem[0], dmem[2] = 0x12345678, 0xCAFEF00D
    return p, dmem


def gen_wrapper(S):
    S.line("wr_rst = 1; wr_clk = 0; #1 wr_clk = 1; #1 wr_clk = 0; wr_rst = 0;")
    S.line("repeat (40) begin #1 wr_clk = 1; #1 wr_clk = 0; end")
    S.line("#1;")
    base = ['W_IROM', 'W_IROM_COND', 'W_RVINST']
    rd_dmem = ['W_DMEM_RANGE', 'W_DMEM_DEC', 'W_DMEM_RD', 'W_RDIN_IF', 'W_RDIN_DMEM', 'W_DECW']
    wr_dmem = ['W_DMEM_RANGE', 'W_DMEM_DEC', 'W_DMEM_WR', 'W_DMEM_WR_IF', 'W_DMEM_WR_COL', 'W_MEMWRITE']
    dip = ['W_MMIO_RANGE', 'W_CASE_DIP', 'W_RD_DIP_IF', 'W_RD_DIP', 'W_RDIN_IF', 'W_RDIN_MMIO', 'W_DECW']
    pb = ['W_MMIO_RANGE', 'W_CASE_PB', 'W_RD_DIP_IF', 'W_RD_PB_IF', 'W_RD_PB', 'W_RDIN_IF', 'W_RDIN_MMIO', 'W_DECW']
    reg = lambda i: 'u_wr.RV1.RegFile1.RegBank[%d]' % i
    c = lambda expr, w, exp, desc, tags: S.chk('wrapper', 'Wrapper', expr, w, exp, 'Wrapper program: ' + desc, base + tags)
    c(reg(8), 32, 0x10010000, 'lui s0 (fetch + execute)', [])
    c(reg(5), 32, 0x12345678, 'lw from data memory', rd_dmem)
    c(reg(6), 32, 0xCAFEF00D, 'lw from data memory', rd_dmem)
    c('u_wr.DMEM[1]', 32, 0xCAFEF00D, 'sw to data memory', wr_dmem + rd_dmem)
    c(reg(7), 32, 0xCAFEF00D, 'lw of the word just stored', rd_dmem + wr_dmem)
    c(reg(28), 32, WR_DIP, 'lw from the switches (0xFFFF0064)', dip)
    c(reg(29), 32, WR_PB, 'lw from the push buttons (0xFFFF0068)', pb)
    c(reg(30), 32, (WR_DIP + WR_PB) & M32, 'add of switches + buttons', dip + pb)
    c('wr_led', 8, 0x78, 'sw to the LEDs (0xFFFF0060)', ['W_MMIO_RANGE', 'W_CASE_LED', 'W_LED_IF', 'W_LED_WR'] + rd_dmem)
    c('wr_seg', 32, 0xCAFEF00D, 'sw to the 7-segment display (0xFFFF0080)', ['W_MMIO_RANGE', 'W_CASE_SEG', 'W_SEG_IF', 'W_SEG_WR', 'W_MEMWRITE'] + rd_dmem)
    c('u_wr.DMEM[3]', 32, (WR_DIP + WR_PB) & M32, 'sw of a computed value to data memory', wr_dmem + dip + pb)
    c('wr_ledpc', 7, HALT_WORD, 'program stopped at halt (LED_PC = word %d)' % HALT_WORD, ['W_LEDPC'])


TB_HEAD = r"""`timescale 1ns / 1ps
// Generated by cpu_check.py - do not edit
module tb_cpu_check;
  // Shifter
  reg [1:0] sh_Sh; reg [4:0] sh_amt; reg [31:0] sh_in; wire [31:0] sh_out;
  Shifter u_sh(sh_Sh, sh_amt, sh_in, sh_out);
  // ALU
  reg [31:0] alu_a, alu_b; reg [3:0] alu_ctl; wire [31:0] alu_res; wire [2:0] alu_flags;
  ALU u_alu(alu_a, alu_b, alu_ctl, alu_res, alu_flags);
  // Extend
  reg [2:0] ex_src; reg [24:0] ex_in; wire [31:0] ex_out;
  Extend u_ex(ex_src, ex_in, ex_out);
  // Decoder
  reg [6:0] d_op; reg [2:0] d_f3; reg [6:0] d_f7;
  wire [1:0] d_PCS; wire d_RegWrite, d_MemWrite, d_MemtoReg; wire [1:0] d_ALUSrcA, d_ALUSrcB; wire [2:0] d_ImmSrc; wire [3:0] d_ALUControl;
  wire d_MStart, d_MCycleSel, d_MResultSel; wire [1:0] d_MCycleOp;
  Decoder u_dec(d_op, d_f3, d_f7, d_PCS, d_RegWrite, d_MemWrite, d_MemtoReg, d_ALUSrcA, d_ALUSrcB, d_ImmSrc, d_ALUControl,
                d_MStart, d_MCycleOp, d_MCycleSel, d_MResultSel);
  // PC_Logic
  reg [1:0] p_pcs; reg [2:0] p_f3; reg [2:0] p_flags; wire [1:0] p_src;
  PC_Logic u_pcl(p_pcs, p_f3, p_flags, p_src);
  // RegFile
  reg rf_clk, rf_we; reg [4:0] rf_rs1, rf_rs2, rf_rd; reg [31:0] rf_wd; wire [31:0] rf_rd1, rf_rd2;
  RegFile u_rf(rf_clk, rf_we, rf_rs1, rf_rs2, rf_rd, rf_wd, rf_rd1, rf_rd2);
  // ProgramCounter
  reg pc_clk, pc_rst, pc_we; reg [31:0] pc_in; wire [31:0] pc_out;
  ProgramCounter #(.PC_INIT(32'h00400000)) u_pc(pc_clk, pc_rst, pc_we, pc_in, pc_out);
  // RV
  reg rv_clk, rv_rst; reg [31:0] rv_instr, rv_rdata; wire rv_memread; wire [3:0] rv_mw; wire [31:0] rv_pc, rv_alu, rv_wdata;
  RV #(.PC_INIT(32'h00400000)) u_rv(rv_clk, rv_rst, rv_instr, rv_rdata, rv_memread, rv_mw, rv_pc, rv_alu, rv_wdata);
  // Wrapper
  reg [15:0] wr_dip = 16'h%04x; reg [2:0] wr_pb = 3'b%s; wire [7:0] wr_led; wire [6:0] wr_ledpc; wire [31:0] wr_seg;
  wire [7:0] wr_utx; wire wr_utxv, wr_urxack, wr_oledw; wire [6:0] wr_oc; wire [5:0] wr_or; wire [23:0] wr_od; wire wr_accr;
  reg wr_rst = 1, wr_clk = 0;
  Wrapper u_wr(wr_dip, wr_pb, wr_led, wr_ledpc, wr_seg, wr_utx, 1'b1, wr_utxv, 8'd0, 1'b0, wr_urxack,
               wr_oledw, wr_oc, wr_or, wr_od, 32'd0, wr_accr, wr_rst, wr_clk);

  initial begin
    #2;
"""
TB_TAIL = r"""
    $display("DONE %d");
    $finish;
  end
endmodule
"""


def build_testbench(seed=3207):
    rnd = random.Random(seed)
    S = Suite()
    S.line('$display("STAGE unit");')
    gen_shifter(S, rnd)
    gen_alu(S, rnd)
    gen_extend(S, rnd)
    gen_decoder(S, rnd)
    gen_pclogic(S)
    gen_regfile(S)
    gen_pc(S)
    S.line('$display("STAGE rv");')
    gen_rv(S, rnd)
    S.line('$display("STAGE wrapper");')
    gen_wrapper(S)
    tb = TB_HEAD % (WR_DIP, format(WR_PB, '03b')) + '\n'.join('    ' + s for s in S.v) + TB_TAIL % len(S.checks)
    return tb, S.checks


# =============================================================================================
# Simulators
# =============================================================================================
def find_xilinx_tool(name):
    w = shutil.which(name)
    if w:
        return w
    pats = []
    for base in ('C:/Xilinx/Vivado/*/bin', 'C:/AMD/Vivado/*/bin', 'C:/AMDDesignTools/*/Vivado/bin', '/tools/Xilinx/Vivado/*/bin',
                 '/opt/Xilinx/Vivado/*/bin', os.path.expanduser('~/Xilinx/Vivado/*/bin')):
        pats += glob.glob(os.path.join(base, name + ('.bat' if os.name == 'nt' else '')))
    return os.path.normpath(sorted(pats)[-1]) if pats else None


def run_cmd(cmd, cwd, timeout=900):
    if os.name == 'nt':
        p = subprocess.run(subprocess.list2cmdline(cmd), cwd=cwd, shell=True, capture_output=True, text=True,
                           errors='replace', timeout=timeout)
    else:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, errors='replace', timeout=timeout)
    return p.returncode, p.stdout + p.stderr


class Iverilog:
    name = 'Icarus Verilog'

    def __init__(self):
        self.iv, self.vvp = shutil.which('iverilog'), shutil.which('vvp')

    def ok(self):
        return bool(self.iv and self.vvp)

    def compile(self, files, top, cwd):
        rc, out = run_cmd([self.iv, '-g2005', '-s', top, '-o', 'sim.vvp'] + files, cwd)
        return rc == 0, out

    def run(self, top, cwd):
        return run_cmd([self.vvp, '-n', 'sim.vvp'], cwd)[1]


class XSim:
    """Same command style Vivado itself uses (xvlog -prj / xelab --snapshot / xsim -R)."""
    name = 'Vivado xsim'

    def __init__(self):
        self.xvlog, self.xelab, self.xsim = (find_xilinx_tool(n) for n in ('xvlog', 'xelab', 'xsim'))

    def ok(self):
        return bool(self.xvlog and self.xelab and self.xsim)

    def compile(self, files, top, cwd):
        prj = os.path.join(cwd, top + '.prj')
        with open(prj, 'w') as fh:
            for f in files:
                fh.write('verilog xil_defaultlib "%s"\n' % os.path.abspath(f).replace('\\', '/'))
        rc, out = run_cmd([self.xvlog, '--relax', '-prj', top + '.prj'], cwd)
        if rc != 0 or re.search(r'^ERROR:', out, re.M):
            return False, out
        rc, out2 = run_cmd([self.xelab, '--relax', '--debug', 'off', '--snapshot', top + '_snap', 'xil_defaultlib.' + top], cwd)
        return rc == 0 and not re.search(r'^ERROR:', out2, re.M), out + out2

    def run(self, top, cwd):
        return run_cmd([self.xsim, top + '_snap', '-R'], cwd)[1]


def compile_errors(out, paths):
    """Pull 'file:line' locations out of compiler output."""
    found = []
    for m in re.finditer(r'([^\s\[\]"]+\.v):(\d+)', out):
        found.append((os.path.basename(m.group(1)), int(m.group(2))))
    seen, res = set(), []
    for f, ln in found:
        if (f, ln) not in seen:
            seen.add((f, ln))
            res.append((f, ln))
    return res


# =============================================================================================
# Fault localisation
# =============================================================================================
def rank(checks, failed_ids):
    fails = [c for c in checks if c['id'] in failed_ids]
    passes = [c for c in checks if c['id'] not in failed_ids]
    nf = len(fails)
    ef, ep = {}, {}
    for c in fails:
        for t in c['tags']:
            ef[t] = ef.get(t, 0) + 1
    for c in passes:
        for t in c['tags']:
            ep[t] = ep.get(t, 0) + 1
    scores = []
    for t, e in ef.items():
        scores.append((e / math.sqrt(nf * (e + ep.get(t, 0))), e, t))
    scores.sort(key=lambda x: (-x[0], -x[1], x[2]))
    return scores


# =============================================================================================
# main
# =============================================================================================
def main():
    ap = argparse.ArgumentParser(description='Line-level test of the CG3207 RISC-V CPU')
    ap.add_argument('--root', default=None, help="folder to search for the .v files (default: this script's folder)")
    ap.add_argument('--sim', choices=['auto', 'iverilog', 'xsim'], default='auto')
    ap.add_argument('--lines', action='store_true', help='print where each checked line is and exit')
    ap.add_argument('--no-demo', action='store_true', help="don't run your own test_Wrapper.v")
    ap.add_argument('--keep', action='store_true', help='keep the work folder')
    ap.add_argument('--json', action='store_true', help=argparse.SUPPRESS)
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(errors='replace')
    except Exception:
        pass

    # search next to this script by default, so it works no matter which folder it is started from
    roots = [args.root] if args.root else [os.path.dirname(os.path.abspath(__file__)), os.getcwd()]
    for root in roots:
        root = os.path.abspath(root)
        found = find_files(root, RTL_FILES + ['test_Wrapper.v', 'AA_IROM.mem', 'AA_DMEM.mem'])
        if all(found[f] for f in RTL_FILES):
            break
    paths = {}
    print('CG3207 CPU line-level check')
    print('Sources (searched below %s):' % root)
    missing = []
    for f in RTL_FILES:
        p = pick(found[f], ['sources_1'])
        if not p:
            missing.append(f)
            continue
        paths[f] = p
        extra = '   (%d other copies ignored)' % (len(found[f]) - 1) if len(found[f]) > 1 else ''
        print('  %-18s %s%s' % (f, os.path.relpath(p, root), extra))
    if missing:
        print('\nERROR: could not find: %s\nPut cpu_check.py in your project folder (next to the .xpr), or use --root <folder>.' % ', '.join(missing))
        return 2
    src = Source(paths)

    if args.lines:
        print('\nChecked lines:')
        cur = None
        for tag in TAGS:
            ln, text, st = src.locate(tag)
            f = TAGS[tag]['file']
            if f != cur:
                print('\n%s' % f)
                cur = f
            print('  %5s  %-44s %s%s' % (ln if ln else '?', TAGS[tag]['meaning'][:44], text[:70], '' if st == 'ok' else '   <-- ' + st))
        return 0

    sims = {'iverilog': Iverilog, 'xsim': XSim}
    order = ['iverilog', 'xsim'] if args.sim == 'auto' else [args.sim]
    sim = None
    for s in order:
        cand = sims[s]()
        if cand.ok():
            sim = cand
            break
    if not sim:
        print('\nERROR: no simulator found. Install Icarus Verilog (iverilog) or run this from a shell where '
              "Vivado's xvlog/xelab/xsim are available (e.g. the 'Vivado Tcl Shell', or after settings64.bat).")
        return 2
    print('Simulator: %s' % sim.name)

    work = os.path.join(tempfile.gettempdir(), WORK_DIR_NAME)
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(os.path.join(work, 'main'))
    tb, checks = build_testbench()
    with open(os.path.join(work, 'main', 'tb_cpu_check.v'), 'w') as fh:
        fh.write(tb)
    prog, dmem = wrapper_program()
    with open(os.path.join(work, 'main', 'AA_IROM.mem'), 'w') as fh:
        fh.write('\n'.join('%08x' % w for w in prog + [0x00000013] * (128 - len(prog))) + '\n')
    with open(os.path.join(work, 'main', 'AA_DMEM.mem'), 'w') as fh:
        fh.write('\n'.join('%08x' % w for w in dmem) + '\n')

    files = [os.path.abspath(os.path.join(work, 'main', 'tb_cpu_check.v'))] + [os.path.abspath(paths[f]) for f in RTL_FILES]
    print('\n[1] Compiling %d checks ...' % len(checks))
    ok, out = sim.compile(files, 'tb_cpu_check', os.path.join(work, 'main'))
    result = dict(compile=ok, failed=[], top=[])
    if not ok:
        print('    COMPILE FAILED - the compiler points at:')
        for f, ln in compile_errors(out, paths)[:8]:
            if f in src.raw and 0 < ln <= len(src.raw[f]):
                print('      %s:%d   %s' % (f, ln, src.raw[f][ln - 1].strip()))
            else:
                print('      %s:%d' % (f, ln))
        print('\n    Compiler output (errors only):')
        for l in out.splitlines():
            if re.search(r'error|ERROR', l):
                print('      ' + l.strip()[:200])
        if args.json:
            print('JSON ' + json.dumps(result))
        return 1

    print('[2] Running ...')
    out = sim.run('tb_cpu_check', os.path.join(work, 'main'))
    done = re.search(r'^DONE\s+(\d+)', out, re.M)
    failed = set()
    got = {}
    for m in re.finditer(r'^F (\d+) (\S+)', out, re.M):
        failed.add(int(m.group(1)))
        got[int(m.group(1))] = m.group(2)
    if not done:
        print('    The simulation did not finish (crash or infinite loop). Last output:')
        print('\n'.join('      ' + l for l in out.splitlines()[-15:]))
        return 1

    # ---- per-module summary
    stages = [('unit', 'Module tests'), ('rv', 'RV datapath, one instruction at a time'), ('wrapper', 'Wrapper: memories and peripherals')]
    mods = []
    for c in checks:
        if c['module'] not in mods:
            mods.append(c['module'])
    print('\nResults')
    for st, title in stages:
        print('  %s' % title)
        for m in mods:
            cs = [c for c in checks if c['stage'] == st and c['module'] == m]
            if not cs:
                continue
            nf = sum(1 for c in cs if c['id'] in failed)
            print('    %-16s %5d checks   %s' % (m, len(cs), 'PASS' if nf == 0 else 'FAIL (%d)' % nf))

    if not failed:
        print('\nAll %d checks passed.' % len(checks))
    else:
        # localise using the first stage that has failures (later stages inherit earlier bugs)
        st = next(s for s, _ in stages if any(c['id'] in failed and c['stage'] == s for c in checks))
        scoped = [c for c in checks if c['stage'] == st]
        fids = {c['id'] for c in scoped if c['id'] in failed}
        scores = rank(scoped, fids)
        print('\n%d of %d checks FAILED.' % (len(failed), len(checks)))
        if st == 'wrapper':
            print('All module and single-instruction RV checks passed; only the Wrapper program fails.\n'
                  'So the bug is most likely in Wrapper.v (memories / address decoding / peripherals).')
        elif st == 'rv':
            print('All module tests passed; the RV datapath fails. So the bug is most likely in RV.v (wiring / muxes).')
        print('\nMost likely line(s), best first (score 1.00 = explains every failure and no passing check uses it):')
        shown = 0
        best = scores[0][0] if scores else 0
        for sc, e, tag in scores:
            if shown >= 8 or (shown >= 3 and sc < best * 0.75):
                break
            ln, text, status = src.locate(tag)
            f = TAGS[tag]['file']
            where = '%s:%s' % (f, ln if ln else '?')
            print('  %-20s %.2f  %s%s' % (where, sc, text[:90], '' if status == 'ok' else '   <-- ' + status))
            print('  %-20s       (%s; involved in %d failing checks)' % ('', TAGS[tag]['meaning'], e))
            result['top'].append(dict(file=f, line=ln, score=round(sc, 3), tag=tag))
            shown += 1
        print('\nExample failures:')
        for c in [c for c in scoped if c['id'] in fids][:10]:
            exp = c['exp'] if isinstance(c['exp'], str) else ('%0*X' % ((c['width'] + 3) // 4, c['exp']))
            print('  %s\n      expected %s, got %s' % (c['desc'], exp, got.get(c['id'], '?').upper()))
        result['failed'] = sorted(failed)
        result['stage'] = st

    # ---- your own testbench + program
    if not args.no_demo:
        tw = pick(found['test_Wrapper.v'], ['sim_1', 'sources_1'])
        mi, md = pick(found['AA_IROM.mem'], ['sources_1']), pick(found['AA_DMEM.mem'], ['sources_1'])
        if tw and mi and md:
            print('\n[3] Your test_Wrapper.v with your AA_IROM.mem / AA_DMEM.mem ...')
            d = os.path.join(work, 'demo')
            os.makedirs(d)
            shutil.copy(mi, os.path.join(d, 'AA_IROM.mem'))
            shutil.copy(md, os.path.join(d, 'AA_DMEM.mem'))
            files = [os.path.abspath(tw)] + [os.path.abspath(paths[f]) for f in RTL_FILES]
            ok, cout = sim.compile(files, 'test_Wrapper', d)
            if not ok:
                print('    could not compile it:')
                print('\n'.join('      ' + l for l in cout.splitlines() if re.search('error', l, re.I))[:2000])
            else:
                dout = sim.run('test_Wrapper', d)
                lines = [l for l in dout.splitlines() if re.search(r'PASS|FAIL|passed|failed', l)]
                for l in [l for l in lines if 'FAIL' in l][:8]:
                    print('    ' + l.strip())
                summ = [l for l in lines if 'passed' in l]
                print('    ' + (summ[-1].strip() if summ else 'no summary printed (does it end with $finish?)'))
        else:
            print('\n[3] Skipped your own test_Wrapper.v (not found together with AA_IROM.mem and AA_DMEM.mem).')

    if not args.keep:
        shutil.rmtree(work, ignore_errors=True)
    if args.json:
        print('JSON ' + json.dumps(result))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())