# CG3207 Labs — Computer Architecture (NUS)

Lab work for CG3207: building a RISC-V processor on the Nexys 4 DDR FPGA (Vivado 2023.2, part
`xc7a100tcsg324-1`), from an HDL warm-up to a single-cycle CPU, then multiply/divide and advanced
CPU features.

> Course template files are licensed for educational use only and must not be posted publicly,
> so keep this repository **private**.

## Repository layout

```
lab_assignments/
  as1/          Assignment 1  — HDL / FPGA and assembly familiarisation  (a1.xpr)
  as2/          Assignment 2  — single-cycle RV32I CPU                    (as2.xpr)
  as3/          Assignment 3  — multiplication / division (MCycle)        (as3.xpr)
submissions/    Exactly what was uploaded to Canvas for each assignment
```

Each assignment is its own Vivado project, started as a copy of the previous one so earlier work
stays exactly as demoed. Each assignment folder has its own `README.md` with details.

## Assignments

| # | Topic | Marks | Demo | Status |
|---|---|---|---|---|
| 1 | HDL / FPGA and assembly familiarisation (individual) | 10 | Week 5 | Submitted |
| 2 | Basic CPU design — single-cycle RV32I | 30 | Week 7 | Submitted |
| 3 | Multiplication / division unit (MCycle) + enhancement + visualisation | 25 | Week 9 | In progress |
| 4 | Advanced CPU design | 15 + 10 | Week 12 | Not started |

## Working with the projects

- Open the `.xpr` inside the assignment folder in Vivado. Vivado's generated folders
  (`*.runs`, `*.cache`, `*.sim`, `*.hw`, `.Xil`, logs) are git-ignored and are rebuilt locally.
- Close Vivado before `git pull`, since it rewrites the `.xpr` while a project is open.
- Commit sources (`.v`, `.vhd`, `.mem`, `.xdc`, `.asm`) and the `.xpr`; don't commit build output.
- Simulations can also be run without Vivado using Icarus Verilog, e.g.
  `python cpu_check.py --root .` in `as2/` or `as3/` runs the full CPU self-test.

## Submissions

`submissions/` keeps a copy of each assignment as submitted, so the demoed files can always be
recovered. Course resources and templates: https://nus-cg3207.github.io/labs/
