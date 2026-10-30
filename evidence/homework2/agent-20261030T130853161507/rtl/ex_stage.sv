module ex_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        id_ex_valid,
    input  logic [31:0] id_ex_pc,
    input  logic [31:0] id_ex_insn,
    input  logic [31:0] id_ex_rs1_val,
    input  logic [31:0] id_ex_rs2_val,
    input  logic [4:0]  id_ex_rs1_addr,
    input  logic [4:0]  id_ex_rs2_addr,
    input  logic [31:0] id_ex_imm,
    input  logic [4:0]  id_ex_rd_addr,
    input  logic [3:0]  id_ex_alu_op,
    input  logic        id_ex_mem_read,
    input  logic        id_ex_mem_write,
    input  logic        id_ex_reg_write,
    input  logic        id_ex_branch,
    input  logic        id_ex_jal,
    input  logic        id_ex_jalr,
    input  logic        id_ex_ecall,
    input  logic [1:0]  id_ex_epoch,
    input  logic [31:0] id_ex_pc_plus4,
    input  logic [1:0]  id_ex_funct3,
    input  logic        id_ex_opcode,
    input  logic [1:0]  forward_a,
    input  logic [1:0]  forward_b,
    input  logic        ex_mem_fwd_valid,
    input  logic        ex_mem_fwd_reg_write,
    input  logic [4:0]  ex_mem_fwd_rd_addr,
    input  logic [31:0] ex_mem_fwd_alu_result,
    input  logic        mem_wb_valid,
    input  logic        mem_wb_reg_write,
    input  logic [4:0]  mem_wb_rd_addr,
    input  logic [31:0] mem_wb_wb_data,
    output logic        ex_mem_valid,
    output logic [31:0] ex_mem_pc,
    output logic [31:0] ex_mem_insn,
    output logic [31:0] ex_mem_pc_plus4,
    output logic [31:0] ex_mem_alu_result,
    output logic [31:0] ex_mem_rs2_val,
    output logic [4:0]  ex_mem_rd_addr,
    output logic        ex_mem_reg_write,
    output logic        ex_mem_mem_read,
    output logic        ex_mem_mem_write,
    output logic        ex_mem_ecall,
    output logic [1:0]  ex_mem_epoch,
    output logic        redirect_valid,
    output logic [31:0] redirect_pc,
    output logic        update_valid,
    output logic [31:0] update_pc,
    output logic        update_taken,
    output logic [31:0] update_target,
    output logic        update_is_branch,
    output logic        update_is_jal,
    output logic        update_is_jalr,
    output logic [1:0]  update_epoch,
    output logic        dbg_bp_resolve,
    output logic        dbg_bp_mispredict,
    output logic        flush_ifid,
    output logic        flush_idex
);

    // ALU op codes
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_SLL  = 4'b0010;
    localparam ALU_SLT  = 4'b0011;
    localparam ALU_SLTU = 4'b0100;
    localparam ALU_XOR  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_OR   = 4'b1000;
    localparam ALU_AND  = 4'b1001;
    localparam ALU_LUI  = 4'b1010;
    localparam ALU_AUIPC= 4'b1011;
    localparam ALU_PC4  = 4'b1100;
    localparam ALU_ADD_I= 4'b1101;

    logic [31:0] rs1_fwd;
    logic [31:0] rs2_fwd;
    logic [31:0] alu_result;
    logic [31:0] branch_target;
    logic [31:0] jalr_target;
    logic        branch_taken;
    logic        is_control;
    logic [31:0] actual_next_pc;
    logic [31:0] pred_next_pc;
    logic        control_valid;
    logic        mispredict_flush;

    // Forwarding mux for rs1
    always_comb begin
        rs1_fwd = id_ex_rs1_val;
        if (forward_a == 2'b10 && ex_mem_fwd_valid && ex_mem_fwd_reg_write && ex_mem_fwd_rd_addr != 5'b0 && ex_mem_fwd_rd_addr == id_ex_rs1_addr)
            rs1_fwd = ex_mem_fwd_alu_result;
        else if (forward_a == 2'b01 && mem_wb_valid && mem_wb_reg_write && mem_wb_rd_addr != 5'b0 && mem_wb_rd_addr == id_ex_rs1_addr)
            rs1_fwd = mem_wb_wb_data;
    end

    // Forwarding mux for rs2
    always_comb begin
        rs2_fwd = id_ex_rs2_val;
        if (forward_b == 2'b10 && ex_mem_fwd_valid && ex_mem_fwd_reg_write && ex_mem_fwd_rd_addr != 5'b0 && ex_mem_fwd_rd_addr == id_ex_rs2_addr)
            rs2_fwd = ex_mem_fwd_alu_result;
        else if (forward_b == 2'b01 && mem_wb_valid && mem_wb_reg_write && mem_wb_rd_addr != 5'b0 && mem_wb_rd_addr == id_ex_rs2_addr)
            rs2_fwd = mem_wb_wb_data;
    end

    // ALU
    always_comb begin
        alu_result = 32'b0;
        case (id_ex_alu_op)
            ALU_ADD:   alu_result = rs1_fwd + rs2_fwd;
            ALU_SUB:   alu_result = rs1_fwd - rs2_fwd;
            ALU_SLL:   alu_result = rs1_fwd << rs2_fwd[4:0];
            ALU_SLT:   alu_result = ($signed(rs1_fwd) < $signed(rs2_fwd)) ? 32'b1 : 32'b0;
            ALU_SLTU:  alu_result = (rs1_fwd < rs2_fwd) ? 32'b1 : 32'b0;
            ALU_XOR:   alu_result = rs1_fwd ^ rs2_fwd;
            ALU_SRL:   alu_result = rs1_fwd >> rs2_fwd[4:0];
            ALU_SRA:   alu_result = $signed(rs1_fwd) >>> rs2_fwd[4:0];
            ALU_OR:    alu_result = rs1_fwd | rs2_fwd;
            ALU_AND:   alu_result = rs1_fwd & rs2_fwd;
            ALU_LUI:   alu_result = {id_ex_insn[31:12], 12'b0};
            ALU_AUIPC: alu_result = id_ex_pc + {id_ex_insn[31:12], 12'b0};
            ALU_PC4:   alu_result = id_ex_pc_plus4;
            ALU_ADD_I: alu_result = rs1_fwd + id_ex_imm;
            default:   alu_result = rs1_fwd + rs2_fwd;
        endcase
    end

    // Branch target
    assign branch_target = id_ex_pc + id_ex_imm;

    // JALR target: full 32-bit target with bit0 forced to 0.
    assign jalr_target = (rs1_fwd + id_ex_imm) & 32'hFFFF_FFFE;

    // Branch taken logic
    always_comb begin
        branch_taken = 1'b0;
        if (id_ex_branch) begin
            case (id_ex_funct3)
                3'b000: branch_taken = (rs1_fwd == rs2_fwd);                    // BEQ
                3'b001: branch_taken = (rs1_fwd != rs2_fwd);                    // BNE
                3'b100: branch_taken = ($signed(rs1_fwd) < $signed(rs2_fwd));   // BLT
                3'b101: branch_taken = ($signed(rs1_fwd) >= $signed(rs2_fwd));  // BGE
                3'b110: branch_taken = (rs1_fwd < rs2_fwd);                     // BLTU
                3'b111: branch_taken = (rs1_fwd >= rs2_fwd);                    // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

    // Control transfer detection
    assign is_control = id_ex_branch || id_ex_jal || id_ex_jalr;
    assign control_valid = id_ex_valid && is_control;

    // Actual next PC
    always_comb begin
        actual_next_pc = id_ex_pc_plus4;
        if (id_ex_jal)
            actual_next_pc = branch_target;
        else if (id_ex_jalr)
            actual_next_pc = jalr_target;
        else if (id_ex_branch && branch_taken)
            actual_next_pc = branch_target;
    end

    // Predicted next PC: the IF stage supplies the predicted PC through the
    // id_ex_pc_plus4 field when a prediction is available.  For a taken
    // branch/jump the predicted PC is the BTB target; for a not-taken branch
    // it is PC+4.  Since the interface does not carry a separate pred_pc,
    // reconstruct the predicted next PC from the epoch-carrying PC+4 field.
    //
    // For JALR, the architectural target must have bit0 cleared.  The BTB
    // target is stored with the same alignment, but to make the comparison
    // robust against a stale/unaligned BTB entry, compare the full 32-bit
    // predicted value against the aligned actual target.
    assign pred_next_pc = id_ex_pc_plus4;

    // Misprediction flush: asserted in the same cycle the control instruction
    // is resolved in EX.  It must clear the two younger stages (IF/ID and
    // ID/EX) on the next edge, but must not clear the resolved instruction
    // itself or any older instruction.
    //
    // Full 32-bit comparison is used.  For JALR, actual_next_pc is already
    // aligned to 32'hFFFF_FFFE, so a stale BTB target differing in any bit
    // (including bit0) triggers a redirect.
    assign mispredict_flush = control_valid && (actual_next_pc != pred_next_pc);

    // Redirect
    assign redirect_valid = mispredict_flush;
    assign redirect_pc = actual_next_pc;

    // Flush controls for the two younger pipeline stages.
    assign flush_ifid = mispredict_flush;
    assign flush_idex = mispredict_flush;

    // Prediction update signals
    assign update_valid = control_valid;
    assign update_pc = id_ex_pc;
    assign update_taken = (id_ex_jal || id_ex_jalr) ? 1'b1 : branch_taken;
    assign update_target = actual_next_pc;
    assign update_is_branch = id_ex_branch;
    assign update_is_jal = id_ex_jal;
    assign update_is_jalr = id_ex_jalr;
    assign update_epoch = id_ex_epoch;

    // Debug signals
    assign dbg_bp_resolve = control_valid;
    assign dbg_bp_mispredict = mispredict_flush;

    // Pipeline registers
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ex_mem_valid <= 1'b0;
            ex_mem_pc <= 32'b0;
            ex_mem_insn <= 32'b0;
            ex_mem_pc_plus4 <= 32'b0;
            ex_mem_alu_result <= 32'b0;
            ex_mem_rs2_val <= 32'b0;
            ex_mem_rd_addr <= 5'b0;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_ecall <= 1'b0;
            ex_mem_epoch <= 2'b0;
        end else begin
            ex_mem_valid <= id_ex_valid;
            ex_mem_pc <= id_ex_pc;
            ex_mem_insn <= id_ex_insn;
            ex_mem_pc_plus4 <= id_ex_pc_plus4;
            ex_mem_alu_result <= alu_result;
            ex_mem_rs2_val <= rs2_fwd;
            ex_mem_rd_addr <= id_ex_rd_addr;
            ex_mem_reg_write <= id_ex_reg_write;
            ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_ecall <= id_ex_ecall;
            ex_mem_epoch <= id_ex_epoch;
        end
    end

endmodule
