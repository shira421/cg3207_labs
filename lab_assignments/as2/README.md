# Assignment 2: single-cycle CPU (Week 7 demo)

Single-cycle RISC-V (RV32I) processor on the Nexys 4 DDR. Every instruction finishes in one clock:
fetch, decode, register read, ALU, memory and write-back all happen in the same cycle. This folder is the
project exactly as it was demoed (commit `43888ac`). Assignment 3 continues in a copy of it (`../as3`), and
Assignment 4 pipelines it (`../as4`).

Open `as2.xpr` in Vivado.

## Where things live

| What | File |
|---|---|
| Datapath (instruction fields, Src_A/Src_B muxes, next-PC adder) | `as2.srcs/sources_1/imports/as2/RV.v` |
| Control unit (one case per opcode) | `Decoder.v` in the same folder |
| ALU, Shifter, Extend, PC_Logic, RegFile, ProgramCounter | same folder |
| Memories and peripherals (MMIO) | `Wrapper.v`, `TOP_Nexys.vhd` |
| Program loaded into the CPU | `AA_IROM.mem`, `AA_DMEM.mem` (sources_1 for the bitstream, sim_1 for simulation) |
| Testbench | `test_Wrapper.v` |
| Demo program (RARS source) | `test.asm` |
| Self-test script | `cpu_check.py` |
| Pin constraints | `as2.srcs/constrs_1/imports/as2/TOP_Nexys4DDR.xdc` |

## Supported instructions

| Group | Instructions |
|---|---|
| DP register | add, sub, and, or, xor, sll, srl, sra, slt, sltu |
| DP immediate | addi, andi, ori, xori, slli, srli, srai, slti, sltiu |
| Memory | lw, sw (no byte / half-word) |
| Branches | beq, bne, blt, bge, bltu, bgeu |
| Jumps | jal, jalr |
| Upper immediate | lui, auipc |

Unsupported opcodes decode as a NOP (no register write, memory write or jump).

## Demo program (`test.asm`)

- **SW11–SW0**: the input number. **SW15–SW12**: which of the 16 trace entries to show on the 7-segment display.
- Runs four test cases through every DP register-type instruction and all six branches, calls a function with both `jal` and `jalr`, and records 16 intermediate values in a trace table (`0x10010020`–`0x1001005C`) that can be compared word-for-word with RARS.
- Expected: **LED[7:0] = 0x65** always; with all switches down the display shows the final checksum **0x0717E0E2**.
- Any push button (BTNL / BTNC / BTNR) halts the program.

To change the program: assemble `test.asm` in RARS (Settings → Memory Configuration → Default), dump the text and data segments as hex, and replace `AA_IROM.mem` / `AA_DMEM.mem` in both `sources_1` and `sim_1`.

## Self-test

```
python cpu_check.py --root .
```

Generates one testbench that checks every module against a Python model, every instruction through the RV datapath, and a short program through the Wrapper, then runs it with Icarus Verilog (or `--sim xsim` for Vivado's simulator). If anything fails it ranks the most likely faulty source lines. Add `--no-demo` to skip running `test_Wrapper.v` with the demo program.

Current result: **all 5803 checks pass**.
