module if_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        redirect,
    input  logic [31:0] redirect_pc,
    input  logic        stall,
    input  logic        kill,
    input  logic        pc_hold,
    input  logic [31:0] imem_rdata,
    output logic [31:0] imem_addr,
    output logic        ifid_valid,
    output logic [31:0] ifid_pc,
    output logic [31:0] ifid_pc4,
    output logic [31:0] ifid_instr
);

    logic [31:0] pc;

    assign imem_addr = pc;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc         <= 32'b0;
            ifid_valid <= 1'b0;
            ifid_pc    <= 32'b0;
            ifid_pc4   <= 32'b0;
            ifid_instr <= 32'b0;
        end else if (redirect) begin
            pc         <= redirect_pc;
            ifid_valid <= 1'b0;
            ifid_pc    <= 32'b0;
            ifid_pc4   <= 32'b0;
            ifid_instr <= 32'b0;
        end else if (stall) begin
            pc         <= pc;
            ifid_valid <= ifid_valid;
            ifid_pc    <= ifid_pc;
            ifid_pc4   <= ifid_pc4;
            ifid_instr <= ifid_instr;
        end else if (pc_hold) begin
            pc         <= pc;
            ifid_valid <= 1'b0;
            ifid_pc    <= 32'b0;
            ifid_pc4   <= 32'b0;
            ifid_instr <= 32'b0;
        end else if (kill) begin
            pc         <= pc + 32'd4;
            ifid_valid <= 1'b0;
            ifid_pc    <= 32'b0;
            ifid_pc4   <= 32'b0;
            ifid_instr <= 32'b0;
        end else begin
            pc         <= pc + 32'd4;
            ifid_valid <= 1'b1;
            ifid_pc    <= pc;
            ifid_pc4   <= pc + 32'd4;
            ifid_instr <= imem_rdata;
        end
    end

endmodule
