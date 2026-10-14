# Assignment 3 — Multiplication / Division (Week 9 demo)

This is its own Vivado project (`as3.xpr`), started as a copy of the Assignment 2 project in
`../as2`, which stays as it was demoed. Open `as3.xpr` in Vivado for all Assignment 3 work.

## Where things live

| What | File |
|---|---|
| MCycle unit (course template, division still a placeholder) | `as3.srcs/sources_1/imports/as2/MCycle.v` |
| MCycle testbench (course template, to become self-checking) | `as3.srcs/sources_1/imports/as2/test_MCycle.v` |
| CPU datapath / control to modify for Task 2 | `RV.v`, `Decoder.v` in the same folder |
| Demo program | `test.asm` (this folder) |
| Task 4 visualisation | `visualisation.html` (to be made) |
| Task 4 prompt history | `prompt_history.md` |
| Task 3 slides | this folder (1–4 slides, .pptx or .pdf) |

Both MCycle files are already registered in `as3.xpr` (MCycle.v in Design Sources, test_MCycle.v in
Simulation Sources). In Vivado, right-click `test_MCycle` → *Set as Top* to simulate it, and set
`MCycle` as top under Design Sources to synthesise it on its own (Task 1 asks for a warning-free
synthesis). Set `TOP` / `test_Wrapper` back as top afterwards.

## Quick local simulation (no Vivado)

```
cd as3.srcs/sources_1/imports/as2
iverilog -g2005 -o mc.vvp test_MCycle.v MCycle.v && vvp mc.vvp
```

## Checklist

- [ ] Task 1 — signed + unsigned division in MCycle (width = 4 first), self-checking testbench, synthesise MCycle as top without warnings
- [ ] Task 2 — `mul`, `div`, `divu` in the CPU: Decoder generates `Start` / `MCycleOp` / result-select, `WE_PC = ~Busy`, ALU/MCycle result mux, MCycle at width 32; HDL sim + board
- [ ] Task 3 — one enhancement (signed mul / signed div / unsigned div), post-synthesis simulation showing cycles/resources before vs after
- [ ] Task 4 — single-file HTML visualisation of that enhancement + complete prompt history
- [ ] Demo program (one .asm / one bitstream) exercising mul, div, divu with corner cases
- [ ] Submission zip `GroupXX_Monday/Friday_Asst3.zip`: modified .v files + testbenches, .bit, .asm, slides, .html, prompt history

## Encodings (RV32M, opcode 0110011, funct7 0000001)

| Instr | funct3 | MCycleOp |
|---|---|---|
| mul  | 000 | 00 (signed mul; low word is the same for signed/unsigned) |
| div  | 100 | 10 |
| divu | 101 | 11 |
