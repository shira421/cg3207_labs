`timescale 1ns / 1ps
/*
 tb_cpu.v - self-checking-friendly testbench for the Assignment 4 CPU (Icarus Verilog or xsim).

 Runs AA_IROM.mem / AA_DMEM.mem (from the current directory) on Wrapper + RV, and writes files that
 run_tests.py compares with the reference model (iss.py):
   mmio.txt   every MMIO store: address, byte enables, data (only the enabled bytes)
   regs.txt   x0..x31 at the end
   dmem.txt   all of DMEM at the end
   stats.txt  cycles, instructions, stalls, flushes, mispredictions, interrupts
   frame_NNN.ppm  (with +frames) the OLED picture each time the program presents a frame

 Plusargs
   +max=N          stop after N cycles (default 2 000 000)
   +cpuctrl=N      force CPU_CTRL (bit 0 no forwarding, bit 1 no branch prediction, bit 2 slow multiplier)
   +toggle         force CPU_CTRL to a new random value every 1..63 cycles (switches flipped while running)
   +dip=N          value of the DIP switches
   +pb=FILE        push-button script: lines "cycle value" (value = PB[2:0], BTNL BTNC BTNR)
   +frames         write the OLED frames
   +swapwait=N     cycles OLED_SwapPending stays high after a present (default 50)
 Defines
   -DNOHAZARD      build RV with HAZARD_UNIT = 0 (compulsory-task pipeline, program padded with nops)

 The run ends when the instruction at +haltpc=HEX (the program's final "j .") has passed through E 20 times,
 or at +max.

 AI assistance declaration (CG3207 lab manual): written with Claude (Anthropic), Claude Opus 5.5, Nov 2026.
*/
module tb_cpu;
	reg  [15:0] DIP = 0;
	reg  [2:0]  PB = 0;
	wire [7:0]  LED_OUT;
	wire [6:0]  LED_PC;
	wire [31:0] SEVENSEGHEX;
	wire [7:0]  UART_TX;
	reg         UART_TX_ready = 1;
	wire        UART_TX_valid;
	reg  [7:0]  UART_RX = 0;
	reg         UART_RX_valid = 0;
	wire        UART_RX_ack;
	wire        OLED_Write;
	wire [6:0]  OLED_Col;
	wire [5:0]  OLED_Row;
	wire [23:0] OLED_Data;
	wire        OLED_Swap;
	reg         OLED_SwapPending = 0;
	reg  [31:0] ACCEL_Data = 32'h1A000040;
	reg         ACCEL_DReady = 1;
	reg         RESET = 1;
	reg         CLK = 0;

	Wrapper #(.DEBOUNCE_BITS(2)) dut(
		.DIP(DIP), .PB(PB), .LED_OUT(LED_OUT), .LED_PC(LED_PC),
		.SEVENSEGHEX(SEVENSEGHEX),
		.UART_TX(UART_TX), .UART_TX_ready(UART_TX_ready), .UART_TX_valid(UART_TX_valid),
		.UART_RX(UART_RX), .UART_RX_valid(UART_RX_valid), .UART_RX_ack(UART_RX_ack),
		.OLED_Write(OLED_Write), .OLED_Col(OLED_Col), .OLED_Row(OLED_Row),
		.OLED_Data(OLED_Data),
		.OLED_Swap(OLED_Swap), .OLED_SwapPending(OLED_SwapPending),
		.ACCEL_Data(ACCEL_Data), .ACCEL_DReady(ACCEL_DReady),
		.RESET(RESET), .CLK(CLK));

`ifdef NOHAZARD
	defparam dut.RV1.HAZARD_UNIT = 0;
`endif

	always #5 CLK = ~CLK;

	integer max_cycles, cycle, halt_count, fd_mmio, fd, i, r, c, nframes, swapwait, swap_count;
	integer n_instr, n_stall_d, n_flush, n_redirect, n_busy, n_int, n_bp_hit;
	reg [31:0] cpuctrl;
	reg [1023:0] pbfile;
	integer pb_fd, pb_cycle, pb_val, pb_have;
	reg [23:0] fb [0:63][0:95];
	reg frames;
	reg [31:0] haltpc;
	reg toggle;
	integer toggle_in = 10, toggle_seed = 3207;

	task dump_frame;
		reg [1023:0] name;
		integer f, y, x;
		begin
			$sformat(name, "frame_%03d.ppm", nframes);
			f = $fopen(name, "w");
			$fwrite(f, "P3\n96 64\n255\n");
			for (y = 0; y < 64; y = y + 1)
				for (x = 0; x < 96; x = x + 1)
					$fwrite(f, "%0d %0d %0d\n", fb[y][x][23:16], fb[y][x][15:8], fb[y][x][7:0]);
			$fclose(f);
			nframes = nframes + 1;
		end
	endtask

	initial begin
		if (!$value$plusargs("max=%d", max_cycles)) max_cycles = 2000000;
		if (!$value$plusargs("swapwait=%d", swapwait)) swapwait = 50;
		if (!$value$plusargs("haltpc=%h", haltpc)) haltpc = 32'hFFFFFFFF;
		if ($value$plusargs("dip=%d", r)) DIP = r;
		frames = $test$plusargs("frames");
		toggle = $test$plusargs("toggle");
		if ($value$plusargs("cpuctrl=%d", r)) begin
			cpuctrl = r;
			force dut.cpu_ctrl = cpuctrl[2:0];
		end
		pb_have = 0;
		if ($value$plusargs("pb=%s", pbfile)) begin
			pb_fd = $fopen(pbfile, "r");
			if ($fscanf(pb_fd, "%d %d\n", pb_cycle, pb_val) == 2) pb_have = 1;
		end
		for (r = 0; r < 64; r = r + 1) for (c = 0; c < 96; c = c + 1) fb[r][c] = 0;
		// The FPGA starts every flip-flop / LUT RAM at 0; simulation starts the register file at x.
		for (i = 0; i < 32; i = i + 1) dut.RV1.RegFile1.RegBank[i] = 0;
		fd_mmio = $fopen("mmio.txt", "w");
		cycle = 0; halt_count = 0; nframes = 0; swap_count = 0;
		n_instr = 0; n_stall_d = 0; n_flush = 0; n_redirect = 0; n_busy = 0; n_int = 0; n_bp_hit = 0;
		#12 RESET = 0;
	end

	always @(posedge CLK) if (!RESET) begin
		cycle = cycle + 1;

		// CPU_CTRL flipped at random
		if (toggle && --toggle_in <= 0) begin
			toggle_in = 1 + ($random(toggle_seed) & 63);
			cpuctrl = $random(toggle_seed);
			force dut.cpu_ctrl = cpuctrl[2:0];
		end

		// push-button script
		while (pb_have && cycle >= pb_cycle) begin
			PB = pb_val;
			if ($fscanf(pb_fd, "%d %d\n", pb_cycle, pb_val) != 2) pb_have = 0;
		end

		// MMIO stores
		if (|dut.MemWrite_out && dut.ALUResult[31:8] == 24'hFFFF00)
			$fwrite(fd_mmio, "%08x %1x %08x\n", {dut.ALUResult[31:2], 2'b00}, dut.MemWrite_out,
				dut.WriteData_out & {{8{dut.MemWrite_out[3]}}, {8{dut.MemWrite_out[2]}}, {8{dut.MemWrite_out[1]}}, {8{dut.MemWrite_out[0]}}});


		// statistics
		if (dut.RV1.Valid_E && !dut.RV1.StallE) n_instr = n_instr + 1;
		if (dut.RV1.StallD) n_stall_d = n_stall_d + 1;
		if (dut.RV1.Busy) n_busy = n_busy + 1;
		if (dut.RV1.Redirect_E) n_redirect = n_redirect + 1;
		if (dut.RV1.IntTake) n_int = n_int + 1;
		if (dut.RV1.Valid_E && dut.RV1.PredTaken_E && !dut.RV1.Redirect_E) n_bp_hit = n_bp_hit + 1;

		// end of program: the final "j ." (at +haltpc) has gone through E 20 times
		if (dut.RV1.Valid_E && !dut.RV1.StallE && dut.RV1.PC_E == haltpc) halt_count = halt_count + 1;
		if (halt_count >= 20 || cycle >= max_cycles) finish_run;
	end

	// OLED model, at the falling edge: OLED_Write / Col / Row / Data were all set by the same rising edge.
	// The pixel lands in the page being drawn; a present copies it to the screen (here: dumps the frame).
	integer swap_timer = 0;
	always @(negedge CLK) begin
		if (OLED_Write) fb[OLED_Row][OLED_Col] = OLED_Data;
		if (OLED_Swap) begin
			if (frames) dump_frame;
			swap_count = swap_count + 1;
			OLED_SwapPending <= 1;
			swap_timer = swapwait;
		end
		else if (swap_timer > 0) begin
			swap_timer = swap_timer - 1;
			if (swap_timer == 0) OLED_SwapPending <= 0;
		end
	end

	task finish_run;
		begin
			$fclose(fd_mmio);
			fd = $fopen("regs.txt", "w");
			for (i = 0; i < 32; i = i + 1)
				$fwrite(fd, "%08x\n", (i == 0) ? 32'd0 : dut.RV1.RegFile1.RegBank[i]);
			$fclose(fd);
			fd = $fopen("dmem.txt", "w");
			for (i = 0; i < 1024; i = i + 1)
				$fwrite(fd, "%08x\n", dut.DMEM[i]);
			$fclose(fd);
			fd = $fopen("stats.txt", "w");
			$fwrite(fd, "halted %0d\ncycles %0d\ninstructions %0d\nstall_d %0d\nbusy %0d\nredirects %0d\nbp_correct_taken %0d\ninterrupts %0d\nframes %0d\nsevenseg %08x\nled %02x\n",
				halt_count >= 20, cycle, n_instr, n_stall_d, n_busy, n_redirect, n_bp_hit, n_int, swap_count, SEVENSEGHEX, LED_OUT);
			$fclose(fd);
			if (frames) dump_frame;
			$finish;
		end
	endtask
endmodule
