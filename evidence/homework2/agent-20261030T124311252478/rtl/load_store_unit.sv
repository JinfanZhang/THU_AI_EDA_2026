// rtl/load_store_unit.sv
module load_store_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        lsu_issue_valid,
    input  logic [5:0]  lsu_issue_prs1,
    input  logic [5:0]  lsu_issue_prs2,
    input  logic [5:0]  lsu_issue_prd,
    input  logic [2:0]  lsu_issue_rob_idx,
    input  logic [31:0] lsu_issue_imm,
    input  logic [3:0]  lsu_issue_op_type,
    input  logic [2:0]  lsu_issue_func3,
    input  logic [31:0] lsu_issue_pc,
    output logic [5:0]  prf_read1_addr,
    input  logic [31:0] prf_read1_data,
    output logic [5:0]  prf_read2_addr,
    input  logic [31:0] prf_read2_data,
    output logic        prf_write_valid,
    output logic [5:0]  prf_write_pr,
    output logic [31:0] prf_write_data,
    output logic        dcache_cpu_req_valid,
    output logic        dcache_cpu_req_we,
    output logic [31:0] dcache_cpu_req_addr,
    output logic [31:0] dcache_cpu_req_wdata,
    output logic [3:0]  dcache_cpu_req_be,
    input  logic        dcache_cpu_req_ready,
    input  logic        dcache_cpu_resp_valid,
    input  logic [31:0] dcache_cpu_resp_rdata,
    output logic        dcache_flush,
    output logic [1:0]  dcache_flush_epoch,
    input  logic [1:0]  rob_epoch,
    input  logic        rob_flush,
    output logic        rob_complete_valid
);

    localparam [3:0] OP_LOAD  = 4'b0001;
    localparam [3:0] OP_STORE = 4'b0010;

    typedef enum logic [1:0] {
        LSU_IDLE,
        LSU_WAIT_REQ_ACCEPT,
        LSU_WAIT_RESP
    } lsu_state_t;

    lsu_state_t state_q, state_d;

    logic        req_valid_q;
    logic        req_we_q;
    logic [31:0] req_addr_q;
    logic [31:0] req_wdata_q;
    logic [3:0]  req_be_q;
    logic [5:0]  req_prd_q;
    logic [2:0]  req_rob_idx_q;
    logic [3:0]  req_op_type_q;
    logic [2:0]  req_func3_q;
    logic [1:0]  req_epoch_q;

    logic [31:0] addr;
    logic [31:0] store_data;
    logic [3:0]  be;
    logic [31:0] wdata;

    logic [31:0] load_data;

    logic [1:0] byte_sel;
    logic       half_sel;

    assign prf_read1_addr = lsu_issue_prs1;
    assign prf_read2_addr = lsu_issue_prs2;

    assign addr = prf_read1_data + lsu_issue_imm;

    always_comb begin
        store_data = prf_read2_data;
        be = 4'b0000;
        wdata = 32'b0;
        case (lsu_issue_func3)
            3'b000: begin
                be = 4'b0001 << addr[1:0];
                wdata = {4{prf_read2_data[7:0]}};
            end
            3'b001: begin
                be = addr[1] ? 4'b1100 : 4'b0011;
                wdata = {2{prf_read2_data[15:0]}};
            end
            3'b010: begin
                be = 4'b1111;
                wdata = prf_read2_data;
            end
            default: begin
                be = 4'b0000;
                wdata = 32'b0;
            end
        endcase
    end

    assign byte_sel = req_addr_q[1:0];
    assign half_sel = req_addr_q[1];

    always_comb begin
        load_data = 32'b0;
        case (req_func3_q)
            3'b000: begin
                case (byte_sel)
                    2'd0: load_data = {{24{dcache_cpu_resp_rdata[7]}},  dcache_cpu_resp_rdata[7:0]};
                    2'd1: load_data = {{24{dcache_cpu_resp_rdata[15]}}, dcache_cpu_resp_rdata[15:8]};
                    2'd2: load_data = {{24{dcache_cpu_resp_rdata[23]}}, dcache_cpu_resp_rdata[23:16]};
                    2'd3: load_data = {{24{dcache_cpu_resp_rdata[31]}}, dcache_cpu_resp_rdata[31:24]};
                endcase
            end
            3'b001: begin
                if (half_sel) begin
                    load_data = {{16{dcache_cpu_resp_rdata[31]}}, dcache_cpu_resp_rdata[31:16]};
                end else begin
                    load_data = {{16{dcache_cpu_resp_rdata[15]}}, dcache_cpu_resp_rdata[15:0]};
                end
            end
            3'b010: begin
                load_data = dcache_cpu_resp_rdata;
            end
            3'b100: begin
                case (byte_sel)
                    2'd0: load_data = {24'b0, dcache_cpu_resp_rdata[7:0]};
                    2'd1: load_data = {24'b0, dcache_cpu_resp_rdata[15:8]};
                    2'd2: load_data = {24'b0, dcache_cpu_resp_rdata[23:16]};
                    2'd3: load_data = {24'b0, dcache_cpu_resp_rdata[31:24]};
                endcase
            end
            3'b101: begin
                if (half_sel) begin
                    load_data = {16'b0, dcache_cpu_resp_rdata[31:16]};
                end else begin
                    load_data = {16'b0, dcache_cpu_resp_rdata[15:0]};
                end
            end
            default: load_data = dcache_cpu_resp_rdata;
        endcase
    end

    assign dcache_cpu_req_valid = (state_q == LSU_WAIT_REQ_ACCEPT) ? 1'b1 : 1'b0;
    assign dcache_cpu_req_we    = req_we_q;
    assign dcache_cpu_req_addr  = req_addr_q;
    assign dcache_cpu_req_wdata = req_wdata_q;
    assign dcache_cpu_req_be    = req_be_q;

    assign dcache_flush       = rob_flush;
    assign dcache_flush_epoch = rob_epoch;

    assign prf_write_valid    = (state_q == LSU_WAIT_RESP) && dcache_cpu_resp_valid && !req_we_q;
    assign prf_write_pr       = req_prd_q;
    assign prf_write_data     = load_data;
    assign rob_complete_valid = (state_q == LSU_WAIT_RESP) && dcache_cpu_resp_valid;

    always_comb begin
        state_d = state_q;
        case (state_q)
            LSU_IDLE: begin
                if (lsu_issue_valid && !rob_flush) begin
                    state_d = LSU_WAIT_REQ_ACCEPT;
                end
            end
            LSU_WAIT_REQ_ACCEPT: begin
                if (rob_flush) begin
                    state_d = LSU_IDLE;
                end else if (dcache_cpu_req_ready) begin
                    state_d = LSU_WAIT_RESP;
                end
            end
            LSU_WAIT_RESP: begin
                if (rob_flush) begin
                    state_d = LSU_IDLE;
                end else if (dcache_cpu_resp_valid) begin
                    state_d = LSU_IDLE;
                end
            end
            default: state_d = LSU_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q        <= LSU_IDLE;
            req_valid_q    <= 1'b0;
            req_we_q       <= 1'b0;
            req_addr_q     <= 32'b0;
            req_wdata_q    <= 32'b0;
            req_be_q       <= 4'b0000;
            req_prd_q      <= 6'b0;
            req_rob_idx_q  <= 3'b0;
            req_op_type_q  <= 4'b0;
            req_func3_q    <= 3'b0;
            req_epoch_q    <= 2'b0;
        end else begin
            state_q <= state_d;
            if (state_q == LSU_IDLE && lsu_issue_valid && !rob_flush) begin
                req_valid_q   <= 1'b1;
                req_we_q      <= (lsu_issue_op_type == OP_STORE);
                req_addr_q    <= addr;
                req_wdata_q   <= wdata;
                req_be_q      <= be;
                req_prd_q     <= lsu_issue_prd;
                req_rob_idx_q <= lsu_issue_rob_idx;
                req_op_type_q <= lsu_issue_op_type;
                req_func3_q   <= lsu_issue_func3;
                req_epoch_q   <= rob_epoch;
            end
            if (state_q == LSU_WAIT_RESP && dcache_cpu_resp_valid) begin
                req_valid_q <= 1'b0;
            end
            if (rob_flush) begin
                req_valid_q <= 1'b0;
            end
        end
    end

endmodule
