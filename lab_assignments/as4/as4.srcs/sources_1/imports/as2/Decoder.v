`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS
-- Engineer: (c) Rajesh Panicker
--
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: Decoder
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Decoder Module
--
-- Dependencies: NIL
--
-- Revision:
-- Revision 0.01 - File Created
-- Revision 0.02 - Assignment 2: full RV32I control (except byte/half-word load/store)
-- Revision 0.03 - Assignment 3: RV32M (mul, mulh, mulhu, div, divu, rem, remu) through the MCycle unit
-- Additional Comments: Interface and implementation can be modified.
--
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
--	License terms :
--	You are free to use this code as long as you
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept the responsibility to ensure that your implementation does not violate anyone's intellectual property.
--		(iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(v) send an email to rajesh<dot>panicker<at>ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(vi) retain this notice in this file as well as any files derived from this.
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
--	Changes: implemented the decoder as one opcode case statement; enabled ALUSrcA;
--	         widened ALUSrcB to 2 bits for the jal/jalr link value (PC + 4).
--	Assignment 3: added MStart, MCycleOp, MCycleSel and MResultSel for the RV32M instructions
--	         (opcode 0110011, funct7 0000001). mulhsu (funct3 010) is not supported and decodes as a NOP.
----------------------------------------------------------------------------------
*/

module Decoder(
    input [6:0] Opcode ,
    input [2:0] Funct3 ,
    input [6:0] Funct7 ,
    output reg [1:0] PCS,	// 00 for non-control, 01 for conditional branch, 10 for jal, 11 for jalr
    output reg RegWrite,	// Asserted only by instructions which write to register file (load, auipc, lui, DPImm, DPReg, jal, jalr);
    output reg MemWrite,	// Asserted only by store (sw)
    output reg MemtoReg,	// Asserted only by load (lw)
    output reg [1:0] ALUSrcA, 	// Src_A select: 00 RD1, 01 zero (lui), 10 PC (auipc, jal, jalr)
    output reg [1:0] ALUSrcB,	// Src_B select: 00 RD2, 01 ExtImm (load, store, lui, auipc, DPImm), 10 constant 4 (jal, jalr link)
    output reg [2:0] ImmSrc, 	// 000 for U, 010 for UJ, 011 for I, 110 for S, 111 for SB.
    output reg [3:0] ALUControl,	// 0000 for add, 0001 for sub, 1110 for and, 1100 for or, 0010 for sll, 1010 for srl, 1011 for sra, 0001 for branch, 0000 for all others.
    					// Note that the most significant 3 bits are Funct3 for all DP instrns. LSB is the same as Funct[5] for DPReg type and DPImm_shifts. For other DPImms, Funct[5] is 0.
    					// It is the same as sub for branches, and add for all others not mentioned in the line above.
    output reg MStart,		// Start the MCycle unit (multiply / divide instruction). The processor stalls while MCycle is Busy.
    output reg [1:0] MCycleOp,	// 00 signed multiply, 01 unsigned multiply, 10 signed divide, 11 unsigned divide
    output reg MCycleSel,	// Register write data comes from MCycle instead of the ALU
    output reg MResultSel,	// 0: MCycle Result1 (low word of product / quotient), 1: Result2 (high word / remainder)
    output reg Mret		// mret: return from the interrupt handler to EPC (Assignment 4)
    );
// Change wire to reg if assigned inside a procedural (always) block. However, where it is easy enough, use assign instead of always.
// A 2-1 multiplexing can be done easily using an assign with a ternary operator
// For multiplexing with number of inputs > 2, a case construct within an always block is a natural fit. DO NOT to use nested ternary assignment operator as it hampers the readability of your code.

	// Opcodes (Instr[6:0]) of the RV32I instruction groups we support
	localparam OP_DPREG  = 7'b0110011 ;	// add, sub, and, or, xor, sll, srl, sra, slt, sltu
	localparam OP_DPIMM  = 7'b0010011 ;	// addi, andi, ori, xori, slli, srli, srai, slti, sltiu
	localparam OP_LOAD   = 7'b0000011 ;	// lb, lh, lw, lbu, lhu
	localparam OP_STORE  = 7'b0100011 ;	// sb, sh, sw
	localparam OP_BRANCH = 7'b1100011 ;	// beq, bne, blt, bge, bltu, bgeu
	localparam OP_JAL    = 7'b1101111 ;	// jal
	localparam OP_JALR   = 7'b1100111 ;	// jalr
	localparam OP_LUI    = 7'b0110111 ;	// lui
	localparam OP_AUIPC  = 7'b0010111 ;	// auipc
	localparam OP_SYSTEM = 7'b1110011 ;	// mret (the only SYSTEM instruction supported)
	localparam FUNCT7_MRET = 7'b0011000 ;	// mret = 0011000 00010 00000 000 00000 1110011

	localparam FUNCT7_M  = 7'b0000001 ;	// RV32M instructions share OP_DPREG, with this funct7

	always@(*) begin
		// Defaults = a NOP. Every signal that changes processor state (RegWrite, MemWrite, PCS,
		// and MemtoReg, which drives MemRead) defaults to a definite 0, never x, so an
		// unsupported/illegal opcode cannot write a register, write memory, or jump.
		PCS        = 2'b00 ;
		RegWrite   = 1'b0 ;
		MemWrite   = 1'b0 ;
		MemtoReg   = 1'b0 ;
		ALUSrcA    = 2'b00 ;
		ALUSrcB    = 2'b00 ;
		ImmSrc     = 3'bxxx ;	// don't care unless an instruction below uses the immediate
		ALUControl = 4'b0000 ;	// add
		MStart     = 1'b0 ;
		MCycleOp   = 2'b00 ;
		MCycleSel  = 1'b0 ;
		MResultSel = 1'b0 ;
		Mret       = 1'b0 ;

		case(Opcode)
			OP_DPREG: begin
				if( Funct7 == FUNCT7_M ) begin	// RV32M: rd = rs1 op rs2, computed by MCycle over several cycles
					//                      MCycleOp           MResultSel
					case( Funct3 )
						3'b000: begin MCycleOp = 2'b00 ; MResultSel = 1'b0 ; end	// mul    low word  (same for signed / unsigned)
						3'b001: begin MCycleOp = 2'b00 ; MResultSel = 1'b1 ; end	// mulh   high word, signed x signed
						3'b011: begin MCycleOp = 2'b01 ; MResultSel = 1'b1 ; end	// mulhu  high word, unsigned x unsigned
						3'b100: begin MCycleOp = 2'b10 ; MResultSel = 1'b0 ; end	// div    quotient, signed
						3'b101: begin MCycleOp = 2'b11 ; MResultSel = 1'b0 ; end	// divu   quotient, unsigned
						3'b110: begin MCycleOp = 2'b10 ; MResultSel = 1'b1 ; end	// rem    remainder, signed
						3'b111: begin MCycleOp = 2'b11 ; MResultSel = 1'b1 ; end	// remu   remainder, unsigned
						default: ;							// mulhsu (signed x unsigned): not supported
					endcase
					if( Funct3 != 3'b010 ) begin	// mulhsu stays a NOP
						RegWrite  = 1'b1 ;	// RV.v only lets the write through once MCycle is no longer Busy
						MStart    = 1'b1 ;
						MCycleSel = 1'b1 ;
					end
				end
				else begin			// rd = rs1 op rs2
					RegWrite   = 1'b1 ;
					ALUControl = {Funct3, Funct7[5]} ;	// Funct7[5] picks sub over add, sra over srl
				end
			end
			OP_DPIMM: begin		// rd = rs1 op imm
				RegWrite   = 1'b1 ;
				ALUSrcB    = 2'b01 ;
				ImmSrc     = 3'b011 ;			// I-type
				// Funct7[5] (instruction bit 30) is only an opcode bit for the shifts (Funct3 = 001 / 101).
				// For addi, xori, ... bit 30 is part of the immediate, so it must not turn addi into sub.
				ALUControl = {Funct3, (Funct3[1:0] == 2'b01) ? Funct7[5] : 1'b0} ;
			end
			OP_LOAD: begin		// rd = mem[rs1 + imm]
				RegWrite   = 1'b1 ;
				MemtoReg   = 1'b1 ;
				ALUSrcB    = 2'b01 ;
				ImmSrc     = 3'b011 ;			// I-type
			end
			OP_STORE: begin		// mem[rs1 + imm] = rs2
				MemWrite   = 1'b1 ;
				ALUSrcB    = 2'b01 ;
				ImmSrc     = 3'b110 ;			// S-type
			end
			OP_BRANCH: begin	// compare rs1 - rs2 in the ALU; PC_Logic decides; target = PC + imm
				PCS        = 2'b01 ;
				ImmSrc     = 3'b111 ;			// SB-type
				ALUControl = 4'b0001 ;			// sub, to produce the flags
			end
			OP_JAL: begin		// rd = PC + 4 (computed by the ALU); target = PC + imm
				PCS        = 2'b10 ;
				RegWrite   = 1'b1 ;
				ALUSrcA    = 2'b10 ;			// PC
				ALUSrcB    = 2'b10 ;			// 4
				ImmSrc     = 3'b010 ;			// UJ-type
			end
			OP_JALR: begin		// rd = PC + 4 (computed by the ALU); target = (rs1 + imm) & ~1
				PCS        = 2'b11 ;
				RegWrite   = 1'b1 ;
				ALUSrcA    = 2'b10 ;			// PC
				ALUSrcB    = 2'b10 ;			// 4
				ImmSrc     = 3'b011 ;			// I-type
			end
			OP_LUI: begin		// rd = 0 + (imm << 12)
				RegWrite   = 1'b1 ;
				ALUSrcA    = 2'b01 ;			// zero
				ALUSrcB    = 2'b01 ;
				ImmSrc     = 3'b000 ;			// U-type
			end
			OP_AUIPC: begin		// rd = PC + (imm << 12)
				RegWrite   = 1'b1 ;
				ALUSrcA    = 2'b10 ;			// PC
				ALUSrcB    = 2'b01 ;
				ImmSrc     = 3'b000 ;			// U-type
			end
			OP_SYSTEM: begin	// mret: PC = EPC. RV.v treats it as a jump that is never predicted.
				if( Funct3 == 3'b000 && Funct7 == FUNCT7_MRET )
					Mret = 1'b1 ;	// ecall, ebreak, csr* and the rest stay NOPs
			end
			default: ;		// unsupported opcode: keep the NOP defaults
		endcase
	end

endmodule