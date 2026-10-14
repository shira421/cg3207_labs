`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Top level module
// This project displays the memory contents on both LEDs (16 bits by 16 bits) and 
// 7-segments (32 bits by 32 bits) with a frequency chosen by BTNU and BTNC.   
// (c) Gu Jing, ECE, NUS
//////////////////////////////////////////////////////////////////////////////////


module Top #(
    parameter THRESH_SLOW = 26'h3FFFFFF,
    parameter THRESH_FAST = 26'h0FFFFFF
)(
    input clk,              // fundamental clock 100 MHz
    input btnU,             // button BTNU for 4Hz speed
    input btnC,             // button BTNC for pause
    output [15:0] led,      // 16 LEDs to display upper or lower 16 bits of memory data
    output dp,              // dot point of 7-segments
    output [7:0] anode,     // anodes of 7-segments
    output [6:0] cathode    // cathodes of 7-segments
    );

wire enable; 			// enable signal to read the next memory content
wire upper_lower;   	// 1-bit signal used between modules to indicate either upper or lower 16-bit contents is displaying on LEDs, 
						// upper_lower = 1 to display upper half of the Memory data
wire [31:0] data;   // entire 32-bit contents displaying on LEDs and 7-segments, can be deleted if 7-segments are not implemented
    
// Choose 1hz or 4hz display frequency based on BTNU and BTNC readings, using given module Clock_Enable.v
Clock_Enable #(
    .THRESH_SLOW (THRESH_SLOW),
    .THRESH_FAST (THRESH_FAST)
) Clock_Enable1 (
    .clk    (clk),
    .btnU   (btnU),
    .btnC   (btnC),
    .enable (enable)
);

// Fetch memory content, using given module Get_MEM.v
Get_MEM Get_MEM1 (
    .clk         (clk),
    .enable      (enable),
    .data        (data),
    .upper_lower (upper_lower)
);

// Displays the 32-bit memory data on 7-segments, using given module Seven_Seg.v
// This module can be deleted if students do not want to implement the 7-segment display
Seven_Seg Seven_Seg1 (
    .clk     (clk),
    .data    (data),
    .dp      (dp),
    .anode   (anode),
    .cathode (cathode)
);

// split the 32-bit Memory data using a multiplexer to display on led 
assign led = upper_lower ? data[31:16] : data[15:0];

endmodule
