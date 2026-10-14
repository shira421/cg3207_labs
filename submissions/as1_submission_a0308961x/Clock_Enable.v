`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// This module is to generate an enable signal for different display frequency based on pushbuttons
// (c) Gu Jing, ECE, NUS
//////////////////////////////////////////////////////////////////////////////////

module Clock_Enable #(
    //   26'h3FFFFFF -> 67,108,864 clk cycles @100MHz = 0.671 s (~1.5 Hz)
    //   26'h0FFFFFF -> 16,777,216 clk cycles @100MHz = 0.168 s (~6 Hz)
    //   ratio is 4
    parameter THRESH_SLOW = 26'h3FFFFFF,
    parameter THRESH_FAST = 26'h0FFFFFF
)(
    input clk,          // fundamental clock 100 MHz
    input btnU,         // button BTNU for 4Hz speed
    input btnC,         // button BTNC for pause
    output reg enable); // output signal used to enable the reading of next memory data
    
wire [25:0] threshold = btnU ? THRESH_FAST : THRESH_SLOW;
reg [25:0] counter;

initial
begin
    counter = 0;
    enable  = 0;
end

always @(posedge clk)
begin
    if (counter >= threshold)
    begin
        counter <= 0;
        enable  <= ~btnC;   // btnC held -> never pulse -> display pauses
    end
    else
    begin
        counter <= counter + 1;
        enable  <= 1'b0;    // enable is high for exactly one clk cycle
    end
end

endmodule