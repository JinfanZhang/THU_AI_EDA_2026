module branch_predictor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] pc_query,
    output logic        pred_pc_valid,
    output logic [31:0] pred_pc,
    input  logic        update_valid,
    input  logic [31:0] update_pc,
    input  logic        update_taken,
    input  logic [31:0] update_target,
    input  logic        update_is_branch,
    input  logic        update_is_jal,
    input  logic        update_is_jalr,
    input  logic [1:0]  update_epoch
);

    // BTB entry: valid, tag[31:6], target[31:0], type[1:0]
    // type: 00 = none, 01 = branch, 10 = jal, 11 = jalr
    logic [15:0] btb_valid;
    logic [15:0][25:0] btb_tag;
    logic [15:0][31:0] btb_target;
    logic [15:0][1:0]  btb_type;

    // BHT: 2-bit saturating counters, 16 entries
    logic [15:0][1:0] bht;

    logic [3:0] query_idx;
    logic [25:0] query_tag;
    logic [3:0] update_idx;
    logic [25:0] update_tag;

    assign query_idx = pc_query[5:2];
    assign query_tag = pc_query[31:6];
    assign update_idx = update_pc[5:2];
    assign update_tag = update_pc[31:6];

    // Prediction lookup (combinational)
    logic btb_hit;
    logic [1:0] bht_state;
    logic [1:0] hit_type;
    logic [31:0] hit_target;

    // Icarus-friendly lookup: use a hand-unrolled case to avoid constant
    // array-index selects in always_comb.
    always_comb begin
        btb_hit    = 1'b0;
        bht_state  = 2'b00;
        hit_type   = 2'b00;
        hit_target = 32'b0;
        case (query_idx)
            4'd0: begin
                btb_hit    = btb_valid[0] && (btb_tag[0] == query_tag);
                bht_state  = bht[0];
                hit_type   = btb_type[0];
                hit_target = btb_target[0];
            end
            4'd1: begin
                btb_hit    = btb_valid[1] && (btb_tag[1] == query_tag);
                bht_state  = bht[1];
                hit_type   = btb_type[1];
                hit_target = btb_target[1];
            end
            4'd2: begin
                btb_hit    = btb_valid[2] && (btb_tag[2] == query_tag);
                bht_state  = bht[2];
                hit_type   = btb_type[2];
                hit_target = btb_target[2];
            end
            4'd3: begin
                btb_hit    = btb_valid[3] && (btb_tag[3] == query_tag);
                bht_state  = bht[3];
                hit_type   = btb_type[3];
                hit_target = btb_target[3];
            end
            4'd4: begin
                btb_hit    = btb_valid[4] && (btb_tag[4] == query_tag);
                bht_state  = bht[4];
                hit_type   = btb_type[4];
                hit_target = btb_target[4];
            end
            4'd5: begin
                btb_hit    = btb_valid[5] && (btb_tag[5] == query_tag);
                bht_state  = bht[5];
                hit_type   = btb_type[5];
                hit_target = btb_target[5];
            end
            4'd6: begin
                btb_hit    = btb_valid[6] && (btb_tag[6] == query_tag);
                bht_state  = bht[6];
                hit_type   = btb_type[6];
                hit_target = btb_target[6];
            end
            4'd7: begin
                btb_hit    = btb_valid[7] && (btb_tag[7] == query_tag);
                bht_state  = bht[7];
                hit_type   = btb_type[7];
                hit_target = btb_target[7];
            end
            4'd8: begin
                btb_hit    = btb_valid[8] && (btb_tag[8] == query_tag);
                bht_state  = bht[8];
                hit_type   = btb_type[8];
                hit_target = btb_target[8];
            end
            4'd9: begin
                btb_hit    = btb_valid[9] && (btb_tag[9] == query_tag);
                bht_state  = bht[9];
                hit_type   = btb_type[9];
                hit_target = btb_target[9];
            end
            4'd10: begin
                btb_hit    = btb_valid[10] && (btb_tag[10] == query_tag);
                bht_state  = bht[10];
                hit_type   = btb_type[10];
                hit_target = btb_target[10];
            end
            4'd11: begin
                btb_hit    = btb_valid[11] && (btb_tag[11] == query_tag);
                bht_state  = bht[11];
                hit_type   = btb_type[11];
                hit_target = btb_target[11];
            end
            4'd12: begin
                btb_hit    = btb_valid[12] && (btb_tag[12] == query_tag);
                bht_state  = bht[12];
                hit_type   = btb_type[12];
                hit_target = btb_target[12];
            end
            4'd13: begin
                btb_hit    = btb_valid[13] && (btb_tag[13] == query_tag);
                bht_state  = bht[13];
                hit_type   = btb_type[13];
                hit_target = btb_target[13];
            end
            4'd14: begin
                btb_hit    = btb_valid[14] && (btb_tag[14] == query_tag);
                bht_state  = bht[14];
                hit_type   = btb_type[14];
                hit_target = btb_target[14];
            end
            4'd15: begin
                btb_hit    = btb_valid[15] && (btb_tag[15] == query_tag);
                bht_state  = bht[15];
                hit_type   = btb_type[15];
                hit_target = btb_target[15];
            end
            default: begin
                btb_hit    = 1'b0;
                bht_state  = 2'b00;
                hit_type   = 2'b00;
                hit_target = 32'b0;
            end
        endcase
    end

    always_comb begin
        pred_pc_valid = 1'b0;
        pred_pc = pc_query + 32'h4;
        if (btb_hit) begin
            case (hit_type)
                2'b01: begin // conditional branch
                    if (bht_state[1]) begin
                        pred_pc_valid = 1'b1;
                        pred_pc = hit_target;
                    end
                end
                2'b10, 2'b11: begin // JAL or JALR
                    pred_pc_valid = 1'b1;
                    pred_pc = hit_target;
                end
                default: begin
                    pred_pc_valid = 1'b0;
                    pred_pc = pc_query + 32'h4;
                end
            endcase
        end
    end

    // Update logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            btb_valid <= 16'h0000;
            btb_tag <= 416'h0;
            btb_target <= 512'h0;
            btb_type <= 32'h0;
            bht <= 32'h55555555;
        end else if (update_valid) begin
            // BHT update for conditional branches
            if (update_is_branch) begin
                case (update_idx)
                    4'd0: begin
                        case (bht[0])
                            2'b00: bht[0] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[0] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[0] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[0] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[0] <= 2'b01;
                        endcase
                    end
                    4'd1: begin
                        case (bht[1])
                            2'b00: bht[1] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[1] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[1] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[1] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[1] <= 2'b01;
                        endcase
                    end
                    4'd2: begin
                        case (bht[2])
                            2'b00: bht[2] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[2] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[2] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[2] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[2] <= 2'b01;
                        endcase
                    end
                    4'd3: begin
                        case (bht[3])
                            2'b00: bht[3] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[3] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[3] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[3] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[3] <= 2'b01;
                        endcase
                    end
                    4'd4: begin
                        case (bht[4])
                            2'b00: bht[4] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[4] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[4] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[4] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[4] <= 2'b01;
                        endcase
                    end
                    4'd5: begin
                        case (bht[5])
                            2'b00: bht[5] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[5] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[5] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[5] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[5] <= 2'b01;
                        endcase
                    end
                    4'd6: begin
                        case (bht[6])
                            2'b00: bht[6] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[6] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[6] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[6] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[6] <= 2'b01;
                        endcase
                    end
                    4'd7: begin
                        case (bht[7])
                            2'b00: bht[7] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[7] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[7] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[7] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[7] <= 2'b01;
                        endcase
                    end
                    4'd8: begin
                        case (bht[8])
                            2'b00: bht[8] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[8] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[8] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[8] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[8] <= 2'b01;
                        endcase
                    end
                    4'd9: begin
                        case (bht[9])
                            2'b00: bht[9] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[9] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[9] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[9] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[9] <= 2'b01;
                        endcase
                    end
                    4'd10: begin
                        case (bht[10])
                            2'b00: bht[10] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[10] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[10] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[10] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[10] <= 2'b01;
                        endcase
                    end
                    4'd11: begin
                        case (bht[11])
                            2'b00: bht[11] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[11] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[11] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[11] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[11] <= 2'b01;
                        endcase
                    end
                    4'd12: begin
                        case (bht[12])
                            2'b00: bht[12] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[12] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[12] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[12] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[12] <= 2'b01;
                        endcase
                    end
                    4'd13: begin
                        case (bht[13])
                            2'b00: bht[13] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[13] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[13] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[13] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[13] <= 2'b01;
                        endcase
                    end
                    4'd14: begin
                        case (bht[14])
                            2'b00: bht[14] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[14] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[14] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[14] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[14] <= 2'b01;
                        endcase
                    end
                    4'd15: begin
                        case (bht[15])
                            2'b00: bht[15] <= update_taken ? 2'b01 : 2'b00;
                            2'b01: bht[15] <= update_taken ? 2'b10 : 2'b00;
                            2'b10: bht[15] <= update_taken ? 2'b11 : 2'b01;
                            2'b11: bht[15] <= update_taken ? 2'b11 : 2'b10;
                            default: bht[15] <= 2'b01;
                        endcase
                    end
                    default: begin
                        // No-op
                    end
                endcase
            end

            // BTB update
            if (update_is_branch) begin
                if (update_taken) begin
                    case (update_idx)
                        4'd0: begin
                            if (!btb_valid[0] || (btb_tag[0] != update_tag) ||
                                (btb_type[0] != 2'b01) || (btb_target[0] != update_target)) begin
                                btb_valid[0] <= 1'b1;
                                btb_tag[0] <= update_tag;
                                btb_target[0] <= update_target;
                                btb_type[0] <= 2'b01;
                            end
                        end
                        4'd1: begin
                            if (!btb_valid[1] || (btb_tag[1] != update_tag) ||
                                (btb_type[1] != 2'b01) || (btb_target[1] != update_target)) begin
                                btb_valid[1] <= 1'b1;
                                btb_tag[1] <= update_tag;
                                btb_target[1] <= update_target;
                                btb_type[1] <= 2'b01;
                            end
                        end
                        4'd2: begin
                            if (!btb_valid[2] || (btb_tag[2] != update_tag) ||
                                (btb_type[2] != 2'b01) || (btb_target[2] != update_target)) begin
                                btb_valid[2] <= 1'b1;
                                btb_tag[2] <= update_tag;
                                btb_target[2] <= update_target;
                                btb_type[2] <= 2'b01;
                            end
                        end
                        4'd3: begin
                            if (!btb_valid[3] || (btb_tag[3] != update_tag) ||
                                (btb_type[3] != 2'b01) || (btb_target[3] != update_target)) begin
                                btb_valid[3] <= 1'b1;
                                btb_tag[3] <= update_tag;
                                btb_target[3] <= update_target;
                                btb_type[3] <= 2'b01;
                            end
                        end
                        4'd4: begin
                            if (!btb_valid[4] || (btb_tag[4] != update_tag) ||
                                (btb_type[4] != 2'b01) || (btb_target[4] != update_target)) begin
                                btb_valid[4] <= 1'b1;
                                btb_tag[4] <= update_tag;
                                btb_target[4] <= update_target;
                                btb_type[4] <= 2'b01;
                            end
                        end
                        4'd5: begin
                            if (!btb_valid[5] || (btb_tag[5] != update_tag) ||
                                (btb_type[5] != 2'b01) || (btb_target[5] != update_target)) begin
                                btb_valid[5] <= 1'b1;
                                btb_tag[5] <= update_tag;
                                btb_target[5] <= update_target;
                                btb_type[5] <= 2'b01;
                            end
                        end
                        4'd6: begin
                            if (!btb_valid[6] || (btb_tag[6] != update_tag) ||
                                (btb_type[6] != 2'b01) || (btb_target[6] != update_target)) begin
                                btb_valid[6] <= 1'b1;
                                btb_tag[6] <= update_tag;
                                btb_target[6] <= update_target;
                                btb_type[6] <= 2'b01;
                            end
                        end
                        4'd7: begin
                            if (!btb_valid[7] || (btb_tag[7] != update_tag) ||
                                (btb_type[7] != 2'b01) || (btb_target[7] != update_target)) begin
                                btb_valid[7] <= 1'b1;
                                btb_tag[7] <= update_tag;
                                btb_target[7] <= update_target;
                                btb_type[7] <= 2'b01;
                            end
                        end
                        4'd8: begin
                            if (!btb_valid[8] || (btb_tag[8] != update_tag) ||
                                (btb_type[8] != 2'b01) || (btb_target[8] != update_target)) begin
                                btb_valid[8] <= 1'b1;
                                btb_tag[8] <= update_tag;
                                btb_target[8] <= update_target;
                                btb_type[8] <= 2'b01;
                            end
                        end
                        4'd9: begin
                            if (!btb_valid[9] || (btb_tag[9] != update_tag) ||
                                (btb_type[9] != 2'b01) || (btb_target[9] != update_target)) begin
                                btb_valid[9] <= 1'b1;
                                btb_tag[9] <= update_tag;
                                btb_target[9] <= update_target;
                                btb_type[9] <= 2'b01;
                            end
                        end
                        4'd10: begin
                            if (!btb_valid[10] || (btb_tag[10] != update_tag) ||
                                (btb_type[10] != 2'b01) || (btb_target[10] != update_target)) begin
                                btb_valid[10] <= 1'b1;
                                btb_tag[10] <= update_tag;
                                btb_target[10] <= update_target;
                                btb_type[10] <= 2'b01;
                            end
                        end
                        4'd11: begin
                            if (!btb_valid[11] || (btb_tag[11] != update_tag) ||
                                (btb_type[11] != 2'b01) || (btb_target[11] != update_target)) begin
                                btb_valid[11] <= 1'b1;
                                btb_tag[11] <= update_tag;
                                btb_target[11] <= update_target;
                                btb_type[11] <= 2'b01;
                            end
                        end
                        4'd12: begin
                            if (!btb_valid[12] || (btb_tag[12] != update_tag) ||
                                (btb_type[12] != 2'b01) || (btb_target[12] != update_target)) begin
                                btb_valid[12] <= 1'b1;
                                btb_tag[12] <= update_tag;
                                btb_target[12] <= update_target;
                                btb_type[12] <= 2'b01;
                            end
                        end
                        4'd13: begin
                            if (!btb_valid[13] || (btb_tag[13] != update_tag) ||
                                (btb_type[13] != 2'b01) || (btb_target[13] != update_target)) begin
                                btb_valid[13] <= 1'b1;
                                btb_tag[13] <= update_tag;
                                btb_target[13] <= update_target;
                                btb_type[13] <= 2'b01;
                            end
                        end
                        4'd14: begin
                            if (!btb_valid[14] || (btb_tag[14] != update_tag) ||
                                (btb_type[14] != 2'b01) || (btb_target[14] != update_target)) begin
                                btb_valid[14] <= 1'b1;
                                btb_tag[14] <= update_tag;
                                btb_target[14] <= update_target;
                                btb_type[14] <= 2'b01;
                            end
                        end
                        4'd15: begin
                            if (!btb_valid[15] || (btb_tag[15] != update_tag) ||
                                (btb_type[15] != 2'b01) || (btb_target[15] != update_target)) begin
                                btb_valid[15] <= 1'b1;
                                btb_tag[15] <= update_tag;
                                btb_target[15] <= update_target;
                                btb_type[15] <= 2'b01;
                            end
                        end
                        default: begin
                            // No-op
                        end
                    endcase
                end else begin
                    // Not taken: keep BTB entry if exists, but ensure type is branch
                    case (update_idx)
                        4'd0: begin
                            if (btb_valid[0] && (btb_tag[0] == update_tag) &&
                                (btb_type[0] != 2'b01)) begin
                                btb_type[0] <= 2'b01;
                            end
                        end
                        4'd1: begin
                            if (btb_valid[1] && (btb_tag[1] == update_tag) &&
                                (btb_type[1] != 2'b01)) begin
                                btb_type[1] <= 2'b01;
                            end
                        end
                        4'd2: begin
                            if (btb_valid[2] && (btb_tag[2] == update_tag) &&
                                (btb_type[2] != 2'b01)) begin
                                btb_type[2] <= 2'b01;
                            end
                        end
                        4'd3: begin
                            if (btb_valid[3] && (btb_tag[3] == update_tag) &&
                                (btb_type[3] != 2'b01)) begin
                                btb_type[3] <= 2'b01;
                            end
                        end
                        4'd4: begin
                            if (btb_valid[4] && (btb_tag[4] == update_tag) &&
                                (btb_type[4] != 2'b01)) begin
                                btb_type[4] <= 2'b01;
                            end
                        end
                        4'd5: begin
                            if (btb_valid[5] && (btb_tag[5] == update_tag) &&
                                (btb_type[5] != 2'b01)) begin
                                btb_type[5] <= 2'b01;
                            end
                        end
                        4'd6: begin
                            if (btb_valid[6] && (btb_tag[6] == update_tag) &&
                                (btb_type[6] != 2'b01)) begin
                                btb_type[6] <= 2'b01;
                            end
                        end
                        4'd7: begin
                            if (btb_valid[7] && (btb_tag[7] == update_tag) &&
                                (btb_type[7] != 2'b01)) begin
                                btb_type[7] <= 2'b01;
                            end
                        end
                        4'd8: begin
                            if (btb_valid[8] && (btb_tag[8] == update_tag) &&
                                (btb_type[8] != 2'b01)) begin
                                btb_type[8] <= 2'b01;
                            end
                        end
                        4'd9: begin
                            if (btb_valid[9] && (btb_tag[9] == update_tag) &&
                                (btb_type[9] != 2'b01)) begin
                                btb_type[9] <= 2'b01;
                            end
                        end
                        4'd10: begin
                            if (btb_valid[10] && (btb_tag[10] == update_tag) &&
                                (btb_type[10] != 2'b01)) begin
                                btb_type[10] <= 2'b01;
                            end
                        end
                        4'd11: begin
                            if (btb_valid[11] && (btb_tag[11] == update_tag) &&
                                (btb_type[11] != 2'b01)) begin
                                btb_type[11] <= 2'b01;
                            end
                        end
                        4'd12: begin
                            if (btb_valid[12] && (btb_tag[12] == update_tag) &&
                                (btb_type[12] != 2'b01)) begin
                                btb_type[12] <= 2'b01;
                            end
                        end
                        4'd13: begin
                            if (btb_valid[13] && (btb_tag[13] == update_tag) &&
                                (btb_type[13] != 2'b01)) begin
                                btb_type[13] <= 2'b01;
                            end
                        end
                        4'd14: begin
                            if (btb_valid[14] && (btb_tag[14] == update_tag) &&
                                (btb_type[14] != 2'b01)) begin
                                btb_type[14] <= 2'b01;
                            end
                        end
                        4'd15: begin
                            if (btb_valid[15] && (btb_tag[15] == update_tag) &&
                                (btb_type[15] != 2'b01)) begin
                                btb_type[15] <= 2'b01;
                            end
                        end
                        default: begin
                            // No-op
                        end
                    endcase
                end
            end else if (update_is_jal) begin
                case (update_idx)
                    4'd0: begin
                        if (!btb_valid[0] || (btb_tag[0] != update_tag) ||
                            (btb_type[0] != 2'b10) || (btb_target[0] != update_target)) begin
                            btb_valid[0] <= 1'b1;
                            btb_tag[0] <= update_tag;
                            btb_target[0] <= update_target;
                            btb_type[0] <= 2'b10;
                        end
                    end
                    4'd1: begin
                        if (!btb_valid[1] || (btb_tag[1] != update_tag) ||
                            (btb_type[1] != 2'b10) || (btb_target[1] != update_target)) begin
                            btb_valid[1] <= 1'b1;
                            btb_tag[1] <= update_tag;
                            btb_target[1] <= update_target;
                            btb_type[1] <= 2'b10;
                        end
                    end
                    4'd2: begin
                        if (!btb_valid[2] || (btb_tag[2] != update_tag) ||
                            (btb_type[2] != 2'b10) || (btb_target[2] != update_target)) begin
                            btb_valid[2] <= 1'b1;
                            btb_tag[2] <= update_tag;
                            btb_target[2] <= update_target;
                            btb_type[2] <= 2'b10;
                        end
                    end
                    4'd3: begin
                        if (!btb_valid[3] || (btb_tag[3] != update_tag) ||
                            (btb_type[3] != 2'b10) || (btb_target[3] != update_target)) begin
                            btb_valid[3] <= 1'b1;
                            btb_tag[3] <= update_tag;
                            btb_target[3] <= update_target;
                            btb_type[3] <= 2'b10;
                        end
                    end
                    4'd4: begin
                        if (!btb_valid[4] || (btb_tag[4] != update_tag) ||
                            (btb_type[4] != 2'b10) || (btb_target[4] != update_target)) begin
                            btb_valid[4] <= 1'b1;
                            btb_tag[4] <= update_tag;
                            btb_target[4] <= update_target;
                            btb_type[4] <= 2'b10;
                        end
                    end
                    4'd5: begin
                        if (!btb_valid[5] || (btb_tag[5] != update_tag) ||
                            (btb_type[5] != 2'b10) || (btb_target[5] != update_target)) begin
                            btb_valid[5] <= 1'b1;
                            btb_tag[5] <= update_tag;
                            btb_target[5] <= update_target;
                            btb_type[5] <= 2'b10;
                        end
                    end
                    4'd6: begin
                        if (!btb_valid[6] || (btb_tag[6] != update_tag) ||
                            (btb_type[6] != 2'b10) || (btb_target[6] != update_target)) begin
                            btb_valid[6] <= 1'b1;
                            btb_tag[6] <= update_tag;
                            btb_target[6] <= update_target;
                            btb_type[6] <= 2'b10;
                        end
                    end
                    4'd7: begin
                        if (!btb_valid[7] || (btb_tag[7] != update_tag) ||
                            (btb_type[7] != 2'b10) || (btb_target[7] != update_target)) begin
                            btb_valid[7] <= 1'b1;
                            btb_tag[7] <= update_tag;
                            btb_target[7] <= update_target;
                            btb_type[7] <= 2'b10;
                        end
                    end
                    4'd8: begin
                        if (!btb_valid[8] || (btb_tag[8] != update_tag) ||
                            (btb_type[8] != 2'b10) || (btb_target[8] != update_target)) begin
                            btb_valid[8] <= 1'b1;
                            btb_tag[8] <= update_tag;
                            btb_target[8] <= update_target;
                            btb_type[8] <= 2'b10;
                        end
                    end
                    4'd9: begin
                        if (!btb_valid[9] || (btb_tag[9] != update_tag) ||
                            (btb_type[9] != 2'b10) || (btb_target[9] != update_target)) begin
                            btb_valid[9] <= 1'b1;
                            btb_tag[9] <= update_tag;
                            btb_target[9] <= update_target;
                            btb_type[9] <= 2'b10;
                        end
                    end
                    4'd10: begin
                        if (!btb_valid[10] || (btb_tag[10] != update_tag) ||
                            (btb_type[10] != 2'b10) || (btb_target[10] != update_target)) begin
                            btb_valid[10] <= 1'b1;
                            btb_tag[10] <= update_tag;
                            btb_target[10] <= update_target;
                            btb_type[10] <= 2'b10;
                        end
                    end
                    4'd11: begin
                        if (!btb_valid[11] || (btb_tag[11] != update_tag) ||
                            (btb_type[11] != 2'b10) || (btb_target[11] != update_target)) begin
                            btb_valid[11] <= 1'b1;
                            btb_tag[11] <= update_tag;
                            btb_target[11] <= update_target;
                            btb_type[11] <= 2'b10;
                        end
                    end
                    4'd12: begin
                        if (!btb_valid[12] || (btb_tag[12] != update_tag) ||
                            (btb_type[12] != 2'b10) || (btb_target[12] != update_target)) begin
                            btb_valid[12] <= 1'b1;
                            btb_tag[12] <= update_tag;
                            btb_target[12] <= update_target;
                            btb_type[12] <= 2'b10;
                        end
                    end
                    4'd13: begin
                        if (!btb_valid[13] || (btb_tag[13] != update_tag) ||
                            (btb_type[13] != 2'b10) || (btb_target[13] != update_target)) begin
                            btb_valid[13] <= 1'b1;
                            btb_tag[13] <= update_tag;
                            btb_target[13] <= update_target;
                            btb_type[13] <= 2'b10;
                        end
                    end
                    4'd14: begin
                        if (!btb_valid[14] || (btb_tag[14] != update_tag) ||
                            (btb_type[14] != 2'b10) || (btb_target[14] != update_target)) begin
                            btb_valid[14] <= 1'b1;
                            btb_tag[14] <= update_tag;
                            btb_target[14] <= update_target;
                            btb_type[14] <= 2'b10;
                        end
                    end
                    4'd15: begin
                        if (!btb_valid[15] || (btb_tag[15] != update_tag) ||
                            (btb_type[15] != 2'b10) || (btb_target[15] != update_target)) begin
                            btb_valid[15] <= 1'b1;
                            btb_tag[15] <= update_tag;
                            btb_target[15] <= update_target;
                            btb_type[15] <= 2'b10;
                        end
                    end
                    default: begin
                        // No-op
                    end
                endcase
            end else if (update_is_jalr) begin
                case (update_idx)
                    4'd0: begin
                        if (!btb_valid[0] || (btb_tag[0] != update_tag) ||
                            (btb_type[0] != 2'b11) || (btb_target[0] != update_target)) begin
                            btb_valid[0] <= 1'b1;
                            btb_tag[0] <= update_tag;
                            btb_target[0] <= update_target;
                            btb_type[0] <= 2'b11;
                        end
                    end
                    4'd1: begin
                        if (!btb_valid[1] || (btb_tag[1] != update_tag) ||
                            (btb_type[1] != 2'b11) || (btb_target[1] != update_target)) begin
                            btb_valid[1] <= 1'b1;
                            btb_tag[1] <= update_tag;
                            btb_target[1] <= update_target;
                            btb_type[1] <= 2'b11;
                        end
                    end
                    4'd2: begin
                        if (!btb_valid[2] || (btb_tag[2] != update_tag) ||
                            (btb_type[2] != 2'b11) || (btb_target[2] != update_target)) begin
                            btb_valid[2] <= 1'b1;
                            btb_tag[2] <= update_tag;
                            btb_target[2] <= update_target;
                            btb_type[2] <= 2'b11;
                        end
                    end
                    4'd3: begin
                        if (!btb_valid[3] || (btb_tag[3] != update_tag) ||
                            (btb_type[3] != 2'b11) || (btb_target[3] != update_target)) begin
                            btb_valid[3] <= 1'b1;
                            btb_tag[3] <= update_tag;
                            btb_target[3] <= update_target;
                            btb_type[3] <= 2'b11;
                        end
                    end
                    4'd4: begin
                        if (!btb_valid[4] || (btb_tag[4] != update_tag) ||
                            (btb_type[4] != 2'b11) || (btb_target[4] != update_target)) begin
                            btb_valid[4] <= 1'b1;
                            btb_tag[4] <= update_tag;
                            btb_target[4] <= update_target;
                            btb_type[4] <= 2'b11;
                        end
                    end
                    4'd5: begin
                        if (!btb_valid[5] || (btb_tag[5] != update_tag) ||
                            (btb_type[5] != 2'b11) || (btb_target[5] != update_target)) begin
                            btb_valid[5] <= 1'b1;
                            btb_tag[5] <= update_tag;
                            btb_target[5] <= update_target;
                            btb_type[5] <= 2'b11;
                        end
                    end
                    4'd6: begin
                        if (!btb_valid[6] || (btb_tag[6] != update_tag) ||
                            (btb_type[6] != 2'b11) || (btb_target[6] != update_target)) begin
                            btb_valid[6] <= 1'b1;
                            btb_tag[6] <= update_tag;
                            btb_target[6] <= update_target;
                            btb_type[6] <= 2'b11;
                        end
                    end
                    4'd7: begin
                        if (!btb_valid[7] || (btb_tag[7] != update_tag) ||
                            (btb_type[7] != 2'b11) || (btb_target[7] != update_target)) begin
                            btb_valid[7] <= 1'b1;
                            btb_tag[7] <= update_tag;
                            btb_target[7] <= update_target;
                            btb_type[7] <= 2'b11;
                        end
                    end
                    4'd8: begin
                        if (!btb_valid[8] || (btb_tag[8] != update_tag) ||
                            (btb_type[8] != 2'b11) || (btb_target[8] != update_target)) begin
                            btb_valid[8] <= 1'b1;
                            btb_tag[8] <= update_tag;
                            btb_target[8] <= update_target;
                            btb_type[8] <= 2'b11;
                        end
                    end
                    4'd9: begin
                        if (!btb_valid[9] || (btb_tag[9] != update_tag) ||
                            (btb_type[9] != 2'b11) || (btb_target[9] != update_target)) begin
                            btb_valid[9] <= 1'b1;
                            btb_tag[9] <= update_tag;
                            btb_target[9] <= update_target;
                            btb_type[9] <= 2'b11;
                        end
                    end
                    4'd10: begin
                        if (!btb_valid[10] || (btb_tag[10] != update_tag) ||
                            (btb_type[10] != 2'b11) || (btb_target[10] != update_target)) begin
                            btb_valid[10] <= 1'b1;
                            btb_tag[10] <= update_tag;
                            btb_target[10] <= update_target;
                            btb_type[10] <= 2'b11;
                        end
                    end
                    4'd11: begin
                        if (!btb_valid[11] || (btb_tag[11] != update_tag) ||
                            (btb_type[11] != 2'b11) || (btb_target[11] != update_target)) begin
                            btb_valid[11] <= 1'b1;
                            btb_tag[11] <= update_tag;
                            btb_target[11] <= update_target;
                            btb_type[11] <= 2'b11;
                        end
                    end
                    4'd12: begin
                        if (!btb_valid[12] || (btb_tag[12] != update_tag) ||
                            (btb_type[12] != 2'b11) || (btb_target[12] != update_target)) begin
                            btb_valid[12] <= 1'b1;
                            btb_tag[12] <= update_tag;
                            btb_target[12] <= update_target;
                            btb_type[12] <= 2'b11;
                        end
                    end
                    4'd13: begin
                        if (!btb_valid[13] || (btb_tag[13] != update_tag) ||
                            (btb_type[13] != 2'b11) || (btb_target[13] != update_target)) begin
                            btb_valid[13] <= 1'b1;
                            btb_tag[13] <= update_tag;
                            btb_target[13] <= update_target;
                            btb_type[13] <= 2'b11;
                        end
                    end
                    4'd14: begin
                        if (!btb_valid[14] || (btb_tag[14] != update_tag) ||
                            (btb_type[14] != 2'b11) || (btb_target[14] != update_target)) begin
                            btb_valid[14] <= 1'b1;
                            btb_tag[14] <= update_tag;
                            btb_target[14] <= update_target;
                            btb_type[14] <= 2'b11;
                        end
                    end
                    4'd15: begin
                        if (!btb_valid[15] || (btb_tag[15] != update_tag) ||
                            (btb_type[15] != 2'b11) || (btb_target[15] != update_target)) begin
                            btb_valid[15] <= 1'b1;
                            btb_tag[15] <= update_tag;
                            btb_target[15] <= update_target;
                            btb_type[15] <= 2'b11;
                        end
                    end
                    default: begin
                        // No-op
                    end
                endcase
            end
        end
    end

endmodule
