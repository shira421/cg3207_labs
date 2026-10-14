#----------------------------------------------------------------------------------
#-- (c) Rajesh Panicker
#--	License terms :
#--	You are free to use this code as long as you
#--		(i) DO NOT post it on any public repository;
#--		(ii) use it only for educational purposes;
#--		(iii) accept the responsibility to ensure that your implementation does not violate anyone's intellectual property.
#--		(iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
#--		(v) send an email to rajesh<dot>panicker<at>ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
#--		(vi) retain this notice in this file and any files derived from this.
#----------------------------------------------------------------------------------
#--	Changes (Assignment 3): a program that tests the RV32M instructions (mul, mulh, mulhu,
#--	         div, divu, rem, remu) on 16 corner cases against a table of expected results,
#--	         measures how many cycles mul and div take, and lets you browse every result
#--	         (or try your own operands) with the switches.
#----------------------------------------------------------------------------------

# Assignment 3 demo program for RARS (Settings > Memory Configuration > Default).
# Needs IROM_DEPTH_BITS = 10 and DMEM_DEPTH_BITS = 10 in Wrapper.v (256 words each).
#
# What it does
#   1. Self-check: for each of the 16 test cases below it runs mul, mulh, mulhu, div, divu, rem and
#      remu back to back, plus div and mul with rd = rs1 / rd = rs2, and compares every result with
#      the 'expected' table. One LED per instruction stays on only if all 16 cases are right:
#        LED0 mul   LED1 mulh   LED2 mulhu   LED3 div   LED4 divu   LED5 rem   LED6 remu
#        LED7 all of the above
#      A correct CPU shows LED[7:0] = 0xFF. (In RARS the same value is written to 'status'.)
#   2. Measures the cycles taken by one mul and one div with the cycle counter (MMIO 0xFFFF00A0).
#      Expected on the hardware: mul 18 cycles (radix-4 Booth, Task 3), div 33 cycles.
#      (RARS has no cycle counter, so both read as 0 there.)
#   3. Forever: shows a value on the 7-segment display, chosen with the switches.
#
#   SW15 = 0 : browse the test cases
#     SW3-SW0 : test case 0-F (see the 'cases' table)
#     SW7-SW4 : what to show
#        0 a (rs1)      1 b (rs2)      2 mul      3 mulh     4 mulhu     5 div      6 divu
#        7 rem          8 remu         9 cycles taken by mul               A cycles taken by div
#        B LED value (self-check flags)            C-F 0
#     The value is recomputed with the RV32M instructions every time, not read from the table.
#
#   SW15 = 1 : your own operands
#     SW14-SW8 : a, a 7-bit signed number (-64 .. 63)
#     SW6-SW0  : b, a 7-bit signed number (-64 .. 63)
#     shows a * b, or hold BTNL: a / b,  BTNC: a % b,  BTNR: a / b unsigned (divu)
#
# Every RV32I instruction type the program needs still runs on the same CPU (lw, sw, lui, auipc,
# addi, andi, ori, slli, srli, srai, add, sub, beq, bne, blt, jal).

.eqv MMIO_BASE 0xFFFF0000
# Memory-mapped peripheral register offsets
.eqv UART_RX_VALID_OFF 			0x00 #RO, status bit
.eqv UART_RX_OFF			0x04 #RO
.eqv UART_TX_READY_OFF			0x08 #RO, status bit
.eqv UART_TX_OFF			0x0C #WO
.eqv OLED_COL_OFF			0x20 #WO
.eqv OLED_ROW_OFF			0x24 #WO
.eqv OLED_DATA_OFF			0x28 #WO
.eqv OLED_CTRL_OFF			0x2C #WO
.eqv ACCEL_DATA_OFF			0x40 #RO
.eqv ACCEL_DREADY_OFF			0x44 #RO, status bit
.eqv DIP_OFF				0x64 #RO
.eqv PB_OFF				0x68 #RO
.eqv LED_OFF				0x60 #WO
.eqv SEVENSEG_OFF			0x80 #WO
.eqv CYCLECOUNT_OFF			0xA0 #RO

.eqv NCASES 16

# ------- <code memory (Instruction Memory ROM) begins>
.text	## IROM segment: IROM_BASE to IROM_BASE+2^IROM_DEPTH_BITS-1
# Pseudoinstructions (e.g., li, la) may be implemented using more than one actual instruction. See the assembled code in the Execute tab of RARS.
# This program assembles to 128 real instructions.

# Register use:
#   s0 = MMIO base address        s1 = address of 'cases'       s2 = address of 'expected'
#   s3 = self-check flags (LEDs)  s4 = cycles taken by one lw   s5 = cycles taken by mul
#   s6 = cycles taken by div      s7 = address of 'view'
#   a0, a1 = operands             a2 = pointer into 'expected'  a4 = pointer into 'cases'
#   t0-t6, a3, a5, a6 = results / temporaries

main:
	li   s0, MMIO_BASE		# lui
	la   s1, cases			# auipc + addi
	la   s2, expected
	la   s7, view

# ---- 1. Self-check all test cases ----------------------------------------------------------
	addi s3, zero, 0x7F		# one flag per instruction, cleared by any wrong result
	addi t6, zero, 0		# test case number
	addi a4, s1, 0			# -> a, b of this case
	addi a2, s2, 0			# -> the 7 expected results of this case

check_loop:
	lw   a0, 0(a4)			# a
	lw   a1, 4(a4)			# b

	# all seven RV32M instructions back to back: each one stalls the CPU until MCycle is done
	mul   t0, a0, a1
	mulh  t1, a0, a1
	mulhu t2, a0, a1
	div   t3, a0, a1
	divu  t4, a0, a1
	rem   t5, a0, a1
	remu  a5, a0, a1

	lw   a3, 0(a2)			# expected mul
	beq  t0, a3, ok_mul
	andi s3, s3, -2			# clear LED0
ok_mul:
	lw   a3, 4(a2)			# expected mulh
	beq  t1, a3, ok_mulh
	andi s3, s3, -3			# clear LED1
ok_mulh:
	lw   a3, 8(a2)			# expected mulhu
	beq  t2, a3, ok_mulhu
	andi s3, s3, -5			# clear LED2
ok_mulhu:
	lw   a3, 12(a2)			# expected div
	beq  t3, a3, ok_div
	andi s3, s3, -9			# clear LED3
ok_div:
	lw   a3, 16(a2)			# expected divu
	beq  t4, a3, ok_divu
	andi s3, s3, -17		# clear LED4
ok_divu:
	lw   a3, 20(a2)			# expected rem
	beq  t5, a3, ok_rem
	andi s3, s3, -33		# clear LED5
ok_rem:
	lw   a3, 24(a2)			# expected remu
	beq  a5, a3, ok_remu
	andi s3, s3, -65		# clear LED6
ok_remu:

	# destination register = source register: the result must only be written once MCycle is done,
	# and MCycle must keep using the operands it started with
	addi a6, a0, 0
	div  a6, a6, a1			# rd = rs1
	lw   a3, 12(a2)
	beq  a6, a3, ok_div_rs1
	andi s3, s3, -9			# clear LED3
ok_div_rs1:
	addi a6, a1, 0
	mul  a6, a0, a6			# rd = rs2
	lw   a3, 0(a2)
	beq  a6, a3, ok_mul_rs2
	andi s3, s3, -2			# clear LED0
ok_mul_rs2:

	addi a4, a4, 8			# next case
	addi a2, a2, 28
	addi t6, t6, 1
	addi a3, zero, NCASES
	blt  t6, a3, check_loop

	addi t0, zero, 0x7F
	bne  s3, t0, not_all_ok
	ori  s3, s3, 0x80		# LED7: everything right
not_all_ok:
	sw   s3, LED_OFF(s0)
	sw   s3, 64(s7)			# 'status' (right after the 16 words of 'view'), for checking in RARS

# ---- 2. Cycles taken by mul and div --------------------------------------------------------
	lw   t0, CYCLECOUNT_OFF(s0)
	lw   t1, CYCLECOUNT_OFF(s0)
	sub  s4, t1, t0			# cycles between two consecutive reads = one lw
	lw   t0, CYCLECOUNT_OFF(s0)
	mul  t2, a0, a1
	lw   t1, CYCLECOUNT_OFF(s0)
	sub  s5, t1, t0
	sub  s5, s5, s4			# cycles taken by mul
	lw   t0, CYCLECOUNT_OFF(s0)
	div  t2, a0, a1
	lw   t1, CYCLECOUNT_OFF(s0)
	sub  s6, t1, t0
	sub  s6, s6, s4			# cycles taken by div

# ---- 3. Show values chosen with the switches -----------------------------------------------
display:
	lw   t0, DIP_OFF(s0)
	srli t1, t0, 15
	bne  t1, zero, live		# SW15 = 1: your own operands

	andi t1, t0, 15			# SW3-0: test case
	srli t2, t0, 4
	andi t2, t2, 15			# SW7-4: what to show
	slli t3, t1, 3
	add  t3, s1, t3
	lw   a0, 0(t3)			# a
	lw   a1, 4(t3)			# b

	sw   a0, 0(s7)			# view[0..11] = everything that can be shown
	sw   a1, 4(s7)
	mul   t3, a0, a1
	sw    t3, 8(s7)
	mulh  t3, a0, a1
	sw    t3, 12(s7)
	mulhu t3, a0, a1
	sw    t3, 16(s7)
	div   t3, a0, a1
	sw    t3, 20(s7)
	divu  t3, a0, a1
	sw    t3, 24(s7)
	rem   t3, a0, a1
	sw    t3, 28(s7)
	remu  t3, a0, a1
	sw    t3, 32(s7)
	sw   s5, 36(s7)			# mul cycles
	sw   s6, 40(s7)			# div cycles
	sw   s3, 44(s7)			# LED value
	slli t2, t2, 2			# view[12..15] are never written, so C-F show 0
	add  t2, s7, t2
	lw   t3, 0(t2)
	jal  zero, show

live:
	slli a0, t0, 17			# SW14-8 as a signed 7-bit number
	srai a0, a0, 25
	slli a1, t0, 25			# SW6-0 as a signed 7-bit number
	srai a1, a1, 25
	lw   t1, PB_OFF(s0)		# bit 2 BTNL, bit 1 BTNC, bit 0 BTNR
	andi t2, t1, 4
	bne  t2, zero, live_div
	andi t2, t1, 2
	bne  t2, zero, live_rem
	andi t2, t1, 1
	bne  t2, zero, live_divu
	mul  t3, a0, a1
	jal  zero, show
live_div:
	div  t3, a0, a1
	jal  zero, show
live_rem:
	rem  t3, a0, a1
	jal  zero, show
live_divu:
	divu t3, a0, a1

show:
	sw   t3, SEVENSEG_OFF(s0)
	jal  zero, display
# ------- <code memory (Instruction Memory ROM) ends>


#------- <Data Memory begins>
.data  ## DMEM segment: DMEM_BASE to DMEM_BASE+2^DMEM_DEPTH_BITS-1
# Total number of constants+variables should not exceed 2^DMEM_DEPTH_BITS/4 (256 words if DMEM_DEPTH_BITS=10).

cases:		# a, b
	.word 0x00000007, 0x00000003		#  0: a = 7, b = 3
	.word 0xFFFFFFF9, 0x00000003		#  1: a = -7, b = 3
	.word 0x00000007, 0xFFFFFFFD		#  2: a = 7, b = -3
	.word 0xFFFFFFF9, 0xFFFFFFFD		#  3: a = -7, b = -3
	.word 0x80000000, 0xFFFFFFFF		#  4: a = -2147483648, b = -1
	.word 0x80000000, 0x00000001		#  5: a = -2147483648, b = 1
	.word 0x7FFFFFFF, 0x7FFFFFFF		#  6: a = 2147483647, b = 2147483647
	.word 0xFFFFFFFF, 0xFFFFFFFF		#  7: a = -1, b = -1
	.word 0x00000000, 0x00000005		#  8: a = 0, b = 5
	.word 0x00000005, 0x00000000		#  9: a = 5, b = 0
	.word 0x075BCD15, 0x000003E8		# 10: a = 123456789, b = 1000
	.word 0xF8A432EB, 0x000003E8		# 11: a = -123456789, b = 1000
	.word 0x12345678, 0x9ABCDEF0		# 12: a = 305419896, b = -1698898192
	.word 0xFFFFFFFE, 0x00000002		# 13: a = -2, b = 2
	.word 0x00000001, 0x80000000		# 14: a = 1, b = -2147483648
	.word 0xDEADBEEF, 0x00010001		# 15: a = -559038737, b = 65537
expected:	# mul, mulh, mulhu, div, divu, rem, remu  (RISC-V rules, including x/0 and min/-1)
	.word 0x00000015, 0x00000000, 0x00000000, 0x00000002, 0x00000002, 0x00000001, 0x00000001	#  0
	.word 0xFFFFFFEB, 0xFFFFFFFF, 0x00000002, 0xFFFFFFFE, 0x55555553, 0xFFFFFFFF, 0x00000000	#  1
	.word 0xFFFFFFEB, 0xFFFFFFFF, 0x00000006, 0xFFFFFFFE, 0x00000000, 0x00000001, 0x00000007	#  2
	.word 0x00000015, 0x00000000, 0xFFFFFFF6, 0x00000002, 0x00000000, 0xFFFFFFFF, 0xFFFFFFF9	#  3
	.word 0x80000000, 0x00000000, 0x7FFFFFFF, 0x80000000, 0x00000000, 0x00000000, 0x80000000	#  4
	.word 0x80000000, 0xFFFFFFFF, 0x00000000, 0x80000000, 0x80000000, 0x00000000, 0x00000000	#  5
	.word 0x00000001, 0x3FFFFFFF, 0x3FFFFFFF, 0x00000001, 0x00000001, 0x00000000, 0x00000000	#  6
	.word 0x00000001, 0x00000000, 0xFFFFFFFE, 0x00000001, 0x00000001, 0x00000000, 0x00000000	#  7
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000	#  8
	.word 0x00000000, 0x00000000, 0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 0x00000005, 0x00000005	#  9
	.word 0xBE991A08, 0x0000001C, 0x0000001C, 0x0001E240, 0x0001E240, 0x00000315, 0x00000315	# 10
	.word 0x4166E5F8, 0xFFFFFFE3, 0x000003CB, 0xFFFE1DC0, 0x003FA6F6, 0xFFFFFCEB, 0x000001FB	# 11
	.word 0x242D2080, 0xF8CC93D6, 0x0B00EA4E, 0x00000000, 0x00000000, 0x12345678, 0x12345678	# 12
	.word 0xFFFFFFFC, 0xFFFFFFFF, 0x00000001, 0xFFFFFFFF, 0x7FFFFFFF, 0x00000000, 0x00000000	# 13
	.word 0x80000000, 0xFFFFFFFF, 0x00000000, 0x00000000, 0x00000000, 0x00000001, 0x00000001	# 14
	.word 0x9D9CBEEF, 0xFFFFDEAD, 0x0000DEAE, 0xFFFFDEAE, 0x0000DEAC, 0xFFFFE041, 0x0000E043	# 15
view:		# values the 7-segment display can show (SW7-4 = 0-B), 16 words
	.word 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
status:		# the LED value, written by the self-check (look at it in RARS: 0xFF when all is right)
	.word 0
#------- <Data Memory ends>
