module hazard_unit (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       id_valid,
    input  logic       id_ecall,
    input  logic [4:0] id_rs1_addr,
    input  logic [4:0] id_rs2_addr,
    input  logic       id_rs1_used,
    input  logic       id_rs2_used,
    input  logic       id_ex_valid,
    input  logic       id_ex_mem_read,
    input  logic [4:0] id_ex_rd_addr,
    input  logic       ex_redirect,
    input  logic       halted,
    output logic       load_use_stall,
    output logic       halt_pending
);

    always_comb begin
        load_use_stall = id_ex_valid && id_ex_mem_read &&
                         (id_ex_rd_addr != 5'd0) && id_valid &&
                         ((id_rs1_used && (id_rs1_addr == id_ex_rd_addr)) ||
                          (id_rs2_used && (id_rs2_addr == id_ex_rd_addr)));
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halt_pending <= 1'b0;
        end else if (id_valid && id_ecall && !ex_redirect && !halt_pending && !halted) begin
            halt_pending <= 1'b1;
        end
    end

endmodule
