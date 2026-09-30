`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS
-- Engineer: (c) Rajesh Panicker
--
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: CondLogic
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Conditional Logic Module
--
-- Dependencies: NIL
--
-- Revision:
-- Revision 0.01 - File Created
-- Revision 0.02 - Assignment 2: all 6 branch conditions, 2-bit PCSrc for jal/jalr
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
--	Changes: branch condition evaluation from {eq, lt, ltu}; PCSrc widened to 2 bits.
----------------------------------------------------------------------------------
*/

module PC_Logic( // This is a combinational module, unlike ARM. See the note below.
	input [1:0] PCS,	// 00 for non-control, 01 for conditional branch, 10 for jal, 11 for jalr
	input [2:0] Funct3,	// condition specified in the instruction (eq / ne / lt / ge / ltu / geu)
	input [2:0] ALUFlags, 	// {eq, lt, ltu}
	output reg [1:0] PCSrc	// [0]: offset added to the base, 0 -> 4, 1 -> ExtImm
				// [1]: base,                      0 -> PC, 1 -> RD1 (jalr)
				// so: 00 = PC + 4, 01 = PC + imm (taken branch, jal), 11 = rs1 + imm (jalr)
    );

    /*
    	Important Note : ALUFlags are not *stored* in flag registers in RISC-V, unlike ARM and most other processors.
    	In RISC-V, the flags are produced and consumed in the same branch instruction.
    	The effect of CMP R1, R2 and BEQ LABEL in ARM is beq x1, x2, LABEL in RISC-V.
    */

	wire eq  = ALUFlags[2] ;
	wire lt  = ALUFlags[1] ;
	wire ltu = ALUFlags[0] ;

	reg BranchTaken ;	// is the condition in Funct3 true?

	always@(*) begin
		case(Funct3)
			3'b000: BranchTaken = eq ;	// beq
			3'b001: BranchTaken = ~eq ;	// bne
			3'b100: BranchTaken = lt ;	// blt
			3'b101: BranchTaken = ~lt ;	// bge
			3'b110: BranchTaken = ltu ;	// bltu
			3'b111: BranchTaken = ~ltu ;	// bgeu
			default: BranchTaken = 1'b0 ;	// 010, 011 are not valid branches: never take them
		endcase
	end

	always@(*) begin
		case(PCS)
			2'b00: PCSrc = 2'b00 ;			// not a control instruction: PC + 4
			2'b01: PCSrc = {1'b0, BranchTaken} ;	// branch: PC + imm if taken, else PC + 4
			2'b10: PCSrc = 2'b01 ;			// jal: PC + imm
			2'b11: PCSrc = 2'b11 ;			// jalr: rs1 + imm
			default: PCSrc = 2'b00 ;
		endcase
	end

endmodule