module mem_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ex_mem_valid,
    input  logic [31:0] ex_mem_pc,
    input  logic [31:0] ex_mem_alu_result,
    input  logic [31:0] ex_mem_wb_data,
    input  logic [31:0] ex_mem_store_data,
    input  logic [4:0]  ex_mem_rd_addr,
    input  logic [4:0]  ex_mem_rs2_addr,
    input  logic        ex_mem_reg_write,
    input  logic        ex_mem_mem_read,
    input  logic        ex_mem_mem_write,
    input  logic [1:0]  ex_mem_mem_size,
    input  logic        ex_mem_mem_unsigned,
    input  logic        ex_mem_ecall,
    input  logic [31:0] dmem_rdata,
    output logic [31:0] mem_dmem_addr,
    output logic [31:0] mem_dmem_wdata,
    output logic [3:0]  mem_dmem_be,
    output logic        mem_dmem_we,
    output logic        mem_dmem_valid,
    output logic        mem_wb_valid,
    output logic [31:0] mem_wb_wb_data,
    output logic [4:0]  mem_wb_rd_addr,
    output logic        mem_wb_reg_write,
    output logic        mem_wb_ecall
);

    localparam logic [1:0] MEM_SIZE_B = 2'd0;
    localparam logic [1:0] MEM_SIZE_H = 2'd1;
    localparam logic [1:0] MEM_SIZE_W = 2'd2;

    logic [31:0] store_data_fwd;
    logic [31:0] load_data_ext;
    logic [31:0] mem_wb_wb_data_next;

    always_comb begin
        store_data_fwd = ex_mem_store_data;
        if (mem_wb_valid && mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) &&
            (mem_wb_rd_addr == ex_mem_rs2_addr)) begin
            store_data_fwd = mem_wb_wb_data;
        end
    end

    always_comb begin
        mem_dmem_valid = ex_mem_valid && (ex_mem_mem_read || ex_mem_mem_write);
        mem_dmem_we    = ex_mem_valid && ex_mem_mem_write;
        mem_dmem_addr  = ex_mem_alu_result;

        mem_dmem_wdata = 32'd0;
        mem_dmem_be    = 4'b0000;
        if (ex_mem_mem_write) begin
            case (ex_mem_mem_size)
                MEM_SIZE_B: begin
                    mem_dmem_wdata = {4{store_data_fwd[7:0]}};
                    mem_dmem_be    = 4'b0001 << ex_mem_alu_result[1:0];
                end
                MEM_SIZE_H: begin
                    mem_dmem_wdata = {2{store_data_fwd[15:0]}};
                    mem_dmem_be    = ex_mem_alu_result[1] ? 4'b1100 : 4'b0011;
                end
                default: begin
                    mem_dmem_wdata = store_data_fwd;
                    mem_dmem_be    = 4'b1111;
                end
            endcase
        end
    end

    always_comb begin
        load_data_ext = dmem_rdata;
        case (ex_mem_mem_size)
            MEM_SIZE_B: begin
                case (ex_mem_alu_result[1:0])
                    2'd0: load_data_ext = {{24{dmem_rdata[7]  & ~ex_mem_mem_unsigned}}, dmem_rdata[7:0]};
                    2'd1: load_data_ext = {{24{dmem_rdata[15] & ~ex_mem_mem_unsigned}}, dmem_rdata[15:8]};
                    2'd2: load_data_ext = {{24{dmem_rdata[23] & ~ex_mem_mem_unsigned}}, dmem_rdata[23:16]};
                    default: load_data_ext = {{24{dmem_rdata[31] & ~ex_mem_mem_unsigned}}, dmem_rdata[31:24]};
                endcase
            end
            MEM_SIZE_H: begin
                if (ex_mem_alu_result[1])
                    load_data_ext = {{16{dmem_rdata[31] & ~ex_mem_mem_unsigned}}, dmem_rdata[31:16]};
                else
                    load_data_ext = {{16{dmem_rdata[15] & ~ex_mem_mem_unsigned}}, dmem_rdata[15:0]};
            end
            default: begin
                load_data_ext = dmem_rdata;
            end
        endcase
    end

    always_comb begin
        mem_wb_wb_data_next = ex_mem_wb_data;
        if (ex_mem_mem_read) begin
            mem_wb_wb_data_next = load_data_ext;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_wb_valid     <= 1'b0;
            mem_wb_wb_data   <= 32'd0;
            mem_wb_rd_addr   <= 5'd0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_ecall     <= 1'b0;
        end else begin
            mem_wb_valid     <= ex_mem_valid;
            mem_wb_wb_data   <= mem_wb_wb_data_next;
            mem_wb_rd_addr   <= ex_mem_rd_addr;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_ecall     <= ex_mem_ecall;
        end
    end

endmodule
