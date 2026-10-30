module reorder_buffer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        rob_alloc_req_valid,
    input  logic [31:0] rob_alloc_req_pc,
    input  logic [31:0] rob_alloc_req_insn,
    input  logic [5:0]  rob_alloc_req_prd,
    input  logic [5:0]  rob_alloc_req_old_prd,
    output logic        rob_alloc_grant,
    output logic [2:0]  rob_alloc_idx,
    output logic        rob_full,
    input  logic        rob_complete_valid_alu,
    input  logic [2:0]  rob_complete_rob_idx_alu,
    input  logic [5:0]  rob_complete_prd_alu,
    input  logic [31:0] rob_complete_data_alu,
    input  logic        rob_mispredict_valid,
    input  logic [31:0] rob_mispredict_pc,
    input  logic        rob_complete_valid_lsu,
    input  logic [2:0]  rob_complete_rob_idx_lsu,
    input  logic [5:0]  rob_complete_prd_lsu,
    input  logic [31:0] rob_complete_data_lsu,
    output logic        rob_commit_valid,
    output logic [4:0]  rob_commit_arch_reg,
    output logic [5:0]  rob_commit_phys_reg,
    output logic [5:0]  rob_commit_old_phys_reg,
    output logic        rob_restore_valid,
    output logic [2:0]  rob_restore_checkpoint_id,
    output logic        rob_squash_valid,
    output logic [2:0]  rob_squash_rob_idx,
    output logic        rob_retire_valid,
    output logic [31:0] rob_retire_pc,
    output logic [31:0] rob_retire_insn,
    output logic        rob_epoch,
    output logic [1:0]  rob_epoch_val,
    output logic        rob_flush,
    output logic [31:0] rob_redirect_pc,
    output logic        rob_halt_request,
    output logic        rob_halted,
    output logic [31:0] rob_exit_code,
    output logic        rob_dbg_ooo_bypass,
    input  logic        dmem_waiting
);

    localparam ROB_DEPTH = 8;
    localparam ROB_IDX_W = 3;

    typedef struct packed {
        logic        valid;
        logic        complete;
        logic [31:0] pc;
        logic [31:0] insn;
        logic [5:0]  prd;
        logic [5:0]  old_prd;
        logic [4:0]  arch_reg;
        logic        is_ecall;
        logic        is_store;
        logic        is_branch;
        logic        mispredict;
        logic [31:0] pred_pc;
        logic [31:0] actual_pc;
        logic        store_committed;
    } rob_entry_t;

    rob_entry_t rob_entries [ROB_DEPTH];
    logic [ROB_IDX_W-1:0] head_ptr;
    logic [ROB_IDX_W-1:0] tail_ptr;
    logic [ROB_IDX_W-1:0] num_entries;
    logic [ROB_IDX_W-1:0] next_free_idx;
    logic [ROB_IDX_W-1:0] checkpoint_id;
    logic [ROB_IDX_W-1:0] restore_checkpoint_id_reg;
    logic        restore_valid_reg;
    logic        squash_valid_reg;
    logic [ROB_IDX_W-1:0] squash_rob_idx_reg;
    logic        flush_reg;
    logic [1:0]  epoch_val_reg;
    logic        halted_reg;
    logic [31:0] exit_code_reg;
    logic        halt_request_reg;
    logic        retire_valid_reg;
    logic [31:0] retire_pc_reg;
    logic [31:0] retire_insn_reg;
    logic        dbg_ooo_bypass_reg;

    logic        rob_full_comb;
    logic        rob_alloc_grant_comb;
    logic [ROB_IDX_W-1:0] rob_alloc_idx_comb;
    logic        commit_valid_comb;
    logic [4:0]  commit_arch_reg_comb;
    logic [5:0]  commit_phys_reg_comb;
    logic [5:0]  commit_old_phys_reg_comb;
    logic        retire_valid_comb;
    logic [31:0] retire_pc_comb;
    logic [31:0] retire_insn_comb;
    logic        restore_valid_comb;
    logic [ROB_IDX_W-1:0] restore_checkpoint_id_comb;
    logic        squash_valid_comb;
    logic [ROB_IDX_W-1:0] squash_rob_idx_comb;
    logic        flush_comb;
    logic [1:0]  epoch_val_comb;
    logic        halted_comb;
    logic [31:0] exit_code_comb;
    logic        halt_request_comb;
    logic        dbg_ooo_bypass_comb;
    logic [31:0] redirect_pc_comb;

    always_comb begin
        rob_full_comb = (num_entries == ROB_DEPTH[ROB_IDX_W-1:0]);
        rob_alloc_grant_comb = rob_alloc_req_valid && !rob_full_comb && !halted_reg && !halt_request_reg;
        rob_alloc_idx_comb = tail_ptr;
        commit_valid_comb = 1'b0;
        commit_arch_reg_comb = 5'b0;
        commit_phys_reg_comb = 6'b0;
        commit_old_phys_reg_comb = 6'b0;
        retire_valid_comb = 1'b0;
        retire_pc_comb = 32'b0;
        retire_insn_comb = 32'b0;
        restore_valid_comb = 1'b0;
        restore_checkpoint_id_comb = 3'b0;
        squash_valid_comb = 1'b0;
        squash_rob_idx_comb = 3'b0;
        flush_comb = 1'b0;
        epoch_val_comb = epoch_val_reg;
        halted_comb = halted_reg;
        exit_code_comb = exit_code_reg;
        halt_request_comb = halt_request_reg;
        dbg_ooo_bypass_comb = 1'b0;
        redirect_pc_comb = 32'b0;

        if (rob_mispredict_valid && !halted_reg) begin
            flush_comb = 1'b1;
            epoch_val_comb = epoch_val_reg + 2'b01;
            redirect_pc_comb = rob_mispredict_pc;
            squash_valid_comb = 1'b1;
            squash_rob_idx_comb = 3'b0;
            restore_valid_comb = 1'b1;
            restore_checkpoint_id_comb = checkpoint_id;
        end

        if (rob_entries[head_ptr].valid && rob_entries[head_ptr].complete && !halted_reg) begin
            if (rob_entries[head_ptr].is_ecall) begin
                if (!halt_request_reg) begin
                    halt_request_comb = 1'b1;
                end
                retire_valid_comb = 1'b1;
                retire_pc_comb = rob_entries[head_ptr].pc;
                retire_insn_comb = rob_entries[head_ptr].insn;
                commit_valid_comb = 1'b0;
            end else if (rob_entries[head_ptr].is_store) begin
                if (rob_entries[head_ptr].store_committed) begin
                    retire_valid_comb = 1'b1;
                    retire_pc_comb = rob_entries[head_ptr].pc;
                    retire_insn_comb = rob_entries[head_ptr].insn;
                    commit_valid_comb = 1'b0;
                end
            end else begin
                retire_valid_comb = 1'b1;
                retire_pc_comb = rob_entries[head_ptr].pc;
                retire_insn_comb = rob_entries[head_ptr].insn;
                commit_valid_comb = 1'b1;
                commit_arch_reg_comb = rob_entries[head_ptr].arch_reg;
                commit_phys_reg_comb = rob_entries[head_ptr].prd;
                commit_old_phys_reg_comb = rob_entries[head_ptr].old_prd;
            end
        end

        if (dmem_waiting && !halted_reg) begin
            if (rob_entries[0].valid && !rob_entries[0].complete && !rob_entries[0].is_store && !rob_entries[0].is_ecall) begin
                dbg_ooo_bypass_comb = 1'b1;
            end else if (rob_entries[1].valid && !rob_entries[1].complete && !rob_entries[1].is_store && !rob_entries[1].is_ecall) begin
                dbg_ooo_bypass_comb = 1'b1;
            end else if (rob_entries[2].valid && !rob_entries[2].complete && !rob_entries[2].is_store && !rob_entries[2].is_ecall) begin
                dbg_ooo_bypass_comb = 1'b1;
            end else if (rob_entries[3].valid && !rob_entries[3].complete && !rob_entries[3].is_store && !rob_entries[3].is_ecall) begin
                dbg_ooo_bypass_comb = 1'b1;
            end else if (rob_entries[4].valid && !rob_entries[4].complete && !rob_entries[4].is_store && !rob_entries[4].is_ecall) begin
                dbg_ooo_bypass_comb = 1'b1;
            end else if (rob_entries[5].valid && !rob_entries[5].complete && !rob_entries[5].is_store && !rob_entries[5].is_ecall) begin
                dbg_ooo_bypass_comb = 1'b1;
            end else if (rob_entries[6].valid && !rob_entries[6].complete && !rob_entries[6].is_store && !rob_entries[6].is_ecall) begin
                dbg_ooo_bypass_comb = 1'b1;
            end else if (rob_entries[7].valid && !rob_entries[7].complete && !rob_entries[7].is_store && !rob_entries[7].is_ecall) begin
                dbg_ooo_bypass_comb = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int idx = 0; idx < ROB_DEPTH; idx++) begin
                rob_entries[idx].valid <= 1'b0;
                rob_entries[idx].complete <= 1'b0;
                rob_entries[idx].pc <= 32'b0;
                rob_entries[idx].insn <= 32'b0;
                rob_entries[idx].prd <= 6'b0;
                rob_entries[idx].old_prd <= 6'b0;
                rob_entries[idx].arch_reg <= 5'b0;
                rob_entries[idx].is_ecall <= 1'b0;
                rob_entries[idx].is_store <= 1'b0;
                rob_entries[idx].is_branch <= 1'b0;
                rob_entries[idx].mispredict <= 1'b0;
                rob_entries[idx].pred_pc <= 32'b0;
                rob_entries[idx].actual_pc <= 32'b0;
                rob_entries[idx].store_committed <= 1'b0;
            end
            head_ptr <= 3'b0;
            tail_ptr <= 3'b0;
            num_entries <= 3'b0;
            next_free_idx <= 3'b0;
            checkpoint_id <= 3'b0;
            restore_valid_reg <= 1'b0;
            restore_checkpoint_id_reg <= 3'b0;
            squash_valid_reg <= 1'b0;
            squash_rob_idx_reg <= 3'b0;
            flush_reg <= 1'b0;
            epoch_val_reg <= 2'b0;
            halted_reg <= 1'b0;
            exit_code_reg <= 32'b0;
            halt_request_reg <= 1'b0;
            retire_valid_reg <= 1'b0;
            retire_pc_reg <= 32'b0;
            retire_insn_reg <= 32'b0;
            dbg_ooo_bypass_reg <= 1'b0;
        end else begin
            if (rob_mispredict_valid && !halted_reg) begin
                for (int idx = 0; idx < ROB_DEPTH; idx++) begin
                    if (rob_entries[idx].valid && rob_entries[idx].is_branch && rob_entries[idx].mispredict) begin
                        rob_entries[idx].valid <= 1'b0;
                        rob_entries[idx].complete <= 1'b0;
                    end
                end
                head_ptr <= head_ptr;
                tail_ptr <= tail_ptr;
                num_entries <= num_entries;
                next_free_idx <= next_free_idx;
                checkpoint_id <= checkpoint_id + 3'b1;
                restore_valid_reg <= restore_valid_comb;
                restore_checkpoint_id_reg <= restore_checkpoint_id_comb;
                squash_valid_reg <= squash_valid_comb;
                squash_rob_idx_reg <= squash_rob_idx_comb;
                flush_reg <= flush_comb;
                epoch_val_reg <= epoch_val_comb;
                halted_reg <= halted_comb;
                exit_code_reg <= exit_code_comb;
                halt_request_reg <= halt_request_comb;
                retire_valid_reg <= retire_valid_comb;
                retire_pc_reg <= retire_pc_comb;
                retire_insn_reg <= retire_insn_comb;
                dbg_ooo_bypass_reg <= dbg_ooo_bypass_comb;
            end else begin
                if (rob_alloc_grant_comb) begin
                    rob_entries[tail_ptr].valid <= 1'b1;
                    rob_entries[tail_ptr].complete <= 1'b0;
                    rob_entries[tail_ptr].pc <= rob_alloc_req_pc;
                    rob_entries[tail_ptr].insn <= rob_alloc_req_insn;
                    rob_entries[tail_ptr].prd <= rob_alloc_req_prd;
                    rob_entries[tail_ptr].old_prd <= rob_alloc_req_old_prd;
                    rob_entries[tail_ptr].arch_reg <= rob_alloc_req_insn[11:7];
                    rob_entries[tail_ptr].is_ecall <= (rob_alloc_req_insn == 32'h0000_0073);
                    rob_entries[tail_ptr].is_store <= (rob_alloc_req_insn[6:0] == 7'b0100011);
                    rob_entries[tail_ptr].is_branch <= (rob_alloc_req_insn[6:0] == 7'b1100011) || (rob_alloc_req_insn[6:0] == 7'b1101111) || (rob_alloc_req_insn[6:0] == 7'b1100111);
                    rob_entries[tail_ptr].mispredict <= 1'b0;
                    rob_entries[tail_ptr].pred_pc <= 32'b0;
                    rob_entries[tail_ptr].actual_pc <= 32'b0;
                    rob_entries[tail_ptr].store_committed <= 1'b0;
                    tail_ptr <= tail_ptr + 3'b1;
                    num_entries <= num_entries + 3'b1;
                end

                if (rob_complete_valid_alu) begin
                    rob_entries[rob_complete_rob_idx_alu].complete <= 1'b1;
                    rob_entries[rob_complete_rob_idx_alu].prd <= rob_complete_prd_alu;
                end

                if (rob_complete_valid_lsu) begin
                    rob_entries[rob_complete_rob_idx_lsu].complete <= 1'b1;
                    rob_entries[rob_complete_rob_idx_lsu].prd <= rob_complete_prd_lsu;
                    if (rob_entries[rob_complete_rob_idx_lsu].is_store) begin
                        rob_entries[rob_complete_rob_idx_lsu].store_committed <= 1'b1;
                    end
                end

                if (commit_valid_comb && !rob_entries[head_ptr].is_ecall && !rob_entries[head_ptr].is_store) begin
                    rob_entries[head_ptr].valid <= 1'b0;
                    head_ptr <= head_ptr + 3'b1;
                    num_entries <= num_entries - 3'b1;
                end else if (retire_valid_comb && rob_entries[head_ptr].is_ecall) begin
                    rob_entries[head_ptr].valid <= 1'b0;
                    head_ptr <= head_ptr + 3'b1;
                    num_entries <= num_entries - 3'b1;
                end else if (retire_valid_comb && rob_entries[head_ptr].is_store && rob_entries[head_ptr].store_committed) begin
                    rob_entries[head_ptr].valid <= 1'b0;
                    head_ptr <= head_ptr + 3'b1;
                    num_entries <= num_entries - 3'b1;
                end

                if (halt_request_comb && !halted_reg) begin
                    halted_comb = 1'b1;
                    exit_code_comb = 32'b0;
                end

                restore_valid_reg <= restore_valid_comb;
                restore_checkpoint_id_reg <= restore_checkpoint_id_comb;
                squash_valid_reg <= squash_valid_comb;
                squash_rob_idx_reg <= squash_rob_idx_comb;
                flush_reg <= flush_comb;
                epoch_val_reg <= epoch_val_comb;
                halted_reg <= halted_comb;
                exit_code_reg <= exit_code_comb;
                halt_request_reg <= halt_request_comb;
                retire_valid_reg <= retire_valid_comb;
                retire_pc_reg <= retire_pc_comb;
                retire_insn_reg <= retire_insn_comb;
                dbg_ooo_bypass_reg <= dbg_ooo_bypass_comb;
            end
        end
    end

    assign rob_alloc_grant = rob_alloc_grant_comb;
    assign rob_alloc_idx = rob_alloc_idx_comb;
    assign rob_full = rob_full_comb;
    assign rob_commit_valid = commit_valid_comb;
    assign rob_commit_arch_reg = commit_arch_reg_comb;
    assign rob_commit_phys_reg = commit_phys_reg_comb;
    assign rob_commit_old_phys_reg = commit_old_phys_reg_comb;
    assign rob_restore_valid = restore_valid_reg;
    assign rob_restore_checkpoint_id = restore_checkpoint_id_reg;
    assign rob_squash_valid = squash_valid_reg;
    assign rob_squash_rob_idx = squash_rob_idx_reg;
    assign rob_retire_valid = retire_valid_reg;
    assign rob_retire_pc = retire_pc_reg;
    assign rob_retire_insn = retire_insn_reg;
    assign rob_epoch = flush_reg;
    assign rob_epoch_val = epoch_val_reg;
    assign rob_flush = flush_reg;
    assign rob_redirect_pc = redirect_pc_comb;
    assign rob_halt_request = halt_request_reg;
    assign rob_halted = halted_reg;
    assign rob_exit_code = exit_code_reg;
    assign rob_dbg_ooo_bypass = dbg_ooo_bypass_reg;

endmodule
