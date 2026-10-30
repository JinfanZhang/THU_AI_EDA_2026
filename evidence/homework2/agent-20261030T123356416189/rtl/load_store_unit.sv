module load_store_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        lsq_disp_valid,
    output logic        lsq_disp_ready,
    input  logic [31:0] disp_imm,
    input  logic [5:0]  disp_prs1,
    input  logic [5:0]  disp_prs2,
    input  logic        disp_prs1_ready,
    input  logic        disp_prs2_ready,
    input  logic [5:0]  disp_prd,
    input  logic        disp_has_dest,
    input  logic        disp_is_store,
    input  logic [2:0]  disp_mem_funct3,
    input  logic [2:0]  disp_rob_idx,
    output logic [5:0]  op_rs1_pr,
    output logic [5:0]  op_rs2_pr,
    input  logic [31:0] op_rs1_val,
    input  logic [31:0] op_rs2_val,
    input  logic        lsu_wb_valid,
    input  logic [5:0]  lsu_wb_prd,
    input  logic        ex_wakeup_valid,
    input  logic [5:0]  ex_wakeup_prd,
    input  logic [2:0]  rob_head,
    input  logic        rob_head_valid,
    input  logic        alu_issue_valid,
    output logic        wb_valid,
    output logic [2:0]  wb_rob_idx,
    output logic [5:0]  wb_prd,
    output logic        wb_has_dest,
    output logic [31:0] wb_data,
    output logic        dc_req_valid,
    output logic        dc_req_we,
    output logic [31:0] dc_req_addr,
    output logic [31:0] dc_req_wdata,
    output logic [3:0]  dc_req_be,
    input  logic        dc_req_ready,
    input  logic        dc_resp_valid,
    input  logic [31:0] dc_resp_rdata,
    input  logic        squash_valid,
    input  logic [7:0]  squash_mask,
    input  logic        dmem_valid,
    input  logic        dmem_ready,
    output logic        dbg_ooo_bypass_evt,
    output logic        idle
);

    localparam int DEPTH = 4;

    logic [DEPTH-1:0] ent_valid;
    logic [DEPTH-1:0] ent_is_store;
    logic [DEPTH-1:0] ent_rs1_rdy;
    logic [DEPTH-1:0] ent_rs2_rdy;
    logic [DEPTH-1:0] ent_issued;
    logic [DEPTH-1:0] ent_has_dest;
    logic [31:0]      ent_imm   [DEPTH];
    logic [5:0]       ent_prs1  [DEPTH];
    logic [5:0]       ent_prs2  [DEPTH];
    logic [5:0]       ent_prd   [DEPTH];
    logic [2:0]       ent_funct3[DEPTH];
    logic [2:0]       ent_rob   [DEPTH];
    logic [31:0]      ent_addr  [DEPTH];
    logic [31:0]      ent_wdata [DEPTH];
    logic [3:0]       ent_be    [DEPTH];

    logic [1:0] head_ptr;
    logic [1:0] tail_ptr;
    logic [2:0] count;

    logic [DEPTH-1:0] ent_sel;
    logic             head_valid;
    logic             head_is_store;
    logic             head_rs1_rdy;
    logic             head_rs2_rdy;
    logic             head_issued;
    logic             head_has_dest;
    logic [31:0]      head_imm;
    logic [5:0]       head_prs1;
    logic [5:0]       head_prs2;
    logic [5:0]       head_prd;
    logic [2:0]       head_funct3;
    logic [2:0]       head_rob;
    logic [31:0]      head_addr;
    logic [31:0]      head_wdata;
    logic [3:0]       head_be;

    logic             head_operands_ready;
    logic             head_can_issue;
    logic             req_fire;
    logic             resp_fire;

    logic [31:0]      load_data;
    logic [31:0]      load_byte;
    logic [31:0]      load_half;

    logic [DEPTH-1:0] squash_hit;
    logic [DEPTH-1:0] wake_rs1;
    logic [DEPTH-1:0] wake_rs2;

    integer i;

    always_comb begin
        ent_sel = 4'b0000;
        ent_sel[head_ptr] = 1'b1;

        head_valid    = ent_valid[head_ptr];
        head_is_store = ent_is_store[head_ptr];
        head_rs1_rdy  = ent_rs1_rdy[head_ptr];
        head_rs2_rdy  = ent_rs2_rdy[head_ptr];
        head_issued   = ent_issued[head_ptr];
        head_has_dest = ent_has_dest[head_ptr];
        head_imm      = ent_imm[head_ptr];
        head_prs1     = ent_prs1[head_ptr];
        head_prs2     = ent_prs2[head_ptr];
        head_prd      = ent_prd[head_ptr];
        head_funct3   = ent_funct3[head_ptr];
        head_rob      = ent_rob[head_ptr];
        head_addr     = ent_addr[head_ptr];
        head_wdata    = ent_wdata[head_ptr];
        head_be       = ent_be[head_ptr];
    end

    always_comb begin
        head_operands_ready = head_rs1_rdy && head_rs2_rdy;
        if (head_is_store) begin
            head_can_issue = head_operands_ready && rob_head_valid && (rob_head == head_rob);
        end else begin
            head_can_issue = head_operands_ready;
        end
    end

    assign lsq_disp_ready = (count < DEPTH[2:0]);

    assign op_rs1_pr = head_prs1;
    assign op_rs2_pr = head_prs2;

    assign dc_req_valid = head_valid && head_can_issue && !head_issued;
    assign dc_req_we    = head_is_store;
    assign dc_req_addr  = head_addr;
    assign dc_req_wdata = head_wdata;
    assign dc_req_be    = head_be;

    assign req_fire  = dc_req_valid && dc_req_ready;
    assign resp_fire = head_valid && head_issued && dc_resp_valid;

    always_comb begin
        load_byte = 32'b0;
        load_half = 32'b0;
        load_data = 32'b0;
        case (head_funct3)
            3'b000: begin
                case (head_addr[1:0])
                    2'b00: load_byte = {{24{dc_resp_rdata[7]}},  dc_resp_rdata[7:0]};
                    2'b01: load_byte = {{24{dc_resp_rdata[15]}}, dc_resp_rdata[15:8]};
                    2'b10: load_byte = {{24{dc_resp_rdata[23]}}, dc_resp_rdata[23:16]};
                    default: load_byte = {{24{dc_resp_rdata[31]}}, dc_resp_rdata[31:24]};
                endcase
                load_data = load_byte;
            end
            3'b001: begin
                if (head_addr[1]) load_half = {{16{dc_resp_rdata[31]}}, dc_resp_rdata[31:16]};
                else              load_half = {{16{dc_resp_rdata[15]}}, dc_resp_rdata[15:0]};
                load_data = load_half;
            end
            3'b010: load_data = dc_resp_rdata;
            3'b100: begin
                case (head_addr[1:0])
                    2'b00: load_byte = {24'b0, dc_resp_rdata[7:0]};
                    2'b01: load_byte = {24'b0, dc_resp_rdata[15:8]};
                    2'b10: load_byte = {24'b0, dc_resp_rdata[23:16]};
                    default: load_byte = {24'b0, dc_resp_rdata[31:24]};
                endcase
                load_data = load_byte;
            end
            3'b101: begin
                if (head_addr[1]) load_half = {16'b0, dc_resp_rdata[31:16]};
                else              load_half = {16'b0, dc_resp_rdata[15:0]};
                load_data = load_half;
            end
            default: load_data = dc_resp_rdata;
        endcase
    end

    assign wb_valid    = resp_fire;
    assign wb_rob_idx  = head_rob;
    assign wb_prd      = head_prd;
    assign wb_has_dest = resp_fire && !head_is_store && head_has_dest;
    assign wb_data     = load_data;

    assign dbg_ooo_bypass_evt = dmem_valid && !dmem_ready && alu_issue_valid;

    assign idle = (count == 3'd0) && !head_issued;

    always_comb begin
        squash_hit = 4'b0000;
        for (i = 0; i < DEPTH; i = i + 1) begin
            if (ent_valid[i] && squash_mask[ent_rob[i]]) squash_hit[i] = 1'b1;
        end
    end

    always_comb begin
        wake_rs1 = 4'b0000;
        wake_rs2 = 4'b0000;
        for (i = 0; i < DEPTH; i = i + 1) begin
            if (ent_valid[i] && !ent_rs1_rdy[i] && (ent_prs1[i] != 6'd0)) begin
                if ((lsu_wb_valid && (lsu_wb_prd == ent_prs1[i])) ||
                    (ex_wakeup_valid && (ex_wakeup_prd == ent_prs1[i]))) begin
                    wake_rs1[i] = 1'b1;
                end
            end
            if (ent_valid[i] && !ent_rs2_rdy[i] && (ent_prs2[i] != 6'd0)) begin
                if ((lsu_wb_valid && (lsu_wb_prd == ent_prs2[i])) ||
                    (ex_wakeup_valid && (ex_wakeup_prd == ent_prs2[i]))) begin
                    wake_rs2[i] = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ent_valid    <= 4'b0000;
            ent_is_store <= 4'b0000;
            ent_rs1_rdy  <= 4'b0000;
            ent_rs2_rdy  <= 4'b0000;
            ent_issued   <= 4'b0000;
            ent_has_dest <= 4'b0000;
            head_ptr     <= 2'd0;
            tail_ptr     <= 2'd0;
            count        <= 3'd0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                ent_imm[i]    <= 32'b0;
                ent_prs1[i]   <= 6'd0;
                ent_prs2[i]   <= 6'd0;
                ent_prd[i]    <= 6'd0;
                ent_funct3[i] <= 3'd0;
                ent_rob[i]    <= 3'd0;
                ent_addr[i]   <= 32'b0;
                ent_wdata[i]  <= 32'b0;
                ent_be[i]     <= 4'b0;
            end
        end else begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                if (wake_rs1[i]) ent_rs1_rdy[i] <= 1'b1;
                if (wake_rs2[i]) ent_rs2_rdy[i] <= 1'b1;
            end

            if (squash_valid) begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    if (squash_hit[i]) begin
                        ent_valid[i]  <= 1'b0;
                        ent_issued[i] <= 1'b0;
                    end
                end
            end

            if (req_fire) begin
                ent_issued[head_ptr] <= 1'b1;
            end

            if (resp_fire) begin
                ent_valid[head_ptr]  <= 1'b0;
                ent_issued[head_ptr] <= 1'b0;
            end

            if (lsq_disp_valid && lsq_disp_ready) begin
                ent_valid[tail_ptr]    <= 1'b1;
                ent_is_store[tail_ptr] <= disp_is_store;
                ent_rs1_rdy[tail_ptr]  <= disp_prs1_ready || (disp_prs1 == 6'd0);
                ent_rs2_rdy[tail_ptr]  <= disp_prs2_ready || (disp_prs2 == 6'd0);
                ent_issued[tail_ptr]   <= 1'b0;
                ent_has_dest[tail_ptr] <= disp_has_dest;
                ent_imm[tail_ptr]      <= disp_imm;
                ent_prs1[tail_ptr]     <= disp_prs1;
                ent_prs2[tail_ptr]     <= disp_prs2;
                ent_prd[tail_ptr]      <= disp_prd;
                ent_funct3[tail_ptr]   <= disp_mem_funct3;
                ent_rob[tail_ptr]      <= disp_rob_idx;
                ent_addr[tail_ptr]     <= op_rs1_val + disp_imm;
                ent_wdata[tail_ptr]    <= op_rs2_val;
                case (disp_mem_funct3)
                    3'b000: ent_be[tail_ptr] <= 4'b0001 << op_rs1_val[1:0];
                    3'b001: ent_be[tail_ptr] <= op_rs1_val[1] ? 4'b1100 : 4'b0011;
                    default: ent_be[tail_ptr] <= 4'b1111;
                endcase
            end

            if (req_fire && !resp_fire) begin
                head_ptr <= head_ptr + 2'd1;
            end else if (resp_fire && !req_fire) begin
                head_ptr <= head_ptr + 2'd1;
            end else if (req_fire && resp_fire) begin
                head_ptr <= head_ptr + 2'd1;
            end

            if (lsq_disp_valid && lsq_disp_ready) begin
                tail_ptr <= tail_ptr + 2'd1;
            end

            if (lsq_disp_valid && lsq_disp_ready && resp_fire) begin
                count <= count;
            end else if (lsq_disp_valid && lsq_disp_ready) begin
                count <= count + 3'd1;
            end else if (resp_fire) begin
                count <= count - 3'd1;
            end
        end
    end

endmodule
