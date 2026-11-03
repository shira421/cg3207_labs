`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS	
-- Engineer: (c) Rajesh Panicker  
-- 
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: RegFile
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Register File Module
-- 
-- Dependencies: NIL
-- 
-- Revision:
-- Revision 0.01 - File Created
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
*/

module RegFile(
    input CLK,
    input WE,
    input [4:0] rs1,
    input [4:0] rs2,
    input [4:0] rd,
    input [31:0] WD,
    output reg [31:0] RD1,
    output reg [31:0] RD2
    );
    
    // declare RegBank
    reg [31:0] RegBank[0:31] ;
    // Assignment 4: start at 0, as the FPGA does, so that simulation (behavioural and
    // post-synthesis) matches the board instead of carrying x until a register is written.
    integer k ;
    initial
        for( k = 0 ; k < 32 ; k = k + 1 )
            RegBank[k] = 32'd0 ;
        // 32 addresses, each a 32-bit word
        // (1 to 31) is sufficient as R15 is not stored. Kept it as (0 to 31) just to supress a warning
		
    // read
    // Assignment 4: write-through. The register file is written at the same clock edge as the
    // pipeline registers, so an instruction in D reading a register that the instruction in W is
    // writing in this cycle would otherwise get the old value. Passing WD straight through removes
    // that hazard (a 5-bit equality compare, as the lab allows). Without it, a dependent instruction
    // would need 3 instructions in between instead of 2.
    always@(*)	// change to @posedge CLK only if using synch read. In that case, the output is RD1E, RD2E directly
    begin
    	if (rs1 == 5'b00000)
    		RD1 <= 32'd0 ;
    	else if (WE && (rd == rs1))
    		RD1 <= WD ;			// write-through from W
    	else
    		RD1 <= RegBank[rs1] ;
    	if (rs2 == 5'b00000)
    		RD2 <= 32'd0 ;
    	else if (WE && (rd == rs2))
    		RD2 <= WD ;
    	else
    		RD2 <= RegBank[rs2] ;
    end 
    
    // write
    always@(posedge CLK)
    begin
        if((rd != 5'b00000) & (WE))
            RegBank[rd] <= WD ;
    end
    
endmodule













