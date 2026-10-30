module mem_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        halted,
    input  logic        ex_mem_valid,
    input  logic [31:0] ex_mem_pc,
    input  logic [31:0] ex_mem_pc_plus4,
    input  logic [31:0] ex_mem_instr,
    input  logic [4:0]  ex_mem_rd,
    input  logic [4:0]  ex_mem_rs2,
    input  logic        ex_mem_reg_write,
    input  logic        ex_mem_mem_read,
    input  logic        ex_mem_mem_write,
    input  logic        ex_mem_is_load,
    input  logic        ex_mem_is_store,
    input  logic [1:0]  ex_mem_mem_size,
    input  logic [31:0] ex_mem_wb_data,
    input  logic [31:0] ex_mem_store_data,
    input  logic [31:0] ex_mem_alu_result,
    input  logic        ex_mem_is_ecall,
    input  logic        wb_ready,
    output logic        mem_wb_valid,
    output logic [31:0] mem_wb_pc,
    output logic [31:0] mem_wb_instr,
    output logic [4:0]  mem_wb_rd,
    output logic        mem_wb_reg_write,
    output logic [31:0] mem_wb_wb_data,
    output logic        mem_wb_is_ecall,
    output logic        mem_stage_stall,
    output logic        cpu_req_valid,
    output logic        cpu_req_we,
    output logic [31:0] cpu_req_addr,
    output logic [31:0] cpu_req_wdata,
    output logic [3:0]  cpu_req_be,
    input  logic        cpu_req_ready,
    input  logic        cpu_resp_valid,
    input  logic [31:0] cpu_resp_rdata
);

    localparam logic [1:0] SZ_B = 2'b00;
    localparam logic [1:0] SZ_H = 2'b01;
    localparam logic [1:0] SZ_W = 2'b10;

    logic [31:0] store_wdata;
    logic [3:0]  store_be;
    logic [31:0] load_data;

    // Byte-enable / store-data generation for the active memory op.
    always_comb begin
        store_wdata = ex_mem_store_data;
        store_be    = 4'b0000;
        if (ex_mem_mem_write) begin
            case (ex_mem_mem_size)
                SZ_B: begin
                    store_wdata = {4{ex_mem_store_data[7:0]}};
                    store_be    = 4'b0001 << ex_mem_alu_result[1:0];
                end
                SZ_H: begin
                    store_wdata = {2{ex_mem_store_data[15:0]}};
                    store_be    = ex_mem_alu_result[1] ? 4'b1100 : 4'b0011;
                end
                default: begin
                    store_wdata = ex_mem_store_data;
                    store_be    = 4'b1111;
                end
            endcase
        end
    end

    // Request presented to the D-cache.  The D-cache is a single-cycle
    // slave: the response is valid in the SAME cycle the request is
    // accepted (cpu_req_ready high).  The request fields are derived
    // from the EX/MEM register; the pipeline is frozen via
    // mem_stage_stall only while the request is not yet accepted.
    always_comb begin
        cpu_req_valid = 1'b0;
        cpu_req_we    = 1'b0;
        cpu_req_addr  = 32'b0;
        cpu_req_wdata = 32'b0;
        cpu_req_be    = 4'b0000;
        if (rst_n && !halted && ex_mem_valid &&
            (ex_mem_mem_read || ex_mem_mem_write)) begin
            cpu_req_valid = 1'b1;
            cpu_req_we    = ex_mem_mem_write;
            cpu_req_addr  = ex_mem_alu_result;
            cpu_req_wdata = store_wdata;
            cpu_req_be    = store_be;
        end
    end

    // Stall MEM (and hence the whole pipeline) while a memory request is
    // outstanding and the D-cache has not accepted it yet.  This freezes
    // EX/MEM so the request stays bit-identical until ready.
    assign mem_stage_stall = cpu_req_valid & ~cpu_req_ready;

    always_comb begin
        load_data = 32'b0;
        case (ex_mem_mem_size)
            SZ_B: begin
                case (ex_mem_alu_result[1:0])
                    2'b00: load_data = {{24{cpu_resp_rdata[7]}},  cpu_resp_rdata[7:0]};
                    2'b01: load_data = {{24{cpu_resp_rdata[15]}}, cpu_resp_rdata[15:8]};
                    2'b10: load_data = {{24{cpu_resp_rdata[23]}}, cpu_resp_rdata[23:16]};
                    default: load_data = {{24{cpu_resp_rdata[31]}}, cpu_resp_rdata[31:24]};
                endcase
            end
            SZ_H: begin
                if (ex_mem_alu_result[1]) begin
                    load_data = {{16{cpu_resp_rdata[31]}}, cpu_resp_rdata[31:16]};
                end else begin
                    load_data = {{16{cpu_resp_rdata[15]}}, cpu_resp_rdata[15:0]};
                end
            end
            default: begin
                load_data = cpu_resp_rdata;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_wb_valid    <= 1'b0;
            mem_wb_pc       <= 32'b0;
            mem_wb_instr    <= 32'b0;
            mem_wb_rd       <= 5'b0;
            mem_wb_reg_write<= 1'b0;
            mem_wb_wb_data  <= 32'b0;
            mem_wb_is_ecall <= 1'b0;
        end else if (halted) begin
            mem_wb_valid    <= 1'b0;
            mem_wb_reg_write<= 1'b0;
            mem_wb_is_ecall <= 1'b0;
        end else if (mem_stage_stall) begin
            // Hold MEM/WB while the outstanding access is not yet accepted.
            mem_wb_valid    <= 1'b0;
            mem_wb_reg_write<= 1'b0;
            mem_wb_is_ecall <= 1'b0;
        end else begin
            mem_wb_valid    <= 1'b0;
            mem_wb_reg_write<= 1'b0;
            mem_wb_is_ecall <= 1'b0;

            if (ex_mem_valid) begin
                mem_wb_valid     <= 1'b1;
                mem_wb_pc        <= ex_mem_pc;
                mem_wb_instr     <= ex_mem_instr;
                // Single-cycle memory: the load data is available in the
                // same cycle the request is accepted, so capture it now.
                mem_wb_wb_data   <= ex_mem_mem_read ? load_data : ex_mem_wb_data;
                mem_wb_rd        <= ex_mem_rd;
                mem_wb_reg_write <= ex_mem_reg_write;
                // Carry the ECALL flag through MEM/WB together with the
                // instruction word so WB can commit it exactly once.
                mem_wb_is_ecall  <= ex_mem_is_ecall &&
                                    (ex_mem_instr == 32'h0000_0073);
            end
        end
    end

endmodule
