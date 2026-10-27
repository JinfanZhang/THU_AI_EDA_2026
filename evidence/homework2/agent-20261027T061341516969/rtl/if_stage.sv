module if_stage (
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    input  logic        pc_hold,
    input  logic        redirect_en,
    input  logic [31:0] redirect_pc,
    input  logic        if_flush,
    output logic        ifid_valid,
    output logic [31:0] ifid_pc,
    output logic [31:0] ifid_pc_plus4,
    output logic [31:0] ifid_instr
);

    logic [31:0] pc;

    assign imem_addr = pc;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc            <= 32'd0;
            ifid_valid    <= 1'b0;
            ifid_pc       <= 32'd0;
            ifid_pc_plus4 <= 32'd0;
            ifid_instr    <= 32'd0;
        end else if (redirect_en) begin
            pc            <= redirect_pc;
            ifid_valid    <= 1'b0;
            ifid_pc       <= 32'd0;
            ifid_pc_plus4 <= 32'd0;
            ifid_instr    <= 32'd0;
        end else if (pc_hold) begin
            pc            <= pc;
            ifid_valid    <= 1'b0;
            ifid_pc       <= 32'd0;
            ifid_pc_plus4 <= 32'd0;
            ifid_instr    <= 32'd0;
        end else begin
            pc            <= pc + 32'd4;
            ifid_valid    <= ~if_flush;
            ifid_pc       <= pc;
            ifid_pc_plus4 <= pc + 32'd4;
            ifid_instr    <= imem_rdata;
        end
    end

endmodule
