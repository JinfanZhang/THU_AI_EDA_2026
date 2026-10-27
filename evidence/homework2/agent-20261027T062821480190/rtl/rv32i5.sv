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

    // IF/ID
    logic        ifid_valid;
    logic [31:0] ifid_pc;
    logic [31:0] ifid_pc4;
    logic [31:0] ifid_instr;

    // ID/EX
    logic        id_ex_valid;
    logic [31:0] id_ex_pc;
    logic [31:0] id_ex_pc4;
    logic [4:0]  id_ex_rs1;
    logic [4:0]  id_ex_rs2;
    logic [4:0]  id_ex_rd;
    logic [31:0] id_ex_rs1_data;
    logic [31:0] id_ex_rs2_data;
    logic [31:0] id_ex_imm;
    logic [3:0]  id_ex_alu_op;
    logic [1:0]  id_ex_alu_a_sel;
    logic [1:0]  id_ex_alu_b_sel;
    logic        id_ex_is_branch;
    logic [2:0]  id_ex_branch_f3;
    logic        id_ex_is_jal;
    logic        id_ex_is_jalr;
    logic        id_ex_is_load;
    logic        id_ex_is_store;
    logic [2:0]  id_ex_mem_f3;
    logic        id_ex_reg_write;
    logic        id_ex_is_ecall;

    // EX/MEM
    logic        ex_mem_valid;
    logic [31:0] ex_mem_result;
    logic [31:0] ex_mem_store_data;
    logic [4:0]  ex_mem_rs2;
    logic [4:0]  ex_mem_rd;
    logic        ex_mem_is_load;
    logic        ex_mem_is_store;
    logic [2:0]  ex_mem_mem_f3;
    logic        ex_mem_reg_write;
    logic        ex_mem_is_ecall;

    // MEM/WB
    logic        mem_wb_valid;
    logic [31:0] mem_wb_data;
    logic [4:0]  mem_wb_rd;
    logic        mem_wb_reg_write;
    logic        mem_wb_is_ecall;

    // ID stage outputs
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic        id_is_ecall;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    // EX stage outputs
    logic        redirect;
    logic [31:0] redirect_pc;

    // Hazard
    logic        halt_pending;
    logic        stall_load_use;
    logic        flush_ifid;
    logic        flush_idex;

    // Forwarding
    logic [1:0]  fwd_a;
    logic [1:0]  fwd_b;
    logic        store_fwd;

    // WB
    logic        rf_we;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;
    logic        halt_commit;

    // Regfile
    logic [31:0] x10_value;

    // Control
    logic        kill_if;
    logic        pc_hold;
    logic        halt_mem;

    // Stall freezes ONLY PC, IF/ID and ID/EX; EX/MEM and MEM/WB always advance.
    assign kill_if  = flush_ifid;
    assign pc_hold  = halt_pending | halted | stall_load_use;
    assign halt_mem = halted | halt_commit;

    if_stage u_if (
        .clk          (clk),
        .rst_n        (rst_n),
        .redirect     (redirect),
        .redirect_pc  (redirect_pc),
        .stall        (stall_load_use),
        .kill         (kill_if),
        .pc_hold      (pc_hold),
        .imem_rdata   (imem_rdata),
        .imem_addr    (imem_addr),
        .ifid_valid   (ifid_valid),
        .ifid_pc      (ifid_pc),
        .ifid_pc4     (ifid_pc4),
        .ifid_instr   (ifid_instr)
    );

    id_stage u_id (
        .clk            (clk),
        .rst_n          (rst_n),
        .ifid_valid     (ifid_valid),
        .ifid_pc        (ifid_pc),
        .ifid_pc4       (ifid_pc4),
        .ifid_instr     (ifid_instr),
        .rs1_data       (rs1_data),
        .rs2_data       (rs2_data),
        .flush          (flush_idex),
        .rs1_addr       (rs1_addr),
        .rs2_addr       (rs2_addr),
        .id_is_ecall    (id_is_ecall),
        .id_ex_valid    (id_ex_valid),
        .id_ex_pc       (id_ex_pc),
        .id_ex_pc4      (id_ex_pc4),
        .id_ex_rs1      (id_ex_rs1),
        .id_ex_rs2      (id_ex_rs2),
        .id_ex_rd       (id_ex_rd),
        .id_ex_rs1_data (id_ex_rs1_data),
        .id_ex_rs2_data (id_ex_rs2_data),
        .id_ex_imm      (id_ex_imm),
        .id_ex_alu_op   (id_ex_alu_op),
        .id_ex_alu_a_sel(id_ex_alu_a_sel),
        .id_ex_alu_b_sel(id_ex_alu_b_sel),
        .id_ex_is_branch(id_ex_is_branch),
        .id_ex_branch_f3(id_ex_branch_f3),
        .id_ex_is_jal   (id_ex_is_jal),
        .id_ex_is_jalr  (id_ex_is_jalr),
        .id_ex_is_load  (id_ex_is_load),
        .id_ex_is_store (id_ex_is_store),
        .id_ex_mem_f3   (id_ex_mem_f3),
        .id_ex_reg_write(id_ex_reg_write),
        .id_ex_is_ecall (id_ex_is_ecall)
    );

    ex_stage u_ex (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (halt_mem),
        .id_ex_valid     (id_ex_valid),
        .id_ex_pc        (id_ex_pc),
        .id_ex_pc4       (id_ex_pc4),
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .id_ex_rd        (id_ex_rd),
        .id_ex_rs1_data  (id_ex_rs1_data),
        .id_ex_rs2_data  (id_ex_rs2_data),
        .id_ex_imm       (id_ex_imm),
        .id_ex_alu_op    (id_ex_alu_op),
        .id_ex_alu_a_sel (id_ex_alu_a_sel),
        .id_ex_alu_b_sel (id_ex_alu_b_sel),
        .id_ex_is_branch (id_ex_is_branch),
        .id_ex_branch_f3 (id_ex_branch_f3),
        .id_ex_is_jal    (id_ex_is_jal),
        .id_ex_is_jalr   (id_ex_is_jalr),
        .id_ex_is_load   (id_ex_is_load),
        .id_ex_is_store  (id_ex_is_store),
        .id_ex_mem_f3    (id_ex_mem_f3),
        .id_ex_reg_write (id_ex_reg_write),
        .id_ex_is_ecall  (id_ex_is_ecall),
        .fwd_a           (fwd_a),
        .fwd_b           (fwd_b),
        .fwd_ex_mem_data (ex_mem_result),
        .fwd_mem_wb_data (mem_wb_data),
        .redirect        (redirect),
        .redirect_pc     (redirect_pc),
        .ex_mem_valid    (ex_mem_valid),
        .ex_mem_result   (ex_mem_result),
        .ex_mem_store_data(ex_mem_store_data),
        .ex_mem_rs2      (ex_mem_rs2),
        .ex_mem_rd       (ex_mem_rd),
        .ex_mem_is_load  (ex_mem_is_load),
        .ex_mem_is_store (ex_mem_is_store),
        .ex_mem_mem_f3   (ex_mem_mem_f3),
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_is_ecall (ex_mem_is_ecall)
    );

    mem_stage u_mem (
        .clk              (clk),
        .rst_n            (rst_n),
        .halt             (halt_mem),
        .ex_mem_valid     (ex_mem_valid),
        .ex_mem_result    (ex_mem_result),
        .ex_mem_store_data(ex_mem_store_data),
        .ex_mem_rs2       (ex_mem_rs2),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_is_load   (ex_mem_is_load),
        .ex_mem_is_store  (ex_mem_is_store),
        .ex_mem_mem_f3    (ex_mem_mem_f3),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_is_ecall  (ex_mem_is_ecall),
        .dmem_rdata       (dmem_rdata),
        .store_fwd        (store_fwd),
        .mem_wb_wb_data   (mem_wb_data),
        .dmem_valid       (dmem_valid),
        .dmem_we          (dmem_we),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_be          (dmem_be),
        .mem_wb_valid     (mem_wb_valid),
        .mem_wb_data      (mem_wb_data),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_is_ecall  (mem_wb_is_ecall)
    );

    wb_stage u_wb (
        .clk             (clk),
        .rst_n           (rst_n),
        .mem_wb_valid    (mem_wb_valid),
        .mem_wb_data     (mem_wb_data),
        .mem_wb_rd       (mem_wb_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .mem_wb_is_ecall (mem_wb_is_ecall),
        .x10_value       (x10_value),
        .rf_we           (rf_we),
        .rf_waddr        (rf_waddr),
        .rf_wdata        (rf_wdata),
        .halt_commit     (halt_commit),
        .halted          (halted),
        .exit_code       (exit_code)
    );

    hazard_unit u_hazard (
        .clk           (clk),
        .rst_n         (rst_n),
        .redirect      (redirect),
        .halted        (halted),
        .id_is_ecall   (id_is_ecall),
        .ifid_valid    (ifid_valid),
        .ifid_instr    (ifid_instr),
        .id_ex_valid   (id_ex_valid),
        .id_ex_is_load (id_ex_is_load),
        .id_ex_rd      (id_ex_rd),
        .halt_pending  (halt_pending),
        .stall_load_use(stall_load_use),
        .flush_ifid    (flush_ifid),
        .flush_idex    (flush_idex)
    );

    forwarding_unit u_fwd (
        .id_ex_valid     (id_ex_valid),
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .ex_mem_valid    (ex_mem_valid),
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_rd       (ex_mem_rd),
        .ex_mem_is_load  (ex_mem_is_load),
        .ex_mem_rs2      (ex_mem_rs2),
        .ex_mem_is_store (ex_mem_is_store),
        .mem_wb_valid    (mem_wb_valid),
        .mem_wb_reg_write(mem_wb_reg_write),
        .mem_wb_rd       (mem_wb_rd),
        .fwd_a           (fwd_a),
        .fwd_b           (fwd_b),
        .store_fwd       (store_fwd)
    );

    regfile u_rf (
        .clk      (clk),
        .rst_n    (rst_n),
        .we       (rf_we),
        .waddr    (rf_waddr),
        .wdata    (rf_wdata),
        .raddr1   (rs1_addr),
        .rdata1   (rs1_data),
        .raddr2   (rs2_addr),
        .rdata2   (rs2_data),
        .dbg_addr (dbg_reg_addr),
        .dbg_data (dbg_reg_data),
        .x10_data (x10_value)
    );

endmodule
