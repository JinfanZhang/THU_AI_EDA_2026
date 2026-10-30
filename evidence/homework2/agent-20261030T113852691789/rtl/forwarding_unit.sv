module forwarding_unit (
    input  logic [4:0] id_ex_rs1_addr,
    input  logic [4:0] id_ex_rs2_addr,
    input  logic       ex_mem_valid,
    input  logic       ex_mem_reg_write,
    input  logic       ex_mem_mem_read,
    input  logic [4:0] ex_mem_rd_addr,
    input  logic       mem_wb_valid,
    input  logic       mem_wb_reg_write,
    input  logic [4:0] mem_wb_rd_addr,
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    always_comb begin
        if (ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read &&
            (ex_mem_rd_addr != 5'd0) && (ex_mem_rd_addr == id_ex_rs1_addr)) begin
            forward_a = 2'd1;
        end else if (mem_wb_valid && mem_wb_reg_write &&
                     (mem_wb_rd_addr != 5'd0) && (mem_wb_rd_addr == id_ex_rs1_addr)) begin
            forward_a = 2'd2;
        end else begin
            forward_a = 2'd0;
        end
    end

    always_comb begin
        if (ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read &&
            (ex_mem_rd_addr != 5'd0) && (ex_mem_rd_addr == id_ex_rs2_addr)) begin
            forward_b = 2'd1;
        end else if (mem_wb_valid && mem_wb_reg_write &&
                     (mem_wb_rd_addr != 5'd0) && (mem_wb_rd_addr == id_ex_rs2_addr)) begin
            forward_b = 2'd2;
        end else begin
            forward_b = 2'd0;
        end
    end

endmodule
