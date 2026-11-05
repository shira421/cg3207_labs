# Assembly view of the exact ROM in tb_all_enhancements.v.
# All five CPU configurations execute this same instruction program.
# The Verilog case(PC), not this file, supplies instructions during simulation.
# Each comment gives the absolute simulated PC and the exact instruction word.
# GNU RISC-V assembly syntax. If assembled, link .text at 0x00400000.
# Custom mulsr uses .word because a standard assembler does not know its mnemonic.
# Gaps contain explicit 32-bit NOPs, matching the ROM's default instruction.
# Simulation RAM is mapped at 0; mem[0] starts as 0x11223344 and other words as 0.
# The testbench initializes registers, injects IRQ at PC_D=0x0040020c,
# changes CpuCtrl for the live core, and finishes after x31 commits 123.
# Those stimuli/checks are Verilog testbench behaviour, not assembly instructions.

    .section .text
    .option norvc
    .option norelax
    .balign 4
    .globl _start


# ENTRY
_start:
    j main                          # PC=0x00400000  word=0x0200006f

# VECTOR
interrupt_vector:
    j isr                           # PC=0x00400004  word=0x2fc0006f

    # NOP padding: 0x00400008 through 0x0040001c
    .rept 6
        nop
    .endr


# PIPELINE / FORWARDING
main:
    addi x1,x0,5                    # PC=0x00400020  word=0x00500093
    addi x2,x0,7                    # PC=0x00400024  word=0x00700113
    addi x3,x0,9                    # PC=0x00400028  word=0x00900193
    addi x4,x0,11                   # PC=0x0040002c  word=0x00b00213
    addi x5,x0,13                   # PC=0x00400030  word=0x00d00293
    add x6,x5,x1                    # PC=0x00400034  word=0x00128333
    addi x7,x0,21                   # PC=0x00400038  word=0x01500393
    nop                             # PC=0x0040003c  word=0x00000013
    nop                             # PC=0x00400040  word=0x00000013
    addi x8,x7,1                    # PC=0x00400044  word=0x00138413; W-to-D write-through
    j multiply                      # PC=0x00400048  word=0x0180006f

    # NOP padding: 0x0040004c through 0x0040005c
    .rept 5
        nop
    .endr


# PIPELINED MULTIPLY
multiply:
    mul x10,x1,x2                   # PC=0x00400060  word=0x02208533
    mul x11,x3,x4                   # PC=0x00400064  word=0x024185b3
    mul x12,x5,x6                   # PC=0x00400068  word=0x02628633
    .word 0x0220868b                # PC=0x0040006c  word=0x0220868b; mulsr x13,x1,x2,1
    addi x14,x13,1                  # PC=0x00400070  word=0x00168713; multiply-use stall
    j fixed_point                   # PC=0x00400074  word=0x02c0006f

    # NOP padding: 0x00400078 through 0x0040009c
    .rept 10
        nop
    .endr


# MULSR / SIGNED AND UNSIGNED
fixed_point:
    addi x15,x0,-7                  # PC=0x004000a0  word=0xff900793
    addi x16,x0,5                   # PC=0x004000a4  word=0x00500813
    .word 0x0307888b                # PC=0x004000a8  word=0x0307888b; mulsr x17,x15,x16,1
    mul x7,x15,x16                  # PC=0x004000ac  word=0x030783b3
    mulh x8,x15,x16                 # PC=0x004000b0  word=0x03079433
    srli x7,x7,1                    # PC=0x004000b4  word=0x0013d393
    slli x8,x8,31                   # PC=0x004000b8  word=0x01f41413
    or x9,x7,x8                     # PC=0x004000bc  word=0x0083e4b3; same signed shifted product
    mulh x25,x15,x16                # PC=0x004000c0  word=0x03079cb3
    mulhu x26,x15,x16               # PC=0x004000c4  word=0x0307bd33
    .word 0x0107838b                # PC=0x004000c8  word=0x0107838b; mulsr x7,x15,x16,0
    .word 0x3f07840b                # PC=0x004000cc  word=0x3f07840b; mulsr x8,x15,x16,31
    j memory                        # PC=0x004000d0  word=0x0300006f

    # NOP padding: 0x004000d4 through 0x004000fc
    .rept 11
        nop
    .endr


# BYTE/HALFWORD / LOAD-USE
memory:
    addi x18,x0,128                 # PC=0x00400100  word=0x08000913
    sb x18,0(x0)                    # PC=0x00400104  word=0x01200023
    addi x18,x0,129                 # PC=0x00400108  word=0x08100913
    sb x18,1(x0)                    # PC=0x0040010c  word=0x012000a3
    addi x18,x0,130                 # PC=0x00400110  word=0x08200913
    sb x18,2(x0)                    # PC=0x00400114  word=0x01200123
    addi x18,x0,131                 # PC=0x00400118  word=0x08300913
    sb x18,3(x0)                    # PC=0x0040011c  word=0x012001a3
    addi x18,x0,-275                # PC=0x00400120  word=0xeed00913; 0xfffffeed
    sh x18,0(x0)                    # PC=0x00400124  word=0x01201023
    lui x3,0x8                      # PC=0x00400128  word=0x000081b7; temporary 0x8000
    addi x3,x3,1                    # PC=0x0040012c  word=0x00118193
    sh x3,2(x0)                     # PC=0x00400130  word=0x00301123
    lb x18,0(x0)                    # PC=0x00400134  word=0x00000903
    sw x18,4(x0)                    # PC=0x00400138  word=0x01202223; captures signed byte
    lbu x18,0(x0)                   # PC=0x0040013c  word=0x00004903
    sw x18,8(x0)                    # PC=0x00400140  word=0x01202423
    lh x18,0(x0)                    # PC=0x00400144  word=0x00001903
    sw x18,12(x0)                   # PC=0x00400148  word=0x01202623
    lhu x18,0(x0)                   # PC=0x0040014c  word=0x00005903
    sw x18,16(x0)                   # PC=0x00400150  word=0x01202823
    lw x18,0(x0)                    # PC=0x00400154  word=0x00002903
    addi x19,x18,1                  # PC=0x00400158  word=0x00190993; load-use
    j branch_test                   # PC=0x0040015c  word=0x0240006f

    # NOP padding: 0x00400160 through 0x0040017c
    .rept 8
        nop
    .endr


# BRANCH PREDICTION
branch_test:
    addi x20,x0,0                   # PC=0x00400180  word=0x00000a13
    addi x21,x0,8                   # PC=0x00400184  word=0x00800a93
loop:
    addi x20,x20,1                  # PC=0x00400188  word=0x001a0a13
    blt x20,x21,loop                # PC=0x0040018c  word=0xff5a4ee3; T T T T T T T N
    j branch_done                   # PC=0x00400190  word=0x00c0006f
    addi x27,x0,99                  # PC=0x00400194  word=0x06300d93; WRONG PATH: must not commit
    sw x1,20(x0)                    # PC=0x00400198  word=0x00102a23; WRONG PATH: must not commit
branch_done:
    addi x22,x0,42                  # PC=0x0040019c  word=0x02a00b13
    j interrupt_test                # PC=0x004001a0  word=0x0600006f

    # NOP padding: 0x004001a4 through 0x004001fc
    .rept 23
        nop
    .endr


# INTERRUPT / PRECISE RETURN
interrupt_test:
    addi x23,x0,0                   # PC=0x00400200  word=0x00000b93
    addi x24,x0,6                   # PC=0x00400204  word=0x00600c13
resume_loop:
    addi x23,x23,1                  # PC=0x00400208  word=0x001b8b93
    nop                             # PC=0x0040020c  word=0x00000013; IRQ asserted when this reaches D
    nop                             # PC=0x00400210  word=0x00000013
    blt x23,x24,resume_loop         # PC=0x00400214  word=0xff8bcae3
    j finish                        # PC=0x00400218  word=0x0480006f

    # NOP padding: 0x0040021c through 0x0040025c
    .rept 17
        nop
    .endr


# MCYCLE RETAINED / FINISH
finish:
    div x29,x10,x2                  # PC=0x00400260  word=0x02254eb3; 35/7=5
    addi x30,x29,1                  # PC=0x00400264  word=0x001e8f13
    addi x31,x0,123                 # PC=0x00400268  word=0x07b00f93; done marker

    # NOP padding: 0x0040026c through 0x004002fc
    .rept 37
        nop
    .endr


# INTERRUPT HANDLER
isr:
    addi x28,x28,1                  # PC=0x00400300  word=0x001e0e13
    mret                            # PC=0x00400304  word=0x30200073

# All remaining ROM addresses return nop (0x00000013) from the Verilog default case.
