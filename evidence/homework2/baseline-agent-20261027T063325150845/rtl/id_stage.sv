module id_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush,
    input  logic        if_valid,
    input  logic [31:0] if_pc,
    input  logic [31:0] if_pc4,
    input  logic [31:0] if_instr,
    input  logic        wb_we,
    input  logic [4:0]  wb_rd,
    input  logic [31:0] wb_data,
    input  logic [4:0]  dbg_reg_addr,
    output logic [31:0] dbg_reg_data,
    output logic [31:0] x10_data,
    output logic        id_valid,
    output logic [4:0]  id_rs1,
    output logic [4:0]  id_rs2,
    output logic        id_uses_rs1,
    output logic        id_uses_rs2,
    output logic        id_ecall,
    output logic        id_ex_valid,
    output logic [31:0] id_ex_pc,
    output logic [31:0] id_ex_pc4,
    output logic [31:0] id_ex_instr,
    output logic [31:0] id_ex_rs1_data,
    output logic [31:0] id_ex_rs2_data,
    output logic [4:0]  id_ex_rs1,
    output logic [4:0]  id_ex_rs2,
    output logic [4:0]  id_ex_rd,
    output logic [31:0] id_ex_imm,
    output logic [3:0]  id_ex_alu_op,
    output logic [1:0]  id_ex_alu_a_sel,
    output logic        id_ex_alu_b_sel,
    output logic        id_ex_reg_write,
    output logic        id_ex_mem_read,
    output logic        id_ex_mem_write,
    output logic [2:0]  id_ex_mem_size,
    output logic [1:0]  id_ex_wb_sel,
    output logic [3:0]  id_ex_branch,
    output logic [1:0]  id_ex_jump,
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

    localparam logic [1:0] A_RS1  = 2'd0;
    localparam logic [1:0] A_PC   = 2'd1;
    localparam logic [1:0] A_ZERO = 2'd2;

    localparam logic [1:0] WB_ALU  = 2'd0;
    localparam logic [1:0] WB_LOAD = 2'd1;
    localparam logic [1:0] WB_PC4  = 2'd2;

    localparam logic [3:0] BR_NONE = 4'd0;
    localparam logic [3:0] BR_BEQ  = 4'd1;
    localparam logic [3:0] BR_BNE  = 4'd2;
    localparam logic [3:0] BR_BLT  = 4'd3;
    localparam logic [3:0] BR_BGE  = 4'd4;
    localparam logic [3:0] BR_BLTU = 4'd5;
    localparam logic [3:0] BR_BGEU = 4'd6;

    localparam logic [1:0] JMP_NONE = 2'd0;
    localparam logic [1:0] JMP_JAL  = 2'd1;
    localparam logic [1:0] JMP_JALR = 2'd2;

    logic [31:0] regs [1:31];

    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;

    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;
    logic [31:0] imm;

    logic        dec_uses_rs1;
    logic        dec_uses_rs2;
    logic        dec_ecall;
    logic [31:0] dec_imm;
    logic [3:0]  dec_alu_op;
    logic [1:0]  dec_alu_a_sel;
    logic        dec_alu_b_sel;
    logic        dec_reg_write;
    logic        dec_mem_read;
    logic        dec_mem_write;
    logic [2:0]  dec_mem_size;
    logic [1:0]  dec_wb_sel;
    logic [3:0]  dec_branch;
    logic [1:0]  dec_jump;

    assign opcode = if_instr[6:0];
    assign funct3 = if_instr[14:12];
    assign funct7 = if_instr[31:25];
    assign rs1    = if_instr[19:15];
    assign rs2    = if_instr[24:20];
    assign rd     = if_instr[11:7];

    assign imm_i = {{20{if_instr[31]}}, if_instr[31:20]};
    assign imm_s = {{20{if_instr[31]}}, if_instr[31:25], if_instr[11:7]};
    assign imm_b = {{19{if_instr[31]}}, if_instr[31], if_instr[7], if_instr[30:25], if_instr[11:8], 1'b0};
    assign imm_u = {if_instr[31:12], 12'b0};
    assign imm_j = {{11{if_instr[31]}}, if_instr[31], if_instr[19:12], if_instr[20], if_instr[30:21], 1'b0};

    always_comb begin
        dec_uses_rs1   = 1'b0;
        dec_uses_rs2   = 1'b0;
        dec_ecall      = 1'b0;
        dec_imm        = 32'b0;
        dec_alu_op     = ALU_ADD;
        dec_alu_a_sel  = A_RS1;
        dec_alu_b_sel  = 1'b0;
        dec_reg_write  = 1'b0;
        dec_mem_read   = 1'b0;
        dec_mem_write  = 1'b0;
        dec_mem_size   = funct3;
        dec_wb_sel     = WB_ALU;
        dec_branch     = BR_NONE;
        dec_jump       = JMP_NONE;

        case (opcode)
            7'b0110011: begin
                dec_uses_rs1  = 1'b1;
                dec_uses_rs2  = 1'b1;
                dec_reg_write = 1'b1;
                dec_alu_a_sel = A_RS1;
                dec_alu_b_sel = 1'b0;
                dec_wb_sel    = WB_ALU;
                case (funct3)
                    3'b000: dec_alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                    3'b001: dec_alu_op = ALU_SLL;
                    3'b010: dec_alu_op = ALU_SLT;
                    3'b011: dec_alu_op = ALU_SLTU;
                    3'b100: dec_alu_op = ALU_XOR;
                    3'b101: dec_alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: dec_alu_op = ALU_OR;
                    3'b111: dec_alu_op = ALU_AND;
                    default: dec_alu_op = ALU_ADD;
                endcase
            end
            7'b0010011: begin
                dec_uses_rs1  = 1'b1;
                dec_reg_write = 1'b1;
                dec_imm       = imm_i;
                dec_alu_a_sel = A_RS1;
                dec_alu_b_sel = 1'b1;
                dec_wb_sel    = WB_ALU;
                case (funct3)
                    3'b000: dec_alu_op = ALU_ADD;
                    3'b001: dec_alu_op = ALU_SLL;
                    3'b010: dec_alu_op = ALU_SLT;
                    3'b011: dec_alu_op = ALU_SLTU;
                    3'b100: dec_alu_op = ALU_XOR;
                    3'b101: dec_alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: dec_alu_op = ALU_OR;
                    3'b111: dec_alu_op = ALU_AND;
                    default: dec_alu_op = ALU_ADD;
                endcase
            end
            7'b0000011: begin
                dec_uses_rs1  = 1'b1;
                dec_reg_write = 1'b1;
                dec_mem_read  = 1'b1;
                dec_imm       = imm_i;
                dec_alu_op    = ALU_ADD;
                dec_alu_a_sel = A_RS1;
                dec_alu_b_sel = 1'b1;
                dec_wb_sel    = WB_LOAD;
                dec_mem_size  = funct3;
            end
            7'b0100011: begin
                dec_uses_rs1  = 1'b1;
                dec_uses_rs2  = 1'b1;
                dec_mem_write = 1'b1;
                dec_imm       = imm_s;
                dec_alu_op    = ALU_ADD;
                dec_alu_a_sel = A_RS1;
                dec_alu_b_sel = 1'b1;
                dec_mem_size  = funct3;
            end
            7'b1100011: begin
                dec_uses_rs1  = 1'b1;
                dec_uses_rs2  = 1'b1;
                dec_imm       = imm_b;
                dec_alu_op    = ALU_ADD;
                dec_alu_a_sel = A_PC;
                dec_alu_b_sel = 1'b1;
                case (funct3)
                    3'b000: dec_branch = BR_BEQ;
                    3'b001: dec_branch = BR_BNE;
                    3'b100: dec_branch = BR_BLT;
                    3'b101: dec_branch = BR_BGE;
                    3'b110: dec_branch = BR_BLTU;
                    3'b111: dec_branch = BR_BGEU;
                    default: dec_branch = BR_NONE;
                endcase
            end
            7'b1101111: begin
                dec_reg_write = 1'b1;
                dec_imm       = imm_j;
                dec_alu_op    = ALU_ADD;
                dec_alu_a_sel = A_PC;
                dec_alu_b_sel = 1'b1;
                dec_wb_sel    = WB_PC4;
                dec_jump      = JMP_JAL;
            end
            7'b1100111: begin
                dec_uses_rs1  = 1'b1;
                dec_reg_write = 1'b1;
                dec_imm       = imm_i;
                dec_alu_op    = ALU_ADD;
                dec_alu_a_sel = A_RS1;
                dec_alu_b_sel = 1'b1;
                dec_wb_sel    = WB_PC4;
                dec_jump      = JMP_JALR;
            end
            7'b0110111: begin
                dec_reg_write = 1'b1;
                dec_imm       = imm_u;
                dec_alu_op    = ALU_ADD;
                dec_alu_a_sel = A_ZERO;
                dec_alu_b_sel = 1'b1;
                dec_wb_sel    = WB_ALU;
            end
            7'b0010111: begin
                dec_reg_write = 1'b1;
                dec_imm       = imm_u;
                dec_alu_op    = ALU_ADD;
                dec_alu_a_sel = A_PC;
                dec_alu_b_sel = 1'b1;
                dec_wb_sel    = WB_ALU;
            end
            7'b1110011: begin
                if (if_instr == 32'h0000_0073) begin
                    dec_ecall = 1'b1;
                end
            end
            default: begin
            end
        endcase
    end

    assign id_valid     = if_valid;
    assign id_rs1       = rs1;
    assign id_rs2       = rs2;
    assign id_uses_rs1  = if_valid & dec_uses_rs1;
    assign id_uses_rs2  = if_valid & dec_uses_rs2;
    assign id_ecall     = if_valid & dec_ecall;

    always_comb begin
        rs1_data = 32'b0;
        if (rs1 != 5'd0) begin
            if (wb_we && (wb_rd == rs1) && (wb_rd != 5'd0))
                rs1_data = wb_data;
            else
                rs1_data = regs[rs1];
        end
    end

    always_comb begin
        rs2_data = 32'b0;
        if (rs2 != 5'd0) begin
            if (wb_we && (wb_rd == rs2) && (wb_rd != 5'd0))
                rs2_data = wb_data;
            else
                rs2_data = regs[rs2];
        end
    end

    always_comb begin
        dbg_reg_data = 32'b0;
        if (dbg_reg_addr != 5'd0)
            dbg_reg_data = regs[dbg_reg_addr];
    end

    assign x10_data = regs[10];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 1; i < 32; i++) begin
                regs[i] <= 32'b0;
            end
        end else if (wb_we && (wb_rd != 5'd0)) begin
            regs[wb_rd] <= wb_data;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            id_ex_valid      <= 1'b0;
            id_ex_pc         <= 32'b0;
            id_ex_pc4        <= 32'b0;
            id_ex_instr      <= 32'b0;
            id_ex_rs1_data   <= 32'b0;
            id_ex_rs2_data   <= 32'b0;
            id_ex_rs1        <= 5'b0;
            id_ex_rs2        <= 5'b0;
            id_ex_rd         <= 5'b0;
            id_ex_imm        <= 32'b0;
            id_ex_alu_op     <= ALU_ADD;
            id_ex_alu_a_sel  <= A_RS1;
            id_ex_alu_b_sel  <= 1'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_mem_size   <= 3'b0;
            id_ex_wb_sel     <= WB_ALU;
            id_ex_branch     <= BR_NONE;
            id_ex_jump       <= JMP_NONE;
            id_ex_is_ecall   <= 1'b0;
        end else if (flush) begin
            id_ex_valid      <= 1'b0;
            id_ex_pc         <= 32'b0;
            id_ex_pc4        <= 32'b0;
            id_ex_instr      <= 32'b0;
            id_ex_rs1_data   <= 32'b0;
            id_ex_rs2_data   <= 32'b0;
            id_ex_rs1        <= 5'b0;
            id_ex_rs2        <= 5'b0;
            id_ex_rd         <= 5'b0;
            id_ex_imm        <= 32'b0;
            id_ex_alu_op     <= ALU_ADD;
            id_ex_alu_a_sel  <= A_RS1;
            id_ex_alu_b_sel  <= 1'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_mem_size   <= 3'b0;
            id_ex_wb_sel     <= WB_ALU;
            id_ex_branch     <= BR_NONE;
            id_ex_jump       <= JMP_NONE;
            id_ex_is_ecall   <= 1'b0;
        end else begin
            id_ex_valid      <= if_valid;
            id_ex_pc         <= if_pc;
            id_ex_pc4        <= if_pc4;
            id_ex_instr      <= if_instr;
            id_ex_rs1_data   <= rs1_data;
            id_ex_rs2_data   <= rs2_data;
            id_ex_rs1        <= rs1;
            id_ex_rs2        <= rs2;
            id_ex_rd         <= rd;
            id_ex_imm        <= dec_imm;
            id_ex_alu_op     <= dec_alu_op;
            id_ex_alu_a_sel  <= dec_alu_a_sel;
            id_ex_alu_b_sel  <= dec_alu_b_sel;
            id_ex_reg_write  <= dec_reg_write;
            id_ex_mem_read   <= dec_mem_read;
            id_ex_mem_write  <= dec_mem_write;
            id_ex_mem_size   <= dec_mem_size;
            id_ex_wb_sel     <= dec_wb_sel;
            id_ex_branch     <= dec_branch;
            id_ex_jump       <= dec_jump;
            id_ex_is_ecall   <= dec_ecall;
        end
    end

endmodule
