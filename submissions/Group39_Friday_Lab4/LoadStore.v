`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Module Name: StoreAlign, LoadExtend
-- Project Name: CG3207 Project, Assignment 4
-- Description: Byte and half-word loads and stores (lb, lh, lbu, lhu, sb, sh),
--              as described in "Implement half-word/byte load and store" of the lab manual.
--
--   StoreAlign (M stage): places the byte / half-word in the byte lane(s) of the word that the
--   address selects, and sets only those bits of MemWrite_out. The data is simply repeated in
--   every lane (e.g. sb of 0xAB gives 0xABABABAB); the byte enables pick the lane that counts.
--
--   LoadExtend (W stage): picks the byte / half-word out of the word read from memory and
--   sign- or zero-extends it.
--
--   Only aligned accesses are supported: half-words at even addresses, words at multiples of 4.
--   Funct3 = size: 000 byte, 001 half-word, 010 word; bit 2 set = unsigned (lbu, lhu).
--   These are multiplexers only: no 32-bit arithmetic is done outside the ALU / MCycle.
----------------------------------------------------------------------------------
*/

module StoreAlign(
    input MemWrite,		// the instruction in M is a store
    input [2:0] Funct3,		// 000 sb, 001 sh, 010 sw
    input [1:0] Addr,		// lowest two bits of the address
    input [31:0] WriteData,	// rs2
    output reg [3:0] MemWrite_out,	// byte enables, bit i = byte lane i (bits 8i+7 : 8i)
    output reg [31:0] WriteData_out
);
    always@(*) begin
        case( Funct3[1:0] )
            2'b00: begin	// sb
                WriteData_out = {4{WriteData[7:0]}} ;
                case( Addr )
                    2'b00:   MemWrite_out = 4'b0001 ;
                    2'b01:   MemWrite_out = 4'b0010 ;
                    2'b10:   MemWrite_out = 4'b0100 ;
                    default: MemWrite_out = 4'b1000 ;
                endcase
            end
            2'b01: begin	// sh
                WriteData_out = {2{WriteData[15:0]}} ;
                MemWrite_out  = Addr[1] ? 4'b1100 : 4'b0011 ;
            end
            default: begin	// sw
                WriteData_out = WriteData ;
                MemWrite_out  = 4'b1111 ;
            end
        endcase
        if( !MemWrite )
            MemWrite_out = 4'b0000 ;
    end
endmodule


module LoadExtend(
    input [2:0] Funct3,		// 000 lb, 001 lh, 010 lw, 100 lbu, 101 lhu
    input [1:0] Addr,
    input [31:0] ReadData_in,	// the whole word containing the data
    output reg [31:0] ReadData
);
    reg [7:0]  byte_sel ;
    reg [15:0] half_sel ;

    always@(*) begin
        case( Addr )
            2'b00:   byte_sel = ReadData_in[7:0] ;
            2'b01:   byte_sel = ReadData_in[15:8] ;
            2'b10:   byte_sel = ReadData_in[23:16] ;
            default: byte_sel = ReadData_in[31:24] ;
        endcase
        half_sel = Addr[1] ? ReadData_in[31:16] : ReadData_in[15:0] ;

        case( Funct3 )
            3'b000:  ReadData = { {24{byte_sel[7]}},  byte_sel } ;	// lb
            3'b001:  ReadData = { {16{half_sel[15]}}, half_sel } ;	// lh
            3'b100:  ReadData = { 24'd0, byte_sel } ;			// lbu
            3'b101:  ReadData = { 16'd0, half_sel } ;			// lhu
            default: ReadData = ReadData_in ;				// lw
        endcase
    end
endmodule
