//COMPILE: iverilog.exe -g2012 -o riscvsingle.vcd -tvvp .\riscvsingle.sv

//Warning normal, continuar simulação -- sorry: constant selects in always_* processes are not currently supported (all bits will be included). 
//SIMULATE: vvp riscvsingle.vcd

module testbench();

  logic clk;
  logic reset;

  logic [31:0] WriteData, DataAdr;
  logic MemWrite;

  top dut(clk, reset, WriteData, DataAdr, MemWrite);

  initial begin
    reset <= 1;
    #22;
    reset <= 0;
  end

  always begin
    clk <= 1;
    #5;
    clk <= 0;
    #5;
  end

  always @(negedge clk) begin
    if (MemWrite) begin
      if (DataAdr === 100 & WriteData === 25) begin
        $display("Simulation succeeded");
        $stop;
      end else if (DataAdr !== 96) begin
        $display("Simulation failed");
        $stop;
      end
    end
  end
endmodule


// ------------------------------------------ // ---------------------------------------- //


module top( //Placa mãe
  input logic clk, reset, // Sinais de entrada de Clock e Resete
  output logic [31:0] WriteData, DataAdr, //Sinais de saída, dado a ser salvo e endereço de memória do dado
  output logic MemWrite //Sinal de saída: MemWrite = 1 -> Salva na memória; MemWrite = 0 -> Não salva na memória
);

  logic [31:0] PC, Instr, ReadData; //Fios de 32 bits para ligar os componentes

  riscvsingle rvsingle(clk, reset, PC, Instr, MemWrite, DataAdr, WriteData, ReadData); //Conecta os pinos físicos do processador aos fios declarados acima
  imem imem(PC, Instr); //imem = memória de instrução; Recebe o endereço (PC) e devolve a instrução (Instr) daquela linha
  dmem dmem(clk, MemWrite, DataAdr, WriteData, ReadData); //  dmem = memória de dados; Recebe Clock, Sinal de escrita, endereço e dado. Devolve o dado lido (ReadData)

endmodule

module riscvsingle( //Processador
  input logic clk, reset, //Sinais de entrada de Clock e Reset 
  output logic [31:0] PC, //Endereço da instruçao atual (Program Counter)
  input logic [31:0] Instr, //A instrução de 32 bits que veio da memória
  output logic MemWrite, //Sinal de escrita de dados na memória
  output logic [31:0] ALUResult, WriteData, //Resultado da conta feita na ALU e o dado a ser lido
  input logic [31:0] ReadData //Dado que foi lido na memória
);

  logic ALUSrc, RegWrite, Jump, Zero, PCSrc; 
  logic [1:0] ResultSrc, ImmSrc;
  logic [2:0] ALUControl;

  controller c( //Lê partes específicas da instrução (OpCode, Funct3, Etc) e gera os sinais de controle
    Instr[6:0], Instr[14:12], Instr[30], Zero,
    ResultSrc, MemWrite, PCSrc,
    ALUSrc, RegWrite, Jump,
    ImmSrc, ALUControl
  );

  datapath dp( //Recebe os sinais de controle do 'cérebro' e faz a movimentação real dos dados (Somas, Branches, etc...)
    clk, reset, ResultSrc, PCSrc,
    ALUSrc, RegWrite,
    ImmSrc, ALUControl,
    Zero, PC, Instr,
    ALUResult, WriteData, ReadData
  );

endmodule

module controller( //Decisão de acionamento dos botões no datapath
  input logic [6:0] op, //OPCode (Diz o tipo da instrução)
  input logic [2:0] funct3, //3 bits que, junto com o funct7, diferenciam instruções com o mesmo OpCode (ex: add vs sub no R-Type)
  input logic funct7b5, // Funct7 (bit 5): Usado para ajudar a diferenciar Add(0) de Sub(1) no R-Type
  input logic Zero,  //Sinal avisando se o resultado deu zero
  output logic [1:0] ResultSrc, //Mux: de onde vem o resultado final
  output logic MemWrite,  //Escrita na memória?
  output logic PCSrc, ALUSrc, //Muxes: Atualiza o PC? Usa um imediato?
  output logic RegWrite, Jump, //Escreve em registrador? É instrução de Salto?
  output logic [1:0] ImmSrc, //Qual o formato da constante?
  output logic [2:0] ALUControl //O que a ALU deve fazer? (Soma, Sub, And, Or)
);

  logic [1:0] ALUOp; //Fio interno: Categoria geral da operação da ALU  
  logic Branch; //Fio interno: Desvio condicional

  maindec md(op, ResultSrc, MemWrite, Branch, ALUSrc, RegWrite, Jump, ImmSrc, ALUOp); //Decodificador principal: Olha pro OpCode e define a maioria dos Sinais
  aludec ad(op[5], funct3, funct7b5, ALUOp, ALUControl);  //Decodificador das ALU: Olha pros detalhes e define a conta da ALU

  assign PCSrc = (Branch & Zero) | Jump; //- Jump foi adicionado na correção do código original, só permitia salto em branch tomado (beq), instruções de jump como jal nunca funcionariam. - 
                                         //Após correção, PC Vai saltar se for um Branch válido ou se for uma ordem direta de Jump

endmodule

module maindec(
  input logic [6:0] op,
  output logic [1:0] ResultSrc,
  output logic MemWrite,
  output logic Branch, ALUSrc,
  output logic RegWrite, Jump,
  output logic [1:0] ImmSrc,
  output logic [1:0] ALUOp
);

  logic [10:0] controls; //Barramento de *11* bits agrupando os sinais de controle

  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump} = controls; //- Jump foi adicionado na correção; o barramento 'controls' passou de 10 para 11 bits no total, distribuídos entre esses 8 sinais -

  always_comb //Bloco que avalia as condições imediatamente como portas lógicas
    case (op) //Verifica o OpCode da instrução
      7'b0000011: controls = 11'b1_00_1_0_01_0_00_0; // Lw
      7'b0100011: controls = 11'b0_01_1_1_00_0_00_0; // Sw
      7'b0110011: controls = 11'b1_xx_0_0_00_0_10_0; // Operações R-Type (Add, Sub, And, Or)
      7'b1100011: controls = 11'b0_10_0_0_00_1_01_0; // BeQ
      7'b0010011: controls = 11'b1_00_1_0_00_0_10_0; // Addi -> Adicionado na correção do código original
      7'b1101111: controls = 11'b1_11_x_0_10_0_xx_1; // Jal -> Adicionado na correção do código original
      default:    controls = 11'bx_xx_x_x_xx_x_xx_x; // Don't care
    endcase

endmodule

module aludec(
  input logic opb5,
  input logic [2:0] funct3,
  input logic funct7b5,
  input logic [1:0] ALUOp,
  output logic [2:0] ALUControl
);

  logic RtypeSub;

  assign RtypeSub = funct7b5 & opb5; // Subtração se for R-Type (opb5 = 1) e o Bit 5 dos 7 bits funct7 seja = 1 

  always_comb
    case (ALUOp) //Avalia a categoria vindo do MainDec
      2'b00: ALUControl = 3'b000; // Se for 00 (ex: lw/sw), a ALU deve sempre somar o endereço base com o offset
      2'b01: ALUControl = 3'b001; // Se for 01 (ex: beq), a ALU deve subtratir para ver se dá zero

      default:
        case (funct3) //Se for R-Type/I-Type, olha para o funct3 para decidir a operação matemática exata (000 = add/sub; 110 = or; 111 = and)
          3'b000: if (RtypeSub) ALUControl = 3'b001;
                   else ALUControl = 3'b000;
          3'b010: ALUControl = 3'b101;
          3'b110: ALUControl = 3'b011;
          3'b111: ALUControl = 3'b010;
          default: ALUControl = 3'bxxx;
        endcase
    endcase

endmodule

module datapath(
  input logic clk, reset,                //------
  input logic [1:0] ResultSrc,                //------
  input logic PCSrc, ALUSrc,                       //------
  input logic RegWrite,                                 //------
  input logic [1:0] ImmSrc,                                 //------
  input logic [2:0] ALUControl,                                  //------> Declaração de fios internos (entradas e saídas)
  output logic Zero,                                        //------
  output logic [31:0] PC,                             //------
  input logic [31:0] Instr,                     //------
  output logic [31:0] ALUResult, WriteData,  //------
  input logic [31:0] ReadData           //------
);

  //Fios internos do datapath
  logic [31:0] PCNext, PCPlus4, PCTarget;
  logic [31:0] ImmExt;
  logic [31:0] SrcA, SrcB;
  logic [31:0] Result;

  flopr #(32) pcreg(clk, reset, PCNext, PC); //FFd que guarda a linha atual do programa. Atualiza para PcNext na batida do Clock
  adder pcadd4(PC, 32'd4, PCPlus4); //PC + 4 (Endereço da próxiima instrução na fila)
  adder pcaddbranch(PC, ImmExt, PCTarget); //PC + Imediato (Endereço de destino caso haja um salto/branch)
  mux2 #(32) pcmux(PCPlus4, PCTarget, PCSrc, PCNext); //Escolhe o próximo PC. Destino do salto (PCTarget) ou segue reto (PCPlus4)

  regfile rf(clk, RegWrite, Instr[19:15], Instr[24:20], //Lança os endereços contidos na instrução para ler ou escrever
             Instr[11:7], Result, SrcA, WriteData); 

  extend ext(Instr[31:7], ImmSrc, ImmExt); //Extrai o imediato da instrução e transforma em 32 bits

  mux2 #(32) srcbmux(WriteData, ImmExt, ALUSrc, SrcB); //O segundo termo da conta vem do registrador (WriteData) ou da instrução (ImmExt)
  
  alu alu(SrcA, SrcB, ALUControl, ALUResult, Zero); //Executa a conta entre SrcA e SrcB e retorna ALUResult e a flag Zero

  mux3 #(32) resultmux(ALUResult, ReadData, PCPlus4, ResultSrc, Result); // - 32'b0 foi alterado para PCPlus4, logo, a terceira entrada do Mux seria Zero, porém para jal, deveria escrever PC+4 no registrador destino -
                                                                         // Mux triplo: Se ResultSrc = 00 -> resultado da ALU; ResultSrc = 01 -> dado na memória (ReadData); ResultSrc = 10 -> PC + 4 (Enderço de retorno usado pelo jal); 
endmodule

module regfile(
  input logic clk, //Clock
  input logic we3, //Permissão para escrita (Write Enable)
  input logic [4:0] a1, a2, a3, //Endereços (Qual ler em 1? em 2? Onde gravar em 3?)
  input logic [31:0] wd3, //Escrita de dados após permissão (WriteData)
  output logic [31:0] rd1, rd2 //Saída de dados para leitura (ReadData)
);

  logic [31:0] rf[31:0]; //Matriz 32x32

  always_ff @(posedge clk) //A escrita só ocorre na subida da borda do clock
    if (we3) rf[a3] <= wd3; // Caso WE3 = 1, guarda o dado WD3 no reg. [a3]

  assign rd1 = (a1 != 0) ? rf[a1] : 0; //-
                                        //- Combinacional: leitura imediata, registrado 0 (x0) está 'aterrado' e sempre retorna 0.
  assign rd2 = (a2 != 0) ? rf[a2] : 0; //-

endmodule

module adder( //Somador simples
  input [31:0] a, b,
  output [31:0] y
);

  assign y = a + b;

endmodule

module extend( 
  input logic [31:7] instr, //Recebe a instrução do bit 7 ao 31
  input logic [1:0] immsrc, //Código dizedno qual o formato
  output logic [31:0] immext //Numero final de 32 bits ajustado com sinal
);

  always_comb
    case (immsrc)
      2'b00: immext = {{20{instr[31]}}, instr[31:20]}; //- Foi adicionado após correção - I-Type (ex: addi). Pega os bits de 31 a 20 e repete o bit de sinal 20 vezes a esquerda
      2'b01: immext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; // S-Type (ex: sw). Junta os bits de cima com os bits de baixo. Repete Sinal
      2'b10: immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; //- Foi adicionado após correção - B-Type (ex: BeQ). Junta os bits espalhados, repete sinal e adiciona 0 no final
      2'b11: immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; // J-Type (ex: jal). Extrai os 20 bits espalhados, repete sinal 12 vezes e adiciona um 0 no final
      default: immext = 32'bx;
    endcase

endmodule

module flopr #(parameter WIDTH = 8)(  //Flip Flop D
  input logic clk, reset,
  input logic [WIDTH-1:0] d,
  output logic [WIDTH-1:0] q
);

  always_ff @(posedge clk, posedge reset)
    if (reset) q <= 0;
    else q <= d;

endmodule

module mux2 #(parameter WIDTH = 8)( //Mux 2 Vias
  input logic [WIDTH-1:0] d0, d1,
  input logic s,
  output logic [WIDTH-1:0] y
);

  assign y = s ? d1 : d0;

endmodule

module mux3 #(parameter WIDTH = 8)( //Mux 3 Vias
  input logic [WIDTH-1:0] d0, d1, d2,
  input logic [1:0] s,
  output logic [WIDTH-1:0] y
);

  assign y = s[1] ? d2 : (s[0] ? d1 : d0);

endmodule

module imem( //Memória ROM
  input logic [31:0] a,
  output logic [31:0] rd
);

  logic [31:0] RAM[63:0];

  initial //Executa 1 vez ao rodar o simulador
    $readmemh("riscvtest.txt", RAM); //Carrega o código Hexa do TXT

  assign rd = RAM[a[31:2]]; //Converte o endereçamento de byte para word

endmodule

module dmem( //Memória RAM
  input logic clk, we,
  input logic [31:0] a, wd,
  output logic [31:0] rd
);

  logic [31:0] RAM[63:0];

  assign rd = RAM[a[31:2]]; //Leitura assíncrona (imediata)

  always_ff @(posedge clk)  //Escrita Síncrona (Grava no Clock)
    if (we) RAM[a[31:2]] <= wd;

endmodule

module alu(
  input logic [31:0] a, b,
  input logic [2:0] alucontrol,
  output logic [31:0] result,
  output logic zero
);

  logic [31:0] condinvb, sum;
  logic v;
  logic isAddSub;

  assign condinvb = alucontrol[0] ? ~b : b; //Se alucontrol[0] for 1 (Subtração), inverte os bits de 'b' (~b) -> Complemento de dois
  assign sum = a + condinvb + alucontrol[0]; // Se soma A + B (Adição) ou A + ~B + 1 (Subtração complemento de dois)

  assign isAddSub = //Identifica se é subtração ou adição
    ~alucontrol[2] & ~alucontrol[1] |
    ~alucontrol[1] & alucontrol[0];

  always_comb //Multiplexador interno da ALU
    case (alucontrol)
      3'b000: result = sum;
      3'b001: result = sum; //Subtração -> Complemento de dois
      3'b010: result = a & b; //And
      3'b011: result = a | b; //Or
      3'b100: result = a ^ b; //Xor
      3'b101: result = sum[31] ^ v; //Menor que
      3'b110: result = a << b[4:0]; //Shift Left
      3'b111: result = a >> b[4:0]; //Shift Right
      default: result = 32'bx;
    endcase

  assign zero = (result == 32'b0); //Seta a flag zero se todos os resultados forem iguais a zero

  assign v = //Calcula overflow
    ~(alucontrol[0] ^ a[31] ^ b[31]) &
    (a[31] ^ sum[31]) &
    isAddSub;

endmodule