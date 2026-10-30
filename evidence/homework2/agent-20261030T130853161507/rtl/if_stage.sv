// rtl/if_stage.sv
module if_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cpu_resp_valid,
    input  logic [31:0] cpu_resp_data,
    input  logic        cpu_req_ready,
    input  logic        redirect_valid,
    input  logic [31:0] redirect_pc,
    input  logic        stall,
    input  logic        pred_pc_valid,
    input  logic [31:0] pred_pc,
    input  logic        ecall_halt_pending,
    input  logic        flush_ifid,
    output logic        cpu_req_valid,
    output logic [31:0] cpu_req_addr,
    output logic        if_id_valid,
    output logic [31:0] if_id_pc,
    output logic [31:0] if_id_insn,
    output logic [1:0]  flush_epoch,
    output logic [31:0] pc_query
);

    logic [31:0] pc;
    logic [31:0] next_pc;
    logic        req_pending;
    logic        if_id_valid_r;
    logic [31:0] if_id_pc_r;
    logic [31:0] if_id_insn_r;
    logic [1:0]  flush_epoch_r;
    logic        halt_pending;

    // PC query for branch predictor
    assign pc_query = pc;

    // Next PC selection.
    // pred_pc is only consumed when pred_pc_valid is high.  When the BTB
    // misses (pred_pc_valid == 0), pred_pc may be stale or uninitialized and
    // must never be used; the front-end falls through to PC+4.
    always_comb begin
        if (redirect_valid)
            next_pc = redirect_pc;
        else if (pred_pc_valid && !stall && !ecall_halt_pending && !halt_pending)
            next_pc = pred_pc;
        else
            next_pc = pc + 32'h4;
    end

    // CPU request to icache
    assign cpu_req_valid = req_pending && !halt_pending && !ecall_halt_pending;
    assign cpu_req_addr  = pc;

    // Outputs
    assign if_id_valid = if_id_valid_r;
    assign if_id_pc    = if_id_pc_r;
    assign if_id_insn  = if_id_insn_r;
    assign flush_epoch = flush_epoch_r;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc              <= 32'h0;
            req_pending     <= 1'b1;
            if_id_valid_r   <= 1'b0;
            if_id_pc_r      <= 32'h0;
            if_id_insn_r    <= 32'h0;
            flush_epoch_r   <= 2'b00;
            halt_pending    <= 1'b0;
        end else begin
            // Halt pending handling
            if (ecall_halt_pending && !halt_pending) begin
                halt_pending <= 1'b1;
                req_pending  <= 1'b0;
                if_id_valid_r <= 1'b0;
            end else if (redirect_valid) begin
                pc              <= redirect_pc;
                req_pending     <= 1'b1;
                if_id_valid_r   <= 1'b0;
                flush_epoch_r   <= flush_epoch_r + 2'b01;
                halt_pending    <= 1'b0;
            end else if (flush_ifid) begin
                // Misprediction flush: clear only the IF/ID valid bit.
                // Do not change PC here; the redirect path above has priority
                // and will set the correct PC in the same cycle.
                if_id_valid_r <= 1'b0;
                req_pending   <= req_pending;
                pc            <= pc;
                flush_epoch_r <= flush_epoch_r;
                halt_pending  <= halt_pending;
            end else if (cpu_resp_valid) begin
                // Capture response unconditionally
                if_id_valid_r <= 1'b1;
                if_id_pc_r    <= pc;
                if_id_insn_r  <= cpu_resp_data;
                pc            <= next_pc;
                req_pending   <= 1'b1;
            end else if (stall) begin
                // Hold IF/ID valid during stall
                if_id_valid_r <= if_id_valid_r;
                if_id_pc_r    <= if_id_pc_r;
                if_id_insn_r  <= if_id_insn_r;
                // Keep req_pending and pc stable
                req_pending   <= req_pending;
                pc            <= pc;
            end else begin
                // Normal advance
                if (req_pending && cpu_req_ready) begin
                    req_pending   <= 1'b0;
                    if_id_valid_r <= 1'b0;
                end else if (!req_pending) begin
                    req_pending   <= 1'b1;
                    if_id_valid_r <= 1'b0;
                end
                pc <= next_pc;
            end
        end
    end

endmodule
