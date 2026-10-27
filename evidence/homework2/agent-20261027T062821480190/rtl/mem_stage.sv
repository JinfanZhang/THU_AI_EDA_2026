module mem_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        halt,
    input  logic        ex_mem_valid,
    input  logic [31:0] ex_mem_result,
    input  logic [31:0] ex_mem_store_data,
    input  logic [4:0]  ex_mem_rs2,
    input  logic [4:0]  ex_mem_rd,
    input  logic        ex_mem_is_load,
    input  logic        ex_mem_is_store,
    input  logic [2:0]  ex_mem_mem_f3,
    input  logic        ex_mem_reg_write,
    input  logic        ex_mem_is_ecall,
    input  logic [31:0] dmem_rdata,
    input  logic        store_fwd,
    input  logic [31:0] mem_wb_wb_data,
    output logic        dmem_valid,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_be,
    output logic        mem_wb_valid,
    output logic [31:0] mem_wb_data,
    output logic [4:0]  mem_wb_rd,
    output logic        mem_wb_reg_write,
    output logic        mem_wb_is_ecall
);

    logic [31:0] store_data;
    logic [31:0] load_data;

    assign store_data = store_fwd ? mem_wb_wb_data : ex_mem_store_data;

    // Exactly one dmem_valid pulse per memory instruction; masked by reset and halt.
    // ex_mem_valid is a one-shot: the EX/MEM register is never frozen by a
    // load-use stall, so each in-flight memory op advances exactly once.
    assign dmem_valid = rst_n && !halt && ex_mem_valid &&
                        (ex_mem_is_load || ex_mem_is_store);
    assign dmem_we    = dmem_valid && ex_mem_is_store;
    assign dmem_addr  = ex_mem_result;

    always_comb begin
        dmem_wdata = 32'b0;
        dmem_be    = 4'b0000;
        if (ex_mem_is_store) begin
            case (ex_mem_mem_f3)
                3'b000: begin
                    dmem_wdata = {4{store_data[7:0]}};
                    dmem_be    = 4'b0001 << ex_mem_result[1:0];
                end
                3'b001: begin
                    dmem_wdata = {2{store_data[15:0]}};
                    dmem_be    = ex_mem_result[1] ? 4'b1100 : 4'b0011;
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
        byte_data = dmem_rdata[{ex_mem_result[1:0], 3'b000} +: 8];
        half_data = dmem_rdata[{ex_mem_result[1], 4'b0000} +: 16];
        case (ex_mem_mem_f3)
            3'b000:  load_data = {{24{byte_data[7]}}, byte_data};
            3'b001:  load_data = {{16{half_data[15]}}, half_data};
            3'b100:  load_data = {24'b0, byte_data};
            3'b101:  load_data = {16'b0, half_data};
            default: load_data = dmem_rdata;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_wb_valid      <= 1'b0;
            mem_wb_data       <= 32'b0;
            mem_wb_rd         <= 5'b0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_is_ecall   <= 1'b0;
        end else if (halt) begin
            mem_wb_valid      <= 1'b0;
            mem_wb_data       <= 32'b0;
            mem_wb_rd         <= 5'b0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_is_ecall   <= 1'b0;
        end else begin
            mem_wb_valid      <= ex_mem_valid;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_is_ecall   <= ex_mem_is_ecall;
            if (ex_mem_is_load)
                mem_wb_data <= load_data;
            else
                mem_wb_data <= ex_mem_result;
        end
    end

endmodule
