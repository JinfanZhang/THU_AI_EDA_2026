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

    // IF/ID pipeline register
    logic        ifid_valid;
    logic [31:0] ifid_pc;
    logic [31:0] ifid_pc_plus4;
    logic [31:0] ifid_instr;

    // ID/EX pipeline register
    logic        idex_valid;
    logic [31:0] idex_pc;
    logic [31:0] idex_pc_plus4;
    logic [31:0] idex_rs1_data;
    logic [31:0] idex_rs2_data;
    logic [4:0]  idex_rs1_addr;
    logic [4:0]  idex_rs2_addr;
    logic [31:0] idex_imm;
    logic [4:0]  idex_rd_addr;
    logic [3:0]  idex_alu_op;
    logic [1:0]  idex_alu_a_sel;
    logic        idex_alu_b_sel;
    logic        idex_reg_write;
    logic        idex_mem_read;
    logic        idex_mem_write;
    logic [1:0]  idex_mem_size;
    logic        idex_mem_unsign;
    logic [1:0]  idex_wb_sel;
    logic        idex_branch;
    logic [2:0]  idex_branch_op;
    logic        idex_jump;
    logic        idex_jalr;
    logic        idex_is_ecall;

    // EX/MEM pipeline register
    logic        exmem_valid;
    logic [31:0] exmem_pc_plus4;
    logic [31:0] exmem_alu_result;
    logic [31:0] exmem_rs2_data;
    logic [4:0]  exmem_rs2_addr;
    logic [4:0]  exmem_rd_addr;
    logic        exmem_reg_write;
    logic        exmem_mem_read;
    logic        exmem_mem_write;
    logic [1:0]  exmem_mem_size;
    logic        exmem_mem_unsign;
    logic [1:0]  exmem_wb_sel;
    logic        exmem_is_ecall;

    // MEM/WB pipeline register
    logic        memwb_valid;
    logic [31:0] memwb_wb_data;
    logic [4:0]  memwb_rd_addr;
    logic        memwb_reg_write;
    logic        memwb_is_ecall;

    // ID stage register-file read ports
    logic [4:0]  id_rs1_addr;
    logic [4:0]  id_rs2_addr;
    logic        id_uses_rs1;
    logic        id_uses_rs2;
    logic [31:0] id_rs1_data;
    logic [31:0] id_rs2_data;
    logic        id_is_ecall;

    // WB stage
    logic        wb_we;
    logic [4:0]  wb_rd_addr;
    logic [31:0] wb_wb_data;
    logic [31:0] x10_value;

    // EX stage
    logic        ex_redirect;
    logic [31:0] redirect_pc;
    logic [31:0] ex_rs1_data;
    logic [31:0] ex_rs2_data;

    // Hazard unit
    logic        redirect_en;
    logic        pc_hold;
    logic        if_flush;
    logic        idex_flush;
    logic        exmem_flush;
    logic        memwb_flush;

    // mem_stage external memory outputs (internal nets, gated at top)
    logic        mem_dmem_valid;
    logic        mem_dmem_we;
    logic [31:0] mem_dmem_addr;
    logic [31:0] mem_dmem_wdata;
    logic [3:0]  mem_dmem_be;

    if_stage u_if (
        .clk           (clk),
        .rst_n         (rst_n),
        .imem_addr     (imem_addr),
        .imem_rdata    (imem_rdata),
        .pc_hold       (pc_hold),
        .redirect_en   (redirect_en),
        .redirect_pc   (redirect_pc),
        .if_flush      (if_flush),
        .ifid_valid    (ifid_valid),
        .ifid_pc       (ifid_pc),
        .ifid_pc_plus4 (ifid_pc_plus4),
        .ifid_instr    (ifid_instr)
    );

    id_stage u_id (
        .clk           (clk),
        .rst_n         (rst_n),
        .ifid_valid    (ifid_valid),
        .ifid_pc       (ifid_pc),
        .ifid_pc_plus4 (ifid_pc_plus4),
        .ifid_instr    (ifid_instr),
        .id_rs1_addr   (id_rs1_addr),
        .id_rs2_addr   (id_rs2_addr),
        .id_uses_rs1   (id_uses_rs1),
        .id_uses_rs2   (id_uses_rs2),
        .id_rs1_data   (id_rs1_data),
        .id_rs2_data   (id_rs2_data),
        .id_is_ecall   (id_is_ecall),
        .idex_flush    (idex_flush),
        .idex_valid    (idex_valid),
        .idex_pc       (idex_pc),
        .idex_pc_plus4 (idex_pc_plus4),
        .idex_rs1_data (idex_rs1_data),
        .idex_rs2_data (idex_rs2_data),
        .idex_rs1_addr (idex_rs1_addr),
        .idex_rs2_addr (idex_rs2_addr),
        .idex_imm      (idex_imm),
        .idex_rd_addr  (idex_rd_addr),
        .idex_alu_op   (idex_alu_op),
        .idex_alu_a_sel(idex_alu_a_sel),
        .idex_alu_b_sel(idex_alu_b_sel),
        .idex_reg_write(idex_reg_write),
        .idex_mem_read (idex_mem_read),
        .idex_mem_write(idex_mem_write),
        .idex_mem_size (idex_mem_size),
        .idex_mem_unsign(idex_mem_unsign),
        .idex_wb_sel   (idex_wb_sel),
        .idex_branch   (idex_branch),
        .idex_branch_op(idex_branch_op),
        .idex_jump     (idex_jump),
        .idex_jalr     (idex_jalr),
        .idex_is_ecall (idex_is_ecall)
    );

    // EX stage consumes the forwarding-resolved operands, not the raw
    // ID-stage register-file reads.
    ex_stage u_ex (
        .clk            (clk),
        .rst_n          (rst_n),
        .idex_valid     (idex_valid),
        .idex_pc        (idex_pc),
        .idex_pc_plus4  (idex_pc_plus4),
        .idex_rs1_data  (ex_rs1_data),
        .idex_rs2_data  (ex_rs2_data),
        .idex_rs1_addr  (idex_rs1_addr),
        .idex_rs2_addr  (idex_rs2_addr),
        .idex_imm       (idex_imm),
        .idex_rd_addr   (idex_rd_addr),
        .idex_alu_op    (idex_alu_op),
        .idex_alu_a_sel (idex_alu_a_sel),
        .idex_alu_b_sel (idex_alu_b_sel),
        .idex_reg_write (idex_reg_write),
        .idex_mem_read  (idex_mem_read),
        .idex_mem_write (idex_mem_write),
        .idex_mem_size  (idex_mem_size),
        .idex_mem_unsign(idex_mem_unsign),
        .idex_wb_sel    (idex_wb_sel),
        .idex_branch    (idex_branch),
        .idex_branch_op (idex_branch_op),
        .idex_jump      (idex_jump),
        .idex_jalr      (idex_jalr),
        .idex_is_ecall  (idex_is_ecall),
        .ex_rs1_data    (ex_rs1_data),
        .ex_rs2_data    (ex_rs2_data),
        .ex_redirect    (ex_redirect),
        .redirect_pc    (redirect_pc),
        .exmem_flush    (exmem_flush),
        .exmem_valid    (exmem_valid),
        .exmem_pc_plus4 (exmem_pc_plus4),
        .exmem_alu_result(exmem_alu_result),
        .exmem_rs2_data (exmem_rs2_data),
        .exmem_rs2_addr (exmem_rs2_addr),
        .exmem_rd_addr  (exmem_rd_addr),
        .exmem_reg_write(exmem_reg_write),
        .exmem_mem_read (exmem_mem_read),
        .exmem_mem_write(exmem_mem_write),
        .exmem_mem_size (exmem_mem_size),
        .exmem_mem_unsign(exmem_mem_unsign),
        .exmem_wb_sel   (exmem_wb_sel),
        .exmem_is_ecall (exmem_is_ecall)
    );

    // mem_stage drives the forwarding-resolved store data / address / byte
    // enables; these are captured on internal nets and gated at the top.
    mem_stage u_mem (
        .clk            (clk),
        .rst_n          (rst_n),
        .exmem_valid    (exmem_valid),
        .exmem_pc_plus4 (exmem_pc_plus4),
        .exmem_alu_result(exmem_alu_result),
        .exmem_rs2_data (exmem_rs2_data),
        .exmem_rs2_addr (exmem_rs2_addr),
        .exmem_rd_addr  (exmem_rd_addr),
        .exmem_reg_write(exmem_reg_write),
        .exmem_mem_read (exmem_mem_read),
        .exmem_mem_write(exmem_mem_write),
        .exmem_mem_size (exmem_mem_size),
        .exmem_mem_unsign(exmem_mem_unsign),
        .exmem_wb_sel   (exmem_wb_sel),
        .exmem_is_ecall (exmem_is_ecall),
        .dmem_rdata     (dmem_rdata),
        .memwb_flush    (memwb_flush),
        .memwb_valid    (memwb_valid),
        .memwb_wb_data  (memwb_wb_data),
        .memwb_rd_addr  (memwb_rd_addr),
        .memwb_reg_write(memwb_reg_write),
        .memwb_is_ecall (memwb_is_ecall),
        .dmem_valid     (mem_dmem_valid),
        .dmem_we        (mem_dmem_we),
        .dmem_addr      (mem_dmem_addr),
        .dmem_wdata     (mem_dmem_wdata),
        .dmem_be        (mem_dmem_be)
    );

    // Top-level external memory interface: dmem_valid is a combinational AND
    // that includes rst_n so it is 0 (not X) strictly before and during reset.
    assign dmem_valid = mem_dmem_valid & rst_n;
    assign dmem_we    = mem_dmem_we    & rst_n;
    assign dmem_addr  = mem_dmem_addr;
    assign dmem_wdata = mem_dmem_wdata;
    assign dmem_be    = mem_dmem_be;

    wb_stage u_wb (
        .clk            (clk),
        .rst_n          (rst_n),
        .memwb_valid    (memwb_valid),
        .memwb_wb_data  (memwb_wb_data),
        .memwb_rd_addr  (memwb_rd_addr),
        .memwb_reg_write(memwb_reg_write),
        .memwb_is_ecall (memwb_is_ecall),
        .x10_value      (x10_value),
        .wb_we          (wb_we),
        .wb_rd_addr     (wb_rd_addr),
        .wb_wb_data     (wb_wb_data),
        .halted         (halted),
        .exit_code      (exit_code)
    );

    hazard_unit u_hazard (
        .clk           (clk),
        .rst_n         (rst_n),
        .halted        (halted),
        .ex_redirect   (ex_redirect),
        .ifid_valid    (ifid_valid),
        .id_uses_rs1   (id_uses_rs1),
        .id_uses_rs2   (id_uses_rs2),
        .id_rs1_addr   (id_rs1_addr),
        .id_rs2_addr   (id_rs2_addr),
        .id_is_ecall   (id_is_ecall),
        .idex_valid    (idex_valid),
        .idex_mem_read (idex_mem_read),
        .idex_rd_addr  (idex_rd_addr),
        .redirect_en   (redirect_en),
        .pc_hold       (pc_hold),
        .if_flush      (if_flush),
        .idex_flush    (idex_flush),
        .exmem_flush   (exmem_flush),
        .memwb_flush   (memwb_flush)
    );

    forwarding_unit u_fwd (
        .idex_valid     (idex_valid),
        .idex_rs1_addr  (idex_rs1_addr),
        .idex_rs2_addr  (idex_rs2_addr),
        .idex_rs1_data  (idex_rs1_data),
        .idex_rs2_data  (idex_rs2_data),
        .exmem_valid    (exmem_valid),
        .exmem_reg_write(exmem_reg_write),
        .exmem_rd_addr  (exmem_rd_addr),
        .exmem_alu_result(exmem_alu_result),
        .memwb_valid    (memwb_valid),
        .memwb_reg_write(memwb_reg_write),
        .memwb_rd_addr  (memwb_rd_addr),
        .memwb_wb_data  (memwb_wb_data),
        .ex_rs1_data    (ex_rs1_data),
        .ex_rs2_data    (ex_rs2_data)
    );

    regfile u_regfile (
        .clk          (clk),
        .rst_n        (rst_n),
        .id_rs1_addr  (id_rs1_addr),
        .id_rs1_data  (id_rs1_data),
        .id_rs2_addr  (id_rs2_addr),
        .id_rs2_data  (id_rs2_data),
        .wb_we        (wb_we),
        .wb_rd_addr   (wb_rd_addr),
        .wb_wb_data   (wb_wb_data),
        .dbg_reg_addr (dbg_reg_addr),
        .dbg_reg_data (dbg_reg_data),
        .x10_value    (x10_value)
    );

endmodule
