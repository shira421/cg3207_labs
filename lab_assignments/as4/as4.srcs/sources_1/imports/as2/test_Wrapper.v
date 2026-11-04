`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
 test_Wrapper.v - Assignment 4 testbench for the fractal explorer demo (AA_IROM.mem / AA_DMEM.mem
 from sw/demo/fractal.c). Uses the Wrapper's ports only, so the same testbench works for
 behavioural simulation and for post-synthesis simulation (synthesise Wrapper as the top).

 What it does (about 6.5 million cycles = 65 ms of simulated time; use Run All):
   1. All enhancements on: 2 frames of the Mandelbrot set.
   2. SW3 on (plain RV32IM: mul + mulh + shifts instead of mulsr): 2 frames.
   3. SW3 off, BTNC pressed (interrupt): the program switches to the Julia set (LED7 on), 2 frames.
 Every frame it prints the 7-segment value (cycles the CPU took to compute the previous frame,
 in decimal), the LEDs, the pixels written and how many of them are not black, and at the end
 checks that
   - every frame wrote all 96 x 64 pixels, and the picture is not blank,
   - mulsr made the frame faster than the plain RV32IM multiply sequence,
   - the interrupt switched to the Julia set (LED7 on).
 (The slow-multiplier switch, SW2, is ~10x slower: about 9 million cycles per frame, so it is
 left out here. sim/run_tests.py checks it in every test.)

 AI assistance declaration (CG3207 lab manual): written with Claude (Anthropic), Claude Opus 5.5, Nov 2026.
----------------------------------------------------------------------------------
*/
module test_Wrapper #(
	parameter N_LEDs_OUT	= 8,
	parameter N_DIPs		= 16,
	parameter N_PBs			= 3
)
(
);
	reg  [N_DIPs-1:0] DIP = 16'h0000;	// everything on, 32 iterations, 7-seg = cycles per frame
	reg  [N_PBs-1:0] PB = 0;
	wire [N_LEDs_OUT-1:0] LED_OUT;
	wire [6:0] LED_PC;
	wire [31:0] SEVENSEGHEX;
	wire [7:0] UART_TX;
	reg  UART_TX_ready = 1;
	wire UART_TX_valid;
	reg  [7:0] UART_RX = 0;
	reg  UART_RX_valid = 0;
	wire UART_RX_ack;
	wire OLED_Write;
	wire [6:0] OLED_Col;
	wire [5:0] OLED_Row;
	wire [23:0] OLED_Data;
	wire OLED_Swap;
	reg  OLED_SwapPending = 0;		// modelled below: high for a while after each present
	reg  [31:0] ACCEL_Data = 32'h1A000040;	// board flat: X = Y = 0, Z = +1 g
	reg  ACCEL_DReady = 1;
	reg  RESET = 1;
	reg  CLK = 0;

	Wrapper dut(
		.DIP(DIP), .PB(PB), .LED_OUT(LED_OUT), .LED_PC(LED_PC),
		.SEVENSEGHEX(SEVENSEGHEX),
		.UART_TX(UART_TX), .UART_TX_ready(UART_TX_ready), .UART_TX_valid(UART_TX_valid),
		.UART_RX(UART_RX), .UART_RX_valid(UART_RX_valid), .UART_RX_ack(UART_RX_ack),
		.OLED_Write(OLED_Write), .OLED_Col(OLED_Col), .OLED_Row(OLED_Row),
		.OLED_Data(OLED_Data),
		.OLED_Swap(OLED_Swap), .OLED_SwapPending(OLED_SwapPending),
		.ACCEL_Data(ACCEL_Data), .ACCEL_DReady(ACCEL_DReady),
		.RESET(RESET), .CLK(CLK));

	always #5 CLK = ~CLK;			// 100 MHz

	integer frame = 0, pixels = 0, lit = 0, swap_timer = 0, errors = 0;
	integer cyc_mulsr = 0, cyc_plain = 0;

	// 7-segment shows BCD; convert to an integer for the checks
	function integer bcd;
		input [31:0] v;
		integer k;
		begin
			bcd = 0;
			for (k = 7; k >= 0; k = k - 1)
				bcd = bcd * 10 + v[4*k +: 4];
		end
	endfunction

	always @(negedge CLK) begin
		if (OLED_Write) begin
			pixels = pixels + 1;
			if (OLED_Data != 24'd0) lit = lit + 1;
		end
		if (OLED_Swap) begin
			OLED_SwapPending <= 1;
			swap_timer = 200;
		end
		else if (swap_timer > 0) begin
			swap_timer = swap_timer - 1;
			if (swap_timer == 0) OLED_SwapPending <= 0;
		end
	end

	// One line per frame. SEVENSEG is written right after the present, so look a little later.
	always @(posedge OLED_Swap) begin
		repeat (300) @(posedge CLK);
		frame = frame + 1;
		$display("frame %0d  SW=%h  7-seg %8h  LED %b  pixels %0d (%0d not black)", frame, DIP, SEVENSEGHEX, LED_OUT, pixels, lit);
		// frame 1 has one extra pixel (main() arms auto-advance with one write)
		if (frame > 1 && pixels != 96 * 64) begin
			$display("   ERROR: expected %0d pixels in a frame", 96 * 64);
			errors = errors + 1;
		end
		if (lit < 1000) begin
			$display("   ERROR: the frame is (nearly) blank");
			errors = errors + 1;
		end
		if (frame == 2) cyc_mulsr = bcd(SEVENSEGHEX);	// frame 2's own cycle count is shown after its present
		if (frame == 4) cyc_plain = bcd(SEVENSEGHEX);
		pixels = 0;
		lit = 0;
	end

	initial begin
		#105 RESET = 0;
		wait (frame == 2);
		DIP = 16'h0008;				// SW3: plain RV32IM multiply code
		wait (frame == 4);
		DIP = 16'h0000;
		PB = 3'b010;				// press BTNC: interrupt -> Julia set
		repeat (200000) @(posedge CLK);	// long enough for the button sampling (2^16 cycles)
		PB = 3'b000;
		wait (frame == 6);
		$display("");
		$display("cycles per frame: %0d with mulsr, %0d with mul + mulh + shifts (%0d%% more)",
		         cyc_mulsr, cyc_plain, (cyc_plain - cyc_mulsr) * 100 / cyc_mulsr);
		if (!(cyc_mulsr > 0 && cyc_mulsr < cyc_plain)) begin
			$display("ERROR: mulsr did not make the frame faster");
			errors = errors + 1;
		end
		if (!LED_OUT[7]) begin
			$display("ERROR: BTNC did not switch to the Julia set (LED7 off)");
			errors = errors + 1;
		end
		if (errors == 0) $display("PASS");
		else $display("FAIL: %0d errors", errors);
		$finish;
	end
endmodule
