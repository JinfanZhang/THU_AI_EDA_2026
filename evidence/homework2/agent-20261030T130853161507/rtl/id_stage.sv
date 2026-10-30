// Instruction decode stage
module id_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        if_id_valid,
    input  logic [31:0] if_id_pc,
    input  logic [31:0] if_id_insn,
    input  logic [1:0]  if_id_epoch,
    input  logic [31:0] read_data1,
    input  logic [31:0] read_data2,
    input  logic        stall,
    input  logic        flush_id_ex,
    input  logic        redirect_valid,
    output logic [4:0]  read_addr1,
    output logic [4:0]  read_addr2,
    output logic        ecall_halt_pending,
    output logic        id_ex_valid,
    output logic [31:0] id_ex_pc,
    output logic [31:0] id_ex_insn,
    output logic [31:0] id_ex_rs1_val,
    output logic [31:0] id_ex_rs2_val,
    output logic [4:0]  id_ex_rs1_addr,
    output logic [4:0]  id_ex_rs2_addr,
    output logic [31:0] id_ex_imm,
    output logic [4:0]  id_ex_rd_addr,
    output logic [3:0]  id_ex_alu_op,
    output logic        id_ex_mem_read,
    output logic        id_ex_mem_write,
    output logic        id_ex_reg_write,
    output logic        id_ex_branch,
    output logic        id_ex_jal,
    output logic        id_ex_jalr,
    output logic        id_ex_ecall,
    output logic [1:0]  id_ex_epoch,
    output logic [31:0] id_ex_pc_plus4,
    output logic [1:0]  id_ex_funct3,
    output logic        id_ex_opcode
);

    // Instruction fields
    logic [6:0]  opcode;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [6:0]  funct7;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [31:0] imm;

    assign opcode = if_id_insn[6:0];
    assign rd     = if_id_insn[11:7];
    assign funct3 = if_id_insn[14:12];
    assign rs1    = if_id_insn[19:15];
    assign rs2    = if_id_insn[24:20];
    assign funct7 = if_id_insn[31:25];

    // Immediate generation
    assign imm_i = {{20{if_id_insn[31]}}, if_id_insn[31:20]};
    assign imm_s = {{20{if_id_insn[31]}}, if_id_insn[31:25], if_id_insn[11:7]};
    assign imm_b = {{19{if_id_insn[31]}}, if_id_insn[31], if_id_insn[7], if_id_insn[30:25], if_id_insn[11:8], 1'b0};
    assign imm_u = {if_id_insn[31:12], 12'b0};
    assign imm_j = {{11{if_id_insn[31]}}, if_id_insn[31], if_id_insn[19:12], if_id_insn[20], if_id_insn[30:21], 1'b0};

    always_comb begin
        case (opcode)
            7'b0110111: imm = imm_u;  // LUI
            7'b0010111: imm = imm_u;  // AUIPC
            7'b1101111: imm = imm_j;  // JAL
            7'b1100111: imm = imm_i;  // JALR
            7'b1100011: imm = imm_b;  // Branch
            7'b0100011: imm = imm_s;  // Store
            7'b0000011: imm = imm_i;  // Load
            7'b0010011: imm = imm_i;  // I-type ALU
            default:    imm = imm_i;
        endcase
    end

    // Control signal generation
    logic is_alu_r, is_alu_i, is_load, is_store, is_branch, is_jal, is_jalr, is_lui, is_auipc, is_ecall;
    logic [3:0] alu_op;

    assign is_alu_r  = (opcode == 7'b0110011);
    assign is_alu_i  = (opcode == 7'b0010011);
    assign is_load   = (opcode == 7'b0000011);
    assign is_store  = (opcode == 7'b0100011);
    assign is_branch = (opcode == 7'b1100011);
    assign is_jal    = (opcode == 7'b1101111);
    assign is_jalr   = (opcode == 7'b1100111);
    assign is_lui    = (opcode == 7'b0110111);
    assign is_auipc  = (opcode == 7'b0010111);
    assign is_ecall  = (if_id_insn == 32'h0000_0073);

    // ALU operation encoding
    always_comb begin
        alu_op = 4'b0000;
        if (is_alu_r) begin
            case ({funct7, funct3})
                10'b0000000_000: alu_op = 4'b0000; // ADD
                10'b0100000_000: alu_op = 4'b0001; // SUB
                10'b0000000_001: alu_op = 4'b0010; // SLL
                10'b0000000_010: alu_op = 4'b0011; // SLT
                10'b0000000_011: alu_op = 4'b0100; // SLTU
                10'b0000000_100: alu_op = 4'b0101; // XOR
                10'b0000000_101: alu_op = 4'b0110; // SRL
                10'b0100000_101: alu_op = 4'b0111; // SRA
                10'b0000000_110: alu_op = 4'b1000; // OR
                10'b0000000_111: alu_op = 4'b1001; // AND
                default:         alu_op = 4'b0000;
            endcase
        end else if (is_alu_i) begin
            case (funct3)
                3'b000: alu_op = 4'b0000; // ADDI
                3'b010: alu_op = 4'b0011; // SLTI
                3'b011: alu_op = 4'b0100; // SLTIU
                3'b100: alu_op = 4'b0101; // XORI
                3'b110: alu_op = 4'b1000; // ORI
                3'b111: alu_op = 4'b1001; // ANDI
                3'b001: alu_op = 4'b0010; // SLLI
                3'b101: begin
                    if (funct7 == 7'b0100000) alu_op = 4'b0111; // SRAI
                    else                      alu_op = 4'b0110; // SRLI
                end
                default: alu_op = 4'b0000;
            endcase
        end else if (is_lui) begin
            alu_op = 4'b1010; // LUI
        end else if (is_auipc) begin
            alu_op = 4'b1011; // AUIPC
        end else if (is_load || is_store) begin
            alu_op = 4'b0000; // ADD for address
        end else if (is_branch || is_jal || is_jalr) begin
            alu_op = 4'b0000; // ADD for target
        end else begin
            alu_op = 4'b0000;
        end
    end

    // Register file read addresses
    assign read_addr1 = rs1;
    assign read_addr2 = rs2;

    // ECALL halt pending detection
    logic ecall_in_id;
    assign ecall_in_id = if_id_valid && is_ecall;

    // Halt pending register
    logic halt_pending_r;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halt_pending_r <= 1'b0;
        end else if (redirect_valid) begin
            halt_pending_r <= 1'b0;
        end else if (ecall_in_id && !halt_pending_r) begin
            halt_pending_r <= 1'b1;
        end
    end
    assign ecall_halt_pending = halt_pending_r;

    // ID/EX pipeline register
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            id_ex_valid      <= 1'b0;
            id_ex_pc         <= 32'b0;
            id_ex_insn       <= 32'b0;
            id_ex_rs1_val    <= 32'b0;
            id_ex_rs2_val    <= 32'b0;
            id_ex_rs1_addr   <= 5'b0;
            id_ex_rs2_addr   <= 5'b0;
            id_ex_imm        <= 32'b0;
            id_ex_rd_addr    <= 5'b0;
            id_ex_alu_op     <= 4'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jal        <= 1'b0;
            id_ex_jalr       <= 1'b0;
            id_ex_ecall      <= 1'b0;
            id_ex_epoch      <= 2'b0;
            id_ex_pc_plus4   <= 32'b0;
            id_ex_funct3     <= 2'b0;
            id_ex_opcode     <= 1'b0;
        end else if (flush_id_ex || redirect_valid) begin
            id_ex_valid      <= 1'b0;
            id_ex_pc         <= 32'b0;
            id_ex_insn       <= 32'b0;
            id_ex_rs1_val    <= 32'b0;
            id_ex_rs2_val    <= 32'b0;
            id_ex_rs1_addr   <= 5'b0;
            id_ex_rs2_addr   <= 5'b0;
            id_ex_imm        <= 32'b0;
            id_ex_rd_addr    <= 5'b0;
            id_ex_alu_op     <= 4'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jal        <= 1'b0;
            id_ex_jalr       <= 1'b0;
            id_ex_ecall      <= 1'b0;
            id_ex_epoch      <= 2'b0;
            id_ex_pc_plus4   <= 32'b0;
            id_ex_funct3     <= 2'b0;
            id_ex_opcode     <= 1'b0;
        end else if (!stall) begin
            id_ex_valid      <= if_id_valid;
            id_ex_pc         <= if_id_pc;
            id_ex_insn       <= if_id_insn;
            id_ex_rs1_val    <= read_data1;
            id_ex_rs2_val    <= read_data2;
            id_ex_rs1_addr   <= rs1;
            id_ex_rs2_addr   <= rs2;
            id_ex_imm        <= imm;
            id_ex_rd_addr    <= rd;
            id_ex_alu_op     <= alu_op;
            id_ex_mem_read   <= is_load;
            id_ex_mem_write  <= is_store;
            id_ex_reg_write  <= (is_alu_r || is_alu_i || is_load || is_lui || is_auipc || is_jal || is_jalr) && (rd != 5'b0);
            id_ex_branch     <= is_branch;
            id_ex_jal        <= is_jal;
            id_ex_jalr       <= is_jalr;
            id_ex_ecall      <= is_ecall;
            id_ex_epoch      <= if_id_epoch;
            id_ex_pc_plus4   <= if_id_pc + 32'd4;
            id_ex_funct3     <= funct3[1:0];
            id_ex_opcode     <= opcode[0];
        end
    end

endmodule
