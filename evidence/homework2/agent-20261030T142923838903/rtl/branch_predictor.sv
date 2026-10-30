module branch_predictor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] lookup_pc,
    input  logic        update_valid,
    input  logic [31:0] update_pc,
    input  logic [31:0] update_target,
    input  logic        update_is_branch,
    input  logic        update_is_jal,
    input  logic        update_is_jalr,
    input  logic        update_taken,
    output logic        pred_valid,
    output logic        pred_taken,
    output logic [31:0] pred_target,
    output logic [31:0] pred_next_pc
);

    // BTB: 16 entries, direct-mapped, index PC[5:2], tag PC[31:6]
    // Stored as packed vectors so Icarus never sees a constant array select
    // inside an always_* process.
    logic [15:0]   btb_valid;
    logic [415:0]  btb_tag;    // 16 x 26
    logic [511:0]  btb_target; // 16 x 32
    logic [31:0]   btb_type;   // 16 x 2  (00=none, 01=branch, 10=jal, 11=jalr)

    // BHT: 16 entries, 2-bit saturating counters, reset to 01 (weakly not-taken)
    logic [31:0]   bht;        // 16 x 2

    // Lookup (combinational, old contents)
    logic [3:0]  lu_idx;
    logic [25:0] lu_tag;
    logic        lu_btb_hit;
    logic [1:0]  lu_type;
    logic [31:0] lu_target;
    logic [1:0]  lu_bht;
    logic        lu_bht_taken;

    assign lu_idx  = lookup_pc[5:2];
    assign lu_tag  = lookup_pc[31:6];
    assign lu_btb_hit = btb_valid[lu_idx] && (btb_tag[{lu_idx, 5'b00000} +: 26] == lu_tag);
    assign lu_type = btb_type[{lu_idx, 1'b0} +: 2];
    assign lu_target = btb_target[{lu_idx, 5'b00000} +: 32];
    assign lu_bht = bht[{lu_idx, 1'b0} +: 2];
    assign lu_bht_taken = lu_bht[1];

    always_comb begin
        pred_valid    = 1'b0;
        pred_taken    = 1'b0;
        pred_target   = 32'b0;
        pred_next_pc  = lookup_pc + 32'd4;

        if (lu_btb_hit) begin
            if (lu_type == 2'b01) begin
                // conditional branch: BHT decides
                pred_valid = 1'b1;
                if (lu_bht_taken) begin
                    pred_taken   = 1'b1;
                    pred_target  = lu_target;
                    pred_next_pc = lu_target;
                end else begin
                    pred_taken   = 1'b0;
                    pred_target  = lu_target;
                    pred_next_pc = lookup_pc + 32'd4;
                end
            end else if (lu_type == 2'b10 || lu_type == 2'b11) begin
                // JAL / JALR: always taken to target
                pred_valid   = 1'b1;
                pred_taken   = 1'b1;
                pred_target  = lu_target;
                pred_next_pc = lu_target;
            end
        end
    end

    // Update logic
    logic [3:0]  up_idx;
    logic [25:0] up_tag;
    logic [1:0]  up_type;
    logic        up_alloc;
    logic [1:0]  up_bht_cur;
    logic [1:0]  up_bht_next;
    logic        up_hit;

    assign up_idx = update_pc[5:2];
    assign up_tag = update_pc[31:6];
    assign up_hit = btb_valid[up_idx] && (btb_tag[{up_idx, 5'b00000} +: 26] == up_tag);
    assign up_bht_cur = bht[{up_idx, 1'b0} +: 2];

    always_comb begin
        up_type = update_is_branch ? 2'b01 :
                  update_is_jal    ? 2'b10 :
                  update_is_jalr   ? 2'b11 : 2'b00;

        // BTB allocation/update rules
        up_alloc = 1'b0;
        if (update_valid) begin
            if (update_is_branch) begin
                // allocate only on BTB miss && taken; update if hit with target/type change
                if (!up_hit) begin
                    if (update_taken) up_alloc = 1'b1;
                end else begin
                    if ((btb_target[{up_idx, 5'b00000} +: 32] != update_target) ||
                        (btb_type[{up_idx, 1'b0} +: 2] != up_type))
                        up_alloc = 1'b1;
                end
            end else if (update_is_jal || update_is_jalr) begin
                if (!up_hit) up_alloc = 1'b1;
                else if ((btb_target[{up_idx, 5'b00000} +: 32] != update_target) ||
                         (btb_type[{up_idx, 1'b0} +: 2] != up_type))
                    up_alloc = 1'b1;
            end
        end

        // BHT next value for conditional branch
        up_bht_next = up_bht_cur;
        if (update_valid && update_is_branch) begin
            if (update_taken) begin
                if (up_bht_cur != 2'b11) up_bht_next = up_bht_cur + 2'b01;
            end else begin
                if (up_bht_cur != 2'b00) up_bht_next = up_bht_cur - 2'b01;
            end
        end
    end

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            btb_valid  <= 16'b0;
            btb_tag    <= 416'b0;
            btb_target <= 512'b0;
            btb_type   <= 32'b0;
            bht        <= 32'h5555_5555; // every 2-bit counter = 2'b01
        end else begin
            if (update_valid) begin
                if (update_is_branch) begin
                    bht[{up_idx, 1'b0} +: 2] <= up_bht_next;
                end
                if (up_alloc) begin
                    btb_valid[up_idx] <= 1'b1;
                    btb_tag[{up_idx, 5'b00000} +: 26]    <= up_tag;
                    btb_target[{up_idx, 5'b00000} +: 32] <= update_target;
                    btb_type[{up_idx, 1'b0} +: 2]        <= up_type;
                end
            end
        end
    end

endmodule
