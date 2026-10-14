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
#--	Changes: replaced the sample DIP-to-LED loop with a program that exercises every
#--	         Assignment 2 instruction (Task 1 and Task 2), and records 16 intermediate
#--	         values in a trace table that can be compared with RARS one by one.
#----------------------------------------------------------------------------------

# Assignment 2 demo program for RARS (Settings > Memory Configuration > Default).
#
# Switches:
#   SW11-SW0  : the input number (12 bits)
#   SW15-SW12 : which trace entry to show on the 7-segment display (0-F, see the table below)
#
# What it does, forever (until a push button is pressed):
#   1. reads the switches
#   2. runs 4 test cases from a table in data memory through every DP register-type
#      instruction and all 6 conditional branches
#   3. calls a function twice (once with jal, once with jalr) that uses every DP immediate instruction
#   4. writes 16 intermediate values to the 'trace' table in data memory (sw)
#   5. reads back the entry chosen by SW15-SW12 (lw) and shows it on the 7-segment display
#   6. shows an 8-bit summary of all 24 branch outcomes on LED[7:0]
#   7. any push button (BTNL / BTNC / BTNR) ends the program at 'halt'
#
# The trace table (in RARS: Data Segment window, addresses 0x10010020 - 0x1001005C):
#   SW15-12  address      contents
#   0        0x10010020   final checksum
#   1        0x10010024   the input number used (SW11-SW0)
#   2        0x10010028   checksum after test case 1
#   3        0x1001002C   checksum after test case 2
#   4        0x10010030   checksum after test case 3
#   5        0x10010034   checksum after test case 4
#   6        0x10010038   branch signature (6 bits per case, one per branch)
#   7        0x1001003C   LED value (the branch signature folded to 8 bits)
#   8        0x10010040   mix(checksum), the function called with jal
#   9        0x10010044   mix(signature), the function called with jalr
#   A        0x10010048   return address saved by jal
#   B        0x1001004C   return address saved by jalr
#   C        0x10010050   address of the test-case table, computed with auipc + addi
#   D        0x10010054   MMIO base address, loaded with lui (+ addi 0)
#   E        0x10010058   (case 2 'a') >> 4 using sra  - sign bits copied in
#   F        0x1001005C   (case 2 'a') >> 4 using srl  - zeros shifted in
#
# Outputs to expect from a correct CPU:
#   LED[7:0]  : always 0x65 (0110 0101) - the branch outcomes do not depend on the switches
#   7-segment : trace[SW15-12], identical to the same word in RARS for the same SW11-SW0.
#               With all switches down it shows the final checksum 0x0717E0E2.
# If any single instruction misbehaves, the LEDs or at least one trace entry change.
#
# Every instruction is reached: each conditional branch is taken in some test cases and not taken in
# others (no dead code), and the result of every instruction is used later.
# All registers are written before they are read (on the FPGA, only x0 starts at 0).

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

# ------- <code memory (Instruction Memory ROM) begins>
.text	## IROM segment: IROM_BASE to IROM_BASE+2^IROM_DEPTH_BITS-1
# Total number of real instructions should not exceed 2^IROM_DEPTH_BITS/4 (127 excluding the last line 'halt B halt' if IROM_DEPTH_BITS=9).
# Pseudoinstructions (e.g., li, la) may be implemented using more than one actual instruction. See the assembled code in the Execute tab of RARS.
# This program assembles to 105 real instructions.

# Register use:
#   s0 = MMIO base address       s1 = input number (SW11-0)     s2 = pointer into the test-case table
#   s3 = test cases left         s4 = data checksum             s5 = branch signature
#   s6 = address of 'trace'      s7 = trace entry to display    s8 = pointer to the next per-case trace slot
#   a0, a1 = operands / function argument and result            t0-t6 = temporaries, ra = return address

main:
	li   s0, MMIO_BASE		# lui + addi (lui)

loop:
	lw   s1, DIP_OFF(s0)		# all 16 switches (lw from MMIO)
	srli s7, s1, 12			# SW15-SW12: which trace entry to display
	slli s1, s1, 20			# keep only SW11-SW0 as the input number:
	srli s1, s1, 20			#   shift the top bits out, then back
	la   s6, trace			# auipc + addi: address of the trace table
	la   s2, cases			# auipc + addi: address of the test-case table (auipc)
	sw   s0, 52(s6)			# trace[D] = MMIO base (made by lui)
	sw   s2, 48(s6)			# trace[C] = table address (made by auipc)
	sw   s1, 4(s6)			# trace[1] = input number
	addi s8, s6, 8			# per-case slots start at trace[2]
	addi s3, zero, 4		# 4 test cases. Also used as the shift amount below (4, 3, 2, 1)
	addi s4, s1, 0			# checksum starts from the input number
	addi s5, zero, 0		# branch signature starts empty

case_loop:
	lw   a0, 0(s2)			# a  (lw from DMEM)
	lw   a1, 4(s2)			# b
	xor  a0, a0, s1			# mix the input into the low bits of a and b.
	xor  a1, a1, s1			# The upper 16 bits of each pair decide every comparison, so the
					# branch outcomes below are the same for any input.

	# ---- DP register-type instructions; each result goes into the checksum
	add  t0, a0, a1
	add  s4, s4, t0
	sub  t0, a0, a1
	xor  s4, s4, t0
	and  t0, a0, a1
	add  s4, s4, t0
	or   t0, a0, a1
	xor  s4, s4, t0
	sll  t0, a0, s3			# shift amount comes from a register (4, 3, 2, 1)
	add  s4, s4, t0
	srl  t0, a0, s3			# case 2 has a negative a, so srl and sra give different results
	xor  s4, s4, t0
	sra  t0, a0, s3
	add  s4, s4, t0
	slt  t0, a0, a1			# signed compare: 1 only in case 2
	xor  s4, s4, t0
	sltu t0, a0, a1			# unsigned compare: 1 only in case 4
	add  s4, s4, t0

	# ---- conditional branches: 6 bits per case in s5, a bit is added when its branch is NOT taken
	slli s5, s5, 6			# make room for this case's 6 bits
	beq  a0, a1, after_beq
	addi s5, s5, 1			# beq not taken  (cases 1, 2, 4)
after_beq:
	bne  a0, a1, after_bne
	addi s5, s5, 2			# bne not taken  (case 3)
after_bne:
	blt  a0, a1, after_blt
	addi s5, s5, 4			# blt not taken  (cases 1, 3, 4)
after_blt:
	bge  a0, a1, after_bge
	addi s5, s5, 8			# bge not taken  (case 2)
after_bge:
	bltu a0, a1, after_bltu
	addi s5, s5, 16			# bltu not taken (cases 1, 2, 3)
after_bltu:
	bgeu a0, a1, after_bgeu
	addi s5, s5, 32			# bgeu not taken (case 4)
after_bgeu:

	sw   s4, 0(s8)			# trace[2..5] = checksum after this case
	addi s8, s8, 4
	addi s2, s2, 8			# next pair in the table
	addi s3, s3, -1
	bne  s3, zero, case_loop	# taken 3 times, not taken once

	# ---- LEDs: fold the 24-bit branch signature to 8 bits: sig[7:0] ^ sig[15:8] ^ sig[23:16]
	sw   s5, 24(s6)			# trace[6] = branch signature
	srli t0, s5, 8
	srli t1, s5, 16
	xor  t0, t0, t1
	xor  t0, t0, s5
	sw   t0, LED_OFF(s0)		# LED[7:0] = 0x65 for a correct CPU (sw to MMIO)
	sw   t0, 28(s6)			# trace[7] = the same value (all 32 bits)

	# ---- function calls: jal and jalr, both with linking (ra = PC + 4)
	addi a0, s4, 0			# argument: the checksum
	jal  ra, mix
	sw   a0, 32(s6)			# trace[8] = mix(checksum)
	sw   ra, 40(s6)			# trace[A] = return address saved by jal
	add  s4, s4, a0
	la   t6, mix			# auipc + addi: address of mix
	addi a0, s5, 0			# argument: the branch signature
	jalr ra, t6, 0			# call through a register
	sw   a0, 36(s6)			# trace[9] = mix(signature)
	sw   ra, 44(s6)			# trace[B] = return address saved by jalr
	xor  s4, s4, a0

	# ---- shifts side by side: case 2's 'a' is negative
	lw   t1, -24(s2)		# s2 is now 32 bytes past 'cases'; case 2's a is at cases + 8 (negative offset)
	xor  t1, t1, s1			# same mixing as in the loop
	srai t3, t1, 4			# arithmetic shift: copies the sign bit into the top
	srli t4, t1, 4			# logical shift: shifts zeros into the top
	sw   t3, 56(s6)			# trace[E]
	sw   t4, 60(s6)			# trace[F]

	# ---- final checksum to memory, then display the entry chosen by SW15-12 (read back with lw)
	sw   s4, 0(s6)			# trace[0] = final checksum (sw to DMEM)
	slli t0, s7, 2			# entry number * 4 = byte offset
	add  t0, t0, s6
	lw   t0, 0(t0)			# trace[SW15-12]; if a sw had not worked, the old value would show
	sw   t0, SEVENSEG_OFF(s0)	# 7-segment display

	# ---- keep running until a push button is pressed
	lw   t0, PB_OFF(s0)		# PB[2:0] = BTNL, BTNC, BTNR
	bne  t0, zero, halt
	j    loop			# jal zero, loop

mix:	# a0 = mix(a0). Uses every DP immediate-type instruction. Leaf function, so ra is preserved.
	slti  t3, a0, -5		# signed:   a0 < -5 ?
	sltiu t4, a0, -5		# unsigned: a0 < 0xFFFFFFFB ?  (differs from slti for positive a0)
	addi  a0, a0, -1024		# these 4 immediates have instruction bit 30 set, which must NOT
	xori  a0, a0, -603		#   turn them into sub / sra. xori with a negative immediate also
	ori   a0, a0, 0x4F0		#   flips the sign, so the shifts below see a negative number
	andi  a0, a0, -3		#   for the second call.
	slli  t0, a0, 7
	srli  t1, a0, 9
	srai  t2, a0, 11		# differs from srli when a0 is negative
	xor   a0, t0, t1
	add   a0, a0, t2
	add   a0, a0, t3
	xor   a0, a0, t4
	ret				# jalr zero, ra, 0

halt:
	j halt		# infinite loop to halt computation. A program should not "terminate" without an operating system to return control to
			# keep halt: j halt as the last line of your code so that there is a 'dead end' beyond which execution will not proceed.

# ------- <code memory (Instruction Memory ROM) ends>


#------- <Data Memory begins>
.data  ## DMEM segment: DMEM_BASE to DMEM_BASE+2^DMEM_DEPTH_BITS-1
# Total number of constants+variables should not exceed 2^DMEM_DEPTH_BITS/4 (128 if DMEM_DEPTH_BITS=9).

DMEM:

cases:	# 0x10010000: test pairs (a, b). Only the upper 16 bits decide the comparisons (the input only changes the lower 12).
	.word 0x00050000, 0x00030000	# case 1: a > b, signed and unsigned
	.word 0x80010000, 0x7FFF0000	# case 2: signed a < b (a - b overflows, so this needs V); unsigned a > b
	.word 0x12340000, 0x12340000	# case 3: a == b
	.word 0x00070000, 0xFFF90000	# case 4: signed a > b; unsigned a < b (b is negative)

trace:	# 0x10010020: 16 words written by the program every pass (see the table at the top). Start as 0.
	.word 0, 0, 0, 0, 0, 0, 0, 0
	.word 0, 0, 0, 0, 0, 0, 0, 0

# No stack is used: mix is a leaf function, so sp is never needed.
#------- <Data Memory ends>
