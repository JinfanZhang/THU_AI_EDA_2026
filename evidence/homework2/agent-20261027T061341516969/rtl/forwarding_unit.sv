module forwarding_unit (
    input  logic        idex_valid,
    input  logic [4:0]  idex_rs1_addr,
    input  logic [4:0]  idex_rs2_addr,
    input  logic [31:0] idex_rs1_data,
    input  logic [31:0] idex_rs2_data,
    input  logic        exmem_valid,
    input  logic        exmem_reg_write,
    input  logic [4:0]  exmem_rd_addr,
    input  logic [31:0] exmem_alu_result,
    input  logic        memwb_valid,
    input  logic        memwb_reg_write,
    input  logic [4:0]  memwb_rd_addr,
    input  logic [31:0] memwb_wb_data,
    output logic [31:0] ex_rs1_data,
    output logic [31:0] ex_rs2_data
);

    logic exmem_hit_rs1;
    logic exmem_hit_rs2;
    logic memwb_hit_rs1;
    logic memwb_hit_rs2;

    always_comb begin
        exmem_hit_rs1 = exmem_valid && exmem_reg_write &&
                        (exmem_rd_addr != 5'd0) &&
                        (exmem_rd_addr == idex_rs1_addr);
        exmem_hit_rs2 = exmem_valid && exmem_reg_write &&
                        (exmem_rd_addr != 5'd0) &&
                        (exmem_rd_addr == idex_rs2_addr);
        memwb_hit_rs1 = memwb_valid && memwb_reg_write &&
                        (memwb_rd_addr != 5'd0) &&
                        (memwb_rd_addr == idex_rs1_addr);
        memwb_hit_rs2 = memwb_valid && memwb_reg_write &&
                        (memwb_rd_addr != 5'd0) &&
                        (memwb_rd_addr == idex_rs2_addr);
    end

    // EX/MEM has priority over MEM/WB (youngest producer wins).
    always_comb begin
        ex_rs1_data = idex_rs1_data;
        if (exmem_hit_rs1) begin
            ex_rs1_data = exmem_alu_result;
        end else if (memwb_hit_rs1) begin
            ex_rs1_data = memwb_wb_data;
        end
    end

    always_comb begin
        ex_rs2_data = idex_rs2_data;
        if (exmem_hit_rs2) begin
            ex_rs2_data = exmem_alu_result;
        end else if (memwb_hit_rs2) begin
            ex_rs2_data = memwb_wb_data;
        end
    end

endmodule
