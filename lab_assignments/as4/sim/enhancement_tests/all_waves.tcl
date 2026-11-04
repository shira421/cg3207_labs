# Open tb_all_enhancements behavioural simulation before sourcing.
# set demo_view branch
# source {C:/path/to/all_waves.tcl}
# Views: pipeline forwarding hazards multiply mulsr branch memory interrupt live
set root /tb_all_enhancements
if {![info exists demo_view]} {set demo_view pipeline}
if {$demo_view ni {pipeline forwarding hazards multiply mulsr branch memory interrupt live}} {
  error "Unknown demo_view: $demo_view"
}
create_wave_config
proc demo_add {path signals} {
  foreach s $signals {add_wave $path/$s}
}
demo_add $root {CLK RESET done}
set f $root/fast/dut
switch -- $demo_view {
  pipeline {
    demo_add $f {PC_F PC_D PC_E Instr_D Valid_D Valid_E rd_E rd_M rd_W ExecResult_E ExecResult_M ExecResult_W RegWrite_W Result_W StallD}
  }
  forwarding {
    foreach core {fast nofwd} {
      set c $root/$core
      demo_add $c {cpu_ctrl stalls completion_cycles}
      demo_add $c/dut {PC_D PC_E rs1_D rs1_E rs2_E rd_M rd_W RD1_D RD1_E RD2_E ForwardA_E ForwardB_E FwdA_E FwdB_E ALUResult_E StallF StallD FlushE RegWrite_W Result_W}
    }
  }
  hazards {
    demo_add $f {PC_F PC_D PC_E rd_D rd_E rd_M rd_W MemtoReg_E IsMul_E Busy StallF StallD StallE FlushD FlushE FlushM Valid_E ForwardA_E ForwardB_E RegWrite_W Result_W}
    demo_add $f/HazardUnit1 {lwStall nofwdStall}
  }
  multiply {
    foreach core {fast slow} {
      set c $root/$core
      demo_add $c {completion_cycles busy_cycles burst_writes}
      demo_add $c/dut {PC_E IsMul_E IsMul_M IsMul_W SlowMul_E Busy StallF StallD StallE FlushM rd_E rd_M rd_W FwdA_E FwdB_E MulShift_E MulResult_M MulResult_W RegWrite_W Result_W}
    }
  }
  mulsr {
    demo_add $f {PC_E FwdA_E FwdB_E IsMul_E MulShift_E MulShift_M rd_E rd_M rd_W MulResult_M MulResult_W RegWrite_W Result_W}
  }
  branch {
    foreach core {fast nopred} {
      set c $root/$core
      demo_add $c {branch_visits branch_redirects correct_taken}
      demo_add $c/dut {PC_F PredTaken_F PredTarget_F PC_D PC_E Valid_E PredTaken_E Taken_E Target_E Redirect_E CorrectPC_E FlushD FlushE RegWrite_W rd_W Result_W}
    }
    # Conditional test branch is PC 0x0040018c: (PC >> 2) & 31 = 3.
    # Array-element visibility varies with simulator debug settings.
    catch {add_wave [format {%s/BranchPredictor1/ctr[3]} $f]}
    catch {add_wave [format {%s/BranchPredictor1/valid[3]} $f]}
  }
  memory {
    demo_add $root/fast {ALUResult MemRead MemWrite_out WriteData_out ReadData_in stores}
    demo_add $f {PC_E Funct3_M Funct3_W ExecResult_W ReadDataRaw_W ReadData_W RegWrite_W rd_W Result_W StallD FlushE}
    catch {add_wave [format {%s/fast/mem[0]} $root]}
  }
  interrupt {
    demo_add $root/fast {Interrupt irq_count mret_count saved_epc irq_sent irq_accepted}
    demo_add $f {PC_F PC_D PC_E Valid_D Valid_E IntTake EPC InISR StallRaw_D Redirect_E FlushD FlushE Mret_E CorrectPC_E RegWrite_W rd_W Result_W}
  }
  live {
    demo_add $root/live {cpu_ctrl mode_changes held_mode_changes modes_seen errors completion_cycles}
    demo_add $root/live/dut {PC_D PC_E NoForward_E SlowMul_E ForwardA_E ForwardB_E PredTaken_F Busy StallD StallE RegWrite_W rd_W Result_W}
  }
}
# Record before restarting, so all views retain full history.
log_wave -r $root/*
restart
run all
puts "View: $demo_view. Zoom using PC ranges in SHOW_AND_EXPLAIN.md; console contains PASS/FAIL."

