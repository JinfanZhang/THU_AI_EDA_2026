module fetch_unit (
    input  logic        clk,
    input  logic        rst_n,
    output logic        icache_cpu_req_valid,
    output logic [31:0] icache_cpu_req_addr,
    input  logic        icache_cpu_req_ready,
    input  logic        icache_cpu_resp_valid,
    input  logic [31:0] icache_cpu_resp_data,
    output logic        icache_flush,
    output logic [1:0]  icache_flush_epoch,
    input  logic [1:0]  rob_epoch,
    input  logic        rob_flush,
    output logic [31:0] branch_pred_pc_query,
    input  logic        branch_pred_valid,
    input  logic        branch_pred_taken,
    input  logic [31:0] branch_pred_target,
    input  logic        redirect_valid,
    input  logic [31:0] redirect_pc,
    input  logic        halt_request,
    output logic        fetch_valid,
    output logic [31:0] fetch_pc,
    output logic [31:0] fetch_insn,
    input  logic        decode_ready
);

    // PC register
    logic [31:0] pc_q;
    // Fetch request pending
    logic req_pending;
    // Fetch output register
    logic fetch_valid_q;
    logic [31:0] fetch_pc_q;
    logic [31:0] fetch_insn_q;
    // Halt pending state
    logic halt_pending;
    // Local flush epoch
    logic [1:0] local_epoch;

    // Branch prediction query is the current PC
    assign branch_pred_pc_query = pc_q;

    // Next PC selection
    logic [31:0] next_pc;
    logic        take_pred;
    logic        take_redirect;
    logic        take_halt;

    always_comb begin
        take_pred     = 1'b0;
        take_redirect = 1'b0;
        take_halt     = 1'b0;
        next_pc       = pc_q + 32'd4;

        if (redirect_valid) begin
            take_redirect = 1'b1;
            next_pc       = redirect_pc;
        end else if (halt_request && !halt_pending) begin
            take_halt = 1'b1;
            next_pc   = pc_q;
        end else if (branch_pred_valid && branch_pred_taken) begin
            take_pred = 1'b1;
            next_pc   = branch_pred_target;
        end
    end

    // icache request signals
    assign icache_cpu_req_valid = req_pending && !halt_pending;
    assign icache_cpu_req_addr  = pc_q;

    // Flush signals
    assign icache_flush       = rob_flush || redirect_valid || (halt_request && !halt_pending);
    assign icache_flush_epoch = local_epoch;

    // Fetch outputs
    assign fetch_valid = fetch_valid_q;
    assign fetch_pc    = fetch_pc_q;
    assign fetch_insn  = fetch_insn_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_q           <= 32'h0000_0000;
            req_pending    <= 1'b0;
            fetch_valid_q  <= 1'b0;
            fetch_pc_q     <= 32'h0000_0000;
            fetch_insn_q   <= 32'h0000_0000;
            halt_pending   <= 1'b0;
            local_epoch    <= 2'b00;
        end else begin
            // Update local epoch on flush
            if (rob_flush || redirect_valid) begin
                local_epoch <= local_epoch + 2'b01;
            end

            if (redirect_valid) begin
                pc_q          <= redirect_pc;
                req_pending   <= 1'b1;
                fetch_valid_q <= 1'b0;
                halt_pending  <= 1'b0;
            end else if (halt_request && !halt_pending) begin
                halt_pending <= 1'b1;
                req_pending  <= 1'b0;
                fetch_valid_q <= 1'b0;
                pc_q         <= pc_q;
            end else if (halt_pending) begin
                // Halted: no new requests, keep state stable
                req_pending  <= 1'b0;
                fetch_valid_q <= 1'b0;
                pc_q         <= pc_q;
            end else if (icache_cpu_resp_valid) begin
                // Capture response unconditionally
                fetch_valid_q <= 1'b1;
                fetch_pc_q    <= pc_q;
                fetch_insn_q  <= icache_cpu_resp_data;
                pc_q          <= next_pc;
                req_pending   <= 1'b1;
            end else if (req_pending && icache_cpu_req_ready) begin
                // Request accepted, wait for response
                req_pending   <= 1'b0;
                fetch_valid_q <= 1'b0;
            end else if (!req_pending && decode_ready) begin
                // Issue new request
                req_pending   <= 1'b1;
                fetch_valid_q <= 1'b0;
            end else if (!req_pending && !decode_ready) begin
                // Stall: hold fetch_valid_q
                fetch_valid_q <= fetch_valid_q;
            end
        end
    end

endmodule
