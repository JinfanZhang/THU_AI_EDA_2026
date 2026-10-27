module wb_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        memwb_valid,
    input  logic [31:0] memwb_wb_data,
    input  logic [4:0]  memwb_rd_addr,
    input  logic        memwb_reg_write,
    input  logic        memwb_is_ecall,
    input  logic [31:0] x10_value,
    output logic        wb_we,
    output logic [4:0]  wb_rd_addr,
    output logic [31:0] wb_wb_data,
    output logic        halted,
    output logic [31:0] exit_code
);

    assign wb_we      = memwb_valid & memwb_reg_write & (memwb_rd_addr != 5'd0);
    assign wb_rd_addr = memwb_rd_addr;
    assign wb_wb_data = memwb_wb_data;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halted    <= 1'b0;
            exit_code <= 32'd0;
        end else if (memwb_valid && memwb_is_ecall) begin
            halted    <= 1'b1;
            exit_code <= x10_value;
        end
    end

endmodule
