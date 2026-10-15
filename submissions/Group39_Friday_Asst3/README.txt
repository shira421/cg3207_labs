CG3207 Assignment 3 - Multiplication / Division (Group 39, Friday)
==========================================================
Files created or modified by the group (all other project files are the unmodified templates
or unchanged from Assignment 2).

RTL
----------------------
MCycle.v      Task 1: signed and unsigned restoring division (MCycleOp 10 / 11). One quotient
              bit per cycle on the magnitudes; the quotient is negated if the operand signs
              differ and the remainder takes the dividend's sign (RISC-V rules, incl.
              -2^31 / -1 = -2^31 r 0 and x / 0 = -1 r x). 32 iterations (33 cycles).
              Task 3: radix-2 Booth signed multiplication (MCycleOp 00). Registers A (33b),
              M (33b), Q (32b), Q-1 (1b); each cycle {Q0,Q-1} = 01 adds M, 10 subtracts M,
              00/11 holds, then {A,Q,Q-1} is shifted right arithmetically. 32 iterations
              (33 cycles) instead of 64 (65 cycles); product = {A[31:0], Q}.
              Parameter BOOTH = 0 restores the original signed multiplier for comparison.
              Unsigned multiplication (01) is the original shift-and-add.

Decoder.v     Decodes the RV32M instructions (opcode 0110011, funct7 0000001): mul, mulh,
              mulhu, div, divu, rem, remu (mulhsu decodes as a NOP). New outputs: MStart,
              MCycleOp, MCycleSel (write the MCycle result instead of the ALU result) and
              MResultSel (Result1 = low word / quotient, Result2 = high word / remainder).

RV.v          Instantiates MCycle (width 32) on RD1/RD2. WE_PC = ~Busy stalls the processor
              while MCycle works; WE = RegWrite & ~Busy writes rd once, in the cycle Busy
              falls. A multiplexer selects the ALU or MCycle result.

Wrapper.v     IROM_DEPTH_BITS and DMEM_DEPTH_BITS raised from 9 to 10 (256 words each) to fit
              the demo program. No other change.

Testbenches
----------------------
test_MCycle.v    Self-checking testbench for MCycle: every operand pair at widths 4 and 6 for
                 all four operations, 32-bit corner cases plus 3000 random pairs per operation,
                 exact cycle counts, Busy timing, back-to-back and gapped Start, operands
                 changing while busy, reset mid-operation, both BOOTH settings
                 (76083 checks, all pass). test_MCycle_postsynth runs the 32-bit tests on a
                 synthesised netlist. Run with "run all".
test_Wrapper.v   Self-checking testbench for the whole CPU running test.asm: LEDs reach 0xFF,
                 every display value for all 16 test cases, measured mul/div cycles, and
                 own-operand mode with each button (229 checks, all pass). Run with "run all".

Program
----------------------
test.asm         Demo program (RARS, Default memory configuration). Runs mul, mulh, mulhu, div,
                 divu, rem and remu on 16 corner cases and checks each against a table
                 (LED[6:0] = one flag per instruction, LED7 = all correct; 0xFF expected),
                 measures the cycles of one mul and one div with the cycle counter, then shows
                 values on the 7-segment display:
                   SW15 = 0: SW3-0 test case, SW7-4 view (0 a, 1 b, 2 mul, 3 mulh, 4 mulhu,
                             5 div, 6 divu, 7 rem, 8 remu, 9 mul cycles, A div cycles, B LEDs)
                   SW15 = 1: SW14-8 = a, SW6-0 = b (7-bit signed); shows a*b, BTNL a/b,
                             BTNC a rem b, BTNR divu
AA_IROM.mem, AA_DMEM.mem   test.asm assembled with RARS (text and data dumps).

TOP.bit          Bitstream of the final design (BOOTH = 1).

Task 3 / Task 4
----------------------
Task3_Booth_Slides.pdf     Slides on the radix-2 Booth enhancement.
booth_visualisation.html   Task 4 interactive visualisation (single file; open in a browser).
prompt_history.md          Complete prompt history used to create the visualisation.
