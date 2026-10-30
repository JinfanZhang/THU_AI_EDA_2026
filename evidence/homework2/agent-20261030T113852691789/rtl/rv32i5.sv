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

    // IF stage
    logic        if_redirect;
    logic [31:0] if_redirect_pc;
    logic        if_stall;
    logic        if_freeze;
    logic        if_id_valid;
    logic [31:0] if_id_pc;
    logic [31:0] if_id_pc_plus4;
    logic [31:0] if_id_instr;

    // ID stage
    logic [4:0]  id_rs1_addr;
    logic [4:0]  id_rs2_addr;
    logic [31:0] id_rs1_data;
    logic [31:0] id_rs2_data;
    logic        id_flush_ex;
    logic        id_valid;
    logic        id_ecall;
    logic        id_rs1_used;
    logic        id_rs2_used;
    logic        id_ex_valid;
    logic [31:0] id_ex_pc;
    logic [31:0] id_ex_pc_plus4;
    logic [31:0] id_ex_rs1_data;
    logic [31:0] id_ex_rs2_data;
    logic [4:0]  id_ex_rs1_addr;
    logic [4:0]  id_ex_rs2_addr;
    logic [4:0]  id_ex_rd_addr;
    logic [31:0] id_ex_imm;
    logic [3:0]  id_ex_alu_op;
    logic [1:0]  id_ex_alu_a_sel;
    logic        id_ex_alu_b_sel;
    logic [2:0]  id_ex_branch;
    logic [1:0]  id_ex_jump;
    logic [1:0]  id_ex_wb_sel;
    logic        id_ex_reg_write;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic [1:0]  id_ex_mem_size;
    logic        id_ex_mem_unsigned;
    logic        id_ex_ecall;

    // EX stage
    logic [1:0]  forward_a;
    logic [1:0]  forward_b;
    logic        ex_redirect;
    logic [31:0] ex_redirect_pc;
    logic        ex_mem_valid;
    logic [31:0] ex_mem_pc;
    logic [31:0] ex_mem_alu_result;
    logic [31:0] ex_mem_wb_data;
    logic [31:0] ex_mem_store_data;
    logic [4:0]  ex_mem_rd_addr;
    logic [4:0]  ex_mem_rs2_addr;
    logic        ex_mem_reg_write;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic [1:0]  ex_mem_mem_size;
    logic        ex_mem_mem_unsigned;
    logic        ex_mem_ecall;

    // MEM stage
    logic [31:0] mem_dmem_addr;
    logic [31:0] mem_dmem_wdata;
    logic [3:0]  mem_dmem_be;
    logic        mem_dmem_we;
    logic        mem_dmem_valid;
    logic        mem_wb_valid;
    logic [31:0] mem_wb_wb_data;
    logic [4:0]  mem_wb_rd_addr;
    logic        mem_wb_reg_write;
    logic        mem_wb_ecall;

    // WB stage
    logic        wb_reg_write_en;
    logic [4:0]  wb_reg_write_addr;
    logic [31:0] wb_reg_write_data;
    logic [31:0] reg_x10_data;

    // Hazard / forwarding
    logic        load_use_stall;
    logic        halt_pending;

    // Regfile
    logic        rf_we;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;

    // IF stage instance
    if_stage u_if (
        .clk             (clk),
        .rst_n           (rst_n),
        .redirect        (if_redirect),
        .redirect_pc     (if_redirect_pc),
        .stall           (if_stall),
        .freeze          (if_freeze),
        .imem_rdata      (imem_rdata),
        .imem_addr       (imem_addr),
        .if_id_valid     (if_id_valid),
        .if_id_pc        (if_id_pc),
        .if_id_pc_plus4  (if_id_pc_plus4),
        .if_id_instr     (if_id_instr)
    );

    // ID stage instance
    id_stage u_id (
        .clk             (clk),
        .rst_n           (rst_n),
        .if_id_valid     (if_id_valid),
        .if_id_pc        (if_id_pc),
        .if_id_pc_plus4  (if_id_pc_plus4),
        .if_id_instr     (if_id_instr),
        .rs1_data        (id_rs1_data),
        .rs2_data        (id_rs2_data),
        .rs1_addr        (id_rs1_addr),
        .rs2_addr        (id_rs2_addr),
        .flush_ex        (id_flush_ex),
        .id_valid        (id_valid),
        .id_ecall        (id_ecall),
        .id_rs1_used     (id_rs1_used),
        .id_rs2_used     (id_rs2_used),
        .id_ex_valid     (id_ex_valid),
        .id_ex_pc        (id_ex_pc),
        .id_ex_pc_plus4  (id_ex_pc_plus4),
        .id_ex_rs1_data  (id_ex_rs1_data),
        .id_ex_rs2_data  (id_ex_rs2_data),
        .id_ex_rs1_addr  (id_ex_rs1_addr),
        .id_ex_rs2_addr  (id_ex_rs2_addr),
        .id_ex_rd_addr   (id_ex_rd_addr),
        .id_ex_imm       (id_ex_imm),
        .id_ex_alu_op    (id_ex_alu_op),
        .id_ex_alu_a_sel (id_ex_alu_a_sel),
        .id_ex_alu_b_sel (id_ex_alu_b_sel),
        .id_ex_branch    (id_ex_branch),
        .id_ex_jump      (id_ex_jump),
        .id_ex_wb_sel    (id_ex_wb_sel),
        .id_ex_reg_write (id_ex_reg_write),
        .id_ex_mem_read  (id_ex_mem_read),
        .id_ex_mem_write (id_ex_mem_write),
        .id_ex_mem_size  (id_ex_mem_size),
        .id_ex_mem_unsigned (id_ex_mem_unsigned),
        .id_ex_ecall     (id_ex_ecall)
    );

    // EX stage instance
    ex_stage u_ex (
        .clk             (clk),
        .rst_n           (rst_n),
        .id_ex_valid     (id_ex_valid),
        .id_ex_pc        (id_ex_pc),
        .id_ex_pc_plus4  (id_ex_pc_plus4),
        .id_ex_rs1_data  (id_ex_rs1_data),
        .id_ex_rs2_data  (id_ex_rs2_data),
        .id_ex_rs1_addr  (id_ex_rs1_addr),
        .id_ex_rs2_addr  (id_ex_rs2_addr),
        .id_ex_rd_addr   (id_ex_rd_addr),
        .id_ex_imm       (id_ex_imm),
        .id_ex_alu_op    (id_ex_alu_op),
        .id_ex_alu_a_sel (id_ex_alu_a_sel),
        .id_ex_alu_b_sel (id_ex_alu_b_sel),
        .id_ex_branch    (id_ex_branch),
        .id_ex_jump      (id_ex_jump),
        .id_ex_wb_sel    (id_ex_wb_sel),
        .id_ex_reg_write (id_ex_reg_write),
        .id_ex_mem_read  (id_ex_mem_read),
        .id_ex_mem_write (id_ex_mem_write),
        .id_ex_mem_size  (id_ex_mem_size),
        .id_ex_mem_unsigned (id_ex_mem_unsigned),
        .id_ex_ecall     (id_ex_ecall),
        .forward_a       (forward_a),
        .forward_b       (forward_b),
        .mem_wb_wb_data  (mem_wb_wb_data),
        .ex_redirect     (ex_redirect),
        .ex_redirect_pc  (ex_redirect_pc),
        .ex_mem_valid    (ex_mem_valid),
        .ex_mem_pc       (ex_mem_pc),
        .ex_mem_alu_result (ex_mem_alu_result),
        .ex_mem_wb_data  (ex_mem_wb_data),
        .ex_mem_store_data (ex_mem_store_data),
        .ex_mem_rd_addr  (ex_mem_rd_addr),
        .ex_mem_rs2_addr (ex_mem_rs2_addr),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read (ex_mem_mem_read),
        .ex_mem_mem_write (ex_mem_mem_write),
        .ex_mem_mem_size (ex_mem_mem_size),
        .ex_mem_mem_unsigned (ex_mem_mem_unsigned),
        .ex_mem_ecall    (ex_mem_ecall)
    );

    // MEM stage instance
    mem_stage u_mem (
        .clk             (clk),
        .rst_n           (rst_n),
        .ex_mem_valid    (ex_mem_valid),
        .ex_mem_pc       (ex_mem_pc),
        .ex_mem_alu_result (ex_mem_alu_result),
        .ex_mem_wb_data  (ex_mem_wb_data),
        .ex_mem_store_data (ex_mem_store_data),
        .ex_mem_rd_addr  (ex_mem_rd_addr),
        .ex_mem_rs2_addr (ex_mem_rs2_addr),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read (ex_mem_mem_read),
        .ex_mem_mem_write (ex_mem_mem_write),
        .ex_mem_mem_size (ex_mem_mem_size),
        .ex_mem_mem_unsigned (ex_mem_mem_unsigned),
        .ex_mem_ecall    (ex_mem_ecall),
        .dmem_rdata      (dmem_rdata),
        .mem_dmem_addr   (mem_dmem_addr),
        .mem_dmem_wdata  (mem_dmem_wdata),
        .mem_dmem_be     (mem_dmem_be),
        .mem_dmem_we     (mem_dmem_we),
        .mem_dmem_valid  (mem_dmem_valid),
        .mem_wb_valid    (mem_wb_valid),
        .mem_wb_wb_data  (mem_wb_wb_data),
        .mem_wb_rd_addr  (mem_wb_rd_addr),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_ecall    (mem_wb_ecall)
    );

    // WB stage instance
    wb_stage u_wb (
        .clk             (clk),
        .rst_n           (rst_n),
        .mem_wb_valid    (mem_wb_valid),
        .mem_wb_wb_data  (mem_wb_wb_data),
        .mem_wb_rd_addr  (mem_wb_rd_addr),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_ecall    (mem_wb_ecall),
        .x10_data        (reg_x10_data),
        .reg_write_en    (wb_reg_write_en),
        .reg_write_addr  (wb_reg_write_addr),
        .reg_write_data  (wb_reg_write_data),
        .halted          (halted),
        .exit_code       (exit_code)
    );

    // Hazard unit instance
    hazard_unit u_hazard (
        .clk             (clk),
        .rst_n           (rst_n),
        .id_valid        (id_valid),
        .id_ecall        (id_ecall),
        .id_rs1_addr     (id_rs1_addr),
        .id_rs2_addr     (id_rs2_addr),
        .id_rs1_used     (id_rs1_used),
        .id_rs2_used     (id_rs2_used),
        .id_ex_valid     (id_ex_valid),
        .id_ex_mem_read  (id_ex_mem_read),
        .id_ex_rd_addr   (id_ex_rd_addr),
        .ex_redirect     (ex_redirect),
        .halted          (halted),
        .load_use_stall  (load_use_stall),
        .halt_pending    (halt_pending)
    );

    // Forwarding unit instance
    forwarding_unit u_fwd (
        .id_ex_rs1_addr  (id_ex_rs1_addr),
        .id_ex_rs2_addr  (id_ex_rs2_addr),
        .ex_mem_valid    (ex_mem_valid),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read (ex_mem_mem_read),
        .ex_mem_rd_addr  (ex_mem_rd_addr),
        .mem_wb_valid    (mem_wb_valid),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_rd_addr  (mem_wb_rd_addr),
        .forward_a       (forward_a),
        .forward_b       (forward_b)
    );

    // Register file instance. The second read port is wired straight from
    // id_stage.rs2_addr to regfile.rs2_addr and regfile.rs2_data back to
    // id_stage.rs2_data so the architectural rs2 operand reaches ID/EX.
    regfile u_rf (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (id_rs1_addr),
        .rs1_data  (id_rs1_data),
        .rs2_addr  (id_rs2_addr),
        .rs2_data  (id_rs2_data),
        .dbg_addr  (dbg_reg_addr),
        .dbg_data  (dbg_reg_data),
        .x10_data  (reg_x10_data),
        .we        (rf_we),
        .waddr     (rf_waddr),
        .wdata     (rf_wdata)
    );

    // Top-level wiring
    assign if_redirect   = ex_redirect;
    assign if_redirect_pc = ex_redirect_pc;
    assign if_stall      = load_use_stall;
    assign if_freeze     = halt_pending | halted;

    assign id_flush_ex   = ex_redirect;

    // Commit path: single write port driven only by wb_stage.
    // wb_stage already qualifies reg_write_en with valid/reg_write/rd!=0/~halted.
    assign rf_we    = wb_reg_write_en;
    assign rf_waddr = wb_reg_write_addr;
    assign rf_wdata = wb_reg_write_data;

    assign dmem_valid = mem_dmem_valid & rst_n & ~halted;
    assign dmem_we    = mem_dmem_we & dmem_valid;
    assign dmem_addr  = mem_dmem_addr;
    assign dmem_wdata = mem_dmem_wdata;
    assign dmem_be    = mem_dmem_be;

endmodule
