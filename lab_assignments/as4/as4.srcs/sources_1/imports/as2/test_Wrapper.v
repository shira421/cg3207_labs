`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
 test_Wrapper.v - Assignment 4 testbench for the Breakout demo (AA_IROM.mem / AA_DMEM.mem from
 sw/demo/breakout.c). Uses the Wrapper's ports only, so the same testbench works for
 behavioural simulation and for post-synthesis simulation (synthesise Wrapper as the top).

 What it does (about 800 000 cycles = 8 ms of simulated time; use Run All):
   1. Autoplay (SW14), all enhancements on: runs 4 frames.
   2. SW1:SW0 = 11 (no forwarding, no branch prediction): runs 4 frames.
   3. Presses BTNC (interrupt) to pause the game, runs 5 frames.
 Every frame it prints the 7-segment value (cycles the CPU took to compute and draw that frame,
 in decimal), the LEDs, and the number of pixels written, and at the end checks that
   - every frame wrote all 96 x 64 pixels,
   - the CPU with its enhancements took fewer cycles per frame than without,
   - the interrupt paused the game (LED7 on).

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
	reg  [N_DIPs-1:0] DIP = 16'h4000;	// SW14 autoplay
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
	reg  [31:0] ACCEL_Data = 32'h1A000040;
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

	integer frame = 0, pixels = 0, swap_timer = 0, errors = 0;
	integer cyc_on = 0, cyc_off = 0;

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
		if (OLED_Write)
			pixels = pixels + 1;
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
		repeat (100) @(posedge CLK);
		frame = frame + 1;
		$display("frame %2d  SW=%h  7-seg %8h  LED %b  pixels %0d", frame, DIP, SEVENSEGHEX, LED_OUT, pixels);
		// frame 1 has one extra pixel (main() arms auto-advance with one write)
		if (frame > 1 && pixels != 96 * 64) begin
			$display("   ERROR: expected %0d pixels in a frame", 96 * 64);
			errors = errors + 1;
		end
		if (frame == 4) cyc_on = bcd(SEVENSEGHEX);
		if (frame == 8) cyc_off = bcd(SEVENSEGHEX);
		pixels = 0;
	end

	initial begin
		#105 RESET = 0;
		wait (frame == 4);
		DIP = 16'h4003;				// switch forwarding and branch prediction off
		wait (frame == 8);
		DIP = 16'h4000;
		PB = 3'b010;				// press BTNC: interrupt -> pause
		repeat (200000) @(posedge CLK);	// long enough for the button sampling (2^16 cycles)
		PB = 3'b000;
		wait (frame == 13);
		$display("");
		$display("cycles per frame: %0d with the enhancements, %0d without (%0d%% more)",
		         cyc_on, cyc_off, (cyc_off - cyc_on) * 100 / cyc_on);
		if (!(cyc_on > 0 && cyc_on < cyc_off)) begin
			$display("ERROR: the enhancements did not reduce the cycles per frame");
			errors = errors + 1;
		end
		if (!LED_OUT[7]) begin
			$display("ERROR: BTNC did not pause the game (LED7 off)");
			errors = errors + 1;
		end
		if (errors == 0) $display("PASS");
		else $display("FAIL: %0d errors", errors);
		$finish;
	end
endmodule
