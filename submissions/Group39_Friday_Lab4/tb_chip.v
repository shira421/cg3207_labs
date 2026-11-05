`timescale 1ns / 1ps
// Whole-chip simulation (run with run_chip.sh): TOP (course VHDL, converted to Verilog by GHDL) + our Wrapper/RV +
// a model of the SSD1331 panel on the Pmod pins. The panel model decodes the SPI stream:
// DC = 0 command bytes are logged, DC = 1 data bytes are 16-bit pixels written to the panel's RAM
// (vertical address increment, as set by command A0 73), and every complete panel frame is dumped.
module tb_chip;
	reg CLK_undiv = 0;
	always #5 CLK_undiv = ~CLK_undiv;

	reg  [15:0] DIP = 16'h4000;
	reg  [2:0]  PB = 0;
	reg  PAUSE = 0, RESET = 1;
	wire [15:0] LED;
	wire [7:0]  SevenSegAn;
	wire [6:0]  SevenSegCat;
	wire TX;
	wire PMOD_CS, PMOD_MOSI, PMOD_SCK, PMOD_DC, PMOD_RES, PMOD_VCCEN, PMOD_EN;
	wire aclSCK, aclMOSI, aclSS;

	TOP dut(.DIP(DIP), .PB(PB), .LED(LED), .SevenSegAn(SevenSegAn), .SevenSegCat(SevenSegCat),
	        .TX(TX), .RX(1'b1), .PAUSE(PAUSE), .RESET(RESET), .CLK_undiv(CLK_undiv),
	        .PMOD_CS(PMOD_CS), .PMOD_MOSI(PMOD_MOSI), .PMOD_SCK(PMOD_SCK), .PMOD_DC(PMOD_DC),
	        .PMOD_RES(PMOD_RES), .PMOD_VCCEN(PMOD_VCCEN), .PMOD_EN(PMOD_EN),
	        .aclSCK(aclSCK), .aclMOSI(aclMOSI), .aclMISO(1'b0), .aclSS(aclSS));

	// ---------------- SSD1331 model ----------------
	reg [7:0] sh = 0;
	integer nbits = 0, ncmd = 0, npix = 0, nframes = 0, col = 0, row = 0, have_hi = 0;
	reg [7:0] hi;
	reg [15:0] ram [0:63][0:95];
	reg disp_on = 0;
	integer max_frames, nonblack, y, x, f;
	reg [1023:0] name;

	always @(posedge PMOD_SCK) if (!PMOD_CS) begin
		sh = {sh[6:0], PMOD_MOSI};
		nbits = nbits + 1;
		if (nbits == 8) begin
			nbits = 0;
			if (!PMOD_DC) begin
				ncmd = ncmd + 1;
				$display("%t  cmd %02x  (EN=%b VCCEN=%b RES=%b)", $time, sh, PMOD_EN, PMOD_VCCEN, PMOD_RES);
				if (sh == 8'hAF) disp_on = 1;
				if (sh == 8'hAE) disp_on = 0;
			end else if (!have_hi) begin
				hi = sh; have_hi = 1;
			end else begin
				have_hi = 0;
				ram[row][col] = {hi, sh};
				npix = npix + 1;
				row = row + 1;
				if (row == 64) begin
					row = 0; col = col + 1;
					if (col == 96) begin
						col = 0;
						dump_frame;
					end
				end
			end
		end
	end
	always @(posedge PMOD_CS) nbits = 0;

	task dump_frame;
		begin
			nonblack = 0;
			$sformat(name, "panel_%02d.ppm", nframes);
			f = $fopen(name, "w");
			$fwrite(f, "P3\n96 64\n255\n");
			for (y = 0; y < 64; y = y + 1)
				for (x = 0; x < 96; x = x + 1) begin
					$fwrite(f, "%0d %0d %0d\n", {ram[y][x][15:11], 3'b0}, {ram[y][x][10:5], 2'b0}, {ram[y][x][4:0], 3'b0});
					if (ram[y][x] != 0) nonblack = nonblack + 1;
				end
			$fclose(f);
			$display("%t  panel frame %0d complete: %0d non-black pixels, display %s, PC=%h, 7seg=%h, LED=%b",
			         $time, nframes, nonblack, disp_on ? "ON" : "OFF", dut.wrapper1.PC, dut.wrapper1.SEVENSEGHEX, LED[7:0]);
			nframes = nframes + 1;
			if (nframes >= max_frames) $finish;
		end
	endtask

	integer cpu_writes = 0, swaps = 0;
	always @(posedge dut.wrapper1.CLK) begin
		if (dut.wrapper1.OLED_Write) cpu_writes = cpu_writes + 1;
		if (dut.wrapper1.OLED_Swap) begin
			swaps = swaps + 1;
			if (swaps <= 3) $display("%t  CPU presents frame %0d after %0d pixel writes, ACCEL_Data = %h", $time, swaps, cpu_writes, dut.wrapper1.ACCEL_Data);
		end
	end

	initial begin
		if (!$value$plusargs("frames=%d", max_frames)) max_frames = 4;
		if ($test$plusargs("noreset")) RESET = 0; else #1000 RESET = 0;
		#300_000_000 $display("TIMEOUT: %0d commands, %0d pixels, %0d CPU pixel writes, %0d swaps", ncmd, npix, cpu_writes, swaps);
		$finish;
	end
endmodule
