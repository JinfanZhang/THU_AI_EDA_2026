module hazard_unit (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       halted,
    input  logic       ex_redirect,
    input  logic       ifid_valid,
    input  logic       id_uses_rs1,
    input  logic       id_uses_rs2,
    input  logic [4:0] id_rs1_addr,
    input  logic [4:0] id_rs2_addr,
    input  logic       id_is_ecall,
    input  logic       idex_valid,
    input  logic       idex_mem_read,
    input  logic [4:0] idex_rd_addr,
    output logic       redirect_en,
    output logic       pc_hold,
    output logic       if_flush,
    output logic       idex_flush,
    output logic       exmem_flush,
    output logic       memwb_flush
);

    logic halt_pending;
    logic load_use;

    // Load-use hazard: the instruction in ID depends on the load currently in
    // EX. The load's data is not available until the end of MEM, so we must
    // stall exactly one cycle: hold PC and IF/ID (dependent instruction is
    // retained, NOT flushed) and inject a single bubble into ID/EX.
    assign load_use = ifid_valid & idex_valid & idex_mem_read &
                      (idex_rd_addr != 5'd0) &
                      ((id_uses_rs1 & (id_rs1_addr == idex_rd_addr)) |
                       (id_uses_rs2 & (id_rs2_addr == idex_rd_addr)));

    assign redirect_en = ex_redirect & ~halted;

    // Load-use: hold PC and IF/ID so the dependent instruction is retained,
    // and insert exactly one bubble into ID/EX (idex_flush).
    assign pc_hold    = halted | halt_pending | load_use;
    assign if_flush   = halted | halt_pending | redirect_en;
    assign idex_flush = halted | redirect_en | load_use;
    assign exmem_flush = halted;
    assign memwb_flush = halted;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halt_pending <= 1'b0;
        end else if (id_is_ecall & ifid_valid & ~redirect_en & ~halted) begin
            halt_pending <= 1'b1;
        end
    end

endmodule
