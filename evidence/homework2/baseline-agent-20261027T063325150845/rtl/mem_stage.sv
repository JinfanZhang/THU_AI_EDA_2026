module mem_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        halted,
    input  logic [31:0] dmem_rdata,
    input  logic        wb_we,
    input  logic [4:0]  wb_rd,
    input  logic [31:0] wb_data,
    input  logic        ex_mem_valid,
    input  logic [31:0] ex_mem_pc4,
    input  logic [4:0]  ex_mem_rd,
    input  logic [31:0] ex_mem_alu_result,
    input  logic [31:0] ex_mem_rs2_data,
    input  logic [4:0]  ex_mem_rs2,
    input  logic        ex_mem_reg_write,
    input  logic        ex_mem_mem_read,
    input  logic        ex_mem_mem_write,
    input  logic [2:0]  ex_mem_mem_size,
    input  logic [1:0]  ex_mem_wb_sel,
    input  logic        ex_mem_is_ecall,
    output logic        dmem_valid,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_be,
    output logic        mem_wb_valid,
    output logic        mem_wb_reg_write,
    output logic [4:0]  mem_wb_rd,
    output logic [1:0]  mem_wb_wb_sel,
    output logic [31:0] mem_wb_alu_result,
    output logic [31:0] mem_wb_pc4,
    output logic [31:0] mem_wb_load_data,
    output logic        mem_wb_is_ecall
);

    localparam logic [1:0] WB_ALU  = 2'd0;
    localparam logic [1:0] WB_LOAD = 2'd1;
    localparam logic [1:0] WB_PC4  = 2'd2;

    logic [31:0] store_data;
    logic [31:0] load_data;

    always_comb begin
        store_data = ex_mem_rs2_data;
        if (wb_we && (wb_rd != 5'd0) && (wb_rd == ex_mem_rs2)) begin
            store_data = wb_data;
        end
    end

    always_comb begin
        dmem_valid = rst_n && !halted && ex_mem_valid &&
                     (ex_mem_mem_read || ex_mem_mem_write);
        dmem_we    = ex_mem_mem_write;
        dmem_addr  = ex_mem_alu_result;
        dmem_wdata = store_data;
        dmem_be    = 4'b0000;
        if (ex_mem_mem_write) begin
            case (ex_mem_mem_size)
                3'b000: begin
                    dmem_wdata = {4{store_data[7:0]}};
                    dmem_be    = 4'b0001 << ex_mem_alu_result[1:0];
                end
                3'b001: begin
                    dmem_wdata = {2{store_data[15:0]}};
                    dmem_be    = ex_mem_alu_result[1] ? 4'b1100 : 4'b0011;
                end
                default: begin
                    dmem_wdata = store_data;
                    dmem_be    = 4'b1111;
                end
            endcase
        end
    end

    always_comb begin
        logic [7:0]  byte_data;
        logic [15:0] half_data;
        byte_data = dmem_rdata[{ex_mem_alu_result[1:0], 3'b000} +: 8];
        half_data = dmem_rdata[{ex_mem_alu_result[1], 4'b0000} +: 16];
        case (ex_mem_mem_size)
            3'b000:  load_data = {{24{byte_data[7]}}, byte_data};
            3'b001:  load_data = {{16{half_data[15]}}, half_data};
            3'b100:  load_data = {24'b0, byte_data};
            3'b101:  load_data = {16'b0, half_data};
            default: load_data = dmem_rdata;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_wb_valid     <= 1'b0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_rd        <= 5'd0;
            mem_wb_wb_sel    <= WB_ALU;
            mem_wb_alu_result<= 32'd0;
            mem_wb_pc4       <= 32'd0;
            mem_wb_load_data <= 32'd0;
            mem_wb_is_ecall  <= 1'b0;
        end else if (halted) begin
            mem_wb_valid     <= 1'b0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_rd        <= 5'd0;
            mem_wb_wb_sel    <= WB_ALU;
            mem_wb_alu_result<= 32'd0;
            mem_wb_pc4       <= 32'd0;
            mem_wb_load_data <= 32'd0;
            mem_wb_is_ecall  <= 1'b0;
        end else begin
            mem_wb_valid     <= ex_mem_valid;
            mem_wb_reg_write <= ex_mem_valid && ex_mem_reg_write;
            mem_wb_rd        <= ex_mem_rd;
            mem_wb_wb_sel    <= ex_mem_wb_sel;
            mem_wb_alu_result<= ex_mem_alu_result;
            mem_wb_pc4       <= ex_mem_pc4;
            mem_wb_load_data <= load_data;
            mem_wb_is_ecall  <= ex_mem_valid && ex_mem_is_ecall;
        end
    end

endmodule
