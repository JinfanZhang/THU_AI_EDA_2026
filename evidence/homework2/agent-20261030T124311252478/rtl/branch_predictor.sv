module branch_predictor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] pc_query,
    output logic        pred_valid,
    output logic        pred_taken,
    output logic [31:0] pred_target,
    input  logic        resolve_valid,
    input  logic [31:0] resolve_pc,
    input  logic        resolve_taken,
    input  logic [31:0] resolve_target,
    input  logic        resolve_is_cond
);

    // BTB entry: valid, tag, target
    localparam BTB_SIZE = 16;
    localparam BHT_SIZE = 16;

    logic [BTB_SIZE-1:0] btb_valid;
    logic [BTB_SIZE-1:0][31:0] btb_tag;
    logic [BTB_SIZE-1:0][31:0] btb_target;

    logic [BHT_SIZE-1:0][1:0] bht_state;

    logic [3:0] query_idx;
    logic [31:0] query_tag;
    logic [3:0] resolve_idx;
    logic [31:0] resolve_tag;

    assign query_idx  = pc_query[5:2];
    assign query_tag  = pc_query[31:6];
    assign resolve_idx = resolve_pc[5:2];
    assign resolve_tag = resolve_pc[31:6];

    // Prediction lookup
    always_comb begin
        pred_valid  = 1'b0;
        pred_taken  = 1'b0;
        pred_target = 32'h0;
        if (btb_valid[query_idx] && (btb_tag[query_idx] == query_tag)) begin
            pred_valid = 1'b1;
            pred_target = btb_target[query_idx];
            // For conditional branches, use BHT; for JAL/JALR, always taken
            // We don't have type info in BTB, so we use BHT for all hits.
            // The resolve_is_cond input tells us if it's conditional for updates.
            // For prediction, we assume BTB hit means branch/jump; BHT decides taken.
            pred_taken = (bht_state[query_idx][1] == 1'b1);
        end
    end

    // Update logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            btb_valid <= '0;
            btb_tag <= '0;
            btb_target <= '0;
            bht_state <= {BHT_SIZE{2'b01}};
        end else begin
            if (resolve_valid) begin
                // Update BTB
                if (!btb_valid[resolve_idx] || (btb_tag[resolve_idx] != resolve_tag)) begin
                    btb_valid[resolve_idx]  <= 1'b1;
                    btb_tag[resolve_idx]    <= resolve_tag;
                    btb_target[resolve_idx] <= resolve_target;
                end else begin
                    // Update target if it changed
                    if (btb_target[resolve_idx] != resolve_target) begin
                        btb_target[resolve_idx] <= resolve_target;
                    end
                end

                // Update BHT only for conditional branches
                if (resolve_is_cond) begin
                    case (bht_state[resolve_idx])
                        2'b00: bht_state[resolve_idx] <= resolve_taken ? 2'b01 : 2'b00;
                        2'b01: bht_state[resolve_idx] <= resolve_taken ? 2'b10 : 2'b00;
                        2'b10: bht_state[resolve_idx] <= resolve_taken ? 2'b11 : 2'b01;
                        2'b11: bht_state[resolve_idx] <= resolve_taken ? 2'b11 : 2'b10;
                        default: bht_state[resolve_idx] <= 2'b01;
                    endcase
                end
            end
        end
    end

endmodule
