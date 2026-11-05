`timescale 1ns/1ps
// Supplementary simulation only. Uses the project's unchanged RV RTL.
// All architectural checks and event coverage must pass before PASS is printed.
module tb_all_enhancements;
  reg CLK=0, RESET=1;
  wire [4:0] done;
  wire [31:0] e0,e1,e2,e3,e4,c0,c1,c2,c3,c4,b0,b1,b2,b3,b4;
  always #5 CLK=~CLK;
  initial #22 RESET=0;
  enhancement_demo_core #(.CTRL(0),.LABEL("ALL_ON")) fast(CLK,RESET,done[0],e0,c0,b0);
  enhancement_demo_core #(.CTRL(1),.LABEL("NO_FORWARD")) nofwd(CLK,RESET,done[1],e1,c1,b1);
  enhancement_demo_core #(.CTRL(2),.LABEL("NO_PREDICT")) nopred(CLK,RESET,done[2],e2,c2,b2);
  enhancement_demo_core #(.CTRL(4),.LABEL("SLOW_MUL")) slow(CLK,RESET,done[3],e3,c3,b3);
  enhancement_demo_core #(.LIVE(1),.LABEL("LIVE_SWITCHES")) live(CLK,RESET,done[4],e4,c4,b4);
  initial begin
    wait(&done); #2;
    $display("Completion cycles ALL_ON=%0d NO_FORWARD=%0d NO_PREDICT=%0d SLOW_MUL=%0d LIVE=%0d",c0,c1,c2,c3,c4);
    $display("Conditional loop redirects ALL_ON=%0d NO_PREDICT=%0d (expected 2 and 7)",b0,b2);
    if ((e0+e1+e2+e3+e4)==0 && c0<c1 && c0<c2 && c0<c3 && b0==2 && b2==7)
      $display("PASS: seven CPU enhancements; architectural results, coverage, A/B comparisons all correct.");
    else $fatal(1,"FAIL: check per-core errors, coverage and A/B counts.");
    $finish;
  end
  initial begin #100000; $fatal(1,"FAIL: timeout"); end
endmodule

module enhancement_demo_core #(parameter [2:0] CTRL=0, parameter LIVE=0, parameter LABEL="CORE")
 (input CLK,input RESET,output reg done=0,output reg [31:0] errors=0,
  output reg [31:0] completion_cycles=0,output reg [31:0] branch_redirects=0);
  reg [2:0] cpu_ctrl=CTRL;
  reg Interrupt=0;
  wire [31:0] PC,ALUResult,WriteData_out;
  wire MemRead;
  wire [3:0] MemWrite_out;
  reg [31:0] Instr;
  reg [31:0] mem[0:63];
  wire [31:0] ReadData_in=mem[ALUResult[7:2]];
  RV dut(.CLK(CLK),.RESET(RESET),.Interrupt(Interrupt),.CpuCtrl(cpu_ctrl),.Instr(Instr),
    .ReadData_in(ReadData_in),.MemRead(MemRead),.MemWrite_out(MemWrite_out),
    .PC(PC),.ALUResult(ALUResult),.WriteData_out(WriteData_out));
  // Small asynchronous memory model with the same byte-enable interface as Wrapper.
  // The program uses aligned words/halfwords and low addresses ONLY in this CPU-only harness.
  integer i,j;
  initial begin
    for(i=0;i<64;i=i+1) mem[i]=0;
    mem[0]=32'h11223344;
    // Deterministic initial register contents for simulation (RF has no reset port).
    for(i=0;i<32;i=i+1) dut.RegFile1.RegBank[i]=0;
  end
  always @(posedge CLK)
    if(!RESET && !done && |MemWrite_out)
      for(j=0;j<4;j=j+1)
        if(MemWrite_out[j]) mem[ALUResult[7:2]][8*j+:8] <= WriteData_out[8*j+:8];

  always @* begin
    case(PC)
      32'h400000: Instr=32'h0200006f;
      32'h400004: Instr=32'h2fc0006f;
      32'h400020: Instr=32'h00500093;
      32'h400024: Instr=32'h00700113;
      32'h400028: Instr=32'h00900193;
      32'h40002c: Instr=32'h00b00213;
      32'h400030: Instr=32'h00d00293;
      32'h400034: Instr=32'h00128333;
      32'h400038: Instr=32'h01500393;
      32'h40003c: Instr=32'h00000013;
      32'h400040: Instr=32'h00000013;
      32'h400044: Instr=32'h00138413;
      32'h400048: Instr=32'h0180006f;
      32'h400060: Instr=32'h02208533;
      32'h400064: Instr=32'h024185b3;
      32'h400068: Instr=32'h02628633;
      32'h40006c: Instr=32'h0220868b;
      32'h400070: Instr=32'h00168713;
      32'h400074: Instr=32'h02c0006f;
      32'h4000a0: Instr=32'hff900793;
      32'h4000a4: Instr=32'h00500813;
      32'h4000a8: Instr=32'h0307888b;
      32'h4000ac: Instr=32'h030783b3;
      32'h4000b0: Instr=32'h03079433;
      32'h4000b4: Instr=32'h0013d393;
      32'h4000b8: Instr=32'h01f41413;
      32'h4000bc: Instr=32'h0083e4b3;
      32'h4000c0: Instr=32'h03079cb3;
      32'h4000c4: Instr=32'h0307bd33;
      32'h4000c8: Instr=32'h0107838b;
      32'h4000cc: Instr=32'h3f07840b;
      32'h4000d0: Instr=32'h0300006f;
      32'h400100: Instr=32'h08000913;
      32'h400104: Instr=32'h01200023;
      32'h400108: Instr=32'h08100913;
      32'h40010c: Instr=32'h012000a3;
      32'h400110: Instr=32'h08200913;
      32'h400114: Instr=32'h01200123;
      32'h400118: Instr=32'h08300913;
      32'h40011c: Instr=32'h012001a3;
      32'h400120: Instr=32'heed00913;
      32'h400124: Instr=32'h01201023;
      32'h400128: Instr=32'h000081b7;
      32'h40012c: Instr=32'h00118193;
      32'h400130: Instr=32'h00301123;
      32'h400134: Instr=32'h00000903;
      32'h400138: Instr=32'h01202223;
      32'h40013c: Instr=32'h00004903;
      32'h400140: Instr=32'h01202423;
      32'h400144: Instr=32'h00001903;
      32'h400148: Instr=32'h01202623;
      32'h40014c: Instr=32'h00005903;
      32'h400150: Instr=32'h01202823;
      32'h400154: Instr=32'h00002903;
      32'h400158: Instr=32'h00190993;
      32'h40015c: Instr=32'h0240006f;
      32'h400180: Instr=32'h00000a13;
      32'h400184: Instr=32'h00800a93;
      32'h400188: Instr=32'h001a0a13;
      32'h40018c: Instr=32'hff5a4ee3;
      32'h400190: Instr=32'h00c0006f;
      32'h400194: Instr=32'h06300d93;
      32'h400198: Instr=32'h00102a23;
      32'h40019c: Instr=32'h02a00b13;
      32'h4001a0: Instr=32'h0600006f;
      32'h400200: Instr=32'h00000b93;
      32'h400204: Instr=32'h00600c13;
      32'h400208: Instr=32'h001b8b93;
      32'h40020c: Instr=32'h00000013;
      32'h400210: Instr=32'h00000013;
      32'h400214: Instr=32'hff8bcae3;
      32'h400218: Instr=32'h0480006f;
      32'h400260: Instr=32'h02254eb3;
      32'h400264: Instr=32'h001e8f13;
      32'h400268: Instr=32'h07b00f93;
      32'h400300: Instr=32'h001e0e13;
      32'h400304: Instr=32'h30200073;
      default: Instr=32'h00000013;
    endcase
  end
  function [31:0] expected_reg;
    input integer r;
    begin case(r)
      0: expected_reg=32'h00000000;
      1: expected_reg=32'h00000005;
      2: expected_reg=32'h00000007;
      3: expected_reg=32'h00008001;
      4: expected_reg=32'h0000000b;
      5: expected_reg=32'h0000000d;
      6: expected_reg=32'h00000012;
      7: expected_reg=32'hffffffdd;
      8: expected_reg=32'hffffffff;
      9: expected_reg=32'hffffffee;
      10: expected_reg=32'h00000023;
      11: expected_reg=32'h00000063;
      12: expected_reg=32'h000000ea;
      13: expected_reg=32'h00000011;
      14: expected_reg=32'h00000012;
      15: expected_reg=32'hfffffff9;
      16: expected_reg=32'h00000005;
      17: expected_reg=32'hffffffee;
      18: expected_reg=32'h8001feed;
      19: expected_reg=32'h8001feee;
      20: expected_reg=32'h00000008;
      21: expected_reg=32'h00000008;
      22: expected_reg=32'h0000002a;
      23: expected_reg=32'h00000006;
      24: expected_reg=32'h00000006;
      25: expected_reg=32'hffffffff;
      26: expected_reg=32'h00000004;
      27: expected_reg=32'h00000000;
      28: expected_reg=32'h00000001;
      29: expected_reg=32'h00000005;
      30: expected_reg=32'h00000006;
      31: expected_reg=32'h0000007b;
      default: expected_reg=0;
    endcase end
  endfunction
  task check;
    input condition;
    input [8*120-1:0] message;
    begin
      if(condition !== 1'b1) begin
        errors=errors+1;
        $display("ERROR %s t=%0t: %0s",LABEL,$time,message);
      end
    end
  endtask
  integer cycles=0, stalls=0, busy_cycles=0, branch_visits=0, correct_taken=0;
  integer fwd_m=0,fwd_w=0,write_through=0,load_use=0,mul_use=0;
  integer irq_count=0,mret_count=0,stores=0,mode_changes=0,held_mode_changes=0;
  integer first_writes=0,last_first_cycle=0,burst_writes=0,last_mul_cycle=0;
  integer loop_cycles=0;
  reg irq_sent=0,irq_accepted=0;
  reg [31:0] saved_epc=0;
  reg held=0;
  reg previous_slow=0,previous_nofwd=0;
  reg [2:0] previous_ctrl=CTRL;
  reg [3:0] modes_seen=0;
  // Change controls and interrupt at falling edges to avoid clock-edge races.
  always @(negedge CLK) begin
    if(!RESET && !done) begin
      if(LIVE) begin
        case((cycles/9)%5)
          0:cpu_ctrl=0; 1:cpu_ctrl=1; 2:cpu_ctrl=2; 3:cpu_ctrl=4; 4:cpu_ctrl=7;
        endcase
      end
      if(!irq_sent && dut.Valid_D && dut.PC_D==32'h0040020c) begin
        Interrupt=1; irq_sent=1;
        $display("%s IRQ requested t=%0t",LABEL,$time);
      end
      // Keep the request high through the handler to test nesting suppression.
      if(irq_accepted && dut.Valid_E && dut.Mret_E) Interrupt=0;
    end
  end

  always @(posedge CLK) begin
    if(!RESET && !done) begin
      cycles=cycles+1;
      if(cpu_ctrl!=previous_ctrl) begin
        mode_changes=mode_changes+1;
        if(dut.StallE) held_mode_changes=held_mode_changes+1;
      end
      previous_ctrl=cpu_ctrl;
      if(cpu_ctrl==0) modes_seen[0]=1;
      if(cpu_ctrl==1) modes_seen[1]=1;
      if(cpu_ctrl==2) modes_seen[2]=1;
      if(cpu_ctrl==4) modes_seen[3]=1;
      if(held) begin
        check(dut.SlowMul_E===previous_slow,"SlowMul_E changed while E was held");
        check(dut.NoForward_E===previous_nofwd,"NoForward_E changed while E was held");
      end
      held=dut.StallE; previous_slow=dut.SlowMul_E; previous_nofwd=dut.NoForward_E;
      if(dut.StallD) stalls=stalls+1;
      if(dut.Busy) busy_cycles=busy_cycles+1;
      if(dut.Valid_E && !dut.StallE) begin
        if(dut.ForwardA_E==2 || dut.ForwardB_E==2) fwd_m=fwd_m+1;
        if(dut.ForwardA_E==1 || dut.ForwardB_E==1) fwd_w=fwd_w+1;
      end
      if(dut.Valid_D && !dut.StallD && dut.RegWrite_W && dut.rd_W!=0 &&
          dut.rs1_D==dut.rd_W && dut.UsesRs1_D) begin
        write_through=write_through+1;
        check(dut.RD1_D===dut.Result_W,"W-to-D register-file write-through failed");
      end
      if(dut.HazardUnit1.lwStall && !dut.Busy) begin
        check(dut.StallF && dut.StallD && dut.FlushE && !dut.StallE,
              "load/multiply-use must hold F/D and insert E bubble");
        if(dut.MemtoReg_E) load_use=load_use+1;
        if(dut.IsMul_E) mul_use=mul_use+1;
      end
      if(dut.Valid_E && !dut.StallE && dut.PC_E==32'h0040018c) begin
        branch_visits=branch_visits+1;
        if(dut.Redirect_E) branch_redirects=branch_redirects+1;
        if(dut.PredTaken_E && dut.Taken_E && !dut.Redirect_E) correct_taken=correct_taken+1;
        $display("%s LOOP t=%0t outcome=%b prediction=%b redirect=%b",LABEL,$time,
                 dut.Taken_E,dut.PredTaken_E,dut.Redirect_E);
      end
      if(dut.IntTake) begin
        check(!dut.InISR && !dut.StallRaw_D && !dut.Redirect_E,"invalid interrupt acceptance");
        irq_count=irq_count+1; saved_epc=dut.PC_D; irq_accepted=1;
        $display("%s IRQ accepted EPC=%08h t=%0t",LABEL,saved_epc,$time);
      end
      if(dut.Valid_E && dut.Mret_E) begin
        mret_count=mret_count+1;
        check(dut.CorrectPC_E===saved_epc,"mret target does not equal interrupted PC_D");
        $display("%s MRET target=%08h t=%0t",LABEL,dut.CorrectPC_E,$time);
      end
      if(dut.InISR) check(!dut.IntTake,"nested interrupt accepted while InISR");
      if(|MemWrite_out) begin
        stores=stores+1;
        case(stores)
          1:check(ALUResult==0 && MemWrite_out==1 && WriteData_out==32'h80808080,"sb lane 0");
          2:check(ALUResult==1 && MemWrite_out==2 && WriteData_out==32'h81818181,"sb lane 1");
          3:check(ALUResult==2 && MemWrite_out==4 && WriteData_out==32'h82828282,"sb lane 2");
          4:check(ALUResult==3 && MemWrite_out==8 && WriteData_out==32'h83838383,"sb lane 3");
          5:check(ALUResult==0 && MemWrite_out==3 && WriteData_out==32'hfeedfeed,"sh lower lanes");
          6:check(ALUResult==2 && MemWrite_out==12 && WriteData_out==32'h80018001,"sh upper lanes");
          7:check(ALUResult==4 && MemWrite_out==15 && WriteData_out==32'hffffffed,"lb sign extension");
          8:check(ALUResult==8 && MemWrite_out==15 && WriteData_out==32'h000000ed,"lbu zero extension");
          9:check(ALUResult==12 && MemWrite_out==15 && WriteData_out==32'hfffffeed,"lh sign extension");
          10:check(ALUResult==16 && MemWrite_out==15 && WriteData_out==32'h0000feed,"lhu zero extension");
          default:check(0,"unexpected store, possibly wrong-path side effect");
        endcase
        $display("%s STORE addr=%08h lanes=%b data=%08h",LABEL,ALUResult,MemWrite_out,WriteData_out);
      end
      // Samples writeback BEFORE nonblocking clock-edge updates.
      if(dut.RegWrite_W && dut.rd_W!=0) begin
        if(dut.rd_W>=1 && dut.rd_W<=5 && first_writes<5) begin
          if(CTRL==0 && !LIVE && first_writes>0)
            check(cycles==last_first_cycle+1,"independent initial instructions did not commit consecutively");
          first_writes=first_writes+1; last_first_cycle=cycles;
        end
        if(dut.rd_W>=10 && dut.rd_W<=12) begin
          case(dut.rd_W)
            10:check(dut.Result_W===32'd35,"mul 5*7");
            11:check(dut.Result_W===32'd99,"mul 9*11");
            12:check(dut.Result_W===32'd234,"mul 13*18");
          endcase
          if(CTRL==0 && !LIVE && burst_writes>0)
            check(cycles==last_mul_cycle+1,"independent fast multiplies did not commit consecutively");
          burst_writes=burst_writes+1;last_mul_cycle=cycles;
        end
        if(dut.rd_W==31) begin
          completion_cycles=cycles;
          #1; // Let the register-file write and pipeline registers settle.
          for(i=0;i<32;i=i+1) begin
            if(i!=0 && dut.RegFile1.RegBank[i] !== expected_reg(i)) begin
              $display("ERROR %s x%0d actual=%08h expected=%08h",LABEL,i,dut.RegFile1.RegBank[i],expected_reg(i));
              errors=errors+1;
            end
          end
          check(mem[0]===32'h8001feed,"partial stores corrupted the final word");
          check(mem[1]===32'hffffffed && mem[2]===32'hed &&
                mem[3]===32'hfffffeed && mem[4]===32'hfeed,"loaded values not stored correctly");
          check(mem[5]===0,"wrong-path store changed canary memory");
          check(stores==10 && burst_writes==3 && first_writes==5,"missing/duplicate architectural events");
          check(branch_visits==8,"loop did not execute eight branch outcomes");
          check(irq_count==1 && mret_count==1,"interrupt must be handled and returned exactly once");
          check(saved_epc==32'h0040020c && dut.EPC===saved_epc,"precise EPC differs from interrupted D PC");
          check(write_through>0 && load_use>0 && mul_use>0,"missing write-through/load-use/multiply-use coverage");
          if(CTRL==0 && !LIVE) begin
            check(fwd_m>0 && fwd_w>0,"both M and W forwarding must be observed");
            check(correct_taken==6 && branch_redirects==2,"BTB loop learning/exit behaviour");
          end
          if(CTRL==1) check(fwd_m==0 && fwd_w==0 && stalls>0,"forwarding-disable comparison ineffective");
          if(CTRL==2) check(correct_taken==0 && branch_redirects==7,"prediction-disable comparison ineffective");
          if(CTRL==4) check(busy_cycles>100,"slow multiplier did not produce long stalls");
          if(LIVE) check(mode_changes>3 && modes_seen==15 && held_mode_changes>0,"live switching coverage incomplete");
          $display("%s RESULTS errors=%0d cycles=%0d stalls=%0d busy=%0d M_fwd=%0d W_fwd=%0d write_through=%0d load_use=%0d mul_use=%0d mode_changes=%0d held_changes=%0d",
            LABEL,errors,cycles,stalls,busy_cycles,fwd_m,fwd_w,write_through,load_use,mul_use,mode_changes,held_mode_changes);
          done=1;
        end
      end
    end
  end
endmodule

