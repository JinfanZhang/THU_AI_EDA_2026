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

    localparam IDLE = 2'd0;
    localparam REFILL = 2'd1;
    localparam RESP = 2'd2;

    logic [15:0] tag_array;
    logic [15:0] valid_array;
    logic [31:0] data_array [0:15][0:3];

    logic [3:0]  index;
    logic [23:0] tag;
    logic [1:0]  wsel;
    logic        hit;
    logic [31:0] hit_data;

    logic [1:0]  state;
    logic [1:0]  refill_word;
    logic [31:0] refill_base;
    logic [23:0] refill_tag;
    logic [3:0]  refill_index;
    logic [1:0]  refill_epoch;
    logic [31:0] resp_data_r;
    logic        resp_valid_r;
    logic        resp_epoch_match;

    assign index = cpu_req_addr[7:4];
    assign tag   = cpu_req_addr[31:8];
    assign wsel  = cpu_req_addr[3:2];

    assign hit      = valid_array[index] && (tag_array[index] == tag);
    assign hit_data = data_array[index][wsel];

    always_comb begin
        cpu_req_ready = 1'b0;
        cpu_resp_valid = 1'b0;
        cpu_resp_data = 32'b0;
        mem_req_valid = 1'b0;
        mem_req_addr = 32'b0;

        case (state)
            IDLE: begin
                if (cpu_req_valid) begin
                    if (hit) begin
                        cpu_req_ready = 1'b1;
                    end else begin
                        mem_req_valid = 1'b1;
                        mem_req_addr = {cpu_req_addr[31:4], 4'b0000};
                    end
                end
            end
            REFILL: begin
                mem_req_valid = 1'b1;
                mem_req_addr = {refill_base[31:4], refill_word, 2'b00};
            end
            RESP: begin
                cpu_resp_valid = resp_valid_r;
                cpu_resp_data = resp_data_r;
                cpu_req_ready = 1'b0;
            end
            default: begin
                cpu_req_ready = 1'b0;
                cpu_resp_valid = 1'b0;
                cpu_resp_data = 32'b0;
                mem_req_valid = 1'b0;
                mem_req_addr = 32'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            refill_word <= 2'd0;
            refill_base <= 32'b0;
            refill_tag <= 24'b0;
            refill_index <= 4'b0;
            refill_epoch <= 2'b0;
            resp_data_r <= 32'b0;
            resp_valid_r <= 1'b0;
            resp_epoch_match <= 1'b0;
            valid_array <= 16'b0;
            tag_array <= 16'b0;
            for (int i = 0; i < 16; i++) begin
                for (int j = 0; j < 4; j++) begin
                    data_array[i][j] <= 32'b0;
                end
            end
        end else begin
            case (state)
                IDLE: begin
                    resp_valid_r <= 1'b0;
                    if (cpu_req_valid) begin
                        if (hit) begin
                            resp_data_r <= hit_data;
                            resp_valid_r <= 1'b1;
                            resp_epoch_match <= 1'b1;
                            state <= RESP;
                        end else begin
                            refill_base <= {cpu_req_addr[31:4], 4'b0000};
                            refill_tag <= tag;
                            refill_index <= index;
                            refill_word <= 2'd0;
                            refill_epoch <= flush_epoch;
                            state <= REFILL;
                        end
                    end
                end
                REFILL: begin
                    if (mem_req_ready) begin
                        if (mem_resp_valid) begin
                            data_array[refill_index][refill_word] <= mem_resp_data;
                            if (refill_word == 2'd3) begin
                                tag_array[refill_index] <= refill_tag;
                                valid_array[refill_index] <= 1'b1;
                                resp_data_r <= data_array[refill_index][refill_base[3:2]];
                                resp_valid_r <= (refill_epoch == flush_epoch);
                                resp_epoch_match <= (refill_epoch == flush_epoch);
                                state <= RESP;
                            end else begin
                                refill_word <= refill_word + 2'd1;
                            end
                        end
                    end
                end
                RESP: begin
                    resp_valid_r <= 1'b0;
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
