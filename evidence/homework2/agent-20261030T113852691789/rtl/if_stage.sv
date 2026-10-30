module if_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        redirect,
    input  logic [31:0] redirect_pc,
    input  logic        stall,
    input  logic        freeze,
    input  logic [31:0] imem_rdata,
    output logic [31:0] imem_addr,
    output logic        if_id_valid,
    output logic [31:0] if_id_pc,
    output logic [31:0] if_id_pc_plus4,
    output logic [31:0] if_id_instr
);

    logic [31:0] pc;
    logic [31:0] pc_plus4;

    assign pc_plus4  = pc + 32'd4;
    assign imem_addr = {pc[31:2], 2'b00};

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc             <= 32'd0;
            if_id_valid    <= 1'b0;
            if_id_pc       <= 32'd0;
            if_id_pc_plus4 <= 32'd0;
            if_id_instr    <= 32'd0;
        end else if (redirect) begin
            pc             <= {redirect_pc[31:2], 2'b00};
            if_id_valid    <= 1'b0;
            if_id_pc       <= 32'd0;
            if_id_pc_plus4 <= 32'd0;
            if_id_instr    <= 32'd0;
        end else if (stall) begin
            // Load-use stall: HOLD PC and PRESERVE the dependent instruction
            // already sitting in IF/ID. It must be replayed, never discarded.
            pc             <= pc;
            if_id_valid    <= if_id_valid;
            if_id_pc       <= if_id_pc;
            if_id_pc_plus4 <= if_id_pc_plus4;
            if_id_instr    <= if_id_instr;
        end else if (freeze) begin
            pc             <= pc;
            if_id_valid    <= 1'b0;
            if_id_pc       <= 32'd0;
            if_id_pc_plus4 <= 32'd0;
            if_id_instr    <= 32'd0;
        end else begin
            pc             <= pc_plus4;
            if_id_valid    <= 1'b1;
            if_id_pc       <= pc;
            if_id_pc_plus4 <= pc_plus4;
            if_id_instr    <= imem_rdata;
        end
    end

endmodule
