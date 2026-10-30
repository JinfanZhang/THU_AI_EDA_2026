// rtl/rename_unit.sv
module rename_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        dec_valid,
    input  logic [31:0] dec_pc,
    input  logic [31:0] dec_insn,
    input  logic [4:0]  dec_rs1,
    input  logic [4:0]  dec_rs2,
    input  logic [4:0]  dec_rd,
    input  logic [31:0] dec_imm,
    input  logic [3:0]  dec_op_type,
    input  logic [2:0]  dec_func3,
    input  logic [6:0]  dec_func7,
    output logic        ren_ready,
    output logic        iq_dispatch_valid,
    output logic [31:0] iq_dispatch_pc,
    output logic [31:0] iq_dispatch_insn,
    output logic [5:0]  iq_dispatch_prs1,
    output logic [5:0]  iq_dispatch_prs2,
    output logic [5:0]  iq_dispatch_prd,
    output logic [2:0]  iq_dispatch_rob_idx,
    output logic [31:0] iq_dispatch_imm,
    output logic [3:0]  iq_dispatch_op_type,
    output logic [2:0]  iq_dispatch_func3,
    output logic [6:0]  iq_dispatch_func7,
    input  logic        iq_full,
    output logic        rob_alloc_req_valid,
    output logic [31:0] rob_alloc_req_pc,
    output logic [31:0] rob_alloc_req_insn,
    output logic [5:0]  rob_alloc_req_prd,
    output logic [5:0]  rob_alloc_req_old_prd,
    input  logic        rob_alloc_grant,
    input  logic [2:0]  rob_alloc_idx,
    input  logic        rob_flush,
    input  logic [1:0]  rob_epoch,
    input  logic        rob_restore_valid,
    input  logic [2:0]  rob_restore_checkpoint_id,
    input  logic [5:0]  rob_commit_phys_reg,
    input  logic [5:0]  rob_commit_old_phys_reg,
    input  logic        rob_commit_valid
);

    // Physical register count: 40 (PR0..PR39)
    localparam PR_COUNT = 40;
    localparam FREE_LIST_DEPTH = 8;  // PR32..PR39

    // RAT: architectural register -> physical register
    logic [5:0] spec_rat [0:31];
    logic [5:0] commit_rat [0:31];

    // Free list
    logic [5:0] free_list [0:FREE_LIST_DEPTH-1];
    logic [2:0] free_head;
    logic [2:0] free_tail;
    logic [2:0] free_count;

    // Checkpoint storage for branch recovery
    logic [5:0] cp_rat [0:7][0:31];
    logic [2:0] cp_free_head [0:7];
    logic [2:0] cp_free_tail [0:7];
    logic [2:0] cp_free_count [0:7];
    logic       cp_valid [0:7];

    // Ready bits for physical registers
    logic [PR_COUNT-1:0] pr_ready;

    // Dispatch pipeline stage
    logic        disp_valid_r;
    logic [31:0] disp_pc_r;
    logic [31:0] disp_insn_r;
    logic [5:0]  disp_prs1_r;
    logic [5:0]  disp_prs2_r;
    logic [5:0]  disp_prd_r;
    logic [2:0]  disp_rob_idx_r;
    logic [31:0] disp_imm_r;
    logic [3:0]  disp_op_type_r;
    logic [2:0]  disp_func3_r;
    logic [6:0]  disp_func7_r;

    // Allocate request pipeline
    logic        alloc_req_valid_r;
    logic [31:0] alloc_req_pc_r;
    logic [31:0] alloc_req_insn_r;
    logic [5:0]  alloc_req_prd_r;
    logic [5:0]  alloc_req_old_prd_r;

    // Internal signals
    logic        can_accept;
    logic        is_control;
    logic [5:0]  new_prd;
    logic [5:0]  old_prd;
    logic [2:0]  cp_idx;
    logic        alloc_taken;

    // Determine if instruction is a control transfer (branch/JAL/JALR)
    always_comb begin
        is_control = 1'b0;
        case (dec_op_type)
            4'b0100: is_control = 1'b1; // branch
            4'b0101: is_control = 1'b1; // JAL
            4'b0110: is_control = 1'b1; // JALR
            default: is_control = 1'b0;
        endcase
    end

    // Check if we can accept a new instruction
    assign can_accept = dec_valid && !iq_full && (free_count > 0) && !rob_flush;

    // ren_ready: we can accept if decode is valid and we have resources
    assign ren_ready = !iq_full && (free_count > 0) && !rob_flush;

    // Find a free checkpoint index (round-robin)
    // Unrolled priority encoder: no break/early-exit constructs.
    logic [2:0] cp_alloc_idx;
    always_comb begin
        if (!cp_valid[0]) begin
            cp_alloc_idx = 3'd0;
        end else if (!cp_valid[1]) begin
            cp_alloc_idx = 3'd1;
        end else if (!cp_valid[2]) begin
            cp_alloc_idx = 3'd2;
        end else if (!cp_valid[3]) begin
            cp_alloc_idx = 3'd3;
        end else if (!cp_valid[4]) begin
            cp_alloc_idx = 3'd4;
        end else if (!cp_valid[5]) begin
            cp_alloc_idx = 3'd5;
        end else if (!cp_valid[6]) begin
            cp_alloc_idx = 3'd6;
        end else begin
            cp_alloc_idx = 3'd7;
        end
    end

    // Allocate new physical register from free list
    assign new_prd = free_list[free_head];
    assign old_prd = spec_rat[dec_rd];

    // Sequential logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Reset RAT to initial mapping
            for (int i = 0; i < 32; i++) begin
                spec_rat[i] <= (i == 0) ? 6'd0 : 6'(i);
                commit_rat[i] <= (i == 0) ? 6'd0 : 6'(i);
            end
            // Reset free list: PR32..PR39
            for (int i = 0; i < FREE_LIST_DEPTH; i++) begin
                free_list[i] <= 6'(32 + i);
            end
            free_head <= 3'd0;
            free_tail <= 3'd0;
            free_count <= 3'd8;

            // Reset checkpoints
            for (int i = 0; i < 8; i++) begin
                cp_valid[i] <= 1'b0;
                cp_free_head[i] <= 3'd0;
                cp_free_tail[i] <= 3'd0;
                cp_free_count[i] <= 3'd0;
                for (int j = 0; j < 32; j++) begin
                    cp_rat[i][j] <= 6'd0;
                end
            end

            // Reset ready bits
            pr_ready <= 40'h00000000FF; // PR0..PR7 ready (x0..x7), others not ready initially
            // Actually: PR0=x0 ready, PR1..PR31=x1..x31 ready with value 0
            pr_ready <= 40'h00000000FFFFFFFF; // PR0..PR31 ready

            // Reset pipeline registers
            disp_valid_r <= 1'b0;
            alloc_req_valid_r <= 1'b0;
        end else begin
            // Handle commit: free old physical register
            if (rob_commit_valid && rob_commit_old_phys_reg != 6'd0) begin
                free_list[free_tail] <= rob_commit_old_phys_reg;
                free_tail <= free_tail + 3'd1;
                free_count <= free_count + 3'd1;
                // Update committed RAT
                commit_rat[rob_commit_phys_reg[4:0]] <= rob_commit_phys_reg;
            end

            // Handle restore (mispredict recovery)
            if (rob_restore_valid) begin
                cp_idx = rob_restore_checkpoint_id;
                if (cp_valid[cp_idx]) begin
                    // Restore speculative RAT from checkpoint
                    for (int i = 0; i < 32; i++) begin
                        spec_rat[i] <= cp_rat[cp_idx][i];
                    end
                    // Restore free list
                    free_head <= cp_free_head[cp_idx];
                    free_tail <= cp_free_tail[cp_idx];
                    free_count <= cp_free_count[cp_idx];
                    // Invalidate this checkpoint and all newer checkpoints
                    for (int i = 0; i < 8; i++) begin
                        if (i >= cp_idx) cp_valid[i] <= 1'b0;
                    end
                    // Clear ready bits for freed registers
                    // (simplified: mark all non-committed PRs as not ready)
                    for (int i = 32; i < PR_COUNT; i++) begin
                        pr_ready[i] <= 1'b0;
                    end
                end
            end

            // Handle allocation request
            if (alloc_req_valid_r && rob_alloc_grant) begin
                alloc_req_valid_r <= 1'b0;
                // Update speculative RAT
                if (dec_rd != 5'd0) begin
                    spec_rat[dec_rd] <= new_prd;
                end
                // Pop free list
                free_head <= free_head + 3'd1;
                free_count <= free_count - 3'd1;
                // Mark new PR as not ready
                pr_ready[new_prd] <= 1'b0;
                // Save checkpoint if control instruction
                if (is_control) begin
                    cp_valid[cp_alloc_idx] <= 1'b1;
                    cp_free_head[cp_alloc_idx] <= free_head;
                    cp_free_tail[cp_alloc_idx] <= free_tail;
                    cp_free_count[cp_alloc_idx] <= free_count;
                    for (int i = 0; i < 32; i++) begin
                        cp_rat[cp_alloc_idx][i] <= spec_rat[i];
                    end
                end
            end

            // Handle new dispatch
            if (can_accept && rob_alloc_grant) begin
                disp_valid_r <= 1'b1;
                disp_pc_r <= dec_pc;
                disp_insn_r <= dec_insn;
                disp_prs1_r <= spec_rat[dec_rs1];
                disp_prs2_r <= spec_rat[dec_rs2];
                disp_prd_r <= new_prd;
                disp_rob_idx_r <= rob_alloc_idx;
                disp_imm_r <= dec_imm;
                disp_op_type_r <= dec_op_type;
                disp_func3_r <= dec_func3;
                disp_func7_r <= dec_func7;

                alloc_req_valid_r <= 1'b1;
                alloc_req_pc_r <= dec_pc;
                alloc_req_insn_r <= dec_insn;
                alloc_req_prd_r <= new_prd;
                alloc_req_old_prd_r <= old_prd;
            end else if (rob_flush) begin
                disp_valid_r <= 1'b0;
                alloc_req_valid_r <= 1'b0;
            end else begin
                disp_valid_r <= 1'b0;
            end
        end
    end

    // Output assignments
    assign iq_dispatch_valid = disp_valid_r;
    assign iq_dispatch_pc = disp_pc_r;
    assign iq_dispatch_insn = disp_insn_r;
    assign iq_dispatch_prs1 = disp_prs1_r;
    assign iq_dispatch_prs2 = disp_prs2_r;
    assign iq_dispatch_prd = disp_prd_r;
    assign iq_dispatch_rob_idx = disp_rob_idx_r;
    assign iq_dispatch_imm = disp_imm_r;
    assign iq_dispatch_op_type = disp_op_type_r;
    assign iq_dispatch_func3 = disp_func3_r;
    assign iq_dispatch_func7 = disp_func7_r;

    assign rob_alloc_req_valid = alloc_req_valid_r;
    assign rob_alloc_req_pc = alloc_req_pc_r;
    assign rob_alloc_req_insn = alloc_req_insn_r;
    assign rob_alloc_req_prd = alloc_req_prd_r;
    assign rob_alloc_req_old_prd = alloc_req_old_prd_r;

endmodule
