module icache (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cpu_req_valid,
    input  logic [31:0] cpu_req_addr,
    output logic        cpu_req_ready,
    output logic        cpu_resp_valid,
    output logic [31:0] cpu_resp_data,
    input  logic        flush,
    input  logic [1:0]  flush_epoch,
    output logic        mem_req_valid,
    input  logic        mem_req_ready,
    output logic [31:0] mem_req_addr,
    input  logic        mem_resp_valid,
    input  logic [31:0] mem_resp_data
);

    // Cache parameters
    localparam NUM_LINES = 16;
    localparam LINE_WORDS = 4;
    localparam TAG_WIDTH = 24;
    localparam INDEX_WIDTH = 4;
    localparam OFFSET_WIDTH = 2;

    // Cache arrays
    logic [NUM_LINES-1:0]                 valid_r;
    logic [NUM_LINES-1:0][TAG_WIDTH-1:0] tag_r;
    logic [NUM_LINES-1:0][LINE_WORDS-1:0][31:0] data_r;

    // Refill FSM
    typedef enum logic [1:0] {
        IDLE,
        REFILL
    } state_t;

    state_t state_r;
    logic [INDEX_WIDTH-1:0] refill_index_r;
    logic [TAG_WIDTH-1:0]   refill_tag_r;
    logic [1:0]             refill_word_r;
    logic [1:0]             refill_epoch_r;
    logic [31:0]            refill_base_addr_r;

    // CPU request tracking
    logic req_pending_r;
    logic [31:0] req_addr_r;
    logic [1:0]  req_epoch_r;

    // Response registers
    logic resp_valid_r;
    logic [31:0] resp_data_r;

    // Address decode
    logic [INDEX_WIDTH-1:0] cpu_index;
    logic [TAG_WIDTH-1:0]   cpu_tag;
    logic [1:0]             cpu_word_sel;

    assign cpu_index    = cpu_req_addr[7:4];
    assign cpu_tag      = cpu_req_addr[31:8];
    assign cpu_word_sel = cpu_req_addr[3:2];

    // Cache hit detection
    logic cpu_hit;
    assign cpu_hit = valid_r[cpu_index] && (tag_r[cpu_index] == cpu_tag);

    // CPU request ready: can accept when not busy refilling and no pending response
    assign cpu_req_ready = (state_r == IDLE) && !resp_valid_r;

    // Memory request outputs
    always_comb begin
        mem_req_valid = 1'b0;
        mem_req_addr  = 32'b0;
        if (state_r == REFILL) begin
            mem_req_valid = 1'b1;
            mem_req_addr  = {refill_tag_r, refill_index_r, refill_word_r, 2'b00};
        end
    end

    // CPU response outputs
    assign cpu_resp_valid = resp_valid_r;
    assign cpu_resp_data  = resp_data_r;

    // Sequential logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_r          <= '0;
            tag_r            <= '0;
            data_r           <= '0;
            state_r          <= IDLE;
            refill_index_r   <= '0;
            refill_tag_r     <= '0;
            refill_word_r    <= '0;
            refill_epoch_r   <= '0;
            refill_base_addr_r <= '0;
            req_pending_r    <= 1'b0;
            req_addr_r       <= '0;
            req_epoch_r      <= '0;
            resp_valid_r     <= 1'b0;
            resp_data_r      <= '0;
        end else begin
            // Default: clear response valid
            resp_valid_r <= 1'b0;

            case (state_r)
                IDLE: begin
                    if (cpu_req_valid && cpu_req_ready) begin
                        if (cpu_hit) begin
                            // Hit: return data next cycle
                            resp_valid_r <= 1'b1;
                            case (cpu_word_sel)
                                2'd0: resp_data_r <= data_r[cpu_index][0];
                                2'd1: resp_data_r <= data_r[cpu_index][1];
                                2'd2: resp_data_r <= data_r[cpu_index][2];
                                2'd3: resp_data_r <= data_r[cpu_index][3];
                                default: resp_data_r <= 32'b0;
                            endcase
                        end else begin
                            // Miss: start refill
                            state_r          <= REFILL;
                            refill_index_r   <= cpu_index;
                            refill_tag_r     <= cpu_tag;
                            refill_word_r    <= 2'b00;
                            refill_epoch_r   <= flush_epoch;
                            refill_base_addr_r <= {cpu_req_addr[31:4], 4'b0000};
                            req_pending_r    <= 1'b0;
                            req_addr_r       <= cpu_req_addr;
                            req_epoch_r      <= flush_epoch;
                        end
                    end
                end

                REFILL: begin
                    if (mem_req_valid && mem_req_ready) begin
                        // Word accepted by memory
                        if (mem_resp_valid) begin
                            // Store word into line
                            case (refill_word_r)
                                2'd0: data_r[refill_index_r][0] <= mem_resp_data;
                                2'd1: data_r[refill_index_r][1] <= mem_resp_data;
                                2'd2: data_r[refill_index_r][2] <= mem_resp_data;
                                2'd3: data_r[refill_index_r][3] <= mem_resp_data;
                                default: ;
                            endcase
                            if (refill_word_r == 2'b11) begin
                                // Last word: install line
                                valid_r[refill_index_r] <= 1'b1;
                                tag_r[refill_index_r]   <= refill_tag_r;
                                state_r <= IDLE;
                                // Return response if epoch matches
                                if (refill_epoch_r == flush_epoch) begin
                                    resp_valid_r <= 1'b1;
                                    resp_data_r  <= mem_resp_data;
                                end
                            end else begin
                                refill_word_r <= refill_word_r + 1'b1;
                            end
                        end else begin
                            // Wait for memory response
                            // Keep state, mem_req_valid stays high
                        end
                    end
                end
            endcase

            // Handle flush: cancel pending refill if epoch mismatch
            if (flush && (state_r == REFILL) && (refill_epoch_r != flush_epoch)) begin
                state_r <= IDLE;
                // Do not install line
            end
        end
    end

endmodule
