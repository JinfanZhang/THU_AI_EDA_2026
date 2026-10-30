module rv32i5 (
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    output logic        imem_valid,
    input  logic        imem_ready,
    output logic        dmem_valid,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_be,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_ready,
    input  logic [4:0]  dbg_reg_addr,
    output logic [31:0] dbg_reg_data,
    output logic        halted,
    output logic [31:0] exit_code,
    output logic [2:0]  dbg_features,
    output logic        dbg_retire_valid,
    output logic [31:0] dbg_retire_pc,
    output logic [31:0] dbg_retire_insn,
    output logic        dbg_bp_resolve,
    output logic        dbg_bp_mispredict,
    output logic        dbg_ooo_issue,
    output logic        dbg_ooo_bypass
);

    // ---------------------------------------------------------------
    // Global control
    // ---------------------------------------------------------------
    logic        halt_pending;
    logic        halt_enter;
    logic        flush_all;
    logic [1:0]  flush_epoch;

    logic        redirect_valid;
    logic [31:0] redirect_pc;
    logic        squash_valid;
    logic [7:0]  squash_mask;
    logic        restore_valid;
    logic [1:0]  restore_ckpt;

    logic        bp_update_valid;
    logic [31:0] bp_update_pc;
    logic        bp_update_is_cond;
    logic        bp_update_taken;
    logic [31:0] bp_update_target;

    logic        rob_head_valid;
    logic [2:0]  rob_head;

    // ---------------------------------------------------------------
    // Fetch <-> ICache <-> Branch predictor
    // ---------------------------------------------------------------
    logic        ic_req_valid;
    logic [31:0] ic_req_addr;
    logic        ic_req_ready;
    logic        ic_resp_valid;
    logic [31:0] ic_resp_data;
    logic        ic_flush;
    logic [1:0]  ic_flush_epoch;
    logic        ic_idle;

    logic        bp_req_valid;
    logic [31:0] bp_pc;
    logic [31:0] bp_npc;
    logic        bp_hit;
    logic        bp_taken;

    logic        if_valid;
    logic        if_ready;
    logic [31:0] if_pc;
    logic [31:0] if_insn;
    logic [31:0] if_pred_npc;
    logic        if_pred_valid;

    // ---------------------------------------------------------------
    // Rename <-> ROB
    // ---------------------------------------------------------------
    logic        rob_disp_valid;
    logic        rob_disp_ready;
    logic [31:0] disp_pc;
    logic [31:0] disp_insn;
    logic [5:0]  disp_prd;
    logic [5:0]  disp_old_prd;
    logic        disp_has_dest;
    logic [4:0]  disp_arch_rd;
    logic        disp_is_load;
    logic        disp_is_store;
    logic        disp_is_ctrl;
    logic        disp_is_cond;
    logic        disp_is_ecall;
    logic        disp_is_ckpt_owner;
    logic [1:0]  disp_ckpt_id;
    logic [31:0] disp_pred_npc;
    logic        disp_pred_valid;
    logic [2:0]  disp_rob_idx;

    // ---------------------------------------------------------------
    // Rename <-> IQ
    // ---------------------------------------------------------------
    logic        iq_disp_valid;
    logic        iq_disp_ready;
    logic [3:0]  disp_alu_op;
    logic [2:0]  disp_br_funct3;
    logic [31:0] disp_imm;
    logic [5:0]  disp_prs1;
    logic [5:0]  disp_prs2;
    logic        disp_prs1_ready;
    logic        disp_prs2_ready;
    logic        disp_use_rs1;
    logic        disp_use_rs2;

    // ---------------------------------------------------------------
    // Rename <-> LSU
    // ---------------------------------------------------------------
    logic        lsq_disp_valid;
    logic        lsq_disp_ready;
    logic [2:0]  disp_mem_funct3;

    // ---------------------------------------------------------------
    // Rename commit / dbg
    // ---------------------------------------------------------------
    logic        commit_valid;
    logic [4:0]  commit_arch_rd;
    logic [5:0]  commit_prd;
    logic        commit_has_dest;
    logic        commit_old_prd_valid;
    logic [5:0]  commit_old_prd;
    logic [5:0]  dbg_prd;

    // ---------------------------------------------------------------
    // IQ <-> ALU
    // ---------------------------------------------------------------
    logic        issue_valid;
    logic        issue_ready;
    logic [3:0]  issue_alu_op;
    logic [2:0]  issue_br_funct3;
    logic [31:0] issue_imm;
    logic [31:0] issue_pc;
    logic [5:0]  issue_prs1;
    logic [5:0]  issue_prs2;
    logic [5:0]  issue_prd;
    logic        issue_has_dest;
    logic [2:0]  issue_rob_idx;

    logic [31:0] prf_rdata1;
    logic [31:0] prf_rdata2;
    logic [31:0] prf_rdata3;
    logic [31:0] prf_rdata4;

    logic [31:0] alu_result;
    logic        alu_br_taken;
    logic [31:0] alu_br_target;

    // ---------------------------------------------------------------
    // ALU completion -> ROB / PRF
    // ---------------------------------------------------------------
    logic        ex_valid;
    logic [2:0]  ex_rob_idx;
    logic [31:0] ex_result;
    logic [31:0] ex_npc;
    logic        ex_wakeup_valid;
    logic [5:0]  ex_wakeup_prd;

    // ---------------------------------------------------------------
    // LSU <-> ROB / PRF / DCache
    // ---------------------------------------------------------------
    logic [5:0]  lsu_op_rs1_pr;
    logic [5:0]  lsu_op_rs2_pr;
    logic [31:0] lsu_op_rs1_val;
    logic [31:0] lsu_op_rs2_val;

    logic        lsu_wb_valid;
    logic [2:0]  lsu_wb_rob_idx;
    logic [5:0]  lsu_wb_prd;
    logic        lsu_wb_has_dest;
    logic [31:0] lsu_wb_data;

    logic        dc_req_valid;
    logic        dc_req_we;
    logic [31:0] dc_req_addr;
    logic [31:0] dc_req_wdata;
    logic [3:0]  dc_req_be;
    logic        dc_req_ready;
    logic        dc_resp_valid;
    logic [31:0] dc_resp_rdata;
    logic        dc_idle;
    logic        lsu_dwait;

    // ---------------------------------------------------------------
    // PRF write
    // ---------------------------------------------------------------
    logic        prf_we;
    logic [5:0]  prf_waddr;
    logic [31:0] prf_wdata;

    // ---------------------------------------------------------------
    // ROB outputs
    // ---------------------------------------------------------------
    logic        rob_retire_valid;
    logic [31:0] rob_retire_pc;
    logic [31:0] rob_retire_insn;
    logic        rob_bp_resolve;
    logic        rob_bp_mispredict;
    logic        rob_halted;
    logic [31:0] rob_exit_code;

    // ---------------------------------------------------------------
    // Global control assignments
    // ---------------------------------------------------------------
    assign flush_all       = redirect_valid | halt_enter;
    assign ic_flush        = flush_all;
    assign ic_flush_epoch  = flush_epoch;
    assign dbg_features    = 3'b111;

    // ---------------------------------------------------------------
    // Fetch unit
    // ---------------------------------------------------------------
    fetch_unit u_fetch (
        .clk            (clk),
        .rst_n          (rst_n),
        .halt_pending   (halt_pending),
        .halted         (halted),
        .flush_all      (flush_all),
        .flush_epoch    (flush_epoch),
        .redirect_valid (redirect_valid),
        .redirect_pc    (redirect_pc),
        .ic_req_valid   (ic_req_valid),
        .ic_req_addr    (ic_req_addr),
        .ic_req_ready   (ic_req_ready),
        .ic_resp_valid  (ic_resp_valid),
        .ic_resp_data   (ic_resp_data),
        .ic_flush       (ic_flush),
        .ic_flush_epoch (ic_flush_epoch),
        .bp_req_valid   (bp_req_valid),
        .bp_pc          (bp_pc),
        .bp_npc         (bp_npc),
        .bp_hit         (bp_hit),
        .if_valid       (if_valid),
        .if_ready       (if_ready),
        .if_pc          (if_pc),
        .if_insn        (if_insn),
        .if_pred_npc    (if_pred_npc),
        .if_pred_valid  (if_pred_valid)
    );

    // ---------------------------------------------------------------
    // Branch predictor
    // ---------------------------------------------------------------
    branch_predictor u_bp (
        .clk              (clk),
        .rst_n            (rst_n),
        .predict_req_valid(bp_req_valid),
        .predict_pc       (bp_pc),
        .predict_npc      (bp_npc),
        .predict_hit      (bp_hit),
        .predict_taken    (bp_taken),
        .update_valid     (bp_update_valid),
        .update_pc        (bp_update_pc),
        .update_is_cond   (bp_update_is_cond),
        .update_taken     (bp_update_taken),
        .update_target    (bp_update_target),
        .flush            (flush_all)
    );

    // ---------------------------------------------------------------
    // I-Cache
    // ---------------------------------------------------------------
    icache u_icache (
        .clk            (clk),
        .rst_n          (rst_n),
        .cpu_req_valid  (ic_req_valid),
        .cpu_req_addr   (ic_req_addr),
        .cpu_req_ready  (ic_req_ready),
        .cpu_resp_valid (ic_resp_valid),
        .cpu_resp_data  (ic_resp_data),
        .flush          (ic_flush),
        .flush_epoch    (ic_flush_epoch),
        .mem_req_valid  (imem_valid),
        .mem_req_addr   (imem_addr),
        .mem_req_ready  (imem_ready),
        .mem_resp_valid (imem_valid & imem_ready),
        .mem_resp_data  (imem_rdata),
        .idle           (ic_idle)
    );

    // ---------------------------------------------------------------
    // Rename unit
    // ---------------------------------------------------------------
    rename_unit u_rename (
        .clk               (clk),
        .rst_n             (rst_n),
        .if_valid          (if_valid),
        .if_ready          (if_ready),
        .if_pc             (if_pc),
        .if_insn           (if_insn),
        .if_pred_npc       (if_pred_npc),
        .if_pred_valid     (if_pred_valid),
        .rob_disp_valid    (rob_disp_valid),
        .rob_disp_ready    (rob_disp_ready),
        .disp_pc           (disp_pc),
        .disp_insn         (disp_insn),
        .disp_prd          (disp_prd),
        .disp_old_prd      (disp_old_prd),
        .disp_has_dest     (disp_has_dest),
        .disp_arch_rd      (disp_arch_rd),
        .disp_is_load      (disp_is_load),
        .disp_is_store     (disp_is_store),
        .disp_is_ctrl      (disp_is_ctrl),
        .disp_is_cond      (disp_is_cond),
        .disp_is_ecall     (disp_is_ecall),
        .disp_is_ckpt_owner(disp_is_ckpt_owner),
        .disp_ckpt_id      (disp_ckpt_id),
        .disp_pred_npc     (disp_pred_npc),
        .disp_pred_valid   (disp_pred_valid),
        .disp_rob_idx      (disp_rob_idx),
        .iq_disp_valid     (iq_disp_valid),
        .iq_disp_ready     (iq_disp_ready),
        .disp_alu_op       (disp_alu_op),
        .disp_br_funct3    (disp_br_funct3),
        .disp_imm          (disp_imm),
        .disp_prs1         (disp_prs1),
        .disp_prs2         (disp_prs2),
        .disp_prs1_ready   (disp_prs1_ready),
        .disp_prs2_ready   (disp_prs2_ready),
        .disp_use_rs1      (disp_use_rs1),
        .disp_use_rs2      (disp_use_rs2),
        .lsq_disp_valid    (lsq_disp_valid),
        .lsq_disp_ready    (lsq_disp_ready),
        .disp_mem_funct3   (disp_mem_funct3),
        .commit_valid      (commit_valid),
        .commit_arch_rd    (commit_arch_rd),
        .commit_prd        (commit_prd),
        .commit_has_dest   (commit_has_dest),
        .commit_old_prd_valid(commit_old_prd_valid),
        .commit_old_prd    (commit_old_prd),
        .restore_valid     (restore_valid),
        .restore_ckpt      (restore_ckpt),
        .ex_wakeup_valid   (ex_wakeup_valid),
        .ex_wakeup_prd     (ex_wakeup_prd),
        .lsu_wb_valid      (lsu_wb_valid),
        .lsu_wb_prd        (lsu_wb_prd),
        .halt_pending      (halt_pending),
        .halt_enter        (halt_enter),
        .dbg_prd           (dbg_prd)
    );

    // ---------------------------------------------------------------
    // Issue queue
    // ---------------------------------------------------------------
    issue_queue u_iq (
        .clk             (clk),
        .rst_n           (rst_n),
        .iq_disp_valid   (iq_disp_valid),
        .iq_disp_ready   (iq_disp_ready),
        .disp_pc         (disp_pc),
        .disp_alu_op     (disp_alu_op),
        .disp_br_funct3  (disp_br_funct3),
        .disp_imm        (disp_imm),
        .disp_prs1       (disp_prs1),
        .disp_prs2       (disp_prs2),
        .disp_prs1_ready (disp_prs1_ready),
        .disp_prs2_ready (disp_prs2_ready),
        .disp_use_rs1    (disp_use_rs1),
        .disp_use_rs2    (disp_use_rs2),
        .disp_prd        (disp_prd),
        .disp_has_dest   (disp_has_dest),
        .disp_rob_idx    (disp_rob_idx),
        .issue_valid     (issue_valid),
        .issue_ready     (issue_ready),
        .issue_alu_op    (issue_alu_op),
        .issue_br_funct3 (issue_br_funct3),
        .issue_imm       (issue_imm),
        .issue_pc        (issue_pc),
        .issue_prs1      (issue_prs1),
        .issue_prs2      (issue_prs2),
        .issue_prd       (issue_prd),
        .issue_has_dest  (issue_has_dest),
        .issue_rob_idx   (issue_rob_idx),
        .lsu_wb_valid    (lsu_wb_valid),
        .lsu_wb_prd      (lsu_wb_prd),
        .squash_valid    (squash_valid),
        .squash_mask     (squash_mask)
    );

    // ---------------------------------------------------------------
    // ALU
    // ---------------------------------------------------------------
    alu u_alu (
        .alu_op    (issue_alu_op),
        .a         (prf_rdata1),
        .b         (prf_rdata2),
        .imm       (issue_imm),
        .pc        (issue_pc),
        .br_funct3 (issue_br_funct3),
        .result    (alu_result),
        .br_taken  (alu_br_taken),
        .br_target (alu_br_target)
    );

    assign issue_ready = 1'b1;

    // ALU completion
    assign ex_valid       = issue_valid;
    assign ex_rob_idx     = issue_rob_idx;
    assign ex_result      = alu_result;
    assign ex_npc         = alu_br_target;
    assign ex_wakeup_valid= issue_valid & issue_has_dest;
    assign ex_wakeup_prd  = issue_prd;

    // ---------------------------------------------------------------
    // Load/store unit
    // ---------------------------------------------------------------
    load_store_unit u_lsu (
        .clk             (clk),
        .rst_n           (rst_n),
        .lsq_disp_valid  (lsq_disp_valid),
        .lsq_disp_ready  (lsq_disp_ready),
        .disp_imm        (disp_imm),
        .disp_prs1       (disp_prs1),
        .disp_prs2       (disp_prs2),
        .disp_prs1_ready (disp_prs1_ready),
        .disp_prs2_ready (disp_prs2_ready),
        .disp_prd        (disp_prd),
        .disp_has_dest   (disp_has_dest),
        .disp_is_store   (disp_is_store),
        .disp_mem_funct3 (disp_mem_funct3),
        .disp_rob_idx    (disp_rob_idx),
        .op_rs1_pr       (lsu_op_rs1_pr),
        .op_rs2_pr       (lsu_op_rs2_pr),
        .op_rs1_val      (lsu_op_rs1_val),
        .op_rs2_val      (lsu_op_rs2_val),
        .lsu_wb_valid    (lsu_wb_valid),
        .lsu_wb_prd      (lsu_wb_prd),
        .ex_wakeup_valid (ex_wakeup_valid),
        .ex_wakeup_prd   (ex_wakeup_prd),
        .rob_head        (rob_head),
        .rob_head_valid  (rob_head_valid),
        .alu_issue_valid (issue_valid),
        .wb_valid        (lsu_wb_valid),
        .wb_rob_idx      (lsu_wb_rob_idx),
        .wb_prd          (lsu_wb_prd),
        .wb_has_dest     (lsu_wb_has_dest),
        .wb_data         (lsu_wb_data),
        .dc_req_valid    (dc_req_valid),
        .dc_req_we       (dc_req_we),
        .dc_req_addr     (dc_req_addr),
        .dc_req_wdata    (dc_req_wdata),
        .dc_req_be       (dc_req_be),
        .dc_req_ready    (dc_req_ready),
        .dc_resp_valid   (dc_resp_valid),
        .dc_resp_rdata   (dc_resp_rdata),
        .squash_valid    (squash_valid),
        .squash_mask     (squash_mask),
        .dwait           (lsu_dwait),
        .idle            ()
    );

    assign lsu_op_rs1_val = prf_rdata3;
    assign lsu_op_rs2_val = prf_rdata4;

    // ---------------------------------------------------------------
    // D-Cache
    // ---------------------------------------------------------------
    dcache u_dcache (
        .clk            (clk),
        .rst_n          (rst_n),
        .cpu_req_valid  (dc_req_valid),
        .cpu_req_we     (dc_req_we),
        .cpu_req_addr   (dc_req_addr),
        .cpu_req_wdata  (dc_req_wdata),
        .cpu_req_be     (dc_req_be),
        .cpu_req_ready  (dc_req_ready),
        .cpu_resp_valid (dc_resp_valid),
        .cpu_resp_rdata (dc_resp_rdata),
        .flush          (flush_all),
        .flush_epoch    (flush_epoch),
        .mem_req_valid  (dmem_valid),
        .mem_req_we     (dmem_we),
        .mem_req_addr   (dmem_addr),
        .mem_req_wdata  (dmem_wdata),
        .mem_req_be     (dmem_be),
        .mem_req_ready  (dmem_ready),
        .mem_resp_valid (dmem_valid & dmem_ready & ~dmem_we),
        .mem_resp_data  (dmem_rdata),
        .idle           (dc_idle)
    );

    // ---------------------------------------------------------------
    // Reorder buffer
    // ---------------------------------------------------------------
    reorder_buffer u_rob (
        .clk              (clk),
        .rst_n            (rst_n),
        .rob_disp_valid   (rob_disp_valid),
        .rob_disp_ready   (rob_disp_ready),
        .disp_pc          (disp_pc),
        .disp_insn        (disp_insn),
        .disp_prd         (disp_prd),
        .disp_old_prd     (disp_old_prd),
        .disp_has_dest    (disp_has_dest),
        .disp_arch_rd     (disp_arch_rd),
        .disp_is_load     (disp_is_load),
        .disp_is_store    (disp_is_store),
        .disp_is_ctrl     (disp_is_ctrl),
        .disp_is_cond     (disp_is_cond),
        .disp_is_ecall    (disp_is_ecall),
        .disp_is_ckpt_owner(disp_is_ckpt_owner),
        .disp_ckpt_id     (disp_ckpt_id),
        .disp_pred_npc    (disp_pred_npc),
        .disp_rob_idx     (disp_rob_idx),
        .ex_valid         (ex_valid),
        .ex_rob_idx       (ex_rob_idx),
        .ex_result        (ex_result),
        .ex_npc           (ex_npc),
        .lsu_wb_valid     (lsu_wb_valid),
        .lsu_wb_rob_idx   (lsu_wb_rob_idx),
        .lsu_wb_data      (lsu_wb_data),
        .commit_valid     (commit_valid),
        .commit_arch_rd   (commit_arch_rd),
        .commit_prd       (commit_prd),
        .commit_has_dest  (commit_has_dest),
        .commit_old_prd_valid(commit_old_prd_valid),
        .commit_old_prd   (commit_old_prd),
        .redirect_valid   (redirect_valid),
        .redirect_pc      (redirect_pc),
        .flush_all        (),
        .flush_epoch      (flush_epoch),
        .squash_valid     (squash_valid),
        .squash_mask      (squash_mask),
        .restore_valid    (restore_valid),
        .restore_ckpt     (restore_ckpt),
        .bp_update_valid  (bp_update_valid),
        .bp_update_pc     (bp_update_pc),
        .bp_update_is_cond(bp_update_is_cond),
        .bp_update_taken  (bp_update_taken),
        .bp_update_target (bp_update_target),
        .dbg_retire_valid (rob_retire_valid),
        .dbg_retire_pc    (rob_retire_pc),
        .dbg_retire_insn  (rob_retire_insn),
        .dbg_bp_resolve   (rob_bp_resolve),
        .dbg_bp_mispredict(rob_bp_mispredict),
        .rob_head         (rob_head),
        .rob_head_valid   (rob_head_valid),
        .halted           (rob_halted),
        .exit_code        (rob_exit_code),
        .halt_enter       (halt_enter),
        .lsu_idle         (dc_idle),
        .ic_idle          (ic_idle)
    );

    // ---------------------------------------------------------------
    // PRF
    // ---------------------------------------------------------------
    assign prf_we    = ex_wakeup_valid;
    assign prf_waddr = ex_wakeup_prd;
    assign prf_wdata = alu_result;

    prf u_prf (
        .clk      (clk),
        .rst_n    (rst_n),
        .raddr1   (issue_prs1),
        .rdata1   (prf_rdata1),
        .raddr2   (issue_prs2),
        .rdata2   (prf_rdata2),
        .raddr3   (lsu_op_rs1_pr),
        .rdata3   (prf_rdata3),
        .raddr4   (lsu_op_rs2_pr),
        .rdata4   (prf_rdata4),
        .dbg_addr (dbg_prd),
        .dbg_data (dbg_reg_data),
        .we       (prf_we),
        .waddr    (prf_waddr),
        .wdata    (prf_wdata)
    );

    // ---------------------------------------------------------------
    // Top-level outputs
    // ---------------------------------------------------------------
    assign halted            = rob_halted;
    assign exit_code         = rob_exit_code;
    assign dbg_retire_valid  = rob_retire_valid & rst_n & ~rob_halted;
    assign dbg_retire_pc     = rob_retire_pc;
    assign dbg_retire_insn   = rob_retire_insn;
    assign dbg_bp_resolve    = rob_bp_resolve & rst_n & ~rob_halted;
    assign dbg_bp_mispredict = rob_bp_mispredict & rst_n & ~rob_halted;

    assign dbg_ooo_issue     = ((iq_disp_valid & iq_disp_ready) |
                                (lsq_disp_valid & lsq_disp_ready)) & rst_n & ~rob_halted;
    assign dbg_ooo_bypass    = lsu_dwait & issue_valid & rst_n & ~rob_halted;

endmodule
