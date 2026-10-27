module if_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,
    input  logic        flush,
    input  logic        redirect,
    input  logic [31:0] redirect_target,
    input  logic [31:0] imem_rdata,
    output logic [31:0] imem_addr,
    output logic        if_valid,
    output logic [31:0] if_pc,
    output logic [31:0] if_pc4,
    output logic [31:0] if_instr
);

    logic [31:0] pc;
    logic [31:0] ifid_pc;
    logic [31:0] ifid_pc4;
    logic [31:0] ifid_instr;
    logic        ifid_valid;

    assign imem_addr = pc;

    assign if_valid = ifid_valid;
    assign if_pc    = ifid_pc;
    assign if_pc4   = ifid_pc4;
    assign if_instr = ifid_instr;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc         <= 32'h0000_0000;
            ifid_valid <= 1'b0;
            ifid_pc    <= 32'h0000_0000;
            ifid_pc4   <= 32'h0000_0000;
            ifid_instr <= 32'h0000_0000;
        end else if (redirect) begin
            pc         <= redirect_target;
            ifid_valid <= 1'b0;
            ifid_pc    <= 32'h0000_0000;
            ifid_pc4   <= 32'h0000_0000;
            ifid_instr <= 32'h0000_0000;
        end else if (stall) begin
            pc         <= pc;
            ifid_valid <= ifid_valid;
            ifid_pc    <= ifid_pc;
            ifid_pc4   <= ifid_pc4;
            ifid_instr <= ifid_instr;
        end else if (flush) begin
            pc         <= pc;
            ifid_valid <= 1'b0;
            ifid_pc    <= pc;
            ifid_pc4   <= pc + 32'd4;
            ifid_instr <= imem_rdata;
        end else begin
            pc         <= pc + 32'd4;
            ifid_valid <= 1'b1;
            ifid_pc    <= pc;
            ifid_pc4   <= pc + 32'd4;
            ifid_instr <= imem_rdata;
        end
    end

endmodule
