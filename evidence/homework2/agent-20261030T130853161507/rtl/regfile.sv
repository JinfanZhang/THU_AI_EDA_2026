module regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        write_en,
    input  logic [4:0]  write_addr,
    input  logic [31:0] write_data,
    input  logic [4:0]  read_addr1,
    input  logic [4:0]  read_addr2,
    input  logic [4:0]  dbg_reg_addr,
    output logic [31:0] read_data1,
    output logic [31:0] read_data2,
    output logic [31:0] dbg_reg_data
);

    logic [31:0] regs [32];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) begin
                regs[i] <= 32'h0;
            end
        end else if (write_en && write_addr != 5'h0) begin
            regs[write_addr] <= write_data;
        end
    end

    always_comb begin
        if (read_addr1 == 5'h0)
            read_data1 = 32'h0;
        else if (write_en && write_addr == read_addr1)
            read_data1 = write_data;
        else
            read_data1 = regs[read_addr1];
    end

    always_comb begin
        if (read_addr2 == 5'h0)
            read_data2 = 32'h0;
        else if (write_en && write_addr == read_addr2)
            read_data2 = write_data;
        else
            read_data2 = regs[read_addr2];
    end

    always_comb begin
        if (dbg_reg_addr == 5'h0)
            dbg_reg_data = 32'h0;
        else
            dbg_reg_data = regs[dbg_reg_addr];
    end

endmodule
