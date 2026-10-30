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
    output logic [31:0] mem_req_addr,
    input  logic        mem_req_ready,
    input  logic        mem_resp_valid,
    input  logic [31:0] mem_resp_data,
    output logic        idle
);

    localparam logic [1:0] ST_IDLE  = 2'd0;
    localparam logic [1:0] ST_LOOK  = 2'd1;
    localparam logic [1:0] ST_REFIL = 2'd2;
    localparam logic [1:0] ST_RESP  = 2'd3;

    logic [127:0] line_data [0:15];
    logic [23:0]  line_tag  [0:15];
    logic [15:0]  line_valid;

    logic [1:0]   state;
    logic [31:0]  req_addr_r;
    logic [1:0]   refill_word;
    logic [1:0]   refill_epoch_r;
    logic [31:0]  refill_base_r;
    logic [127:0] refill_data_r;
    logic [31:0]  resp_data_r;

    logic [3:0]   req_index;
    logic [1:0]   req_word;
    logic [23:0]  req_tag;
    logic         req_hit;

    assign req_index = req_addr_r[7:4];
    assign req_word  = req_addr_r[3:2];
    assign req_tag   = req_addr_r[31:8];
    assign req_hit   = line_valid[req_index] && (line_tag[req_index] == req_tag);

    assign cpu_req_ready  = (state == ST_IDLE);
    assign cpu_resp_valid = (state == ST_RESP);
    assign cpu_resp_data  = resp_data_r;

    assign mem_req_valid = (state == ST_REFIL);
    assign mem_req_addr  = refill_base_r + {refill_word, 2'b00};

    assign idle = (state == ST_IDLE);

    logic [31:0] hit_word;
    assign hit_word = line_data[req_index][{req_word, 5'b00000} +: 32];

    // Full-vector next-state temporaries: no constant/part select on the LHS
    // of a procedural assignment, so each array word / valid bit is driven
    // from exactly one process and Icarus cannot collapse the select into a
    // spurious multiple driver.
    logic [127:0] line_data_nxt [0:15];
    logic [23:0]  line_tag_nxt  [0:15];
    logic [15:0]  line_valid_nxt;
    logic [127:0] refill_data_nxt;

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            req_addr_r     <= 32'b0;
            refill_word    <= 2'b0;
            refill_epoch_r <= 2'b0;
            refill_base_r  <= 32'b0;
            refill_data_r  <= 128'b0;
            resp_data_r    <= 32'b0;
            line_valid     <= 16'b0;
            for (i = 0; i < 16; i = i + 1) begin
                line_data[i] <= 128'b0;
                line_tag[i]  <= 24'b0;
            end
        end else begin
            // Default: hold every array word and the valid vector.
            for (i = 0; i < 16; i = i + 1) begin
                line_data_nxt[i] = line_data[i];
                line_tag_nxt[i]  = line_tag[i];
            end
            line_valid_nxt  = line_valid;
            refill_data_nxt = refill_data_r;

            case (state)
                ST_IDLE: begin
                    if (cpu_req_valid) begin
                        req_addr_r <= cpu_req_addr;
                        state      <= ST_LOOK;
                    end
                end

                ST_LOOK: begin
                    if (req_hit) begin
                        resp_data_r <= hit_word;
                        state       <= ST_RESP;
                    end else begin
                        refill_base_r  <= {req_addr_r[31:4], 4'b0000};
                        refill_word    <= 2'b0;
                        refill_epoch_r <= flush_epoch;
                        refill_data_nxt <= 128'b0;
                        state          <= ST_REFIL;
                    end
                end

                ST_REFIL: begin
                    if (mem_resp_valid) begin
                        refill_data_nxt[{refill_word, 5'b00000} +: 32] = mem_resp_data;
                        if (refill_word == 2'd3) begin
                            if (flush_epoch == refill_epoch_r) begin
                                line_data_nxt[req_index] = {mem_resp_data,
                                                            refill_data_r[95:64],
                                                            refill_data_r[63:32],
                                                            refill_data_r[31:0]};
                                line_tag_nxt[req_index]   = req_tag;
                                line_valid_nxt[req_index] = 1'b1;
                                resp_data_r <= mem_resp_data;
                                state       <= ST_RESP;
                            end else begin
                                state <= ST_IDLE;
                            end
                        end else begin
                            refill_word <= refill_word + 2'd1;
                        end
                    end
                end

                ST_RESP: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase

            if (flush && (state == ST_LOOK)) begin
                state <= ST_IDLE;
            end

            // Single full-vector commit of the arrays / valid bits.
            for (i = 0; i < 16; i = i + 1) begin
                line_data[i] <= line_data_nxt[i];
                line_tag[i]  <= line_tag_nxt[i];
            end
            line_valid  <= line_valid_nxt;
            refill_data_r <= refill_data_nxt;
        end
    end

endmodule
