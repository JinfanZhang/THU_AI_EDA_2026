module branch_predictor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] lookup_pc,
    output logic        pred_valid,
    output logic [31:0] pred_next_pc,
    output logic        pred_is_branch,
    output logic        pred_is_jal,
    output logic        pred_is_jalr,
    input  logic        update_valid,
    input  logic [31:0] update_pc,
    input  logic [31:0] update_actual_next_pc,
    input  logic        update_is_branch,
    input  logic        update_is_jal,
    input  logic        update_is_jalr,
    input  logic        update_taken
);

    // ---------------------------------------------------------------
    // Storage: packed vectors (Icarus-friendly, no array indexing in
    // always_* with constant selects).
    //   BTB: 16 entries, direct-mapped, index PC[5:2], tag PC[31:6]
    //   BHT: 16 x 2-bit saturating counters, reset 2'b01
    // ---------------------------------------------------------------
    logic [15:0] btb_valid;
    logic [415:0] btb_tag;    // 16 * 26
    logic [511:0] btb_target; // 16 * 32
    logic [31:0] btb_type;    // 16 * 2
    logic [31:0] bht;         // 16 * 2

    logic [3:0]  lookup_idx;
    logic [25:0] lookup_tag;
    logic [3:0]  update_idx;
    logic [25:0] update_tag;

    // Selected (OLD) entry fields
    logic        btb_hit;
    logic [1:0]  btb_type_sel;
    logic [31:0] btb_target_sel;
    logic [1:0]  bht_sel;
    logic        bht_taken;

    // Update decision
    logic        upd_btb_write;
    logic [1:0]  upd_btb_type;
    logic [31:0] upd_btb_target;
    logic        upd_bht_write;
    logic [1:0]  upd_bht_val;

    // Per-entry write enables
    logic [15:0] btb_we;
    logic [15:0] bht_we;

    integer i;

    assign lookup_idx = lookup_pc[5:2];
    assign lookup_tag = lookup_pc[31:6];
    assign update_idx = update_pc[5:2];
    assign update_tag = update_pc[31:6];

    // ---------------------------------------------------------------
    // Same-cycle lookup: read OLD entry (before this cycle's write)
    // ---------------------------------------------------------------
    always_comb begin
        btb_hit        = 1'b0;
        btb_type_sel   = 2'b00;
        btb_target_sel = 32'd0;
        bht_sel        = 2'b01;
        case (lookup_idx)
            4'd0:  begin btb_hit = btb_valid[0];  btb_type_sel = btb_type[1:0];   btb_target_sel = btb_target[31:0];   bht_sel = bht[1:0];   end
            4'd1:  begin btb_hit = btb_valid[1];  btb_type_sel = btb_type[3:2];   btb_target_sel = btb_target[63:32];  bht_sel = bht[3:2];   end
            4'd2:  begin btb_hit = btb_valid[2];  btb_type_sel = btb_type[5:4];   btb_target_sel = btb_target[95:64];  bht_sel = bht[5:4];   end
            4'd3:  begin btb_hit = btb_valid[3];  btb_type_sel = btb_type[7:6];   btb_target_sel = btb_target[127:96]; bht_sel = bht[7:6];   end
            4'd4:  begin btb_hit = btb_valid[4];  btb_type_sel = btb_type[9:8];   btb_target_sel = btb_target[159:128];bht_sel = bht[9:8];   end
            4'd5:  begin btb_hit = btb_valid[5];  btb_type_sel = btb_type[11:10]; btb_target_sel = btb_target[191:160];bht_sel = bht[11:10]; end
            4'd6:  begin btb_hit = btb_valid[6];  btb_type_sel = btb_type[13:12]; btb_target_sel = btb_target[223:192];bht_sel = bht[13:12]; end
            4'd7:  begin btb_hit = btb_valid[7];  btb_type_sel = btb_type[15:14]; btb_target_sel = btb_target[255:224];bht_sel = bht[15:14]; end
            4'd8:  begin btb_hit = btb_valid[8];  btb_type_sel = btb_type[17:16]; btb_target_sel = btb_target[287:256];bht_sel = bht[17:16]; end
            4'd9:  begin btb_hit = btb_valid[9];  btb_type_sel = btb_type[19:18]; btb_target_sel = btb_target[319:288];bht_sel = bht[19:18]; end
            4'd10: begin btb_hit = btb_valid[10]; btb_type_sel = btb_type[21:20]; btb_target_sel = btb_target[351:320];bht_sel = bht[21:20]; end
            4'd11: begin btb_hit = btb_valid[11]; btb_type_sel = btb_type[23:22]; btb_target_sel = btb_target[383:352];bht_sel = bht[23:22]; end
            4'd12: begin btb_hit = btb_valid[12]; btb_type_sel = btb_type[25:24]; btb_target_sel = btb_target[415:384];bht_sel = bht[25:24]; end
            4'd13: begin btb_hit = btb_valid[13]; btb_type_sel = btb_type[27:26]; btb_target_sel = btb_target[447:416];bht_sel = bht[27:26]; end
            4'd14: begin btb_hit = btb_valid[14]; btb_type_sel = btb_type[29:28]; btb_target_sel = btb_target[479:448];bht_sel = bht[29:28]; end
            default: begin btb_hit = btb_valid[15]; btb_type_sel = btb_type[31:30]; btb_target_sel = btb_target[511:480];bht_sel = bht[31:30]; end
        endcase
        // Tag compare against selected entry
        case (lookup_idx)
            4'd0:  btb_hit = btb_hit && (btb_tag[25:0]    == lookup_tag);
            4'd1:  btb_hit = btb_hit && (btb_tag[51:26]   == lookup_tag);
            4'd2:  btb_hit = btb_hit && (btb_tag[77:52]   == lookup_tag);
            4'd3:  btb_hit = btb_hit && (btb_tag[103:78]  == lookup_tag);
            4'd4:  btb_hit = btb_hit && (btb_tag[129:104] == lookup_tag);
            4'd5:  btb_hit = btb_hit && (btb_tag[155:130] == lookup_tag);
            4'd6:  btb_hit = btb_hit && (btb_tag[181:156] == lookup_tag);
            4'd7:  btb_hit = btb_hit && (btb_tag[207:182] == lookup_tag);
            4'd8:  btb_hit = btb_hit && (btb_tag[233:208] == lookup_tag);
            4'd9:  btb_hit = btb_hit && (btb_tag[259:234] == lookup_tag);
            4'd10: btb_hit = btb_hit && (btb_tag[285:260] == lookup_tag);
            4'd11: btb_hit = btb_hit && (btb_tag[311:286] == lookup_tag);
            4'd12: btb_hit = btb_hit && (btb_tag[337:312] == lookup_tag);
            4'd13: btb_hit = btb_hit && (btb_tag[363:338] == lookup_tag);
            4'd14: btb_hit = btb_hit && (btb_tag[389:364] == lookup_tag);
            default: btb_hit = btb_hit && (btb_tag[415:390] == lookup_tag);
        endcase
    end

    assign bht_taken = bht_sel[1];

    always_comb begin
        pred_valid     = 1'b0;
        pred_next_pc   = lookup_pc + 32'd4;
        pred_is_branch = 1'b0;
        pred_is_jal    = 1'b0;
        pred_is_jalr   = 1'b0;
        if (btb_hit) begin
            if (btb_type_sel == 2'b00) begin
                pred_is_branch = 1'b1;
                if (bht_taken) begin
                    pred_valid   = 1'b1;
                    pred_next_pc = btb_target_sel;
                end
            end else if (btb_type_sel == 2'b01) begin
                pred_is_jal  = 1'b1;
                pred_valid   = 1'b1;
                pred_next_pc = btb_target_sel;
            end else if (btb_type_sel == 2'b10) begin
                pred_is_jalr = 1'b1;
                pred_valid   = 1'b1;
                pred_next_pc = btb_target_sel;
            end
        end
    end

    // ---------------------------------------------------------------
    // Update decision (uses OLD entry state)
    // ---------------------------------------------------------------
    always_comb begin
        upd_btb_write  = 1'b0;
        upd_btb_type   = 2'b00;
        upd_btb_target = update_actual_next_pc;
        upd_bht_write  = 1'b0;
        upd_bht_val    = bht_sel;

        if (update_valid) begin
            if (update_is_branch) begin
                upd_btb_type = 2'b00;
                if (!btb_hit) begin
                    // BTB miss: allocate only if actually taken
                    if (update_taken) begin
                        upd_btb_write = 1'b1;
                    end
                end else begin
                    // Hit: fix type/target if needed
                    if (btb_type_sel != 2'b00) begin
                        upd_btb_write = 1'b1;
                    end else if (update_taken && (btb_target_sel != update_actual_next_pc)) begin
                        upd_btb_write = 1'b1;
                    end
                end
                // BHT always updates for a resolved conditional
                upd_bht_write = 1'b1;
                if (update_taken) begin
                    if (bht_sel != 2'b11) upd_bht_val = bht_sel + 2'b01;
                    else                  upd_bht_val = 2'b11;
                end else begin
                    if (bht_sel != 2'b00) upd_bht_val = bht_sel - 2'b01;
                    else                  upd_bht_val = 2'b00;
                end
            end else if (update_is_jal) begin
                upd_btb_type = 2'b01;
                if (!btb_hit || (btb_type_sel != 2'b01) ||
                    (btb_target_sel != update_actual_next_pc)) begin
                    upd_btb_write = 1'b1;
                end
            end else if (update_is_jalr) begin
                upd_btb_type = 2'b10;
                if (!btb_hit || (btb_type_sel != 2'b10) ||
                    (btb_target_sel != update_actual_next_pc)) begin
                    upd_btb_write = 1'b1;
                end
            end
        end
    end

    // Per-entry write enables (one-hot on update_idx)
    always_comb begin
        btb_we = 16'd0;
        bht_we = 16'd0;
        if (upd_btb_write) begin
            case (update_idx)
                4'd0:  btb_we = 16'h0001;
                4'd1:  btb_we = 16'h0002;
                4'd2:  btb_we = 16'h0004;
                4'd3:  btb_we = 16'h0008;
                4'd4:  btb_we = 16'h0010;
                4'd5:  btb_we = 16'h0020;
                4'd6:  btb_we = 16'h0040;
                4'd7:  btb_we = 16'h0080;
                4'd8:  btb_we = 16'h0100;
                4'd9:  btb_we = 16'h0200;
                4'd10: btb_we = 16'h0400;
                4'd11: btb_we = 16'h0800;
                4'd12: btb_we = 16'h1000;
                4'd13: btb_we = 16'h2000;
                4'd14: btb_we = 16'h4000;
                default: btb_we = 16'h8000;
            endcase
        end
        if (upd_bht_write) begin
            case (update_idx)
                4'd0:  bht_we = 16'h0001;
                4'd1:  bht_we = 16'h0002;
                4'd2:  bht_we = 16'h0004;
                4'd3:  bht_we = 16'h0008;
                4'd4:  bht_we = 16'h0010;
                4'd5:  bht_we = 16'h0020;
                4'd6:  bht_we = 16'h0040;
                4'd7:  bht_we = 16'h0080;
                4'd8:  bht_we = 16'h0100;
                4'd9:  bht_we = 16'h0200;
                4'd10: bht_we = 16'h0400;
                4'd11: bht_we = 16'h0800;
                4'd12: bht_we = 16'h1000;
                4'd13: bht_we = 16'h2000;
                4'd14: bht_we = 16'h4000;
                default: bht_we = 16'h8000;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Sequential state update
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            btb_valid  <= 16'd0;
            btb_tag    <= 416'd0;
            btb_target <= 512'd0;
            btb_type   <= 32'd0;
            bht        <= 32'h5555_5555; // every 2-bit counter = 2'b01
        end else begin
            for (i = 0; i < 16; i = i + 1) begin
                if (btb_we[i]) begin
                    btb_valid[i] <= 1'b1;
                end
            end
            if (btb_we[0])  begin btb_tag[25:0]    <= update_tag; btb_target[31:0]   <= upd_btb_target; btb_type[1:0]   <= upd_btb_type; end
            if (btb_we[1])  begin btb_tag[51:26]   <= update_tag; btb_target[63:32]  <= upd_btb_target; btb_type[3:2]   <= upd_btb_type; end
            if (btb_we[2])  begin btb_tag[77:52]   <= update_tag; btb_target[95:64]  <= upd_btb_target; btb_type[5:4]   <= upd_btb_type; end
            if (btb_we[3])  begin btb_tag[103:78]  <= update_tag; btb_target[127:96] <= upd_btb_target; btb_type[7:6]   <= upd_btb_type; end
            if (btb_we[4])  begin btb_tag[129:104] <= update_tag; btb_target[159:128]<= upd_btb_target; btb_type[9:8]   <= upd_btb_type; end
            if (btb_we[5])  begin btb_tag[155:130] <= update_tag; btb_target[191:160]<= upd_btb_target; btb_type[11:10] <= upd_btb_type; end
            if (btb_we[6])  begin btb_tag[181:156] <= update_tag; btb_target[223:192]<= upd_btb_target; btb_type[13:12] <= upd_btb_type; end
            if (btb_we[7])  begin btb_tag[207:182] <= update_tag; btb_target[255:224]<= upd_btb_target; btb_type[15:14] <= upd_btb_type; end
            if (btb_we[8])  begin btb_tag[233:208] <= update_tag; btb_target[287:256]<= upd_btb_target; btb_type[17:16] <= upd_btb_type; end
            if (btb_we[9])  begin btb_tag[259:234] <= update_tag; btb_target[319:288]<= upd_btb_target; btb_type[19:18] <= upd_btb_type; end
            if (btb_we[10]) begin btb_tag[285:260] <= update_tag; btb_target[351:320]<= upd_btb_target; btb_type[21:20] <= upd_btb_type; end
            if (btb_we[11]) begin btb_tag[311:286] <= update_tag; btb_target[383:352]<= upd_btb_target; btb_type[23:22] <= upd_btb_type; end
            if (btb_we[12]) begin btb_tag[337:312] <= update_tag; btb_target[415:384]<= upd_btb_target; btb_type[25:24] <= upd_btb_type; end
            if (btb_we[13]) begin btb_tag[363:338] <= update_tag; btb_target[447:416]<= upd_btb_target; btb_type[27:26] <= upd_btb_type; end
            if (btb_we[14]) begin btb_tag[389:364] <= update_tag; btb_target[479:448]<= upd_btb_target; btb_type[29:28] <= upd_btb_type; end
            if (btb_we[15]) begin btb_tag[415:390] <= update_tag; btb_target[511:480]<= upd_btb_target; btb_type[31:30] <= upd_btb_type; end

            if (bht_we[0])  bht[1:0]   <= upd_bht_val;
            if (bht_we[1])  bht[3:2]   <= upd_bht_val;
            if (bht_we[2])  bht[5:4]   <= upd_bht_val;
            if (bht_we[3])  bht[7:6]   <= upd_bht_val;
            if (bht_we[4])  bht[9:8]   <= upd_bht_val;
            if (bht_we[5])  bht[11:10] <= upd_bht_val;
            if (bht_we[6])  bht[13:12] <= upd_bht_val;
            if (bht_we[7])  bht[15:14] <= upd_bht_val;
            if (bht_we[8])  bht[17:16] <= upd_bht_val;
            if (bht_we[9])  bht[19:18] <= upd_bht_val;
            if (bht_we[10]) bht[21:20] <= upd_bht_val;
            if (bht_we[11]) bht[23:22] <= upd_bht_val;
            if (bht_we[12]) bht[25:24] <= upd_bht_val;
            if (bht_we[13]) bht[27:26] <= upd_bht_val;
            if (bht_we[14]) bht[29:28] <= upd_bht_val;
            if (bht_we[15]) bht[31:30] <= upd_bht_val;
        end
    end

endmodule
