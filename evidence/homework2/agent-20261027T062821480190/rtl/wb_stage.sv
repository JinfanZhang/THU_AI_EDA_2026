module wb_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem_wb_valid,
    input  logic [31:0] mem_wb_data,
    input  logic [4:0]  mem_wb_rd,
    input  logic        mem_wb_reg_write,
    input  logic        mem_wb_is_ecall,
    input  logic [31:0] x10_value,
    output logic        rf_we,
    output logic [4:0]  rf_waddr,
    output logic [31:0] rf_wdata,
    output logic        halt_commit,
    output logic        halted,
    output logic [31:0] exit_code
);

    assign halt_commit = mem_wb_valid && mem_wb_is_ecall;

    assign rf_we    = mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0) && !halted && !halt_commit;
    assign rf_waddr = mem_wb_rd;
    assign rf_wdata = mem_wb_data;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halted    <= 1'b0;
            exit_code <= 32'd0;
        end else if (halt_commit) begin
            halted    <= 1'b1;
            exit_code <= x10_value;
        end
    end

endmodule
