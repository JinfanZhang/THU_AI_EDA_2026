// rtl/forwarding_unit.sv
module forwarding_unit (
    input  logic [4:0] id_ex_rs1_addr,
    input  logic [4:0] id_ex_rs2_addr,
    input  logic       ex_mem_valid,
    input  logic       ex_mem_reg_write,
    input  logic [4:0] ex_mem_rd_addr,
    input  logic       mem_wb_valid,
    input  logic       mem_wb_reg_write,
    input  logic [4:0] mem_wb_rd_addr,
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    // Forwarding select encoding:
    // 2'b00 : no forwarding, use ID/EX register value
    // 2'b01 : forward from MEM/WB
    // 2'b10 : forward from EX/MEM

    always_comb begin
        // Default: no forwarding
        forward_a = 2'b00;
        forward_b = 2'b00;

        // Forward A (rs1)
        // EX/MEM has priority over MEM/WB.
        // Never forward when the destination register is x0 or when the
        // source register field is x0.
        if (ex_mem_valid && ex_mem_reg_write &&
            (ex_mem_rd_addr != 5'd0) &&
            (id_ex_rs1_addr != 5'd0) &&
            (ex_mem_rd_addr == id_ex_rs1_addr)) begin
            forward_a = 2'b10;  // EX/MEM
        end else if (mem_wb_valid && mem_wb_reg_write &&
                     (mem_wb_rd_addr != 5'd0) &&
                     (id_ex_rs1_addr != 5'd0) &&
                     (mem_wb_rd_addr == id_ex_rs1_addr)) begin
            forward_a = 2'b01;  // MEM/WB
        end

        // Forward B (rs2)
        // EX/MEM has priority over MEM/WB.
        // Never forward when the destination register is x0 or when the
        // source register field is x0.
        if (ex_mem_valid && ex_mem_reg_write &&
            (ex_mem_rd_addr != 5'd0) &&
            (id_ex_rs2_addr != 5'd0) &&
            (ex_mem_rd_addr == id_ex_rs2_addr)) begin
            forward_b = 2'b10;  // EX/MEM
        end else if (mem_wb_valid && mem_wb_reg_write &&
                     (mem_wb_rd_addr != 5'd0) &&
                     (id_ex_rs2_addr != 5'd0) &&
                     (mem_wb_rd_addr == id_ex_rs2_addr)) begin
            forward_b = 2'b01;  // MEM/WB
        end
    end

endmodule
