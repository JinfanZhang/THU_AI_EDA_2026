module if_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        if_stall,
    input  logic        if_flush,
    input  logic        redirect_valid,
    input  logic [31:0] redirect_pc,
    input  logic        halt_pending,
    output logic [31:0] bp_lookup_pc,
    input  logic        bp_pred_taken,
    input  logic [31:0] bp_pred_target,
    output logic        cpu_req_valid,
    output logic [31:0] cpu_req_addr,
    input  logic        cpu_req_ready,
    input  logic        cpu_resp_valid,
    input  logic [31:0] cpu_resp_data,
    output logic        if_id_valid,
    output logic [31:0] if_id_pc,
    output logic [31:0] if_id_pc_plus4,
    output logic [31:0] if_id_instr,
    output logic [31:0] if_id_pred_next_pc,
    output logic        if_id_pred_valid
);

    // Single-cycle fetch model: the request address is driven
    // combinationally from the live fetch PC, and the response data is
    // consumed in the SAME cycle the request is accepted (cpu_req_ready).
    // The PC captured into IF/ID is the PC of the word actually fetched
    // this cycle (fetch_pc), NOT the incremented next PC.
    logic [31:0] fetch_pc;
    logic [31:0] pred_next_pc;
    logic        pred_valid;

    // Prediction is consumed combinationally from the predictor lookup
    // on the current fetch PC.  A taken prediction redirects the next
    // fetch to bp_pred_target; otherwise the fall-through is PC+4.
    always_comb begin
        pred_next_pc = fetch_pc + 32'd4;
        pred_valid   = 1'b0;
        if (bp_pred_taken) begin
            pred_next_pc = bp_pred_target;
            pred_valid   = 1'b1;
        end
    end

    assign bp_lookup_pc = fetch_pc;

    // Request address is the live PC (word aligned).  The request is
    // valid whenever we are allowed to fetch and not halted.
    assign cpu_req_addr  = {fetch_pc[31:2], 2'b00};
    assign cpu_req_valid = rst_n & ~halt_pending;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fetch_pc           <= 32'h0000_0000;
            if_id_valid        <= 1'b0;
            if_id_pc           <= 32'h0000_0000;
            if_id_pc_plus4     <= 32'h0000_0000;
            if_id_instr        <= 32'h0000_0000;
            if_id_pred_next_pc <= 32'h0000_0000;
            if_id_pred_valid   <= 1'b0;
        end else if (halt_pending) begin
            // Freeze fetch once halted; stop producing new instructions.
            if_id_valid     <= 1'b0;
            if_id_pred_valid<= 1'b0;
        end else if (redirect_valid) begin
            // Control transfer resolved in EX: flush younger instructions
            // and restart fetch at the redirect target next cycle.
            fetch_pc        <= {redirect_pc[31:2], 2'b00};
            if_id_valid     <= 1'b0;
            if_id_pred_valid<= 1'b0;
        end else if (if_flush) begin
            // Flush the instruction currently in IF/ID; keep fetching.
            if_id_valid     <= 1'b0;
            if_id_pred_valid<= 1'b0;
            fetch_pc        <= pred_next_pc;
        end else if (if_stall) begin
            // Freeze PC and IF/ID for exactly the stall cycle.
            fetch_pc        <= fetch_pc;
            if_id_valid     <= if_id_valid;
            if_id_pred_valid<= if_id_pred_valid;
        end else if (cpu_req_ready) begin
            // Same-cycle response: capture the instruction word that the
            // memory returns for the address driven this cycle, together
            // with THAT address (fetch_pc), not the incremented next PC.
            if_id_valid        <= 1'b1;
            if_id_pc           <= {fetch_pc[31:2], 2'b00};
            if_id_pc_plus4     <= {fetch_pc[31:2], 2'b00} + 32'd4;
            if_id_instr        <= cpu_resp_data;
            if_id_pred_next_pc <= pred_next_pc;
            if_id_pred_valid   <= pred_valid;
            fetch_pc           <= pred_next_pc;
        end else begin
            // Wait state: hold PC, do not capture a valid instruction.
            fetch_pc        <= fetch_pc;
            if_id_valid     <= 1'b0;
            if_id_pred_valid<= 1'b0;
        end
    end

endmodule
