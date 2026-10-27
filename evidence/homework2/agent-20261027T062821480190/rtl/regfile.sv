module regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        we,
    input  logic [4:0]  waddr,
    input  logic [31:0] wdata,
    input  logic [4:0]  raddr1,
    output logic [31:0] rdata1,
    input  logic [4:0]  raddr2,
    output logic [31:0] rdata2,
    input  logic [4:0]  dbg_addr,
    output logic [31:0] dbg_data,
    output logic [31:0] x10_data
);

    logic [31:0] regs [1:31];

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 1; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
        end else if (we && (waddr != 5'd0)) begin
            regs[waddr] <= wdata;
        end
    end

    logic wr_en;
    assign wr_en = we && (waddr != 5'd0);

    always_comb begin
        if (raddr1 == 5'd0) begin
            rdata1 = 32'b0;
        end else if (wr_en && (waddr == raddr1)) begin
            rdata1 = wdata;
        end else begin
            rdata1 = regs[raddr1];
        end
    end

    always_comb begin
        if (raddr2 == 5'd0) begin
            rdata2 = 32'b0;
        end else if (wr_en && (waddr == raddr2)) begin
            rdata2 = wdata;
        end else begin
            rdata2 = regs[raddr2];
        end
    end

    always_comb begin
        if (dbg_addr == 5'd0) begin
            dbg_data = 32'b0;
        end else if (wr_en && (waddr == dbg_addr)) begin
            dbg_data = wdata;
        end else begin
            dbg_data = regs[dbg_addr];
        end
    end

    always_comb begin
        if (wr_en && (waddr == 5'd10)) begin
            x10_data = wdata;
        end else begin
            x10_data = regs[10];
        end
    end

endmodule
