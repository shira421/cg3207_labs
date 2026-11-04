# mulsr.s - the pipelined multiplier and mulsr: back-to-back, dependent, all k, signed/unsigned,
# a Mandelbrot-style inner loop in Q4.28, and results checked by the reference model.
    .section .text.init, "ax"
    .globl _start
_start:
    lui   x9, %hi(buf)
    addi  x9, x9, %lo(buf)
    lui   x10, %hi(0x12345678)
    addi  x10, x10, %lo(0x12345678)
    lui   x11, %hi(0xFEDCBA98)
    addi  x11, x11, %lo(0xFEDCBA98)
    mul   x12, x10, x11          # back to back, independent
    mulh  x13, x10, x11
    mulhu x14, x10, x11
    .insn r 0x0b, 0, 16, x15, x10, x11    # mulsr x15, x10, x11, 16
    add   x16, x15, x14          # needs the mulsr right before: 1 stall
    .insn r 0x0b, 0, 31, x17, x16, x16
    sw    x17, 0(x9)             # store data from a multiply
    .insn r 0x0b, 0, 0, x18, x17, x10
    lw    x19, 0(x9)
    .insn r 0x0b, 0, 5, x20, x19, x18     # multiply after a load (load-use into the multiplier)
    # Q4.28 Mandelbrot iteration for c = (-0.75, 0.1), 20 iterations
    lui   x21, %hi(-201326592)
    addi  x21, x21, %lo(-201326592)        # cx = -0.75 * 2^28
    lui   x22, %hi(26843545)
    addi  x22, x22, %lo(26843545)          # cy =  0.10 * 2^28
    lui   x23, %hi(0)
    addi  x23, x23, %lo(0)                 # zx
    lui   x24, %hi(0)
    addi  x24, x24, %lo(0)                 # zy
    lui   x25, %hi(20)
    addi  x25, x25, %lo(20)                # iterations
    lui   x26, %hi(0x40000000)
    addi  x26, x26, %lo(0x40000000)        # 4.0
loop:
    .insn r 0x0b, 0, 28, x27, x23, x23    # zx^2
    .insn r 0x0b, 0, 28, x28, x24, x24    # zy^2
    .insn r 0x0b, 0, 27, x29, x23, x24    # 2 zx zy
    add   x30, x27, x28
    bgeu  x30, x26, done
    sub   x23, x27, x28
    add   x23, x23, x21
    add   x24, x29, x22
    addi  x25, x25, -1
    bnez  x25, loop
done:
    lui   x7, 0xFFFF0
    sw    x23, 0x80(x7)
end:
    j     end

    .data
buf: .space 16
