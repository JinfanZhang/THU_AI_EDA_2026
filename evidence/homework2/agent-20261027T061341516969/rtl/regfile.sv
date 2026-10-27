module regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [4:0]  id_rs1_addr,
    output logic [31:0] id_rs1_data,
    input  logic [4:0]  id_rs2_addr,
    output logic [31:0] id_rs2_data,
    input  logic        wb_we,
    input  logic [4:0]  wb_rd_addr,
    input  logic [31:0] wb_wb_data,
    input  logic [4:0]  dbg_reg_addr,
    output logic [31:0] dbg_reg_data,
    output logic [31:0] x10_value
);

    logic [31:0] regs [0:31];
    integer i;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'd0;
            end
        end else if (wb_we && (wb_rd_addr != 5'd0)) begin
            regs[wb_rd_addr] <= wb_wb_data;
        end
    end

    always_comb begin
        if (id_rs1_addr == 5'd0) begin
            id_rs1_data = 32'd0;
        end else if (wb_we && (wb_rd_addr != 5'd0) && (wb_rd_addr == id_rs1_addr)) begin
            id_rs1_data = wb_wb_data;
        end else begin
            id_rs1_data = regs[id_rs1_addr];
        end
    end

    always_comb begin
        if (id_rs2_addr == 5'd0) begin
            id_rs2_data = 32'd0;
        end else if (wb_we && (wb_rd_addr != 5'd0) && (wb_rd_addr == id_rs2_addr)) begin
            id_rs2_data = wb_wb_data;
        end else begin
            id_rs2_data = regs[id_rs2_addr];
        end
    end

    always_comb begin
        if (dbg_reg_addr == 5'd0) begin
            dbg_reg_data = 32'd0;
        end else begin
            dbg_reg_data = regs[dbg_reg_addr];
        end
    end

    assign x10_value = regs[10];

endmodule
