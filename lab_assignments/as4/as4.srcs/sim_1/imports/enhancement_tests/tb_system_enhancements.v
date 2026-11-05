`timescale 1ns/1ps
// Integration supplement: actual Wrapper, MMIO controls, PB synchronization and OLED port handshakes.
// Uses a short test program in IROM after time 1 ns; project memory files are untouched.
module tb_system_enhancements;
  reg CLK=0,RESET=1;
  reg [2:0] PB=0;
  reg [15:0] DIP=0;
  reg pending=0;
  wire pixel,swap;
  wire [6:0] col;
  wire [5:0] row;
  wire [23:0] rgb;
  wire [7:0] led,uart_tx;
  wire [6:0] ledpc;
  wire [31:0] seven;
  wire tx_valid,rx_ack;
  Wrapper #(.DEBOUNCE_BITS(2)) dut(
    .CLK(CLK),.RESET(RESET),.DIP(DIP),.PB(PB),.LED_OUT(led),.LED_PC(ledpc),
    .SEVENSEGHEX(seven),.UART_TX(uart_tx),.UART_TX_ready(1'b1),.UART_TX_valid(tx_valid),
    .UART_RX(8'd0),.UART_RX_valid(1'b0),.UART_RX_ack(rx_ack),
    .OLED_Write(pixel),.OLED_Col(col),.OLED_Row(row),.OLED_Data(rgb),
    .OLED_Swap(swap),.OLED_SwapPending(pending),
    .ACCEL_Data(32'h1a000040),.ACCEL_DReady(1'b1));
  always #5 CLK=~CLK;
  integer i,errors=0,cycles=0,ctrl_writes=0,pixels=0,swaps=0,irqs=0,returns=0;
  integer pending_timer=0;
  reg pb_started=0,saw_status_one=0,saw_status_zero=0;
  reg [31:0] epc_saved=0;
  reg ctrl_pending=0;
  reg [2:0] expected_ctrl=0;
  integer slow_busy=0;
  task check;
    input condition;
    input [8*100-1:0] message;
    begin if(condition!==1'b1) begin errors=errors+1;$display("ERROR system: %0s",message);end end
  endtask
  initial begin
    #1; // Wrapper has already performed its normal time-zero readmemh.
    for(i=0;i<1024;i=i+1) begin dut.IROM[i]=32'h00000013; dut.DMEM[i]=0; end
    for(i=0;i<32;i=i+1) dut.RV1.RegFile1.RegBank[i]=0;
    dut.IROM[0]=32'h0200006f; // j main
    dut.IROM[1]=32'h1fc0006f; // j isr
    dut.IROM[8]=32'hffff00b7; // lui x1,0xffff0
    dut.IROM[9]=32'h00100113; // addi x2,x0,1
    dut.IROM[10]=32'h0620a823; // sw x2,CPU_CTRL(x1)
    dut.IROM[11]=32'h00200113; // addi x2,x0,2
    dut.IROM[12]=32'h0620a823; // sw x2,CPU_CTRL(x1)
    dut.IROM[13]=32'h00400113; // addi x2,x0,4
    dut.IROM[14]=32'h0620a823; // sw x2,CPU_CTRL(x1)
    dut.IROM[15]=32'h00600193; // addi x3,x0,6
    dut.IROM[16]=32'h00700213; // addi x4,x0,7
    dut.IROM[17]=32'h024182b3; // mul x5,x3,x4 # slow mode
    dut.IROM[18]=32'h00000113; // addi x2,x0,0
    dut.IROM[19]=32'h0620a823; // sw x2,CPU_CTRL(x1)
    dut.IROM[20]=32'h00300113; // addi x2,x0,3
    dut.IROM[21]=32'h0220a023; // sw x2,OLED_COL(x1)
    dut.IROM[22]=32'h00400113; // addi x2,x0,4
    dut.IROM[23]=32'h0220a223; // sw x2,OLED_ROW(x1)
    dut.IROM[24]=32'h01000113; // addi x2,x0,16 # RGB565
    dut.IROM[25]=32'h0220a623; // sw x2,OLED_CTRL(x1)
    dut.IROM[26]=32'h00010337; // lui x6,0x10
    dut.IROM[27]=32'h80030313; // addi x6,x6,-2048 # 0xf800
    dut.IROM[28]=32'h02609423; // sh x6,OLED_DATA(x1)
    dut.IROM[29]=32'h00800113; // addi x2,x0,8 # present request
    dut.IROM[30]=32'h0220a623; // sw x2,OLED_CTRL(x1)
    dut.IROM[31]=32'h0300a383; // poll: lw x7,OLED_STATUS(x1)
    dut.IROM[32]=32'hfe039ee3; // bne x7,x0,poll
    dut.IROM[33]=32'h00100113; // addi x2,x0,1
    dut.IROM[34]=32'h0620aa23; // sw x2,INT_EN(x1)
    dut.IROM[35]=32'h000e0063; // wait_irq: beq x28,x0,wait_irq
    dut.IROM[36]=32'h07b00f93; // addi x31,x0,123
    dut.IROM[128]=32'h0620ac23; // sw x2,INT_FLAGS(x1) # write-one-to-clear
    dut.IROM[129]=32'h001e0e13; // addi x28,x28,1
    dut.IROM[130]=32'h30200073; // mret
    #21 RESET=0;
  end
  // Model only the external controller's busy handshake, NOT the controller or its SPI panel.
  always @(negedge CLK) if(!RESET) begin
    if(pixel) begin
      pixels=pixels+1;
      check(col==3 && row==4 && rgb==24'hf80000,"RGB565 halfword pixel should be red at (3,4)");
      $display("SYSTEM PIXEL col=%0d row=%0d rgb=%06h",col,row,rgb);
    end
    if(swap) begin swaps=swaps+1; pending=1;pending_timer=32; end
    else if(pending_timer>0) begin
      pending_timer=pending_timer-1;
      if(pending_timer==0) pending=0;
    end
    if(dut.int_en==1 && !pb_started) begin
      PB=1;pb_started=1;
    end
    if(dut.int_flags==1) PB=0;
  end
  always @(posedge CLK) if(!RESET) begin
    cycles=cycles+1;
    if(ctrl_pending) check(dut.cpu_ctrl===expected_ctrl,"CPU_CTRL did not latch MMIO write");
    ctrl_pending=0;
    if(dut.RV1.Busy && dut.RV1.SlowMul_E) slow_busy=slow_busy+1;
    if(dut.MemWrite_out[0] && dut.dec_CPU_CTRL) begin
      ctrl_writes=ctrl_writes+1;
      ctrl_pending=1;expected_ctrl=dut.WriteData_out[2:0];
      case(ctrl_writes)
        1:check(dut.WriteData_out[2:0]==1,"first control mode");
        2:check(dut.WriteData_out[2:0]==2,"second control mode");
        3:check(dut.WriteData_out[2:0]==4,"third control mode");
        4:check(dut.WriteData_out[2:0]==0,"restore all-on mode");
        default:check(0,"unexpected control store");
      endcase
    end
    if(dut.RV1.IntTake) begin irqs=irqs+1;epc_saved=dut.RV1.PC_D; end
    if(dut.RV1.Valid_E && dut.RV1.Mret_E) begin
      returns=returns+1;check(dut.RV1.CorrectPC_E==epc_saved,"system mret target");
    end
    if(dut.RV1.RegWrite_W && dut.RV1.rd_W==7) begin
      if(dut.RV1.Result_W==1) saw_status_one=1;
      if(dut.RV1.Result_W==0) saw_status_zero=1;
    end
    if(dut.RV1.RegWrite_W && dut.RV1.rd_W==31) begin
      #1;
      check(ctrl_writes==4 && dut.cpu_ctrl==0,"software-controlled feature switches");
      check(dut.RV1.RegFile1.RegBank[5]==42,"slow multiply through actual Wrapper");
      check(slow_busy>0,"MMIO slow-multiplier mode was not exercised");
      check(pixels==1 && swaps==1 && saw_status_one && saw_status_zero,"OLED pixel/present/status coverage");
      check(irqs==1 && returns==1 && dut.int_flags==0 && dut.RV1.RegFile1.RegBank[28]==1,
            "button interrupt, acknowledgement and exact-once handler");
      if(errors==0) $display("PASS: Wrapper MMIO feature controls, button interrupt, OLED pixel and present/status handshake.");
      else $fatal(1,"FAIL: system integration");
      $finish;
    end
  end
  initial begin #100000; $fatal(1,"FAIL: system timeout"); end
endmodule

