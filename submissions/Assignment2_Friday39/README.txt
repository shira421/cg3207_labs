CG3207 Assignment 2
==========================================================
Files created or modified by the group (all other files are the unmodified templates).
----------------------
ALU.v         Added xor, slt, sltu and the shift operations (sll/srl/sra via the Shifter).
              Branch flags {eq, lt, ltu} are derived from the subtraction result:
              eq = Z, lt = N ^ V (signed, overflow-corrected), ltu = ~C (unsigned).

Decoder.v     Main control unit. Decodes the opcode into PCS, RegWrite, MemWrite, MemtoReg,
              ALUSrcA, ALUSrcB, ImmSrc and ALUControl for all supported instructions.
              Unsupported opcodes default to a NOP (no register/memory write, no jump).
              ALUSrcA added (for lui/auipc/link) and ALUSrcB widened to 2 bits (constant 4
              for the jal/jalr link value).

PC_Logic.v    Evaluates the branch condition (beq, bne, blt, bge, bltu, bgeu) from the ALU
              flags and generates a 2-bit PCSrc: PC+4, PC+imm (taken branch / jal) or
              rs1+imm (jalr).

RV.v          Datapath wiring: instruction field extraction, Src_A mux (RD1 / 0 / PC),
              Src_B mux (RD2 / ExtImm / 4), result mux (ALU / memory), and the next-PC adder
              (the second and only other 32-bit adder; bit 0 cleared for jalr).

Supported instructions: add, sub, and, or, xor, sll, srl, sra, slt, sltu, addi, andi, ori,
xori, slti, sltiu, slli, srli, srai, lw, sw, beq, bne, blt, bge, bltu, bgeu, jal (with link),
jalr, lui, auipc. (Task 1 and Task 2; byte/half-word load/store not implemented.)
----------------------
test_Wrapper.v   Self-checking testbench for test.asm. Steps the switches through all 16
                 trace-table entries and several inputs, checks the 7-segment display and LEDs
                 against values obtained from RARS, then presses a push button and checks the
                 program stops at 'halt'. Ends with a pass/fail summary (27 checks).
test.asm         Demo program (RARS, Default memory configuration). Each pass reads the
                 switches, runs 4 test pairs through every register-type instruction and all
                 6 branches (each branch both taken and not taken), calls a function with jal
                 and with jalr that uses every immediate-type instruction, and records 16
                 intermediate values in a trace table in data memory.
                   SW11-SW0  : input number
                   SW15-SW12 : which trace entry the 7-segment display shows
                   LED[7:0]  : summary of all 24 branch outcomes (always 0x65 when correct)
                   BTNL/BTNC/BTNR : stop the program at 'halt'
AA_IROM.mem      Instruction memory contents, dumped from RARS (.text, hexadecimal text).
AA_DMEM.mem      Data memory contents, dumped from RARS (.data, hexadecimal text).
TOP.bit          Bitstream used for the demo (CLK_DIV_BITS = 5, Nexys 4 DDR, xc7a100tcsg324-1).
