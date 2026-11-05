CG3207 Assignment 4 - Group 39 (Friday)
==========================================================
Pipelined RISC-V + enhancements. Demo program: real-time Mandelbrot / Julia fractal explorer on the
Pmod OLED (in header JB). CPU clock 50 MHz (MMCM), all timing constraints met.

Files created or modified by the group. Template files that are unchanged (ProgramCounter.v,
Shifter.v, uart.vhd, SPI_If.vhd, ADXL362Ctrl.vhd, the .xdc) are not included.

RTL sources
----------------------
RV.v              5-stage pipeline F/D/E/M/W. Pipeline registers with stall and flush, forwarding
                  muxes, branch resolution in E, BTB lookup in F, the pipelined multiplier in E and M,
                  byte/half-word store and load units, interrupts (EPC, mret), and the live switches
                  (CPU_CTRL: no forwarding / no prediction / slow multiplier, latched per instruction).
PipeMul.v         NEW. Pipelined 32x32 multiplier: radix-4 Booth (17 partial products) and a
                  carry-save tree (18 -> 4 rows) in E, 2 more CSA levels, one 64-bit adder and the
                  result window [k+31:k] in M. One multiply per cycle. No '*' operator.
HazardUnit.v      NEW. Forwarding select (M before W), load/multiply-use stall, flush on redirect and
                  on an accepted interrupt, MCycle stall, interlocking when forwarding is switched off.
BranchPredictor.v NEW. 32-entry branch target buffer with 2-bit saturating counters.
LoadStore.v       NEW. StoreAlign (byte enables, sb/sh/sw) and LoadExtend (lb/lh/lw/lbu/lhu).
Decoder.v         Adds mret and the custom instruction mulsr rd, rs1, rs2, k (custom-0 opcode 0001011,
                  funct3 000, funct7 = k): rd = (rs1 * rs2) >> k, signed. Multiplies go to the
                  pipelined multiplier; division stays on MCycle.
RegFile.v         Write-through (W -> D in the same cycle), registers start at 0.
Wrapper.v         Course v2 Wrapper (double-buffered OLED) plus CPU_CTRL (0x70), INT_EN (0x74) and
                  INT_FLAGS (0x78) MMIO registers, button synchronising/debouncing for interrupts,
                  4 KB IROM and DMEM.
MCycle.v          Assignment 3 multiply/divide unit (radix-2 Booth, restoring division). Used for
                  division, and for multiplies when SW2 selects the old multiplier.
ALU.v, Extend.v,  From Assignments 2 and 3 (ALU operations and flags, immediates, branch conditions).
PC_Logic.v
TOP_Nexys.vhd     Course v2 TOP plus: CPU clock from an MMCM (CPU_CLK_DIV = 2 -> 50 MHz), so Vivado
                  times the CPU; power-on reset for the CPU, OLED, accelerometer and UART (the OLED was
                  blank after programming without it); CPU reset synchronised to the CPU clock;
                  LED8 heartbeat. Fixes a missing OLED_Swap / OLED_SwapPending in the course
                  template's Wrapper component declaration.
pmodoledrgb_bitmap.vhd  Course v2 OLED controller with explicit initial values for its state machine.

Testbenches
----------------------
test_Wrapper.v           The demo (AA_IROM.mem / AA_DMEM.mem): 6 frames, checks every frame has 6144
                         pixels and is not blank, that mulsr is faster than mul+mulh+shifts
                         (933,564 vs 1,937,793 cycles), and that BTNC (interrupt) switches to the
                         Julia set. Prints PASS. Works for behavioural and post-synthesis simulation.
tb_all_enhancements.v    Five RV cores (all on, no forwarding, no prediction, slow multiplier, live
                         switching) run testbench_enhancements.asm; checks results, stalls, forwarding,
                         the BTB loop (2 vs 7 redirects), byte/half-word access and a precise interrupt.
                         Prints PASS.
tb_system_enhancements.v Wrapper integration: CPU_CTRL written by software, button interrupt with
                         acknowledge, OLED pixel and present/status handshake. Prints PASS.
tb_cpu.v                 Testbench used by our regression (random programs compared with a reference
                         instruction-set simulator, in every CPU_CTRL mode and with interrupts).
tb_chip.v, unisim_fake.vhd  Whole-chip simulation: TOP + OLED controller + CPU with a model of the
                         OLED panel decoding the SPI wires (MMCM/BUFG replaced by simple models).

Program
----------------------
fractal.c, fractal_tables.h  The demo in C (Q7.25 fixed point, mulsr through .insn).
fractal.s                Assembly generated from fractal.c (riscv64-unknown-elf-gcc -march=rv32im -Os).
crt0.s                   Start-up code: reset jump, interrupt vector at 0x00400004, stack.
AA_IROM.mem, AA_DMEM.mem The memory images in the bitstream.
testbench_enhancements.asm  The program run by tb_all_enhancements.v.

Other
----------------------
TOP.bit                  Bitstream used in the demo (CPU_CLK_DIV = 2, 50 MHz).
CG3207_Assignment4.pptx  Slides.

Demo controls
----------------------
Tilt the board: fly around the Mandelbrot set. BTNR / BTNL: zoom. BTNC: Mandelbrot <-> Julia set
(interrupt). SW0 / SW1 / SW2: switch forwarding / branch prediction / the pipelined multiplier off.
SW3: plain RV32IM instead of mulsr. SW7-4: iterations. SW15: 7-seg shows cycles per iteration
instead of per frame. BTND: reset.

Cycles per frame (96 x 64, 32 iterations), same program, switches flipped live:
  everything on 953,584 | no forwarding 1,449,056 (1.5x) | no prediction 1,154,544 (1.2x)
  no mulsr 1,967,776 (2.1x) | A3 multiplier 8,862,960 (9.3x) | all four off 18,880,880 (19.8x)
