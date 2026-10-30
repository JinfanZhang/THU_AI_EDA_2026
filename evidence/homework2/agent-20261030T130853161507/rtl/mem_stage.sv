module mem_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ex_mem_valid,
    input  logic [31:0] ex_mem_pc,
    input  logic [31:0] ex_mem_insn,
    input  logic [31:0] ex_mem_pc_plus4,
    input  logic [31:0] ex_mem_alu_result,
    input  logic [31:0] ex_mem_rs2_val,
    input  logic [4:0]  ex_mem_rd_addr,
    input  logic        ex_mem_reg_write,
    input  logic        ex_mem_mem_read,
    input  logic        ex_mem_mem_write,
    input  logic        ex_mem_ecall,
    input  logic [1:0]  ex_mem_epoch,
    input  logic        cpu_resp_valid,
    input  logic [31:0] cpu_resp_rdata,
    input  logic        cpu_req_ready,
    output logic        cpu_req_valid,
    output logic        cpu_req_we,
    output logic [31:0] cpu_req_addr,
    output logic [31:0] cpu_req_wdata,
    output logic [3:0]  cpu_req_be,
    output logic        mem_wb_valid,
    output logic [31:0] mem_wb_pc,
    output logic [31:0] mem_wb_insn,
    output logic [31:0] mem_wb_pc_plus4,
    output logic [31:0] mem_wb_alu_result,
    output logic [31:0] mem_wb_load_data,
    output logic [4:0]  mem_wb_rd_addr,
    output logic        mem_wb_reg_write,
    output logic        mem_wb_ecall,
    output logic [1:0]  mem_wb_epoch,
    output logic        ex_mem_valid_out,
    output logic        ex_mem_reg_write_out,
    output logic [4:0]  ex_mem_rd_addr_out,
    output logic [31:0] ex_mem_alu_result_out
);

    // Internal state
    logic        mem_active;
    logic        mem_wait_resp;
    logic        mem_is_load;
    logic [31:0] mem_pc_r;
    logic [31:0] mem_insn_r;
    logic [31:0] mem_pc_plus4_r;
    logic [31:0] mem_alu_result_r;
    logic [31:0] mem_rs2_val_r;
    logic [4:0]  mem_rd_addr_r;
    logic        mem_reg_write_r;
    logic        mem_ecall_r;
    logic [1:0]  mem_epoch_r;
    logic [2:0]  mem_funct3_r;

    // Load data selection
    logic [31:0] load_data_raw;
    logic [31:0] load_data_ext;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_active      <= 1'b0;
            mem_wait_resp   <= 1'b0;
            mem_is_load     <= 1'b0;
            mem_pc_r        <= 32'b0;
            mem_insn_r      <= 32'b0;
            mem_pc_plus4_r  <= 32'b0;
            mem_alu_result_r<= 32'b0;
            mem_rs2_val_r   <= 32'b0;
            mem_rd_addr_r   <= 5'b0;
            mem_reg_write_r <= 1'b0;
            mem_ecall_r     <= 1'b0;
            mem_epoch_r     <= 2'b0;
            mem_funct3_r    <= 3'b0;
        end else begin
            if (mem_active) begin
                if (cpu_resp_valid) begin
                    mem_active      <= 1'b0;
                    mem_wait_resp   <= 1'b0;
                end else if (!mem_wait_resp && cpu_req_ready) begin
                    mem_wait_resp   <= 1'b1;
                end
            end else if (ex_mem_valid && (ex_mem_mem_read || ex_mem_mem_write)) begin
                mem_active      <= 1'b1;
                mem_wait_resp   <= 1'b0;
                mem_is_load     <= ex_mem_mem_read;
                mem_pc_r        <= ex_mem_pc;
                mem_insn_r      <= ex_mem_insn;
                mem_pc_plus4_r  <= ex_mem_pc_plus4;
                mem_alu_result_r<= ex_mem_alu_result;
                mem_rs2_val_r   <= ex_mem_rs2_val;
                mem_rd_addr_r   <= ex_mem_rd_addr;
                mem_reg_write_r <= ex_mem_reg_write;
                mem_ecall_r     <= ex_mem_ecall;
                mem_epoch_r     <= ex_mem_epoch;
                mem_funct3_r    <= ex_mem_insn[14:12];
            end
        end
    end

    // CPU request outputs
    always_comb begin
        cpu_req_valid = 1'b0;
        cpu_req_we    = 1'b0;
        cpu_req_addr  = 32'b0;
        cpu_req_wdata = 32'b0;
        cpu_req_be    = 4'b0;

        if (mem_active && !mem_wait_resp) begin
            cpu_req_valid = 1'b1;
            cpu_req_addr  = mem_alu_result_r;
            if (mem_is_load) begin
                cpu_req_we = 1'b0;
                cpu_req_wdata = 32'b0;
                cpu_req_be = 4'b0;
            end else begin
                cpu_req_we = 1'b1;
                case (mem_funct3_r)
                    3'b000: begin // SB
                        cpu_req_wdata = {4{mem_rs2_val_r[7:0]}};
                        cpu_req_be    = 4'b0001 << mem_alu_result_r[1:0];
                    end
                    3'b001: begin // SH
                        cpu_req_wdata = {2{mem_rs2_val_r[15:0]}};
                        cpu_req_be    = mem_alu_result_r[1] ? 4'b1100 : 4'b0011;
                    end
                    3'b010: begin // SW
                        cpu_req_wdata = mem_rs2_val_r;
                        cpu_req_be    = 4'b1111;
                    end
                    default: begin
                        cpu_req_wdata = mem_rs2_val_r;
                        cpu_req_be    = 4'b1111;
                    end
                endcase
            end
        end
    end

    // Load data extraction
    always_comb begin
        load_data_raw = cpu_resp_rdata;
        case (mem_funct3_r)
            3'b000: begin // LB
                case (mem_alu_result_r[1:0])
                    2'b00: load_data_raw = {{24{cpu_resp_rdata[7]}},  cpu_resp_rdata[7:0]};
                    2'b01: load_data_raw = {{24{cpu_resp_rdata[15]}}, cpu_resp_rdata[15:8]};
                    2'b10: load_data_raw = {{24{cpu_resp_rdata[23]}}, cpu_resp_rdata[23:16]};
                    2'b11: load_data_raw = {{24{cpu_resp_rdata[31]}}, cpu_resp_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH
                if (mem_alu_result_r[1])
                    load_data_raw = {{16{cpu_resp_rdata[31]}}, cpu_resp_rdata[31:16]};
                else
                    load_data_raw = {{16{cpu_resp_rdata[15]}}, cpu_resp_rdata[15:0]};
            end
            3'b010: begin // LW
                load_data_raw = cpu_resp_rdata;
            end
            3'b100: begin // LBU
                case (mem_alu_result_r[1:0])
                    2'b00: load_data_raw = {24'b0, cpu_resp_rdata[7:0]};
                    2'b01: load_data_raw = {24'b0, cpu_resp_rdata[15:8]};
                    2'b10: load_data_raw = {24'b0, cpu_resp_rdata[23:16]};
                    2'b11: load_data_raw = {24'b0, cpu_resp_rdata[31:24]};
                endcase
            end
            3'b101: begin // LHU
                if (mem_alu_result_r[1])
                    load_data_raw = {16'b0, cpu_resp_rdata[31:16]};
                else
                    load_data_raw = {16'b0, cpu_resp_rdata[15:0]};
            end
            default: load_data_raw = cpu_resp_rdata;
        endcase
    end

    // MEM/WB outputs
    always_comb begin
        mem_wb_valid       = 1'b0;
        mem_wb_pc          = 32'b0;
        mem_wb_insn        = 32'b0;
        mem_wb_pc_plus4    = 32'b0;
        mem_wb_alu_result  = 32'b0;
        mem_wb_load_data   = 32'b0;
        mem_wb_rd_addr     = 5'b0;
        mem_wb_reg_write   = 1'b0;
        mem_wb_ecall       = 1'b0;
        mem_wb_epoch       = 2'b0;

        if (mem_active && cpu_resp_valid) begin
            mem_wb_valid      = 1'b1;
            mem_wb_pc         = mem_pc_r;
            mem_wb_insn       = mem_insn_r;
            mem_wb_pc_plus4   = mem_pc_plus4_r;
            mem_wb_alu_result = mem_alu_result_r;
            mem_wb_load_data  = load_data_raw;
            mem_wb_rd_addr    = mem_rd_addr_r;
            mem_wb_reg_write  = mem_reg_write_r;
            mem_wb_ecall      = mem_ecall_r;
            mem_wb_epoch      = mem_epoch_r;
        end else if (ex_mem_valid && !ex_mem_mem_read && !ex_mem_mem_write) begin
            mem_wb_valid      = 1'b1;
            mem_wb_pc         = ex_mem_pc;
            mem_wb_insn       = ex_mem_insn;
            mem_wb_pc_plus4   = ex_mem_pc_plus4;
            mem_wb_alu_result = ex_mem_alu_result;
            mem_wb_load_data  = 32'b0;
            mem_wb_rd_addr    = ex_mem_rd_addr;
            mem_wb_reg_write  = ex_mem_reg_write;
            mem_wb_ecall      = ex_mem_ecall;
            mem_wb_epoch      = ex_mem_epoch;
        end
    end

    // Forwarding outputs for EX stage
    assign ex_mem_valid_out       = mem_active ? 1'b0 : ex_mem_valid;
    assign ex_mem_reg_write_out   = mem_active ? 1'b0 : ex_mem_reg_write;
    assign ex_mem_rd_addr_out     = mem_active ? 5'b0  : ex_mem_rd_addr;
    assign ex_mem_alu_result_out  = mem_active ? 32'b0 : ex_mem_alu_result;

endmodule
