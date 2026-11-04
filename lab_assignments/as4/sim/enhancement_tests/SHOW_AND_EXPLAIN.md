# AS4: show and explain every CPU enhancement

This package targets the RTL in:
lab_assignments/as4 in shira421/cg3207_labs

The seven CPU enhancements are taken from README.md and checked against RV.v, PipeMul.v,
HazardUnit.v, BranchPredictor.v, LoadStore.v, Decoder.v, RegFile.v and Wrapper.v.
Forwarding is part of enhancement 3 (the hazard unit), rather than a separate eighth enhancement.
Whether the marking rubric gives it separate credit is a grading decision.

## Validation status — read this first

- Both testbenches were run with Icarus Verilog 12 against the repository RTL (4 Nov 2026) and print
  PASS. Results from that run:

  | Core | Errors | Cycles | Stalls | Busy | M fwd | W fwd | Loop redirects |
  |---|---:|---:|---:|---:|---:|---:|---:|
  | ALL_ON (000) | 0 | 181 | 38 | 32 | 19 | 20 | 2 |
  | NO_FORWARD (001) | 0 | 228 | 85 | 32 | 0 | 0 | — |
  | NO_PREDICT (010) | 0 | 197 | 38 | 32 | 19 | 14 | 7 |
  | SLOW_MUL (100) | 0 | 533 | 390 | 384 | 18 | 17 | — |
  | LIVE_SWITCHES | 0 | 234 | 83 | 64 | 13 | 13 | — (25 mode changes, 7 while E was held) |

  tb_system_enhancements: PASS (CPU_CTRL writes, slow multiply x5 = 42, OLED pixel (3,4) = f80000,
  present/status handshake, button interrupt acknowledged once).
- The first run failed with 12 errors in every core. Cause: in simulation the Decoder's `always @(*)`
  does not run until its input changes, so for one cycle after reset its outputs were x and a phantom
  "store" with an x address reached M. That shifted every later store check by one. RV.v now loads a
  bubble into E whenever D holds a bubble (`Valid_D = 0`), which is functionally identical (a bubble is
  a NOP) and removes the x. Real hardware was never affected.
- Vivado 2023.2 xvlog accepts both testbenches. The instruction encodings and all expected register and
  RAM values agree with the project's instruction-set simulator, including an injected interrupt.
- These tests use a 10 ns simulation clock for readable cycles. They do not establish FPGA Fmax.

## Files and Vivado setup

1. Extract the ZIP to a normal directory.
2. Open this codebase's as4.xpr. Keep TOP as the synthesis top.
3. Add tb_all_enhancements.v and tb_system_enhancements.v through
   Add Sources > Add or Create Simulation Sources.
4. Check that the design sources include PipeMul.v, HazardUnit.v, BranchPredictor.v and LoadStore.v.
5. In Simulation Sources, right-click tb_all_enhancements > Set as Top.
6. Run Simulation > Run Behavioral Simulation.
7. In the SIMULATION Tcl Console (after the simulator opens), paste:

   set demo_view pipeline
   source {C:/your/extracted/folder/all_waves.tcl}

   Replace that path with your actual path. Tcl accepts forward slashes and braces handle spaces.

8. Look for the final PASS in the console. If simulation initially stops at its default duration,
   enter run all. The test normally needs only microseconds; a 100 us watchdog catches hangs.
9. To change the view, change demo_view and source the same script again, for example:

   set demo_view branch
   source {C:/your/extracted/folder/all_waves.tcl}

Each invocation creates a fresh wave configuration, logs signals, restarts and runs to completion.
Signal rows are grouped by their hierarchical paths. Set PCs/instructions/data to hexadecimal;
register indices and counters to unsigned decimal; forwarding selectors and byte enables to binary.
Use the PC ranges below to locate an event. Times differ between comparison cores because they stall
by different amounts. Compare the same instruction/event, rather than assuming time alignment.

These tests use a 10 ns simulation clock for readable cycles. This does not establish FPGA Fmax.

## Which CPU is which?

| Path under /tb_all_enhancements | Configuration |
|---|---|
| fast/dut | All enhancements enabled, CPU_CTRL = 000 |
| nofwd/dut | CPU_CTRL = 001: no forwarding, dependency interlocks retained |
| nopred/dut | CPU_CTRL = 010: no taken prediction; BTB still trains |
| slow/dut | CPU_CTRL = 100: old MCycle multiplier |
| live/dut | Controls change every nine cycles, cycling 000/001/010/100/111 |

All five run the same instructions and must produce the same final architectural results.
No-forwarding is still a five-stage pipeline with stalls. It is not the unprotected
HAZARD_UNIT=0 compulsory pipeline.

The CPU-only harness directly connects RV and a 64-word RAM. Low data addresses belong to that
test RAM only; they are not the FPGA Wrapper's real data-memory addresses.
No application memory files or project RTL are changed.
The register file is initialized to zero by the testbench for deterministic simulation.

The console prints store transactions, branch resolutions, interrupt entry/return and final
coverage counters. A final PASS requires both correct outputs and observed mechanisms.

## Pipeline — compulsory feature

View: pipeline. Follow fast/dut as PC_D moves through 00400020–00400034.

The initial instructions are:
addi x1,x0,5; addi x2,x0,7; addi x3,x0,9; addi x4,x0,11; addi x5,x0,13.

What to see:
- PC_F, PC_D and PC_E identify different instructions in the same cycle.
- Follow rd_E=1/result=5 into rd_M=1/result=5 and then rd_W=1/Result_W=5.
- Meanwhile E is already processing x2, then x3.
- With no dependency stalls, x1..x5 commit on five consecutive rising edges.
- The testbench explicitly checks this consecutive-commit property in fast.

Say:
"The pipeline registers carry an instruction's information from one stage to the next.
Different instructions occupy the stages simultaneously. After filling, these independent
instructions write back one per cycle."

Do not say each instruction has one-cycle latency. Throughput and instruction latency differ.
PC values are carried only through F/D/E; identify M and W instructions by destination and result.
At a rising edge the register file commits the W-stage values present before that edge;
the new W-stage values appear after nonblocking updates.

## Enhancement 1 — pipelined multiplier

View: multiply. In fast, find PC_E 00400060, 00400064, 00400068.
Compare with the same PCs in slow.

| Instruction | Expected result |
|---|---:|
| mul x10,x1,x2 | 5*7 = 35 |
| mul x11,x3,x4 | 9*11 = 99 |
| mul x12,x5,x6 | 13*18 = 234 |

What to see:
- In fast, these independent multiplies enter E on consecutive cycles.
- IsMul_E, IsMul_M and IsMul_W mark multiplies moving through the pipeline.
- MulResult_M shows 35, 99, 234 on consecutive cycles; they reach W one cycle later.
- The test checks that the three products commit consecutively.
- Busy and StallE are zero for the fast multiply burst.
- In slow, SlowMul_E=1; Busy holds F/D/E while FlushM inserts bubbles.
  The same three correct products arrive much farther apart.
- The console reports busy cycles and completion cycles.

Say:
"We split multiplication between E and M. Independent multiplies overlap, allowing one completed
product per cycle once the multiplier fills. The old multiplier stalls the processor until each
multiply finishes."

Use MulResult_M, MulResult_W and Result_W for products. ExecResult_E/M/W is not the fast
multiplier's completed-product path. This test proves functional throughput, not FPGA clock speed.
Signed high-word mulh and unsigned high-word mulhu are also checked later:
for 0xfffffff9 times 5, x25=ffffffff and x26=00000004.

## Enhancement 2 — custom mulsr instruction

View: mulsr. Positive example at PC_E=0040006c.
Signed example at 004000a8; ordinary-instruction reconstruction at 004000ac–004000bc.

mulsr rd,rs1,rs2,k returns bits [k+31:k] of the signed 64-bit product.
The supported k range is 0..31.

| Case | Expected writeback |
|---|---|
| 5*7 shifted by 1, x13 | 00000011 = 17 |
| x13+1, x14 | 00000012 = 18 |
| -7*5 shifted by 1, x17 | ffffffee = -18 |
| mul + mulh + srli + slli + or, x9 | ffffffee = -18 |
| -7*5 with k=0, x7 | ffffffdd = -35 |
| -7*5 with k=31, x8 | ffffffff = -1 |

What to see:
- IsMul_E=1 and MulShift_E/M carry the requested k with the instruction.
- The signed result is -18, not -17: discarding low bits of a negative product rounds down here.
- The single mulsr and the five-instruction reconstruction produce the same 32-bit value.
- Immediate users of a product are stalled correctly (next section).

Say:
"mulsr combines signed multiplication and fixed-point rescaling. We select the required 32-bit
window of the full product, preserving information that could be lost by shifting only a low-word
mul result. It replaces this ordinary five-instruction sequence with one instruction."

The demo checks k=0, 1 and 31; it is a focused showcase, not exhaustive coverage of all operands/k.
The program listing gives every encoding; no assembler extension is needed.

## Enhancement 3 — hazard unit, including forwarding

Views: forwarding and hazards.

### M-to-E and W-to-E forwarding
At PC_E=00400034:
addi x5,x0,13 is followed immediately by add x6,x5,x1.

In fast:
- rs1_E=5, rd_M=5, ForwardA_E=10, FwdA_E=13.
- FwdB_E=5 and ALUResult_E=18.
- This ALU dependency needs no data stall.

In nofwd:
- The dependent instruction waits in D while E/M still own its source.
- StallF/StallD and FlushE insert the required bubbles.
- When it executes, forwarding selectors remain 00 and it still writes x6=18.

For a W-to-E example, inspect the consumer after the multiply/load-use bubble:
ForwardA_E=01 selects Result_W. The coverage requires both M and W forwarding in fast.

Say:
"The consumer needs the producer's value before it has reached the register file.
Forwarding supplies the newest result directly from M or W. With forwarding disabled,
interlocks preserve the result but add waiting cycles."

### Register-file write-through, W-to-D
At PC_D=00400044, addi x8,x7,1 reads x7 in the same cycle that W writes x7=21.
RD1_D must already be 21. x8 is 22 at this point (it is reused later).
This is a separate write-through path in RegFile, not the E-stage forwarding multiplexer.
The test requires at least one write-through event in every core.

### Multiply-use and load-use interlocks
- Multiply-use: PC_E=0040006c with its dependent addi in D at 00400070.
- Load-use: PC_E=00400154 with addi x19,x18,1 in D at 00400158.
- In fast, expect StallF=StallD=1, FlushE=1, StallE=0 for the dependency.
- On the next edge F/D hold while E becomes a bubble. The producer advances.
- The consumer then executes with the correct W-forwarded operand.
- x14=18; x19=8001feee. The test requires both event types.

Say:
"These results become available later than an ALU result. One bubble lets the producer finish;
the dependent instruction then receives the correct value."

### Redirect flushing and retained MCycle support
- Redirects flush D and E, preventing the two younger wrong-path instructions from committing.
- The branch test's wrong-path addi must leave x27=0, and its store must leave mem[5]=0.
- DIV at PC_E=00400260 still uses MCycle: Busy stalls F/D/E and FlushM bubbles M.
- x29=5 and the dependent x30=6 prove division and resumption still work.
Division is retained Assignment 3 functionality, not a new Assignment 4 enhancement.

## Enhancement 4 — branch prediction

View: branch. Compare fast/dut with nopred/dut.
Focus ONLY on conditional branch PC_E=0040018c; other jumps also redirect.

The loop increments x20 to 8. Its branch outcomes are:
T, T, T, T, T, T, T, N.

| Visit | Actual outcome | Fast prediction | Expected effect |
|---:|---|---|---|
| 1 | Taken | Not taken (cold BTB) | Redirect + D/E flush; allocate counter 10 |
| 2 | Taken | Taken | No redirect; counter becomes 11 |
| 3–7 | Taken | Taken | No redirect; counter stays 11 |
| 8 | Not taken | Taken | Redirect to fall-through; counter drops to 10 |

The branch's BTB index is 3: (0x0040018c >> 2) & 31.
If array visibility permits, ctr[3] and valid[3] show training directly.
Otherwise the prediction/outcome/redirect signals and console event lines establish the behaviour.

What to see:
- In F, PredTaken_F=1 selects PredTarget_F=00400188 for learned loop iterations.
- Later in E, PredTaken_E=Taken_E=1 and Redirect_E=0 for correct predictions.
- At loop exit, PredTaken_E=1, Taken_E=0, Redirect_E=1,
  CorrectPC_E=00400190, FlushD=FlushE=1.
- In fast, branch_visits=8, correct_taken=6, branch_redirects=2 for this PC.
- In nopred, branch_visits=8, correct_taken=0, branch_redirects=7.
- Both finish with x20=8 and x22=42. Wrong-path x27 and canary RAM remain zero.

Say:
"The first taken branch trains the BTB. Later taken iterations fetch the target immediately
and avoid recovery flushes. The loop exit is deliberately mispredicted, and the processor
redirects to the fall-through address and discards the wrong path. Disabling prediction
increases this loop's redirects from two to seven without changing its answer."

The predictor does not predict every branch correctly. It predicts branches and jal;
jalr and mret resolve through redirects. Counters in the guide are specific to this branch.

## Enhancement 5 — byte/half-word loads and stores

View: memory. PC_E region 00400100–00400158.
Initial mem[0]=11223344 (little endian).

| Stores | Byte enables | Word afterwards |
|---|---|---|
| sb 80 at +0 | 0001 | 11223380 |
| sb 81 at +1 | 0010 | 11228180 |
| sb 82 at +2 | 0100 | 11828180 |
| sb 83 at +3 | 1000 | 83828180 |
| sh feed at +0 | 0011 | 8382feed |
| sh 8001 at +2 | 1100 | 8001feed |

WriteData_out repeats a byte/halfword in all lanes; only enabled lanes are written.
The scoreboard checks each address, mask and data, plus final RAM.

| Load from +0 | Result | Stored to test RAM |
|---|---|---|
| lb | ffffffed (-19) | mem[1], address 4 |
| lbu | 000000ed (237) | mem[2], address 8 |
| lh | fffffeed (-275) | mem[3], address 12 |
| lhu | 0000feed (65261) | mem[4], address 16 |
| lw | 8001feed | x18 |

Say:
"The write enables update only the addressed bytes. The load unit selects the addressed
byte or halfword, then sign-extends signed loads and zero-extends unsigned loads.
The matching RAM checks show that neighbouring bytes are preserved."

Only aligned word/halfword accesses are supported; this showcase does not claim misaligned support.

## Enhancement 6 — precise interrupts and mret

View: interrupt. Main test PCs 00400200–00400218; vector 00400004; handler 00400300.

The harness asserts Interrupt at a falling edge when PC_D=0040020c.
It intentionally keeps the request high during the handler to exercise nesting suppression.

What to see:
- Interrupt=1 followed by IntTake=1 when D is valid and the CPU can accept the interrupt.
- On the acceptance edge: EPC becomes 0040020c, InISR becomes 1,
  PC redirects to vector 00400004, and FlushD/FlushE discard the younger instructions.
- The older addi in E completes; it is not discarded.
- The handler increments x28 once and executes mret at 00400304.
- InISR prevents a nested acceptance while the request remains high.
- Mret_E selects CorrectPC_E=EPC and redirects back to 0040020c.
- The resumed loop finishes with x23=6. Losing or repeating its interrupted increment would
  change the expected result.
- irq_count=1, mret_count=1, x28=1. The test checks both the saved EPC and return target.

Say:
"We preserve older in-flight instructions, save the address of the D-stage instruction,
and discard younger work. The handler runs once, then mret resumes at the saved address.
The final loop count confirms that the interrupted program neither loses nor repeats work."

This CPU test injects the RV Interrupt input directly. The separate system test below verifies
the real Wrapper button, pending flag, enable and acknowledgement path.

## Enhancement 7 — safe live A/B feature controls

View: live. Inspect /tb_all_enhancements/live.
cpu_ctrl cycles through 000,001,010,100,111 every nine clock cycles.

What to see:
- CPU controls change without RESET.
- NoForward_E and SlowMul_E are latched for the instruction when it leaves D.
- They remain stable while that instruction is held in E, even when cpu_ctrl changes.
- With SlowMul_E=1, MCycle completes the original multiply correctly despite a later mode change.
- Prediction enable changes the F-stage lookup; the BTB still trains when prediction is disabled.
- The live core produces the same final registers/RAM as the other four cores.
- mode_changes, modes_seen and held_mode_changes confirm that switching actually occurred.
- Assertions check stability of latched controls while E stalls.

Say:
"The control bits change the selected implementation while the program runs.
Instructions already in flight retain their own latched forwarding/multiplier mode,
so a switch does not corrupt them. Identical final results and explicit switching coverage
show that changing modes preserves correctness."

There is no per-instruction NoPredict_E latch; do not claim all three controls are latched.
SW3 in the fractal application is a software choice between mulsr and an ordinary sequence;
it is not a fourth RV CpuCtrl bit. The mulsr comparison above demonstrates the two calculations.

## Run the actual Wrapper integration supplement

After the CPU suite, close simulation, set tb_system_enhancements as simulation top and run
Behavioural Simulation again. The project must retain its normal AA_IROM.mem and AA_DMEM.mem
as simulation dependencies. At 1 ns this test fills only the simulated IROM/DMEM arrays with
its short program; it does not overwrite files.

Paste:
source {C:/your/extracted/folder/system_waves.tcl}

This test demonstrates:
1. Actual CPU stores to CPU_CTRL select 001,010,100,000 in the Wrapper register.
   A multiply in slow mode still produces x5=42.
2. A halfword RGB565 pixel write produces OLED_Write with col=3,row=4,rgb=f80000.
3. A present command pulses OLED_Swap. A small testbench model asserts OLED_SwapPending.
   Software reads OLED_STATUS=1 while busy, then reads 0 and progresses.
4. Software enables button 0. PB passes through pb_sync1/pb_sync2 and the sampling logic,
   sets int_flags, and drives Interrupt.
5. The real handler acknowledges the flag using write-one-to-clear at INT_FLAGS,
   increments x28 once and returns. Check exactly one interrupt and mret, flags=0.

Say:
"This connects the CPU features to the real memory-mapped Wrapper. Software changes the
feature modes, a button generates an interrupt that software acknowledges, and the OLED
receives a pixel and a present request with the expected busy handshake."

The OLED controller/panel is modelled only by its pending handshake here. This does not prove
the physical page-copy/double-buffer controller or SPI output. PB sampling uses DEBOUNCE_BITS=2
to keep the test short, instead of the board's longer sampling interval.

## Board-level additions and what these tests do not establish

README also describes MMCM clocking, power-on reset, OLED initialization/double buffering and
the fractal/tilt interface. These are system/application additions beyond the seven CPU enhancements.

- This package checks the Wrapper's OLED pixel and present interface, not the VHDL framebuffer/SPI.
- Use the existing sim/chip whole-chip test to show actual OLED startup, frames and page exchange.
  That flow uses behavioural MMCM/BUFG models and does not establish physical timing.
- Use TOP behavioural simulation to inspect RESET_INT and MMCM lock before board operation.
  The CPU-only test intentionally bypasses that clock/reset circuitry.
- Establish maximum FPGA frequency using correctly constrained post-route implementation reports.
- Run the existing test_Wrapper fractal simulation for the application demonstration and use the
  board for tilt/buttons, visible frames and live switch performance.

Do not claim the new CPU test proves these separate system behaviours.

## Recommended presentation evidence

Capture one view per row; combine hazard subcases if time is short.

| Capture | Evidence |
|---|---|
| Pipeline | x1 progression plus simultaneous different stages |
| Multiplier | Three consecutive fast products vs spaced slow products |
| mulsr | x17=-18 equals reconstructed x9=-18; shift travels with instruction |
| Forwarding/hazards | selector 10 vs interlock; one load/multiply-use bubble |
| Branch | Cold miss, learned correct prediction, exit recovery; redirects 2 vs 7 |
| Memory | Byte masks and signed vs unsigned extension |
| Interrupt | IntTake, EPC, InISR, mret, correct resumed count |
| Live controls | Controls change during Busy; latched instruction mode stays fixed |
| Wrapper supplement | CPU_CTRL writes, real button flag/ack, OLED pixel/present/status |

Keep the console PASS and counters as supporting evidence. Screenshots should include CLK,
relevant PCs, control signals and the checked result together.

