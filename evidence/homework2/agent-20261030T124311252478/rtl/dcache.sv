// rtl/dcache.sv
// Data cache: 256B direct-mapped, write-through + write-allocate
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

    // Cache parameters
    localparam NUM_LINES = 16;
    localparam LINE_WORDS = 4;
    localparam INDEX_BITS = 4;
    localparam OFFSET_BITS = 2;
    localparam TAG_BITS = 24;

    // Cache arrays flattened to packed vectors
    logic [NUM_LINES-1:0]                 valid_arr;
    logic [NUM_LINES-1:0][TAG_BITS-1:0]  tag_arr;
    logic [NUM_LINES-1:0][LINE_WORDS-1:0][31:0] data_arr;

    // Request tracking
    logic [31:0] req_addr_r;
    logic [31:0] req_wdata_r;
    logic [3:0]  req_be_r;
    logic        req_we_r;
    logic        req_valid_r;
    logic [1:0]  req_epoch_r;

    // Refill state
    logic [1:0]  refill_word;
    logic [3:0]  refill_index;
    logic [TAG_BITS-1:0] refill_tag;
    logic [1:0]  refill_epoch;
    logic        refill_active;
    logic [LINE_WORDS-1:0][31:0] refill_data;

    // Write-through state
    logic        wt_active;
    logic [31:0] wt_addr;
    logic [31:0] wt_wdata;
    logic [3:0]  wt_be;
    logic [1:0]  wt_epoch;

    // Response state
    logic        resp_pending;
    logic [31:0] resp_data;
    logic [1:0]  resp_epoch;

    // Address decode
    logic [3:0]  cpu_index;
    logic [TAG_BITS-1:0] cpu_tag;
    logic [1:0]  cpu_word_sel;
    logic        cpu_hit;

    assign cpu_index    = cpu_req_addr[7:4];
    assign cpu_tag      = cpu_req_addr[31:8];
    assign cpu_word_sel = cpu_req_addr[3:2];

    assign cpu_hit = valid_arr[cpu_index] && (tag_arr[cpu_index] == cpu_tag);

    // CPU request ready: accept only when not busy with refill/write-through and no pending response
    assign cpu_req_ready = !refill_active && !wt_active && !resp_pending;

    // Memory request outputs
    always_comb begin
        mem_req_valid = 1'b0;
        mem_req_addr  = 32'b0;
        mem_req_we    = 1'b0;
        mem_req_wdata = 32'b0;
        mem_req_be    = 4'b0;

        if (refill_active) begin
            mem_req_valid = 1'b1;
            mem_req_addr  = {refill_tag, refill_index, refill_word, 2'b00};
            mem_req_we    = 1'b0;
            mem_req_wdata = 32'b0;
            mem_req_be    = 4'b1111;
        end else if (wt_active) begin
            mem_req_valid = 1'b1;
            mem_req_addr  = wt_addr;
            mem_req_we    = 1'b1;
            mem_req_wdata = wt_wdata;
            mem_req_be    = wt_be;
        end
    end

    // CPU response
    assign cpu_resp_valid = resp_pending;
    assign cpu_resp_rdata = resp_data;

    // Main state machine
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_arr <= '0;
            tag_arr   <= '0;
            data_arr  <= '0;
            req_valid_r <= 1'b0;
            req_addr_r  <= 32'b0;
            req_wdata_r <= 32'b0;
            req_be_r    <= 4'b0;
            req_we_r    <= 1'b0;
            req_epoch_r <= 2'b0;
            refill_active <= 1'b0;
            refill_word   <= 2'b0;
            refill_index  <= 4'b0;
            refill_tag    <= '0;
            refill_epoch  <= 2'b0;
            refill_data   <= '0;
            wt_active     <= 1'b0;
            wt_addr       <= 32'b0;
            wt_wdata      <= 32'b0;
            wt_be         <= 4'b0;
            wt_epoch      <= 2'b0;
            resp_pending  <= 1'b0;
            resp_data     <= 32'b0;
            resp_epoch    <= 2'b0;
        end else begin
            // Default: clear one-cycle response
            if (resp_pending) begin
                resp_pending <= 1'b0;
            end

            // Handle flush: cancel pending CPU request if not yet accepted
            if (flush) begin
                if (req_valid_r && !refill_active && !wt_active) begin
                    req_valid_r <= 1'b0;
                end
                // If refill/wt in progress, they continue; responses will be epoch-gated
            end

            // Refill state machine
            if (refill_active) begin
                if (mem_req_ready) begin
                    // Current refill word accepted
                    if (mem_resp_valid) begin
                        // Capture response data for current word
                        case (refill_word)
                            2'd0: refill_data[0] <= mem_resp_data;
                            2'd1: refill_data[1] <= mem_resp_data;
                            2'd2: refill_data[2] <= mem_resp_data;
                            2'd3: refill_data[3] <= mem_resp_data;
                            default: ;
                        endcase
                        if (refill_word == 2'd3) begin
                            // Last word: install line
                            valid_arr[refill_index] <= 1'b1;
                            tag_arr[refill_index]   <= refill_tag;
                            data_arr[refill_index][0] <= refill_data[0];
                            data_arr[refill_index][1] <= refill_data[1];
                            data_arr[refill_index][2] <= refill_data[2];
                            data_arr[refill_index][3] <= refill_data[3];
                            refill_active <= 1'b0;
                            // If there was a pending CPU request for this line, handle it
                            if (req_valid_r && (req_addr_r[7:4] == refill_index) &&
                                (req_addr_r[31:8] == refill_tag) &&
                                (req_epoch_r == refill_epoch)) begin
                                if (req_we_r) begin
                                    // Store: merge into line and start write-through
                                    // Merge byte-enables into the selected word
                                    case (req_addr_r[3:2])
                                        2'd0: begin
                                            if (req_be_r[0]) data_arr[refill_index][0][7:0]   <= req_wdata_r[7:0];
                                            if (req_be_r[1]) data_arr[refill_index][0][15:8]  <= req_wdata_r[15:8];
                                            if (req_be_r[2]) data_arr[refill_index][0][23:16] <= req_wdata_r[23:16];
                                            if (req_be_r[3]) data_arr[refill_index][0][31:24] <= req_wdata_r[31:24];
                                        end
                                        2'd1: begin
                                            if (req_be_r[0]) data_arr[refill_index][1][7:0]   <= req_wdata_r[7:0];
                                            if (req_be_r[1]) data_arr[refill_index][1][15:8]  <= req_wdata_r[15:8];
                                            if (req_be_r[2]) data_arr[refill_index][1][23:16] <= req_wdata_r[23:16];
                                            if (req_be_r[3]) data_arr[refill_index][1][31:24] <= req_wdata_r[31:24];
                                        end
                                        2'd2: begin
                                            if (req_be_r[0]) data_arr[refill_index][2][7:0]   <= req_wdata_r[7:0];
                                            if (req_be_r[1]) data_arr[refill_index][2][15:8]  <= req_wdata_r[15:8];
                                            if (req_be_r[2]) data_arr[refill_index][2][23:16] <= req_wdata_r[23:16];
                                            if (req_be_r[3]) data_arr[refill_index][2][31:24] <= req_wdata_r[31:24];
                                        end
                                        2'd3: begin
                                            if (req_be_r[0]) data_arr[refill_index][3][7:0]   <= req_wdata_r[7:0];
                                            if (req_be_r[1]) data_arr[refill_index][3][15:8]  <= req_wdata_r[15:8];
                                            if (req_be_r[2]) data_arr[refill_index][3][23:16] <= req_wdata_r[23:16];
                                            if (req_be_r[3]) data_arr[refill_index][3][31:24] <= req_wdata_r[31:24];
                                        end
                                        default: ;
                                    endcase
                                    wt_active <= 1'b1;
                                    wt_addr   <= req_addr_r;
                                    wt_wdata  <= req_wdata_r;
                                    wt_be     <= req_be_r;
                                    wt_epoch  <= req_epoch_r;
                                    req_valid_r <= 1'b0;
                                end else begin
                                    // Load: respond with the requested word
                                    resp_pending <= 1'b1;
                                    case (req_addr_r[3:2])
                                        2'd0: resp_data <= refill_data[0];
                                        2'd1: resp_data <= refill_data[1];
                                        2'd2: resp_data <= refill_data[2];
                                        2'd3: resp_data <= refill_data[3];
                                        default: resp_data <= 32'b0;
                                    endcase
                                    resp_epoch   <= req_epoch_r;
                                    req_valid_r  <= 1'b0;
                                end
                            end
                        end else begin
                            refill_word <= refill_word + 2'd1;
                        end
                    end else begin
                        // mem_req_ready but no mem_resp_valid: wait for response
                        // Keep refill_word stable
                    end
                end
            end else if (wt_active) begin
                if (mem_req_ready) begin
                    // Write-through accepted
                    wt_active <= 1'b0;
                    // Generate response for the store
                    resp_pending <= 1'b1;
                    resp_data    <= 32'b0;
                    resp_epoch   <= wt_epoch;
                end
            end else begin
                // Idle: accept new CPU request
                if (cpu_req_valid && cpu_req_ready) begin
                    req_valid_r <= 1'b1;
                    req_addr_r  <= cpu_req_addr;
                    req_wdata_r <= cpu_req_wdata;
                    req_be_r    <= cpu_req_be;
                    req_we_r    <= cpu_req_we;
                    req_epoch_r <= flush_epoch;

                    if (cpu_hit) begin
                        if (cpu_req_we) begin
                            // Store hit: merge into line and start write-through
                            case (cpu_word_sel)
                                2'd0: begin
                                    if (cpu_req_be[0]) data_arr[cpu_index][0][7:0]   <= cpu_req_wdata[7:0];
                                    if (cpu_req_be[1]) data_arr[cpu_index][0][15:8]  <= cpu_req_wdata[15:8];
                                    if (cpu_req_be[2]) data_arr[cpu_index][0][23:16] <= cpu_req_wdata[23:16];
                                    if (cpu_req_be[3]) data_arr[cpu_index][0][31:24] <= cpu_req_wdata[31:24];
                                end
                                2'd1: begin
                                    if (cpu_req_be[0]) data_arr[cpu_index][1][7:0]   <= cpu_req_wdata[7:0];
                                    if (cpu_req_be[1]) data_arr[cpu_index][1][15:8]  <= cpu_req_wdata[15:8];
                                    if (cpu_req_be[2]) data_arr[cpu_index][1][23:16] <= cpu_req_wdata[23:16];
                                    if (cpu_req_be[3]) data_arr[cpu_index][1][31:24] <= cpu_req_wdata[31:24];
                                end
                                2'd2: begin
                                    if (cpu_req_be[0]) data_arr[cpu_index][2][7:0]   <= cpu_req_wdata[7:0];
                                    if (cpu_req_be[1]) data_arr[cpu_index][2][15:8]  <= cpu_req_wdata[15:8];
                                    if (cpu_req_be[2]) data_arr[cpu_index][2][23:16] <= cpu_req_wdata[23:16];
                                    if (cpu_req_be[3]) data_arr[cpu_index][2][31:24] <= cpu_req_wdata[31:24];
                                end
                                2'd3: begin
                                    if (cpu_req_be[0]) data_arr[cpu_index][3][7:0]   <= cpu_req_wdata[7:0];
                                    if (cpu_req_be[1]) data_arr[cpu_index][3][15:8]  <= cpu_req_wdata[15:8];
                                    if (cpu_req_be[2]) data_arr[cpu_index][3][23:16] <= cpu_req_wdata[23:16];
                                    if (cpu_req_be[3]) data_arr[cpu_index][3][31:24] <= cpu_req_wdata[31:24];
                                end
                                default: ;
                            endcase
                            wt_active <= 1'b1;
                            wt_addr   <= cpu_req_addr;
                            wt_wdata  <= cpu_req_wdata;
                            wt_be     <= cpu_req_be;
                            wt_epoch  <= flush_epoch;
                            req_valid_r <= 1'b0;
                        end else begin
                            // Load hit: respond next cycle
                            resp_pending <= 1'b1;
                            case (cpu_word_sel)
                                2'd0: resp_data <= data_arr[cpu_index][0];
                                2'd1: resp_data <= data_arr[cpu_index][1];
                                2'd2: resp_data <= data_arr[cpu_index][2];
                                2'd3: resp_data <= data_arr[cpu_index][3];
                                default: resp_data <= 32'b0;
                            endcase
                            resp_epoch   <= flush_epoch;
                            req_valid_r  <= 1'b0;
                        end
                    end else begin
                        // Miss: start refill
                        refill_active <= 1'b1;
                        refill_word   <= 2'd0;
                        refill_index  <= cpu_index;
                        refill_tag    <= cpu_tag;
                        refill_epoch  <= flush_epoch;
                        refill_data   <= '0;
                    end
                end
            end

            // Epoch check for pending response
            if (resp_pending && (resp_epoch != flush_epoch)) begin
                resp_pending <= 1'b0;
            end
        end
    end

endmodule
