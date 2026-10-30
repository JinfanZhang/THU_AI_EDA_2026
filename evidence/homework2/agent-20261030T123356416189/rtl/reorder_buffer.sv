module reorder_buffer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        rob_disp_valid,
    output logic        rob_disp_ready,
    input  logic [31:0] disp_pc,
    input  logic [31:0] disp_insn,
    input  logic [5:0]  disp_prd,
    input  logic [5:0]  disp_old_prd,
    input  logic        disp_has_dest,
    input  logic [4:0]  disp_arch_rd,
    input  logic        disp_is_load,
    input  logic        disp_is_store,
    input  logic        disp_is_ctrl,
    input  logic        disp_is_cond,
    input  logic        disp_is_ecall,
    input  logic        disp_is_ckpt_owner,
    input  logic [1:0]  disp_ckpt_id,
    input  logic [31:0] disp_pred_npc,
    output logic [2:0]  disp_rob_idx,
    input  logic        ex_valid,
    input  logic [2:0]  ex_rob_idx,
    input  logic [31:0] ex_result,
    input  logic [31:0] ex_npc,
    input  logic        lsu_wb_valid,
    input  logic [2:0]  lsu_wb_rob_idx,
    input  logic [31:0] lsu_wb_data,
    output logic        commit_valid,
    output logic [4:0]  commit_arch_rd,
    output logic [5:0]  commit_prd,
    output logic        commit_has_dest,
    output logic        commit_old_prd_valid,
    output logic [5:0]  commit_old_prd,
    output logic        redirect_valid,
    output logic [31:0] redirect_pc,
    output logic        flush_all,
    output logic [1:0]  flush_epoch,
    output logic        squash_valid,
    output logic [7:0]  squash_mask,
    output logic        restore_valid,
    output logic [1:0]  restore_ckpt,
    output logic        bp_update_valid,
    output logic [31:0] bp_update_pc,
    output logic        bp_update_is_cond,
    output logic        bp_update_taken,
    output logic [31:0] bp_update_target,
    output logic        dbg_retire_valid,
    output logic [31:0] dbg_retire_pc,
    output logic [31:0] dbg_retire_insn,
    output logic        dbg_bp_resolve,
    output logic        dbg_bp_mispredict,
    output logic        rob_head_valid,
    output logic [2:0]  rob_head,
    output logic        halted,
    output logic [31:0] exit_code,
    input  logic        halt_enter,
    input  logic        lsu_idle,
    input  logic        ic_idle
);

    localparam int ROB_DEPTH = 8;

    logic [31:0] ent_pc      [0:ROB_DEPTH-1];
    logic [31:0] ent_insn    [0:ROB_DEPTH-1];
    logic [5:0]  ent_prd     [0:ROB_DEPTH-1];
    logic [5:0]  ent_old_prd [0:ROB_DEPTH-1];
    logic        ent_has_dest[0:ROB_DEPTH-1];
    logic [4:0]  ent_arch_rd [0:ROB_DEPTH-1];
    logic        ent_is_load [0:ROB_DEPTH-1];
    logic        ent_is_store[0:ROB_DEPTH-1];
    logic        ent_is_ctrl [0:ROB_DEPTH-1];
    logic        ent_is_cond [0:ROB_DEPTH-1];
    logic        ent_is_ecall[0:ROB_DEPTH-1];
    logic        ent_is_ckpt [0:ROB_DEPTH-1];
    logic [1:0]  ent_ckpt_id[0:ROB_DEPTH-1];
    logic [31:0] ent_pred_npc[0:ROB_DEPTH-1];
    logic        ent_valid   [0:ROB_DEPTH-1];
    logic        ent_complete[0:ROB_DEPTH-1];
    logic [31:0] ent_result  [0:ROB_DEPTH-1];

    logic [2:0]  head;
    logic [2:0]  tail;
    logic [3:0]  count;

    logic        halted_r;
    logic [31:0] exit_code_r;
    logic [31:0] x10_r;
    logic [1:0]  epoch_r;

    logic        head_valid;
    logic        head_complete;
    logic        head_is_store;
    logic        head_is_ecall;
    logic        head_is_ctrl;
    logic        head_is_cond;
    logic        head_is_ckpt;
    logic [1:0]  head_ckpt_id;
    logic [31:0] head_pc;
    logic [31:0] head_insn;
    logic [31:0] head_pred_npc;
    logic [5:0]  head_prd;
    logic [5:0]  head_old_prd;
    logic        head_has_dest;
    logic [4:0]  head_arch_rd;

    logic        can_commit;
    logic        do_commit;
    logic        do_ecall_commit;
    logic        do_ctrl_resolve;

    logic [7:0]  squash_mask_c;
    logic        redirect_valid_c;
    logic [31:0] redirect_pc_c;
    logic        restore_valid_c;
    logic [1:0]  restore_ckpt_c;
    logic        bp_update_valid_c;
    logic        bp_update_is_cond_c;
    logic        bp_update_taken_c;
    logic [31:0] bp_update_target_c;
    logic        dbg_bp_resolve_c;
    logic        dbg_bp_mispredict_c;

    logic        ex_hit;
    logic        lsu_hit;
    logic        ex_is_ctrl;
    logic        ex_is_cond;
    logic        ex_is_ckpt;
    logic [1:0]  ex_ckpt_id;
    logic [31:0] ex_pc;
    logic [31:0] ex_pred_npc;
    logic        ex_mispredict;

    assign rob_disp_ready = (count != 4'd8) && !halted_r;
    assign disp_rob_idx   = tail;

    assign rob_head_valid = head_valid;
    assign rob_head       = head;

    assign head_valid     = ent_valid[head];
    assign head_complete  = ent_complete[head];
    assign head_is_store  = ent_is_store[head];
    assign head_is_ecall  = ent_is_ecall[head];
    assign head_is_ctrl   = ent_is_ctrl[head];
    assign head_is_cond   = ent_is_cond[head];
    assign head_is_ckpt   = ent_is_ckpt[head];
    assign head_ckpt_id   = ent_ckpt_id[head];
    assign head_pc        = ent_pc[head];
    assign head_insn      = ent_insn[head];
    assign head_pred_npc  = ent_pred_npc[head];
    assign head_prd       = ent_prd[head];
    assign head_old_prd   = ent_old_prd[head];
    assign head_has_dest  = ent_has_dest[head];
    assign head_arch_rd   = ent_arch_rd[head];

    assign can_commit = head_valid && head_complete && !halted_r;

    assign do_ecall_commit = can_commit && head_is_ecall && lsu_idle && ic_idle;
    assign do_commit       = can_commit && !head_is_ecall;
    assign do_ctrl_resolve = can_commit && head_is_ctrl;

    assign ex_hit      = ex_valid && ent_valid[ex_rob_idx];
    assign ex_is_ctrl  = ent_is_ctrl[ex_rob_idx];
    assign ex_is_cond  = ent_is_cond[ex_rob_idx];
    assign ex_is_ckpt  = ent_is_ckpt[ex_rob_idx];
    assign ex_ckpt_id  = ent_ckpt_id[ex_rob_idx];
    assign ex_pc       = ent_pc[ex_rob_idx];
    assign ex_pred_npc = ent_pred_npc[ex_rob_idx];
    assign ex_mispredict = (ex_npc != ex_pred_npc);

    assign lsu_hit = lsu_wb_valid && ent_valid[lsu_wb_rob_idx];

    always_comb begin
        squash_mask_c        = 8'b0;
        redirect_valid_c     = 1'b0;
        redirect_pc_c        = 32'b0;
        restore_valid_c      = 1'b0;
        restore_ckpt_c       = 2'b0;
        bp_update_valid_c    = 1'b0;
        bp_update_is_cond_c  = 1'b0;
        bp_update_taken_c    = 1'b0;
        bp_update_target_c   = 32'b0;
        dbg_bp_resolve_c     = 1'b0;
        dbg_bp_mispredict_c  = 1'b0;

        if (ex_hit && ex_is_ctrl && !halted_r) begin
            dbg_bp_resolve_c    = 1'b1;
            bp_update_valid_c   = 1'b1;
            bp_update_is_cond_c = ex_is_cond;
            bp_update_taken_c   = (ex_npc != (ex_pc + 32'd4));
            bp_update_target_c  = ex_npc;
            if (ex_mispredict) begin
                dbg_bp_mispredict_c = 1'b1;
                redirect_valid_c    = 1'b1;
                redirect_pc_c       = ex_npc;
                squash_mask_c       = 8'hFF << (ex_rob_idx + 3'd1);
                if (ex_is_ckpt) begin
                    restore_valid_c = 1'b1;
                    restore_ckpt_c  = ex_ckpt_id;
                end
            end
        end
    end

    assign commit_valid         = do_commit;
    assign commit_arch_rd       = head_arch_rd;
    assign commit_prd           = head_prd;
    assign commit_has_dest      = head_has_dest;
    assign commit_old_prd_valid = head_has_dest && (head_old_prd != 6'd0);
    assign commit_old_prd       = head_old_prd;

    assign redirect_valid = redirect_valid_c;
    assign redirect_pc    = redirect_pc_c;
    assign flush_all      = redirect_valid_c | halt_enter;
    assign flush_epoch    = epoch_r;
    assign squash_valid   = redirect_valid_c;
    assign squash_mask    = squash_mask_c;
    assign restore_valid  = restore_valid_c;
    assign restore_ckpt   = restore_ckpt_c;
    assign bp_update_valid   = bp_update_valid_c;
    assign bp_update_pc      = ex_pc;
    assign bp_update_is_cond = bp_update_is_cond_c;
    assign bp_update_taken   = bp_update_taken_c;
    assign bp_update_target  = bp_update_target_c;

    assign dbg_retire_valid    = do_commit | do_ecall_commit;
    assign dbg_retire_pc       = head_pc;
    assign dbg_retire_insn     = head_insn;
    assign dbg_bp_resolve      = dbg_bp_resolve_c;
    assign dbg_bp_mispredict   = dbg_bp_mispredict_c;

    assign halted    = halted_r;
    assign exit_code = exit_code_r;

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            head       <= 3'd0;
            tail       <= 3'd0;
            count      <= 4'd0;
            halted_r   <= 1'b0;
            exit_code_r<= 32'd0;
            x10_r      <= 32'd0;
            epoch_r    <= 2'd0;
            for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                ent_valid[i]    <= 1'b0;
                ent_complete[i] <= 1'b0;
                ent_pc[i]       <= 32'd0;
                ent_insn[i]     <= 32'd0;
                ent_prd[i]      <= 6'd0;
                ent_old_prd[i]  <= 6'd0;
                ent_has_dest[i] <= 1'b0;
                ent_arch_rd[i]  <= 5'd0;
                ent_is_load[i]  <= 1'b0;
                ent_is_store[i] <= 1'b0;
                ent_is_ctrl[i]  <= 1'b0;
                ent_is_cond[i]  <= 1'b0;
                ent_is_ecall[i] <= 1'b0;
                ent_is_ckpt[i]  <= 1'b0;
                ent_ckpt_id[i]  <= 2'd0;
                ent_pred_npc[i] <= 32'd0;
                ent_result[i]   <= 32'd0;
            end
        end else begin
            if (halt_enter) begin
                epoch_r <= epoch_r + 2'd1;
            end
            if (redirect_valid_c) begin
                epoch_r <= epoch_r + 2'd1;
            end

            if (halted_r) begin
                // frozen
            end else begin
                // dispatch
                if (rob_disp_valid && rob_disp_ready) begin
                    ent_pc[tail]       <= disp_pc;
                    ent_insn[tail]     <= disp_insn;
                    ent_prd[tail]      <= disp_prd;
                    ent_old_prd[tail]  <= disp_old_prd;
                    ent_has_dest[tail] <= disp_has_dest;
                    ent_arch_rd[tail]  <= disp_arch_rd;
                    ent_is_load[tail]  <= disp_is_load;
                    ent_is_store[tail] <= disp_is_store;
                    ent_is_ctrl[tail]  <= disp_is_ctrl;
                    ent_is_cond[tail]  <= disp_is_cond;
                    ent_is_ecall[tail] <= disp_is_ecall;
                    ent_is_ckpt[tail]  <= disp_is_ckpt_owner;
                    ent_ckpt_id[tail]  <= disp_ckpt_id;
                    ent_pred_npc[tail] <= disp_pred_npc;
                    ent_valid[tail]    <= 1'b1;
                    ent_complete[tail] <= disp_is_ecall;
                    ent_result[tail]   <= 32'd0;
                    tail <= tail + 3'd1;
                end

                // execution completion
                if (ex_hit) begin
                    ent_complete[ex_rob_idx] <= 1'b1;
                    ent_result[ex_rob_idx]   <= ex_result;
                end

                // lsu completion
                if (lsu_hit) begin
                    ent_complete[lsu_wb_rob_idx] <= 1'b1;
                    ent_result[lsu_wb_rob_idx]   <= lsu_wb_data;
                end

                // squash younger entries
                if (redirect_valid_c) begin
                    for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                        if (squash_mask_c[i]) begin
                            ent_valid[i]    <= 1'b0;
                            ent_complete[i] <= 1'b0;
                        end
                    end
                end

                // commit
                if (do_commit) begin
                    ent_valid[head] <= 1'b0;
                    head <= head + 3'd1;
                    if (head_has_dest && head_arch_rd == 5'd10) begin
                        x10_r <= ent_result[head];
                    end
                end

                if (do_ecall_commit) begin
                    ent_valid[head] <= 1'b0;
                    head <= head + 3'd1;
                    halted_r    <= 1'b1;
                    exit_code_r <= x10_r;
                end

                // count update
                if (rob_disp_valid && rob_disp_ready) begin
                    if (do_commit || do_ecall_commit) begin
                        count <= count;
                    end else begin
                        count <= count + 4'd1;
                    end
                end else begin
                    if (do_commit || do_ecall_commit) begin
                        count <= count - 4'd1;
                    end
                end
            end
        end
    end

endmodule
