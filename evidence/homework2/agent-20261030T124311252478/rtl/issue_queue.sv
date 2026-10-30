module issue_queue (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        iq_dispatch_valid,
    input  logic [31:0] iq_dispatch_pc,
    input  logic [31:0] iq_dispatch_insn,
    input  logic [5:0]  iq_dispatch_prs1,
    input  logic [5:0]  iq_dispatch_prs2,
    input  logic [5:0]  iq_dispatch_prd,
    input  logic [2:0]  iq_dispatch_rob_idx,
    input  logic [31:0] iq_dispatch_imm,
    input  logic [3:0]  iq_dispatch_op_type,
    input  logic [2:0]  iq_dispatch_func3,
    input  logic [6:0]  iq_dispatch_func7,
    output logic        iq_full,
    output logic        alu_issue_valid,
    output logic [5:0]  alu_issue_prs1,
    output logic [5:0]  alu_issue_prs2,
    output logic [5:0]  alu_issue_prd,
    output logic [2:0]  alu_issue_rob_idx,
    output logic [31:0] alu_issue_imm,
    output logic [3:0]  alu_issue_op_type,
    output logic [2:0]  alu_issue_func3,
    output logic [6:0]  alu_issue_func7,
    output logic [31:0] alu_issue_pc,
    output logic        lsu_issue_valid,
    output logic [5:0]  lsu_issue_prs1,
    output logic [5:0]  lsu_issue_prs2,
    output logic [5:0]  lsu_issue_prd,
    output logic [2:0]  lsu_issue_rob_idx,
    output logic [31:0] lsu_issue_imm,
    output logic [3:0]  lsu_issue_op_type,
    output logic [2:0]  lsu_issue_func3,
    output logic [6:0]  lsu_issue_func7,
    output logic [31:0] lsu_issue_pc,
    input  logic        prf_ready_alu1,
    input  logic        prf_ready_alu2,
    input  logic        prf_ready_lsu1,
    input  logic        prf_ready_lsu2,
    input  logic        squash_valid,
    input  logic [2:0]  squash_rob_idx,
    output logic        dbg_ooo_issue
);

    localparam IQ_DEPTH = 8;
    localparam IQ_PTR_W = 3;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] insn;
        logic [5:0]  prs1;
        logic [5:0]  prs2;
        logic [5:0]  prd;
        logic [2:0]  rob_idx;
        logic [31:0] imm;
        logic [3:0]  op_type;
        logic [2:0]  func3;
        logic [6:0]  func7;
        logic        is_lsu;
        logic        src1_ready;
        logic        src2_ready;
    } iq_entry_t;

    iq_entry_t iq_entries [IQ_DEPTH];

    logic [IQ_PTR_W-1:0] wr_ptr;
    logic [IQ_PTR_W-1:0] rd_ptr_alu;
    logic [IQ_PTR_W-1:0] rd_ptr_lsu;
    logic [IQ_PTR_W:0]   count;

    logic [IQ_PTR_W-1:0] alu_candidate;
    logic [IQ_PTR_W-1:0] lsu_candidate;
    logic                alu_candidate_valid;
    logic                lsu_candidate_valid;

    logic [IQ_DEPTH-1:0] alu_ready_vec;
    logic [IQ_DEPTH-1:0] lsu_ready_vec;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < IQ_DEPTH; i++) begin
                iq_entries[i].valid       <= 1'b0;
                iq_entries[i].pc          <= 32'b0;
                iq_entries[i].insn        <= 32'b0;
                iq_entries[i].prs1        <= 6'b0;
                iq_entries[i].prs2        <= 6'b0;
                iq_entries[i].prd         <= 6'b0;
                iq_entries[i].rob_idx     <= 3'b0;
                iq_entries[i].imm         <= 32'b0;
                iq_entries[i].op_type     <= 4'b0;
                iq_entries[i].func3       <= 3'b0;
                iq_entries[i].func7       <= 7'b0;
                iq_entries[i].is_lsu      <= 1'b0;
                iq_entries[i].src1_ready  <= 1'b0;
                iq_entries[i].src2_ready  <= 1'b0;
            end
            wr_ptr <= 3'b0;
            rd_ptr_alu <= 3'b0;
            rd_ptr_lsu <= 3'b0;
            count <= 4'b0;
        end else begin
            if (squash_valid) begin
                for (int i = 0; i < IQ_DEPTH; i++) begin
                    if (iq_entries[i].valid && (iq_entries[i].rob_idx >= squash_rob_idx)) begin
                        iq_entries[i].valid <= 1'b0;
                    end
                end
                wr_ptr <= 3'b0;
                rd_ptr_alu <= 3'b0;
                rd_ptr_lsu <= 3'b0;
                count <= 4'b0;
            end else begin
                if (iq_dispatch_valid && count < IQ_DEPTH) begin
                    iq_entries[wr_ptr].valid       <= 1'b1;
                    iq_entries[wr_ptr].pc          <= iq_dispatch_pc;
                    iq_entries[wr_ptr].insn        <= iq_dispatch_insn;
                    iq_entries[wr_ptr].prs1        <= iq_dispatch_prs1;
                    iq_entries[wr_ptr].prs2        <= iq_dispatch_prs2;
                    iq_entries[wr_ptr].prd         <= iq_dispatch_prd;
                    iq_entries[wr_ptr].rob_idx     <= iq_dispatch_rob_idx;
                    iq_entries[wr_ptr].imm         <= iq_dispatch_imm;
                    iq_entries[wr_ptr].op_type     <= iq_dispatch_op_type;
                    iq_entries[wr_ptr].func3       <= iq_dispatch_func3;
                    iq_entries[wr_ptr].func7       <= iq_dispatch_func7;
                    iq_entries[wr_ptr].is_lsu      <= (iq_dispatch_op_type[3:2] == 2'b10);
                    iq_entries[wr_ptr].src1_ready  <= (iq_dispatch_prs1 == 6'b0) ? 1'b1 : 1'b0;
                    iq_entries[wr_ptr].src2_ready  <= (iq_dispatch_prs2 == 6'b0) ? 1'b1 : 1'b0;
                    wr_ptr <= wr_ptr + 1'b1;
                    count <= count + 1'b1;
                end

                if (alu_candidate_valid) begin
                    iq_entries[alu_candidate].valid <= 1'b0;
                    rd_ptr_alu <= alu_candidate + 1'b1;
                    count <= count - 1'b1;
                end

                if (lsu_candidate_valid) begin
                    iq_entries[lsu_candidate].valid <= 1'b0;
                    rd_ptr_lsu <= lsu_candidate + 1'b1;
                    count <= count - 1'b1;
                end
            end
        end
    end

    always_comb begin
        for (int i = 0; i < IQ_DEPTH; i++) begin
            if (iq_entries[i].valid) begin
                if (iq_entries[i].prs1 == 6'b0) begin
                    iq_entries[i].src1_ready = 1'b1;
                end else if (prf_ready_alu1) begin
                    iq_entries[i].src1_ready = 1'b1;
                end else begin
                    iq_entries[i].src1_ready = 1'b0;
                end

                if (iq_entries[i].prs2 == 6'b0) begin
                    iq_entries[i].src2_ready = 1'b1;
                end else if (prf_ready_alu2) begin
                    iq_entries[i].src2_ready = 1'b1;
                end else begin
                    iq_entries[i].src2_ready = 1'b0;
                end
            end
        end
    end

    always_comb begin
        alu_ready_vec[0] = iq_entries[0].valid && !iq_entries[0].is_lsu && iq_entries[0].src1_ready && iq_entries[0].src2_ready;
        alu_ready_vec[1] = iq_entries[1].valid && !iq_entries[1].is_lsu && iq_entries[1].src1_ready && iq_entries[1].src2_ready;
        alu_ready_vec[2] = iq_entries[2].valid && !iq_entries[2].is_lsu && iq_entries[2].src1_ready && iq_entries[2].src2_ready;
        alu_ready_vec[3] = iq_entries[3].valid && !iq_entries[3].is_lsu && iq_entries[3].src1_ready && iq_entries[3].src2_ready;
        alu_ready_vec[4] = iq_entries[4].valid && !iq_entries[4].is_lsu && iq_entries[4].src1_ready && iq_entries[4].src2_ready;
        alu_ready_vec[5] = iq_entries[5].valid && !iq_entries[5].is_lsu && iq_entries[5].src1_ready && iq_entries[5].src2_ready;
        alu_ready_vec[6] = iq_entries[6].valid && !iq_entries[6].is_lsu && iq_entries[6].src1_ready && iq_entries[6].src2_ready;
        alu_ready_vec[7] = iq_entries[7].valid && !iq_entries[7].is_lsu && iq_entries[7].src1_ready && iq_entries[7].src2_ready;
    end

    always_comb begin
        lsu_ready_vec[0] = iq_entries[0].valid && iq_entries[0].is_lsu && iq_entries[0].src1_ready && iq_entries[0].src2_ready;
        lsu_ready_vec[1] = iq_entries[1].valid && iq_entries[1].is_lsu && iq_entries[1].src1_ready && iq_entries[1].src2_ready;
        lsu_ready_vec[2] = iq_entries[2].valid && iq_entries[2].is_lsu && iq_entries[2].src1_ready && iq_entries[2].src2_ready;
        lsu_ready_vec[3] = iq_entries[3].valid && iq_entries[3].is_lsu && iq_entries[3].src1_ready && iq_entries[3].src2_ready;
        lsu_ready_vec[4] = iq_entries[4].valid && iq_entries[4].is_lsu && iq_entries[4].src1_ready && iq_entries[4].src2_ready;
        lsu_ready_vec[5] = iq_entries[5].valid && iq_entries[5].is_lsu && iq_entries[5].src1_ready && iq_entries[5].src2_ready;
        lsu_ready_vec[6] = iq_entries[6].valid && iq_entries[6].is_lsu && iq_entries[6].src1_ready && iq_entries[6].src2_ready;
        lsu_ready_vec[7] = iq_entries[7].valid && iq_entries[7].is_lsu && iq_entries[7].src1_ready && iq_entries[7].src2_ready;
    end

    always_comb begin
        alu_candidate_valid = 1'b0;
        alu_candidate = 3'b0;
        if (alu_ready_vec[0]) begin
            alu_candidate_valid = 1'b1;
            alu_candidate = 3'd0;
        end else if (alu_ready_vec[1]) begin
            alu_candidate_valid = 1'b1;
            alu_candidate = 3'd1;
        end else if (alu_ready_vec[2]) begin
            alu_candidate_valid = 1'b1;
            alu_candidate = 3'd2;
        end else if (alu_ready_vec[3]) begin
            alu_candidate_valid = 1'b1;
            alu_candidate = 3'd3;
        end else if (alu_ready_vec[4]) begin
            alu_candidate_valid = 1'b1;
            alu_candidate = 3'd4;
        end else if (alu_ready_vec[5]) begin
            alu_candidate_valid = 1'b1;
            alu_candidate = 3'd5;
        end else if (alu_ready_vec[6]) begin
            alu_candidate_valid = 1'b1;
            alu_candidate = 3'd6;
        end else if (alu_ready_vec[7]) begin
            alu_candidate_valid = 1'b1;
            alu_candidate = 3'd7;
        end
    end

    always_comb begin
        lsu_candidate_valid = 1'b0;
        lsu_candidate = 3'b0;
        if (lsu_ready_vec[0]) begin
            lsu_candidate_valid = 1'b1;
            lsu_candidate = 3'd0;
        end else if (lsu_ready_vec[1]) begin
            lsu_candidate_valid = 1'b1;
            lsu_candidate = 3'd1;
        end else if (lsu_ready_vec[2]) begin
            lsu_candidate_valid = 1'b1;
            lsu_candidate = 3'd2;
        end else if (lsu_ready_vec[3]) begin
            lsu_candidate_valid = 1'b1;
            lsu_candidate = 3'd3;
        end else if (lsu_ready_vec[4]) begin
            lsu_candidate_valid = 1'b1;
            lsu_candidate = 3'd4;
        end else if (lsu_ready_vec[5]) begin
            lsu_candidate_valid = 1'b1;
            lsu_candidate = 3'd5;
        end else if (lsu_ready_vec[6]) begin
            lsu_candidate_valid = 1'b1;
            lsu_candidate = 3'd6;
        end else if (lsu_ready_vec[7]) begin
            lsu_candidate_valid = 1'b1;
            lsu_candidate = 3'd7;
        end
    end

    always_comb begin
        alu_issue_valid = 1'b0;
        alu_issue_prs1 = 6'b0;
        alu_issue_prs2 = 6'b0;
        alu_issue_prd = 6'b0;
        alu_issue_rob_idx = 3'b0;
        alu_issue_imm = 32'b0;
        alu_issue_op_type = 4'b0;
        alu_issue_func3 = 3'b0;
        alu_issue_func7 = 7'b0;
        alu_issue_pc = 32'b0;

        if (alu_candidate_valid) begin
            alu_issue_valid = 1'b1;
            alu_issue_prs1 = iq_entries[alu_candidate].prs1;
            alu_issue_prs2 = iq_entries[alu_candidate].prs2;
            alu_issue_prd = iq_entries[alu_candidate].prd;
            alu_issue_rob_idx = iq_entries[alu_candidate].rob_idx;
            alu_issue_imm = iq_entries[alu_candidate].imm;
            alu_issue_op_type = iq_entries[alu_candidate].op_type;
            alu_issue_func3 = iq_entries[alu_candidate].func3;
            alu_issue_func7 = iq_entries[alu_candidate].func7;
            alu_issue_pc = iq_entries[alu_candidate].pc;
        end
    end

    always_comb begin
        lsu_issue_valid = 1'b0;
        lsu_issue_prs1 = 6'b0;
        lsu_issue_prs2 = 6'b0;
        lsu_issue_prd = 6'b0;
        lsu_issue_rob_idx = 3'b0;
        lsu_issue_imm = 32'b0;
        lsu_issue_op_type = 4'b0;
        lsu_issue_func3 = 3'b0;
        lsu_issue_func7 = 7'b0;
        lsu_issue_pc = 32'b0;

        if (lsu_candidate_valid) begin
            lsu_issue_valid = 1'b1;
            lsu_issue_prs1 = iq_entries[lsu_candidate].prs1;
            lsu_issue_prs2 = iq_entries[lsu_candidate].prs2;
            lsu_issue_prd = iq_entries[lsu_candidate].prd;
            lsu_issue_rob_idx = iq_entries[lsu_candidate].rob_idx;
            lsu_issue_imm = iq_entries[lsu_candidate].imm;
            lsu_issue_op_type = iq_entries[lsu_candidate].op_type;
            lsu_issue_func3 = iq_entries[lsu_candidate].func3;
            lsu_issue_func7 = iq_entries[lsu_candidate].func7;
            lsu_issue_pc = iq_entries[lsu_candidate].pc;
        end
    end

    assign iq_full = (count >= IQ_DEPTH);
    assign dbg_ooo_issue = alu_issue_valid | lsu_issue_valid;

endmodule
