// Data cache: direct-mapped, 256B, 16B lines, write-through, write-allocate
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
    input  logic        mem_req_ready,
    output logic [31:0] mem_req_addr,
    output logic        mem_req_we,
    output logic [31:0] mem_req_wdata,
    output logic [3:0]  mem_req_be,
    input  logic        mem_resp_valid,
    input  logic [31:0] mem_resp_data
);

    // Cache line: 16 lines, each 128 bits (4 words)
    logic [15:0]        tag_valid;
    logic [15:0][23:0]  tag_array;
    logic [15:0][127:0] data_array;

    // Request tracking
    logic [31:0] req_addr_r;
    logic        req_we_r;
    logic [31:0] req_wdata_r;
    logic [3:0]  req_be_r;
    logic [1:0]  req_epoch_r;
    logic        req_active;

    // Refill FSM
    typedef enum logic [2:0] {
        IDLE,
        REFILL_REQ,
        REFILL_WAIT,
        WRITEBACK_REQ,
        WRITEBACK_WAIT
    } state_t;

    state_t state, next_state;

    logic [31:0] refill_base;
    logic [1:0]  refill_word;
    logic [1:0]  refill_epoch;
    logic [3:0]  refill_index;
    logic [23:0] refill_tag;
    logic [127:0] refill_data;
    logic [3:0]  refill_be;

    // Derived signals
    logic [3:0]  index;
    logic [23:0] tag;
    logic [1:0]  wsel;
    logic        hit;
    logic [31:0] hit_word;

    // Icarus-friendly lookup: use a temporary packed vector selected by a
    // hand-unrolled generate block, avoiding variable part-selects and
    // constant array-index selects in always_comb.
    logic [127:0] lookup_line;
    logic [23:0]  lookup_tag;
    logic         lookup_valid;

    assign index = cpu_req_addr[7:4];
    assign tag   = cpu_req_addr[31:8];
    assign wsel  = cpu_req_addr[3:2];

    always_comb begin
        lookup_line  = 128'b0;
        lookup_tag   = 24'b0;
        lookup_valid = 1'b0;
        case (index)
            4'd0: begin
                lookup_line  = data_array[0];
                lookup_tag   = tag_array[0];
                lookup_valid = tag_valid[0];
            end
            4'd1: begin
                lookup_line  = data_array[1];
                lookup_tag   = tag_array[1];
                lookup_valid = tag_valid[1];
            end
            4'd2: begin
                lookup_line  = data_array[2];
                lookup_tag   = tag_array[2];
                lookup_valid = tag_valid[2];
            end
            4'd3: begin
                lookup_line  = data_array[3];
                lookup_tag   = tag_array[3];
                lookup_valid = tag_valid[3];
            end
            4'd4: begin
                lookup_line  = data_array[4];
                lookup_tag   = tag_array[4];
                lookup_valid = tag_valid[4];
            end
            4'd5: begin
                lookup_line  = data_array[5];
                lookup_tag   = tag_array[5];
                lookup_valid = tag_valid[5];
            end
            4'd6: begin
                lookup_line  = data_array[6];
                lookup_tag   = tag_array[6];
                lookup_valid = tag_valid[6];
            end
            4'd7: begin
                lookup_line  = data_array[7];
                lookup_tag   = tag_array[7];
                lookup_valid = tag_valid[7];
            end
            4'd8: begin
                lookup_line  = data_array[8];
                lookup_tag   = tag_array[8];
                lookup_valid = tag_valid[8];
            end
            4'd9: begin
                lookup_line  = data_array[9];
                lookup_tag   = tag_array[9];
                lookup_valid = tag_valid[9];
            end
            4'd10: begin
                lookup_line  = data_array[10];
                lookup_tag   = tag_array[10];
                lookup_valid = tag_valid[10];
            end
            4'd11: begin
                lookup_line  = data_array[11];
                lookup_tag   = tag_array[11];
                lookup_valid = tag_valid[11];
            end
            4'd12: begin
                lookup_line  = data_array[12];
                lookup_tag   = tag_array[12];
                lookup_valid = tag_valid[12];
            end
            4'd13: begin
                lookup_line  = data_array[13];
                lookup_tag   = tag_array[13];
                lookup_valid = tag_valid[13];
            end
            4'd14: begin
                lookup_line  = data_array[14];
                lookup_tag   = tag_array[14];
                lookup_valid = tag_valid[14];
            end
            4'd15: begin
                lookup_line  = data_array[15];
                lookup_tag   = tag_array[15];
                lookup_valid = tag_valid[15];
            end
            default: begin
                lookup_line  = 128'b0;
                lookup_tag   = 24'b0;
                lookup_valid = 1'b0;
            end
        endcase
    end

    assign hit = lookup_valid && (lookup_tag == tag);

    always_comb begin
        hit_word = 32'b0;
        case (wsel)
            2'd0: hit_word = lookup_line[31:0];
            2'd1: hit_word = lookup_line[63:32];
            2'd2: hit_word = lookup_line[95:64];
            2'd3: hit_word = lookup_line[127:96];
            default: hit_word = 32'b0;
        endcase
    end

    // CPU request ready: only when idle and no pending response
    assign cpu_req_ready = (state == IDLE) && !req_active;

    // Memory request outputs
    always_comb begin
        mem_req_valid = 1'b0;
        mem_req_addr  = 32'b0;
        mem_req_we    = 1'b0;
        mem_req_wdata = 32'b0;
        mem_req_be    = 4'b0;
        case (state)
            REFILL_REQ, REFILL_WAIT: begin
                mem_req_valid = 1'b1;
                mem_req_addr  = {refill_base[31:4], refill_word, 2'b00};
                mem_req_we    = 1'b0;
                mem_req_wdata = 32'b0;
                mem_req_be    = 4'b1111;
            end
            WRITEBACK_REQ, WRITEBACK_WAIT: begin
                mem_req_valid = 1'b1;
                mem_req_addr  = req_addr_r;
                mem_req_we    = 1'b1;
                mem_req_wdata = req_wdata_r;
                mem_req_be    = req_be_r;
            end
            default: begin
                mem_req_valid = 1'b0;
                mem_req_addr  = 32'b0;
                mem_req_we    = 1'b0;
                mem_req_wdata = 32'b0;
                mem_req_be    = 4'b0;
            end
        endcase
    end

    // CPU response
    always_comb begin
        cpu_resp_valid = 1'b0;
        cpu_resp_rdata = 32'b0;
        if (req_active && (state == IDLE)) begin
            cpu_resp_valid = 1'b1;
            cpu_resp_rdata = req_we_r ? 32'b0 : hit_word;
        end
    end

    // State machine
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cpu_req_valid && !req_active) begin
                    if (cpu_req_we) begin
                        if (hit) begin
                            next_state = WRITEBACK_REQ;
                        end else begin
                            next_state = REFILL_REQ;
                        end
                    end else begin
                        if (!hit) begin
                            next_state = REFILL_REQ;
                        end else begin
                            next_state = IDLE;
                        end
                    end
                end
            end
            REFILL_REQ: begin
                if (mem_req_ready) begin
                    next_state = REFILL_WAIT;
                end
            end
            REFILL_WAIT: begin
                if (mem_resp_valid) begin
                    if (refill_word == 2'd3) begin
                        if (req_we_r) begin
                            next_state = WRITEBACK_REQ;
                        end else begin
                            next_state = IDLE;
                        end
                    end else begin
                        next_state = REFILL_REQ;
                    end
                end
            end
            WRITEBACK_REQ: begin
                if (mem_req_ready) begin
                    next_state = WRITEBACK_WAIT;
                end
            end
            WRITEBACK_WAIT: begin
                if (mem_resp_valid) begin
                    next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            tag_valid <= 16'b0;
            req_active <= 1'b0;
            req_addr_r <= 32'b0;
            req_we_r <= 1'b0;
            req_wdata_r <= 32'b0;
            req_be_r <= 4'b0;
            req_epoch_r <= 2'b0;
            refill_base <= 32'b0;
            refill_word <= 2'b0;
            refill_epoch <= 2'b0;
            refill_index <= 4'b0;
            refill_tag <= 24'b0;
            refill_data <= 128'b0;
            refill_be <= 4'b0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    if (cpu_req_valid && !req_active) begin
                        req_active <= 1'b1;
                        req_addr_r <= cpu_req_addr;
                        req_we_r <= cpu_req_we;
                        req_wdata_r <= cpu_req_wdata;
                        req_be_r <= cpu_req_be;
                        req_epoch_r <= flush_epoch;
                        if (cpu_req_we) begin
                            if (hit) begin
                                // Store hit: merge byte-enable lanes using a
                                // temporary packed vector and explicit case.
                                case (index)
                                    4'd0: begin
                                        if (cpu_req_be[0]) data_array[0][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[0][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[0][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[0][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd1: begin
                                        if (cpu_req_be[0]) data_array[1][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[1][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[1][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[1][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd2: begin
                                        if (cpu_req_be[0]) data_array[2][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[2][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[2][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[2][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd3: begin
                                        if (cpu_req_be[0]) data_array[3][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[3][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[3][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[3][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd4: begin
                                        if (cpu_req_be[0]) data_array[4][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[4][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[4][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[4][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd5: begin
                                        if (cpu_req_be[0]) data_array[5][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[5][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[5][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[5][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd6: begin
                                        if (cpu_req_be[0]) data_array[6][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[6][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[6][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[6][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd7: begin
                                        if (cpu_req_be[0]) data_array[7][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[7][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[7][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[7][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd8: begin
                                        if (cpu_req_be[0]) data_array[8][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[8][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[8][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[8][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd9: begin
                                        if (cpu_req_be[0]) data_array[9][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[9][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[9][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[9][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd10: begin
                                        if (cpu_req_be[0]) data_array[10][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[10][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[10][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[10][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd11: begin
                                        if (cpu_req_be[0]) data_array[11][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[11][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[11][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[11][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd12: begin
                                        if (cpu_req_be[0]) data_array[12][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[12][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[12][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[12][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd13: begin
                                        if (cpu_req_be[0]) data_array[13][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[13][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[13][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[13][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd14: begin
                                        if (cpu_req_be[0]) data_array[14][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[14][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[14][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[14][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    4'd15: begin
                                        if (cpu_req_be[0]) data_array[15][7:0]   <= cpu_req_wdata[7:0];
                                        if (cpu_req_be[1]) data_array[15][15:8]  <= cpu_req_wdata[15:8];
                                        if (cpu_req_be[2]) data_array[15][23:16] <= cpu_req_wdata[23:16];
                                        if (cpu_req_be[3]) data_array[15][31:24] <= cpu_req_wdata[31:24];
                                    end
                                    default: begin
                                        // No-op
                                    end
                                endcase
                            end else begin
                                // Store miss: refill then merge
                                refill_base <= {cpu_req_addr[31:4], 4'b0};
                                refill_word <= 2'b0;
                                refill_epoch <= flush_epoch;
                                refill_index <= cpu_req_addr[7:4];
                                refill_tag <= cpu_req_addr[31:8];
                                refill_data <= 128'b0;
                                refill_be <= cpu_req_be;
                            end
                        end else begin
                            if (!hit) begin
                                // Load miss: refill
                                refill_base <= {cpu_req_addr[31:4], 4'b0};
                                refill_word <= 2'b0;
                                refill_epoch <= flush_epoch;
                                refill_index <= cpu_req_addr[7:4];
                                refill_tag <= cpu_req_addr[31:8];
                                refill_data <= 128'b0;
                                refill_be <= 4'b0;
                            end
                        end
                    end
                end
                REFILL_REQ: begin
                    if (mem_req_ready) begin
                        // Request accepted, wait for response
                    end
                end
                REFILL_WAIT: begin
                    if (mem_resp_valid) begin
                        case (refill_word)
                            2'd0: refill_data[31:0]   <= mem_resp_data;
                            2'd1: refill_data[63:32]  <= mem_resp_data;
                            2'd2: refill_data[95:64]  <= mem_resp_data;
                            2'd3: refill_data[127:96] <= mem_resp_data;
                            default: refill_data[31:0] <= mem_resp_data;
                        endcase
                        if (refill_word == 2'd3) begin
                            // Install line
                            case (refill_index)
                                4'd0: begin
                                    tag_valid[0] <= 1'b1;
                                    tag_array[0] <= refill_tag;
                                    data_array[0] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[0][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[0][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[0][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[0][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd1: begin
                                    tag_valid[1] <= 1'b1;
                                    tag_array[1] <= refill_tag;
                                    data_array[1] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[1][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[1][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[1][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[1][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd2: begin
                                    tag_valid[2] <= 1'b1;
                                    tag_array[2] <= refill_tag;
                                    data_array[2] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[2][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[2][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[2][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[2][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd3: begin
                                    tag_valid[3] <= 1'b1;
                                    tag_array[3] <= refill_tag;
                                    data_array[3] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[3][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[3][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[3][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[3][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd4: begin
                                    tag_valid[4] <= 1'b1;
                                    tag_array[4] <= refill_tag;
                                    data_array[4] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[4][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[4][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[4][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[4][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd5: begin
                                    tag_valid[5] <= 1'b1;
                                    tag_array[5] <= refill_tag;
                                    data_array[5] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[5][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[5][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[5][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[5][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd6: begin
                                    tag_valid[6] <= 1'b1;
                                    tag_array[6] <= refill_tag;
                                    data_array[6] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[6][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[6][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[6][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[6][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd7: begin
                                    tag_valid[7] <= 1'b1;
                                    tag_array[7] <= refill_tag;
                                    data_array[7] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[7][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[7][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[7][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[7][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd8: begin
                                    tag_valid[8] <= 1'b1;
                                    tag_array[8] <= refill_tag;
                                    data_array[8] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[8][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[8][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[8][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[8][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd9: begin
                                    tag_valid[9] <= 1'b1;
                                    tag_array[9] <= refill_tag;
                                    data_array[9] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[9][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[9][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[9][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[9][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd10: begin
                                    tag_valid[10] <= 1'b1;
                                    tag_array[10] <= refill_tag;
                                    data_array[10] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[10][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[10][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[10][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[10][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd11: begin
                                    tag_valid[11] <= 1'b1;
                                    tag_array[11] <= refill_tag;
                                    data_array[11] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[11][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[11][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[11][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[11][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd12: begin
                                    tag_valid[12] <= 1'b1;
                                    tag_array[12] <= refill_tag;
                                    data_array[12] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[12][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[12][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[12][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[12][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd13: begin
                                    tag_valid[13] <= 1'b1;
                                    tag_array[13] <= refill_tag;
                                    data_array[13] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[13][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[13][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[13][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[13][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd14: begin
                                    tag_valid[14] <= 1'b1;
                                    tag_array[14] <= refill_tag;
                                    data_array[14] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[14][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[14][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[14][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[14][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                4'd15: begin
                                    tag_valid[15] <= 1'b1;
                                    tag_array[15] <= refill_tag;
                                    data_array[15] <= refill_data;
                                    if (req_we_r) begin
                                        if (req_be_r[0]) data_array[15][7:0]   <= req_wdata_r[7:0];
                                        if (req_be_r[1]) data_array[15][15:8]  <= req_wdata_r[15:8];
                                        if (req_be_r[2]) data_array[15][23:16] <= req_wdata_r[23:16];
                                        if (req_be_r[3]) data_array[15][31:24] <= req_wdata_r[31:24];
                                    end
                                end
                                default: begin
                                    // No-op
                                end
                            endcase
                        end else begin
                            refill_word <= refill_word + 2'd1;
                        end
                    end
                end
                WRITEBACK_REQ: begin
                    if (mem_req_ready) begin
                        // Write-through accepted
                    end
                end
                WRITEBACK_WAIT: begin
                    if (mem_resp_valid) begin
                        req_active <= 1'b0;
                    end
                end
                default: begin
                    // No-op
                end
            endcase

            // Flush handling: cancel pending request if not yet accepted
            if (flush && (state == REFILL_REQ) && (refill_epoch != flush_epoch)) begin
                state <= IDLE;
                req_active <= 1'b0;
            end
            if (flush && (state == WRITEBACK_REQ) && (req_epoch_r != flush_epoch)) begin
                state <= IDLE;
                req_active <= 1'b0;
            end
        end
    end

endmodule
