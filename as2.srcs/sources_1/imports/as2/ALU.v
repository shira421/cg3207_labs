`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS
-- Engineer: (c) Rajesh Panicker
--
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: ALU
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor ALU Module
--
-- Dependencies: NIL
--
-- Revision:
-- Revision 0.01 - File Created
-- Revision 0.02 - Assignment 2: shifts, xor, slt/sltu, eq/lt/ltu flags
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
--	Changes: added xor/slt/sltu/shift cases, connected the Shifter, derived
--	         eq/lt/ltu from the subtraction result (N, Z, C, V).
----------------------------------------------------------------------------------
*/

module ALU(
	input [31:0] Src_A,
	input [31:0] Src_B,
	input [3:0] ALUControl,	// {Funct3, 1 bit}:
				// 0000 add, 0001 sub (also used by branches), 0010 sll, 0100 slt, 0110 sltu,
				// 1000 xor, 1010 srl, 1011 sra, 1100 or, 1110 and.
	output reg [31:0] ALUResult,
	output [2:0] ALUFlags	//{eq, lt, ltu}
);

	// Shifter signals
	wire [1:0] Sh ;
	wire [4:0] Shamt5 ;
	wire [31:0] ShIn ;
	wire [31:0] ShOut ;

	// Other signals
	wire [32:0] S_wider ;
	reg [32:0] Src_A_comp ;
	reg [32:0] Src_B_comp ;
	reg [32:0] C_0 ;
	wire N, Z, C, V; 	// intermediate values used to derive eq, lt, ltu
	wire lt, ltu ;		// signed / unsigned "Src_A < Src_B", valid whenever the adder is subtracting

	// The ONLY 32-bit adder in the ALU. Subtraction reuses it as A + ~B + 1.
	assign S_wider = Src_A_comp + Src_B_comp + C_0 ;

	// always@(*) instead of an explicit sensitivity list, so simulation cannot miss a signal
	// (lt and ltu are read below, and they were not in the template's list).
	always@(*) begin
        	// default values; help avoid latches
		C_0 = 0 ;
		Src_A_comp = {1'b0, Src_A} ;
		Src_B_comp = {1'b0, Src_B} ;

		case(ALUControl)
			4'b0000: ALUResult = S_wider[31:0] ;		// add
			4'b0001: begin					// sub (also used for all branches)
				C_0[0] = 1 ;
				Src_B_comp = {1'b0, ~ Src_B} ;
				ALUResult = S_wider[31:0] ;
			end
			4'b0100: begin					// slt: subtract, then return the signed less-than flag
				C_0[0] = 1 ;
				Src_B_comp = {1'b0, ~ Src_B} ;
				ALUResult = {31'd0, lt} ;
			end
			4'b0110: begin					// sltu: subtract, then return the unsigned less-than flag
				C_0[0] = 1 ;
				Src_B_comp = {1'b0, ~ Src_B} ;
				ALUResult = {31'd0, ltu} ;
			end
			4'b1000: ALUResult = Src_A ^ Src_B ;		// xor
			4'b1100: ALUResult = Src_A | Src_B ; 		// or
			4'b1110: ALUResult = Src_A & Src_B ;		// and
			4'b0010, 4'b1010, 4'b1011:			// sll, srl, sra - all done by the Shifter
				ALUResult = ShOut ;
			default: ALUResult = 32'bx;
		endcase
	end

	// Flags from the adder output. They are meaningful when the adder is subtracting
	// (branches, slt, sltu); PC_Logic only looks at them for branches.
	assign N = S_wider[31] ;				// sign of (A - B)
	assign Z = ~|S_wider[31:0] ;				// (A - B) == 0; a 32-input NOR, not a 32-bit comparator
	assign C = S_wider[32] ;				// carry out; for A + ~B + 1 it is 1 exactly when A >= B (unsigned)
	assign V = (Src_A_comp[31] ~^ Src_B_comp[31]) & (Src_A_comp[31] ^ S_wider[31]) ;
								// signed overflow: operands of the addition have the same sign,
								// but the result's sign is different
	assign lt  = N ^ V ;					// signed A < B
	assign ltu = ~C ;					// unsigned A < B (a borrow happened)

	assign ALUFlags = {Z, lt, ltu} ; 			//{eq, lt, ltu}

	// Shifter connections
	assign Sh = {ALUControl[3], ALUControl[0]} ;		// 00 sll, 10 srl, 11 sra (see Shifter.v)
	assign Shamt5 = Src_B[4:0] ;				// rs2[4:0] for sll/srl/sra, imm[4:0] (shamt) for slli/srli/srai
	assign ShIn = Src_A ;

	// Instantiate Shifter
	Shifter Shifter1(
            Sh,
        	Shamt5,
        	ShIn,
        	ShOut
        );

endmodule