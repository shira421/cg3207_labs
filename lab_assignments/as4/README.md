# Assignment 4 — Pipelining + enhancements (Week 12 demo)

This is its own Vivado project (`as4.xpr`), started as a copy of the Assignment 3 project in `../as3`,
which stays as it was demoed. The sources are still in `as4.srcs/sources_1/imports/as2/` so the project
file needed no path changes.

## Status

| Part | What was done | Verified | Still to do (needs Vivado / the board) |
|---|---|---|---|
| Compulsory: pipelining | 5-stage pipeline F/D/E/M/W, runs everything from A2 + A3 (incl. MCycle mul/div) | The **unmodified A3 program** (`../as3/test.asm`) gives LED = 0xFF, mul/div 33 cycles; 1000+ random programs match a reference model; a `HAZARD_UNIT = 0` build (plain pipeline, programs padded with nops) also matches | Synthesis + timing: find the max frequency with `CLK_DIV_BITS`, report it |
| Enh. 1: hazard unit | Forwarding (M→E, W→E), register-file write-through (W→D), load-use stall, flush on redirect, MCycle stall | Random programs in every mode; planted bugs (mutation test) all caught | — |
| Enh. 2: branch prediction | 32-entry BTB with 2-bit counters, predicted in F, resolved in E | Same; mispredictions/target checks covered by planted bugs | — |
| Enh. 3: byte/half-word load/store | `lb lh lbu lhu sb sh` (StoreAlign in M, LoadExtend in W) | Random programs (all sizes, all offsets, DMEM and MMIO) | — |
| Enh. 4: interrupts | Push-button interrupts, EPC, `mret`, precise (taken between instructions) | 60 random programs interrupted at random times: results unchanged, handler ran once per press, in every mode | — |
| Enh. 5: live A/B switches | `CPU_CTRL` MMIO register switches forwarding / branch prediction off **while the program runs** | Random programs with the switches flipped every few cycles | — |
| OLED | v2 double-buffered OLED files (Wrapper, TOP, pmodoledrgb_bitmap) | Demo frames rendered from simulation (`docs/breakout_frames.png`) | Check on the board |
| Demo program | Breakout in C (`sw/demo/breakout.c`) | `test_Wrapper.v` (behavioural) prints **PASS**; frames look right | Bitstream + board, post-synthesis simulation |
| Slides | `Lab4_Slides.pptx` (5 slides) | — | Fill in the max frequency and resource numbers from Vivado |

## The numbers (same program, switches flipped live)

Cycles the CPU needs to compute and draw one Breakout frame (shown on the 7-segment display):

| SW1 SW0 | CPU | Cycles / frame | CPI |
|---|---|---|---|
| 0 0 | everything on | **45 412** | 1.05 |
| 0 1 | no forwarding (interlocks) | 71 911 | 1.65 |
| 1 0 | no branch prediction (always flush taken branches) | 73 290 | 1.68 |
| 1 1 | neither (= a plain interlocked pipeline) | 95 675 | 2.19 |

So forwarding + branch prediction make the frame **2.1x faster**. On random test programs (which have many
mul/div) the CPI goes from 3.03 to 2.28.

---

## How the pipeline works (walkthrough)

```
   F               D                E                  M                W
 PC_F --IROM-->  Instr_D  -->   ALU / MCycle   -->  ExecResult_M -->  Result_W --> RegFile
 BTB lookup      Decoder        PC_Logic            DMEM / MMIO       LoadExtend
                 RegFile read   branch resolve      StoreAlign
                 Extend         BTB update
```

Followed the lab's systematic procedure: every signal has a stage suffix (`_F _D _E _M _W`), and a signal
that moves to the next stage goes through one pipeline register, e.g. `ExtImm_D -> ExtImm_E`. In `RV.v`
each pipeline register is one `always @(posedge CLK)` block, with reset, a stall (hold) and a flush
(bubble: every control signal that changes state cleared).

What moved where, compared to the single-cycle CPU:
- **F**: PC, `PC_F + 4` (next-PC adder), BTB lookup. The instruction from IROM goes into `Instr_D`.
- **D**: decode, register file read, immediate. The register file writes at the same edge as the pipeline
  registers, so it has a **write-through** (if W writes the register D reads, D gets the new value).
- **E**: forwarding muxes, ALU, MCycle, `PC_Logic`, branch target adder (`PC_E` or `rs1` + imm), and
  the check of the prediction. `Redirect_E` = the instruction fetched after this one was the wrong one.
- **M**: data memory / MMIO access. `ALUResult` (the Wrapper's address) is now `ExecResult_M`.
  `StoreAlign` makes the byte enables and puts the byte/half-word in the right lane.
- **W**: `LoadExtend` picks the byte/half-word out of the word and sign/zero-extends it; register write.

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
| Load followed by a user of the loaded value | stall F and D, bubble into E | 1 cycle |
| Branch/jal mispredicted, jalr, mret | flush D and E | 2 cycles |
| mul/div in E (MCycle Busy) | stall F, D, E; bubble into M | ~33 cycles |

All comparisons are 5-bit register-number equalities, as the lab allows. `UsesRs1_D / UsesRs2_D` stop
needless stalls when, e.g., an `addi`'s immediate bits happen to equal a register number.

MCycle takes its (forwarded) operands in its first cycle; the pipeline holds the instruction in E while
`Busy`, and sends bubbles into M so nothing is written twice.

### Branch prediction (`BranchPredictor.v`)
- 32 entries, direct-mapped by `PC[6:2]`, tag `PC[15:7]` (so in a ≤ 64 KB IROM no two instructions share an
  entry), 30-bit target, 2-bit saturating counter.
- **F**: hit and counter ≥ 10 → fetch from the target next. `PredTaken` travels down with the instruction.
- **E**: the real outcome is known. If it differs from the prediction → redirect. The entry is updated
  (or allocated, for a taken branch or a `jal`) by every branch/jal leaving E. `jalr` and `mret` are never
  predicted, so they always redirect.
- A correctly predicted taken branch costs 0 instead of 2 cycles. Loops are where it shows.

### Byte / half-word (`LoadStore.v`)
Exactly as in the lab manual. `sb` of `0xAB` at an address ending in `10` → `WriteData_out = 0xABABABAB`,
`MemWrite_out = 0100`. `lbu` picks byte `addr[1:0]` and zero-extends; `lb` sign-extends. Only aligned
accesses. Size = `Funct3`, carried down the pipeline.

### Interrupts
- Wrapper: buttons are synchronised, sampled every 2^16 cycles (debounce), and a press sets a bit in
  `INT_FLAGS`. `Interrupt = |(INT_FLAGS & INT_EN)`.
- RV: taken when D holds a real instruction, nothing stalls, there is no redirect, and it is not already in
  the handler. The instructions in F and D are discarded (they run after the return); E, M and W finish. So
  `EPC = PC_D` and the interrupt is precise. `InISR` blocks nesting until `mret` passes E.
- `mret` (`0x30200073`) jumps to EPC. The C handler uses `__attribute__((interrupt("machine")))`, so GCC
  saves what it uses and ends with `mret`. `crt0.s` puts `j isr` at `0x00400004`.

### Live A/B switches (`CPU_CTRL`)
- `CPU_CTRL[0] = 1`: no forwarding. D waits while E or M will write a register it reads (W is covered by the
  write-through). The setting travels with each instruction (`NoForward_E`), and forwarding is really off
  for instructions decoded in this mode, so it is a faithful "CPU without a forwarding unit" and flipping
  it mid-program is safe.
- `CPU_CTRL[1] = 1`: no branch prediction (the BTB keeps learning but never predicts taken).
- `HAZARD_UNIT = 0` (parameter of RV, synthesis time): the plain pipeline of the compulsory task, with
  no forwarding / stalls (except MCycle) / flushes / prediction / interrupts. Programs need 3 nops between
  dependent instructions and 2 after branches (`sim/fuzz.py pad_with_nops` does this).

### New MMIO registers (base `0xFFFF0000`)

| Offset | Name | |
|---|---|---|
| `0x70` | CPU_CTRL | WO. [0] no forwarding, [1] no branch prediction. 0 after reset |
| `0x74` | INT_EN | WO. [2:0] interrupt enable for BTNL, BTNC, BTNR |
| `0x78` | INT_FLAGS | RW. [2:0] presses pending. Write 1s to acknowledge |

(OLED v2: `OLED_CTRL` bit 3 = present the drawn frame, `OLED_STATUS` `0x30` bit 0 = present not done yet.)

---

## The demo program: Breakout (`sw/demo/breakout.c`)

| Input | |
|---|---|
| BTNL / BTNR | move the paddle |
| BTNC | launch / pause / restart — **interrupt** |
| SW0, SW1 | switch forwarding / branch prediction **off** (CPU_CTRL, every frame) |
| SW14 | autoplay (paddle follows the ball) — handy for comparing modes hands-free |
| SW15 | 7-seg: 0 = cycles per frame (decimal), 1 = score |

| Output | |
|---|---|
| OLED | the game: every frame all 6144 pixels are computed and written (16-bit colour, `sh`), then presented |
| 7-seg | cycles per frame, or score |
| LED7 / LED6-4 / LED1-0 | paused / lives / SW1, SW0 echoed |

Why it shows off the enhancements: the frame is one big branchy per-pixel loop (branch prediction), full of
dependent instructions (forwarding), the bricks are a byte array (`lbu`/`sb`), pixels are half-word stores to
the OLED, BTNC is an interrupt, the score uses `mul` and the decimal 7-seg uses `divu`/`remu`. The ball moves
a fixed distance per frame, so a slower CPU gives a **visibly slower game**.

![frames](docs/breakout_frames.png)

### Suggested demo script (about 3 minutes)
1. Start with SW14 on (autoplay), SW1 SW0 = 00. Point at the 7-seg (~45 000 cycles/frame).
2. Flip SW0: ~72 000 (no forwarding). Flip back. Flip SW1: ~73 000 (no prediction). Both: ~96 000 — the
   game visibly slows down. Same program, same bitstream: only the CPU behaviour changed.
3. SW14 off, play with BTNL/BTNR. Press BTNC to pause/resume: that is the interrupt (the game loop never
   reads BTNC). LED7 shows paused.
4. Mention the A3 program still runs unmodified (LED = 0xFF), and the verification (random programs, mutation test).

**Clock for the demo.** The OLED shows at most ~68 frames/s (SPI at 6.67 MHz, 16 bits × 6144 pixels). At
`CLK_DIV_BITS = 5` (3.125 MHz with the v2 TOP) a frame takes 14.5 ms with everything on (≈ OLED speed) and
30.6 ms with neither (half speed), so the difference is easy to see. At `CLK_DIV_BITS = 6` it is
34 fps vs 16 fps. At the max frequency the CPU is much faster than the OLED, so only the 7-seg shows the
difference. Note the **v2 TOP fixes an off-by-one**: the clock is now 100 MHz / 2^CLK_DIV_BITS (v1 divided
by 2^(CLK_DIV_BITS+1)).

---

## Vivado steps

1. Open `as4.xpr`. Check that `HazardUnit.v`, `BranchPredictor.v` and `LoadStore.v` are in Design Sources
   (if not: Add Sources → add them from `as4.srcs/sources_1/imports/as2/`). Synthesis top stays `TOP`.
2. **Behavioural simulation**: simulation top `test_Wrapper`, Run All (~8 ms simulated). It prints one line per
   frame and ends with `PASS`.
3. **Max frequency (compulsory)**: set `CLK_DIV_BITS` in `TOP_Nexys.vhd` to 0, 1, 2, … run synthesis +
   implementation, and look for the critical warning that timing is not met. The smallest value without it
   is the max safe frequency (100 MHz / 2^CLK_DIV_BITS). Open the timing report to see the critical path —
   it is most likely in E (forwarding mux → ALU → branch decision → next-PC mux). Put this on the slides.
4. **Post-synthesis simulation**: set `Wrapper.v` as the synthesis top (right-click → Set as Top), synthesise,
   then Simulation → Run Post-Synthesis Functional Simulation with `test_Wrapper`. Set `TOP` back as the top
   afterwards.
5. **Bitstream**: put `CLK_DIV_BITS` back to the demo value (5), re-run synthesis (Vivado does not notice
   changed .mem files), generate the bitstream, program the board.

## Building programs
In WSL / Linux: `sudo apt install gcc-riscv64-unknown-elf`, then

```
cd sw && python3 build.py demo/breakout.c
```

This compiles with `crt0.s` + `link.ld`, writes `AA_IROM.mem` / `AA_DMEM.mem` into both `sources_1` and `sim_1`,
the disassembly (`sw/build/program.lst`) and the generated assembly (`sw/build/breakout.s`, for the
submission), and checks that only instructions this CPU implements are used. The .mem files of the demo are
already committed, so this is only needed after changing the program.

## Verification (`sim/`)
`python3 sim/run_tests.py` (Icarus Verilog: `sudo apt install iverilog`) runs every program on the RTL and on
`iss.py`, a small instruction-set simulator, and compares all registers, all of DMEM and every MMIO store:

- `tests/smoke.s`, plus the same program padded with nops on the `HAZARD_UNIT = 0` pipeline;
- 1000 random programs (`fuzz.py`: every instruction, dependent chains, load-use pairs, all load/store
  sizes and offsets, MMIO stores, mul/div, forward branches, loops, calls, jalr) in modes 00/01/10/11 and with
  the switches flipped at random every few cycles; a quarter of them also nop-padded on `HAZARD_UNIT = 0`;
- 60 random programs interrupted by button presses at random times (results must be unchanged, handler
  must run once per press).

Mutation test: 13 bugs were planted one at a time; these 12 were caught — forwarding priority
swapped, no load-use stall, no flush of E on redirect, no register-file write-through, wrong prediction
check, `lb` zero-extending, `sh` wrong byte lanes, interrupt taken during a stall, `EPC = PC_F`, mul
operands not forwarded, no-forwarding mode not waiting for E or for M. (Removing the M bubble while
Busy was not caught: it only re-writes the mul's own rd with a value that is overwritten anyway.)

## Files

| What | File |
|---|---|
| Pipelined CPU | `as4.srcs/sources_1/imports/as2/RV.v` |
| Hazard unit | `.../HazardUnit.v` |
| Branch predictor | `.../BranchPredictor.v` |
| Byte/half-word load/store | `.../LoadStore.v` |
| Decoder (+ mret), RegFile (+ write-through) | `.../Decoder.v`, `.../RegFile.v` |
| Wrapper (v2 + CPU_CTRL + interrupts), TOP, OLED (v2) | `.../Wrapper.v`, `.../TOP_Nexys.vhd`, `.../pmodoledrgb_bitmap.vhd` |
| Vivado testbench (demo, port-level, post-synth OK) | `.../test_Wrapper.v` |
| Demo program | `sw/demo/breakout.c` → `sw/build/breakout.s`, `AA_IROM.mem`, `AA_DMEM.mem` |
| Start-up code, linker script, build script | `sw/crt0.s`, `sw/link.ld`, `sw/build.py` |
| Regression, reference model, random programs, iverilog testbench | `sim/run_tests.py`, `sim/iss.py`, `sim/fuzz.py`, `sim/tb_cpu.v` |
| Slides | `Lab4_Slides.pptx` |
| Submission zip | `python3 make_submission.py` → `Group39_Friday_Lab4.zip` (add the .bit first) |

## AI assistance declaration (CG3207 lab manual)
Tool: Claude (Anthropic), model Claude Opus 5.5, via claude.ai, 3 Nov 2026.
Prompt: "for this assignment, I want to integrate in the pmod oled display as well … please setup everything
and run through the changes with me. complete all the compulsory and optional tasks as well"
(together with the group's A3 repository and the course's v2 OLED templates). All of the Assignment 4 RTL
changes, the demo program, the build/test scripts and the slides came from this.
