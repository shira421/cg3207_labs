`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Module Name: HazardUnit
-- Project Name: CG3207 Project, Assignment 4
-- Description: Forwarding, stalling and flushing for the 5-stage pipeline in RV.v
--              (Chapter 5 (v2) design, plus the MCycle stall, interrupt entry and a
--              runtime "no forwarding" mode used to compare against a plain interlocked pipeline).
--
-- Every comparison here is an equality on 5-bit register numbers, as the lab allows.
----------------------------------------------------------------------------------

  What each hazard costs and how it is handled
  --------------------------------------------
  Data hazard, ALU result needed in E      -> forward from M (ExecResult_M) or W (Result_W). 0 cycles.
  Data hazard, value written in W, read D  -> RegFile write-through. 0 cycles.
  Load followed by a user of the load      -> stall F and D, bubble into E. 1 cycle.
  Multiply followed by a user of the product -> the same (the pipelined multiplier finishes in M). 1 cycle.
  Mispredicted branch / jal / jalr / mret  -> flush D and E (the 2 wrong-path instructions). 2 cycles.
  MCycle (div, or mul in slow mode) in E   -> stall F, D and E, bubble into M. ~33 cycles.
  Interrupt accepted                       -> flush D and E, like a taken jump.

  NoForward = 1 (runtime, CPU_CTRL[0])
      Forwarding is replaced by interlocking: D waits while E or M will write a register it reads,
      so it never needs a forwarded value (W is covered by the write-through). This is how the CPU
      behaves without a forwarding unit, and lets the demo program measure what forwarding buys.
      The setting travels down the pipeline with each instruction (NoForward_E), and forwarding into
      E is switched off only for instructions that were decoded in this mode - they waited in D, so
      they need none. That makes it safe to flip the switch while the program runs.

  HAZARD_UNIT = 0 (synthesis-time parameter)
      No forwarding, no load-use stall, no flushing: the plain pipeline of the compulsory task, where
      the program must contain enough nops (3 between dependent instructions, 2 after a branch).
      The MCycle stall stays, since mul/div cannot work without it.
*/

module HazardUnit #(
    parameter HAZARD_UNIT = 1
)(
    // D stage (the instruction being decoded)
    input [4:0] rs1_D,
    input [4:0] rs2_D,
    input UsesRs1_D,		// the instruction really reads rs1 (not lui / auipc / jal)
    input UsesRs2_D,		// the instruction really reads rs2 (R-type, store, branch)
    // E stage
    input [4:0] rs1_E,
    input [4:0] rs2_E,
    input [4:0] rd_E,
    input RegWrite_E,
    input MemtoReg_E,		// the instruction in E is a load
    input IsMul_E,		// the instruction in E is a multiply: like a load, its result is ready in W
    input Busy,			// MCycle is working on the instruction in E
    input Redirect_E,		// E found the next PC was predicted wrongly (or jalr / mret)
    // M and W stages
    input [4:0] rd_M,
    input RegWrite_M,
    input [4:0] rd_W,
    input RegWrite_W,
    // other
    input IntTake,		// an interrupt is being taken this cycle (RV.v only allows it when nothing stalls)
    input NoForward,		// runtime switch: interlock instead of forwarding (for the instruction in D)
    input NoForward_E,		// ... and as it was when the instruction now in E was in D

    output reg [1:0] ForwardA_E,	// 00 register file, 10 from M, 01 from W
    output reg [1:0] ForwardB_E,
    output StallRaw_D,			// D cannot move on this cycle (before redirects are considered)
    output StallF,
    output StallD,
    output StallE,
    output FlushD,
    output FlushE,
    output FlushM
);

    //------------------------------------------------------------------
    // Forwarding into E. M has priority, as it holds the newer value.
    //------------------------------------------------------------------
    always@(*) begin
        ForwardA_E = 2'b00 ;
        ForwardB_E = 2'b00 ;
        if( HAZARD_UNIT && !NoForward_E ) begin
            if( RegWrite_M && (rd_M != 5'd0) && (rd_M == rs1_E) )
                ForwardA_E = 2'b10 ;
            else if( RegWrite_W && (rd_W != 5'd0) && (rd_W == rs1_E) )
                ForwardA_E = 2'b01 ;

            if( RegWrite_M && (rd_M != 5'd0) && (rd_M == rs2_E) )
                ForwardB_E = 2'b10 ;
            else if( RegWrite_W && (rd_W != 5'd0) && (rd_W == rs2_E) )
                ForwardB_E = 2'b01 ;
        end
    end

    //------------------------------------------------------------------
    // Stalls
    //------------------------------------------------------------------
    // Does the instruction in D read the register that the instruction in X will write?
    wire dep_E = RegWrite_E && (rd_E != 5'd0) &&
                 ( (UsesRs1_D && (rs1_D == rd_E)) || (UsesRs2_D && (rs2_D == rd_E)) ) ;
    wire dep_M = RegWrite_M && (rd_M != 5'd0) &&
                 ( (UsesRs1_D && (rs1_D == rd_M)) || (UsesRs2_D && (rs2_D == rd_M)) ) ;

    // Load-use: the loaded value only exists at the end of M, too late to forward into E.
    // The same holds for a multiply, whose product is finished by the end of M.
    wire lwStall    = (HAZARD_UNIT != 0) && (MemtoReg_E || IsMul_E) && dep_E ;
    // No-forwarding mode: wait until the producer has reached W.
    wire nofwdStall = (HAZARD_UNIT != 0) && NoForward && (dep_E || dep_M) ;

    wire dataStall  = lwStall || nofwdStall ;

    assign StallRaw_D = dataStall || Busy ;

    // A redirect from E wins over a data stall: the instruction stalling in D is on the wrong
    // path and is about to be flushed anyway. (Busy and a redirect never happen together:
    // a redirect comes from a control instruction in E, Busy from a mul/div in E.)
    wire redirectFlush = (HAZARD_UNIT != 0) && Redirect_E ;

    assign StallF = StallRaw_D && !redirectFlush ;
    assign StallD = StallRaw_D && !redirectFlush ;
    assign StallE = Busy ;			// hold the mul/div in E until it is done

    assign FlushD = redirectFlush || IntTake ;
    // While Busy, E must not be flushed (it holds the mul/div), so a data stall then only stalls.
    assign FlushE = redirectFlush || IntTake || (dataStall && !Busy) ;
    assign FlushM = Busy ;			// the mul/div is not finished: send a bubble down to M

endmodule
