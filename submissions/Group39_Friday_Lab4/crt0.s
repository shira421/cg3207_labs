# CG3207 Assignment 4 start-up code.
# The first two words of IROM are fixed by the hardware:
#   0x00400000  reset: PC_INIT in RV.v
#   0x00400004  interrupt: ISR_ADDR in RV.v. The CPU jumps here with the return address in EPC;
#               the handler (a C function with __attribute__((interrupt))) ends with mret.
# .data and .bss need no copying or clearing: AA_DMEM.mem already holds their initial values.

    .section .text.init, "ax"
    .globl _start
_start:
    j       reset
    j       isr                 # interrupt vector (ISR_ADDR = PC_INIT + 4)

reset:
    la      sp, __stack_top     # stack grows down from the top of DMEM
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    call    main
hang:
    j       hang

    # Default handler if the program has none: acknowledge every button and return.
    .weak   isr
isr:
    addi    sp, sp, -8
    sw      t0, 0(sp)
    sw      t1, 4(sp)
    li      t0, 0xFFFF0078      # INT_FLAGS
    li      t1, 7
    sw      t1, 0(t0)
    lw      t1, 4(sp)
    lw      t0, 0(sp)
    addi    sp, sp, 8
    mret
