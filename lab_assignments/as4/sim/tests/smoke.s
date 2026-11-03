# smoke.s - a few dependent instructions, a load-use, a loop, a call, mul/div, byte stores.
    .section .text.init, "ax"
    .globl _start
_start:
    lui   x9, %hi(buf)
    addi  x9, x9, %lo(buf)
    addi  x10, x0, 5
    addi  x11, x10, 7        # forward from M
    add   x12, x11, x10      # forward from M and W
    sw    x12, 0(x9)
    lw    x13, 0(x9)
    addi  x14, x13, 1        # load-use
    addi  x15, x0, 10
    addi  x16, x0, 0
loop:
    add   x16, x16, x15
    addi  x15, x15, -1
    bnez  x15, loop          # predicted after the first iterations
    jal   x6, sub
    mul   x18, x16, x14
    div   x19, x18, x10
    rem   x20, x18, x11
    sb    x18, 5(x9)
    sh    x19, 10(x9)
    lbu   x21, 5(x9)
    lh    x22, 10(x9)
    lb    x23, 5(x9)
    lui   x7, 0xFFFF0
    sw    x16, 0x80(x7)      # 7-segment
    sb    x21, 0x60(x7)      # LEDs
end:
    j     end
sub:
    addi  x17, x16, 100
    jalr  x0, 0(x6)

    .data
buf: .space 64
