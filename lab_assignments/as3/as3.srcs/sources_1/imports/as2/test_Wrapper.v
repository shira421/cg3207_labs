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
	Tool   : Claude (Anthropic), model Claude Opus 5.5, via claude.ai, 14 Oct 2026
	Prompt : "okay now can we complete tasks 1, 2 and 3 for assignment 3" (with the Assignment 3 manual,
	         MCycle.v and test_MCycle.v)
	Changes: stimuli and self-checking for the Assignment 3 demo program (test.asm).
	         Expected values were computed in Python with the RISC-V rules and agree with RARS
	         (the program's own self-check gives status = 0xFF when run in RARS).
*/

// Self-checking testbench for the Assignment 3 test.asm. Needs the AA_IROM.mem / AA_DMEM.mem generated
// from it (Wrapper.v: IROM_DEPTH_BITS = DMEM_DEPTH_BITS = 10).
//
//   1. The program's self-check must turn on all 8 LEDs (LED_OUT = 0xFF): every RV32M instruction gave the
//      expected result on all 16 test cases, including back-to-back and rd = rs1 / rs2.
//   2. SW15 = 0: for every test case (SW3-0) every view (SW7-4) is checked on the 7-segment display:
//      a, b, mul, mulh, mulhu, div, divu, rem, remu, the measured cycles of mul (18) and div (33), LED value.
//   3. SW15 = 1: own operands from SW14-8 / SW6-0, with BTNL / BTNC / BTNR choosing div / rem / divu.
//
// One pass of the display loop takes at most about 280 cycles, so each check waits 700 cycles after
// changing the switches. Run with "run all" (about 2 ms of simulated time); it stops by itself.

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
	localparam WAIT_TIME    = 700 * CLK_PERIOD;
	localparam EXPECTED_LED = 8'hFF;

	integer pass_count = 0;
	integer fail_count = 0;
	integer cycles = 0;

	// Set the switches, wait for the program to pick them up, and compare the display
	task check(input [15:0] dip_value, input [31:0] expected_sevenseg, input [8*44-1:0] what);
	begin
		DIP = dip_value;
		PB = 3'b000;
		#(WAIT_TIME);
		if (SEVENSEGHEX === expected_sevenseg && LED_OUT === EXPECTED_LED)
			pass_count = pass_count + 1;
		else begin
			fail_count = fail_count + 1;
			$display("[%0t] FAIL: SW=%h  7-seg=%h (expected %h)  LED=%h  %0s",
				$time, dip_value, SEVENSEGHEX, expected_sevenseg, LED_OUT, what);
		end
	end
	endtask

	// Own operands (SW15 = 1) with a push button held
	task check_live(input [15:0] dip_value, input [2:0] buttons, input [31:0] expected_sevenseg, input [8*44-1:0] what);
	begin
		DIP = dip_value;
		PB = buttons;
		#(WAIT_TIME);
		if (SEVENSEGHEX === expected_sevenseg)
			pass_count = pass_count + 1;
		else begin
			fail_count = fail_count + 1;
			$display("[%0t] FAIL: SW=%h PB=%b  7-seg=%h (expected %h)  %0s",
				$time, dip_value, buttons, SEVENSEGHEX, expected_sevenseg, what);
		end
		PB = 3'b000;
	end
	endtask

	// STIMULI
    initial
    begin
	RESET = 1; #10; RESET = 0; //hold reset state for 10 ns.

	// 1) Self-check of all 16 test cases: LED_OUT must become 0xFF
	while (LED_OUT !== EXPECTED_LED && cycles < 20000) begin
		#(CLK_PERIOD);
		cycles = cycles + 1;
	end
	if (LED_OUT === EXPECTED_LED) begin
		pass_count = pass_count + 1;
		$display("[%0t] PASS: self-check of all RV32M instructions done after %0d cycles, LED = %h", $time, cycles, LED_OUT);
	end
	else begin
		fail_count = fail_count + 1;
		$display("[%0t] FAIL: LED = %h after %0d cycles (expected %h). A 0 bit shows which instruction failed:",
			$time, LED_OUT, cycles, EXPECTED_LED);
		$display("          bit 0 mul, 1 mulh, 2 mulhu, 3 div, 4 divu, 5 rem, 6 remu, 7 all");
	end

	// 2) SW15 = 0: every view of every test case (SW7-4 = view, SW3-0 = case)
	// case 0: a = 7, b = 3
	check(16'h0000, 32'h00000007, "case 0: a (rs1)");
	check(16'h0010, 32'h00000003, "case 0: b (rs2)");
	check(16'h0020, 32'h00000015, "case 0: mul");
	check(16'h0030, 32'h00000000, "case 0: mulh");
	check(16'h0040, 32'h00000000, "case 0: mulhu");
	check(16'h0050, 32'h00000002, "case 0: div");
	check(16'h0060, 32'h00000002, "case 0: divu");
	check(16'h0070, 32'h00000001, "case 0: rem");
	check(16'h0080, 32'h00000001, "case 0: remu");
	check(16'h0090, 32'h00000012, "case 0: mul cycles");
	check(16'h00A0, 32'h00000021, "case 0: div cycles");
	check(16'h00B0, 32'h000000FF, "case 0: LED value");

	// case 1: a = -7, b = 3
	check(16'h0001, 32'hFFFFFFF9, "case 1: a (rs1)");
	check(16'h0011, 32'h00000003, "case 1: b (rs2)");
	check(16'h0021, 32'hFFFFFFEB, "case 1: mul");
	check(16'h0031, 32'hFFFFFFFF, "case 1: mulh");
	check(16'h0041, 32'h00000002, "case 1: mulhu");
	check(16'h0051, 32'hFFFFFFFE, "case 1: div");
	check(16'h0061, 32'h55555553, "case 1: divu");
	check(16'h0071, 32'hFFFFFFFF, "case 1: rem");
	check(16'h0081, 32'h00000000, "case 1: remu");
	check(16'h0091, 32'h00000012, "case 1: mul cycles");
	check(16'h00A1, 32'h00000021, "case 1: div cycles");
	check(16'h00B1, 32'h000000FF, "case 1: LED value");

	// case 2: a = 7, b = -3
	check(16'h0002, 32'h00000007, "case 2: a (rs1)");
	check(16'h0012, 32'hFFFFFFFD, "case 2: b (rs2)");
	check(16'h0022, 32'hFFFFFFEB, "case 2: mul");
	check(16'h0032, 32'hFFFFFFFF, "case 2: mulh");
	check(16'h0042, 32'h00000006, "case 2: mulhu");
	check(16'h0052, 32'hFFFFFFFE, "case 2: div");
	check(16'h0062, 32'h00000000, "case 2: divu");
	check(16'h0072, 32'h00000001, "case 2: rem");
	check(16'h0082, 32'h00000007, "case 2: remu");
	check(16'h0092, 32'h00000012, "case 2: mul cycles");
	check(16'h00A2, 32'h00000021, "case 2: div cycles");
	check(16'h00B2, 32'h000000FF, "case 2: LED value");

	// case 3: a = -7, b = -3
	check(16'h0003, 32'hFFFFFFF9, "case 3: a (rs1)");
	check(16'h0013, 32'hFFFFFFFD, "case 3: b (rs2)");
	check(16'h0023, 32'h00000015, "case 3: mul");
	check(16'h0033, 32'h00000000, "case 3: mulh");
	check(16'h0043, 32'hFFFFFFF6, "case 3: mulhu");
	check(16'h0053, 32'h00000002, "case 3: div");
	check(16'h0063, 32'h00000000, "case 3: divu");
	check(16'h0073, 32'hFFFFFFFF, "case 3: rem");
	check(16'h0083, 32'hFFFFFFF9, "case 3: remu");
	check(16'h0093, 32'h00000012, "case 3: mul cycles");
	check(16'h00A3, 32'h00000021, "case 3: div cycles");
	check(16'h00B3, 32'h000000FF, "case 3: LED value");

	// case 4: a = -2147483648, b = -1
	check(16'h0004, 32'h80000000, "case 4: a (rs1)");
	check(16'h0014, 32'hFFFFFFFF, "case 4: b (rs2)");
	check(16'h0024, 32'h80000000, "case 4: mul");
	check(16'h0034, 32'h00000000, "case 4: mulh");
	check(16'h0044, 32'h7FFFFFFF, "case 4: mulhu");
	check(16'h0054, 32'h80000000, "case 4: div");
	check(16'h0064, 32'h00000000, "case 4: divu");
	check(16'h0074, 32'h00000000, "case 4: rem");
	check(16'h0084, 32'h80000000, "case 4: remu");
	check(16'h0094, 32'h00000012, "case 4: mul cycles");
	check(16'h00A4, 32'h00000021, "case 4: div cycles");
	check(16'h00B4, 32'h000000FF, "case 4: LED value");

	// case 5: a = -2147483648, b = 1
	check(16'h0005, 32'h80000000, "case 5: a (rs1)");
	check(16'h0015, 32'h00000001, "case 5: b (rs2)");
	check(16'h0025, 32'h80000000, "case 5: mul");
	check(16'h0035, 32'hFFFFFFFF, "case 5: mulh");
	check(16'h0045, 32'h00000000, "case 5: mulhu");
	check(16'h0055, 32'h80000000, "case 5: div");
	check(16'h0065, 32'h80000000, "case 5: divu");
	check(16'h0075, 32'h00000000, "case 5: rem");
	check(16'h0085, 32'h00000000, "case 5: remu");
	check(16'h0095, 32'h00000012, "case 5: mul cycles");
	check(16'h00A5, 32'h00000021, "case 5: div cycles");
	check(16'h00B5, 32'h000000FF, "case 5: LED value");

	// case 6: a = 2147483647, b = 2147483647
	check(16'h0006, 32'h7FFFFFFF, "case 6: a (rs1)");
	check(16'h0016, 32'h7FFFFFFF, "case 6: b (rs2)");
	check(16'h0026, 32'h00000001, "case 6: mul");
	check(16'h0036, 32'h3FFFFFFF, "case 6: mulh");
	check(16'h0046, 32'h3FFFFFFF, "case 6: mulhu");
	check(16'h0056, 32'h00000001, "case 6: div");
	check(16'h0066, 32'h00000001, "case 6: divu");
	check(16'h0076, 32'h00000000, "case 6: rem");
	check(16'h0086, 32'h00000000, "case 6: remu");
	check(16'h0096, 32'h00000012, "case 6: mul cycles");
	check(16'h00A6, 32'h00000021, "case 6: div cycles");
	check(16'h00B6, 32'h000000FF, "case 6: LED value");

	// case 7: a = -1, b = -1
	check(16'h0007, 32'hFFFFFFFF, "case 7: a (rs1)");
	check(16'h0017, 32'hFFFFFFFF, "case 7: b (rs2)");
	check(16'h0027, 32'h00000001, "case 7: mul");
	check(16'h0037, 32'h00000000, "case 7: mulh");
	check(16'h0047, 32'hFFFFFFFE, "case 7: mulhu");
	check(16'h0057, 32'h00000001, "case 7: div");
	check(16'h0067, 32'h00000001, "case 7: divu");
	check(16'h0077, 32'h00000000, "case 7: rem");
	check(16'h0087, 32'h00000000, "case 7: remu");
	check(16'h0097, 32'h00000012, "case 7: mul cycles");
	check(16'h00A7, 32'h00000021, "case 7: div cycles");
	check(16'h00B7, 32'h000000FF, "case 7: LED value");

	// case 8: a = 0, b = 5
	check(16'h0008, 32'h00000000, "case 8: a (rs1)");
	check(16'h0018, 32'h00000005, "case 8: b (rs2)");
	check(16'h0028, 32'h00000000, "case 8: mul");
	check(16'h0038, 32'h00000000, "case 8: mulh");
	check(16'h0048, 32'h00000000, "case 8: mulhu");
	check(16'h0058, 32'h00000000, "case 8: div");
	check(16'h0068, 32'h00000000, "case 8: divu");
	check(16'h0078, 32'h00000000, "case 8: rem");
	check(16'h0088, 32'h00000000, "case 8: remu");
	check(16'h0098, 32'h00000012, "case 8: mul cycles");
	check(16'h00A8, 32'h00000021, "case 8: div cycles");
	check(16'h00B8, 32'h000000FF, "case 8: LED value");

	// case 9: a = 5, b = 0
	check(16'h0009, 32'h00000005, "case 9: a (rs1)");
	check(16'h0019, 32'h00000000, "case 9: b (rs2)");
	check(16'h0029, 32'h00000000, "case 9: mul");
	check(16'h0039, 32'h00000000, "case 9: mulh");
	check(16'h0049, 32'h00000000, "case 9: mulhu");
	check(16'h0059, 32'hFFFFFFFF, "case 9: div");
	check(16'h0069, 32'hFFFFFFFF, "case 9: divu");
	check(16'h0079, 32'h00000005, "case 9: rem");
	check(16'h0089, 32'h00000005, "case 9: remu");
	check(16'h0099, 32'h00000012, "case 9: mul cycles");
	check(16'h00A9, 32'h00000021, "case 9: div cycles");
	check(16'h00B9, 32'h000000FF, "case 9: LED value");

	// case A: a = 123456789, b = 1000
	check(16'h000A, 32'h075BCD15, "case A: a (rs1)");
	check(16'h001A, 32'h000003E8, "case A: b (rs2)");
	check(16'h002A, 32'hBE991A08, "case A: mul");
	check(16'h003A, 32'h0000001C, "case A: mulh");
	check(16'h004A, 32'h0000001C, "case A: mulhu");
	check(16'h005A, 32'h0001E240, "case A: div");
	check(16'h006A, 32'h0001E240, "case A: divu");
	check(16'h007A, 32'h00000315, "case A: rem");
	check(16'h008A, 32'h00000315, "case A: remu");
	check(16'h009A, 32'h00000012, "case A: mul cycles");
	check(16'h00AA, 32'h00000021, "case A: div cycles");
	check(16'h00BA, 32'h000000FF, "case A: LED value");

	// case B: a = -123456789, b = 1000
	check(16'h000B, 32'hF8A432EB, "case B: a (rs1)");
	check(16'h001B, 32'h000003E8, "case B: b (rs2)");
	check(16'h002B, 32'h4166E5F8, "case B: mul");
	check(16'h003B, 32'hFFFFFFE3, "case B: mulh");
	check(16'h004B, 32'h000003CB, "case B: mulhu");
	check(16'h005B, 32'hFFFE1DC0, "case B: div");
	check(16'h006B, 32'h003FA6F6, "case B: divu");
	check(16'h007B, 32'hFFFFFCEB, "case B: rem");
	check(16'h008B, 32'h000001FB, "case B: remu");
	check(16'h009B, 32'h00000012, "case B: mul cycles");
	check(16'h00AB, 32'h00000021, "case B: div cycles");
	check(16'h00BB, 32'h000000FF, "case B: LED value");

	// case C: a = 305419896, b = -1698898192
	check(16'h000C, 32'h12345678, "case C: a (rs1)");
	check(16'h001C, 32'h9ABCDEF0, "case C: b (rs2)");
	check(16'h002C, 32'h242D2080, "case C: mul");
	check(16'h003C, 32'hF8CC93D6, "case C: mulh");
	check(16'h004C, 32'h0B00EA4E, "case C: mulhu");
	check(16'h005C, 32'h00000000, "case C: div");
	check(16'h006C, 32'h00000000, "case C: divu");
	check(16'h007C, 32'h12345678, "case C: rem");
	check(16'h008C, 32'h12345678, "case C: remu");
	check(16'h009C, 32'h00000012, "case C: mul cycles");
	check(16'h00AC, 32'h00000021, "case C: div cycles");
	check(16'h00BC, 32'h000000FF, "case C: LED value");

	// case D: a = -2, b = 2
	check(16'h000D, 32'hFFFFFFFE, "case D: a (rs1)");
	check(16'h001D, 32'h00000002, "case D: b (rs2)");
	check(16'h002D, 32'hFFFFFFFC, "case D: mul");
	check(16'h003D, 32'hFFFFFFFF, "case D: mulh");
	check(16'h004D, 32'h00000001, "case D: mulhu");
	check(16'h005D, 32'hFFFFFFFF, "case D: div");
	check(16'h006D, 32'h7FFFFFFF, "case D: divu");
	check(16'h007D, 32'h00000000, "case D: rem");
	check(16'h008D, 32'h00000000, "case D: remu");
	check(16'h009D, 32'h00000012, "case D: mul cycles");
	check(16'h00AD, 32'h00000021, "case D: div cycles");
	check(16'h00BD, 32'h000000FF, "case D: LED value");

	// case E: a = 1, b = -2147483648
	check(16'h000E, 32'h00000001, "case E: a (rs1)");
	check(16'h001E, 32'h80000000, "case E: b (rs2)");
	check(16'h002E, 32'h80000000, "case E: mul");
	check(16'h003E, 32'hFFFFFFFF, "case E: mulh");
	check(16'h004E, 32'h00000000, "case E: mulhu");
	check(16'h005E, 32'h00000000, "case E: div");
	check(16'h006E, 32'h00000000, "case E: divu");
	check(16'h007E, 32'h00000001, "case E: rem");
	check(16'h008E, 32'h00000001, "case E: remu");
	check(16'h009E, 32'h00000012, "case E: mul cycles");
	check(16'h00AE, 32'h00000021, "case E: div cycles");
	check(16'h00BE, 32'h000000FF, "case E: LED value");

	// case F: a = -559038737, b = 65537
	check(16'h000F, 32'hDEADBEEF, "case F: a (rs1)");
	check(16'h001F, 32'h00010001, "case F: b (rs2)");
	check(16'h002F, 32'h9D9CBEEF, "case F: mul");
	check(16'h003F, 32'hFFFFDEAD, "case F: mulh");
	check(16'h004F, 32'h0000DEAE, "case F: mulhu");
	check(16'h005F, 32'hFFFFDEAE, "case F: div");
	check(16'h006F, 32'h0000DEAC, "case F: divu");
	check(16'h007F, 32'hFFFFE041, "case F: rem");
	check(16'h008F, 32'h0000E043, "case F: remu");
	check(16'h009F, 32'h00000012, "case F: mul cycles");
	check(16'h00AF, 32'h00000021, "case F: div cycles");
	check(16'h00BF, 32'h000000FF, "case F: LED value");

	check(16'h00C5, 32'h00000000, "case 5: unused view C shows 0");
	check(16'h00D5, 32'h00000000, "case 5: unused view D shows 0");
	check(16'h00E5, 32'h00000000, "case 5: unused view E shows 0");
	check(16'h00F5, 32'h00000000, "case 5: unused view F shows 0");

	// 3) SW15 = 1: own operands, SW14-8 = a, SW6-0 = b (7-bit signed); none / BTNL / BTNC / BTNR
	check_live(16'hFB03, 3'b000, 32'hFFFFFFF1, "a = -5, b = 3: a * b");
	check_live(16'hFB03, 3'b100, 32'hFFFFFFFF, "a = -5, b = 3: a / b (BTNL)");
	check_live(16'hFB03, 3'b010, 32'hFFFFFFFE, "a = -5, b = 3: a rem b (BTNC)");
	check_live(16'hFB03, 3'b001, 32'h55555553, "a = -5, b = 3: a / b unsigned (BTNR)");
	check_live(16'hBF40, 3'b000, 32'hFFFFF040, "a = 63, b = -64: a * b");
	check_live(16'hBF40, 3'b100, 32'h00000000, "a = 63, b = -64: a / b (BTNL)");
	check_live(16'hBF40, 3'b010, 32'h0000003F, "a = 63, b = -64: a rem b (BTNC)");
	check_live(16'hBF40, 3'b001, 32'h00000000, "a = 63, b = -64: a / b unsigned (BTNR)");
	check_live(16'hC07F, 3'b000, 32'h00000040, "a = -64, b = -1: a * b");
	check_live(16'hC07F, 3'b100, 32'h00000040, "a = -64, b = -1: a / b (BTNL)");
	check_live(16'hC07F, 3'b010, 32'h00000000, "a = -64, b = -1: a rem b (BTNC)");
	check_live(16'hC07F, 3'b001, 32'h00000000, "a = -64, b = -1: a / b unsigned (BTNR)");
	check_live(16'hC001, 3'b000, 32'hFFFFFFC0, "a = -64, b = 1: a * b");
	check_live(16'hC001, 3'b100, 32'hFFFFFFC0, "a = -64, b = 1: a / b (BTNL)");
	check_live(16'hC001, 3'b010, 32'h00000000, "a = -64, b = 1: a rem b (BTNC)");
	check_live(16'hC001, 3'b001, 32'hFFFFFFC0, "a = -64, b = 1: a / b unsigned (BTNR)");
	check_live(16'h8007, 3'b000, 32'h00000000, "a = 0, b = 7: a * b");
	check_live(16'h8007, 3'b100, 32'h00000000, "a = 0, b = 7: a / b (BTNL)");
	check_live(16'h8007, 3'b010, 32'h00000000, "a = 0, b = 7: a rem b (BTNC)");
	check_live(16'h8007, 3'b001, 32'h00000000, "a = 0, b = 7: a / b unsigned (BTNR)");
	check_live(16'h9100, 3'b000, 32'h00000000, "a = 17, b = 0: a * b");
	check_live(16'h9100, 3'b100, 32'hFFFFFFFF, "a = 17, b = 0: a / b (BTNL)");
	check_live(16'h9100, 3'b010, 32'h00000011, "a = 17, b = 0: a rem b (BTNC)");
	check_live(16'h9100, 3'b001, 32'hFFFFFFFF, "a = 17, b = 0: a / b unsigned (BTNR)");
	check_live(16'hFF7F, 3'b000, 32'h00000001, "a = -1, b = -1: a * b");
	check_live(16'hFF7F, 3'b100, 32'h00000001, "a = -1, b = -1: a / b (BTNL)");
	check_live(16'hFF7F, 3'b010, 32'h00000000, "a = -1, b = -1: a rem b (BTNC)");
	check_live(16'hFF7F, 3'b001, 32'h00000001, "a = -1, b = -1: a / b unsigned (BTNR)");
	check_live(16'hAD06, 3'b000, 32'h0000010E, "a = 45, b = 6: a * b");
	check_live(16'hAD06, 3'b100, 32'h00000007, "a = 45, b = 6: a / b (BTNL)");
	check_live(16'hAD06, 3'b010, 32'h00000003, "a = 45, b = 6: a rem b (BTNC)");
	check_live(16'hAD06, 3'b001, 32'h00000007, "a = 45, b = 6: a / b unsigned (BTNR)");

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
