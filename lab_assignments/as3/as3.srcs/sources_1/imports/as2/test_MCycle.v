`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: NUS
// Engineer: Shahzor Ahmad, Rajesh C Panicker
//
// Create Date: 27.09.2016 16:55:23
// Design Name:
// Module Name: test_MCycle
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Assignment 3: converted into a self-checking testbench
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
/*
----------------------------------------------------------------------------------
--	(c) Shahzor Ahmad, Rajesh C Panicker
--	License terms :
--	You are free to use this code as long as you
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(iv) send an email to rajesh.panicker@ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(v) retain this notice in this file or any files derived from this.
----------------------------------------------------------------------------------
*/

/*
----------------------------------------------------------------------------------
--	Self-checking testbench for MCycle (all four operations).
--
--	AI assistance declaration: written with Claude (Anthropic), Claude Opus 5.5, 14 Oct 2026,
--	from the prompt "complete tasks 1, 2 and 3 for assignment 3" and the template files.
--
--	One mcycle_tester runs one MCycle instance. test_MCycle runs several in parallel:
--	  width 4  : every operand pair (exhaustive), all four operations          - radix-4 Booth
--	  width 6  : every operand pair (exhaustive), all four operations          - radix-4 Booth
--	  width 32 : corner cases (0, +-1, +-2, min, max, patterns) x each other
--	             + 3000 random pairs per operation                             - radix-4 Booth
--	  width 4 and 32 again with RADIX4_BOOTH = 0 (original shift-and-add multiplier), for comparison
--
--	Every operation is checked for
--	  - Result1 / Result2 against a reference computed here (RISC-V rules for division,
--	    including x/0 and min/-1, although the CPU may assume the divisor is never 0)
--	  - the exact number of cycles (cycles with Busy = 1, plus the cycle in which Busy falls,
--	    which is when the processor writes the result back)
--	  - Busy rising in the same cycle as Start (combinational)
--	The way operations are issued is varied, the way the processor would:
--	  - back to back with Start held at 1 (consecutive mul/div instructions),
--	  - with Start dropped for a cycle in between (results must be held while idle),
--	  - with Operand1 / Operand2 changed while Busy (the unit must use the values from the start).
--	It also resets the unit in the middle of an operation.
--
--	Run with "run all"; it stops by itself and prints PASSED / FAILED with the cycle counts.
--	test_MCycle_postsynth (below) runs the width-32 tests on a synthesized MCycle netlist instead.
--	(About 3.6 ms of simulated time.)
----------------------------------------------------------------------------------
*/

module test_MCycle(

    );

    wire done_4, done_6, done_32, done_4o, done_32o ;

    //                       width  Booth  exhaustive  randoms per op
    mcycle_tester #(.W( 4), .BOOTH(1), .EXHAUSTIVE(1), .NRANDOM(   0), .SEED(11)) t4   (.finished(done_4)) ;
    mcycle_tester #(.W( 6), .BOOTH(1), .EXHAUSTIVE(1), .NRANDOM(   0), .SEED(22)) t6   (.finished(done_6)) ;
    mcycle_tester #(.W(32), .BOOTH(1), .EXHAUSTIVE(0), .NRANDOM(3000), .SEED(33)) t32  (.finished(done_32)) ;
    mcycle_tester #(.W( 4), .BOOTH(0), .EXHAUSTIVE(1), .NRANDOM(   0), .SEED(44)) t4o  (.finished(done_4o)) ;
    mcycle_tester #(.W(32), .BOOTH(0), .EXHAUSTIVE(0), .NRANDOM( 300), .SEED(55)) t32o (.finished(done_32o)) ;

    initial begin
        wait( done_4 & done_6 & done_32 & done_4o & done_32o ) ;
        #1 ;
        $display("") ;
        $display("==================================================================================") ;
        $display(" MCycle                     checks   errors   cycles: smul  umul  sdiv  udiv") ;
        report("width  4, radix-4 Booth  ", t4.checks,   t4.errors,   t4.lat_seen[0],   t4.lat_seen[1],   t4.lat_seen[2],   t4.lat_seen[3]) ;
        report("width  6, radix-4 Booth  ", t6.checks,   t6.errors,   t6.lat_seen[0],   t6.lat_seen[1],   t6.lat_seen[2],   t6.lat_seen[3]) ;
        report("width 32, radix-4 Booth  ", t32.checks,  t32.errors,  t32.lat_seen[0],  t32.lat_seen[1],  t32.lat_seen[2],  t32.lat_seen[3]) ;
        report("width  4, original mul   ", t4o.checks,  t4o.errors,  t4o.lat_seen[0],  t4o.lat_seen[1],  t4o.lat_seen[2],  t4o.lat_seen[3]) ;
        report("width 32, original mul   ", t32o.checks, t32o.errors, t32o.lat_seen[0], t32o.lat_seen[1], t32o.lat_seen[2], t32o.lat_seen[3]) ;
        $display("==================================================================================") ;
        if( t4.errors + t6.errors + t32.errors + t4o.errors + t32o.errors == 0 )
            $display(" PASSED - all %0d checks", t4.checks + t6.checks + t32.checks + t4o.checks + t32o.checks) ;
        else
            $display(" FAILED - %0d errors", t4.errors + t6.errors + t32.errors + t4o.errors + t32o.errors) ;
        $display("==================================================================================") ;
        $finish ;
    end

    task report(input [8*25-1:0] name, input integer checks, input integer errors,
                input integer l0, input integer l1, input integer l2, input integer l3) ;
        $display(" %0s %9d %8d          %4d  %4d  %4d  %4d", name, checks, errors, l0, l1, l2, l3) ;
    endtask

endmodule


// Post-synthesis simulation of MCycle (Task 3), for comparing the two multipliers on the synthesized netlist.
// 1. Settings > Synthesis > More Options: -generic width=32 -generic RADIX4_BOOTH=1   (or 0 for the original)
//    (or Settings > General > Generics/Parameters), and set MCycle as the top module. Run Synthesis.
// 2. Set BOOTH below to the same value, set test_MCycle_postsynth as the simulation top, then
//    Run Simulation > Run Post-Synthesis Functional (or Timing) Simulation, "run all".
// It checks the results and the cycle count of every operation, and prints the cycles taken.
module test_MCycle_postsynth ;
    localparam BOOTH = 1 ;  // must match RADIX4_BOOTH used for synthesis
    wire done ;
    mcycle_tester #(.W(32), .BOOTH(BOOTH), .EXHAUSTIVE(0), .NRANDOM(500), .SEED(77), .NETLIST(1)) t (.finished(done)) ;
    initial begin
        wait( done ) ;
        #1 ;
        $display("") ;
        $display("==================================================================================") ;
        $display(" MCycle netlist (width 32, RADIX4_BOOTH = %0d): %0d checks, %0d errors", BOOTH, t.checks, t.errors) ;
        $display(" cycles: signed mul %0d, unsigned mul %0d, signed div %0d, unsigned div %0d",
                 t.lat_seen[0], t.lat_seen[1], t.lat_seen[2], t.lat_seen[3]) ;
        $display(" %0s", (t.errors == 0) ? "PASSED" : "FAILED") ;
        $display("==================================================================================") ;
        $finish ;
    end
endmodule


// Drives one MCycle instance through all of the tests described above.
module mcycle_tester #(
        parameter W = 4,            // MCycle width
        parameter BOOTH = 1,        // MCycle RADIX4_BOOTH
        parameter EXHAUSTIVE = 1,   // 1: every operand pair (only sensible for W <= 8)
        parameter NRANDOM = 0,      // random operand pairs per operation (in addition)
        parameter SEED = 1,
        parameter NETLIST = 0       // 1: the DUT is a synthesized netlist (post-synthesis simulation)
    )(
        output reg finished
    );

    // DECLARE INPUT SIGNALs
    reg CLK = 0 ;
    reg RESET = 0 ;
    reg Start = 0 ;
    reg [1:0] MCycleOp = 0 ;
    reg [W-1:0] Operand1 = 0 ;
    reg [W-1:0] Operand2 = 0 ;

    // DECLARE OUTPUT SIGNALs
    wire [W-1:0] Result1 ;
    wire [W-1:0] Result2 ;
    wire Busy ;

    // INSTANTIATE DEVICE/UNIT UNDER TEST (DUT/UUT)
    // A synthesized netlist has no parameters left (they were fixed at synthesis), so the
    // post-synthesis testbench instantiates it without overriding them.
    generate
        if( NETLIST ) begin : g_netlist
            MCycle dut( CLK, RESET, Start, MCycleOp, Operand1, Operand2, Result1, Result2, Busy ) ;
        end
        else begin : g_rtl
            MCycle #(.width(W), .RADIX4_BOOTH(BOOTH)) dut(
                CLK,
                RESET,
                Start,
                MCycleOp,
                Operand1,
                Operand2,
                Result1,
                Result2,
                Busy
                ) ;
        end
    endgenerate

    // GENERATE CLOCK
    always begin
        #5 CLK = ~CLK ; // invert CLK every 5 time units
    end

    localparam [W-1:0] MIN_S = {1'b1, {(W-1){1'b0}}} ; // most negative signed value
    localparam [W-1:0] MAX_S = {1'b0, {(W-1){1'b1}}} ; // most positive signed value
    localparam [W-1:0] ONES  = {W{1'b1}} ;             // -1

    integer checks = 0 ;
    integer errors = 0 ;
    integer lat_seen [0:3] ;    // cycles taken by each operation (the last value seen)
    integer seed = SEED ;
    integer n_ops = 0 ;         // operations issued, used to vary the way they are issued
    integer i, j, k ;

    reg [W-1:0] corner [0:9] ;

    // Expected cycles: iterations + 1 (the cycle in which Busy falls and the result is written back)
    function integer expected_latency(input [1:0] op) ;
        begin
            case(op)
                2'b00:   expected_latency = BOOTH ? W/2 + 2 : 2*W + 1 ;  // radix-4 Booth: W/2+1 iterations
                2'b01:   expected_latency = BOOTH ? W/2 + 2 : W + 1 ;
                default: expected_latency = W + 1 ;                    // division: one quotient bit per cycle
            endcase
        end
    endfunction

    // Reference results
    task reference(input [1:0] op, input [W-1:0] a, input [W-1:0] b, output [W-1:0] r1, output [W-1:0] r2) ;
        reg [2*W-1:0] p ;
        begin
            case(op)
                2'b00: begin p = $signed(a) * $signed(b) ; r1 = p[W-1:0] ; r2 = p[2*W-1:W] ; end
                2'b01: begin p = a * b ;                   r1 = p[W-1:0] ; r2 = p[2*W-1:W] ; end
                2'b10: begin
                    if( b == 0 )                          begin r1 = ONES ;  r2 = a ; end
                    else if( a == MIN_S && b == ONES )    begin r1 = MIN_S ; r2 = 0 ; end
                    else begin
                        r1 = $signed(a) / $signed(b) ;   // Verilog rounds towards zero, like RISC-V
                        r2 = $signed(a) % $signed(b) ;   // and the remainder takes the dividend's sign
                    end
                end
                2'b11: begin
                    if( b == 0 ) begin r1 = ONES ; r2 = a ; end
                    else         begin r1 = a / b ; r2 = a % b ; end
                end
            endcase
        end
    endtask

    // Issue one operation and check it.
    // Called just after a negedge, with the unit idle (state IDLE). Returns just after the negedge of
    // the following idle cycle, with Start still 1 (back to back) or 0 (gap = 1).
    task run_op(input [1:0] op, input [W-1:0] a, input [W-1:0] b, input gap, input scramble) ;
        reg [W-1:0] e1, e2 ;
        integer cycles ;
        begin
            reference(op, a, b, e1, e2) ;
            MCycleOp = op ;
            Operand1 = a ;
            Operand2 = b ;
            Start = 1'b1 ;
            #1 ;
            checks = checks + 1 ;
            if( ~Busy ) begin
                errors = errors + 1 ;
                if( errors <= 10 ) $display("[W=%0d] ERROR t=%0t: Busy did not rise with Start (op %b)", W, $time, op) ;
            end

            cycles = 1 ;                          // the cycle in which Start rose
            @(posedge CLK) ;
            @(negedge CLK) ;
            while( Busy ) begin
                cycles = cycles + 1 ;
                if( scramble ) begin              // the unit must not look at the operands again
                    Operand1 = $random(seed) ;
                    Operand2 = $random(seed) ;
                end
                @(posedge CLK) ;
                @(negedge CLK) ;
            end
            cycles = cycles + 1 ;                 // this cycle: Busy low, result being written back
            lat_seen[op] = cycles ;

            checks = checks + 1 ;
            if( Result1 !== e1 || Result2 !== e2 || cycles != expected_latency(op) ) begin
                errors = errors + 1 ;
                if( errors <= 10 )
                    $display("[W=%0d B=%0d] ERROR op %b  a=%h b=%h : got R2=%h R1=%h in %0d cycles, expected R2=%h R1=%h in %0d cycles",
                             W, BOOTH, op, a, b, Result2, Result1, cycles, e2, e1, expected_latency(op)) ;
            end

            if( gap ) Start = 1'b0 ;
            @(negedge CLK) ;                      // next cycle: the unit is idle again
            if( gap ) begin                       // results must be held while idle
                checks = checks + 1 ;
                if( Busy || Result1 !== e1 || Result2 !== e2 ) begin
                    errors = errors + 1 ;
                    if( errors <= 10 ) $display("[W=%0d] ERROR t=%0t: results not held / Busy while idle (op %b)", W, $time, op) ;
                end
            end
            n_ops = n_ops + 1 ;
        end
    endtask

    // Vary how the next operation is issued
    task issue(input [1:0] op, input [W-1:0] a, input [W-1:0] b) ;
        begin
            run_op(op, a, b, (n_ops % 3 == 0), (n_ops % 2 == 0)) ;
        end
    endtask

    initial begin
        finished = 1'b0 ;
        for( k = 0 ; k < 4 ; k = k + 1 ) lat_seen[k] = 0 ;

        corner[0] = 0 ;        corner[1] = 1 ;          corner[2] = ONES ;     corner[3] = 2 ;
        corner[4] = ONES - 1 ; corner[5] = MIN_S ;      corner[6] = MAX_S ;    corner[7] = MIN_S + 1 ;
        corner[8] = {W/2{2'b01}} ;                      corner[9] = {W/2{2'b10}} ;

        // reset first
        RESET = 1'b1 ;
        @(negedge CLK) ;
        @(negedge CLK) ;
        RESET = 1'b0 ;
        @(negedge CLK) ;

        // Reset in the middle of an operation: Busy must drop, and the next operation must still be right
        MCycleOp = 2'b10 ; Operand1 = MAX_S ; Operand2 = 3 ; Start = 1'b1 ;
        @(negedge CLK) ; @(negedge CLK) ;
        RESET = 1'b1 ; Start = 1'b0 ;
        #1 ;
        checks = checks + 1 ;
        if( Busy ) begin errors = errors + 1 ; $display("[W=%0d] ERROR: Busy still high during reset", W) ; end
        @(negedge CLK) ;
        RESET = 1'b0 ;
        @(negedge CLK) ;

        for( k = 0 ; k < 4 ; k = k + 1 ) begin
            if( EXHAUSTIVE ) begin
                for( i = 0 ; i < (1 << W) ; i = i + 1 )
                    for( j = 0 ; j < (1 << W) ; j = j + 1 )
                        issue(k, i, j) ;
            end
            else begin
                for( i = 0 ; i < 10 ; i = i + 1 )
                    for( j = 0 ; j < 10 ; j = j + 1 )
                        issue(k, corner[i], corner[j]) ;
            end
            for( i = 0 ; i < NRANDOM ; i = i + 1 )
                issue(k, $random(seed), $random(seed)) ;
        end

        // A few mixed operations back to back (like consecutive mul / div / divu instructions)
        for( i = 0 ; i < 40 ; i = i + 1 )
            run_op(i % 4, $random(seed), $random(seed) | 1, 1'b0, 1'b0) ;

        Start = 1'b0 ;
        finished = 1'b1 ;
    end

endmodule
