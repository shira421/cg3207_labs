	.file	"breakout.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.type	reset_bricks, @function
reset_bricks:
	lui	a4,%hi(.LANCHOR0)
	addi	a5,a4,%lo(.LANCHOR0)
	addi	a2,a5,72
	addi	a4,a4,%lo(.LANCHOR0)
	li	a1,1
	li	a0,12
.L2:
	li	a3,0
.L3:
	add	a6,a5,a3
	sb	a1,0(a6)
	addi	a3,a3,1
	bne	a3,a0,.L3
	addi	a5,a5,12
	bne	a5,a2,.L2
	li	a5,72
	sw	a5,72(a4)
	ret
	.size	reset_bricks, .-reset_bricks
	.align	2
	.type	serve, @function
serve:
	lui	a5,%hi(.LANCHOR0)
	addi	a4,a5,%lo(.LANCHOR0)
	lw	a3,80(a4)
	sw	zero,88(a4)
	sw	zero,92(a4)
	addi	a3,a3,7
	slli	a3,a3,4
	sw	a3,76(a4)
	li	a3,928
	sw	a3,84(a4)
	lw	a4,96(a4)
	addi	a5,a5,%lo(.LANCHOR0)
	li	a3,-10
	andi	a4,a4,1
	beq	a4,zero,.L7
	li	a3,10
.L7:
	lw	a4,108(a5)
	sw	a3,100(a5)
	li	a3,-2
	addi	a4,a4,7
	mul	a4,a4,a3
	sw	a4,104(a5)
	ret
	.size	serve, .-serve
	.align	2
	.type	new_game, @function
new_game:
	addi	sp,sp,-16
	lui	a5,%hi(.LANCHOR0)
	sw	ra,12(sp)
	addi	a5,a5,%lo(.LANCHOR0)
	li	a4,3
	sw	a4,112(a5)
	li	a4,40
	sw	zero,96(a5)
	sw	zero,108(a5)
	sw	zero,116(a5)
	sw	a4,80(a5)
	call	reset_bricks
	lw	ra,12(sp)
	addi	sp,sp,16
	tail	serve
	.size	new_game, .-new_game
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
	beq	a5,zero,.L13
	lui	a5,%hi(.LANCHOR0)
	addi	a5,a5,%lo(.LANCHOR0)
	lw	a4,116(a5)
	beq	a4,zero,.L14
	li	a4,1
	sw	a4,120(a5)
.L13:
	li	a5,-65536
	sw	a3,120(a5)
	lw	a4,8(sp)
	lw	a3,12(sp)
	lw	a5,4(sp)
	addi	sp,sp,16
	mret
.L14:
	lw	a4,88(a5)
	bne	a4,zero,.L15
	li	a4,1
	sw	a4,88(a5)
	j	.L13
.L15:
	lw	a4,92(a5)
	seqz	a4,a4
	sw	a4,92(a5)
	j	.L13
	.size	isr, .-isr
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-80
	sw	s0,72(sp)
	sw	s2,64(sp)
	sw	s3,60(sp)
	sw	ra,76(sp)
	sw	s1,68(sp)
	sw	s4,56(sp)
	sw	s5,52(sp)
	sw	s6,48(sp)
	sw	s7,44(sp)
	sw	s8,40(sp)
	sw	s9,36(sp)
	sw	s10,32(sp)
	sw	s11,28(sp)
	li	a5,-65536
	li	a4,20
	sw	a4,44(a5)
	li	a5,-65536
	sh	zero,40(a5)
	li	a4,2
	li	a5,-65536
	sw	a4,116(a5)
	call	new_game
	li	a5,65536
	lui	s0,%hi(.LANCHOR0)
	lui	s2,%hi(.LANCHOR1)
	addi	a5,a5,-1
	addi	s0,s0,%lo(.LANCHOR0)
	li	s3,1
	addi	s2,s2,%lo(.LANCHOR1)
	sw	a5,12(sp)
.L66:
	li	a5,-65536
	lw	s5,160(a5)
	li	a5,-65536
	lw	s1,100(a5)
	li	a5,-65536
	andi	s4,s1,3
	sw	s4,112(a5)
	lw	a5,120(s0)
	beq	a5,zero,.L21
	sw	zero,120(s0)
	call	new_game
.L21:
	li	a5,-65536
	lw	a4,104(a5)
	li	a3,16384
	and	a3,s1,a3
	lw	a5,80(s0)
	beq	a3,zero,.L22
	lw	a4,76(s0)
	li	a2,16
	div	a4,a4,a2
	addi	a2,a4,-8
	ble	a2,a5,.L23
.L114:
	addi	a5,a5,2
	j	.L115
.L23:
	addi	a4,a4,-6
	bge	a4,a5,.L24
	addi	a5,a5,-2
.L115:
	sw	a5,80(s0)
	j	.L24
.L22:
	andi	a2,a4,4
	beq	a2,zero,.L26
	addi	a5,a5,-2
	sw	a5,80(s0)
.L26:
	andi	a4,a4,1
	lw	a5,80(s0)
	bne	a4,zero,.L114
.L24:
	lw	a4,80(s0)
	bge	a4,zero,.L28
	sw	zero,80(s0)
.L29:
	lw	a5,116(s0)
	bne	a5,zero,.L31
	lw	a5,92(s0)
	bne	a5,zero,.L31
	lw	a5,88(s0)
	bne	a5,zero,.L33
	lw	a5,80(s0)
	addi	a5,a5,7
	slli	a5,a5,4
	sw	a5,76(s0)
	li	a5,928
	sw	a5,84(s0)
	beq	a3,zero,.L31
	sw	s3,88(s0)
.L31:
	lw	a4,76(s0)
	lw	a6,84(s0)
	li	a5,16
	div	a4,a4,a5
	li	a7,1
	div	a6,a6,a5
	lw	a5,88(s0)
	bne	a5,zero,.L44
	lw	a7,116(s0)
	seqz	a7,a7
.L44:
	li	a5,-65536
	li	a3,95
	sw	a3,32(a5)
	li	t3,-65536
	li	a5,-65536
	li	a3,63
	sw	a3,36(a5)
	addi	t2,a6,1
	li	a5,0
	li	t0,23
	addi	ra,a4,1
	addi	t3,t3,40
	li	s6,96
	li	s7,64
.L53:
	srai	a3,a5,3
	slli	a3,a3,1
	add	a3,s2,a3
	lhu	a1,0(a3)
	li	a2,0
	beq	a7,zero,.L45
	bgt	a6,a5,.L45
	slt	a2,t2,a5
	seqz	a2,a2
.L45:
	addi	a3,a5,-6
	bgtu	a3,t0,.L46
	andi	t1,a3,3
	li	t4,3
	li	a0,0
	beq	t1,t4,.L60
	srai	a3,a3,2
	li	a0,12
	mul	a0,a3,a0
	slli	a3,a3,1
	add	a3,s2,a3
	li	t5,65536
	li	t4,-65536
	lhu	s9,16(a3)
	li	s10,7
	li	a3,0
	addi	s11,a4,1
	addi	t5,t5,-1
	add	a0,s0,a0
	addi	t4,t4,40
	li	s8,96
.L50:
	andi	t6,a3,7
	mv	t1,a1
	beq	t6,s10,.L48
	srai	t1,a3,3
	add	t1,a0,t1
	lbu	t6,0(t1)
	mv	t1,s9
	bne	t6,zero,.L48
	mv	t1,a1
.L48:
	beq	a2,zero,.L49
	bgt	a4,a3,.L49
	blt	s11,a3,.L49
	mv	t1,t5
.L49:
	sh	t1,0(t4)
	addi	a3,a3,1
	bne	a3,s8,.L50
	addi	a5,a5,1
	j	.L53
.L28:
	li	a5,80
	ble	a4,a5,.L29
	sw	a5,80(s0)
	j	.L29
.L33:
	lw	a4,76(s0)
	lw	a2,84(s0)
	lw	a5,100(s0)
	lw	a3,104(s0)
	add	a4,a5,a4
	add	a2,a3,a2
	sw	a4,76(s0)
	sw	a2,84(s0)
	bge	a4,zero,.L34
	sw	zero,76(s0)
.L116:
	neg	a5,a5
	sw	a5,100(s0)
.L35:
	bge	a2,zero,.L36
	neg	a3,a3
	sw	zero,84(s0)
	sw	a3,104(s0)
.L36:
	lw	a2,76(s0)
	li	a5,16
	lw	s6,84(s0)
	div	a2,a2,a5
	lw	a3,104(s0)
	div	a5,s6,a5
	addi	a4,a2,1
	ble	a3,zero,.L37
	addi	a1,s6,-928
	li	a0,63
	bgtu	a1,a0,.L37
	lw	a5,80(s0)
	bgt	a5,a4,.L31
	addi	a1,a5,15
	bgt	a2,a1,.L31
	addi	a5,a5,8
	neg	a2,a3
	li	a3,2
	beq	a5,a4,.L39
	sub	a4,a4,a5
	li	a3,3
	mul	a3,a4,a3
.L39:
	li	a5,928
	sw	a2,104(s0)
	sw	a3,100(s0)
	sw	a5,84(s0)
	j	.L31
.L34:
	li	a1,1504
	ble	a4,a1,.L35
	sw	a1,76(s0)
	j	.L116
.L37:
	addi	a5,a5,-5
	li	a3,23
	bgtu	a5,a3,.L41
	srai	a3,a4,3
	srai	a5,a5,2
	li	a4,12
	mul	a4,a5,a4
	add	a4,s0,a4
	add	a4,a4,a3
	lbu	a3,0(a4)
	beq	a3,zero,.L41
	sb	zero,0(a4)
	lw	a4,104(s0)
	lw	a3,108(s0)
	lw	a2,72(s0)
	neg	a4,a4
	sw	a4,104(s0)
	li	a4,6
	sub	a5,a4,a5
	addi	a3,a3,1
	mul	a5,a5,a3
	li	a4,10
	addi	a2,a2,-1
	sw	a2,72(s0)
	mul	a5,a5,a4
	lw	a4,96(s0)
	add	a5,a5,a4
	sw	a5,96(s0)
	bne	a2,zero,.L41
	sw	a3,108(s0)
	call	reset_bricks
	call	serve
.L41:
	li	a5,1023
	ble	s6,a5,.L31
	lw	a5,112(s0)
	addi	a5,a5,-1
	sw	a5,112(s0)
	bne	a5,zero,.L43
	sw	s3,116(s0)
	j	.L31
.L43:
	call	serve
	j	.L31
.L46:
	addi	a3,a5,-60
	li	a0,0
	bgtu	a3,s3,.L60
	lw	a3,116(s0)
	li	a0,57344
	addi	a0,a0,1852
	beq	a3,zero,.L54
	li	a0,32768
	addi	a0,a0,-1073
.L54:
	lw	t6,80(s0)
	li	t5,65536
	li	t4,-65536
	addi	s8,t6,15
	li	a3,0
	addi	s9,a4,1
	addi	t5,t5,-1
	addi	t4,t4,40
	li	s10,96
.L57:
	mv	t1,a1
	bgt	t6,a3,.L55
	mv	t1,a0
	bge	s8,a3,.L55
	mv	t1,a1
.L55:
	beq	a2,zero,.L56
	bgt	a4,a3,.L56
	blt	s9,a3,.L56
	mv	t1,t5
.L56:
	sh	t1,0(t4)
	addi	a3,a3,1
	bne	a3,s10,.L57
.L58:
	addi	a5,a5,1
	bne	a5,s7,.L53
	li	a5,-65536
	addi	a5,a5,160
	lw	a5,0(a5)
	li	a4,-65536
	li	a3,8
	sub	a5,a5,s5
	sw	a5,124(s0)
	sw	a3,44(a4)
	li	a4,32768
	and	s1,s1,a4
	beq	s1,zero,.L61
	lw	a4,96(s0)
	li	s1,0
	li	a5,0
	li	a2,10
	li	a1,32
.L62:
	remu	a3,a4,a2
	sll	a3,a3,a5
	addi	a5,a5,4
	divu	a4,a4,a2
	or	s1,s1,a3
	bne	a5,a1,.L62
.L63:
	li	a5,-65536
	sw	s1,128(a5)
	lw	a5,112(s0)
	lw	a4,92(s0)
	sll	a5,s3,a5
	addi	a5,a5,-1
	slli	a5,a5,4
	snez	a4,a4
	slli	a4,a4,7
	andi	a5,a5,112
	or	a5,a5,a4
	or	a5,a5,s4
	li	a4,-65536
	sw	a5,96(a4)
	li	a4,-65536
	addi	a4,a4,48
.L65:
	lw	a5,0(a4)
	andi	a5,a5,1
	bne	a5,zero,.L65
	j	.L66
.L60:
	mv	a3,a1
	beq	a2,zero,.L59
	bgt	a4,a0,.L59
	blt	ra,a0,.L59
	lw	a3,12(sp)
.L59:
	sh	a3,0(t3)
	addi	a0,a0,1
	bne	a0,s6,.L60
	j	.L58
.L61:
	li	a4,0
	li	a2,10
	li	a1,32
.L64:
	remu	a3,a5,a2
	sll	a3,a3,a4
	addi	a4,a4,4
	divu	a5,a5,a2
	or	s1,s1,a3
	bne	a4,a1,.L64
	j	.L63
	.size	main, .-main
	.section	.rodata
	.align	2
	.set	.LANCHOR1,. + 0
	.type	bg_colour, @object
	.size	bg_colour, 16
bg_colour:
	.half	5
	.half	4
	.half	4
	.half	3
	.half	3
	.half	2
	.half	2
	.half	1
	.type	row_colour, @object
	.size	row_colour, 12
row_colour:
	.half	-1723
	.half	-928
	.half	-224
	.half	12007
	.half	11551
	.half	-21857
	.bss
	.align	2
	.set	.LANCHOR0,. + 0
	.type	bricks, @object
	.size	bricks, 72
bricks:
	.zero	72
	.type	bricks_left, @object
	.size	bricks_left, 4
bricks_left:
	.zero	4
	.type	ball_x, @object
	.size	ball_x, 4
ball_x:
	.zero	4
	.type	paddle_x, @object
	.size	paddle_x, 4
paddle_x:
	.zero	4
	.type	ball_y, @object
	.size	ball_y, 4
ball_y:
	.zero	4
	.type	launched, @object
	.size	launched, 4
launched:
	.zero	4
	.type	paused, @object
	.size	paused, 4
paused:
	.zero	4
	.type	score, @object
	.size	score, 4
score:
	.zero	4
	.type	vel_x, @object
	.size	vel_x, 4
vel_x:
	.zero	4
	.type	vel_y, @object
	.size	vel_y, 4
vel_y:
	.zero	4
	.type	level, @object
	.size	level, 4
level:
	.zero	4
	.type	lives, @object
	.size	lives, 4
lives:
	.zero	4
	.type	game_over, @object
	.size	game_over, 4
game_over:
	.zero	4
	.type	restart_req, @object
	.size	restart_req, 4
restart_req:
	.zero	4
	.type	last_frame_cycles, @object
	.size	last_frame_cycles, 4
last_frame_cycles:
	.zero	4
	.ident	"GCC: (13.2.0-11ubuntu1+12) 13.2.0"
