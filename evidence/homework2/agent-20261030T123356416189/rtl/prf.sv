module prf (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [5:0]  raddr1,
    output logic [31:0] rdata1,
    input  logic [5:0]  raddr2,
    output logic [31:0] rdata2,
    input  logic [5:0]  raddr3,
    output logic [31:0] rdata3,
    input  logic [5:0]  raddr4,
    output logic [31:0] rdata4,
    input  logic [5:0]  dbg_addr,
    output logic [31:0] dbg_data,
    input  logic        we,
    input  logic [5:0]  waddr,
    input  logic [31:0] wdata
);

    logic [31:0] regs [0:39];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 40; i++) begin
                regs[i] <= 32'b0;
            end
        end else if (we && (waddr != 6'd0)) begin
            regs[waddr] <= wdata;
        end
    end

    assign rdata1   = (raddr1   == 6'd0) ? 32'b0 : regs[raddr1];
    assign rdata2   = (raddr2   == 6'd0) ? 32'b0 : regs[raddr2];
    assign rdata3   = (raddr3   == 6'd0) ? 32'b0 : regs[raddr3];
    assign rdata4   = (raddr4   == 6'd0) ? 32'b0 : regs[raddr4];
    assign dbg_data = (dbg_addr == 6'd0) ? 32'b0 : regs[dbg_addr];

endmodule
