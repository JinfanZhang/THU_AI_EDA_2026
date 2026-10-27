module id_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ifid_valid,
    input  logic [31:0] ifid_pc,
    input  logic [31:0] ifid_pc_plus4,
    input  logic [31:0] ifid_instr,
    output logic [4:0]  id_rs1_addr,
    output logic [4:0]  id_rs2_addr,
    output logic        id_uses_rs1,
    output logic        id_uses_rs2,
    input  logic [31:0] id_rs1_data,
    input  logic [31:0] id_rs2_data,
    output logic        id_is_ecall,
    input  logic        idex_flush,
    output logic        idex_valid,
    output logic [31:0] idex_pc,
    output logic [31:0] idex_pc_plus4,
    output logic [31:0] idex_rs1_data,
    output logic [31:0] idex_rs2_data,
    output logic [4:0]  idex_rs1_addr,
    output logic [4:0]  idex_rs2_addr,
    output logic [31:0] idex_imm,
    output logic [4:0]  idex_rd_addr,
    output logic [3:0]  idex_alu_op,
    output logic [1:0]  idex_alu_a_sel,
    output logic        idex_alu_b_sel,
    output logic        idex_reg_write,
    output logic        idex_mem_read,
    output logic        idex_mem_write,
    output logic [1:0]  idex_mem_size,
    output logic        idex_mem_unsign,
    output logic [1:0]  idex_wb_sel,
    output logic        idex_branch,
    output logic [2:0]  idex_branch_op,
    output logic        idex_jump,
    output logic        idex_jalr,
    output logic        idex_is_ecall
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

    localparam logic [1:0] A_SEL_RS1 = 2'd0;
    localparam logic [1:0] A_SEL_PC  = 2'd1;
    localparam logic [1:0] A_SEL_ZERO= 2'd2;

    localparam logic [1:0] WB_ALU  = 2'd0;
    localparam logic [1:0] WB_LOAD = 2'd1;
    localparam logic [1:0] WB_PC4  = 2'd2;

    localparam logic [1:0] MS_BYTE = 2'd0;
    localparam logic [1:0] MS_HALF = 2'd1;
    localparam logic [1:0] MS_WORD = 2'd2;

    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [4:0]  rd_addr;

    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;
    logic [31:0] imm_sel;

    logic        uses_rs1;
    logic        uses_rs2;
    logic        is_ecall;

    logic [3:0]  alu_op;
    logic [1:0]  alu_a_sel;
    logic        alu_b_sel;
    logic        reg_write;
    logic        mem_read;
    logic        mem_write;
    logic [1:0]  mem_size;
    logic        mem_unsign;
    logic [1:0]  wb_sel;
    logic        branch;
    logic [2:0]  branch_op;
    logic        jump;
    logic        jalr;

    assign opcode   = ifid_instr[6:0];
    assign funct3   = ifid_instr[14:12];
    assign funct7   = ifid_instr[31:25];
    assign rs1_addr = ifid_instr[19:15];
    assign rs2_addr = ifid_instr[24:20];
    assign rd_addr  = ifid_instr[11:7];

    assign imm_i = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
    assign imm_s = {{20{ifid_instr[31]}}, ifid_instr[31:25], ifid_instr[11:7]};
    assign imm_b = {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7],
                    ifid_instr[30:25], ifid_instr[11:8], 1'b0};
    assign imm_u = {ifid_instr[31:12], 12'b0};
    assign imm_j = {{11{ifid_instr[31]}}, ifid_instr[31], ifid_instr[19:12],
                    ifid_instr[20], ifid_instr[30:21], 1'b0};

    assign id_rs1_addr = rs1_addr;
    assign id_rs2_addr = rs2_addr;

    assign is_ecall = ifid_valid && (ifid_instr == 32'h0000_0073);
    assign id_is_ecall = is_ecall;

    always_comb begin
        uses_rs1   = 1'b0;
        uses_rs2   = 1'b0;
        imm_sel    = 32'd0;
        alu_op     = ALU_ADD;
        alu_a_sel  = A_SEL_RS1;
        alu_b_sel  = 1'b0;
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_size   = MS_WORD;
        mem_unsign = 1'b0;
        wb_sel     = WB_ALU;
        branch     = 1'b0;
        branch_op  = 3'd0;
        jump       = 1'b0;
        jalr       = 1'b0;

        if (ifid_valid) begin
            case (opcode)
                7'b0110011: begin
                    uses_rs1  = 1'b1;
                    uses_rs2  = 1'b1;
                    reg_write = 1'b1;
                    wb_sel    = WB_ALU;
                    alu_a_sel = A_SEL_RS1;
                    alu_b_sel = 1'b0;
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
                7'b0010011: begin
                    uses_rs1  = 1'b1;
                    reg_write = 1'b1;
                    wb_sel    = WB_ALU;
                    alu_a_sel = A_SEL_RS1;
                    alu_b_sel = 1'b1;
                    imm_sel   = imm_i;
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
                7'b0000011: begin
                    uses_rs1  = 1'b1;
                    reg_write = 1'b1;
                    mem_read  = 1'b1;
                    wb_sel    = WB_LOAD;
                    alu_op    = ALU_ADD;
                    alu_a_sel = A_SEL_RS1;
                    alu_b_sel = 1'b1;
                    imm_sel   = imm_i;
                    case (funct3)
                        3'b000: begin mem_size = MS_BYTE; mem_unsign = 1'b0; end
                        3'b001: begin mem_size = MS_HALF; mem_unsign = 1'b0; end
                        3'b010: begin mem_size = MS_WORD; mem_unsign = 1'b0; end
                        3'b100: begin mem_size = MS_BYTE; mem_unsign = 1'b1; end
                        3'b101: begin mem_size = MS_HALF; mem_unsign = 1'b1; end
                        default: begin mem_size = MS_WORD; mem_unsign = 1'b0; end
                    endcase
                end
                7'b0100011: begin
                    uses_rs1  = 1'b1;
                    uses_rs2  = 1'b1;
                    mem_write = 1'b1;
                    alu_op    = ALU_ADD;
                    alu_a_sel = A_SEL_RS1;
                    alu_b_sel = 1'b1;
                    imm_sel   = imm_s;
                    case (funct3)
                        3'b000: mem_size = MS_BYTE;
                        3'b001: mem_size = MS_HALF;
                        3'b010: mem_size = MS_WORD;
                        default: mem_size = MS_WORD;
                    endcase
                end
                7'b1100011: begin
                    uses_rs1  = 1'b1;
                    uses_rs2  = 1'b1;
                    branch    = 1'b1;
                    alu_op    = ALU_ADD;
                    alu_a_sel = A_SEL_PC;
                    alu_b_sel = 1'b1;
                    imm_sel   = imm_b;
                    case (funct3)
                        3'b000: branch_op = 3'd0;
                        3'b001: branch_op = 3'd1;
                        3'b100: branch_op = 3'd2;
                        3'b101: branch_op = 3'd3;
                        3'b110: branch_op = 3'd4;
                        3'b111: branch_op = 3'd5;
                        default: branch_op = 3'd0;
                    endcase
                end
                7'b1101111: begin
                    reg_write = 1'b1;
                    jump      = 1'b1;
                    wb_sel    = WB_PC4;
                    alu_op    = ALU_ADD;
                    alu_a_sel = A_SEL_PC;
                    alu_b_sel = 1'b1;
                    imm_sel   = imm_j;
                end
                7'b1100111: begin
                    uses_rs1  = 1'b1;
                    reg_write = 1'b1;
                    jump      = 1'b1;
                    jalr      = 1'b1;
                    wb_sel    = WB_PC4;
                    alu_op    = ALU_ADD;
                    alu_a_sel = A_SEL_RS1;
                    alu_b_sel = 1'b1;
                    imm_sel   = imm_i;
                end
                7'b0110111: begin
                    reg_write = 1'b1;
                    wb_sel    = WB_ALU;
                    alu_op    = ALU_ADD;
                    alu_a_sel = A_SEL_ZERO;
                    alu_b_sel = 1'b1;
                    imm_sel   = imm_u;
                end
                7'b0010111: begin
                    reg_write = 1'b1;
                    wb_sel    = WB_ALU;
                    alu_op    = ALU_ADD;
                    alu_a_sel = A_SEL_PC;
                    alu_b_sel = 1'b1;
                    imm_sel   = imm_u;
                end
                7'b1110011: begin
                    if (ifid_instr == 32'h0000_0073) begin
                        reg_write = 1'b0;
                    end
                end
                default: begin
                    reg_write = 1'b0;
                end
            endcase
        end
    end

    assign id_uses_rs1 = ifid_valid && uses_rs1;
    assign id_uses_rs2 = ifid_valid && uses_rs2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            idex_valid       <= 1'b0;
            idex_pc          <= 32'd0;
            idex_pc_plus4    <= 32'd0;
            idex_rs1_data    <= 32'd0;
            idex_rs2_data    <= 32'd0;
            idex_rs1_addr    <= 5'd0;
            idex_rs2_addr    <= 5'd0;
            idex_imm         <= 32'd0;
            idex_rd_addr     <= 5'd0;
            idex_alu_op      <= ALU_ADD;
            idex_alu_a_sel   <= A_SEL_RS1;
            idex_alu_b_sel   <= 1'b0;
            idex_reg_write   <= 1'b0;
            idex_mem_read    <= 1'b0;
            idex_mem_write   <= 1'b0;
            idex_mem_size    <= MS_WORD;
            idex_mem_unsign  <= 1'b0;
            idex_wb_sel      <= WB_ALU;
            idex_branch      <= 1'b0;
            idex_branch_op   <= 3'd0;
            idex_jump        <= 1'b0;
            idex_jalr        <= 1'b0;
            idex_is_ecall    <= 1'b0;
        end else if (idex_flush) begin
            idex_valid       <= 1'b0;
            idex_pc          <= 32'd0;
            idex_pc_plus4    <= 32'd0;
            idex_rs1_data    <= 32'd0;
            idex_rs2_data    <= 32'd0;
            idex_rs1_addr    <= 5'd0;
            idex_rs2_addr    <= 5'd0;
            idex_imm         <= 32'd0;
            idex_rd_addr     <= 5'd0;
            idex_alu_op      <= ALU_ADD;
            idex_alu_a_sel   <= A_SEL_RS1;
            idex_alu_b_sel   <= 1'b0;
            idex_reg_write   <= 1'b0;
            idex_mem_read    <= 1'b0;
            idex_mem_write   <= 1'b0;
            idex_mem_size    <= MS_WORD;
            idex_mem_unsign  <= 1'b0;
            idex_wb_sel      <= WB_ALU;
            idex_branch      <= 1'b0;
            idex_branch_op   <= 3'd0;
            idex_jump        <= 1'b0;
            idex_jalr        <= 1'b0;
            idex_is_ecall    <= 1'b0;
        end else begin
            idex_valid       <= ifid_valid;
            idex_pc          <= ifid_pc;
            idex_pc_plus4    <= ifid_pc_plus4;
            idex_rs1_data    <= id_rs1_data;
            idex_rs2_data    <= id_rs2_data;
            idex_rs1_addr    <= rs1_addr;
            idex_rs2_addr    <= rs2_addr;
            idex_imm         <= imm_sel;
            idex_rd_addr     <= rd_addr;
            idex_alu_op      <= alu_op;
            idex_alu_a_sel   <= alu_a_sel;
            idex_alu_b_sel   <= alu_b_sel;
            idex_reg_write   <= reg_write;
            idex_mem_read    <= mem_read;
            idex_mem_write   <= mem_write;
            idex_mem_size    <= mem_size;
            idex_mem_unsign  <= mem_unsign;
            idex_wb_sel      <= wb_sel;
            idex_branch      <= branch;
            idex_branch_op   <= branch_op;
            idex_jump        <= jump;
            idex_jalr        <= jalr;
            idex_is_ecall    <= is_ecall;
        end
    end

endmodule
