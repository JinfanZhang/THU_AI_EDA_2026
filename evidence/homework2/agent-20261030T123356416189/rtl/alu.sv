module alu (
    input  logic [3:0]  alu_op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] imm,
    input  logic [31:0] pc,
    input  logic [2:0]  br_funct3,
    output logic [31:0] result,
    output logic        br_taken,
    output logic [31:0] br_target
);

    localparam logic [3:0] ALU_ADD    = 4'd0;
    localparam logic [3:0] ALU_SUB    = 4'd1;
    localparam logic [3:0] ALU_SLL    = 4'd2;
    localparam logic [3:0] ALU_SLT    = 4'd3;
    localparam logic [3:0] ALU_SLTU   = 4'd4;
    localparam logic [3:0] ALU_XOR    = 4'd5;
    localparam logic [3:0] ALU_SRL    = 4'd6;
    localparam logic [3:0] ALU_SRA    = 4'd7;
    localparam logic [3:0] ALU_OR     = 4'd8;
    localparam logic [3:0] ALU_AND    = 4'd9;
    localparam logic [3:0] ALU_LUI    = 4'd10;
    localparam logic [3:0] ALU_AUIPC  = 4'd11;
    localparam logic [3:0] ALU_PC4    = 4'd12;
    localparam logic [3:0] ALU_PASS   = 4'd13;
    localparam logic [3:0] ALU_BRANCH = 4'd14;
    localparam logic [3:0] ALU_JUMP   = 4'd15;

    logic [4:0] shamt;
    logic       lt_s;
    logic       lt_u;
    logic       eq;
    logic [31:0] sum;

    always_comb begin
        shamt = b[4:0];
        lt_s  = ($signed(a) < $signed(b));
        lt_u  = (a < b);
        eq    = (a == b);
        sum   = a + b;

        result = 32'b0;
        unique case (alu_op)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = a - b;
            ALU_SLL:    result = a << shamt;
            ALU_SLT:    result = {31'b0, lt_s};
            ALU_SLTU:   result = {31'b0, lt_u};
            ALU_XOR:    result = a ^ b;
            ALU_SRL:    result = a >> shamt;
            ALU_SRA:    result = $signed(a) >>> shamt;
            ALU_OR:     result = a | b;
            ALU_AND:    result = a & b;
            ALU_LUI:    result = imm;
            ALU_AUIPC:  result = pc + imm;
            ALU_PC4:    result = pc + 32'd4;
            ALU_PASS:   result = a;
            ALU_BRANCH: result = 32'b0;
            ALU_JUMP:   result = pc + 32'd4;
            default:    result = 32'b0;
        endcase
    end

    always_comb begin
        br_taken = 1'b0;
        unique case (br_funct3)
            3'b000: br_taken = eq;
            3'b001: br_taken = ~eq;
            3'b100: br_taken = lt_s;
            3'b101: br_taken = ~lt_s;
            3'b110: br_taken = lt_u;
            3'b111: br_taken = ~lt_u;
            default: br_taken = 1'b0;
        endcase
    end

    always_comb begin
        if (alu_op == ALU_JUMP)
            br_target = (sum & 32'hFFFF_FFFE);
        else
            br_target = pc + imm;
    end

endmodule
