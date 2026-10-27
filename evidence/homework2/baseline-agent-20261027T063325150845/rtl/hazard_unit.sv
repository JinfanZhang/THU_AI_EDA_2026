module hazard_unit (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       id_valid,
    input  logic       id_ecall,
    input  logic       id_uses_rs1,
    input  logic       id_uses_rs2,
    input  logic [4:0] id_rs1,
    input  logic [4:0] id_rs2,
    input  logic       ex_valid,
    input  logic       ex_mem_read,
    input  logic [4:0] ex_rd,
    input  logic       redirect,
    input  logic       halted,
    output logic       stall,
    output logic       flush_if_id,
    output logic       flush_id_ex,
    output logic       halt_pending
);

    logic load_use;
    logic ecall_enter;

    always_comb begin
        load_use = 1'b0;
        if (ex_valid && ex_mem_read && (ex_rd != 5'd0) && id_valid) begin
            if ((id_uses_rs1 && (id_rs1 == ex_rd)) ||
                (id_uses_rs2 && (id_rs2 == ex_rd))) begin
                load_use = 1'b1;
            end
        end
    end

    always_comb begin
        ecall_enter = id_valid && id_ecall && !halt_pending && !redirect && !halted;
    end

    always_comb begin
        stall       = load_use && !redirect && !halt_pending && !halted;
        flush_if_id = redirect || halt_pending || halted;
        flush_id_ex = redirect || halt_pending || halted || (load_use && !redirect && !halt_pending && !halted);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halt_pending <= 1'b0;
        end else if (halted) begin
            halt_pending <= 1'b0;
        end else if (ecall_enter) begin
            halt_pending <= 1'b1;
        end
    end

endmodule
