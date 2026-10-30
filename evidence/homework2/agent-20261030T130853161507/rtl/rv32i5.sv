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

    // =========================================================================
    // Internal signals
    // =========================================================================

    // IF stage <-> ICache
    logic        if_cpu_req_valid;
    logic [31:0] if_cpu_req_addr;
    logic        if_cpu_req_ready;
    logic        if_cpu_resp_valid;
    logic [31:0] if_cpu_resp_data;

    // IF stage <-> Branch predictor
    logic [31:0] if_pc_query;
    logic        pred_pc_valid;
    logic [31:0] pred_pc;

    // IF stage <-> ID stage
    logic        if_id_valid;
    logic [31:0] if_id_pc;
    logic [31:0] if_id_insn;
    logic [1:0]  if_id_epoch;

    // IF stage control
    logic        if_redirect_valid;
    logic [31:0] if_redirect_pc;
    logic        if_stall;
    logic        if_ecall_halt_pending;

    // ID stage <-> Regfile
    logic [4:0]  id_read_addr1;
    logic [4:0]  id_read_addr2;
    logic [31:0] id_read_data1;
    logic [31:0] id_read_data2;

    // ID stage <-> EX stage
    logic        id_ex_valid;
    logic [31:0] id_ex_pc;
    logic [31:0] id_ex_insn;
    logic [31:0] id_ex_rs1_val;
    logic [31:0] id_ex_rs2_val;
    logic [4:0]  id_ex_rs1_addr;
    logic [4:0]  id_ex_rs2_addr;
    logic [31:0] id_ex_imm;
    logic [4:0]  id_ex_rd_addr;
    logic [3:0]  id_ex_alu_op;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic        id_ex_reg_write;
    logic        id_ex_branch;
    logic        id_ex_jal;
    logic        id_ex_jalr;
    logic        id_ex_ecall;
    logic [1:0]  id_ex_epoch;
    logic [31:0] id_ex_pc_plus4;
    logic [1:0]  id_ex_funct3;
    logic        id_ex_opcode;

    // ID stage control
    logic        id_flush_id_ex;
    logic        id_redirect_valid;

    // Hazard unit
    logic        hazard_stall;

    // Forwarding unit
    logic [1:0]  forward_a;
    logic [1:0]  forward_b;

    // EX stage <-> MEM stage
    logic        ex_mem_valid;
    logic [31:0] ex_mem_pc;
    logic [31:0] ex_mem_insn;
    logic [31:0] ex_mem_pc_plus4;
    logic [31:0] ex_mem_alu_result;
    logic [31:0] ex_mem_rs2_val;
    logic [4:0]  ex_mem_rd_addr;
    logic        ex_mem_reg_write;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic        ex_mem_ecall;
    logic [1:0]  ex_mem_epoch;

    // EX stage <-> Branch predictor update
    logic        bp_update_valid;
    logic [31:0] bp_update_pc;
    logic        bp_update_taken;
    logic [31:0] bp_update_target;
    logic        bp_update_is_branch;
    logic        bp_update_is_jal;
    logic        bp_update_is_jalr;
    logic [1:0]  bp_update_epoch;

    // EX stage debug
    logic        ex_dbg_bp_resolve;
    logic        ex_dbg_bp_mispredict;

    // MEM stage <-> DCache
    logic        mem_cpu_req_valid;
    logic        mem_cpu_req_we;
    logic [31:0] mem_cpu_req_addr;
    logic [31:0] mem_cpu_req_wdata;
    logic [3:0]  mem_cpu_req_be;
    logic        mem_cpu_req_ready;
    logic        mem_cpu_resp_valid;
    logic [31:0] mem_cpu_resp_rdata;

    // MEM stage <-> WB stage
    logic        mem_wb_valid;
    logic [31:0] mem_wb_pc;
    logic [31:0] mem_wb_insn;
    logic [31:0] mem_wb_pc_plus4;
    logic [31:0] mem_wb_alu_result;
    logic [31:0] mem_wb_load_data;
    logic [4:0]  mem_wb_rd_addr;
    logic        mem_wb_reg_write;
    logic        mem_wb_ecall;
    logic [1:0]  mem_wb_epoch;

    // MEM stage forwarding outputs
    logic        mem_ex_mem_valid_out;
    logic        mem_ex_mem_reg_write_out;
    logic [4:0]  mem_ex_mem_rd_addr_out;
    logic [31:0] mem_ex_mem_alu_result_out;

    // WB stage <-> Regfile
    logic        wb_regfile_write_en;
    logic [4:0]  wb_regfile_write_addr;
    logic [31:0] wb_regfile_write_data;

    // WB stage forwarding outputs
    logic        wb_mem_wb_valid_out;
    logic        wb_mem_wb_reg_write_out;
    logic [4:0]  wb_mem_wb_rd_addr_out;
    logic [31:0] wb_mem_wb_wb_data_out;

    // ICache <-> external memory
    logic        icache_mem_req_valid;
    logic        icache_mem_req_ready;
    logic [31:0] icache_mem_req_addr;
    logic        icache_mem_resp_valid;
    logic [31:0] icache_mem_resp_data;

    // DCache <-> external memory
    logic        dcache_mem_req_valid;
    logic        dcache_mem_req_ready;
    logic [31:0] dcache_mem_req_addr;
    logic        dcache_mem_req_we;
    logic [31:0] dcache_mem_req_wdata;
    logic [3:0]  dcache_mem_req_be;
    logic        dcache_mem_resp_valid;
    logic [31:0] dcache_mem_resp_data;

    // Flush epoch
    logic [1:0]  flush_epoch;
    logic        flush_signal;

    // =========================================================================
    // Constant assignments
    // =========================================================================
    assign dbg_features = 3'b011;
    assign dbg_ooo_issue = 1'b0;
    assign dbg_ooo_bypass = 1'b0;

    // =========================================================================
    // IF stage
    // =========================================================================
    if_stage u_if_stage (
        .clk                (clk),
        .rst_n              (rst_n),
        .cpu_resp_valid     (if_cpu_resp_valid),
        .cpu_resp_data      (if_cpu_resp_data),
        .cpu_req_ready      (if_cpu_req_ready),
        .redirect_valid     (if_redirect_valid),
        .redirect_pc        (if_redirect_pc),
        .stall              (if_stall),
        .pred_pc_valid      (pred_pc_valid),
        .pred_pc            (pred_pc),
        .ecall_halt_pending (if_ecall_halt_pending),
        .cpu_req_valid      (if_cpu_req_valid),
        .cpu_req_addr       (if_cpu_req_addr),
        .if_id_valid        (if_id_valid),
        .if_id_pc           (if_id_pc),
        .if_id_insn         (if_id_insn),
        .flush_epoch        (flush_epoch),
        .pc_query           (if_pc_query)
    );

    // =========================================================================
    // ICache
    // =========================================================================
    icache u_icache (
        .clk            (clk),
        .rst_n          (rst_n),
        .cpu_req_valid  (if_cpu_req_valid),
        .cpu_req_addr   (if_cpu_req_addr),
        .cpu_req_ready  (if_cpu_req_ready),
        .cpu_resp_valid (if_cpu_resp_valid),
        .cpu_resp_data  (if_cpu_resp_data),
        .flush          (flush_signal),
        .flush_epoch    (flush_epoch),
        .mem_req_valid  (icache_mem_req_valid),
        .mem_req_ready  (icache_mem_req_ready),
        .mem_req_addr   (icache_mem_req_addr),
        .mem_resp_valid (icache_mem_resp_valid),
        .mem_resp_data  (icache_mem_resp_data)
    );

    // =========================================================================
    // Branch predictor
    // =========================================================================
    branch_predictor u_branch_predictor (
        .clk             (clk),
        .rst_n           (rst_n),
        .pc_query        (if_pc_query),
        .pred_pc_valid   (pred_pc_valid),
        .pred_pc         (pred_pc),
        .update_valid    (bp_update_valid),
        .update_pc       (bp_update_pc),
        .update_taken    (bp_update_taken),
        .update_target   (bp_update_target),
        .update_is_branch(bp_update_is_branch),
        .update_is_jal   (bp_update_is_jal),
        .update_is_jalr  (bp_update_is_jalr),
        .update_epoch    (bp_update_epoch)
    );

    // =========================================================================
    // ID stage
    // =========================================================================
    id_stage u_id_stage (
        .clk                (clk),
        .rst_n              (rst_n),
        .if_id_valid        (if_id_valid),
        .if_id_pc           (if_id_pc),
        .if_id_insn         (if_id_insn),
        .if_id_epoch        (if_id_epoch),
        .read_data1         (id_read_data1),
        .read_data2         (id_read_data2),
        .stall              (hazard_stall),
        .flush_id_ex        (id_flush_id_ex),
        .redirect_valid     (id_redirect_valid),
        .read_addr1         (id_read_addr1),
        .read_addr2         (id_read_addr2),
        .ecall_halt_pending (if_ecall_halt_pending),
        .id_ex_valid        (id_ex_valid),
        .id_ex_pc           (id_ex_pc),
        .id_ex_insn         (id_ex_insn),
        .id_ex_rs1_val      (id_ex_rs1_val),
        .id_ex_rs2_val      (id_ex_rs2_val),
        .id_ex_rs1_addr     (id_ex_rs1_addr),
        .id_ex_rs2_addr     (id_ex_rs2_addr),
        .id_ex_imm          (id_ex_imm),
        .id_ex_rd_addr      (id_ex_rd_addr),
        .id_ex_alu_op       (id_ex_alu_op),
        .id_ex_mem_read     (id_ex_mem_read),
        .id_ex_mem_write    (id_ex_mem_write),
        .id_ex_reg_write    (id_ex_reg_write),
        .id_ex_branch       (id_ex_branch),
        .id_ex_jal          (id_ex_jal),
        .id_ex_jalr         (id_ex_jalr),
        .id_ex_ecall        (id_ex_ecall),
        .id_ex_epoch        (id_ex_epoch),
        .id_ex_pc_plus4     (id_ex_pc_plus4),
        .id_ex_funct3       (id_ex_funct3),
        .id_ex_opcode       (id_ex_opcode)
    );

    // =========================================================================
    // Regfile
    // =========================================================================
    regfile u_regfile (
        .clk          (clk),
        .rst_n        (rst_n),
        .write_en     (wb_regfile_write_en),
        .write_addr   (wb_regfile_write_addr),
        .write_data   (wb_regfile_write_data),
        .read_addr1   (id_read_addr1),
        .read_addr2   (id_read_addr2),
        .dbg_reg_addr (dbg_reg_addr),
        .read_data1   (id_read_data1),
        .read_data2   (id_read_data2),
        .dbg_reg_data (dbg_reg_data)
    );

    // =========================================================================
    // Hazard unit
    // =========================================================================
    hazard_unit u_hazard_unit (
        .id_rs1_addr (id_read_addr1),
        .id_rs2_addr (id_read_addr2),
        .id_valid    (if_id_valid),
        .ex_rd_addr  (id_ex_rd_addr),
        .ex_reg_write(id_ex_reg_write),
        .ex_mem_read (id_ex_mem_read),
        .stall       (hazard_stall)
    );

    // =========================================================================
    // Forwarding unit
    // =========================================================================
    forwarding_unit u_forwarding_unit (
        .id_ex_rs1_addr   (id_ex_rs1_addr),
        .id_ex_rs2_addr   (id_ex_rs2_addr),
        .ex_mem_valid     (mem_ex_mem_valid_out),
        .ex_mem_reg_write (mem_ex_mem_reg_write_out),
        .ex_mem_rd_addr   (mem_ex_mem_rd_addr_out),
        .mem_wb_valid     (wb_mem_wb_valid_out),
        .mem_wb_reg_write (wb_mem_wb_reg_write_out),
        .mem_wb_rd_addr   (wb_mem_wb_rd_addr_out),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    // =========================================================================
    // EX stage
    // =========================================================================
    ex_stage u_ex_stage (
        .clk                (clk),
        .rst_n              (rst_n),
        .id_ex_valid        (id_ex_valid),
        .id_ex_pc           (id_ex_pc),
        .id_ex_insn         (id_ex_insn),
        .id_ex_rs1_val      (id_ex_rs1_val),
        .id_ex_rs2_val      (id_ex_rs2_val),
        .id_ex_rs1_addr     (id_ex_rs1_addr),
        .id_ex_rs2_addr     (id_ex_rs2_addr),
        .id_ex_imm          (id_ex_imm),
        .id_ex_rd_addr      (id_ex_rd_addr),
        .id_ex_alu_op       (id_ex_alu_op),
        .id_ex_mem_read     (id_ex_mem_read),
        .id_ex_mem_write    (id_ex_mem_write),
        .id_ex_reg_write    (id_ex_reg_write),
        .id_ex_branch       (id_ex_branch),
        .id_ex_jal          (id_ex_jal),
        .id_ex_jalr         (id_ex_jalr),
        .id_ex_ecall        (id_ex_ecall),
        .id_ex_epoch        (id_ex_epoch),
        .id_ex_pc_plus4     (id_ex_pc_plus4),
        .id_ex_funct3       (id_ex_funct3),
        .id_ex_opcode       (id_ex_opcode),
        .forward_a          (forward_a),
        .forward_b          (forward_b),
        .ex_mem_fwd_valid       (mem_ex_mem_valid_out),
        .ex_mem_fwd_reg_write   (mem_ex_mem_reg_write_out),
        .ex_mem_fwd_rd_addr     (mem_ex_mem_rd_addr_out),
        .ex_mem_fwd_alu_result  (mem_ex_mem_alu_result_out),
        .mem_wb_valid       (wb_mem_wb_valid_out),
        .mem_wb_reg_write   (wb_mem_wb_reg_write_out),
        .mem_wb_rd_addr     (wb_mem_wb_rd_addr_out),
        .mem_wb_wb_data     (wb_mem_wb_wb_data_out),
        .ex_mem_valid       (ex_mem_valid),
        .ex_mem_pc          (ex_mem_pc),
        .ex_mem_insn        (ex_mem_insn),
        .ex_mem_pc_plus4    (ex_mem_pc_plus4),
        .ex_mem_alu_result  (ex_mem_alu_result),
        .ex_mem_rs2_val     (ex_mem_rs2_val),
        .ex_mem_rd_addr     (ex_mem_rd_addr),
        .ex_mem_reg_write   (ex_mem_reg_write),
        .ex_mem_mem_read    (ex_mem_mem_read),
        .ex_mem_mem_write   (ex_mem_mem_write),
        .ex_mem_ecall       (ex_mem_ecall),
        .ex_mem_epoch       (ex_mem_epoch),
        .redirect_valid     (if_redirect_valid),
        .redirect_pc        (if_redirect_pc),
        .update_valid       (bp_update_valid),
        .update_pc          (bp_update_pc),
        .update_taken       (bp_update_taken),
        .update_target      (bp_update_target),
        .update_is_branch   (bp_update_is_branch),
        .update_is_jal      (bp_update_is_jal),
        .update_is_jalr     (bp_update_is_jalr),
        .update_epoch       (bp_update_epoch),
        .dbg_bp_resolve     (ex_dbg_bp_resolve),
        .dbg_bp_mispredict  (ex_dbg_bp_mispredict)
    );

    // =========================================================================
    // MEM stage
    // =========================================================================
    mem_stage u_mem_stage (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .ex_mem_valid           (ex_mem_valid),
        .ex_mem_pc              (ex_mem_pc),
        .ex_mem_insn            (ex_mem_insn),
        .ex_mem_pc_plus4        (ex_mem_pc_plus4),
        .ex_mem_alu_result      (ex_mem_alu_result),
        .ex_mem_rs2_val         (ex_mem_rs2_val),
        .ex_mem_rd_addr         (ex_mem_rd_addr),
        .ex_mem_reg_write       (ex_mem_reg_write),
        .ex_mem_mem_read        (ex_mem_mem_read),
        .ex_mem_mem_write       (ex_mem_mem_write),
        .ex_mem_ecall           (ex_mem_ecall),
        .ex_mem_epoch           (ex_mem_epoch),
        .cpu_resp_valid         (mem_cpu_resp_valid),
        .cpu_resp_rdata         (mem_cpu_resp_rdata),
        .cpu_req_ready          (mem_cpu_req_ready),
        .cpu_req_valid          (mem_cpu_req_valid),
        .cpu_req_we             (mem_cpu_req_we),
        .cpu_req_addr           (mem_cpu_req_addr),
        .cpu_req_wdata          (mem_cpu_req_wdata),
        .cpu_req_be             (mem_cpu_req_be),
        .mem_wb_valid           (mem_wb_valid),
        .mem_wb_pc              (mem_wb_pc),
        .mem_wb_insn            (mem_wb_insn),
        .mem_wb_pc_plus4        (mem_wb_pc_plus4),
        .mem_wb_alu_result      (mem_wb_alu_result),
        .mem_wb_load_data       (mem_wb_load_data),
        .mem_wb_rd_addr         (mem_wb_rd_addr),
        .mem_wb_reg_write       (mem_wb_reg_write),
        .mem_wb_ecall           (mem_wb_ecall),
        .mem_wb_epoch           (mem_wb_epoch),
        .ex_mem_valid_out       (mem_ex_mem_valid_out),
        .ex_mem_reg_write_out   (mem_ex_mem_reg_write_out),
        .ex_mem_rd_addr_out     (mem_ex_mem_rd_addr_out),
        .ex_mem_alu_result_out  (mem_ex_mem_alu_result_out)
    );

    // =========================================================================
    // DCache
    // =========================================================================
    dcache u_dcache (
        .clk            (clk),
        .rst_n          (rst_n),
        .cpu_req_valid  (mem_cpu_req_valid),
        .cpu_req_we     (mem_cpu_req_we),
        .cpu_req_addr   (mem_cpu_req_addr),
        .cpu_req_wdata  (mem_cpu_req_wdata),
        .cpu_req_be     (mem_cpu_req_be),
        .cpu_req_ready  (mem_cpu_req_ready),
        .cpu_resp_valid (mem_cpu_resp_valid),
        .cpu_resp_rdata (mem_cpu_resp_rdata),
        .flush          (flush_signal),
        .flush_epoch    (flush_epoch),
        .mem_req_valid  (dcache_mem_req_valid),
        .mem_req_ready  (dcache_mem_req_ready),
        .mem_req_addr   (dcache_mem_req_addr),
        .mem_req_we     (dcache_mem_req_we),
        .mem_req_wdata  (dcache_mem_req_wdata),
        .mem_req_be     (dcache_mem_req_be),
        .mem_resp_valid (dcache_mem_resp_valid),
        .mem_resp_data  (dcache_mem_resp_data)
    );

    // =========================================================================
    // WB stage
    // =========================================================================
    wb_stage u_wb_stage (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .mem_wb_valid           (mem_wb_valid),
        .mem_wb_pc              (mem_wb_pc),
        .mem_wb_insn            (mem_wb_insn),
        .mem_wb_pc_plus4        (mem_wb_pc_plus4),
        .mem_wb_alu_result      (mem_wb_alu_result),
        .mem_wb_load_data       (mem_wb_load_data),
        .mem_wb_rd_addr         (mem_wb_rd_addr),
        .mem_wb_reg_write       (mem_wb_reg_write),
        .mem_wb_ecall           (mem_wb_ecall),
        .mem_wb_epoch           (mem_wb_epoch),
        .regfile_write_en       (wb_regfile_write_en),
        .regfile_write_addr     (wb_regfile_write_addr),
        .regfile_write_data     (wb_regfile_write_data),
        .mem_wb_valid_out       (wb_mem_wb_valid_out),
        .mem_wb_reg_write_out   (wb_mem_wb_reg_write_out),
        .mem_wb_rd_addr_out     (wb_mem_wb_rd_addr_out),
        .mem_wb_wb_data_out     (wb_mem_wb_wb_data_out),
        .dbg_retire_valid       (dbg_retire_valid),
        .dbg_retire_pc          (dbg_retire_pc),
        .dbg_retire_insn        (dbg_retire_insn),
        .halted                 (halted),
        .exit_code              (exit_code)
    );

    // =========================================================================
    // External memory connections
    // =========================================================================
    assign imem_valid = icache_mem_req_valid;
    assign imem_addr  = icache_mem_req_addr;
    assign icache_mem_req_ready = imem_ready;
    assign icache_mem_resp_valid = imem_valid && imem_ready;
    assign icache_mem_resp_data  = imem_rdata;

    assign dmem_valid = dcache_mem_req_valid;
    assign dmem_we    = dcache_mem_req_we;
    assign dmem_addr  = dcache_mem_req_addr;
    assign dmem_wdata = dcache_mem_req_wdata;
    assign dmem_be    = dcache_mem_req_be;
    assign dcache_mem_req_ready = dmem_ready;
    assign dcache_mem_resp_valid = dmem_valid && dmem_ready;
    assign dcache_mem_resp_data  = dmem_rdata;

    // =========================================================================
    // Flush signal generation
    // =========================================================================
    assign flush_signal = if_redirect_valid || if_ecall_halt_pending;

    // =========================================================================
    // Stall and flush connections
    // =========================================================================
    assign if_stall = hazard_stall;
    assign id_flush_id_ex = if_redirect_valid;
    assign id_redirect_valid = if_redirect_valid;

    // =========================================================================
    // Debug signals
    // =========================================================================
    assign dbg_bp_resolve    = ex_dbg_bp_resolve;
    assign dbg_bp_mispredict = ex_dbg_bp_mispredict;

endmodule
