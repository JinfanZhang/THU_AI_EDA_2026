module fetch_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        halt_pending,
    input  logic        halted,
    input  logic        flush_all,
    input  logic [1:0]  flush_epoch,
    input  logic        redirect_valid,
    input  logic [31:0] redirect_pc,
    output logic        ic_req_valid,
    output logic [31:0] ic_req_addr,
    input  logic        ic_req_ready,
    input  logic        ic_resp_valid,
    input  logic [31:0] ic_resp_data,
    output logic        ic_flush,
    output logic [1:0]  ic_flush_epoch,
    output logic        bp_req_valid,
    output logic [31:0] bp_pc,
    input  logic [31:0] bp_npc,
    input  logic        bp_hit,
    output logic        if_valid,
    input  logic        if_ready,
    output logic [31:0] if_pc,
    output logic [31:0] if_insn,
    output logic [31:0] if_pred_npc,
    output logic        if_pred_valid
);

    logic [31:0] pc;
    logic        req_pending;
    logic [31:0] req_addr;

    logic [31:0] if_pc_q;
    logic [31:0] if_insn_q;
    logic [31:0] if_pred_npc_q;
    logic        if_pred_valid_q;
    logic        if_valid_q;

    logic        stop_fetch;
    logic        req_fire;
    logic        resp_fire;

    assign stop_fetch = halt_pending | halted;

    assign ic_req_valid   = req_pending & ~stop_fetch;
    assign ic_req_addr    = req_addr;
    assign ic_flush       = flush_all;
    assign ic_flush_epoch = flush_epoch;

    assign bp_req_valid = ~stop_fetch & ~req_pending & ~if_valid_q;
    assign bp_pc        = pc;

    assign if_valid      = if_valid_q;
    assign if_pc         = if_pc_q;
    assign if_insn       = if_insn_q;
    assign if_pred_npc   = if_pred_npc_q;
    assign if_pred_valid = if_pred_valid_q;

    assign req_fire  = ic_req_valid & ic_req_ready;
    assign resp_fire = ic_resp_valid;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc             <= 32'h0000_0000;
            req_pending    <= 1'b0;
            req_addr       <= 32'h0000_0000;
            if_valid_q     <= 1'b0;
            if_pc_q        <= 32'h0000_0000;
            if_insn_q      <= 32'h0000_0000;
            if_pred_npc_q  <= 32'h0000_0000;
            if_pred_valid_q<= 1'b0;
        end else if (flush_all) begin
            req_pending    <= 1'b0;
            if_valid_q     <= 1'b0;
            if_pc_q        <= 32'h0000_0000;
            if_insn_q      <= 32'h0000_0000;
            if_pred_npc_q  <= 32'h0000_0000;
            if_pred_valid_q<= 1'b0;
            if (redirect_valid) begin
                pc      <= {redirect_pc[31:2], 2'b00};
                req_addr<= {redirect_pc[31:2], 2'b00};
            end
        end else if (halted) begin
            req_pending    <= 1'b0;
            if_valid_q     <= 1'b0;
        end else if (halt_pending) begin
            req_pending    <= 1'b0;
            if_valid_q     <= 1'b0;
        end else if (resp_fire) begin
            if_valid_q      <= 1'b1;
            if_pc_q         <= req_addr;
            if_insn_q       <= ic_resp_data;
            if_pred_npc_q   <= bp_npc;
            if_pred_valid_q <= bp_hit;
            pc              <= {bp_npc[31:2], 2'b00};
            req_addr        <= {bp_npc[31:2], 2'b00};
            req_pending     <= 1'b1;
        end else if (req_fire) begin
            req_pending <= 1'b0;
        end else if (if_valid_q && if_ready) begin
            if_valid_q <= 1'b0;
        end else if (!req_pending && !if_valid_q) begin
            req_pending <= 1'b1;
            req_addr    <= {pc[31:2], 2'b00};
        end
    end

endmodule
