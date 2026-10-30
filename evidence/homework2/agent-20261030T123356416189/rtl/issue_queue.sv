module issue_queue (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        iq_disp_valid,
    output logic        iq_disp_ready,
    input  logic [31:0] disp_pc,
    input  logic [31:0] disp_alu_op,
    input  logic [2:0]  disp_br_funct3,
    input  logic [31:0] disp_imm,
    input  logic [5:0]  disp_prs1,
    input  logic [5:0]  disp_prs2,
    input  logic        disp_prs1_ready,
    input  logic        disp_prs2_ready,
    input  logic        disp_use_rs1,
    input  logic        disp_use_rs2,
    input  logic [5:0]  disp_prd,
    input  logic        disp_has_dest,
    input  logic [2:0]  disp_rob_idx,
    output logic        issue_valid,
    input  logic        issue_ready,
    output logic [3:0]  issue_alu_op,
    output logic [2:0]  issue_br_funct3,
    output logic [31:0] issue_imm,
    output logic [31:0] issue_pc,
    output logic [5:0]  issue_prs1,
    output logic [5:0]  issue_prs2,
    output logic [5:0]  issue_prd,
    output logic        issue_has_dest,
    output logic [2:0]  issue_rob_idx,
    input  logic        lsu_wb_valid,
    input  logic [5:0]  lsu_wb_prd,
    input  logic        squash_valid,
    input  logic [7:0]  squash_mask
);

    localparam int N = 8;

    logic        vld    [N];
    logic [31:0] pc_q   [N];
    logic [3:0]  alu_q  [N];
    logic [2:0]  br_q   [N];
    logic [31:0] imm_q  [N];
    logic [5:0]  ps1_q  [N];
    logic [5:0]  ps2_q  [N];
    logic        r1_q   [N];
    logic        r2_q   [N];
    logic        u1_q   [N];
    logic        u2_q   [N];
    logic [5:0]  prd_q  [N];
    logic        hd_q   [N];
    logic [2:0]  rob_q  [N];

    logic        free_vec;
    logic [2:0]  free_idx;
    logic        free_found;

    logic        sel_valid;
    logic [2:0]  sel_idx;
    logic        sel_found;

    logic        do_disp;
    logic        do_issue;

    logic [N-1:0] r1_eff;
    logic [N-1:0] r2_eff;
    logic [N-1:0] cand;

    integer i;

    always_comb begin
        free_vec   = 1'b0;
        free_idx   = 3'd0;
        free_found = 1'b0;
        for (i = 0; i < N; i = i + 1) begin
            if (!vld[i] && !free_found) begin
                free_vec   = 1'b1;
                free_idx   = i[2:0];
                free_found = 1'b1;
            end
        end
    end

    always_comb begin
        r1_eff[i] = 1'b0;
    end

    always_comb begin
        for (i = 0; i < N; i = i + 1) begin
            r1_eff[i] = r1_q[i] | (lsu_wb_valid && (lsu_wb_prd == ps1_q[i]));
            r2_eff[i] = r2_q[i] | (lsu_wb_valid && (lsu_wb_prd == ps2_q[i]));
            cand[i]   = vld[i] && (!u1_q[i] || r1_eff[i]) && (!u2_q[i] || r2_eff[i]);
        end
    end

    always_comb begin
        sel_valid = 1'b0;
        sel_idx   = 3'd0;
        sel_found = 1'b0;
        for (i = 0; i < N; i = i + 1) begin
            if (cand[i] && !sel_found) begin
                sel_valid = 1'b1;
                sel_idx   = i[2:0];
                sel_found = 1'b1;
            end
        end
    end

    assign iq_disp_ready = free_vec;

    assign do_disp  = iq_disp_valid && iq_disp_ready;
    assign do_issue = sel_valid && issue_ready;

    assign issue_valid      = sel_valid;
    assign issue_alu_op     = alu_q[sel_idx];
    assign issue_br_funct3  = br_q[sel_idx];
    assign issue_imm        = imm_q[sel_idx];
    assign issue_pc         = pc_q[sel_idx];
    assign issue_prs1       = ps1_q[sel_idx];
    assign issue_prs2       = ps2_q[sel_idx];
    assign issue_prd        = prd_q[sel_idx];
    assign issue_has_dest   = hd_q[sel_idx];
    assign issue_rob_idx    = rob_q[sel_idx];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) begin
                vld[i]   <= 1'b0;
                pc_q[i]  <= 32'd0;
                alu_q[i] <= 4'd0;
                br_q[i]  <= 3'd0;
                imm_q[i] <= 32'd0;
                ps1_q[i] <= 6'd0;
                ps2_q[i] <= 6'd0;
                r1_q[i]  <= 1'b0;
                r2_q[i]  <= 1'b0;
                u1_q[i]  <= 1'b0;
                u2_q[i]  <= 1'b0;
                prd_q[i] <= 6'd0;
                hd_q[i]  <= 1'b0;
                rob_q[i] <= 3'd0;
            end
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                if (squash_valid && vld[i] && squash_mask[rob_q[i]]) begin
                    vld[i] <= 1'b0;
                end else if (do_issue && (sel_idx == i[2:0])) begin
                    vld[i] <= 1'b0;
                end else if (do_disp && (free_idx == i[2:0])) begin
                    vld[i]   <= 1'b1;
                    pc_q[i]  <= disp_pc;
                    alu_q[i] <= disp_alu_op[3:0];
                    br_q[i]  <= disp_br_funct3;
                    imm_q[i] <= disp_imm;
                    ps1_q[i] <= disp_prs1;
                    ps2_q[i] <= disp_prs2;
                    r1_q[i]  <= disp_prs1_ready;
                    r2_q[i]  <= disp_prs2_ready;
                    u1_q[i]  <= disp_use_rs1;
                    u2_q[i]  <= disp_use_rs2;
                    prd_q[i] <= disp_prd;
                    hd_q[i]  <= disp_has_dest;
                    rob_q[i] <= disp_rob_idx;
                end else begin
                    if (lsu_wb_valid) begin
                        if (u1_q[i] && (ps1_q[i] == lsu_wb_prd)) r1_q[i] <= 1'b1;
                        if (u2_q[i] && (ps2_q[i] == lsu_wb_prd)) r2_q[i] <= 1'b1;
                    end
                    if (do_issue && hd_q[sel_idx]) begin
                        if (u1_q[i] && (ps1_q[i] == prd_q[sel_idx])) r1_q[i] <= 1'b1;
                        if (u2_q[i] && (ps2_q[i] == prd_q[sel_idx])) r2_q[i] <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
