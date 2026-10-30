// rtl/alu_unit.sv
module alu_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        alu_issue_valid,
    input  logic [5:0]  alu_issue_prs1,
    input  logic [5:0]  alu_issue_prs2,
    input  logic [5:0]  alu_issue_prd,
    input  logic [2:0]  alu_issue_rob_idx,
    input  logic [31:0] alu_issue_imm,
    input  logic [3:0]  alu_issue_op_type,
    input  logic [2:0]  alu_issue_func3,
    input  logic [6:0]  alu_issue_func7,
    input  logic [31:0] alu_issue_pc,
    output logic [5:0]  prf_read1_addr,
    input  logic [31:0] prf_read1_data,
    output logic [5:0]  prf_read2_addr,
    input  logic [31:0] prf_read2_data,
    output logic        prf_write_valid,
    output logic [5:0]  prf_write_pr,
    output logic [31:0] prf_write_data,
    output logic        rob_complete_valid,
    output logic [2:0]  rob_complete_rob_idx,
    output logic [5:0]  rob_complete_prd,
    output logic [31:0] rob_complete_data,
    output logic        rob_mispredict_valid,
    output logic [31:0] rob_mispredict_pc,
    output logic        bp_resolve_valid,
    output logic [31:0] bp_resolve_pc,
    output logic        bp_resolve_taken,
    output logic [31:0] bp_resolve_target,
    output logic        bp_resolve_is_cond,
    input  logic        squash_va
);

    // Op type encoding (must match decode/rename/issue)
    localparam [3:0] OP_ALU    = 4'b0000;
    localparam [3:0] OP_LUI    = 4'b0001;
    localparam [3:0] OP_AUIPC  = 4'b0010;
    localparam [3:0] OP_JAL    = 4'b0011;
    localparam [3:0] OP_JALR   = 4'b0100;
    localparam [3:0] OP_BRANCH = 4'b0101;
    localparam [3:0] OP_LOAD   = 4'b0110;
    localparam [3:0] OP_STORE  = 4'b0111;
    localparam [3:0] OP_ECALL  = 4'b1000;

    // Pipeline stage registers
    logic        valid_r;
    logic [5:0]  prs1_r;
    logic [5:0]  prs2_r;
    logic [5:0]  prd_r;
    logic [2:0]  rob_idx_r;
    logic [31:0] imm_r;
    logic [3:0]  op_type_r;
    logic [2:0]  func3_r;
    logic [6:0]  func7_r;
    logic [31:0] pc_r;
    logic [31:0] op1_r;
    logic [31:0] op2_r;

    // Combinational ALU result
    logic [31:0] alu_result;
    logic [31:0] branch_target;
    logic        branch_taken;
    logic        is_cond_branch;
    logic        is_control;

    // Read addresses
    assign prf_read1_addr = alu_issue_prs1;
    assign prf_read2_addr = alu_issue_prs2;

    // ALU operation
    always_comb begin
        alu_result = 32'b0;
        branch_taken = 1'b0;
        branch_target = 32'b0;
        is_cond_branch = 1'b0;
        is_control = 1'b0;

        case (op_type_r)
            OP_ALU: begin
                case (func3_r)
                    3'b000: begin
                        if (func7_r[5] && func7_r[0]) // SUB
                            alu_result = op1_r - op2_r;
                        else // ADD
                            alu_result = op1_r + op2_r;
                    end
                    3'b001: alu_result = op1_r << op2_r[4:0]; // SLL
                    3'b010: alu_result = ($signed(op1_r) < $signed(op2_r)) ? 32'b1 : 32'b0; // SLT
                    3'b011: alu_result = (op1_r < op2_r) ? 32'b1 : 32'b0; // SLTU
                    3'b100: alu_result = op1_r ^ op2_r; // XOR
                    3'b101: begin
                        if (func7_r[5]) // SRA/SRAI
                            alu_result = $signed(op1_r) >>> op2_r[4:0];
                        else // SRL/SRLI
                            alu_result = op1_r >> op2_r[4:0];
                    end
                    3'b110: alu_result = op1_r | op2_r; // OR
                    3'b111: alu_result = op1_r & op2_r; // AND
                    default: alu_result = 32'b0;
                endcase
            end
            OP_LUI: alu_result = imm_r;
            OP_AUIPC: alu_result = pc_r + imm_r;
            OP_JAL: begin
                alu_result = pc_r + 32'h4;
                branch_target = pc_r + imm_r;
                branch_taken = 1'b1;
                is_control = 1'b1;
            end
            OP_JALR: begin
                alu_result = pc_r + 32'h4;
                branch_target = (op1_r + imm_r) & 32'hFFFF_FFFE;
                branch_taken = 1'b1;
                is_control = 1'b1;
            end
            OP_BRANCH: begin
                is_cond_branch = 1'b1;
                is_control = 1'b1;
                branch_target = pc_r + imm_r;
                case (func3_r)
                    3'b000: branch_taken = (op1_r == op2_r); // BEQ
                    3'b001: branch_taken = (op1_r != op2_r); // BNE
                    3'b100: branch_taken = ($signed(op1_r) < $signed(op2_r)); // BLT
                    3'b101: branch_taken = ($signed(op1_r) >= $signed(op2_r)); // BGE
                    3'b110: branch_taken = (op1_r < op2_r); // BLTU
                    3'b111: branch_taken = (op1_r >= op2_r); // BGEU
                    default: branch_taken = 1'b0;
                endcase
            end
            default: alu_result = 32'b0;
        endcase
    end

    // Pipeline register update
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_r <= 1'b0;
            prs1_r <= 6'b0;
            prs2_r <= 6'b0;
            prd_r <= 6'b0;
            rob_idx_r <= 3'b0;
            imm_r <= 32'b0;
            op_type_r <= 4'b0;
            func3_r <= 3'b0;
            func7_r <= 7'b0;
            pc_r <= 32'b0;
            op1_r <= 32'b0;
            op2_r <= 32'b0;
        end else if (squash_va) begin
            valid_r <= 1'b0;
        end else if (alu_issue_valid) begin
            valid_r <= 1'b1;
            prs1_r <= alu_issue_prs1;
            prs2_r <= alu_issue_prs2;
            prd_r <= alu_issue_prd;
            rob_idx_r <= alu_issue_rob_idx;
            imm_r <= alu_issue_imm;
            op_type_r <= alu_issue_op_type;
            func3_r <= alu_issue_func3;
            func7_r <= alu_issue_func7;
            pc_r <= alu_issue_pc;
            op1_r <= prf_read1_data;
            op2_r <= prf_read2_data;
        end else begin
            valid_r <= 1'b0;
        end
    end

    // Outputs
    always_comb begin
        prf_write_valid = 1'b0;
        prf_write_pr = 6'b0;
        prf_write_data = 32'b0;
        rob_complete_valid = 1'b0;
        rob_complete_rob_idx = 3'b0;
        rob_complete_prd = 6'b0;
        rob_complete_data = 32'b0;
        rob_mispredict_valid = 1'b0;
        rob_mispredict_pc = 32'b0;
        bp_resolve_valid = 1'b0;
        bp_resolve_pc = 32'b0;
        bp_resolve_taken = 1'b0;
        bp_resolve_target = 32'b0;
        bp_resolve_is_cond = 1'b0;

        if (valid_r && !squash_va) begin
            // Writeback for non-control, non-ECALL instructions with rd != 0
            if (op_type_r != OP_BRANCH && op_type_r != OP_ECALL && prd_r != 6'b0) begin
                prf_write_valid = 1'b1;
                prf_write_pr = prd_r;
                prf_write_data = alu_result;
            end

            // ROB completion
            rob_complete_valid = 1'b1;
            rob_complete_rob_idx = rob_idx_r;
            rob_complete_prd = prd_r;
            rob_complete_data = alu_result;

            // Branch resolution
            if (is_control) begin
                bp_resolve_valid = 1'b1;
                bp_resolve_pc = pc_r;
                bp_resolve_taken = branch_taken;
                bp_resolve_target = branch_target;
                bp_resolve_is_cond = is_cond_branch;
                rob_mispredict_valid = 1'b1;
                rob_mispredict_pc = branch_target;
            end
        end
    end

endmodule
