`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
--	(c) Rajesh Panicker
--	License terms :
--	You are free to use this code as long as you
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept the responsibility to ensure that your implementation does not violate any intellectual property of ARM Holdings or other entities.
--		(iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(v) send an email to rajesh.panicker@ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(vi) retain this notice in this file or any files derived from this.
----------------------------------------------------------------------------------
*/

/*
	Changes: stimuli and self-checking for the Assignment 2 demo program (test.asm) instead of DIP_to_LED.
*/

// Self-checking testbench for test.asm. Needs the AA_IROM.mem / AA_DMEM.mem generated from test.asm.
//
// The program loops forever: read DIP -> compute -> write LED[7:0] and the 7-segment display.
// One pass of the loop takes 195 clock cycles, so after changing the switches we wait 3 passes
// (the pass that was running when the switches changed still uses the old value).
//
// Expected values come from running test.asm in RARS with the same switch values:
//   LED_OUT     = 0x65 for every switch setting (summary of all 24 branch outcomes)
//   SEVENSEGHEX = the checksum s4, which depends on the switches (table below)
// Finally a push button is pressed, and the program must stop at 'halt' (instruction word 81).

module test_Wrapper #(
	   parameter N_LEDs_OUT	= 8,
	   parameter N_DIPs		= 16,
	   parameter N_PBs		= 3
	)
	(
	);

	// Signals for the Unit Under Test (UUT)
	reg  [N_DIPs-1:0] DIP = 0;
	reg  [N_PBs-1:0] PB = 0;
	wire [N_LEDs_OUT-1:0] LED_OUT;
	wire [6:0] LED_PC;
	wire [31:0] SEVENSEGHEX;
	wire [7:0] UART_TX;
	reg  UART_TX_ready = 0;
	wire UART_TX_valid;
	reg  [7:0] UART_RX = 0;
	reg  UART_RX_valid = 0;
	wire UART_RX_ack;
	wire OLED_Write;
	wire [6:0] OLED_Col;
	wire [5:0] OLED_Row;
	wire [23:0] OLED_Data;
	reg [31:0] ACCEL_Data = 0;
	wire ACCEL_DReady;
	reg  RESET = 0;
	reg  CLK = 0;

	// Instantiate UUT
    Wrapper dut(DIP, PB, LED_OUT, LED_PC, SEVENSEGHEX, UART_TX, UART_TX_ready, UART_TX_valid, UART_RX, UART_RX_valid, UART_RX_ack, OLED_Write, OLED_Col, OLED_Row, OLED_Data, ACCEL_Data, ACCEL_DReady, RESET, CLK) ;

	localparam CLK_PERIOD  = 10;		// ns, see the clock generator below
	localparam PASS_CYCLES = 195;		// clock cycles for one pass of the main loop in test.asm
	localparam WAIT_TIME   = 3 * PASS_CYCLES * CLK_PERIOD;
	localparam EXPECTED_LED = 8'h65;
	localparam HALT_INDEX   = 7'd81;	// word index of 'halt: j halt' = LED_PC value when stopped

	integer pass_count = 0;
	integer fail_count = 0;

	// Set the switches, wait for the program to pick them up, and compare both outputs
	task check_switches(input [15:0] dip_value, input [31:0] expected_sevenseg);
	begin
		DIP = dip_value;
		#(WAIT_TIME);
		if (SEVENSEGHEX === expected_sevenseg && LED_OUT === EXPECTED_LED) begin
			pass_count = pass_count + 1;
			$display("[%0t] PASS: DIP=%h  7-seg=%h  LED=%h", $time, dip_value, SEVENSEGHEX, LED_OUT);
		end
		else begin
			fail_count = fail_count + 1;
			$display("[%0t] FAIL: DIP=%h  7-seg=%h (expected %h)  LED=%h (expected %h)",
				$time, dip_value, SEVENSEGHEX, expected_sevenseg, LED_OUT, EXPECTED_LED);
		end
	end
	endtask

	// STIMULI
    initial
    begin
	RESET = 1; #10; RESET = 0; //hold reset state for 10 ns.

	// switch value, expected 7-segment value (from RARS)
	check_switches(16'h0000, 32'h0717E0E2);		// all switches OFF
	check_switches(16'hFFFF, 32'h022D006D);		// all switches ON
	check_switches(16'hA5C3, 32'h05BCB628);
	check_switches(16'h1234, 32'h00CE4A74);
	check_switches(16'h8001, 32'h0019F43D);
	check_switches(16'h001F, 32'h071864C2);

	// Press BTNC: the program must leave the loop and stay at 'halt'
	PB = 3'b010;
	#(WAIT_TIME);
	PB = 3'b000;
	#(10 * CLK_PERIOD);
	if (LED_PC === HALT_INDEX) begin
		#(20 * CLK_PERIOD);			// still there later?
		if (LED_PC === HALT_INDEX) begin
			pass_count = pass_count + 1;
			$display("[%0t] PASS: push button stopped the program at halt (LED_PC=%h)", $time, LED_PC);
		end
		else begin
			fail_count = fail_count + 1;
			$display("[%0t] FAIL: program left halt (LED_PC=%h)", $time, LED_PC);
		end
	end
	else begin
		fail_count = fail_count + 1;
		$display("[%0t] FAIL: program did not stop at halt (LED_PC=%h, expected %h)", $time, LED_PC, HALT_INDEX);
	end

	$display("\n=== %0d passed, %0d failed ===", pass_count, fail_count);
	if (fail_count == 0) $display("*** ALL TESTS PASSED ***\n");
	$finish;
    end

	// GENERATE CLOCK
    always
    begin
       #5 CLK = ~CLK ; // invert clk every 5 time units
    end

endmodule