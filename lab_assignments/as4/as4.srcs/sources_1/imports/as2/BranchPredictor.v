`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Module Name: BranchPredictor
-- Project Name: CG3207 Project, Assignment 4
-- Description: Branch target buffer (BTB) with a 2-bit saturating counter per entry.
--
--   Looked up in F with PC_F. If the PC hits an entry whose counter says "taken"
--   (10 or 11), the next PC is the stored target instead of PC + 4, so a correctly
--   predicted taken branch or jal costs nothing instead of 2 flushed instructions.
--
--   Updated in E, where the branch outcome and target are known. Entries are only
--   allocated for branches that were taken and for jal (always taken). jalr and mret
--   are never predicted (their target changes), so they always redirect from E.
--
--   ENTRIES entries, direct mapped by PC[IDX+1:2]. The tag is PC[TAG_HI:IDX+2]; with
--   TAG_HI = 15 every instruction address in a <= 64 KB IROM has its own tag, so an
--   entry can only belong to one instruction and its target is always right.
--   RV.v still checks: a "taken" prediction for an instruction that turns out not to be a
--   branch/jal (possible only for PCs outside IROM) is treated as a misprediction.
--
--   Counter: 00 strongly not taken, 01 weakly not taken, 10 weakly taken, 11 strongly taken.
--   A new taken branch starts at 10, jal at 11.
--
--   The table is in flip-flops (about 32 x 41 bits), with a read port for F and one for E.
--   The comparisons are equalities on the tag, as for hazard detection; the only adder involved
--   is the next-PC adder in RV.v, as the lab allows for branch prediction.
----------------------------------------------------------------------------------
*/

module BranchPredictor #(
    parameter IDX    = 5,		// 2^IDX entries
    parameter TAG_HI = 15
)(
    input CLK,
    input RESET,
    input Enable,			// 0: never predict taken (the table keeps learning). Runtime switch.
    // F stage lookup
    input [31:0] PC_F,
    output PredTaken_F,
    output [31:0] PredTarget_F,
    // E stage update
    input Update_E,			// a valid branch or jal is leaving E this cycle
    input [31:0] PC_E,
    input Taken_E,			// what it actually did
    input IsJal_E,
    input [31:0] Target_E		// where it goes when taken
);
    localparam ENTRIES = 1 << IDX ;
    localparam TAGW    = TAG_HI - IDX - 1 ;	// tag = PC[TAG_HI : IDX+2]

    reg              valid  [0:ENTRIES-1] ;
    reg [TAGW-1:0]   tag    [0:ENTRIES-1] ;
    reg [31:2]       target [0:ENTRIES-1] ;	// targets are word aligned
    reg [1:0]        ctr    [0:ENTRIES-1] ;

    integer i ;
    initial begin
        for( i = 0 ; i < ENTRIES ; i = i + 1 ) begin
            valid[i]  = 1'b0 ;
            tag[i]    = {TAGW{1'b0}} ;
            target[i] = 30'd0 ;
            ctr[i]    = 2'b00 ;
        end
    end

    //------------------------------------------------------------------
    // F: lookup
    //------------------------------------------------------------------
    wire [IDX-1:0]  idx_F = PC_F[IDX+1:2] ;
    wire [TAGW-1:0] tag_F = PC_F[TAG_HI:IDX+2] ;
    wire hit_F = valid[idx_F] && (tag[idx_F] == tag_F) ;

    assign PredTaken_F  = Enable && hit_F && ctr[idx_F][1] ;
    assign PredTarget_F = {target[idx_F], 2'b00} ;

    //------------------------------------------------------------------
    // E: update. The entry is read again here (rather than carrying what F saw), so that a
    // branch in a tight loop sees the counter as updated by its previous iteration.
    //------------------------------------------------------------------
    wire [IDX-1:0]  idx_E = PC_E[IDX+1:2] ;
    wire [TAGW-1:0] tag_E = PC_E[TAG_HI:IDX+2] ;
    wire hit_E = valid[idx_E] && (tag[idx_E] == tag_E) ;
    wire [1:0] ctr_E = ctr[idx_E] ;

    always@(posedge CLK) begin
        if( RESET ) begin
            for( i = 0 ; i < ENTRIES ; i = i + 1 )
                valid[i] <= 1'b0 ;
        end
        else if( Update_E ) begin
            if( hit_E ) begin
                // saturating counter
                if( Taken_E && (ctr_E != 2'b11) )
                    ctr[idx_E] <= ctr_E + 2'd1 ;
                else if( !Taken_E && (ctr_E != 2'b00) )
                    ctr[idx_E] <= ctr_E - 2'd1 ;
                if( Taken_E )
                    target[idx_E] <= Target_E[31:2] ;
            end
            else if( Taken_E ) begin	// allocate (replacing whatever was there)
                valid[idx_E]  <= 1'b1 ;
                tag[idx_E]    <= tag_E ;
                target[idx_E] <= Target_E[31:2] ;
                ctr[idx_E]    <= IsJal_E ? 2'b11 : 2'b10 ;
            end
        end
    end

endmodule
