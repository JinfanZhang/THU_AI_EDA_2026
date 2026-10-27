module forwarding_unit (
    input  logic       ex_mem_valid,
    input  logic       ex_mem_reg_write,
    input  logic       ex_mem_mem_read,
    input  logic [4:0] ex_mem_rd,
    input  logic       wb_we,
    input  logic [4:0] wb_rd,
    input  logic [4:0] id_ex_rs1,
    input  logic [4:0] id_ex_rs2,
    output logic [1:0] fwd_a_sel,
    output logic [1:0] fwd_b_sel
);

    logic ex_mem_hit_a;
    logic ex_mem_hit_b;
    logic wb_hit_a;
    logic wb_hit_b;

    assign ex_mem_hit_a = ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read &&
                          (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1);
    assign ex_mem_hit_b = ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read &&
                          (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2);

    assign wb_hit_a = wb_we && (wb_rd != 5'd0) && (wb_rd == id_ex_rs1);
    assign wb_hit_b = wb_we && (wb_rd != 5'd0) && (wb_rd == id_ex_rs2);

    always_comb begin
        if (ex_mem_hit_a) begin
            fwd_a_sel = 2'b10;
        end else if (wb_hit_a) begin
            fwd_a_sel = 2'b01;
        end else begin
            fwd_a_sel = 2'b00;
        end

        if (ex_mem_hit_b) begin
            fwd_b_sel = 2'b10;
        end else if (wb_hit_b) begin
            fwd_b_sel = 2'b01;
        end else begin
            fwd_b_sel = 2'b00;
        end
    end

endmodule
