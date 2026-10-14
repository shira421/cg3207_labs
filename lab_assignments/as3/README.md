# Assignment 3 — Multiplication / Division (Week 9 demo)

This is its own Vivado project (`as3.xpr`), started as a copy of the Assignment 2 project in
`../as2`, which stays as it was demoed. Open `as3.xpr` in Vivado for all Assignment 3 work.

## Status

| Task | What was done | Verified (Icarus Verilog / Yosys) | Still to do in Vivado / on the board |
|---|---|---|---|
| 1 Division | Signed + unsigned restoring division in MCycle | Self-checking `test_MCycle`: exhaustive at width 4 and 6, corner cases + random at width 32 — 76 083 checks pass | Behavioural sim; synthesise MCycle as top, check warnings |
| 2 CPU | mul, mulh, mulhu, div, divu, rem, remu; stall on Busy; demo program | `test_Wrapper`: 229 checks pass (all 16 cases × all views, measured cycles, own-operand mode); `cpu_check.py`: 6 703 RV32I checks pass | Behavioural sim, bitstream, board demo |
| 3 Enhancement | Radix-4 Booth multiplier for signed **and** unsigned multiplication | Gate-level (Yosys netlist) sim of both versions passes; cycles and resources below | Post-synthesis simulation + utilisation report for the slides |
| 4 Visualisation | — | — | Not started |

## Where things live

| What | File |
|---|---|
| MCycle unit (Tasks 1 and 3) | `as3.srcs/sources_1/imports/as2/MCycle.v` |
| MCycle testbench, self-checking (+ `test_MCycle_postsynth` for Task 3) | `as3.srcs/sources_1/imports/as2/test_MCycle.v` |
| CPU changes (Task 2) | `RV.v`, `Decoder.v`, `Wrapper.v` (memory sizes only) in the same folder |
| CPU testbench, self-checking | `test_Wrapper.v` in the same folder |
| Demo program | `test.asm` (this folder) → `AA_IROM.mem` / `AA_DMEM.mem` in `sources_1` and `sim_1` |
| RV32I regression self-test | `cpu_check.py` (this folder): `python cpu_check.py --root .` |
| Task 4 visualisation | `visualisation.html` (to be made) |
| Task 4 prompt history | `prompt_history.md` |
| Task 3 slides | this folder (1–4 slides, .pptx or .pdf) |

## Task 1 — Division

Restoring division on magnitudes, one quotient bit per cycle (`width` cycles, 33 for 32-bit including
the write-back cycle):

1. **Start:** `{R, Q} = {0, |dividend|}`, `D = |divisor|`. Magnitudes are only taken for signed
   division. The signs the results need are remembered.
2. **Each cycle:** shift `{R, Q}` left by 1. If `R ≥ D`, set `R = R − D` and the new quotient bit to 1;
   otherwise restore and set it to 0. The bit shifted out of R is kept, because R can reach 2D−1 after
   the shift.
3. **End:** negate the quotient if the operand signs differ. The remainder takes the dividend's sign.

The results follow RISC-V: the quotient rounds towards zero, `−2³¹ / −1 = −2³¹` with remainder 0, and
`x / 0` gives a quotient of all ones and a remainder of `x`. The manual says the divisor is never zero,
but this still matches RISC-V and RARS.

## Task 2 — CPU integration

- **Decoder:** opcode `0110011` with funct7 `0000001` raises `MStart` and selects `MCycleOp` and which
  MCycle result to write (`MResultSel`). `MCycleSel` makes the CPU write the MCycle result instead of
  the ALU result.

  | Instr | funct3 | MCycleOp | Result |
  |---|---|---|---|
  | mul | 000 | 00 | Result1 (low word) |
  | mulh | 001 | 00 | Result2 (high word) |
  | mulhu | 011 | 01 | Result2 |
  | div | 100 | 10 | Result1 (quotient) |
  | divu | 101 | 11 | Result1 |
  | rem | 110 | 10 | Result2 (remainder) |
  | remu | 111 | 11 | Result2 |

  `mulhsu` (funct3 010) is not supported and decodes as a NOP.
- **RV.v:** MCycle (width 32) takes RD1/RD2. `WE_PC = ~Busy` freezes the PC, and with it the
  instruction, while MCycle works. The register write is held off (`WE = RegWrite & ~Busy`) and
  happens in the cycle where Busy falls. A multiplexer chooses between the ALU and MCycle results.
- **Wrapper.v:** IROM and DMEM enlarged to 256 words (`*_DEPTH_BITS = 10`) for the demo program.

### Demo program (`test.asm`)

- At start-up it runs all seven M instructions back to back on 16 corner cases, plus `div` with rd = rs1
  and `mul` with rd = rs2. Every result is compared against an expected table.
  - **LED[6:0]** = one flag per instruction (mul, mulh, mulhu, div, divu, rem, remu), **LED7** = all of
    them. A correct CPU shows **LED = 0xFF**.
- It measures the cycles taken by one `mul` and one `div` with the cycle counter. Expected: **mul 18,
  div 33**.
- **SW15 = 0:** SW3–0 picks a test case and SW7–4 picks what to show on the 7-segment display:
  0 a, 1 b, 2 mul, 3 mulh, 4 mulhu, 5 div, 6 divu, 7 rem, 8 remu, 9 mul cycles, A div cycles,
  B LED value. Values are recomputed live with the M instructions, not read from the table.
- **SW15 = 1:** use your own operands, SW14–8 = a and SW6–0 = b (7-bit signed). The display shows
  a × b; hold BTNL for a / b, BTNC for a rem b, or BTNR for divu.

| Case | a | b | Why |
|---|---|---|---|
| 0–3 | ±7 | ±3 | all sign combinations |
| 4 | 0x80000000 | −1 | div overflow (result −2³¹, remainder 0) |
| 5 | 0x80000000 | 1 | most negative number |
| 6 | 0x7FFFFFFF | 0x7FFFFFFF | largest positive product |
| 7 | −1 | −1 | signed 1 vs unsigned huge |
| 8 / 9 | 0 / 5 | 5 / 0 | zero dividend / zero divisor |
| 10, 11 | ±123456789 | 1000 | ordinary multi-digit |
| 12 | 0x12345678 | 0x9ABCDEF0 | large mixed |
| 13 | −2 | 2 | divu of a "negative" number |
| 14 | 1 | 0x80000000 | divisor larger than dividend |
| 15 | 0xDEADBEEF | 0x00010001 | pattern |

The expected table was computed with the RISC-V rules. Running the program in RARS gives
`status = 0xFF`, so RARS agrees with every expected value.

To reassemble: in RARS, *File → Dump Memory*, `.text` and `.data` as *Hexadecimal Text*, into
`AA_IROM.mem` / `AA_DMEM.mem` in both `sources_1/imports/as2` and `sim_1/imports/as2`.

## Task 3 — Enhancement: radix-4 Booth multiplication

The original multiplier adds one partial product per cycle: 2·width cycles for signed (operands
sign-extended to 64 bits) and width cycles for unsigned, using a 2·width-bit adder and two 2·width-bit
shift registers.

Radix-4 (modified) Booth recoding looks at 3 multiplier bits per cycle: 2 new bits plus the last bit
of the previous pair. It turns them into one digit in {−2, −1, 0, +1, +2}:

| bits | digit |
|---|---|
| 000, 111 | 0 |
| 001, 010 | +M |
| 011 | +2M |
| 100 | −2M |
| 101, 110 | −M |

Each cycle adds digit × M to the upper part of the product register (subtraction is done as ~pp + 1
through the carry-in), then shifts the whole register right by 2 (arithmetic). Both operands are first
extended by one bit (sign bit for signed, 0 for unsigned), so **one datapath does both signed and
unsigned** multiplication in width/2 + 1 iterations.

| width 32 | Original | Radix-4 Booth |
|---|---|---|
| signed mul cycles (incl. write-back) | 65 | **18** (3.6× faster) |
| unsigned mul cycles | 33 | **18** (1.8× faster) |
| multiply adder | 64-bit | **35-bit** |
| whole MCycle, LUTs (Yosys estimate*) | 905 | **658** |
| whole MCycle, flip-flops (Yosys estimate*) | 268 | **243** |

\*Yosys `synth_xilinx`, no DSPs. Replace these with Vivado's post-synthesis utilisation report for
the slides.

`RADIX4_BOOTH = 0` gives back the original multiplier, so both versions can be compared from the same
file. `test_MCycle` runs both versions.

### Post-synthesis simulation in Vivado (for the slides)

1. Set `MCycle` as top under Design Sources.
2. Go to *Settings → Synthesis → More Options* and add `-generic width=32 -generic RADIX4_BOOTH=1`.
3. Run Synthesis. Note the LUT and FF counts from *Report Utilization*.
4. Set `test_MCycle_postsynth` as the simulation top (`localparam BOOTH = 1`). Run *Post-Synthesis
   Functional Simulation* and use `run all`. It prints the checks passed and the cycles for each
   operation.
5. Repeat with `RADIX4_BOOTH=0` and `localparam BOOTH = 0` for the original multiplier.
6. Afterwards, remove the `-generic` options and set `TOP` / `test_Wrapper` back as tops.

## Simulating

- **Vivado:** set `test_MCycle` (unit) or `test_Wrapper` (CPU + program) as the simulation top, run the
  behavioural simulation, and use `run all`. Both stop by themselves and print PASSED/FAILED.
- **Without Vivado:** from `as3.srcs/sources_1/imports/as2`, run
  ```
  iverilog -g2005 -s test_MCycle -o mc.vvp test_MCycle.v MCycle.v && vvp mc.vvp
  ```
  For the CPU, run from `as3.srcs/sim_1/imports/as2` so the `.mem` files are found, and compile
  `test_Wrapper.v` with all the RTL `.v` files.

## Checklist

- [x] Task 1 — signed + unsigned division in MCycle, self-checking testbench
- [ ] Task 1 — synthesise MCycle as top in Vivado, check the warnings
- [x] Task 2 — RV32M in the CPU, demo program, CPU-level simulation
- [ ] Task 2 — bitstream and board demo
- [x] Task 3 — radix-4 Booth multiplier, gate-level check
- [ ] Task 3 — Vivado post-synthesis simulation + utilisation numbers, 1–4 slides
- [ ] Task 4 — single-file HTML visualisation of the Booth multiplier + complete prompt history
- [ ] Submission zip `GroupXX_Monday/Friday_Asst3.zip`: modified .v files + testbenches, .bit, .asm, slides, .html, prompt history
