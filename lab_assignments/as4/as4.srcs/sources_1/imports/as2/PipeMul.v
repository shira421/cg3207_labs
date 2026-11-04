`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Module Name: PipeMulE, PipeMulM
-- Project Name: CG3207 Project, Assignment 4
-- Description: Fully pipelined 32 x 32 -> 64 multiplier, woven into the E and M stages.
--
--   E  (PipeMulE)  radix-4 Booth recoding -> 17 partial products + 1 row of "+1" bits
--                  -> 4 levels of 3:2 carry-save adders -> 4 rows, into the E/M register
--   M  (PipeMulM)  2 more levels of 3:2 carry-save adders -> 2 rows -> ONE 64-bit adder
--                  -> funnel select: result = product[k+31 : k]     , into the M/W register
--
--   so every multiply is in flight for exactly the E and M stages, like a load:
--     - a new multiply can start every cycle (independent multiplies never stall),
--     - an instruction that needs the result right away waits 1 cycle (load-use rule),
--       then gets it forwarded from W.
--   (The Assignment 3 MCycle took 33 cycles and froze the whole pipeline for each one.)
--
--   k selects the 32 bits of the 64-bit product that are written back:
--     mul       k = 0     (low word)
--     mulh/mulhu k = 32   (high word)
--     mulsr     k = 0..31 (custom fixed-point multiply: (rs1 * rs2) >> k, binary point at bit k)
--
--   Signed = 1: rs1, rs2 signed (mul, mulh, mulsr). Signed = 0: unsigned (mulhu).
--
--   How it stays inside the rules: no '*' anywhere. The partial products are multiplexers and
--   XORs, the 3:2 compressors are AND/OR/XOR (no '+'), and the only '+' is the final 64-bit
--   carry-propagate add in PipeMulM (multiplication is listed as an allowed exception).
--
--   Booth radix-4: the multiplier B (extended to 34 bits) is read 2 bits at a time with one
--   bit of overlap: digit_i = -2*b[2i+1] + b[2i] + b[2i-1]  in {-2,-1,0,+1,+2}, so
--   A*B = sum_i digit_i * A * 4^i: 17 partial products instead of 32. A negative digit is
--   written as ~(|digit|*A) << 2i plus a 1 at bit 2i (two's complement), the 1s going into an
--   extra row. Everything is computed modulo 2^64, which gives the exact 64-bit product for
--   both signed and unsigned operands.
----------------------------------------------------------------------------------
*/

module PipeMulE(
    input [31:0] A,
    input [31:0] B,
    input Signed,
    output [63:0] R0, R1, R2, R3	// carry-save rows: R0 + R1 + R2 + R3 = A * B (mod 2^64)
);
    wire [33:0] A34 = Signed ? {A[31], A[31], A} : {2'b00, A} ;
    wire [33:0] B34 = Signed ? {B[31], B[31], B} : {2'b00, B} ;
    wire [63:0] A64 = {{30{A34[33]}}, A34} ;
    wire [63:0] A64x2 = {A64[62:0], 1'b0} ;
    wire [34:0] Bx = {B34, 1'b0} ;		// Bx[j+1] = b[j], Bx[0] = b[-1] = 0

    // 17 partial products + the row of +1s for the negative digits = 18 rows
    wire [63:0] row [0:17] ;

    genvar i ;
    generate
        for( i = 0 ; i < 17 ; i = i + 1 ) begin : booth
            wire [2:0] t = Bx[2*i+2 : 2*i] ;			// {b[2i+1], b[2i], b[2i-1]}
            wire one = t[1] ^ t[0] ;				// digit is +-1
            wire two = (t == 3'b011) || (t == 3'b100) ;	// digit is +-2
            wire neg = t[2] && !(t[1] && t[0]) ;		// digit is negative (100, 101, 110)
            wire [63:0] mag = one ? A64 : (two ? A64x2 : 64'd0) ;
            wire [63:0] pp  = mag ^ {64{neg}} ;			// ones' complement if negative
            assign row[i] = pp << (2*i) ;
        end
    endgenerate

    // the +1 of each negative digit's two's complement, at bit 2i
    wire [63:0] plus1 ;
    generate
        for( i = 0 ; i < 64 ; i = i + 1 ) begin : plus1_bits
            if( (i % 2 == 0) && (i < 34) )
                assign plus1[i] = booth[i/2].neg ;
            else
                assign plus1[i] = 1'b0 ;
        end
    endgenerate
    assign row[17] = plus1 ;

    // 3:2 carry-save adder: x + y + z = s + c, no carries propagate
    function [127:0] csa ;
        input [63:0] x, y, z ;
        reg [63:0] s, c ;
        begin
            s = x ^ y ^ z ;
            c = ((x & y) | (x & z) | (y & z)) << 1 ;
            csa = {c, s} ;
        end
    endfunction

    // level 1: 18 -> 12
    wire [63:0] l1 [0:11] ;
    generate
        for( i = 0 ; i < 6 ; i = i + 1 ) begin : lev1
            assign {l1[2*i+1], l1[2*i]} = csa(row[3*i], row[3*i+1], row[3*i+2]) ;
        end
    endgenerate
    // level 2: 12 -> 8
    wire [63:0] l2 [0:7] ;
    generate
        for( i = 0 ; i < 4 ; i = i + 1 ) begin : lev2
            assign {l2[2*i+1], l2[2*i]} = csa(l1[3*i], l1[3*i+1], l1[3*i+2]) ;
        end
    endgenerate
    // level 3: 8 -> 6 (two groups of 3, two rows pass through)
    wire [63:0] l3 [0:5] ;
    assign {l3[1], l3[0]} = csa(l2[0], l2[1], l2[2]) ;
    assign {l3[3], l3[2]} = csa(l2[3], l2[4], l2[5]) ;
    assign l3[4] = l2[6] ;
    assign l3[5] = l2[7] ;
    // level 4: 6 -> 4
    assign {R1, R0} = csa(l3[0], l3[1], l3[2]) ;
    assign {R3, R2} = csa(l3[3], l3[4], l3[5]) ;
endmodule


module PipeMulM(
    input [63:0] R0, R1, R2, R3,
    input [5:0] K,			// 0..32: which 32 bits of the product
    output [31:0] Result
);
    function [127:0] csa ;
        input [63:0] x, y, z ;
        reg [63:0] s, c ;
        begin
            s = x ^ y ^ z ;
            c = ((x & y) | (x & z) | (y & z)) << 1 ;
            csa = {c, s} ;
        end
    endfunction

    wire [63:0] a0, a1, b0, b1 ;
    assign {a1, a0} = csa(R0, R1, R2) ;	// level 5: 4 -> 3 (a0, a1, R3)
    assign {b1, b0} = csa(a0, a1, R3) ;	// level 6: 3 -> 2

    wire [63:0] Product = b0 + b1 ;	// the one carry-propagate adder

    // funnel select (a 64 -> 32 bit shifter, inside the multiply unit)
    wire [95:0] wide = {32'd0, Product} ;
    assign Result = wide[K +: 32] ;
endmodule
