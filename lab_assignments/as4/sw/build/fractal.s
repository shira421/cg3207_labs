	.file	"fractal.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.globl	isr
	.type	isr, @function
isr:
	addi	sp,sp,-16
	sw	a5,4(sp)
	li	a5,-65536
	sw	a3,12(sp)
	lw	a3,120(a5)
	sw	a4,8(sp)
	andi	a5,a3,2
	beq	a5,zero,.L2
	lui	a5,%hi(.LANCHOR0)
	addi	a4,a5,%lo(.LANCHOR0)
	lw	a4,0(a4)
	addi	a5,a5,%lo(.LANCHOR0)
	bne	a4,zero,.L3
	lui	a4,%hi(.LANCHOR1)
	lw	a4,%lo(.LANCHOR1)(a4)
	sw	a4,4(a5)
	lw	a4,12(a5)
	sw	a4,8(a5)
.L3:
	lw	a4,0(a5)
	seqz	a4,a4
	sw	a4,0(a5)
.L2:
	li	a5,-65536
	sw	a3,120(a5)
	lw	a4,8(sp)
	lw	a3,12(sp)
	lw	a5,4(sp)
	addi	sp,sp,16
	mret
	.size	isr, .-isr
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-96
	sw	ra,92(sp)
	sw	s0,88(sp)
	sw	s1,84(sp)
	sw	s2,80(sp)
	sw	s3,76(sp)
	sw	s4,72(sp)
	sw	s5,68(sp)
	sw	s6,64(sp)
	sw	s7,60(sp)
	sw	s8,56(sp)
	sw	s9,52(sp)
	sw	s10,48(sp)
	sw	s11,44(sp)
	li	a5,-65536
	li	a4,1
	sw	a4,96(a5)
	li	a5,-65536
	li	a4,20
	sw	a4,44(a5)
	li	a5,-65536
	sh	zero,40(a5)
	li	a4,2
	li	a5,-65536
	sw	a4,116(a5)
	li	a5,-65536
	lw	a3,64(a5)
	lui	a5,%hi(.LANCHOR0)
	addi	a4,a5,%lo(.LANCHOR0)
	sw	a3,16(a4)
	li	a4,-65536
	addi	a4,a4,100
	sw	a4,12(sp)
	li	a4,-65536
	addi	a4,a4,112
	sw	a4,16(sp)
	li	a4,-65536
	addi	a4,a4,104
	sw	a4,20(sp)
	li	a4,-65536
	addi	a4,a4,32
	sw	a4,24(sp)
	li	a4,-65536
	lui	a3,%hi(.LANCHOR1)
	addi	a4,a4,36
	lui	t3,%hi(.LANCHOR2)
	li	a7,0
	addi	a5,a5,%lo(.LANCHOR0)
	li	t1,6
	addi	a3,a3,%lo(.LANCHOR1)
	sw	a4,28(sp)
	addi	t3,t3,%lo(.LANCHOR2)
	li	ra,134217728
.L60:
	lw	a4,12(sp)
	lw	a2,16(sp)
	lw	a1,0(a4)
	andi	a4,a1,7
	sw	a4,0(a2)
	lw	a4,20(sp)
	lw	a6,16(a5)
	lw	a0,0(a4)
	li	a4,-65536
	lw	a2,64(a4)
	srli	t4,a6,16
	slli	t4,t4,24
	srli	a4,a2,16
	slli	a4,a4,24
	srai	a4,a4,24
	srai	t4,t4,24
	sub	a4,a4,t4
	ble	a4,t1,.L9
	addi	a4,a4,-6
.L10:
	srli	a2,a2,8
	srli	a6,a6,8
	slli	a2,a2,24
	slli	a6,a6,24
	srai	a2,a2,24
	srai	a6,a6,24
	sub	a2,a2,a6
	ble	a2,t1,.L12
	addi	a2,a2,-6
.L13:
	slli	a6,a1,19
	bge	a6,zero,.L15
	neg	a4,a4
.L15:
	slli	a6,a1,18
	bge	a6,zero,.L16
	neg	a2,a2
.L16:
	lw	t4,0(a5)
	lui	a6,%hi(.LANCHOR1+8)
	addi	a6,a6,%lo(.LANCHOR1+8)
	beq	t4,zero,.L17
	addi	a6,a3,4
.L17:
	lw	t4,0(a5)
	beq	t4,zero,.L18
	lw	t4,4(a5)
	slli	a2,a2,10
	slli	a4,a4,10
	sub	a2,t4,a2
	sw	a2,4(a5)
	lw	a2,8(a5)
	add	a4,a4,a2
	sw	a4,8(a5)
.L19:
	andi	a4,a0,1
	beq	a4,zero,.L23
	lw	a4,0(a6)
	li	a2,64
	ble	a4,a2,.L23
	srai	a2,a4,4
	sub	a4,a4,a2
	sw	a4,0(a6)
.L23:
	andi	a0,a0,4
	beq	a0,zero,.L24
	lw	a2,0(a6)
	li	a4,1396736
	addi	a4,a4,1364
	bgt	a2,a4,.L24
	srai	a4,a2,4
	addi	a4,a4,1
	add	a4,a4,a2
	sw	a4,0(a6)
.L24:
	li	a4,-65536
	addi	a4,a4,160
	lw	a4,0(a4)
	li	a0,95
	andi	a2,a1,240
	sw	a4,4(sp)
	lw	a4,24(sp)
	addi	a2,a2,32
	sw	a0,0(a4)
	lw	a4,28(sp)
	li	a0,63
	sw	a0,0(a4)
	lw	s1,0(a5)
	andi	a0,a1,8
	beq	a0,zero,.L25
	beq	s1,zero,.L26
	lw	t2,4(a3)
	li	a0,0
.L27:
	li	a4,-48
	mul	a4,t2,a4
	li	t5,0
	add	a4,a4,a0
	sw	a4,8(sp)
	bne	s1,zero,.L28
	lw	t5,12(a5)
.L28:
	lw	a0,20(a5)
	slli	a4,t2,5
	sub	t5,t5,a4
	andi	a4,a0,63
	slli	a4,a4,2
	add	a4,t3,a4
	lw	t4,0(a4)
	lw	a6,4(a5)
	li	s2,-65536
	slli	s9,a0,1
	add	s11,t4,a6
	lw	a6,256(a4)
	lw	a4,8(a5)
	li	a0,0
	li	t6,0
	add	s10,a6,a4
	addi	s2,s2,40
	li	s8,96
	li	s7,64
.L29:
	lw	s0,8(sp)
	li	t0,0
	addi	s6,t6,-29
.L38:
	mv	a4,a2
	beq	s1,zero,.L63
	mv	a6,t5
	mv	s3,s0
.L32:
	mul	t4,s3,s3
	mulh	s4,s3,s3
	srli	t4,t4,25
	slli	s4,s4,7
	mulh	s5,a6,a6
	or	t4,s4,t4
	mul	s4,a6,a6
	slli	s5,s5,7
	srli	s4,s4,25
	or	s4,s5,s4
	mul	s5,s3,a6
	mulh	a6,s3,a6
	srli	s5,s5,24
	slli	a6,a6,8
	or	s5,a6,s5
	add	a6,t4,s4
	bgeu	a6,ra,.L34
	sub	t4,t4,s4
	addi	a4,a4,-1
	add	s3,t4,s11
	add	a6,s10,s5
	bne	a4,zero,.L32
.L34:
	sub	a4,a2,a4
	add	a0,a0,a4
	li	a6,0
	beq	a2,a4,.L35
	slli	a4,a4,2
	add	a4,a4,s9
	andi	a4,a4,63
	slli	a4,a4,1
	add	a4,t3,a4
	lhu	a6,512(a4)
.L35:
	bne	s1,zero,.L36
	li	a4,48
	bne	t0,a4,.L37
	bgtu	s6,t1,.L36
.L66:
	li	a6,65536
	addi	a6,a6,-1
	j	.L36
.L9:
	li	t4,-6
	ble	a4,t4,.L11
	li	a4,-6
.L11:
	addi	a4,a4,6
	j	.L10
.L12:
	li	a6,-6
	ble	a2,a6,.L14
	li	a2,-6
.L14:
	addi	a2,a2,6
	j	.L13
.L18:
	lw	t5,0(a6)
	lw	t4,0(a3)
	srai	t5,t5,3
	mul	a2,a2,t5
	mul	a4,a4,t5
	sub	a2,t4,a2
	lw	t4,12(a5)
	sw	a2,0(a3)
	add	a4,a4,t4
	sw	a4,12(a5)
	li	t4,50331648
	ble	a2,t4,.L20
.L101:
	sw	t4,0(a3)
	j	.L21
.L20:
	li	t4,-83886080
	blt	a2,t4,.L101
.L21:
	li	a2,50331648
	ble	a4,a2,.L22
.L102:
	sw	a2,12(a5)
	j	.L19
.L22:
	li	a2,-50331648
	blt	a4,a2,.L102
	j	.L19
.L26:
	lw	t2,8(a3)
	lw	a0,0(a3)
	j	.L27
.L63:
	li	a6,0
	li	s3,0
.L30:
	mul	t4,s3,s3
	mulh	s4,s3,s3
	srli	t4,t4,25
	slli	s4,s4,7
	mulh	s5,a6,a6
	or	t4,s4,t4
	mul	s4,a6,a6
	slli	s5,s5,7
	srli	s4,s4,25
	or	s4,s5,s4
	mul	s5,s3,a6
	mulh	a6,s3,a6
	srli	s5,s5,24
	slli	a6,a6,8
	or	s5,a6,s5
	add	a6,t4,s4
	bgeu	a6,ra,.L34
	sub	t4,t4,s4
	addi	a4,a4,-1
	add	s3,t4,s0
	add	a6,s5,t5
	bne	a4,zero,.L30
	j	.L34
.L37:
	li	a4,32
	bne	t6,a4,.L36
	addi	a4,t0,-45
	bleu	a4,t1,.L66
.L36:
	sh	a6,0(s2)
	addi	t0,t0,1
	add	s0,s0,t2
	bne	t0,s8,.L38
	addi	t6,t6,1
	add	t5,t5,t2
	bne	t6,s7,.L29
.L39:
	li	a4,-65536
	sw	a0,24(a5)
	addi	a4,a4,160
	lw	a4,0(a4)
	lw	a2,4(sp)
	sub	a4,a4,a2
	bne	a7,zero,.L53
	li	a2,-65536
	li	a0,3
	sw	a0,96(a2)
.L53:
	li	a2,-65536
	li	a0,8
	sw	a0,44(a2)
	slli	a2,a1,16
	bge	a2,zero,.L54
	lw	a2,24(a5)
	bne	a2,zero,.L55
	li	a2,1
.L55:
	divu	a4,a4,a2
.L54:
	li	a0,0
	li	a2,0
	li	t4,10
.L56:
	remu	a6,a4,t4
	sll	a6,a6,a2
	or	a0,a0,a6
	addi	a2,a2,4
	li	a6,32
	divu	a4,a4,t4
	bne	a2,a6,.L56
	li	a4,-65536
	li	a2,-65536
	sw	a0,128(a4)
	addi	a2,a2,48
.L58:
	lw	a4,0(a2)
	andi	a4,a4,1
	bne	a4,zero,.L58
	bne	a7,zero,.L59
	li	a4,-65536
	addi	a4,a4,64
	lw	a4,0(a4)
	sw	a4,16(a5)
.L59:
	lw	a4,20(a5)
	addi	a7,a7,1
	andi	a1,a1,15
	addi	a4,a4,1
	sw	a4,20(a5)
	lw	a4,0(a5)
	slli	a2,a7,6
	andi	a2,a2,64
	snez	a4,a4
	slli	a4,a4,7
	or	a4,a4,a1
	or	a4,a4,a2
	addi	a2,a7,-1
	seqz	a2,a2
	slli	a2,a2,2
	or	a4,a4,a2
	li	a2,-65536
	sw	a4,96(a2)
	j	.L60
.L25:
	beq	s1,zero,.L40
	lw	t2,4(a3)
	li	a4,0
.L41:
	li	t0,-48
	mul	t0,t2,t0
	li	a6,0
	add	t0,t0,a4
	bne	s1,zero,.L42
	lw	a6,12(a5)
.L42:
	lw	s2,20(a5)
	slli	a4,t2,5
	sub	a6,a6,a4
	andi	a4,s2,63
	slli	a4,a4,2
	add	a4,t3,a4
	lw	s5,0(a4)
	lw	s6,256(a4)
	lw	t4,4(a5)
	lw	a4,8(a5)
	li	s7,-65536
	add	s5,s5,t4
	add	s6,s6,a4
	slli	s2,s2,1
	li	t5,0
	addi	s7,s7,40
	li	s9,96
	li	s10,64
.L43:
	mv	s0,t0
	li	t6,0
	addi	s8,t5,-29
.L52:
	mv	a4,a2
	beq	s1,zero,.L68
	mv	t4,a6
	mv	s3,s0
.L46:
 #APP
# 103 "demo/fractal.c" 1
	.insn r 0x0b, 0, 25, s11, t4, t4
# 0 "" 2
# 103 "demo/fractal.c" 1
	.insn r 0x0b, 0, 25, s4, s3, s3
# 0 "" 2
# 103 "demo/fractal.c" 1
	.insn r 0x0b, 0, 24, t4, s3, t4
# 0 "" 2
 #NO_APP
	add	s3,s4,s11
	bgeu	s3,ra,.L48
	sub	s4,s4,s11
	addi	a4,a4,-1
	add	s3,s4,s5
	add	t4,s6,t4
	bne	a4,zero,.L46
.L48:
	sub	a4,a2,a4
	add	a0,a0,a4
	li	t4,0
	beq	a2,a4,.L49
	slli	a4,a4,2
	add	a4,a4,s2
	andi	a4,a4,63
	slli	a4,a4,1
	add	a4,t3,a4
	lhu	t4,512(a4)
.L49:
	bne	s1,zero,.L50
	li	a4,48
	bne	t6,a4,.L51
	bgtu	s8,t1,.L50
.L71:
	li	t4,65536
	addi	t4,t4,-1
	j	.L50
.L40:
	lw	t2,8(a3)
	lw	a4,0(a3)
	j	.L41
.L68:
	li	t4,0
	li	s3,0
.L44:
 #APP
# 103 "demo/fractal.c" 1
	.insn r 0x0b, 0, 25, s11, t4, t4
# 0 "" 2
# 103 "demo/fractal.c" 1
	.insn r 0x0b, 0, 25, s4, s3, s3
# 0 "" 2
# 103 "demo/fractal.c" 1
	.insn r 0x0b, 0, 24, t4, s3, t4
# 0 "" 2
 #NO_APP
	add	s3,s4,s11
	bgeu	s3,ra,.L48
	sub	s4,s4,s11
	addi	a4,a4,-1
	add	s3,s4,s0
	add	t4,t4,a6
	bne	a4,zero,.L44
	j	.L48
.L51:
	li	a4,32
	bne	t5,a4,.L50
	addi	a4,t6,-45
	bleu	a4,t1,.L71
.L50:
	sh	t4,0(s7)
	addi	t6,t6,1
	add	s0,s0,t2
	bne	t6,s9,.L52
	addi	t5,t5,1
	add	a6,a6,t2
	bne	t5,s10,.L43
	j	.L39
	.size	main, .-main
	.section	.rodata
	.align	2
	.set	.LANCHOR2,. + 0
	.type	orbit_x, @object
	.size	orbit_x, 256
orbit_x:
	.word	738198
	.word	734643
	.word	724013
	.word	706411
	.word	682006
	.word	651032
	.word	613789
	.word	570634
	.word	521984
	.word	468308
	.word	410121
	.word	347984
	.word	282496
	.word	214287
	.word	144015
	.word	72356
	.word	0
	.word	-72356
	.word	-144015
	.word	-214287
	.word	-282496
	.word	-347984
	.word	-410121
	.word	-468308
	.word	-521984
	.word	-570634
	.word	-613789
	.word	-651032
	.word	-682006
	.word	-706411
	.word	-724013
	.word	-734643
	.word	-738198
	.word	-734643
	.word	-724013
	.word	-706411
	.word	-682006
	.word	-651032
	.word	-613789
	.word	-570634
	.word	-521984
	.word	-468308
	.word	-410121
	.word	-347984
	.word	-282496
	.word	-214287
	.word	-144015
	.word	-72356
	.word	0
	.word	72356
	.word	144015
	.word	214287
	.word	282496
	.word	347984
	.word	410121
	.word	468308
	.word	521984
	.word	570634
	.word	613789
	.word	651032
	.word	682006
	.word	706411
	.word	724013
	.word	734643
	.type	orbit_y, @object
	.size	orbit_y, 256
orbit_y:
	.word	0
	.word	72356
	.word	144015
	.word	214287
	.word	282496
	.word	347984
	.word	410121
	.word	468308
	.word	521984
	.word	570634
	.word	613789
	.word	651032
	.word	682006
	.word	706411
	.word	724013
	.word	734643
	.word	738198
	.word	734643
	.word	724013
	.word	706411
	.word	682006
	.word	651032
	.word	613789
	.word	570634
	.word	521984
	.word	468308
	.word	410121
	.word	347984
	.word	282496
	.word	214287
	.word	144015
	.word	72356
	.word	0
	.word	-72356
	.word	-144015
	.word	-214287
	.word	-282496
	.word	-347984
	.word	-410121
	.word	-468308
	.word	-521984
	.word	-570634
	.word	-613789
	.word	-651032
	.word	-682006
	.word	-706411
	.word	-724013
	.word	-734643
	.word	-738198
	.word	-734643
	.word	-724013
	.word	-706411
	.word	-682006
	.word	-651032
	.word	-613789
	.word	-570634
	.word	-521984
	.word	-468308
	.word	-410121
	.word	-347984
	.word	-282496
	.word	-214287
	.word	-144015
	.word	-72356
	.type	palette, @object
	.size	palette, 128
palette:
	.half	44
	.half	76
	.half	141
	.half	207
	.half	2384
	.half	2482
	.half	4660
	.half	6806
	.half	6903
	.half	6968
	.half	7001
	.half	9049
	.half	9081
	.half	11193
	.half	15354
	.half	19546
	.half	23707
	.half	27931
	.half	32124
	.half	-29220
	.half	-22947
	.half	-18754
	.half	-14562
	.half	-10402
	.half	-8289
	.half	-6177
	.half	-4097
	.half	-4097
	.half	-4097
	.half	-4131
	.half	-4165
	.half	-2183
	.half	-2250
	.half	-2317
	.half	-2385
	.half	-2484
	.half	-503
	.half	-570
	.half	-605
	.half	-671
	.half	-704
	.half	-704
	.half	-704
	.half	-768
	.half	-4960
	.half	-7104
	.half	-9280
	.half	-13504
	.half	-17760
	.half	-22016
	.half	-26240
	.half	-28416
	.half	-32608
	.half	30784
	.half	30720
	.half	28672
	.half	28672
	.half	24577
	.half	20483
	.half	16421
	.half	12327
	.half	6185
	.half	2090
	.half	44
	.data
	.align	2
	.set	.LANCHOR1,. + 0
	.type	centre_x, @object
	.size	centre_x, 4
centre_x:
	.word	-20132659
	.type	julia_step, @object
	.size	julia_step, 4
julia_step:
	.word	1118481
	.type	step, @object
	.size	step, 4
step:
	.word	1048576
	.bss
	.align	2
	.set	.LANCHOR0,. + 0
	.type	julia, @object
	.size	julia, 4
julia:
	.zero	4
	.type	jc_x, @object
	.size	jc_x, 4
jc_x:
	.zero	4
	.type	jc_y, @object
	.size	jc_y, 4
jc_y:
	.zero	4
	.type	centre_y, @object
	.size	centre_y, 4
centre_y:
	.zero	4
	.type	accel_level, @object
	.size	accel_level, 4
accel_level:
	.zero	4
	.type	phase, @object
	.size	phase, 4
phase:
	.zero	4
	.type	total_iters, @object
	.size	total_iters, 4
total_iters:
	.zero	4
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
