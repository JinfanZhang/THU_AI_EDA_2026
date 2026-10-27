module rv32i5 (
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    output logic        dmem_valid,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_be,
    input  logic [31:0] dmem_rdata,
    input  logic [4:0]  dbg_reg_addr,
    output logic [31:0] dbg_reg_data,
    output logic        halted,
    output logic [31:0] exit_code
);

    // IF <-> ID
    logic        if_valid;
    logic [31:0] if_pc;
    logic [31:0] if_pc4;
    logic [31:0] if_instr;

    // ID <-> EX
    logic        id_valid;
    logic [4:0]  id_rs1;
    logic [4:0]  id_rs2;
    logic        id_uses_rs1;
    logic        id_uses_rs2;
    logic        id_ecall;
    logic        id_ex_valid;
    logic [31:0] id_ex_pc;
    logic [31:0] id_ex_pc4;
    logic [31:0] id_ex_instr;
    logic [31:0] id_ex_rs1_data;
    logic [31:0] id_ex_rs2_data;
    logic [4:0]  id_ex_rs1;
    logic [4:0]  id_ex_rs2;
    logic [4:0]  id_ex_rd;
    logic [31:0] id_ex_imm;
    logic [3:0]  id_ex_alu_op;
    logic [1:0]  id_ex_alu_a_sel;
    logic        id_ex_alu_b_sel;
    logic        id_ex_reg_write;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic [2:0]  id_ex_mem_size;
    logic [1:0]  id_ex_wb_sel;
    logic [3:0]  id_ex_branch;
    logic [1:0]  id_ex_jump;
    logic        id_ex_is_ecall;

    // EX <-> MEM
    logic        ex_mem_valid;
    logic [31:0] ex_mem_pc4;
    logic [4:0]  ex_mem_rd;
    logic [31:0] ex_mem_alu_result;
    logic [31:0] ex_mem_rs2_data;
    logic [4:0]  ex_mem_rs2;
    logic        ex_mem_reg_write;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic [2:0]  ex_mem_mem_size;
    logic [1:0]  ex_mem_wb_sel;
    logic        ex_mem_is_ecall;

    // EX control
    logic        ex_redirect;
    logic [31:0] ex_redirect_target;

    // MEM <-> WB
    logic        mem_wb_valid;
    logic        mem_wb_reg_write;
    logic [4:0]  mem_wb_rd;
    logic [1:0]  mem_wb_wb_sel;
    logic [31:0] mem_wb_alu_result;
    logic [31:0] mem_wb_pc4;
    logic [31:0] mem_wb_load_data;
    logic        mem_wb_is_ecall;

    // WB
    logic        wb_we;
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;

    // Hazard
    logic        stall;
    logic        flush_if_id;
    logic        flush_id_ex;
    logic        halt_pending;

    // Forwarding
    logic [1:0]  fwd_a_sel;
    logic [1:0]  fwd_b_sel;

    // x10
    logic [31:0] x10_data;

    if_stage u_if (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (stall),
        .flush           (flush_if_id),
        .redirect        (ex_redirect),
        .redirect_target (ex_redirect_target),
        .imem_rdata      (imem_rdata),
        .imem_addr       (imem_addr),
        .if_valid        (if_valid),
        .if_pc           (if_pc),
        .if_pc4          (if_pc4),
        .if_instr        (if_instr)
    );

    id_stage u_id (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (flush_id_ex),
        .if_valid        (if_valid),
        .if_pc           (if_pc),
        .if_pc4          (if_pc4),
        .if_instr        (if_instr),
        .wb_we           (wb_we),
        .wb_rd           (wb_rd),
        .wb_data         (wb_data),
        .dbg_reg_addr    (dbg_reg_addr),
        .dbg_reg_data    (dbg_reg_data),
        .x10_data        (x10_data),
        .id_valid        (id_valid),
        .id_rs1          (id_rs1),
        .id_rs2          (id_rs2),
        .id_uses_rs1     (id_uses_rs1),
        .id_uses_rs2     (id_uses_rs2),
        .id_ecall        (id_ecall),
        .id_ex_valid     (id_ex_valid),
        .id_ex_pc        (id_ex_pc),
        .id_ex_pc4       (id_ex_pc4),
        .id_ex_instr     (id_ex_instr),
        .id_ex_rs1_data  (id_ex_rs1_data),
        .id_ex_rs2_data  (id_ex_rs2_data),
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .id_ex_rd        (id_ex_rd),
        .id_ex_imm       (id_ex_imm),
        .id_ex_alu_op    (id_ex_alu_op),
        .id_ex_alu_a_sel (id_ex_alu_a_sel),
        .id_ex_alu_b_sel (id_ex_alu_b_sel),
        .id_ex_reg_write (id_ex_reg_write),
        .id_ex_mem_read  (id_ex_mem_read),
        .id_ex_mem_write (id_ex_mem_write),
        .id_ex_mem_size  (id_ex_mem_size),
        .id_ex_wb_sel    (id_ex_wb_sel),
        .id_ex_branch    (id_ex_branch),
        .id_ex_jump      (id_ex_jump),
        .id_ex_is_ecall  (id_ex_is_ecall)
    );

    ex_stage u_ex (
        .clk              (clk),
        .rst_n            (rst_n),
        .fwd_a_sel        (fwd_a_sel),
        .fwd_b_sel        (fwd_b_sel),
        .wb_data          (wb_data),
        .id_ex_valid      (id_ex_valid),
        .id_ex_pc         (id_ex_pc),
        .id_ex_pc4        (id_ex_pc4),
        .id_ex_instr      (id_ex_instr),
        .id_ex_rs1_data   (id_ex_rs1_data),
        .id_ex_rs2_data   (id_ex_rs2_data),
        .id_ex_rs1        (id_ex_rs1),
        .id_ex_rs2        (id_ex_rs2),
        .id_ex_rd         (id_ex_rd),
        .id_ex_imm        (id_ex_imm),
        .id_ex_alu_op     (id_ex_alu_op),
        .id_ex_alu_a_sel  (id_ex_alu_a_sel),
        .id_ex_alu_b_sel  (id_ex_alu_b_sel),
        .id_ex_reg_write  (id_ex_reg_write),
        .id_ex_mem_read   (id_ex_mem_read),
        .id_ex_mem_write  (id_ex_mem_write),
        .id_ex_mem_size   (id_ex_mem_size),
        .id_ex_wb_sel     (id_ex_wb_sel),
        .id_ex_branch     (id_ex_branch),
        .id_ex_jump       (id_ex_jump),
        .id_ex_is_ecall   (id_ex_is_ecall),
        .ex_mem_valid     (ex_mem_valid),
        .ex_mem_pc4       (ex_mem_pc4),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_alu_result(ex_mem_alu_result),
        .ex_mem_rs2_data  (ex_mem_rs2_data),
        .ex_mem_rs2       (ex_mem_rs2),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read  (ex_mem_mem_read),
        .ex_mem_mem_write (ex_mem_mem_write),
        .ex_mem_mem_size  (ex_mem_mem_size),
        .ex_mem_wb_sel    (ex_mem_wb_sel),
        .ex_mem_is_ecall  (ex_mem_is_ecall),
        .redirect         (ex_redirect),
        .redirect_target  (ex_redirect_target)
    );

    mem_stage u_mem (
        .clk              (clk),
        .rst_n            (rst_n),
        .halted           (halted),
        .dmem_rdata       (dmem_rdata),
        .wb_we            (wb_we),
        .wb_rd            (wb_rd),
        .wb_data          (wb_data),
        .ex_mem_valid     (ex_mem_valid),
        .ex_mem_pc4       (ex_mem_pc4),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_alu_result(ex_mem_alu_result),
        .ex_mem_rs2_data  (ex_mem_rs2_data),
        .ex_mem_rs2       (ex_mem_rs2),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read  (ex_mem_mem_read),
        .ex_mem_mem_write (ex_mem_mem_write),
        .ex_mem_mem_size  (ex_mem_mem_size),
        .ex_mem_wb_sel    (ex_mem_wb_sel),
        .ex_mem_is_ecall  (ex_mem_is_ecall),
        .dmem_valid       (dmem_valid),
        .dmem_we          (dmem_we),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_be          (dmem_be),
        .mem_wb_valid     (mem_wb_valid),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_wb_sel    (mem_wb_wb_sel),
        .mem_wb_alu_result(mem_wb_alu_result),
        .mem_wb_pc4       (mem_wb_pc4),
        .mem_wb_load_data (mem_wb_load_data),
        .mem_wb_is_ecall  (mem_wb_is_ecall)
    );

    wb_stage u_wb (
        .clk              (clk),
        .rst_n            (rst_n),
        .x10_data         (x10_data),
        .mem_wb_valid     (mem_wb_valid),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_wb_sel    (mem_wb_wb_sel),
        .mem_wb_alu_result(mem_wb_alu_result),
        .mem_wb_pc4       (mem_wb_pc4),
        .mem_wb_load_data (mem_wb_load_data),
        .mem_wb_is_ecall  (mem_wb_is_ecall),
        .wb_we            (wb_we),
        .wb_rd            (wb_rd),
        .wb_data          (wb_data),
        .halted           (halted),
        .exit_code        (exit_code)
    );

    hazard_unit u_hazard (
        .clk          (clk),
        .rst_n        (rst_n),
        .id_valid     (id_valid),
        .id_ecall     (id_ecall),
        .id_uses_rs1  (id_uses_rs1),
        .id_uses_rs2  (id_uses_rs2),
        .id_rs1       (id_rs1),
        .id_rs2       (id_rs2),
        .ex_valid     (id_ex_valid),
        .ex_mem_read  (id_ex_mem_read),
        .ex_rd        (id_ex_rd),
        .redirect     (ex_redirect),
        .halted       (halted),
        .stall        (stall),
        .flush_if_id  (flush_if_id),
        .flush_id_ex  (flush_id_ex),
        .halt_pending (halt_pending)
    );

    forwarding_unit u_fwd (
        .ex_mem_valid     (ex_mem_valid),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read  (ex_mem_mem_read),
        .ex_mem_rd        (ex_mem_rd),
        .wb_we            (wb_we),
        .wb_rd            (wb_rd),
        .id_ex_rs1        (id_ex_rs1),
        .id_ex_rs2        (id_ex_rs2),
        .fwd_a_sel        (fwd_a_sel),
        .fwd_b_sel        (fwd_b_sel)
    );

endmodule
