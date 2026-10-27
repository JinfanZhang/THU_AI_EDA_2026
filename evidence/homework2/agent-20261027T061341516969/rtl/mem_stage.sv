module mem_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        exmem_valid,
    input  logic [31:0] exmem_pc_plus4,
    input  logic [31:0] exmem_alu_result,
    input  logic [31:0] exmem_rs2_data,
    input  logic [4:0]  exmem_rs2_addr,
    input  logic [4:0]  exmem_rd_addr,
    input  logic        exmem_reg_write,
    input  logic        exmem_mem_read,
    input  logic        exmem_mem_write,
    input  logic [1:0]  exmem_mem_size,
    input  logic        exmem_mem_unsign,
    input  logic [1:0]  exmem_wb_sel,
    input  logic        exmem_is_ecall,
    input  logic [31:0] dmem_rdata,
    input  logic        memwb_flush,
    output logic        memwb_valid,
    output logic [31:0] memwb_wb_data,
    output logic [4:0]  memwb_rd_addr,
    output logic        memwb_reg_write,
    output logic        memwb_is_ecall,
    output logic        dmem_valid,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_be
);

    logic [31:0] store_data;
    logic [31:0] load_data;
    logic [31:0] wb_data_mux;

    // Byte/half lane selection wires (constant part-selects moved out of
    // procedural always_* blocks into continuous assigns for iverilog).
    logic [7:0]  byte_sel;
    logic [15:0] half_sel;

    // Store-data forwarding mux: memwb (youngest) > exmem_rs2_data.
    // The value to be stored may be produced by an immediately preceding
    // load/ALU instruction that is still in WB, so it must be forwarded
    // into the store data path here in MEM.
    always @(*) begin
        store_data = exmem_rs2_data;
        if (memwb_valid && memwb_reg_write && (memwb_rd_addr != 5'd0) &&
            (memwb_rd_addr == exmem_rs2_addr)) begin
            store_data = memwb_wb_data;
        end
    end

    // Store byte-lane replication / byte-enable generation.
    // dmem_valid covers both loads and stores and is combinationally gated
    // by rst_n so it is a defined 0 before the first reset edge.
    always @(*) begin
        dmem_valid = rst_n & exmem_valid & (exmem_mem_read | exmem_mem_write);
        dmem_we    = exmem_mem_write;
        dmem_addr  = exmem_alu_result;
        dmem_wdata = 32'd0;
        dmem_be    = 4'b0000;
        if (exmem_mem_write) begin
            case (exmem_mem_size)
                2'd0: begin
                    dmem_wdata = {4{store_data[7:0]}};
                    dmem_be    = 4'b0001 << exmem_alu_result[1:0];
                end
                2'd1: begin
                    dmem_wdata = {2{store_data[15:0]}};
                    dmem_be    = exmem_alu_result[1] ? 4'b1100 : 4'b0011;
                end
                default: begin
                    dmem_wdata = store_data;
                    dmem_be    = 4'b1111;
                end
            endcase
        end
    end

    // Load lane extraction via continuous assigns
    assign byte_sel = (exmem_alu_result[1:0] == 2'd0) ? dmem_rdata[7:0]  :
                      (exmem_alu_result[1:0] == 2'd1) ? dmem_rdata[15:8] :
                      (exmem_alu_result[1:0] == 2'd2) ? dmem_rdata[23:16] :
                                                        dmem_rdata[31:24];
    assign half_sel = exmem_alu_result[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];

    // Load sign/zero extension
    always @(*) begin
        case (exmem_mem_size)
            2'd0: begin
                if (exmem_mem_unsign)
                    load_data = {24'd0, byte_sel};
                else
                    load_data = {{24{byte_sel[7]}}, byte_sel};
            end
            2'd1: begin
                if (exmem_mem_unsign)
                    load_data = {16'd0, half_sel};
                else
                    load_data = {{16{half_sel[15]}}, half_sel};
            end
            default: load_data = dmem_rdata;
        endcase
    end

    // Writeback data mux
    always @(*) begin
        case (exmem_wb_sel)
            2'd0:    wb_data_mux = exmem_alu_result;
            2'd1:    wb_data_mux = load_data;
            default: wb_data_mux = exmem_pc_plus4;
        endcase
    end

    // MEM/WB pipeline register (synchronous active-low reset)
    always @(posedge clk) begin
        if (!rst_n) begin
            memwb_valid      <= 1'b0;
            memwb_wb_data    <= 32'd0;
            memwb_rd_addr    <= 5'd0;
            memwb_reg_write  <= 1'b0;
            memwb_is_ecall   <= 1'b0;
        end else if (memwb_flush) begin
            memwb_valid      <= 1'b0;
            memwb_wb_data    <= 32'd0;
            memwb_rd_addr    <= 5'd0;
            memwb_reg_write  <= 1'b0;
            memwb_is_ecall   <= 1'b0;
        end else begin
            memwb_valid      <= exmem_valid;
            memwb_wb_data    <= wb_data_mux;
            memwb_rd_addr    <= exmem_rd_addr;
            memwb_reg_write  <= exmem_reg_write;
            memwb_is_ecall   <= exmem_is_ecall;
        end
    end

endmodule
