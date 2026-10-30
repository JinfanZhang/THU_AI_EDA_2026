module rename_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        if_valid,
    output logic        if_ready,
    input  logic [31:0] if_pc,
    input  logic [31:0] if_insn,
    input  logic [31:0] if_pred_npc,
    input  logic        if_pred_valid,
    output logic        rob_disp_valid,
    input  logic        rob_disp_ready,
    output logic [31:0] disp_pc,
    output logic [31:0] disp_insn,
    output logic [5:0]  disp_prd,
    output logic [5:0]  disp_old_prd,
    output logic        disp_has_dest,
    output logic [4:0]  disp_arch_rd,
    output logic        disp_is_load,
    output logic        disp_is_store,
    output logic        disp_is_ctrl,
    output logic        disp_is_cond,
    output logic        disp_is_ecall,
    output logic        disp_is_ckpt_owner,
    output logic [1:0]  disp_ckpt_id,
    output logic [31:0] disp_pred_npc,
    output logic        disp_pred_valid,
    input  logic [2:0]  disp_rob_idx,
    output logic        iq_disp_valid,
    input  logic        iq_disp_ready,
    output logic [3:0]  disp_alu_op,
    output logic [2:0]  disp_br_funct3,
    output logic [31:0] disp_imm,
    output logic [5:0]  disp_prs1,
    output logic [5:0]  disp_prs2,
    output logic        disp_prs1_ready,
    output logic        disp_prs2_ready,
    output logic        disp_use_rs1,
    output logic        disp_use_rs2,
    output logic        lsq_disp_valid,
    input  logic        lsq_disp_ready,
    output logic [2:0]  disp_mem_funct3,
    output logic        halt_pending,
    output logic        halt_enter,
    input  logic        restore_valid,
    input  logic [1:0]  restore_ckpt,
    input  logic        commit_valid,
    input  logic [4:0]  commit_arch_rd,
    input  logic [5:0]  commit_prd,
    input  logic        commit_has_dest,
    input  logic        commit_old_prd_valid,
    input  logic [5:0]  commit_old_prd,
    input  logic        ex_wakeup_valid,
    input  logic [5:0]  ex_wakeup_prd,
    input  logic        lsu_wb_valid,
    input  logic [5:0]  lsu_wb_prd,
    output logic [4:0]  dbg_prd
);

    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_IMM    = 7'b0010011;
    localparam logic [6:0] OP_REG    = 7'b0110011;
    localparam logic [6:0] OP_SYSTEM = 7'b1110011;

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

    logic [5:0] rat [0:31];
    logic [5:0] committed_rat [0:31];
    logic [39:0] ready_tbl;
    logic [5:0] free_list [0:7];
    logic [3:0] free_head;
    logic [3:0] free_tail;
    logic [3:0] free_count;

    logic [5:0] ckpt_rat [0:3][0:31];
    logic [5:0] ckpt_free [0:3][0:7];
    logic [3:0] ckpt_free_head [0:3];
    logic [3:0] ckpt_free_tail [0:3];
    logic [3:0] ckpt_free_count [0:3];
    logic [3:0] ckpt_valid;
    logic [1:0] ckpt_alloc_ptr;

    logic halt_pending_r;
    logic halt_enter_r;

    assign halt_pending = halt_pending_r;
    assign halt_enter   = halt_enter_r;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;
    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    assign opcode = if_insn[6:0];
    assign funct3 = if_insn[14:12];
    assign funct7 = if_insn[31:25];
    assign rd     = if_insn[11:7];
    assign rs1    = if_insn[19:15];
    assign rs2    = if_insn[24:20];

    assign imm_i = {{20{if_insn[31]}}, if_insn[31:20]};
    assign imm_s = {{20{if_insn[31]}}, if_insn[31:25], if_insn[11:7]};
    assign imm_b = {{19{if_insn[31]}}, if_insn[31], if_insn[7], if_insn[30:25], if_insn[11:8], 1'b0};
    assign imm_u = {if_insn[31:12], 12'b0};
    assign imm_j = {{11{if_insn[31]}}, if_insn[31], if_insn[19:12], if_insn[20], if_insn[30:21], 1'b0};

    logic is_ecall;
    logic is_lui;
    logic is_auipc;
    logic is_jal;
    logic is_jalr;
    logic is_branch;
    logic is_load;
    logic is_store;
    logic is_alu_imm;
    logic is_alu_reg;
    logic is_ctrl;
    logic is_cond;
    logic has_dest;
    logic use_rs1;
    logic use_rs2;
    logic [3:0] alu_op;
    logic [31:0] imm_sel;
    logic [2:0] br_funct3;
    logic [2:0] mem_funct3;

    assign is_ecall   = (if_insn == 32'h0000_0073);
    assign is_lui     = (opcode == OP_LUI);
    assign is_auipc   = (opcode == OP_AUIPC);
    assign is_jal     = (opcode == OP_JAL);
    assign is_jalr    = (opcode == OP_JALR);
    assign is_branch  = (opcode == OP_BRANCH);
    assign is_load    = (opcode == OP_LOAD);
    assign is_store   = (opcode == OP_STORE);
    assign is_alu_imm = (opcode == OP_IMM);
    assign is_alu_reg = (opcode == OP_REG);

    assign is_ctrl = is_jal | is_jalr | is_branch;
    assign is_cond = is_branch;

    assign has_dest = (is_lui | is_auipc | is_jal | is_jalr | is_load |
                       is_alu_imm | is_alu_reg) & (rd != 5'd0);

    assign use_rs1 = (is_jalr | is_branch | is_load | is_store | is_alu_imm | is_alu_reg);
    assign use_rs2 = (is_branch | is_store | is_alu_reg);

    always_comb begin
        alu_op   = ALU_ADD;
        imm_sel  = 32'd0;
        br_funct3 = funct3;
        mem_funct3 = funct3;
        if (is_lui) begin
            alu_op  = ALU_LUI;
            imm_sel = imm_u;
        end else if (is_auipc) begin
            alu_op  = ALU_AUIPC;
            imm_sel = imm_u;
        end else if (is_jal) begin
            alu_op  = ALU_JUMP;
            imm_sel = imm_j;
        end else if (is_jalr) begin
            alu_op  = ALU_JUMP;
            imm_sel = imm_i;
        end else if (is_branch) begin
            alu_op  = ALU_BRANCH;
            imm_sel = imm_b;
        end else if (is_load) begin
            alu_op  = ALU_ADD;
            imm_sel = imm_i;
        end else if (is_store) begin
            alu_op  = ALU_ADD;
            imm_sel = imm_s;
        end else if (is_alu_imm) begin
            imm_sel = imm_i;
            case (funct3)
                3'b000: alu_op = ALU_ADD;
                3'b010: alu_op = ALU_SLT;
                3'b011: alu_op = ALU_SLTU;
                3'b100: alu_op = ALU_XOR;
                3'b110: alu_op = ALU_OR;
                3'b111: alu_op = ALU_AND;
                3'b001: alu_op = ALU_SLL;
                3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                default: alu_op = ALU_ADD;
            endcase
        end else if (is_alu_reg) begin
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
    end

    logic [5:0] src1_pr;
    logic [5:0] src2_pr;
    logic [5:0] dest_pr;
    logic [5:0] old_pr;
    logic [5:0] free_pr;
    logic free_avail;
    logic [1:0] ckpt_id_sel;
    logic is_ckpt_owner;

    assign src1_pr = use_rs1 ? rat[rs1] : 6'd0;
    assign src2_pr = use_rs2 ? rat[rs2] : 6'd0;
    assign free_avail = (free_count != 4'd0);
    assign free_pr = free_list[free_head[2:0]];
    assign dest_pr = has_dest ? free_pr : 6'd0;
    assign old_pr = has_dest ? rat[rd] : 6'd0;

    assign ckpt_id_sel = ckpt_alloc_ptr;
    assign is_ckpt_owner = is_ctrl & if_valid & ~halt_pending_r;

    logic need_alloc;
    logic need_iq;
    logic need_lsq;
    logic need_rob;
    logic can_disp;

    assign need_alloc = has_dest;
    assign need_iq = (is_alu_imm | is_alu_reg | is_lui | is_auipc | is_jal | is_jalr | is_branch);
    assign need_lsq = (is_load | is_store);
    assign need_rob = 1'b1;

    assign can_disp = if_valid & ~halt_pending_r &
                      (~need_alloc | free_avail) &
                      (~need_iq | iq_disp_ready) &
                      (~need_lsq | lsq_disp_ready) &
                      rob_disp_ready;

    assign if_ready = ~halt_pending_r & (~need_alloc | free_avail) &
                      (~need_iq | iq_disp_ready) &
                      (~need_lsq | lsq_disp_ready) &
                      rob_disp_ready;

    assign rob_disp_valid = can_disp;
    assign iq_disp_valid  = can_disp & need_iq;
    assign lsq_disp_valid = can_disp & need_lsq;

    assign disp_pc        = if_pc;
    assign disp_insn      = if_insn;
    assign disp_prd       = dest_pr;
    assign disp_old_prd   = old_pr;
    assign disp_has_dest  = has_dest;
    assign disp_arch_rd   = rd;
    assign disp_is_load   = is_load;
    assign disp_is_store  = is_store;
    assign disp_is_ctrl   = is_ctrl;
    assign disp_is_cond   = is_cond;
    assign disp_is_ecall  = is_ecall;
    assign disp_is_ckpt_owner = is_ckpt_owner;
    assign disp_ckpt_id   = ckpt_id_sel;
    assign disp_pred_npc  = if_pred_npc;
    assign disp_pred_valid = if_pred_valid;
    assign disp_alu_op    = alu_op;
    assign disp_br_funct3 = br_funct3;
    assign disp_imm       = imm_sel;
    assign disp_prs1      = src1_pr;
    assign disp_prs2      = src2_pr;
    assign disp_prs1_ready = ready_tbl[src1_pr];
    assign disp_prs2_ready = ready_tbl[src2_pr];
    assign disp_use_rs1   = use_rs1;
    assign disp_use_rs2   = use_rs2;
    assign disp_mem_funct3 = mem_funct3;

    assign dbg_prd = committed_rat[5'd0] == 6'd0 ? 5'd0 : 5'd0;

    integer i;
    integer j;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                rat[i] <= i[5:0];
                committed_rat[i] <= i[5:0];
            end
            ready_tbl <= 40'h0000_0000_FFFF_FFFF;
            for (i = 0; i < 8; i = i + 1) begin
                free_list[i] <= 6'd32 + i[5:0];
            end
            free_head <= 4'd0;
            free_tail <= 4'd0;
            free_count <= 4'd8;
            ckpt_valid <= 4'd0;
            ckpt_alloc_ptr <= 2'd0;
            for (i = 0; i < 4; i = i + 1) begin
                ckpt_free_head[i] <= 4'd0;
                ckpt_free_tail[i] <= 4'd0;
                ckpt_free_count[i] <= 4'd0;
                for (j = 0; j < 32; j = j + 1) begin
                    ckpt_rat[i][j] <= j[5:0];
                end
                for (j = 0; j < 8; j = j + 1) begin
                    ckpt_free[i][j] <= 6'd0;
                end
            end
            halt_pending_r <= 1'b0;
            halt_enter_r <= 1'b0;
        end else begin
            halt_enter_r <= 1'b0;

            if (restore_valid) begin
                for (i = 0; i < 32; i = i + 1) begin
                    rat[i] <= ckpt_rat[restore_ckpt][i];
                end
                for (i = 0; i < 8; i = i + 1) begin
                    free_list[i] <= ckpt_free[restore_ckpt][i];
                end
                free_head <= ckpt_free_head[restore_ckpt];
                free_tail <= ckpt_free_tail[restore_ckpt];
                free_count <= ckpt_free_count[restore_ckpt];
                ckpt_valid[restore_ckpt] <= 1'b0;
                ckpt_alloc_ptr <= restore_ckpt;
                halt_pending_r <= 1'b0;
                for (i = 0; i < 40; i = i + 1) begin
                    if (i == 0) begin
                        ready_tbl[i] <= 1'b1;
                    end else begin
                        ready_tbl[i] <= 1'b0;
                    end
                end
                for (i = 0; i < 32; i = i + 1) begin
                    ready_tbl[ckpt_rat[restore_ckpt][i]] <= 1'b1;
                end
            end else begin
                if (ex_wakeup_valid) begin
                    ready_tbl[ex_wakeup_prd] <= 1'b1;
                end
                if (lsu_wb_valid) begin
                    ready_tbl[lsu_wb_prd] <= 1'b1;
                end

                if (commit_valid) begin
                    if (commit_has_dest) begin
                        committed_rat[commit_arch_rd] <= commit_prd;
                    end
                    if (commit_old_prd_valid) begin
                        ready_tbl[commit_old_prd] <= 1'b0;
                        free_list[free_tail[2:0]] <= commit_old_prd;
                        free_tail <= free_tail + 4'd1;
                        free_count <= free_count + 4'd1;
                        for (i = 0; i < 4; i = i + 1) begin
                            if (ckpt_valid[i]) begin
                                ckpt_free[i][ckpt_free_tail[i][2:0]] <= commit_old_prd;
                                ckpt_free_tail[i] <= ckpt_free_tail[i] + 4'd1;
                                ckpt_free_count[i] <= ckpt_free_count[i] + 4'd1;
                            end
                        end
                    end
                end

                if (can_disp) begin
                    if (has_dest) begin
                        rat[rd] <= free_pr;
                        ready_tbl[free_pr] <= 1'b0;
                        free_head <= free_head + 4'd1;
                        free_count <= free_count - 4'd1;
                        for (i = 0; i < 4; i = i + 1) begin
                            if (ckpt_valid[i]) begin
                                ckpt_free_head[i] <= ckpt_free_head[i] + 4'd1;
                                ckpt_free_count[i] <= ckpt_free_count[i] - 4'd1;
                            end
                        end
                    end
                    if (is_ecall) begin
                        halt_pending_r <= 1'b1;
                        halt_enter_r <= 1'b1;
                    end
                    if (is_ckpt_owner) begin
                        for (i = 0; i < 32; i = i + 1) begin
                            ckpt_rat[ckpt_id_sel][i] <= rat[i];
                        end
                        if (has_dest) begin
                            ckpt_rat[ckpt_id_sel][rd] <= free_pr;
                        end
                        for (i = 0; i < 8; i = i + 1) begin
                            ckpt_free[ckpt_id_sel][i] <= free_list[i];
                        end
                        if (has_dest) begin
                            ckpt_free[ckpt_id_sel][free_head[2:0]] <= 6'd0;
                        end
                        ckpt_free_head[ckpt_id_sel] <= free_head + (has_dest ? 4'd1 : 4'd0);
                        ckpt_free_tail[ckpt_id_sel] <= free_tail;
                        ckpt_free_count[ckpt_id_sel] <= free_count - (has_dest ? 4'd1 : 4'd0);
                        ckpt_valid[ckpt_id_sel] <= 1'b1;
                        ckpt_alloc_ptr <= ckpt_alloc_ptr + 2'd1;
                    end
                end
            end
        end
    end

endmodule
