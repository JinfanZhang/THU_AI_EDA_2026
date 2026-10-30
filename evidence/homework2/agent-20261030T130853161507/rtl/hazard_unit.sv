module hazard_unit (
    input  logic [4:0] id_rs1_addr,
    input  logic [4:0] id_rs2_addr,
    input  logic       id_valid,
    input  logic [4:0] ex_rd_addr,
    input  logic       ex_reg_write,
    input  logic       ex_mem_read,
    output logic       stall
);

    always_comb begin
        stall = 1'b0;
        if (id_valid && ex_mem_read && ex_reg_write && (ex_rd_addr != 5'b0)) begin
            if ((id_rs1_addr == ex_rd_addr) || (id_rs2_addr == ex_rd_addr)) begin
                stall = 1'b1;
            end
        end
    end

endmodule
