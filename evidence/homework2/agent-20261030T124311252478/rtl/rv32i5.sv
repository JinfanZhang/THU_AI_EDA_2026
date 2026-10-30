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

    // ============================================================
    // Internal signals
    // ============================================================

    // Fetch unit <-> ICache
    logic        fetch_icache_cpu_req_valid;
    logic [31:0] fetch_icache_cpu_req_addr;
    logic        fetch_icache_cpu_req_ready;
    logic        fetch_icache_cpu_resp_valid;
    logic [31:0] fetch_icache_cpu_resp_data;
    logic        fetch_icache_flush;
    logic [1:0]  fetch_icache_flush_epoch;

    // ROB epoch/flush
    logic [1:0]  rob_epoch;
    logic        rob_flush;

    // Branch predictor
    logic [31:0] fetch_branch_pred_pc_query;
    logic        fetch_branch_pred_valid;
    logic        fetch_branch_pred_taken;
    logic [31:0] fetch_branch_pred_target;

    // Redirect
    logic        redirect_valid;
    logic [31:0] redirect_pc;

    // Halt request
    logic        halt_request;

    // Fetch -> Decode
    logic        fetch_valid;
    logic [31:0] fetch_pc;
    logic [31:0] fetch_insn;
    logic        decode_ready;

    // Decode -> Rename
    logic        dec_valid;
    logic [31:0] dec_pc;
    logic [31:0] dec_insn;
    logic [4:0]  dec_rs1;
    logic [4:0]  dec_rs2;
    logic [4:0]  dec_rd;
    logic [31:0] dec_imm;
    logic [3:0]  dec_op_type;
    logic [2:0]  dec_func3;
    logic [6:0]  dec_func7;
    logic        ren_ready;

    // Rename -> IQ
    logic        iq_dispatch_valid;
    logic [31:0] iq_dispatch_pc;
    logic [31:0] iq_dispatch_insn;
    logic [5:0]  iq_dispatch_prs1;
    logic [5:0]  iq_dispatch_prs2;
    logic [5:0]  iq_dispatch_prd;
    logic [2:0]  iq_dispatch_rob_idx;
    logic [31:0] iq_dispatch_imm;
    logic [3:0]  iq_dispatch_op_type;
    logic [2:0]  iq_dispatch_func3;
    logic [6:0]  iq_dispatch_func7;
    logic        iq_full;

    // Rename -> ROB
    logic        rob_alloc_req_valid;
    logic [31:0] rob_alloc_req_pc;
    logic [31:0] rob_alloc_req_insn;
    logic [5:0]  rob_alloc_req_prd;
    logic [5:0]  rob_alloc_req_old_prd;
    logic        rob_alloc_grant;
    logic [2:0]  rob_alloc_idx;

    // IQ -> ALU
    logic        alu_issue_valid;
    logic [5:0]  alu_issue_prs1;
    logic [5:0]  alu_issue_prs2;
    logic [5:0]  alu_issue_prd;
    logic [2:0]  alu_issue_rob_idx;
    logic [31:0] alu_issue_imm;
    logic [3:0]  alu_issue_op_type;
    logic [2:0]  alu_issue_func3;
    logic [6:0]  alu_issue_func7;
    logic [31:0] alu_issue_pc;

    // IQ -> LSU
    logic        lsu_issue_valid;
    logic [5:0]  lsu_issue_prs1;
    logic [5:0]  lsu_issue_prs2;
    logic [5:0]  lsu_issue_prd;
    logic [2:0]  lsu_issue_rob_idx;
    logic [31:0] lsu_issue_imm;
    logic [3:0]  lsu_issue_op_type;
    logic [2:0]  lsu_issue_func3;
    logic [31:0] lsu_issue_pc;

    // ALU -> PRF
    logic [5:0]  alu_prf_read1_addr;
    logic [31:0] alu_prf_read1_data;
    logic [5:0]  alu_prf_read2_addr;
    logic [31:0] alu_prf_read2_data;
    logic        alu_prf_write_valid;
    logic [5:0]  alu_prf_write_pr;
    logic [31:0] alu_prf_write_data;

    // ALU -> ROB
    logic        alu_rob_complete_valid;
    logic [2:0]  alu_rob_complete_rob_idx;
    logic [5:0]  alu_rob_complete_prd;
    logic [31:0] alu_rob_complete_data;
    logic        alu_rob_mispredict_valid;
    logic [31:0] alu_rob_mispredict_pc;

    // ALU -> Branch predictor
    logic        alu_bp_resolve_valid;
    logic [31:0] alu_bp_resolve_pc;
    logic        alu_bp_resolve_taken;
    logic [31:0] alu_bp_resolve_target;
    logic        alu_bp_resolve_is_cond;

    // Squash
    logic        squash_valid;

    // LSU -> PRF
    logic [5:0]  lsu_prf_read1_addr;
    logic [31:0] lsu_prf_read1_data;
    logic [5:0]  lsu_prf_read2_addr;
    logic [31:0] lsu_prf_read2_data;
    logic        lsu_prf_write_valid;
    logic [5:0]  lsu_prf_write_pr;
    logic [31:0] lsu_prf_write_data;

    // LSU -> DCache
    logic        lsu_dcache_cpu_req_valid;
    logic        lsu_dcache_cpu_req_we;
    logic [31:0] lsu_dcache_cpu_req_addr;
    logic [31:0] lsu_dcache_cpu_req_wdata;
    logic [3:0]  lsu_dcache_cpu_req_be;
    logic        lsu_dcache_cpu_req_ready;
    logic        lsu_dcache_cpu_resp_valid;
    logic [31:0] lsu_dcache_cpu_resp_rdata;
    logic        lsu_dcache_flush;
    logic [1:0]  lsu_dcache_flush_epoch;

    // LSU -> ROB
    logic        lsu_rob_complete_valid;
    logic [2:0]  lsu_rob_complete_rob_idx;
    logic [5:0]  lsu_rob_complete_prd;
    logic [31:0] lsu_rob_complete_data;

    // ROB -> Rename (checkpoint)
    logic        rob_restore_valid;
    logic [2:0]  rob_restore_checkpoint_id;
    logic        rob_squash_valid;
    logic [2:0]  rob_squash_rob_idx;
    logic        rob_retire_valid;
    logic [31:0] rob_retire_pc;
    logic [31:0] rob_retire_insn;
    logic [4:0]  rob_retire_arch_reg;
    logic [5:0]  rob_retire_phys_reg;
    logic [5:0]  rob_retire_old_phys_reg;
    logic        rob_retire_is_ecall;
    logic [31:0] rob_retire_exit_code;
    logic        rob_retire_store;
    logic        rob_retire_load;
    logic        rob_retire_branch;
    logic        rob_retire_jal;
    logic        rob_retire_jalr;

    // ROB -> PRF (commit write)
    logic        rob_prf_commit_valid;
    logic [5:0]  rob_prf_commit_pr;
    logic [31:0] rob_prf_commit_data;

    // ROB -> Fetch (redirect)
    logic        rob_redirect_valid;
    logic [31:0] rob_redirect_pc;

    // ROB -> Halt
    logic        rob_halt_valid;
    logic [31:0] rob_halt_exit_code;

    // ROB -> LSU (squash)
    logic        rob_lsu_squash_valid;
    logic [2:0]  rob_lsu_squash_rob_idx;

    // ROB -> IQ (squash)
    logic        rob_iq_squash_valid;
    logic [2:0]  rob_iq_squash_rob_idx;

    // ROB -> Rename (squash)
    logic        rob_ren_squash_valid;
    logic [2:0]  rob_ren_squash_rob_idx;

    // ROB -> Fetch (squash)
    logic        rob_fetch_squash_valid;
    logic [2:0]  rob_fetch_squash_rob_idx;

    // ROB -> Branch predictor (resolve)
    logic        rob_bp_resolve_valid;
    logic [31:0] rob_bp_resolve_pc;
    logic        rob_bp_resolve_taken;
    logic [31:0] rob_bp_resolve_target;
    logic        rob_bp_resolve_is_cond;

    // ROB -> LSU (dmem_waiting)
    logic        lsu_dmem_waiting;

    // ROB -> Top (dbg_ooo_bypass)
    logic        rob_dbg_ooo_bypass;

    // IQ -> Top (dbg_ooo_issue)
    logic        iq_dbg_ooo_issue;

    // ============================================================
    // Module instantiations
    // ============================================================

    fetch_unit u_fetch_unit (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .icache_cpu_req_valid   (fetch_icache_cpu_req_valid),
        .icache_cpu_req_addr    (fetch_icache_cpu_req_addr),
        .icache_cpu_req_ready   (fetch_icache_cpu_req_ready),
        .icache_cpu_resp_valid  (fetch_icache_cpu_resp_valid),
        .icache_cpu_resp_data   (fetch_icache_cpu_resp_data),
        .icache_flush           (fetch_icache_flush),
        .icache_flush_epoch     (fetch_icache_flush_epoch),
        .rob_epoch              (rob_epoch),
        .rob_flush              (rob_flush),
        .branch_pred_pc_query   (fetch_branch_pred_pc_query),
        .branch_pred_valid      (fetch_branch_pred_valid),
        .branch_pred_taken      (fetch_branch_pred_taken),
        .branch_pred_target     (fetch_branch_pred_target),
        .redirect_valid         (redirect_valid),
        .redirect_pc            (redirect_pc),
        .halt_request           (halt_request),
        .fetch_valid            (fetch_valid),
        .fetch_pc               (fetch_pc),
        .fetch_insn             (fetch_insn),
        .decode_ready           (decode_ready)
    );

    decode_unit u_decode_unit (
        .clk            (clk),
        .rst_n          (rst_n),
        .fetch_valid    (fetch_valid),
        .fetch_pc       (fetch_pc),
        .fetch_insn     (fetch_insn),
        .dec_valid      (dec_valid),
        .dec_pc         (dec_pc),
        .dec_insn       (dec_insn),
        .dec_rs1        (dec_rs1),
        .dec_rs2        (dec_rs2),
        .dec_rd         (dec_rd),
        .dec_imm        (dec_imm),
        .dec_op_type    (dec_op_type),
        .dec_func3      (dec_func3),
        .dec_func7      (dec_func7),
        .ren_ready      (ren_ready)
    );

    rename_unit u_rename_unit (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .dec_valid              (dec_valid),
        .dec_pc                 (dec_pc),
        .dec_insn               (dec_insn),
        .dec_rs1                (dec_rs1),
        .dec_rs2                (dec_rs2),
        .dec_rd                 (dec_rd),
        .dec_imm                (dec_imm),
        .dec_op_type            (dec_op_type),
        .dec_func3              (dec_func3),
        .dec_func7              (dec_func7),
        .ren_ready              (ren_ready),
        .iq_dispatch_valid      (iq_dispatch_valid),
        .iq_dispatch_pc         (iq_dispatch_pc),
        .iq_dispatch_insn       (iq_dispatch_insn),
        .iq_dispatch_prs1       (iq_dispatch_prs1),
        .iq_dispatch_prs2       (iq_dispatch_prs2),
        .iq_dispatch_prd        (iq_dispatch_prd),
        .iq_dispatch_rob_idx    (iq_dispatch_rob_idx),
        .iq_dispatch_imm        (iq_dispatch_imm),
        .iq_dispatch_op_type    (iq_dispatch_op_type),
        .iq_dispatch_func3      (iq_dispatch_func3),
        .iq_dispatch_func7      (iq_dispatch_func7),
        .iq_full                (iq_full),
        .rob_alloc_req_valid    (rob_alloc_req_valid),
        .rob_alloc_req_pc       (rob_alloc_req_pc),
        .rob_alloc_req_insn     (rob_alloc_req_insn),
        .rob_alloc_req_prd      (rob_alloc_req_prd),
        .rob_alloc_req_old_prd  (rob_alloc_req_old_prd),
        .rob_alloc_grant        (rob_alloc_grant),
        .rob_alloc_idx          (rob_alloc_idx),
        .rob_restore_valid      (rob_restore_valid),
        .rob_restore_checkpoint_id (rob_restore_checkpoint_id),
        .rob_squash_valid       (rob_ren_squash_valid),
        .rob_squash_rob_idx     (rob_ren_squash_rob_idx)
    );

    issue_queue u_issue_queue (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .iq_dispatch_valid      (iq_dispatch_valid),
        .iq_dispatch_pc         (iq_dispatch_pc),
        .iq_dispatch_insn       (iq_dispatch_insn),
        .iq_dispatch_prs1       (iq_dispatch_prs1),
        .iq_dispatch_prs2       (iq_dispatch_prs2),
        .iq_dispatch_prd        (iq_dispatch_prd),
        .iq_dispatch_rob_idx    (iq_dispatch_rob_idx),
        .iq_dispatch_imm        (iq_dispatch_imm),
        .iq_dispatch_op_type    (iq_dispatch_op_type),
        .iq_dispatch_func3      (iq_dispatch_func3),
        .iq_dispatch_func7      (iq_dispatch_func7),
        .iq_full                (iq_full),
        .alu_issue_valid        (alu_issue_valid),
        .alu_issue_prs1         (alu_issue_prs1),
        .alu_issue_prs2         (alu_issue_prs2),
        .alu_issue_prd          (alu_issue_prd),
        .alu_issue_rob_idx      (alu_issue_rob_idx),
        .alu_issue_imm          (alu_issue_imm),
        .alu_issue_op_type      (alu_issue_op_type),
        .alu_issue_func3        (alu_issue_func3),
        .alu_issue_func7        (alu_issue_func7),
        .alu_issue_pc           (alu_issue_pc),
        .lsu_issue_valid        (lsu_issue_valid),
        .lsu_issue_prs1         (lsu_issue_prs1),
        .lsu_issue_prs2         (lsu_issue_prs2),
        .lsu_issue_prd          (lsu_issue_prd),
        .lsu_issue_rob_idx      (lsu_issue_rob_idx),
        .lsu_issue_imm          (lsu_issue_imm),
        .lsu_issue_op_type      (lsu_issue_op_type),
        .lsu_issue_func3        (lsu_issue_func3),
        .lsu_issue_pc           (lsu_issue_pc),
        .squash_valid           (rob_iq_squash_valid),
        .squash_rob_idx         (rob_iq_squash_rob_idx),
        .dbg_ooo_issue          (iq_dbg_ooo_issue)
    );

    alu_unit u_alu_unit (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .alu_issue_valid        (alu_issue_valid),
        .alu_issue_prs1         (alu_issue_prs1),
        .alu_issue_prs2         (alu_issue_prs2),
        .alu_issue_prd          (alu_issue_prd),
        .alu_issue_rob_idx      (alu_issue_rob_idx),
        .alu_issue_imm          (alu_issue_imm),
        .alu_issue_op_type      (alu_issue_op_type),
        .alu_issue_func3        (alu_issue_func3),
        .alu_issue_func7        (alu_issue_func7),
        .alu_issue_pc           (alu_issue_pc),
        .prf_read1_addr         (alu_prf_read1_addr),
        .prf_read1_data         (alu_prf_read1_data),
        .prf_read2_addr         (alu_prf_read2_addr),
        .prf_read2_data         (alu_prf_read2_data),
        .prf_write_valid        (alu_prf_write_valid),
        .prf_write_pr           (alu_prf_write_pr),
        .prf_write_data         (alu_prf_write_data),
        .rob_complete_valid     (alu_rob_complete_valid),
        .rob_complete_rob_idx   (alu_rob_complete_rob_idx),
        .rob_complete_prd       (alu_rob_complete_prd),
        .rob_complete_data      (alu_rob_complete_data),
        .rob_mispredict_valid   (alu_rob_mispredict_valid),
        .rob_mispredict_pc      (alu_rob_mispredict_pc),
        .bp_resolve_valid       (alu_bp_resolve_valid),
        .bp_resolve_pc          (alu_bp_resolve_pc),
        .bp_resolve_taken       (alu_bp_resolve_taken),
        .bp_resolve_target      (alu_bp_resolve_target),
        .bp_resolve_is_cond     (alu_bp_resolve_is_cond),
        .squash_valid           (squash_valid)
    );

    load_store_unit u_load_store_unit (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .lsu_issue_valid        (lsu_issue_valid),
        .lsu_issue_prs1         (lsu_issue_prs1),
        .lsu_issue_prs2         (lsu_issue_prs2),
        .lsu_issue_prd          (lsu_issue_prd),
        .lsu_issue_rob_idx      (lsu_issue_rob_idx),
        .lsu_issue_imm          (lsu_issue_imm),
        .lsu_issue_op_type      (lsu_issue_op_type),
        .lsu_issue_func3        (lsu_issue_func3),
        .lsu_issue_pc           (lsu_issue_pc),
        .prf_read1_addr         (lsu_prf_read1_addr),
        .prf_read1_data         (lsu_prf_read1_data),
        .prf_read2_addr         (lsu_prf_read2_addr),
        .prf_read2_data         (lsu_prf_read2_data),
        .prf_write_valid        (lsu_prf_write_valid),
        .prf_write_pr           (lsu_prf_write_pr),
        .prf_write_data         (lsu_prf_write_data),
        .dcache_cpu_req_valid   (lsu_dcache_cpu_req_valid),
        .dcache_cpu_req_we      (lsu_dcache_cpu_req_we),
        .dcache_cpu_req_addr    (lsu_dcache_cpu_req_addr),
        .dcache_cpu_req_wdata   (lsu_dcache_cpu_req_wdata),
        .dcache_cpu_req_be      (lsu_dcache_cpu_req_be),
        .dcache_cpu_req_ready   (lsu_dcache_cpu_req_ready),
        .dcache_cpu_resp_valid  (lsu_dcache_cpu_resp_valid),
        .dcache_cpu_resp_rdata  (lsu_dcache_cpu_resp_rdata),
        .dcache_flush           (lsu_dcache_flush),
        .dcache_flush_epoch     (lsu_dcache_flush_epoch),
        .rob_epoch              (rob_epoch),
        .rob_flush              (rob_flush),
        .rob_complete_valid     (lsu_rob_complete_valid),
        .rob_complete_rob_idx   (lsu_rob_complete_rob_idx),
        .rob_complete_prd       (lsu_rob_complete_prd),
        .rob_complete_data      (lsu_rob_complete_data),
        .squash_valid           (rob_lsu_squash_valid),
        .squash_rob_idx         (rob_lsu_squash_rob_idx),
        .dmem_waiting           (lsu_dmem_waiting)
    );

    reorder_buffer u_reorder_buffer (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .rob_alloc_req_valid        (rob_alloc_req_valid),
        .rob_alloc_req_pc           (rob_alloc_req_pc),
        .rob_alloc_req_insn         (rob_alloc_req_insn),
        .rob_alloc_req_prd          (rob_alloc_req_prd),
        .rob_alloc_req_old_prd      (rob_alloc_req_old_prd),
        .rob_alloc_grant            (rob_alloc_grant),
        .rob_alloc_idx              (rob_alloc_idx),
        .rob_full                   (),
        .rob_complete_valid_alu     (alu_rob_complete_valid),
        .rob_complete_rob_idx_alu   (alu_rob_complete_rob_idx),
        .rob_complete_prd_alu       (alu_rob_complete_prd),
        .rob_complete_data_alu      (alu_rob_complete_data),
        .rob_mispredict_valid       (alu_rob_mispredict_valid),
        .rob_mispredict_pc          (alu_rob_mispredict_pc),
        .rob_complete_valid_lsu     (lsu_rob_complete_valid),
        .rob_complete_rob_idx_lsu   (lsu_rob_complete_rob_idx),
        .rob_complete_prd_lsu       (lsu_rob_complete_prd),
        .rob_complete_data_lsu      (lsu_rob_complete_data),
        .rob_commit_valid           (rob_retire_valid),
        .rob_commit_arch_reg        (rob_retire_arch_reg),
        .rob_commit_phys_reg        (rob_retire_phys_reg),
        .rob_commit_old_phys_reg    (rob_retire_old_phys_reg),
        .rob_restore_valid          (rob_restore_valid),
        .rob_restore_checkpoint_id  (rob_restore_checkpoint_id),
        .rob_squash_valid           (rob_squash_valid),
        .rob_squash_rob_idx         (rob_squash_rob_idx),
        .rob_retire_valid           (rob_retire_valid),
        .rob_retire_pc              (rob_retire_pc),
        .rob_retire_insn            (rob_retire_insn),
        .rob_retire_is_ecall        (rob_retire_is_ecall),
        .rob_retire_exit_code       (rob_retire_exit_code),
        .rob_retire_store           (rob_retire_store),
        .rob_retire_load            (rob_retire_load),
        .rob_retire_branch          (rob_retire_branch),
        .rob_retire_jal             (rob_retire_jal),
        .rob_retire_jalr            (rob_retire_jalr),
        .rob_prf_commit_valid       (rob_prf_commit_valid),
        .rob_prf_commit_pr          (rob_prf_commit_pr),
        .rob_prf_commit_data        (rob_prf_commit_data),
        .rob_redirect_valid         (rob_redirect_valid),
        .rob_redirect_pc            (rob_redirect_pc),
        .rob_halt_valid             (rob_halt_valid),
        .rob_halt_exit_code         (rob_halt_exit_code),
        .rob_epoch                  (rob_epoch),
        .rob_flush                  (rob_flush),
        .rob_lsu_squash_valid       (rob_lsu_squash_valid),
        .rob_lsu_squash_rob_idx     (rob_lsu_squash_rob_idx),
        .rob_iq_squash_valid        (rob_iq_squash_valid),
        .rob_iq_squash_rob_idx      (rob_iq_squash_rob_idx),
        .rob_ren_squash_valid       (rob_ren_squash_valid),
        .rob_ren_squash_rob_idx     (rob_ren_squash_rob_idx),
        .rob_fetch_squash_valid     (rob_fetch_squash_valid),
        .rob_fetch_squash_rob_idx   (rob_fetch_squash_rob_idx),
        .rob_bp_resolve_valid       (rob_bp_resolve_valid),
        .rob_bp_resolve_pc          (rob_bp_resolve_pc),
        .rob_bp_resolve_taken       (rob_bp_resolve_taken),
        .rob_bp_resolve_target      (rob_bp_resolve_target),
        .rob_bp_resolve_is_cond     (rob_bp_resolve_is_cond),
        .dmem_waiting               (lsu_dmem_waiting),
        .dbg_ooo_bypass             (rob_dbg_ooo_bypass)
    );

    prf u_prf (
        .clk                (clk),
        .rst_n              (rst_n),
        .alu_read1_addr     (alu_prf_read1_addr),
        .alu_read1_data     (alu_prf_read1_data),
        .alu_read2_addr     (alu_prf_read2_addr),
        .alu_read2_data     (alu_prf_read2_data),
        .lsu_read1_addr     (lsu_prf_read1_addr),
        .lsu_read1_data     (lsu_prf_read1_data),
        .lsu_read2_addr     (lsu_prf_read2_addr),
        .lsu_read2_data     (lsu_prf_read2_data),
        .write_valid_alu    (alu_prf_write_valid),
        .write_pr_alu       (alu_prf_write_pr),
        .write_data_alu     (alu_prf_write_data),
        .write_valid_lsu    (lsu_prf_write_valid),
        .write_pr_lsu       (lsu_prf_write_pr),
        .write_data_lsu     (lsu_prf_write_data)
    );

    icache u_icache (
        .clk                (clk),
        .rst_n              (rst_n),
        .cpu_req_valid      (fetch_icache_cpu_req_valid),
        .cpu_req_addr       (fetch_icache_cpu_req_addr),
        .cpu_req_ready      (fetch_icache_cpu_req_ready),
        .cpu_resp_valid     (fetch_icache_cpu_resp_valid),
        .cpu_resp_data      (fetch_icache_cpu_resp_data),
        .flush              (fetch_icache_flush),
        .flush_epoch        (fetch_icache_flush_epoch),
        .mem_req_valid      (imem_valid),
        .mem_req_ready      (imem_ready),
        .mem_req_addr       (imem_addr),
        .mem_resp_valid     (1'b0),
        .mem_resp_data      (imem_rdata)
    );

    dcache u_dcache (
        .clk                (clk),
        .rst_n              (rst_n),
        .cpu_req_valid      (lsu_dcache_cpu_req_valid),
        .cpu_req_we         (lsu_dcache_cpu_req_we),
        .cpu_req_addr       (lsu_dcache_cpu_req_addr),
        .cpu_req_wdata      (lsu_dcache_cpu_req_wdata),
        .cpu_req_be         (lsu_dcache_cpu_req_be),
        .cpu_req_ready      (lsu_dcache_cpu_req_ready),
        .cpu_resp_valid     (lsu_dcache_cpu_resp_valid),
        .cpu_resp_rdata     (lsu_dcache_cpu_resp_rdata),
        .flush              (lsu_dcache_flush),
        .flush_epoch        (lsu_dcache_flush_epoch),
        .mem_req_valid      (dmem_valid),
        .mem_req_ready      (dmem_ready),
        .mem_req_addr       (dmem_addr),
        .mem_req_we         (dmem_we),
        .mem_req_wdata      (dmem_wdata),
        .mem_req_be         (dmem_be),
        .mem_resp_valid     (1'b0),
        .mem_resp_data      (dmem_rdata)
    );

    branch_predictor u_branch_predictor (
        .clk                (clk),
        .rst_n              (rst_n),
        .pc_query           (fetch_branch_pred_pc_query),
        .pred_valid         (fetch_branch_pred_valid),
        .pred_taken         (fetch_branch_pred_taken),
        .pred_target        (fetch_branch_pred_target),
        .resolve_valid      (rob_bp_resolve_valid),
        .resolve_pc         (rob_bp_resolve_pc),
        .resolve_taken      (rob_bp_resolve_taken),
        .resolve_target     (rob_bp_resolve_target),
        .resolve_is_cond    (rob_bp_resolve_is_cond)
    );

    // ============================================================
    // Top-level glue logic
    // ============================================================

    // Redirect from ROB
    assign redirect_valid = rob_redirect_valid;
    assign redirect_pc    = rob_redirect_pc;

    // Halt request from ROB
    assign halt_request = rob_halt_valid;

    // Squash valid for ALU
    assign squash_valid = rob_squash_valid;

    // Debug features
    assign dbg_features = 3'b111;

    // Debug register read (committed architectural state)
    // We use the PRF committed values via ROB retire interface
    // For simplicity, we maintain a committed register file in the top level
    logic [31:0] committed_regs [0:31];
    logic [31:0] committed_regs_next [0:31];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) begin
                committed_regs[i] <= 32'b0;
            end
        end else begin
            for (int i = 0; i < 32; i++) begin
                committed_regs[i] <= committed_regs_next[i];
            end
        end
    end

    always_comb begin
        for (int i = 0; i < 32; i++) begin
            committed_regs_next[i] = committed_regs[i];
        end
        if (rob_retire_valid && rob_retire_arch_reg != 5'b0) begin
            committed_regs_next[rob_retire_arch_reg] = rob_prf_commit_data;
        end
    end

    assign dbg_reg_data = committed_regs[dbg_reg_addr];

    // Halted and exit code
    logic halted_reg;
    logic [31:0] exit_code_reg;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halted_reg <= 1'b0;
            exit_code_reg <= 32'b0;
        end else if (rob_halt_valid) begin
            halted_reg <= 1'b1;
            exit_code_reg <= rob_halt_exit_code;
        end
    end

    assign halted    = halted_reg;
    assign exit_code = exit_code_reg;

    // Debug retire
    assign dbg_retire_valid = rob_retire_valid;
    assign dbg_retire_pc    = rob_retire_pc;
    assign dbg_retire_insn  = rob_retire_insn;

    // Debug branch resolve
    assign dbg_bp_resolve    = rob_bp_resolve_valid;
    assign dbg_bp_mispredict = rob_bp_resolve_valid && (rob_bp_resolve_taken != fetch_branch_pred_taken || rob_bp_resolve_target != fetch_branch_pred_target);

    // Debug OOO
    assign dbg_ooo_issue  = iq_dbg_ooo_issue;
    assign dbg_ooo_bypass = rob_dbg_ooo_bypass;

    // Decode ready from rename
    assign decode_ready = ren_ready;

endmodule
