module dcache (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cpu_req_valid,
    input  logic        cpu_req_we,
    input  logic [31:0] cpu_req_addr,
    input  logic [31:0] cpu_req_wdata,
    input  logic [3:0]  cpu_req_be,
    output logic        cpu_req_ready,
    output logic        cpu_resp_valid,
    output logic [31:0] cpu_resp_rdata,
    input  logic        flush,
    input  logic [1:0]  flush_epoch,
    output logic        mem_req_valid,
    output logic        mem_req_we,
    output logic [31:0] mem_req_addr,
    output logic [31:0] mem_req_wdata,
    output logic [3:0]  mem_req_be,
    input  logic        mem_req_ready,
    input  logic        mem_resp_valid,
    input  logic [31:0] mem_resp_data,
    output logic        idle
);

    localparam logic [2:0] S_IDLE     = 3'd0;
    localparam logic [2:0] S_REFILL   = 3'd1;
    localparam logic [2:0] S_WT       = 3'd2;
    localparam logic [2:0] S_RESP     = 3'd3;

    logic [2:0]  state;
    logic [127:0] line_data [0:15];
    logic [23:0]  line_tag  [0:15];
    logic [15:0]  line_valid;

    logic [31:0] req_addr;
    logic        req_we;
    logic [31:0] req_wdata;
    logic [3:0]  req_be;
    logic [1:0]  req_epoch;

    logic [31:0] refill_base;
    logic [2:0]  refill_word;
    logic [127:0] refill_data;
    logic [23:0] refill_tag;
    logic [3:0]  refill_idx;
    logic [1:0]  refill_epoch;

    logic [31:0] resp_rdata_r;

    logic [3:0]  req_idx;
    logic [23:0] req_tag;
    logic [1:0]  req_wsel;
    logic        req_hit;

    assign req_idx  = req_addr[7:4];
    assign req_tag  = req_addr[31:8];
    assign req_wsel = req_addr[3:2];
    assign req_hit  = line_valid[req_idx] && (line_tag[req_idx] == req_tag);

    assign cpu_req_ready = (state == S_IDLE);

    assign mem_req_valid = (state == S_REFILL) || (state == S_WT);
    assign mem_req_we    = (state == S_WT);
    assign mem_req_addr  = (state == S_REFILL) ? (refill_base + {refill_word, 2'b00}) : req_addr;
    assign mem_req_wdata = req_wdata;
    assign mem_req_be    = (state == S_WT) ? req_be : 4'b0000;

    assign cpu_resp_valid = (state == S_RESP);
    assign cpu_resp_rdata = resp_rdata_r;

    assign idle = (state == S_IDLE);

    logic [31:0] hit_word;
    assign hit_word = line_data[req_idx][{req_wsel, 5'b00000} +: 32];

    logic [31:0] merged_word;
    always_comb begin
        merged_word = hit_word;
        for (int i = 0; i < 4; i++) begin
            if (req_be[i]) begin
                merged_word[8*i +: 8] = req_wdata[8*i +: 8];
            end
        end
    end

    logic [31:0] refill_merged_word;
    always_comb begin
        refill_merged_word = mem_resp_data;
        if (req_we && (refill_base[7:4] == req_addr[7:4]) && (refill_base[31:8] == req_addr[31:8]) &&
            (refill_word == {1'b0, req_addr[3:2]})) begin
            for (int i = 0; i < 4; i++) begin
                if (req_be[i]) begin
                    refill_merged_word[8*i +: 8] = req_wdata[8*i +: 8];
                end
            end
        end
    end

    // Full-vector temporaries so that no constant/part select appears on the
    // LHS of a procedural assignment (avoids Icarus collapsing the select to
    // the whole vector and reporting a spurious multiple driver).
    logic [127:0] line_data_nxt [0:15];
    logic [23:0]  line_tag_nxt  [0:15];
    logic [15:0]  line_valid_nxt;
    logic [127:0] refill_data_nxt;

    integer k;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            line_valid    <= 16'b0;
            req_addr      <= 32'b0;
            req_we        <= 1'b0;
            req_wdata     <= 32'b0;
            req_be        <= 4'b0;
            req_epoch     <= 2'b0;
            refill_base   <= 32'b0;
            refill_word   <= 3'b0;
            refill_data   <= 128'b0;
            refill_tag    <= 24'b0;
            refill_idx    <= 4'b0;
            refill_epoch  <= 2'b0;
            resp_rdata_r  <= 32'b0;
            for (k = 0; k < 16; k = k + 1) begin
                line_data[k] <= 128'b0;
                line_tag[k]  <= 24'b0;
            end
        end else begin
            // Default: hold every array word and the valid vector.
            for (k = 0; k < 16; k = k + 1) begin
                line_data_nxt[k] = line_data[k];
                line_tag_nxt[k]  = line_tag[k];
            end
            line_valid_nxt  = line_valid;
            refill_data_nxt = refill_data;

            case (state)
                S_IDLE: begin
                    if (cpu_req_valid) begin
                        req_addr  <= cpu_req_addr;
                        req_we    <= cpu_req_we;
                        req_wdata <= cpu_req_wdata;
                        req_be    <= cpu_req_be;
                        req_epoch <= flush_epoch;
                        if (req_hit) begin
                            if (cpu_req_we) begin
                                line_data_nxt[req_idx][{req_wsel, 5'b00000} +: 32] = merged_word;
                                state <= S_WT;
                            end else begin
                                resp_rdata_r <= hit_word;
                                state <= S_RESP;
                            end
                        end else begin
                            refill_base  <= {cpu_req_addr[31:4], 4'b0000};
                            refill_word  <= 3'd0;
                            refill_data_nxt <= 128'b0;
                            refill_tag   <= cpu_req_addr[31:8];
                            refill_idx   <= cpu_req_addr[7:4];
                            refill_epoch <= flush_epoch;
                            state <= S_REFILL;
                        end
                    end
                end

                S_REFILL: begin
                    if (mem_req_ready && mem_resp_valid) begin
                        refill_data_nxt[{refill_word[1:0], 5'b00000} +: 32] = refill_merged_word;
                        if (refill_word == 3'd3) begin
                            line_data_nxt[refill_idx] = {refill_merged_word,
                                                         refill_data[95:64],
                                                         refill_data[63:32],
                                                         refill_data[31:0]};
                            line_tag_nxt[refill_idx]   = refill_tag;
                            line_valid_nxt[refill_idx] = 1'b1;
                            if (req_we) begin
                                state <= S_WT;
                            end else begin
                                resp_rdata_r <= refill_merged_word;
                                state <= S_RESP;
                            end
                        end else begin
                            refill_word <= refill_word + 3'd1;
                        end
                    end
                end

                S_WT: begin
                    if (mem_req_ready) begin
                        if (req_we) begin
                            resp_rdata_r <= 32'b0;
                        end
                        state <= S_RESP;
                    end
                end

                S_RESP: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase

            // Single full-vector commit of the arrays / valid bits.
            for (k = 0; k < 16; k = k + 1) begin
                line_data[k] <= line_data_nxt[k];
                line_tag[k]  <= line_tag_nxt[k];
            end
            line_valid  <= line_valid_nxt;
            refill_data <= refill_data_nxt;
        end
    end

endmodule
