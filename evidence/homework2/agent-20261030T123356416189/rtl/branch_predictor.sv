module branch_predictor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        predict_req_valid,
    input  logic [31:0] predict_pc,
    output logic [31:0] predict_npc,
    output logic        predict_hit,
    output logic        predict_taken,
    input  logic        update_valid,
    input  logic [31:0] update_pc,
    input  logic        update_is_cond,
    input  logic        update_taken,
    input  logic [31:0] update_target,
    input  logic        flush
);

    logic        btb_valid [0:15];
    logic [23:0] btb_tag   [0:15];
    logic [31:0] btb_target[0:15];
    logic        btb_cond  [0:15];
    logic [1:0]  bht       [0:15];

    logic [3:0]  p_idx;
    logic [23:0] p_tag;
    logic [3:0]  u_idx;
    logic [23:0] u_tag;

    logic        hit_r;
    logic        cond_r;
    logic [31:0] target_r;
    logic [1:0]  ctr_r;
    logic        bht_taken_r;

    assign p_idx = predict_pc[5:2];
    assign p_tag = predict_pc[31:8];
    assign u_idx = update_pc[5:2];
    assign u_tag = update_pc[31:8];

    always_comb begin
        hit_r       = 1'b0;
        cond_r      = 1'b0;
        target_r    = 32'b0;
        ctr_r       = 2'b01;
        bht_taken_r = 1'b0;
        if (btb_valid[p_idx] && (btb_tag[p_idx] == p_tag)) begin
            hit_r    = 1'b1;
            cond_r   = btb_cond[p_idx];
            target_r = btb_target[p_idx];
        end
        ctr_r       = bht[p_idx];
        bht_taken_r = ctr_r[1];
    end

    always_comb begin
        predict_hit   = 1'b0;
        predict_taken = 1'b0;
        predict_npc   = predict_pc + 32'd4;
        if (predict_req_valid) begin
            if (hit_r) begin
                predict_hit = 1'b1;
                if (cond_r) begin
                    if (bht_taken_r) begin
                        predict_taken = 1'b1;
                        predict_npc   = target_r;
                    end
                end else begin
                    predict_taken = 1'b1;
                    predict_npc   = target_r;
                end
            end
        end
    end

    // Full-vector next-state temporaries: no constant/part select on the LHS
    // of a procedural assignment, so each table entry is driven from exactly
    // one process and Icarus cannot collapse the select into a multi-driver.
    logic        btb_valid_nxt [0:15];
    logic [23:0] btb_tag_nxt   [0:15];
    logic [31:0] btb_target_nxt[0:15];
    logic        btb_cond_nxt  [0:15];
    logic [1:0]  bht_nxt       [0:15];

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) begin
                btb_valid[i]  <= 1'b0;
                btb_tag[i]    <= 24'b0;
                btb_target[i] <= 32'b0;
                btb_cond[i]   <= 1'b0;
                bht[i]        <= 2'b01;
            end
        end else begin
            for (i = 0; i < 16; i = i + 1) begin
                btb_valid_nxt[i]  = btb_valid[i];
                btb_tag_nxt[i]    = btb_tag[i];
                btb_target_nxt[i] = btb_target[i];
                btb_cond_nxt[i]   = btb_cond[i];
                bht_nxt[i]        = bht[i];
            end

            if (flush) begin
                for (i = 0; i < 16; i = i + 1) begin
                    btb_valid_nxt[i] = 1'b0;
                end
            end else if (update_valid) begin
                btb_valid_nxt[u_idx]  = 1'b1;
                btb_tag_nxt[u_idx]    = u_tag;
                btb_target_nxt[u_idx] = update_target;
                btb_cond_nxt[u_idx]   = update_is_cond;
                if (update_is_cond) begin
                    if (update_taken) begin
                        if (bht[u_idx] != 2'b11)
                            bht_nxt[u_idx] = bht[u_idx] + 2'b01;
                    end else begin
                        if (bht[u_idx] != 2'b00)
                            bht_nxt[u_idx] = bht[u_idx] - 2'b01;
                    end
                end
            end

            for (i = 0; i < 16; i = i + 1) begin
                btb_valid[i]  <= btb_valid_nxt[i];
                btb_tag[i]    <= btb_tag_nxt[i];
                btb_target[i] <= btb_target_nxt[i];
                btb_cond[i]   <= btb_cond_nxt[i];
                bht[i]        <= bht_nxt[i];
            end
        end
    end

endmodule
