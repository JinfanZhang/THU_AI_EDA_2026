module id_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ifid_valid,
    input  logic [31:0] ifid_pc,
    input  logic [31:0] ifid_pc4,
    input  logic [31:0] ifid_instr,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic        flush,
    output logic [4:0]  rs1_addr,
    output logic [4:0]  rs2_addr,
    output logic        id_is_ecall,
    output logic        id_ex_valid,
    output logic [31:0] id_ex_pc,
    output logic [31:0] id_ex_pc4,
    output logic [4:0]  id_ex_rs1,
    output logic [4:0]  id_ex_rs2,
    output logic [4:0]  id_ex_rd,
    output logic [31:0] id_ex_rs1_data,
    output logic [31:0] id_ex_rs2_data,
    output logic [31:0] id_ex_imm,
    output logic [3:0]  id_ex_alu_op,
    output logic [1:0]  id_ex_alu_a_sel,
    output logic [1:0]  id_ex_alu_b_sel,
    output logic        id_ex_is_branch,
    output logic [2:0]  id_ex_branch_f3,
    output logic        id_ex_is_jal,
    output logic        id_ex_is_jalr,
    output logic        id_ex_is_load,
    output logic        id_ex_is_store,
    output logic [2:0]  id_ex_mem_f3,
    output logic        id_ex_reg_write,
    output logic        id_ex_is_ecall
);

    localparam logic [3:0] ALU_ADD  = 4'd0;
    localparam logic [3:0] ALU_SUB  = 4'd1;
    localparam logic [3:0] ALU_SLL  = 4'd2;
    localparam logic [3:0] ALU_SLT  = 4'd3;
    localparam logic [3:0] ALU_SLTU = 4'd4;
    localparam logic [3:0] ALU_XOR  = 4'd5;
    localparam logic [3:0] ALU_SRL  = 4'd6;
    localparam logic [3:0] ALU_SRA  = 4'd7;
    localparam logic [3:0] ALU_OR   = 4'd8;
    localparam logic [3:0] ALU_AND  = 4'd9;

    localparam logic [1:0] A_RS1 = 2'd0;
    localparam logic [1:0] A_PC  = 2'd1;
    localparam logic [1:0] A_ZERO= 2'd2;
    localparam logic [1:0] B_RS2 = 2'd0;
    localparam logic [1:0] B_IMM = 2'd1;

    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [4:0]  rd;

    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;
    logic [31:0] imm;

    logic [3:0]  alu_op;
    logic [1:0]  alu_a_sel;
    logic [1:0]  alu_b_sel;
    logic        is_branch;
    logic        is_jal;
    logic        is_jalr;
    logic        is_load;
    logic        is_store;
    logic        reg_write;
    logic        is_ecall;
    logic        is_lui;
    logic        is_auipc;

    assign opcode = ifid_instr[6:0];
    assign funct3 = ifid_instr[14:12];
    assign funct7 = ifid_instr[31:25];
    assign rd     = ifid_instr[11:7];

    assign rs1_addr = ifid_instr[19:15];
    assign rs2_addr = ifid_instr[24:20];

    assign imm_i = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
    assign imm_s = {{20{ifid_instr[31]}}, ifid_instr[31:25], ifid_instr[11:7]};
    assign imm_b = {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7],
                    ifid_instr[30:25], ifid_instr[11:8], 1'b0};
    assign imm_u = {ifid_instr[31:12], 12'b0};
    assign imm_j = {{11{ifid_instr[31]}}, ifid_instr[31], ifid_instr[19:12],
                    ifid_instr[20], ifid_instr[30:21], 1'b0};

    assign is_ecall = (ifid_instr == 32'h0000_0073);

    always_comb begin
        imm          = 32'b0;
        alu_op       = ALU_ADD;
        alu_a_sel    = A_RS1;
        alu_b_sel    = B_IMM;
        is_branch    = 1'b0;
        is_jal       = 1'b0;
        is_jalr      = 1'b0;
        is_load      = 1'b0;
        is_store     = 1'b0;
        reg_write    = 1'b0;
        is_lui       = 1'b0;
        is_auipc     = 1'b0;

        case (opcode)
            7'b0110011: begin // R-type
                reg_write = 1'b1;
                alu_a_sel = A_RS1;
                alu_b_sel = B_RS2;
                case (funct3)
                    3'b000: alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                    3'b001: alu_op = ALU_SLL;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end
            7'b0010011: begin // I-type ALU
                reg_write = 1'b1;
                imm       = imm_i;
                alu_a_sel = A_RS1;
                alu_b_sel = B_IMM;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b001: alu_op = ALU_SLL;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end
            7'b0000011: begin // Load
                reg_write = 1'b1;
                is_load   = 1'b1;
                imm       = imm_i;
                alu_op    = ALU_ADD;
                alu_a_sel = A_RS1;
                alu_b_sel = B_IMM;
            end
            7'b0100011: begin // Store
                is_store  = 1'b1;
                imm       = imm_s;
                alu_op    = ALU_ADD;
                alu_a_sel = A_RS1;
                alu_b_sel = B_IMM;
            end
            7'b1100011: begin // Branch
                is_branch = 1'b1;
                imm       = imm_b;
                alu_op    = ALU_ADD;
                alu_a_sel = A_RS1;
                alu_b_sel = B_IMM;
            end
            7'b1101111: begin // JAL
                reg_write = 1'b1;
                is_jal    = 1'b1;
                imm       = imm_j;
                alu_op    = ALU_ADD;
                alu_a_sel = A_PC;
                alu_b_sel = B_IMM;
            end
            7'b1100111: begin // JALR
                reg_write = 1'b1;
                is_jalr   = 1'b1;
                imm       = imm_i;
                alu_op    = ALU_ADD;
                alu_a_sel = A_RS1;
                alu_b_sel = B_IMM;
            end
            7'b0110111: begin // LUI
                reg_write = 1'b1;
                is_lui    = 1'b1;
                imm       = imm_u;
                alu_op    = ALU_ADD;
                alu_a_sel = A_ZERO;
                alu_b_sel = B_IMM;
            end
            7'b0010111: begin // AUIPC
                reg_write = 1'b1;
                is_auipc  = 1'b1;
                imm       = imm_u;
                alu_op    = ALU_ADD;
                alu_a_sel = A_PC;
                alu_b_sel = B_IMM;
            end
            7'b1110011: begin // ECALL
                if (is_ecall) begin
                    reg_write = 1'b0;
                end
            end
            default: begin
                reg_write = 1'b0;
            end
        endcase
    end

    assign id_is_ecall = ifid_valid && is_ecall;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            id_ex_valid       <= 1'b0;
            id_ex_pc          <= 32'b0;
            id_ex_pc4         <= 32'b0;
            id_ex_rs1         <= 5'b0;
            id_ex_rs2         <= 5'b0;
            id_ex_rd          <= 5'b0;
            id_ex_rs1_data    <= 32'b0;
            id_ex_rs2_data    <= 32'b0;
            id_ex_imm         <= 32'b0;
            id_ex_alu_op      <= 4'b0;
            id_ex_alu_a_sel   <= 2'b0;
            id_ex_alu_b_sel   <= 2'b0;
            id_ex_is_branch   <= 1'b0;
            id_ex_branch_f3   <= 3'b0;
            id_ex_is_jal      <= 1'b0;
            id_ex_is_jalr     <= 1'b0;
            id_ex_is_load     <= 1'b0;
            id_ex_is_store    <= 1'b0;
            id_ex_mem_f3      <= 3'b0;
            id_ex_reg_write   <= 1'b0;
            id_ex_is_ecall    <= 1'b0;
        end else if (flush) begin
            id_ex_valid       <= 1'b0;
            id_ex_pc          <= 32'b0;
            id_ex_pc4         <= 32'b0;
            id_ex_rs1         <= 5'b0;
            id_ex_rs2         <= 5'b0;
            id_ex_rd          <= 5'b0;
            id_ex_rs1_data    <= 32'b0;
            id_ex_rs2_data    <= 32'b0;
            id_ex_imm         <= 32'b0;
            id_ex_alu_op      <= 4'b0;
            id_ex_alu_a_sel   <= 2'b0;
            id_ex_alu_b_sel   <= 2'b0;
            id_ex_is_branch   <= 1'b0;
            id_ex_branch_f3   <= 3'b0;
            id_ex_is_jal      <= 1'b0;
            id_ex_is_jalr     <= 1'b0;
            id_ex_is_load     <= 1'b0;
            id_ex_is_store    <= 1'b0;
            id_ex_mem_f3      <= 3'b0;
            id_ex_reg_write   <= 1'b0;
            id_ex_is_ecall    <= 1'b0;
        end else begin
            id_ex_valid       <= ifid_valid;
            id_ex_pc          <= ifid_pc;
            id_ex_pc4         <= ifid_pc4;
            id_ex_rs1         <= ifid_instr[19:15];
            id_ex_rs2         <= ifid_instr[24:20];
            id_ex_rd          <= rd;
            id_ex_rs1_data    <= rs1_data;
            id_ex_rs2_data    <= rs2_data;
            id_ex_imm         <= imm;
            id_ex_alu_op      <= alu_op;
            id_ex_alu_a_sel   <= alu_a_sel;
            id_ex_alu_b_sel   <= alu_b_sel;
            id_ex_is_branch   <= is_branch;
            id_ex_branch_f3   <= funct3;
            id_ex_is_jal      <= is_jal;
            id_ex_is_jalr     <= is_jalr;
            id_ex_is_load     <= is_load;
            id_ex_is_store    <= is_store;
            id_ex_mem_f3      <= funct3;
            id_ex_reg_write   <= reg_write;
            id_ex_is_ecall    <= is_ecall;
        end
    end

endmodule
