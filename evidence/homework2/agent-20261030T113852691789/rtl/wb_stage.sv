module wb_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem_wb_valid,
    input  logic [31:0] mem_wb_wb_data,
    input  logic [4:0]  mem_wb_rd_addr,
    input  logic        mem_wb_reg_write,
    input  logic        mem_wb_ecall,
    input  logic [31:0] x10_data,
    output logic        reg_write_en,
    output logic [4:0]  reg_write_addr,
    output logic [31:0] reg_write_data,
    output logic        halted,
    output logic [31:0] exit_code
);

    // Commit path: write enable/address/data all taken from the SAME mem_wb
    // pipeline register, in the same cycle, so the committed value is exactly
    // the one produced for this instruction (no off-by-one capture).
    assign reg_write_en   = mem_wb_valid && mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) && ~halted;
    assign reg_write_addr = mem_wb_rd_addr;
    assign reg_write_data = mem_wb_wb_data;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halted    <= 1'b0;
            exit_code <= 32'd0;
        end else if (mem_wb_valid && mem_wb_ecall && ~halted) begin
            halted    <= 1'b1;
            exit_code <= x10_data;
        end
    end

endmodule
