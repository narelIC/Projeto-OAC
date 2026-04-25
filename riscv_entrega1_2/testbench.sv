
module testbench();
  logic        clk;
  logic        reset;
  logic [31:0] WriteData, DataAdr;
  logic        MemWrite;

  top dut(clk, reset, WriteData, DataAdr, MemWrite);
  
  initial begin
    reset = 1;
    clk = 0; 
    #22; 
    reset = 0;
  end

  always begin
    #5 clk = ~clk;
  end

  always @(negedge clk) begin
    if(MemWrite) begin
      if(DataAdr === 100 & WriteData === 25) begin
        $display("Simulation succeeded");
        $stop;
      end else if (DataAdr !== 96) begin
        $display("Simulation failed");
        $stop;
      end
    end
  end

  always @(posedge clk) begin
    $display("Tempo: %0t | PC: %h | Instrucao: %h | Escrevendo: %b | Adr: %d | Data: %d", 
              $time, dut.PC, dut.Instr, MemWrite, DataAdr, WriteData);
  end
endmodule

module top(input  logic        clk, reset, 
           output logic [31:0] WriteData, DataAdr, 
           output logic        MemWrite);

  logic [31:0] PC, Instr, ReadData;
  
  riscvsingle rvsingle(clk, reset, PC, Instr, MemWrite, DataAdr, WriteData, ReadData);
  imem imem(PC, Instr);
  dmem dmem(clk, MemWrite, DataAdr, WriteData, ReadData);
endmodule