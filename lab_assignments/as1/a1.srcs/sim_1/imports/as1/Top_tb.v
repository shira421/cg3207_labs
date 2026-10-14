`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench for Top (CG3207 Assignment 1, Task 2)
//
// Uses shrunken clock-enable thresholds via parameter override, so no edit to
// Clock_Enable.v is needed for simulation.
//   THRESH_SLOW = 15 -> enable every 16 clk = 160 ns  ("1 Hz")
//   THRESH_FAST = 3  -> enable every  4 clk =  40 ns  ("4 Hz")
// The 4x ratio is preserved, exactly as on hardware.
//////////////////////////////////////////////////////////////////////////////////

module Top_tb;

    localparam SLOW      = 15;
    localparam FAST      = 3;
    localparam SLOW_NS   = (SLOW + 1) * 10;   // 160 ns
    localparam FAST_NS   = (FAST + 1) * 10;   //  40 ns

    reg         clk  = 0;
    reg         btnU = 0;
    reg         btnC = 0;
    wire [15:0] led;
    wire        dp;
    wire [7:0]  anode;
    wire [6:0]  cathode;

    Top #(.THRESH_SLOW(SLOW), .THRESH_FAST(FAST)) uut (
        .clk     (clk),
        .btnU    (btnU),
        .btnC    (btnC),
        .led     (led),
        .dp      (dp),
        .anode   (anode),
        .cathode (cathode)
    );

    always #5 clk = ~clk;   // 100 MHz

    //--------------------------------------------------------------------------
    // Internal signals, pulled up for the waveform window and for checking.
    // NOTE: these hierarchical references only work in BEHAVIOURAL simulation.
    // For post-synthesis functional simulation, comment out this section and the
    // checkers below - the internal names get renamed or optimised away.
    //--------------------------------------------------------------------------
    wire [8:0]  addr        = uut.Get_MEM1.addr;
    wire [31:0] data        = uut.data;
    wire        enable      = uut.enable;
    wire        upper_lower = uut.upper_lower;

    integer errors = 0;

    task report;
        input [8*80:1] msg;
        begin
            $display("[%t] %0s", $time, msg);
        end
    endtask

    task fail;
        input [8*80:1] msg;
        begin
            errors = errors + 1;
            $display("[%t] *** ERROR: %0s", $time, msg);
            // Swap the line above for the following to halt on first failure:
            // $error("%0s", msg);
        end
    endtask

    //--------------------------------------------------------------------------
    // Checker 1 - combinational relationships, valid at all times
    //--------------------------------------------------------------------------
    always @(negedge clk) begin
        if (upper_lower !== ~addr[0])
            fail("upper_lower does not match ~addr[0]");
        if (led !== (upper_lower ? data[31:16] : data[15:0]))
            fail("led does not match the selected half of data");
    end

    //--------------------------------------------------------------------------
    // Checker 2 - addr must be frozen whenever btnC is held
    //--------------------------------------------------------------------------
    reg        freeze_check = 0;
    reg [8:0]  addr_prev    = 0;

    always @(negedge clk) begin
        if (freeze_check && (addr !== addr_prev))
            fail("addr advanced while btnC was held");
        addr_prev <= addr;
    end

    //--------------------------------------------------------------------------
    // Checker 3 - interval between enable pulses
    //--------------------------------------------------------------------------
    reg        period_check    = 0;
    integer    expected_period = SLOW_NS;
    time       last_pulse      = 0;
    time       delta;

    always @(posedge clk) begin
        if (enable) begin
            delta      = $time - last_pulse;
            last_pulse = $time;
            if (period_check && (delta != expected_period))
                fail("enable pulse interval is wrong");
        end
    end

    // Watchdog - guarantees termination
    initial begin
        #25000;
        $display("*** WATCHDOG: testbench did not finish on its own ***");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Stimulus - a simulated user pressing buttons
    //--------------------------------------------------------------------------
    initial begin
        $timeformat(-9, 0, " ns", 8);   // print %t in ns, not ps
        $display("=== CG3207 Assignment 1 Task 2 - Top testbench ===");
        #1 $display("[%t] IROM[0] via data = %h  (expect ffff0437)", $time, data);

        // --- Phase 1: no buttons, slow rate ---------------------------------
        report("Phase 1: no buttons  -> expect one step every 160 ns");
        expected_period = SLOW_NS;
        #400 period_check = 1;      // let the first pulse establish a reference
        #800 period_check = 0;
        $display("[%t]   addr = %0d, data = %h", $time, addr, data);

        // --- Phase 2: btnU held, 4x faster ----------------------------------
        report("Phase 2: btnU held   -> expect one step every 40 ns");
        btnU = 1;
        expected_period = FAST_NS;
        #200 period_check = 1;
        #400 period_check = 0;
        $display("[%t]   addr = %0d (should have advanced ~15)", $time, addr);

        // --- Phase 3: btnU released, back to slow ---------------------------
        report("Phase 3: btnU released -> back to 160 ns, sequence continues");
        btnU = 0;
        expected_period = SLOW_NS;
        #400 period_check = 1;
        #500 period_check = 0;

        // --- Phase 4: btnC held, paused -------------------------------------
        report("Phase 4: btnC held   -> expect addr frozen");
        btnC = 1;
        #50  freeze_check = 1;      // grace period for an in-flight pulse
        #600 freeze_check = 0;
        $display("[%t]   addr = %0d (frozen during btnC)", $time, addr);

        // --- Phase 5: btnC released, resumes from the same place ------------
        report("Phase 5: btnC released -> resumes from the same addr");
        btnC = 0;
        #600;

        // --- Phase 6: both buttons (undefined by spec; we pause) ------------
        report("Phase 6: btnU + btnC -> our choice: btnC wins, stays paused");
        btnU = 1;
        btnC = 1;
        #50  freeze_check = 1;
        #400 freeze_check = 0;
        btnU = 0;
        btnC = 0;
        #200;

        // --- Phase 7: long fast run, crossing IROM -> DMEM ------------------
        // Deterministic delay rather than wait(), so the testbench always
        // terminates even if the design is not advancing.
        report("Phase 7: btnU held long enough to cross from IROM into DMEM");
        btnU = 1;
        #8800;
        $display("[%t]   addr = %0d, data = %h  (near end of IROM)", $time, addr, data);
        #400;
        $display("[%t]   addr = %0d, data = %h  (crossed into DMEM: addr >= 256)",
                 $time, addr, data);
        btnU = 0;
        #400;

        // --- Done -----------------------------------------------------------
        if (errors == 0)
            $display("=== PASS: no errors detected ===");
        else
            $display("=== FAIL: %0d error(s) detected ===", errors);
        $finish;
    end

endmodule