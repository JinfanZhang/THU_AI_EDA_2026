module regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [4:0]  rs1_addr,
    output logic [31:0] rs1_data,
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs2_data,
    input  logic [4:0]  dbg_addr,
    output logic [31:0] dbg_data,
    output logic [31:0] x10_data,
    input  logic        we,
    input  logic [4:0]  waddr,
    input  logic [31:0] wdata
);

    logic [31:0] regs [0:31];

    integer i;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'd0;
            end
        end else if (we && (waddr != 5'd0)) begin
            regs[waddr] <= wdata;
        end
    end

    // Combinational read of the register addressed by rs1_addr. x0 reads 0.
    // Write-first bypass: a same-cycle commit to the addressed register is
    // visible immediately so a consumer in ID sees the fresh value.
    always_comb begin
        if (rs1_addr == 5'd0) begin
            rs1_data = 32'd0;
        end else if (we && (waddr != 5'd0) && (waddr == rs1_addr)) begin
            rs1_data = wdata;
        end else begin
            rs1_data = regs[rs1_addr];
        end
    end

    // Combinational read of the register addressed by rs2_addr. This is the
    // architectural second read port; it must mirror rs1_data exactly.
    always_comb begin
        if (rs2_addr == 5'd0) begin
            rs2_data = 32'd0;
        end else if (we && (waddr != 5'd0) && (waddr == rs2_addr)) begin
            rs2_data = wdata;
        end else begin
            rs2_data = regs[rs2_addr];
        end
    end

    // Debug read: current architectural value, x0 hardwired to 0, with the
    // same write-first bypass so a just-committed value is observable.
    always_comb begin
        if (dbg_addr == 5'd0) begin
            dbg_data = 32'd0;
        end else if (we && (waddr != 5'd0) && (waddr == dbg_addr)) begin
            dbg_data = wdata;
        end else begin
            dbg_data = regs[dbg_addr];
        end
    end

    always_comb begin
        if (we && (waddr != 5'd0) && (waddr == 5'd10)) begin
            x10_data = wdata;
        end else begin
            x10_data = regs[10];
        end
    end

endmodule
