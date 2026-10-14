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

/* AI assistance declaration (required by the CG3207 lab manual):
	Tool   : Claude (Anthropic), model Claude Opus 5.5, via claude.ai, 30 Sep 2026
	Prompts: "help edit the code as necessary as required in the rars programming guide for this lab"
	         "can you design a demo where we can validate the checksum values side by side with the
	          rars code to show that they are the same when the assembly program is run"
	         (given together with test.asm, the Assignment 2 manual and the RARS programming guide)
	Changes: stimuli and self-checking for the Assignment 2 demo program (test.asm) instead of DIP_to_LED.
*/

// Self-checking testbench for test.asm. Needs the AA_IROM.mem / AA_DMEM.mem generated from test.asm.
//
// Switches: SW11-SW0 = input number, SW15-SW12 = which of the 16 trace entries the 7-segment display shows.
// The program loops forever; one pass takes 224 clock cycles. After changing the switches, the display
// is correct within 2 passes (the pass that was running still used the old switch value).
//
// Every expected value below is the word RARS writes to the 'trace' table (Data Segment window,
// 0x10010020 - 0x1001005C) for the same input, so this testbench repeats the side-by-side comparison.
// LED_OUT must always be 0x65. Finally a push button is pressed, and the program must stop at
// 'halt' (instruction word 104 = 0x68).
//
// Run it with "run all" (it takes about 115 us of simulated time and stops by itself).

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

	localparam CLK_PERIOD   = 10;		// ns, see the clock generator below
	localparam PASS_CYCLES  = 224;		// clock cycles for one pass of the main loop in test.asm
	localparam WAIT_TIME    = (2 * PASS_CYCLES + 20) * CLK_PERIOD;
	localparam EXPECTED_LED = 8'h65;
	localparam HALT_INDEX   = 7'h68;	// word index of 'halt: j halt' = LED_PC value when stopped

	integer pass_count = 0;
	integer fail_count = 0;

	// Set the switches, wait for the program to pick them up, and compare both outputs
	task check(input [15:0] dip_value, input [31:0] expected_sevenseg, input [8*40-1:0] what);
	begin
		DIP = dip_value;
		#(WAIT_TIME);
		if (SEVENSEGHEX === expected_sevenseg && LED_OUT === EXPECTED_LED) begin
			pass_count = pass_count + 1;
			$display("[%0t] PASS: SW=%h  view %h  input %h  7-seg=%h  LED=%h  %0s",
				$time, dip_value, dip_value[15:12], dip_value[11:0], SEVENSEGHEX, LED_OUT, what);
		end
		else begin
			fail_count = fail_count + 1;
			$display("[%0t] FAIL: SW=%h  view %h  input %h  7-seg=%h (expected %h)  LED=%h (expected %h)  %0s",
				$time, dip_value, dip_value[15:12], dip_value[11:0], SEVENSEGHEX, expected_sevenseg,
				LED_OUT, EXPECTED_LED, what);
		end
	end
	endtask

	// STIMULI
    initial
    begin
	RESET = 1; #10; RESET = 0; //hold reset state for 10 ns.

	// 1) Input 000: all 16 trace entries, as RARS shows them at 0x10010020 - 0x1001005C
	check(16'h0000, 32'h0717E0E2, "0: final checksum");
	check(16'h1000, 32'h00000000, "1: input number");
	check(16'h2000, 32'h005CA000, "2: checksum after case 1");
	check(16'h3000, 32'hDFA8A001, "3: checksum after case 2");
	check(16'h4000, 32'h4E5AA001, "4: checksum after case 3");
	check(16'h5000, 32'hB1BEA002, "5: checksum after case 4");
	check(16'h6000, 32'h005595A5, "6: branch signature");
	check(16'h7000, 32'h0055C065, "7: LED value (low byte)");
	check(16'h8000, 32'h209FA25E, "8: mix() via jal");
	check(16'h9000, 32'hD549A282, "9: mix() via jalr");
	check(16'hA000, 32'h00400108, "A: jal return address");
	check(16'hB000, 32'h00400124, "B: jalr return address");
	check(16'hC000, 32'h10010000, "C: auipc table address");
	check(16'hD000, 32'hFFFF0000, "D: lui MMIO base");
	check(16'hE000, 32'hF8001000, "E: sra by 4");
	check(16'hF000, 32'h08001000, "F: srl by 4");

	// 2) Final checksum (view 0) for other inputs
	check(16'h0001, 32'h0717E58B, "0: final checksum");
	check(16'h0123, 32'h071CF464, "0: final checksum");
	check(16'h0800, 32'h025DE4D2, "0: final checksum");
	check(16'h0A5C, 32'h024E71CE, "0: final checksum");
	check(16'h0FFF, 32'h0282F143, "0: final checksum");

	// 3) Other entries for other inputs
	check(16'h1A5C, 32'h00000A5C, "1: input number");
	check(16'h5A5C, 32'hB1B52A02, "5: checksum after case 4");
	check(16'h8FFF, 32'h2617A3B4, "8: mix() via jal");
	check(16'hE800, 32'hF8001080, "E: sra by 4");
	check(16'hF123, 32'h08001012, "F: srl by 4");

	// 4) Press BTNC: the program must leave the loop and stay at 'halt'
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