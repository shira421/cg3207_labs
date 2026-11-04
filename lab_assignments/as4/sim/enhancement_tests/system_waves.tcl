# Run with tb_system_enhancements as the behavioural simulation top.
create_wave_config
set r /tb_system_enhancements
foreach s {CLK RESET PB pending pixel col row rgb swap errors ctrl_writes pixels swaps irqs returns saw_status_one saw_status_zero} {
  add_wave $r/$s
}
foreach s {cpu_ctrl ALUResult MemWrite_out WriteData_out MemRead ReadData_in dec_CPU_CTRL pb_sync1 pb_sync2 pb_sample debounce_count int_en int_flags Interrupt OLED_ctrl_reg} {
  add_wave $r/dut/$s
}
foreach s {PC_F PC_D PC_E IntTake EPC InISR Mret_E CorrectPC_E SlowMul_E Busy RegWrite_W rd_W Result_W} {
  add_wave $r/dut/RV1/$s
}
log_wave -r $r/*
restart
run all

