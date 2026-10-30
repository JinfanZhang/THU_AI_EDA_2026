module prf (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [5:0]  alu_read1_addr,
    output logic [31:0] alu_read1_data,
    input  logic [5:0]  alu_read2_addr,
    output logic [31:0] alu_read2_data,
    input  logic [5:0]  lsu_read1_addr,
    output logic [31:0] lsu_read1_data,
    input  logic [5:0]  lsu_read2_addr,
    output logic [31:0] lsu_read2_data,
    input  logic        write_valid_alu,
    input  logic [5:0]  write_pr_alu,
    input  logic [31:0] write_data_alu,
    input  logic        write_valid_lsu,
    input  logic [5:0]  write_pr_lsu,
    input  logic [31:0] write_data_lsu
);

    localparam PRF_DEPTH = 40;
    logic [31:0] regs [PRF_DEPTH];

    // Write ports with explicit per-entry reset logic.
    // Icarus Verilog 12 does not support whole-array or array-slice
    // assignment inside always_ff, so each physical register is reset
    // individually without using a procedural loop.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            regs[0]  <= 32'b0;
            regs[1]  <= 32'b0;
            regs[2]  <= 32'b0;
            regs[3]  <= 32'b0;
            regs[4]  <= 32'b0;
            regs[5]  <= 32'b0;
            regs[6]  <= 32'b0;
            regs[7]  <= 32'b0;
            regs[8]  <= 32'b0;
            regs[9]  <= 32'b0;
            regs[10] <= 32'b0;
            regs[11] <= 32'b0;
            regs[12] <= 32'b0;
            regs[13] <= 32'b0;
            regs[14] <= 32'b0;
            regs[15] <= 32'b0;
            regs[16] <= 32'b0;
            regs[17] <= 32'b0;
            regs[18] <= 32'b0;
            regs[19] <= 32'b0;
            regs[20] <= 32'b0;
            regs[21] <= 32'b0;
            regs[22] <= 32'b0;
            regs[23] <= 32'b0;
            regs[24] <= 32'b0;
            regs[25] <= 32'b0;
            regs[26] <= 32'b0;
            regs[27] <= 32'b0;
            regs[28] <= 32'b0;
            regs[29] <= 32'b0;
            regs[30] <= 32'b0;
            regs[31] <= 32'b0;
            regs[32] <= 32'b0;
            regs[33] <= 32'b0;
            regs[34] <= 32'b0;
            regs[35] <= 32'b0;
            regs[36] <= 32'b0;
            regs[37] <= 32'b0;
            regs[38] <= 32'b0;
            regs[39] <= 32'b0;
        end else begin
            if (write_valid_alu && write_pr_alu != 6'd0) begin
                regs[write_pr_alu] <= write_data_alu;
            end
            if (write_valid_lsu && write_pr_lsu != 6'd0) begin
                regs[write_pr_lsu] <= write_data_lsu;
            end
        end
    end

    // Read ports (combinational, x0 reads as 0)
    assign alu_read1_data = (alu_read1_addr == 6'd0) ? 32'b0 : regs[alu_read1_addr];
    assign alu_read2_data = (alu_read2_addr == 6'd0) ? 32'b0 : regs[alu_read2_addr];
    assign lsu_read1_data = (lsu_read1_addr == 6'd0) ? 32'b0 : regs[lsu_read1_addr];
    assign lsu_read2_data = (lsu_read2_addr == 6'd0) ? 32'b0 : regs[lsu_read2_addr];

endmodule
