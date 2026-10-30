module branch_predictor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] bp_lookup_pc,
    output logic        bp_pred_taken,
    output logic [31:0] bp_pred_target,
    output logic        bp_btb_hit,
    input  logic        bp_update_valid,
    input  logic [31:0] bp_update_pc,
    input  logic [31:0] bp_update_target,
    input  logic        bp_update_is_cond,
    input  logic        bp_update_actual_taken,
    input  logic        bp_update_is_jalr
);

    // Packed storage: avoids constant-indexed array writes inside
    // always_ff (Icarus -g2012 limitation).
    logic [15:0]  btb_valid;
    logic [415:0] btb_tag;    // 16 x 26
    logic [511:0] btb_target; // 16 x 32
    logic [31:0]  btb_type;   // 16 x 2
    logic [31:0]  bht;        // 16 x 2

    logic [3:0]  lookup_idx;
    logic [25:0] lookup_tag;
    logic [3:0]  update_idx;
    logic [25:0] update_tag;

    assign lookup_idx = bp_lookup_pc[5:2];
    assign lookup_tag = bp_lookup_pc[31:6];
    assign update_idx = bp_update_pc[5:2];
    assign update_tag = bp_update_pc[31:6];

    logic        lookup_hit;
    logic [1:0]  lookup_type;
    logic [1:0]  lookup_bht;
    logic        lookup_bht_taken;
    logic [25:0] lookup_tag_sel;
    logic [31:0] lookup_target_sel;

    assign lookup_tag_sel    = btb_tag[26*lookup_idx +: 26];
    assign lookup_target_sel = btb_target[32*lookup_idx +: 32];
    assign lookup_hit        = btb_valid[lookup_idx] && (lookup_tag_sel == lookup_tag);
    assign lookup_type       = btb_type[2*lookup_idx +: 2];
    assign lookup_bht        = bht[2*lookup_idx +: 2];
    assign lookup_bht_taken  = lookup_bht[1];

    always_comb begin
        bp_btb_hit     = lookup_hit;
        bp_pred_taken  = 1'b0;
        bp_pred_target = bp_lookup_pc + 32'd4;
        if (lookup_hit) begin
            if (lookup_type == 2'b00) begin
                if (lookup_bht_taken) begin
                    bp_pred_taken  = 1'b1;
                    bp_pred_target = lookup_target_sel;
                end else begin
                    bp_pred_taken  = 1'b0;
                    bp_pred_target = bp_lookup_pc + 32'd4;
                end
            end else begin
                bp_pred_taken  = 1'b1;
                bp_pred_target = lookup_target_sel;
            end
        end
    end

    // Per-entry update helpers (computed combinationally, written with
    // a variable index into packed vectors).
    logic [1:0]  bht_cur;
    logic [1:0]  bht_nxt;
    logic        btb_hit_upd;
    logic [1:0]  btb_type_cur;
    logic [31:0] btb_target_cur;

    assign bht_cur        = bht[2*update_idx +: 2];
    assign btb_hit_upd    = btb_valid[update_idx] && (btb_tag[26*update_idx +: 26] == update_tag);
    assign btb_type_cur   = btb_type[2*update_idx +: 2];
    assign btb_target_cur = btb_target[32*update_idx +: 32];

    always_comb begin
        bht_nxt = bht_cur;
        if (bp_update_valid && bp_update_is_cond) begin
            if (bp_update_actual_taken) begin
                if (bht_cur != 2'b11) bht_nxt = bht_cur + 2'b01;
            end else begin
                if (bht_cur != 2'b00) bht_nxt = bht_cur - 2'b01;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            btb_valid  <= 16'd0;
            btb_tag    <= 416'd0;
            btb_target <= 512'd0;
            btb_type   <= 32'd0;
            bht        <= 32'h5555_5555; // every 2-bit counter = 01 (weak not-taken)
        end else if (bp_update_valid) begin
            if (bp_update_is_cond) begin
                bht[2*update_idx +: 2] <= bht_nxt;

                if (!btb_hit_upd) begin
                    if (bp_update_actual_taken) begin
                        btb_valid[update_idx]              <= 1'b1;
                        btb_tag[26*update_idx +: 26]       <= update_tag;
                        btb_target[32*update_idx +: 32]    <= bp_update_target;
                        btb_type[2*update_idx +: 2]        <= 2'b00;
                    end
                end else begin
                    if (btb_type_cur != 2'b00) begin
                        btb_type[2*update_idx +: 2]     <= 2'b00;
                        btb_target[32*update_idx +: 32] <= bp_update_target;
                    end else if (btb_target_cur != bp_update_target) begin
                        btb_target[32*update_idx +: 32] <= bp_update_target;
                    end
                end
            end else begin
                if (!btb_hit_upd ||
                    (btb_target_cur != bp_update_target) ||
                    (btb_type_cur != (bp_update_is_jalr ? 2'b10 : 2'b01))) begin
                    btb_valid[update_idx]           <= 1'b1;
                    btb_tag[26*update_idx +: 26]    <= update_tag;
                    btb_target[32*update_idx +: 32] <= bp_update_target;
                    btb_type[2*update_idx +: 2]     <= bp_update_is_jalr ? 2'b10 : 2'b01;
                end
            end
        end
    end

endmodule
