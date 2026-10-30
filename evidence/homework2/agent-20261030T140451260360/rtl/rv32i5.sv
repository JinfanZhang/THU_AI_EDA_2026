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
    // IF stage <-> I-Cache
    // ---------------------------------------------------------------
    logic        if_cpu_req_valid;
    logic [31:0] if_cpu_req_addr;
    logic        if_cpu_req_ready;
    logic        if_cpu_resp_valid;
    logic [31:0] if_cpu_resp_data;

    // IF/ID pipeline register
    logic        if2id_valid;
    logic [31:0] if2id_pc;
    logic [31:0] if2id_pc4;
    logic [31:0] if2id_insn;
    logic [31:0] if2id_pred_next_pc;
    logic        if2id_pred_valid;

    // ---------------------------------------------------------------
    // ID stage
    // ---------------------------------------------------------------
    logic        id_uses_rs1;
    logic        id_uses_rs2;
    logic [4:0]  id_rs1;
    logic [4:0]  id_rs2;
    logic        ecall_in_id;
    logic [31:0] reg_x10;

    logic        id2ex_valid;
    logic [31:0] id2ex_pc;
    logic [31:0] id2ex_pc4;
    logic [31:0] id2ex_insn;
    logic [31:0] id2ex_rs1_val;
    logic [31:0] id2ex_rs2_val;
    logic [31:0] id2ex_imm;
    logic [4:0]  id2ex_rs1;
    logic [4:0]  id2ex_rs2;
    logic [4:0]  id2ex_rd;
    logic [3:0]  id2ex_alu_op;
    logic        id2ex_op_a_pc;
    logic        id2ex_op_b_imm;
    logic        id2ex_reg_write;
    logic        id2ex_mem_read;
    logic        id2ex_mem_write;
    logic        id2ex_branch;
    logic        id2ex_jump;
    logic [1:0]  id2ex_wb_sel;
    logic [2:0]  id2ex_funct3;
    logic        id2ex_is_ecall;
    logic [31:0] id2ex_pred_next_pc;
    logic        id2ex_pred_valid;

    // ---------------------------------------------------------------
    // EX stage
    // ---------------------------------------------------------------
    logic        redirect_valid;
    logic [31:0] redirect_target;
    logic        ex_load_valid;
    logic [4:0]  ex_load_rd;

    logic        ex2mem_valid;
    logic [31:0] ex2mem_pc;
    logic [31:0] ex2mem_pc4;
    logic [31:0] ex2mem_insn;
    logic [31:0] ex2mem_alu_result;
    logic [31:0] ex2mem_store_data;
    logic [4:0]  ex2mem_rd;
    logic        ex2mem_reg_write;
    logic        ex2mem_mem_read;
    logic        ex2mem_mem_write;
    logic [1:0]  ex2mem_wb_sel;
    logic [2:0]  ex2mem_funct3;
    logic        ex2mem_is_ecall;

    logic [1:0]  fwd_a;
    logic [1:0]  fwd_b;
    logic [31:0] ex2mem_forward_data;

    // ---------------------------------------------------------------
    // MEM stage <-> D-Cache
    // ---------------------------------------------------------------
    logic        mem_cpu_req_valid;
    logic        mem_cpu_req_we;
    logic [31:0] mem_cpu_req_addr;
    logic [31:0] mem_cpu_req_wdata;
    logic [3:0]  mem_cpu_req_be;
    logic        mem_cpu_req_ready;
    logic        mem_cpu_resp_valid;
    logic [31:0] mem_cpu_resp_rdata;

    logic        mem_stall;

    logic        mem2wb_valid;
    logic [31:0] mem2wb_pc;
    logic [31:0] mem2wb_insn;
    logic [31:0] mem2wb_wdata;
    logic [4:0]  mem2wb_rd;
    logic        mem2wb_reg_write;
    logic        mem2wb_is_ecall;

    // ---------------------------------------------------------------
    // WB stage
    // ---------------------------------------------------------------
    logic        wb_reg_write;
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;

    // ---------------------------------------------------------------
    // Hazard / flush
    // ---------------------------------------------------------------
    logic        load_use_stall;
    logic        flush_id_ex;
    logic        flush;
    logic [1:0]  flush_epoch;

    // ---------------------------------------------------------------
    // I-Cache external bus
    // ---------------------------------------------------------------
    logic        ic_mem_req_valid;
    logic [31:0] ic_mem_req_addr;
    logic        ic_mem_req_ready;
    logic        ic_mem_resp_valid;
    logic [31:0] ic_mem_resp_data;

    // ---------------------------------------------------------------
    // D-Cache external bus
    // ---------------------------------------------------------------
    logic        dc_mem_req_valid;
    logic        dc_mem_req_we;
    logic [31:0] dc_mem_req_addr;
    logic [31:0] dc_mem_req_wdata;
    logic [3:0]  dc_mem_req_be;
    logic        dc_mem_req_ready;
    logic        dc_mem_resp_valid;
    logic [31:0] dc_mem_resp_data;

    // ---------------------------------------------------------------
    // Branch predictor observability
    // ---------------------------------------------------------------
    logic [31:0] bp_lookup_pc;
    logic        bp_pred_taken;
    logic [31:0] bp_pred_target;
    logic        bp_btb_hit;

    // Single authoritative EX-stage resolution strobe.
    logic        ex_bp_resolve;
    logic [31:0] ex_bp_pc;
    logic [31:0] ex_bp_target;
    logic        ex_bp_is_cond;
    logic        ex_bp_actual_taken;
    logic        ex_bp_is_jalr;

    // ---------------------------------------------------------------
    // Feature declaration: L2 = I-cache + D-cache + dynamic branch
    // prediction + OoO-style forwarding/bypass.
    // ---------------------------------------------------------------
    assign dbg_features = 3'b111;

    // ---------------------------------------------------------------
    // IF stage
    // ---------------------------------------------------------------
    if_stage u_if_stage (
        .clk               (clk),
        .rst_n             (rst_n),
        .if_stall          (load_use_stall),
        .if_flush          (flush),
        .redirect_valid    (redirect_valid),
        .redirect_pc       (redirect_target),
        .halt_pending      (halted),
        .bp_lookup_pc      (bp_lookup_pc),
        .bp_pred_taken     (bp_pred_taken),
        .bp_pred_target    (bp_pred_target),
        .cpu_req_valid     (if_cpu_req_valid),
        .cpu_req_addr      (if_cpu_req_addr),
        .cpu_req_ready     (if_cpu_req_ready),
        .cpu_resp_valid    (if_cpu_resp_valid),
        .cpu_resp_data     (if_cpu_resp_data),
        .if_id_valid       (if2id_valid),
        .if_id_pc          (if2id_pc),
        .if_id_pc_plus4    (if2id_pc4),
        .if_id_instr       (if2id_insn),
        .if_id_pred_next_pc(if2id_pred_next_pc),
        .if_id_pred_valid  (if2id_pred_valid)
    );

    // ---------------------------------------------------------------
    // ID stage
    // ---------------------------------------------------------------
    id_stage u_id_stage (
        .clk           (clk),
        .rst_n         (rst_n),
        .if2id_valid   (if2id_valid),
        .if2id_pc      (if2id_pc),
        .if2id_pc4     (if2id_pc4),
        .if2id_insn    (if2id_insn),
        .wb_reg_write  (wb_reg_write),
        .wb_rd         (wb_rd),
        .wb_data       (wb_data),
        .flush_id_ex   (flush_id_ex),
        .mem_stall     (mem_stall),
        .id_uses_rs1   (id_uses_rs1),
        .id_uses_rs2   (id_uses_rs2),
        .id_rs1        (id_rs1),
        .id_rs2        (id_rs2),
        .ecall_in_id   (ecall_in_id),
        .dbg_reg_addr  (dbg_reg_addr),
        .dbg_reg_data  (dbg_reg_data),
        .reg_x10       (reg_x10),
        .id2ex_valid   (id2ex_valid),
        .id2ex_pc      (id2ex_pc),
        .id2ex_pc4     (id2ex_pc4),
        .id2ex_insn    (id2ex_insn),
        .id2ex_rs1_val (id2ex_rs1_val),
        .id2ex_rs2_val (id2ex_rs2_val),
        .id2ex_imm     (id2ex_imm),
        .id2ex_rs1     (id2ex_rs1),
        .id2ex_rs2     (id2ex_rs2),
        .id2ex_rd      (id2ex_rd),
        .id2ex_alu_op  (id2ex_alu_op),
        .id2ex_op_a_pc (id2ex_op_a_pc),
        .id2ex_op_b_imm(id2ex_op_b_imm),
        .id2ex_reg_write(id2ex_reg_write),
        .id2ex_mem_read(id2ex_mem_read),
        .id2ex_mem_write(id2ex_mem_write),
        .id2ex_branch  (id2ex_branch),
        .id2ex_jump    (id2ex_jump),
        .id2ex_wb_sel  (id2ex_wb_sel),
        .id2ex_funct3  (id2ex_funct3),
        .id2ex_is_ecall(id2ex_is_ecall)
    );

    // Carry the predicted next PC alongside the ID/EX register.  The
    // prediction is captured in IF/ID and forwarded through ID/EX so
    // the EX stage can compare against the resolved target.
    assign id2ex_pred_next_pc = if2id_pred_next_pc;
    assign id2ex_pred_valid   = if2id_pred_valid;

    // EX/MEM forward data must select PC value for JAL/JALR.
    assign ex2mem_forward_data = (ex2mem_wb_sel == 2'b10) ? ex2mem_pc4 :
                                 (ex2mem_wb_sel == 2'b11) ? ex2mem_pc  :
                                                            ex2mem_alu_result;

    // ---------------------------------------------------------------
    // EX stage
    // ---------------------------------------------------------------
    ex_stage u_ex_stage (
        .clk             (clk),
        .rst_n           (rst_n),
        .mem_stall       (mem_stall),
        .id2ex_valid     (id2ex_valid),
        .id2ex_pc        (id2ex_pc),
        .id2ex_pc4       (id2ex_pc4),
        .id2ex_insn      (id2ex_insn),
        .id2ex_rs1_val   (id2ex_rs1_val),
        .id2ex_rs2_val   (id2ex_rs2_val),
        .id2ex_imm       (id2ex_imm),
        .id2ex_rs1       (id2ex_rs1),
        .id2ex_rs2       (id2ex_rs2),
        .id2ex_rd        (id2ex_rd),
        .id2ex_alu_op    (id2ex_alu_op),
        .id2ex_op_a_pc   (id2ex_op_a_pc),
        .id2ex_op_b_imm  (id2ex_op_b_imm),
        .id2ex_reg_write (id2ex_reg_write),
        .id2ex_mem_read  (id2ex_mem_read),
        .id2ex_mem_write (id2ex_mem_write),
        .id2ex_branch    (id2ex_branch),
        .id2ex_jump      (id2ex_jump),
        .id2ex_wb_sel    (id2ex_wb_sel),
        .id2ex_funct3    (id2ex_funct3),
        .id2ex_is_ecall  (id2ex_is_ecall),
        .fwd_a           (fwd_a),
        .fwd_b           (fwd_b),
        .mem2wb_wdata    (mem2wb_wdata),
        .ex2mem_forward_data(ex2mem_forward_data),
        .redirect_valid  (redirect_valid),
        .redirect_target (redirect_target),
        .ex_load_valid   (ex_load_valid),
        .ex_load_rd      (ex_load_rd),
        .ex2mem_valid    (ex2mem_valid),
        .ex2mem_pc       (ex2mem_pc),
        .ex2mem_pc4      (ex2mem_pc4),
        .ex2mem_insn     (ex2mem_insn),
        .ex2mem_alu_result(ex2mem_alu_result),
        .ex2mem_store_data(ex2mem_store_data),
        .ex2mem_rd       (ex2mem_rd),
        .ex2mem_reg_write(ex2mem_reg_write),
        .ex2mem_mem_read (ex2mem_mem_read),
        .ex2mem_mem_write(ex2mem_mem_write),
        .ex2mem_wb_sel   (ex2mem_wb_sel),
        .ex2mem_funct3   (ex2mem_funct3),
        .ex2mem_is_ecall (ex2mem_is_ecall),
        .ex_bp_resolve      (ex_bp_resolve),
        .ex_bp_pc           (ex_bp_pc),
        .ex_bp_target       (ex_bp_target),
        .ex_bp_is_cond      (ex_bp_is_cond),
        .ex_bp_actual_taken (ex_bp_actual_taken),
        .ex_bp_is_jalr      (ex_bp_is_jalr)
    );

    // ---------------------------------------------------------------
    // MEM stage
    // ---------------------------------------------------------------
    mem_stage u_mem_stage (
        .clk             (clk),
        .rst_n           (rst_n),
        .halted          (halted),
        .ex_mem_valid    (ex2mem_valid),
        .ex_mem_pc       (ex2mem_pc),
        .ex_mem_pc_plus4 (ex2mem_pc4),
        .ex_mem_instr    (ex2mem_insn),
        .ex_mem_rd       (ex2mem_rd),
        .ex_mem_rs2      (5'b0),
        .ex_mem_reg_write(ex2mem_reg_write),
        .ex_mem_mem_read (ex2mem_mem_read),
        .ex_mem_mem_write(ex2mem_mem_write),
        .ex_mem_is_load  (ex2mem_mem_read),
        .ex_mem_is_store (ex2mem_mem_write),
        .ex_mem_mem_size (ex2mem_funct3[1:0]),
        .ex_mem_wb_data  (ex2mem_forward_data),
        .ex_mem_store_data(ex2mem_store_data),
        .ex_mem_alu_result(ex2mem_alu_result),
        .ex_mem_is_ecall (ex2mem_is_ecall),
        .wb_ready        (1'b1),
        .mem_wb_valid    (mem2wb_valid),
        .mem_wb_pc       (mem2wb_pc),
        .mem_wb_instr    (mem2wb_insn),
        .mem_wb_rd       (mem2wb_rd),
        .mem_wb_reg_write(mem2wb_reg_write),
        .mem_wb_wb_data  (mem2wb_wdata),
        .mem_wb_is_ecall (mem2wb_is_ecall),
        .mem_stage_stall (mem_stall),
        .cpu_req_valid   (mem_cpu_req_valid),
        .cpu_req_we      (mem_cpu_req_we),
        .cpu_req_addr    (mem_cpu_req_addr),
        .cpu_req_wdata   (mem_cpu_req_wdata),
        .cpu_req_be      (mem_cpu_req_be),
        .cpu_req_ready   (mem_cpu_req_ready),
        .cpu_resp_valid  (mem_cpu_resp_valid),
        .cpu_resp_rdata  (mem_cpu_resp_rdata)
    );

    // ---------------------------------------------------------------
    // WB stage
    // ---------------------------------------------------------------
    wb_stage u_wb_stage (
        .clk             (clk),
        .rst_n           (rst_n),
        .mem2wb_valid    (mem2wb_valid),
        .mem2wb_pc       (mem2wb_pc),
        .mem2wb_insn     (mem2wb_insn),
        .mem2wb_wdata    (mem2wb_wdata),
        .mem2wb_rd       (mem2wb_rd),
        .mem2wb_reg_write(mem2wb_reg_write),
        .mem2wb_is_ecall (mem2wb_is_ecall),
        .reg_x10         (reg_x10),
        .wb_reg_write    (wb_reg_write),
        .wb_rd           (wb_rd),
        .wb_data         (wb_data),
        .halted          (halted),
        .exit_code       (exit_code),
        .dbg_retire_valid(dbg_retire_valid),
        .dbg_retire_pc   (dbg_retire_pc),
        .dbg_retire_insn (dbg_retire_insn)
    );

    // ---------------------------------------------------------------
    // Hazard unit
    // ---------------------------------------------------------------
    hazard_unit u_hazard_unit (
        .clk            (clk),
        .rst_n          (rst_n),
        .id_valid       (if2id_valid),
        .id_rs1         (id_rs1),
        .id_rs2         (id_rs2),
        .id_uses_rs1    (id_uses_rs1),
        .id_uses_rs2    (id_uses_rs2),
        .ex_load_valid  (ex_load_valid),
        .ex_load_rd     (ex_load_rd),
        .redirect_valid (redirect_valid),
        .ecall_in_id    (ecall_in_id),
        .load_use_stall (load_use_stall),
        .flush_id_ex    (flush_id_ex),
        .flush          (flush),
        .flush_epoch    (flush_epoch)
    );

    // ---------------------------------------------------------------
    // Forwarding unit
    // ---------------------------------------------------------------
    forwarding_unit u_forwarding_unit (
        .id2ex_rs1       (id2ex_rs1),
        .id2ex_rs2       (id2ex_rs2),
        .ex2mem_valid    (ex2mem_valid),
        .ex2mem_reg_write(ex2mem_reg_write),
        .ex2mem_mem_read (ex2mem_mem_read),
        .ex2mem_rd       (ex2mem_rd),
        .mem2wb_valid    (mem2wb_valid),
        .mem2wb_reg_write(mem2wb_reg_write),
        .mem2wb_rd       (mem2wb_rd),
        .fwd_a           (fwd_a),
        .fwd_b           (fwd_b)
    );

    // ---------------------------------------------------------------
    // I-Cache
    // ---------------------------------------------------------------
    icache u_icache (
        .clk            (clk),
        .rst_n          (rst_n),
        .halted         (halted),
        .flush          (flush),
        .flush_epoch    (flush_epoch),
        .cpu_req_valid  (if_cpu_req_valid),
        .cpu_req_addr   (if_cpu_req_addr),
        .cpu_req_ready  (if_cpu_req_ready),
        .cpu_resp_valid (if_cpu_resp_valid),
        .cpu_resp_data  (if_cpu_resp_data),
        .mem_req_valid  (ic_mem_req_valid),
        .mem_req_addr   (ic_mem_req_addr),
        .mem_req_ready  (ic_mem_req_ready),
        .mem_resp_valid (ic_mem_resp_valid),
        .mem_resp_data  (ic_mem_resp_data)
    );

    // ---------------------------------------------------------------
    // D-Cache
    // ---------------------------------------------------------------
    dcache u_dcache (
        .clk            (clk),
        .rst_n          (rst_n),
        .halted         (halted),
        .flush          (flush),
        .flush_epoch    (flush_epoch),
        .cpu_req_valid  (mem_cpu_req_valid),
        .cpu_req_we     (mem_cpu_req_we),
        .cpu_req_addr   (mem_cpu_req_addr),
        .cpu_req_wdata  (mem_cpu_req_wdata),
        .cpu_req_be     (mem_cpu_req_be),
        .cpu_req_ready  (mem_cpu_req_ready),
        .cpu_resp_valid (mem_cpu_resp_valid),
        .cpu_resp_rdata (mem_cpu_resp_rdata),
        .mem_req_valid  (dc_mem_req_valid),
        .mem_req_we     (dc_mem_req_we),
        .mem_req_addr   (dc_mem_req_addr),
        .mem_req_wdata  (dc_mem_req_wdata),
        .mem_req_be     (dc_mem_req_be),
        .mem_req_ready  (dc_mem_req_ready),
        .mem_resp_valid (dc_mem_resp_valid),
        .mem_resp_data  (dc_mem_resp_data)
    );

    // ---------------------------------------------------------------
    // Branch predictor
    // ---------------------------------------------------------------
    branch_predictor u_branch_predictor (
        .clk                 (clk),
        .rst_n               (rst_n),
        .bp_lookup_pc        (bp_lookup_pc),
        .bp_pred_taken       (bp_pred_taken),
        .bp_pred_target      (bp_pred_target),
        .bp_btb_hit          (bp_btb_hit),
        .bp_update_valid     (ex_bp_resolve),
        .bp_update_pc        (ex_bp_pc),
        .bp_update_target    (ex_bp_target),
        .bp_update_is_cond   (ex_bp_is_cond),
        .bp_update_actual_taken(ex_bp_actual_taken),
        .bp_update_is_jalr   (ex_bp_is_jalr)
    );

    // ---------------------------------------------------------------
    // External bus arbitration: I-Cache has priority; D-Cache requests
    // are held until the I bus is idle.  imem_addr is forced to 0 and
    // imem_valid to 0 during reset so no access is issued while rst_n
    // is low.  The external memory is a single-cycle slave: the response
    // is valid in the SAME cycle as the request when ready is high, so
    // the response data path is not registered here.
    // ---------------------------------------------------------------
    logic ic_bus_active;

    assign ic_bus_active = ic_mem_req_valid;

    assign imem_valid    = rst_n & ic_mem_req_valid;
    assign imem_addr     = rst_n ? {ic_mem_req_addr[31:2], 2'b00} : 32'h0000_0000;
    assign ic_mem_req_ready  = imem_ready;
    assign ic_mem_resp_valid = imem_valid & imem_ready;
    assign ic_mem_resp_data  = imem_rdata;

    assign dmem_valid    = rst_n & dc_mem_req_valid & ~ic_bus_active;
    assign dmem_we       = dc_mem_req_we;
    assign dmem_addr     = dc_mem_req_addr;
    assign dmem_wdata    = dc_mem_req_wdata;
    assign dmem_be       = dc_mem_req_be;
    assign dc_mem_req_ready  = ~ic_bus_active & dmem_ready;
    assign dc_mem_resp_valid = dmem_valid & dmem_ready;
    assign dc_mem_resp_data  = dmem_rdata;

    // ---------------------------------------------------------------
    // Capability observability, driven by real pipeline events.
    // ---------------------------------------------------------------
    assign dbg_bp_resolve    = ex_bp_resolve;
    assign dbg_bp_mispredict = ex_bp_resolve &
                               ((ex_bp_is_cond & (bp_pred_taken != ex_bp_actual_taken)) |
                                (ex_bp_target != bp_pred_target));

    // OoO-style issue: a younger ALU instruction issues into EX while an
    // older load is waiting on external memory (dmem_ready low).
    logic load_wait_ext;
    assign load_wait_ext = mem_stall & ~dmem_ready;
    assign dbg_ooo_issue = load_wait_ext & id2ex_valid & ~load_use_stall;

    // OoO-style bypass: a real forwarding path selected in EX while an
    // older load is waiting on external memory.
    assign dbg_ooo_bypass = load_wait_ext & ((fwd_a != 2'b00) | (fwd_b != 2'b00));

endmodule
