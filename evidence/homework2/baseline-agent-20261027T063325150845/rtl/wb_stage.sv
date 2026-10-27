module wb_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] x10_data,
    input  logic        mem_wb_valid,
    input  logic        mem_wb_reg_write,
    input  logic [4:0]  mem_wb_rd,
    input  logic [1:0]  mem_wb_wb_sel,
    input  logic [31:0] mem_wb_alu_result,
    input  logic [31:0] mem_wb_pc4,
    input  logic [31:0] mem_wb_load_data,
    input  logic        mem_wb_is_ecall,
    output logic        wb_we,
    output logic [4:0]  wb_rd,
    output logic [31:0] wb_data,
    output logic        halted,
    output logic [31:0] exit_code
);

    localparam logic [1:0] WB_ALU  = 2'd0;
    localparam logic [1:0] WB_LOAD = 2'd1;
    localparam logic [1:0] WB_PC4  = 2'd2;

    logic [31:0] wb_data_sel;

    always_comb begin
        wb_data_sel = mem_wb_alu_result;
        case (mem_wb_wb_sel)
            WB_ALU:  wb_data_sel = mem_wb_alu_result;
            WB_LOAD: wb_data_sel = mem_wb_load_data;
            WB_PC4:  wb_data_sel = mem_wb_pc4;
            default: wb_data_sel = mem_wb_alu_result;
        endcase
    end

    always_comb begin
        wb_we   = mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0) && !halted;
        wb_rd   = mem_wb_rd;
        wb_data = wb_data_sel;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halted    <= 1'b0;
            exit_code <= 32'd0;
        end else if (!halted) begin
            if (mem_wb_valid && mem_wb_is_ecall) begin
                halted    <= 1'b1;
                exit_code <= x10_data;
            end
        end
    end

endmodule
