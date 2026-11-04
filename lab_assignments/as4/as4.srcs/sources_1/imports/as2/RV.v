`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS
-- Engineer: (c) Rajesh Panicker
--
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: RV
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Module
--
-- Dependencies: NIL
--
-- Revision:
-- Revision 0.01 - File Created
-- Revision 0.02 - Assignment 2: single-cycle datapath for RV32I (except byte/half-word load/store)
-- Revision 0.03 - Assignment 3: MCycle unit for RV32M (mul, mulh, mulhu, div, divu, rem, remu), stalling while Busy
-- Revision 0.04 - Assignment 4: 5-stage pipeline (F D E M W), hazard unit, branch prediction,
--                 byte/half-word load/store, interrupts, pipelined multiplier + mulsr
-- Additional Comments: The interface SHOULD NOT be modified (except making output reg) unless you modify Wrapper.v/vhd too.
                        The implementation can be modified.
                        Assignment 4 adds the Interrupt and CpuCtrl inputs; Wrapper.v was changed to match.
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
--	Assignment 4 - overview
--
--	   F            D             E                M              W
--	 PC_F ->IROM-> Instr_D ->   ALU / MCycle   -> ExecResult_M -> Result_W -> RegFile
--	 BTB lookup    Decoder      PC_Logic          DMEM / MMIO     LoadExtend
--	               RegFile      branch resolve    StoreAlign
--	               Extend       BTB update
--	                            PipeMulE:         PipeMulM:
--	                            Booth + CSA  ->   CSA + add + select -> MulResult_W
--
--	Multiplies (mul, mulh, mulhu, mulsr) go down the pipelined multiplier in E and M, one per
--	cycle, and their result is ready in W like a load's. Division (and multiplies in the
--	slow-multiplier mode, CPU_CTRL[2]) still use the MCycle unit, which stalls the pipeline.
--
--	Every signal carries the suffix of the stage it belongs to. A signal that moves on to the
--	next stage goes through one pipeline register (an always @(posedge CLK) block below),
--	e.g. ExtImm_D -> ExtImm_E. Each pipeline register can be stalled (hold) and/or flushed
--	(turned into a bubble: every control signal that changes state is cleared), as the
--	HazardUnit says.
--
--	Next PC (F), in priority order:
--	   1. Redirect_E: E found that the instruction after the one in E is not the one fetched
--	      (mispredicted branch, jalr, mret)    -> CorrectPC_E, flush D and E
--	   2. IntTake: interrupt accepted            -> ISR_ADDR, flush D and E, EPC = PC_D
--	   3. BTB predicts taken                     -> PredTarget_F
--	   4. otherwise                              -> PC_F + 4
--	With HAZARD_UNIT = 0 (compulsory-task pipeline, program padded with nops) there is no
--	forwarding, stalling (except MCycle), flushing, prediction or interrupt.
----------------------------------------------------------------------------------
*/

// Change wire to reg if assigned inside a procedural (always) block. However, where it is easy enough, use assign instead of always.
// A 2-1 multiplexing can be done easily using an assign with a ternary operator
// For multiplexing with number of inputs > 2, a case construct within an always block is a natural fit. DO NOT to use nested ternary assignment operator as it hampers the readability of your code.


module RV #(
    parameter PC_INIT = 32'h00400000,
    parameter HAZARD_UNIT = 1,		// 0: plain pipeline, the program must contain the nops (compulsory task)
    parameter ISR_ADDR = PC_INIT + 4	// interrupt handler: the second word of the program (a jump to the handler)
)(
    input CLK,
    input RESET,
    input Interrupt,			// level, from Wrapper. Taken when the CPU is not already in the handler.
    input [2:0] CpuCtrl,		// runtime switches from Wrapper (MMIO CPU_CTRL): [0] no forwarding, [1] no branch prediction,
    					// [2] slow multiplier (multiplies on the Assignment 3 MCycle unit, 33 cycles, stalling)
    input [31:0] Instr,
    input [31:0] ReadData_in,       // Name mangled to support lb/lbu/lh/lhu
    output MemRead,
    output [3:0] MemWrite_out,		// Column-wise write enable to support sb/sw. Each column is a byte.
    output [31:0] PC,
    output [31:0] ALUResult,
    output [31:0] WriteData_out		// Name mangled to support sb/sw
);

    localparam [31:0] NOP = 32'h00000013 ;	// addi x0, x0, 0

    // Opcodes needed here to know which source registers an instruction really reads
    localparam OP_DPREG  = 7'b0110011 ;
    localparam OP_STORE  = 7'b0100011 ;
    localparam OP_BRANCH = 7'b1100011 ;
    localparam OP_JAL    = 7'b1101111 ;
    localparam OP_LUI    = 7'b0110111 ;
    localparam OP_AUIPC  = 7'b0010111 ;
    localparam OP_CUSTOM0 = 7'b0001011 ;	// mulsr

    wire NoForward  = CpuCtrl[0] ;
    wire NoPredict  = CpuCtrl[1] ;
    wire SlowMul    = CpuCtrl[2] ;

    //==================================================================
    // Hazard unit signals
    //==================================================================
    wire [1:0] ForwardA_E, ForwardB_E ;
    wire StallRaw_D, StallF, StallD, StallE, FlushD, FlushE, FlushM ;
    wire Redirect_E ;
    wire IntTake ;

    //==================================================================
    // F stage
    //==================================================================
    wire [31:0] PC_F ;
    wire [31:0] PCPlus4_F ;
    wire PredTaken_F ;
    wire [31:0] PredTarget_F ;
    wire [31:0] NextPC_F ;
    reg  [31:0] PC_IN ;
    wire WE_PC ;
    wire [31:0] CorrectPC_E ;

    assign PC = PC_F ;
    assign PCPlus4_F = PC_F + 32'd4 ;		// next-PC adder (the lab allows + for the next PC)
    assign NextPC_F  = PredTaken_F ? PredTarget_F : PCPlus4_F ;

    always@(*) begin
        if( Redirect_E )
            PC_IN = CorrectPC_E ;
        else if( IntTake )
            PC_IN = ISR_ADDR ;
        else
            PC_IN = NextPC_F ;
    end

    assign WE_PC = ~StallF ;

    ProgramCounter #(.PC_INIT(PC_INIT)) ProgramCounter1(
                    CLK,
                    RESET,
                    WE_PC,
                    PC_IN,
                    PC_F
                );

    //------------------------------------------------------------------
    // F -> D pipeline register
    //------------------------------------------------------------------
    reg [31:0] Instr_D = NOP ;
    reg [31:0] PC_D = 32'd0 ;
    reg [31:0] PCPlus4_D = 32'd0 ;
    reg PredTaken_D = 1'b0 ;
    reg Valid_D = 1'b0 ;		// 0 for a bubble. Needed to know where to return to after an interrupt.

    always@(posedge CLK) begin
        if( RESET || FlushD ) begin
            Instr_D     <= NOP ;
            PC_D        <= 32'd0 ;
            PCPlus4_D   <= 32'd0 ;
            PredTaken_D <= 1'b0 ;
            Valid_D     <= 1'b0 ;
        end
        else if( !StallD ) begin
            Instr_D     <= Instr ;
            PC_D        <= PC_F ;
            PCPlus4_D   <= PCPlus4_F ;
            PredTaken_D <= PredTaken_F ;
            Valid_D     <= 1'b1 ;
        end
    end

    //==================================================================
    // D stage
    //==================================================================
    wire [6:0] Opcode_D = Instr_D[6:0] ;
    wire [4:0] rd_D     = Instr_D[11:7] ;
    wire [2:0] Funct3_D = Instr_D[14:12] ;
    wire [4:0] rs1_D    = Instr_D[19:15] ;
    wire [4:0] rs2_D    = Instr_D[24:20] ;
    wire [6:0] Funct7_D = Instr_D[31:25] ;
    wire [24:0] InstrImm_D = Instr_D[31:7] ;

    wire [1:0] PCS_D ;
    wire RegWrite_D, MemWrite_D, MemtoReg_D ;
    wire [1:0] ALUSrcA_D, ALUSrcB_D ;
    wire [2:0] ImmSrc_D ;
    wire [3:0] ALUControl_D ;
    wire MStart_D ;
    wire [1:0] MCycleOp_D ;
    wire MCycleSel_D, MResultSel_D ;
    wire Mret_D ;
    wire IsMul_D ;
    wire [5:0] MulShift_D ;
    wire [31:0] ExtImm_D ;
    wire [31:0] RD1_D, RD2_D ;

    // Which register fields are real source registers (so that, e.g., the immediate bits of an
    // addi that happen to equal rd of an earlier instruction do not cause a needless stall)
    wire UsesRs1_D = !( (Opcode_D == OP_LUI) || (Opcode_D == OP_AUIPC) || (Opcode_D == OP_JAL) ) ;
    wire UsesRs2_D = (Opcode_D == OP_DPREG) || (Opcode_D == OP_STORE) || (Opcode_D == OP_BRANCH) ||
                     (Opcode_D == OP_CUSTOM0) ;

    Decoder Decoder1(
                    Opcode_D,
                    Funct3_D,
                    Funct7_D,
                    PCS_D,
                    RegWrite_D,
                    MemWrite_D,
                    MemtoReg_D,
                    ALUSrcA_D,
                    ALUSrcB_D,
                    ImmSrc_D,
                    ALUControl_D,
                    MStart_D,
                    MCycleOp_D,
                    MCycleSel_D,
                    MResultSel_D,
                    Mret_D,
                    IsMul_D,
                    MulShift_D
                );

    Extend Extend1(
                    ImmSrc_D,
                    InstrImm_D,
                    ExtImm_D
                );

    // Register file: read in D, written by W at the same clock edge as the pipeline registers
    // (with write-through, see RegFile.v)
    wire RegWrite_W_wire ;
    wire [4:0] rd_W_wire ;
    wire [31:0] Result_W ;

    RegFile RegFile1(
                    CLK,
                    RegWrite_W_wire,
                    rs1_D,
                    rs2_D,
                    rd_W_wire,
                    Result_W,
                    RD1_D,
                    RD2_D
                );

    //------------------------------------------------------------------
    // D -> E pipeline register
    //------------------------------------------------------------------
    reg [1:0]  PCS_E = 2'b00 ;
    reg        RegWrite_E = 1'b0, MemWrite_E = 1'b0, MemtoReg_E = 1'b0 ;
    reg [1:0]  ALUSrcA_E = 2'b00, ALUSrcB_E = 2'b00 ;
    reg [3:0]  ALUControl_E = 4'b0000 ;
    reg        MStart_E = 1'b0 ;
    reg [1:0]  MCycleOp_E = 2'b00 ;
    reg        MCycleSel_E = 1'b0, MResultSel_E = 1'b0 ;
    reg        Mret_E = 1'b0 ;
    reg [2:0]  Funct3_E = 3'b000 ;
    reg [31:0] RD1_E = 32'd0, RD2_E = 32'd0, ExtImm_E = 32'd0 ;
    reg [31:0] PC_E = 32'd0, PCPlus4_E = 32'd0 ;
    reg [4:0]  rs1_E = 5'd0, rs2_E = 5'd0, rd_E = 5'd0 ;
    reg        PredTaken_E = 1'b0 ;
    reg        Valid_E = 1'b0 ;
    reg        NoForward_E = 1'b0 ;	// CPU_CTRL[0] when this instruction was in D
    reg        IsMul_E = 1'b0 ;
    reg [5:0]  MulShift_E = 6'd0 ;
    reg        SlowMul_E = 1'b0 ;	// CPU_CTRL[2] when this instruction was in D

    always@(posedge CLK) begin
        if( RESET || (FlushE && !StallE) ) begin
            // A bubble: nothing that changes state. (The data fields do not matter.)
            PCS_E        <= 2'b00 ;
            RegWrite_E   <= 1'b0 ;
            MemWrite_E   <= 1'b0 ;
            MemtoReg_E   <= 1'b0 ;
            MStart_E     <= 1'b0 ;
            MCycleSel_E  <= 1'b0 ;
            Mret_E       <= 1'b0 ;
            IsMul_E      <= 1'b0 ;
            PredTaken_E  <= 1'b0 ;
            Valid_E      <= 1'b0 ;
            rs1_E        <= 5'd0 ;
            rs2_E        <= 5'd0 ;
            rd_E         <= 5'd0 ;
        end
        else if( !StallE ) begin
            PCS_E        <= PCS_D ;
            RegWrite_E   <= RegWrite_D ;
            MemWrite_E   <= MemWrite_D ;
            MemtoReg_E   <= MemtoReg_D ;
            ALUSrcA_E    <= ALUSrcA_D ;
            ALUSrcB_E    <= ALUSrcB_D ;
            ALUControl_E <= ALUControl_D ;
            MStart_E     <= MStart_D ;
            MCycleOp_E   <= MCycleOp_D ;
            MCycleSel_E  <= MCycleSel_D ;
            MResultSel_E <= MResultSel_D ;
            Mret_E       <= Mret_D ;
            Funct3_E     <= Funct3_D ;
            RD1_E        <= RD1_D ;
            RD2_E        <= RD2_D ;
            ExtImm_E     <= ExtImm_D ;
            PC_E         <= PC_D ;
            PCPlus4_E    <= PCPlus4_D ;
            rs1_E        <= rs1_D ;
            rs2_E        <= rs2_D ;
            rd_E         <= rd_D ;
            PredTaken_E  <= PredTaken_D ;
            Valid_E      <= Valid_D ;
            NoForward_E  <= NoForward ;
            IsMul_E      <= IsMul_D ;
            MulShift_E   <= MulShift_D ;
            SlowMul_E    <= SlowMul ;
        end
    end

    //==================================================================
    // E stage
    //==================================================================
    reg  [31:0] FwdA_E, FwdB_E ;	// rs1 / rs2 after forwarding
    reg  [31:0] Src_A_E, Src_B_E ;
    wire [31:0] ALUResult_E ;
    wire [2:0]  ALUFlags_E ;
    wire [1:0]  PCSrc_E ;
    wire [31:0] MCycleResult1_E, MCycleResult2_E ;
    wire        Busy ;
    wire [31:0] ExecResult_E ;
    reg  [31:0] ExecResult_M ;		// declared here as E forwards from it

    // Forwarding multiplexers
    always@(*) begin
        case( ForwardA_E )
            2'b10:   FwdA_E = ExecResult_M ;
            2'b01:   FwdA_E = Result_W ;
            default: FwdA_E = RD1_E ;
        endcase
        case( ForwardB_E )
            2'b10:   FwdB_E = ExecResult_M ;
            2'b01:   FwdB_E = Result_W ;
            default: FwdB_E = RD2_E ;
        endcase
    end

    // ALU operand multiplexers (as in Assignment 2)
    always@(*) begin
        case( ALUSrcA_E )
            2'b00:   Src_A_E = FwdA_E ;		// rs1
            2'b01:   Src_A_E = 32'd0 ;		// lui:  0 + imm
            2'b10:   Src_A_E = PC_E ;		// auipc: PC + imm; jal/jalr link: PC + 4
            default: Src_A_E = 32'bx ;
        endcase
        case( ALUSrcB_E )
            2'b00:   Src_B_E = FwdB_E ;		// rs2
            2'b01:   Src_B_E = ExtImm_E ;
            2'b10:   Src_B_E = 32'd4 ;
            default: Src_B_E = 32'bx ;
        endcase
    end

    ALU ALU1(
                    Src_A_E,
                    Src_B_E,
                    ALUControl_E,
                    ALUResult_E,
                    ALUFlags_E
                );

    // MCycle takes its operands (after forwarding) in its first cycle, and the pipeline holds
    // the instruction in E until Busy falls. It does division, and multiplication only in the
    // slow-multiplier mode; otherwise multiplies go down the pipelined multiplier below.
    wire MCycleStart_E = MStart_E && (!IsMul_E || SlowMul_E) ;
    MCycle #(.width(32)) MCycle1(
                    .CLK(CLK),
                    .RESET(RESET),
                    .Start(MCycleStart_E),
                    .MCycleOp(MCycleOp_E),
                    .Operand1(FwdA_E),
                    .Operand2(FwdB_E),
                    .Result1(MCycleResult1_E),
                    .Result2(MCycleResult2_E),
                    .Busy(Busy)
                );

    assign ExecResult_E = MCycleSel_E ? (MResultSel_E ? MCycleResult2_E : MCycleResult1_E) : ALUResult_E ;

    //------------------------------------------------------------------
    // Pipelined multiplier, first half: Booth partial products + carry-save tree -> 4 rows.
    // In the slow-multiplier mode the rows are just MCycle's 64-bit product (and zeros), so the
    // second half (CSA, add, select) works the same either way.
    //------------------------------------------------------------------
    wire [63:0] MulRow0_E, MulRow1_E, MulRow2_E, MulRow3_E ;
    wire [63:0] BoothRow0_E, BoothRow1_E, BoothRow2_E, BoothRow3_E ;
    PipeMulE PipeMulE1(
                    .A(FwdA_E),
                    .B(FwdB_E),
                    .Signed(~MCycleOp_E[0]),	// 00 signed (mul, mulh, mulsr), 01 unsigned (mulhu)
                    .R0(BoothRow0_E),
                    .R1(BoothRow1_E),
                    .R2(BoothRow2_E),
                    .R3(BoothRow3_E)
                );
    assign MulRow0_E = SlowMul_E ? {MCycleResult2_E, MCycleResult1_E} : BoothRow0_E ;
    assign MulRow1_E = SlowMul_E ? 64'd0 : BoothRow1_E ;
    assign MulRow2_E = SlowMul_E ? 64'd0 : BoothRow2_E ;
    assign MulRow3_E = SlowMul_E ? 64'd0 : BoothRow3_E ;

    //------------------------------------------------------------------
    // Branch resolution
    //------------------------------------------------------------------
    PC_Logic PC_Logic1(
                    PCS_E,
                    Funct3_E,
                    ALUFlags_E,
                    PCSrc_E
                );

    // Branch / jump target: PC_E + imm, or rs1 + imm for jalr. (The second next-PC adder.)
    wire [31:0] TargetBase_E = PCSrc_E[1] ? FwdA_E : PC_E ;
    wire [31:0] TargetSum_E  = TargetBase_E + ExtImm_E ;
    wire [31:0] Target_E     = {TargetSum_E[31:1], 1'b0} ;	// jalr clears bit 0

    wire Taken_E   = PCSrc_E[0] ;				// branch taken, jal, jalr
    wire IsBrJal_E = (PCS_E == 2'b01) || (PCS_E == 2'b10) ;	// what the BTB knows about
    wire IsJalr_E  = (PCS_E == 2'b11) ;

    // The instruction after this one was fetched from: PredTarget if PredTaken_E, else PC + 4.
    // Redirect if that was wrong. jalr and mret are never predicted, so they always redirect.
    assign Redirect_E = Valid_E && ( (Taken_E != PredTaken_E) || IsJalr_E || Mret_E ) ;

    reg [31:0] EPC = 32'd0 ;
    assign CorrectPC_E = Mret_E ? EPC : ( Taken_E ? Target_E : PCPlus4_E ) ;

    // Train the predictor with every branch and jal that leaves E
    BranchPredictor #(.IDX(5), .TAG_HI(15)) BranchPredictor1(
                    .CLK(CLK),
                    .RESET(RESET),
                    .Enable((HAZARD_UNIT != 0) && !NoPredict),
                    .PC_F(PC_F),
                    .PredTaken_F(PredTaken_F),
                    .PredTarget_F(PredTarget_F),
                    .Update_E(Valid_E && IsBrJal_E && !StallE),
                    .PC_E(PC_E),
                    .Taken_E(Taken_E),
                    .IsJal_E(PCS_E == 2'b10),
                    .Target_E(Target_E)
                );

    //------------------------------------------------------------------
    // Interrupts
    // Taken between instructions: the instruction in D (and the one in F) are discarded and will
    // be executed after the handler returns; everything in E, M, W completes. So EPC = PC_D.
    // Only when D holds a real instruction on the correct path and nothing is stalling.
    //------------------------------------------------------------------
    reg InISR = 1'b0 ;	// in the handler: further interrupts wait until mret

    assign IntTake = (HAZARD_UNIT != 0) && Interrupt && !InISR && Valid_D && !Redirect_E && !StallRaw_D ;

    always@(posedge CLK) begin
        if( RESET ) begin
            InISR <= 1'b0 ;
            EPC   <= 32'd0 ;
        end
        else if( IntTake ) begin
            InISR <= 1'b1 ;
            EPC   <= PC_D ;
        end
        else if( Valid_E && Mret_E )
            InISR <= 1'b0 ;
    end

    //------------------------------------------------------------------
    // E -> M pipeline register
    //------------------------------------------------------------------
    reg        RegWrite_M = 1'b0, MemWrite_M = 1'b0, MemtoReg_M = 1'b0 ;
    reg [2:0]  Funct3_M = 3'b000 ;
    reg [31:0] WriteData_M = 32'd0 ;
    reg [4:0]  rd_M = 5'd0 ;
    reg        IsMul_M = 1'b0 ;
    reg [5:0]  MulShift_M = 6'd0 ;
    reg [63:0] MulRow0_M = 64'd0, MulRow1_M = 64'd0, MulRow2_M = 64'd0, MulRow3_M = 64'd0 ;
    initial ExecResult_M = 32'd0 ;

    always@(posedge CLK) begin
        if( RESET || FlushM ) begin
            RegWrite_M   <= 1'b0 ;
            MemWrite_M   <= 1'b0 ;
            MemtoReg_M   <= 1'b0 ;
            rd_M         <= 5'd0 ;
            IsMul_M      <= 1'b0 ;
        end
        else begin
            IsMul_M      <= IsMul_E ;
            MulShift_M   <= MulShift_E ;
            MulRow0_M    <= MulRow0_E ;
            MulRow1_M    <= MulRow1_E ;
            MulRow2_M    <= MulRow2_E ;
            MulRow3_M    <= MulRow3_E ;
            RegWrite_M   <= RegWrite_E ;
            MemWrite_M   <= MemWrite_E ;
            MemtoReg_M   <= MemtoReg_E ;
            Funct3_M     <= Funct3_E ;
            ExecResult_M <= ExecResult_E ;
            WriteData_M  <= FwdB_E ;		// sw stores rs2 (forwarded)
            rd_M         <= rd_E ;
        end
    end

    //==================================================================
    // M stage
    //==================================================================
    assign ALUResult = ExecResult_M ;		// data memory / MMIO address
    assign MemRead   = MemtoReg_M ;		// This is needed for the proper functionality of some devices such as UART CONSOLE

    // Pipelined multiplier, second half: CSA, the 64-bit add, and the 32-bit window [k+31:k]
    wire [31:0] MulResult_M ;
    PipeMulM PipeMulM1(
                    .R0(MulRow0_M),
                    .R1(MulRow1_M),
                    .R2(MulRow2_M),
                    .R3(MulRow3_M),
                    .K(MulShift_M),
                    .Result(MulResult_M)
                );

    StoreAlign StoreAlign1(
                    .MemWrite(MemWrite_M),
                    .Funct3(Funct3_M),
                    .Addr(ExecResult_M[1:0]),
                    .WriteData(WriteData_M),
                    .MemWrite_out(MemWrite_out),
                    .WriteData_out(WriteData_out)
                );

    //------------------------------------------------------------------
    // M -> W pipeline register
    //------------------------------------------------------------------
    reg        RegWrite_W = 1'b0, MemtoReg_W = 1'b0 ;
    reg [2:0]  Funct3_W = 3'b000 ;
    reg [31:0] ExecResult_W = 32'd0 ;
    reg [31:0] ReadDataRaw_W = 32'd0 ;	// the whole word read from memory
    reg [4:0]  rd_W = 5'd0 ;
    reg        IsMul_W = 1'b0 ;
    reg [31:0] MulResult_W = 32'd0 ;

    always@(posedge CLK) begin
        if( RESET ) begin
            RegWrite_W   <= 1'b0 ;
            MemtoReg_W   <= 1'b0 ;
            rd_W         <= 5'd0 ;
            IsMul_W      <= 1'b0 ;
        end
        else begin
            IsMul_W       <= IsMul_M ;
            MulResult_W   <= MulResult_M ;
            RegWrite_W    <= RegWrite_M ;
            MemtoReg_W    <= MemtoReg_M ;
            Funct3_W      <= Funct3_M ;
            ExecResult_W  <= ExecResult_M ;
            ReadDataRaw_W <= ReadData_in ;
            rd_W          <= rd_M ;
        end
    end

    //==================================================================
    // W stage
    //==================================================================
    wire [31:0] ReadData_W ;
    reg  [31:0] Result_W_r ;

    LoadExtend LoadExtend1(
                    .Funct3(Funct3_W),
                    .Addr(ExecResult_W[1:0]),
                    .ReadData_in(ReadDataRaw_W),
                    .ReadData(ReadData_W)
                );

    always@(*) begin
        if( MemtoReg_W )
            Result_W_r = ReadData_W ;
        else if( IsMul_W )
            Result_W_r = MulResult_W ;
        else
            Result_W_r = ExecResult_W ;
    end
    assign Result_W = Result_W_r ;
    assign RegWrite_W_wire = RegWrite_W ;
    assign rd_W_wire = rd_W ;

    //==================================================================
    // Hazard unit
    //==================================================================
    HazardUnit #(.HAZARD_UNIT(HAZARD_UNIT)) HazardUnit1(
                    .rs1_D(rs1_D),
                    .rs2_D(rs2_D),
                    .UsesRs1_D(UsesRs1_D),
                    .UsesRs2_D(UsesRs2_D),
                    .rs1_E(rs1_E),
                    .rs2_E(rs2_E),
                    .rd_E(rd_E),
                    .RegWrite_E(RegWrite_E),
                    .MemtoReg_E(MemtoReg_E),
                    .IsMul_E(IsMul_E),
                    .Busy(Busy),
                    .Redirect_E(Redirect_E),
                    .rd_M(rd_M),
                    .RegWrite_M(RegWrite_M),
                    .rd_W(rd_W),
                    .RegWrite_W(RegWrite_W),
                    .IntTake(IntTake),
                    .NoForward(NoForward),
                    .NoForward_E(NoForward_E),
                    .ForwardA_E(ForwardA_E),
                    .ForwardB_E(ForwardB_E),
                    .StallRaw_D(StallRaw_D),
                    .StallF(StallF),
                    .StallD(StallD),
                    .StallE(StallE),
                    .FlushD(FlushD),
                    .FlushE(FlushE),
                    .FlushM(FlushM)
                );

endmodule
