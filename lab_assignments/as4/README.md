# Assignment 4 — Pipelining + enhancements (Week 12 demo)

**A pipelined RISC-V that flies through fractals.** A 5-stage pipeline with a fully pipelined fixed-point
multiply unit renders the Mandelbrot and Julia sets on the Pmod OLED in real time. You tilt the board to
fly around, press buttons to zoom, and press BTNC to dive into the Julia set of the point you are on.
Every enhancement can be switched off **while it runs** from the DIP switches, so the same program on
the same bitstream shows what each one is worth.

This is its own Vivado project (`as4.xpr`), started as a copy of `../as3`, which stays as it was demoed.
The sources are in `as4.srcs/sources_1/imports/as2/`.

## Status

| Part | What was done | Verified | Still to do (Vivado / board) |
|---|---|---|---|
| Compulsory: pipelining | 5-stage pipeline F/D/E/M/W, runs everything from A2 + A3 | The **unmodified A3 program** still gives LED = 0xFF; 1000 random programs match a reference model; the `HAZARD_UNIT = 0` build (program padded with nops) matches too | Report the max frequency (MMCM, below) |
| **Enh. 1: pipelined multiplier** | Radix-4 Booth + carry-save tree across E and M, one multiply per cycle, result ready like a load's. Replaces the 33-cycle MCycle for mul/mulh/mulhu (division stays on MCycle) | 202 366 vectors on the unit alone; all random programs; planted bugs caught | — |
| **Enh. 2: `mulsr` instruction** | `mulsr rd, rs1, rs2, k` = (rs1 × rs2) >> k, a fixed-point multiply in one instruction (custom-0 opcode) | Same | — |
| Enh. 3: hazard unit | Forwarding (M→E, W→E), register-file write-through, load/multiply-use stall, flush on redirect, MCycle stall | Random programs in every mode; planted bugs caught | — |
| Enh. 4: branch prediction | 32-entry BTB with 2-bit counters | Same | — |
| Enh. 5: byte/half-word load/store | `lb lh lbu lhu sb sh` | Same | — |
| Enh. 6: interrupts | Push-button interrupts, EPC, `mret`, precise | 60 random programs interrupted at random times | — |
| Enh. 7: live A/B switches | `CPU_CTRL`: forwarding, branch prediction and the fast multiplier can each be switched off while running | Random programs with the switches flipped every few cycles | — |
| Clocking | **MMCM** CPU clock (Vivado now times the CPU), power-on reset | Whole-chip simulation (below) | Read the timing report |
| OLED | v2 double-buffered OLED + **fix for the blank screen** (below) | Whole-chip simulation with a model of the panel: correct frames with no reset pressed | Check on the board |
| Demo | Fractal explorer in C (`sw/demo/fractal.c`) | Frames rendered from simulation; `test_Wrapper.v` prints PASS | Bitstream + board, post-synthesis simulation |
| Slides | `Lab4_Slides.pptx` | — | Fill in max frequency / resources |

## The numbers

Cycles to compute one fractal frame (96 × 64 pixels, up to 32 iterations each) for each switch setting.
They come from simulation of the same program, which also shows them on the 7-segment display:

| Switches | What is off | Cycles / frame | vs everything on | Frames/s at 25 MHz |
|---|---|---|---|---|
| 0000 | Everything on | 953,584 | 1.0× | 26.2 |
| 0001 | SW0: no forwarding | 1,449,056 | 1.5× | 17.3 |
| 0010 | SW1: no branch prediction | 1,154,544 | 1.2× | 21.7 |
| 0011 | SW0+SW1 | 1,573,600 | 1.7× | 15.9 |
| 1000 | SW3: no mulsr (mul+mulh+shifts) | 1,967,776 | 2.1× | 12.7 |
| 0100 | SW2: A3 multiplier (MCycle) | 8,862,960 | 9.3× | 2.8 |
| 0111 | SW2+SW1+SW0 | 9,400,592 | 9.9× | 2.7 |
| 1100 | SW3+SW2 | 17,786,016 | 18.7× | 1.4 |
| 1111 | All four off | 18,880,880 | 19.8× | 1.3 |

Measured on a 1/16 sample of the frame (every 4th pixel each way, same view) and scaled ×16; the full frame with everything on measured 929 099 cycles. With everything on that is 12 cycles per iteration (76 472 iterations), including the per-pixel work; the inner loop itself is 10 instructions, three of them multiplies. With the A3 multiplier: 116.

---

## Why the OLED was blank, and the fix

I simulated the whole chip: the course's TOP and OLED controller VHDL (converted to Verilog with GHDL),
our CPU, and a model of the SSD1331 panel that decodes the SPI wires back into a picture (`sim/chip/`).

- With BTND pressed after start-up, the panel received its full start-up sequence (`FD 12 AE A0 73 … AF`)
  and correct frames.
- **Without a reset, it received nothing.** The OLED controller's state register (`OLED_FSM`) has no
  reset value and no explicit initial value, and TOP only resets it from BTND. Whether the panel ever
  starts after programming depended on how synthesis encoded that state machine, and it can come up
  in a state that never leads anywhere. Then the screen stays black until BTND is pressed, and goes
  black again after every reprogram.

Fix (both in this push):
1. **Power-on reset** in TOP (`RESET_INT`, which the template left as "for future use"). It holds the CPU
   and the OLED controller in reset for ~10 ms after configuration (and until the MMCM has locked). The
   OLED controller is now reset by power-on **or** BTND. So are the accelerometer controller and the UART,
   which had the same problem: in the whole-chip simulation the accelerometer reading stayed undefined
   until BTND was pressed.
2. **Explicit initial values** in `pmodoledrgb_bitmap.vhd` (`OLED_FSM := waking`, the SPI counters).

After the fix, the same simulation without any reset shows the start-up commands at 36 ms and correct
frames after that.

Also check: the OLED goes in header **JB** (labelled on the board), pin 1 matched to pin 1. If the panel
stays black, look at the LEDs (boot self-test, below).

## Clocking: MMCM (and why `CLK_DIV_BITS` couldn't measure the max frequency)

The template divides the clock with a counter, and uses the counter's top bit as the CPU clock. Vivado
does not treat a flip-flop output as a clock, so with `CLK_DIV_BITS` ≥ 1 **nothing in the CPU is timed**:
no timing warning at 1, 2, … means nothing. Only `CLK_DIV_BITS = 0` was a real check.

TOP now makes the CPU clock with an **MMCM** (`MMCME2_BASE`): `CPU clock = 100 MHz / CPU_CLK_DIV`. The
default is 4 (25 MHz). The peripherals (OLED, UART, accelerometer, 7-seg) run on a second 100 MHz output
of the same MMCM, so the two clocks are related and Vivado times the paths between them too. BTNU (pause)
still works (a `BUFGCE` stops the CPU clock), and LED8 now blinks slowly while the CPU clock runs.
Setting `USE_MMCM = false` brings back the template's divider.

The demo also takes the accelerometer reading at start-up as "level", so a sensor offset or an uneven table
does not make the view drift.

**Max frequency (compulsory):** set `CPU_CLK_DIV` to 1 (100 MHz), 2 (50), 3 (33.3), 4 (25) and run
implementation each time. The smallest value with **WNS ≥ 0** in the Design Timing Summary (and no critical
warning) is the max safe frequency. Report Timing Summary → the worst path shows what limits it (most likely
in E: forwarding mux → ALU → branch decision → next-PC mux).

---

## How the pipeline works (walkthrough)

```
   F               D                E                    M                    W
 PC_F --IROM-->  Instr_D  -->   ALU / MCycle     -->  ExecResult_M    -->  Result_W --> RegFile
 BTB lookup      Decoder        PC_Logic              DMEM / MMIO          LoadExtend
                 RegFile read   branch resolve        StoreAlign
                 Extend         BTB update
                                PipeMulE:             PipeMulM:
                                Booth + 4 CSA levels  2 CSA levels + add   MulResult_W
                                                      + select [k+31:k]
```

Followed the lab's systematic procedure: every signal has a stage suffix (`_F _D _E _M _W`), and a signal
that moves to the next stage goes through one pipeline register, e.g. `ExtImm_D -> ExtImm_E`. In `RV.v`
each pipeline register is one `always @(posedge CLK)` block, with reset, a stall (hold) and a flush
(bubble: every control signal that changes state cleared).

What moved where, compared to the single-cycle CPU:
- **F**: PC, `PC_F + 4` (next-PC adder), BTB lookup. The instruction from IROM goes into `Instr_D`.
- **D**: decode, register file read, immediate. The register file writes at the same edge as the pipeline
  registers, so it has a **write-through** (if W writes the register D reads, D gets the new value).
- **E**: forwarding muxes, ALU, MCycle, first half of the multiplier, `PC_Logic`, branch target adder,
  and the check of the prediction. `Redirect_E` = the instruction fetched after this one was the wrong one.
- **M**: data memory / MMIO access, second half of the multiplier. `ALUResult` (the Wrapper's address) is
  now `ExecResult_M`. `StoreAlign` makes the byte enables and puts the byte/half-word in the right lane.
- **W**: `LoadExtend` picks the byte/half-word out of the word and sign/zero-extends it; the result is the
  loaded value, the multiply result or the ALU/MCycle result; register write.

### The multiply unit (`PipeMul.v`)

The A3 MCycle multiplied one bit per cycle and **froze the whole pipeline** for 33 cycles per multiply.
The fractal does three multiplies per iteration, so that is where the time went. The new unit is a real
pipelined multiplier, split across the E and M stages:

1. **Radix-4 Booth recoding (E).** The multiplier is read 2 bits at a time (with 1 bit of overlap):
   digit = −2·b[2i+1] + b[2i] + b[2i−1] ∈ {−2, −1, 0, +1, +2}. That gives **17 partial products instead of
   32**, each just A, 2A or 0, inverted if negative (+1 at bit 2i for the two's complement, collected in
   one extra row). Signed and unsigned (mulhu) both work by extending the operands to 34 bits.
2. **Carry-save tree (E, then M).** 18 rows → 12 → 8 → 6 → 4 with 3:2 compressors (`s = x^y^z`,
   `c = majority(x,y,z) << 1`: no carries propagate, so each level is one LUT deep). The 4 rows go into the
   E/M register; M does 4 → 3 → 2.
3. **One 64-bit adder (M),** then the **funnel select** `product[k+31 : k]` → the M/W register.
   mul is k = 0, mulh/mulhu k = 32, mulsr any k from 0 to 31.

No `*` anywhere. The only `+` is the final carry-propagate adder (multiplication is an allowed exception).

**In the pipeline**, a multiply is like a load: its result is ready at the end of M, so
- a new multiply can start every cycle, and independent multiplies never stall,
- an instruction that uses the product right away waits 1 cycle (the load-use rule, `HazardUnit.v`), then
  gets it forwarded from W.

The fractal's inner loop (3 `mulsr` + 7 other instructions) runs with no stalls at all, because GCC puts
each product's first user 2 or more instructions after it.

**`mulsr rd, rs1, rs2, k`** (custom-0 opcode `0001011`, funct3 `000`, funct7 = k): rd = (rs1 × rs2) >> k,
signed. In fixed point with k fraction bits this is "multiply", in **one** instruction. Plain RV32IM needs
`mul` + `mulh` + `srli` + `slli` + `or` and two multiplies. Written in C as
`__asm__(".insn r 0x0b, 0, k, %0, %1, %2" ...)`.

**Slow-multiplier mode** (`CPU_CTRL[2]`, SW2): multiplies go back to the A3 MCycle (33 cycles, pipeline
frozen). Its 64-bit product is fed into the same second half (as one row plus zeros), so mulsr still works.
The setting is latched per instruction, so flipping SW2 mid-multiply is safe.

### Next PC (in priority order)
1. `Redirect_E` (mispredicted branch, any `jalr`, `mret`) → the correct PC, and flush D and E.
2. Interrupt taken → `ISR_ADDR` (= `0x00400004`), flush D and E, `EPC = PC_D`.
3. BTB predicts taken → the stored target.
4. Otherwise `PC_F + 4`.

### Hazards (`HazardUnit.v`)

| Hazard | Handled by | Cost |
|---|---|---|
| ALU result needed by the next instructions | forward from M (`ExecResult_M`) or W (`Result_W`) into E | 0 |
| Register written in W, read in D | register-file write-through | 0 |
| Load or multiply, then an immediate user | stall F and D, bubble into E | 1 cycle |
| Branch/jal mispredicted, jalr, mret | flush D and E | 2 cycles |
| div (or mul in slow mode) in E, MCycle Busy | stall F, D, E; bubble into M | ~33 cycles |

All comparisons are 5-bit register-number equalities, as the lab allows. `UsesRs1_D / UsesRs2_D` stop
needless stalls when, e.g., an `addi`'s immediate bits happen to equal a register number.

### Branch prediction (`BranchPredictor.v`)
- 32 entries, direct-mapped by `PC[6:2]`, tag `PC[15:7]` (so in a ≤ 64 KB IROM no two instructions share an
  entry), 30-bit target, 2-bit saturating counter.
- **F**: hit and counter ≥ 10 → fetch from the target next. `PredTaken` travels down with the instruction.
- **E**: the real outcome is known. If it differs from the prediction → redirect. The entry is updated
  (or allocated, for a taken branch or a `jal`) by every branch/jal leaving E. `jalr` and `mret` are never
  predicted, so they always redirect.

### Byte / half-word (`LoadStore.v`)
Exactly as in the lab manual. `sb` of `0xAB` at an address ending in `10` → `WriteData_out = 0xABABABAB`,
`MemWrite_out = 0100`. `lbu` picks byte `addr[1:0]` and zero-extends; `lb` sign-extends. Only aligned
accesses. Size = `Funct3`, carried down the pipeline. The demo writes its pixels with `sh` (16-bit colour).

### Interrupts
- Wrapper: buttons are synchronised, sampled every 2^16 cycles (debounce), and a press sets a bit in
  `INT_FLAGS`. `Interrupt = |(INT_FLAGS & INT_EN)`.
- RV: taken when D holds a real instruction, nothing stalls, there is no redirect, and it is not already in
  the handler. The instructions in F and D are discarded (they run after the return); E, M and W finish. So
  `EPC = PC_D` and the interrupt is precise. `InISR` blocks nesting until `mret` passes E.
- `mret` (`0x30200073`) jumps to EPC. The C handler uses `__attribute__((interrupt("machine")))`, so GCC
  saves what it uses and ends with `mret`. `crt0.s` puts `j isr` at `0x00400004`.

### Live A/B switches (`CPU_CTRL`)
- `CPU_CTRL[0]`: no forwarding. D waits while E or M will write a register it reads. The setting travels with
  each instruction, and forwarding really is off for instructions decoded in this mode, so it is a faithful
  "CPU without a forwarding unit" and flipping it mid-program is safe.
- `CPU_CTRL[1]`: no branch prediction (the BTB keeps learning but never predicts taken).
- `CPU_CTRL[2]`: slow multiplier (above).
- `HAZARD_UNIT = 0` (parameter of RV, synthesis time): the plain pipeline of the compulsory task, with
  no forwarding / stalls (except MCycle) / flushes / prediction / interrupts. Programs need 3 nops between
  dependent instructions and 2 after branches (`sim/fuzz.py pad_with_nops` does this).

### MMIO registers added (base `0xFFFF0000`)

| Offset | Name | |
|---|---|---|
| `0x70` | CPU_CTRL | WO. [0] no forwarding, [1] no branch prediction, [2] slow multiplier. 0 after reset |
| `0x74` | INT_EN | WO. [2:0] interrupt enable for BTNL, BTNC, BTNR |
| `0x78` | INT_FLAGS | RW. [2:0] presses pending. Write 1s to acknowledge |

(OLED v2: `OLED_CTRL` bit 3 = present the drawn frame, `OLED_STATUS` `0x30` bit 0 = present not done yet.)

---

## The demo program: fractal explorer (`sw/demo/fractal.c`)

| Input | |
|---|---|
| Tilt the board | fly around the Mandelbrot set (accelerometer); in Julia mode, steer c so the set morphs |
| BTNR / BTNL (hold) | zoom in / out |
| BTNC | Mandelbrot ↔ Julia set of the point under the crosshair — **interrupt** |
| SW0, SW1, SW2 | switch forwarding / branch prediction / the fast multiplier **off** (CPU_CTRL, every frame) |
| SW3 | software: plain RV32IM (`mul` + `mulh` + shifts) instead of `mulsr` |
| SW7–4 | max iterations = 32 + 16 × SW[7:4] (more detail, slower) |
| SW12 | reverse the tilt directions |
| SW15 | 7-seg: 0 = cycles per frame, 1 = cycles per iteration (decimal) |

| Output | |
|---|---|
| OLED | the fractal, drawn into the back buffer and presented every frame; colours cycle |
| 7-seg | cycles per frame, or per iteration |
| LED3–0 | SW3–0 echoed (what is switched off) · LED6 toggles every frame · LED7 Julia mode |
| LED8 | blinks while the CPU clock runs |

**Boot self-test:** LED0 = `main()` reached, LED1 = first frame drawn, LED2 = first present done.
Normally this flashes by in milliseconds. If the board stops, the LEDs show how far it got.

Each pixel is up to `max_iter` iterations of z = z² + c in **Q7.25 fixed point** (7 integer bits are
needed because |z|² can reach ~42 before the escape test). Every iteration is three multiplies (x², y², 2xy;
the 2 comes free as a shift of 24 instead of 25), so the multiplier decides the frame rate.

![Mandelbrot and Julia frames from simulation](docs/fractal_frames.png)

### Suggested demo script (about 3 minutes)
1. All switches down. Tilt the board to fly around, hold BTNR to zoom into the edge. Point at the 7-seg:
   ~950 000 cycles per frame.
2. Flip **SW2** (old multiplier): the picture crawls, and the 7-seg jumps about 10×. Flip it back. Flip **SW3**
   (no mulsr): noticeably slower. SW0 / SW1: forwarding and prediction. **Same program, same bitstream.**
3. SW15 up: cycles **per iteration** (~12 with everything on, ~116 with SW2). The inner loop runs at 1 instruction
   per cycle, with 3 multiplies in it.
4. Press **BTNC** (interrupt): the Julia set of the crosshair point appears and morphs. Tilt to steer it.
   The main loop never reads BTNC.
5. Mention: the A3 program still runs unmodified (LED = 0xFF); verification (random programs, interrupts,
   planted bugs, whole-chip simulation with the panel model).

---

## Vivado steps

1. Open `as4.xpr`. Check these are in Design Sources: `HazardUnit.v`, `BranchPredictor.v`, `LoadStore.v`,
   **`PipeMul.v`** (if not: Add Sources → add them from `as4.srcs/sources_1/imports/as2/`). Synthesis top
   stays `TOP`.
2. **Behavioural simulation**: simulation top `test_Wrapper`, Run All (~65 ms simulated, a few minutes). It
   prints one line per frame and ends with `PASS`.
3. **Max frequency**: `CPU_CLK_DIV` in `TOP_Nexys.vhd` (see *Clocking* above). Run implementation and read
   WNS. Use the fastest passing value for the demo.
4. **Post-synthesis simulation**: set `Wrapper.v` as the synthesis top (right-click → Set as Top),
   synthesise, then Run Simulation → Run Post-Synthesis Functional Simulation with `test_Wrapper`. Set `TOP`
   back as the top afterwards.
5. **Bitstream**: right-click synth_1 → Reset Runs (Vivado does not notice changed .mem files), Generate
   Bitstream, program the board. The OLED starts by itself about 0.1 s later; no need to press anything.

## Building programs
In WSL / Linux: `sudo apt install gcc-riscv64-unknown-elf`, then

```
cd sw && python3 build.py demo/fractal.c
```

This compiles with `crt0.s` + `link.ld`, writes `AA_IROM.mem` / `AA_DMEM.mem` into both `sources_1` and `sim_1`,
the disassembly (`sw/build/program.lst`) and the generated assembly (`sw/build/fractal.s`, for the
submission), and checks that only instructions this CPU implements are used (including `mulsr`). The .mem
files of the demo are already committed. `demo/breakout.c` (the earlier demo) still builds and runs.

## Verification (`sim/`)
`python3 sim/run_tests.py` (Icarus Verilog: `sudo apt install iverilog`) runs every program on the RTL and on
`iss.py`, a small instruction-set simulator, and compares all registers, all of DMEM and every MMIO store:

- `tests/smoke.s`, `tests/mulsr.s` (multiplier and mulsr: back-to-back, dependent, every k, a Q4.28
  Mandelbrot loop), each also padded with nops on the `HAZARD_UNIT = 0` pipeline;
- 1000 random programs (`fuzz.py`: every instruction incl. mulsr with random k, multiply bursts, dependent
  chains, load-use pairs, all load/store sizes and offsets, MMIO stores, div, forward branches, loops,
  calls, jalr, the program writing CPU_CTRL itself) in CPU_CTRL modes 0/1/2/3/4/7, with the switches flipped
  at random every few cycles, and with CPU_CTRL left to the program;
- 60 random programs interrupted by button presses at random times (results must be unchanged, the handler
  must run once per press).

The multiplier on its own: 202 366 vectors (corner values × every k, plus random), all exact.

**Planted bugs** (mutation test: one bug at a time, then the regression above), 19 of 20 caught:
- pipeline: forwarding priority swapped, no load-use stall, no flush of E on redirect, no register-file
  write-through, wrong prediction check, `lb` zero-extending, `sh` wrong byte lanes, interrupt taken during
  a stall, `EPC = PC_F`, MCycle operands not forwarded, no-forwarding mode not waiting for E / for M;
- multiplier: no stall after a multiply, `mulsr`'s rs2 not seen as a source, `mulhu` treated as signed,
  `mulh` taking bits [62:31], Booth +1 bits in the wrong place, slow mode using the Booth rows, the
  slow-multiplier setting not latched per instruction (caught by the mode where the program writes
  `CPU_CTRL` itself).
- Not caught: removing the M bubble while MCycle is busy. That one is harmless: it only rewrites the
  instruction's own rd with a value that is overwritten when MCycle finishes.

**Whole-chip simulation** (`sim/chip/`): TOP + OLED controller (course VHDL → Verilog with GHDL 4.1), our
Wrapper/CPU, the MMCM/BUFG replaced by simple models, and an SSD1331 panel model decoding the SPI wires. It
is how the blank-OLED problem was found; `run_chip.sh` reruns it.

## Files

| What | File |
|---|---|
| Pipelined CPU | `as4.srcs/sources_1/imports/as2/RV.v` |
| Pipelined multiplier (Booth + CSA) | `.../PipeMul.v` |
| Hazard unit | `.../HazardUnit.v` |
| Branch predictor | `.../BranchPredictor.v` |
| Byte/half-word load/store | `.../LoadStore.v` |
| Decoder (+ mret, mulsr), RegFile (+ write-through) | `.../Decoder.v`, `.../RegFile.v` |
| Wrapper (v2 + CPU_CTRL + interrupts) | `.../Wrapper.v` |
| TOP (v2 + MMCM + power-on reset), OLED (v2 + initial values) | `.../TOP_Nexys.vhd`, `.../pmodoledrgb_bitmap.vhd` |
| Vivado testbench (demo, port-level, post-synth OK) | `.../test_Wrapper.v` |
| Demo program | `sw/demo/fractal.c` (+ `fractal_tables.h`) → `sw/build/fractal.s`, `AA_IROM.mem`, `AA_DMEM.mem` |
| Start-up code, linker script, build script | `sw/crt0.s`, `sw/link.ld`, `sw/build.py` |
| Regression, reference model, random programs, testbench | `sim/run_tests.py`, `sim/iss.py`, `sim/fuzz.py`, `sim/tb_cpu.v` |
| Whole-chip simulation | `sim/chip/` |
| Slides | `Lab4_Slides.pptx` |
| Submission zip | `python3 make_submission.py --bit …` → `Group39_Friday_Lab4.zip` |

## AI assistance declaration (CG3207 lab manual)
Tool: Claude (Anthropic), model Claude Opus 5.5, via claude.ai, 3–4 Nov 2026.
Prompts: "for this assignment, I want to integrate in the pmod oled display as well … complete all the
compulsory and optional tasks as well"; "start all over again i want an enhancement that enhances
performance critically, and ties in well while remaining creative and cool … also the pmod oled doesnt
show anything when i run the bitstream figure out why and fix it". All of the Assignment 4 RTL, the demo
programs, the build/test scripts and the slides came from these.
