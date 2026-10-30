module wb_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem2wb_valid,
    input  logic [31:0] mem2wb_pc,
    input  logic [31:0] mem2wb_insn,
    input  logic [31:0] mem2wb_wdata,
    input  logic [4:0]  mem2wb_rd,
    input  logic        mem2wb_reg_write,
    input  logic        mem2wb_is_ecall,
    input  logic [31:0] reg_x10,
    output logic        wb_reg_write,
    output logic [4:0]  wb_rd,
    output logic [31:0] wb_data,
    output logic        halted,
    output logic [31:0] exit_code,
    output logic        dbg_retire_valid,
    output logic [31:0] dbg_retire_pc,
    output logic [31:0] dbg_retire_insn
);

    logic        halted_q;
    logic [31:0] exit_code_q;

    // A committed ECALL is the exact instruction word 32'h0000_0073 that is
    // valid in MEM/WB.  Gate on both the carried flag and the instruction
    // word so a bubble or a mis-carried flag can never halt the CPU.
    logic ecall_commit;
    assign ecall_commit = mem2wb_valid && mem2wb_is_ecall &&
                          (mem2wb_insn == 32'h0000_0073) && !halted_q;

    assign wb_reg_write = mem2wb_valid && mem2wb_reg_write && (mem2wb_rd != 5'd0) && !halted_q;
    assign wb_rd        = mem2wb_rd;
    assign wb_data      = mem2wb_wdata;

    // Retirement reports the PC and instruction word carried by MEM/WB,
    // i.e. the PC of the instruction being retired (not pc+4).  The ECALL
    // itself retires (one pulse) and then halted freezes further pulses.
    assign dbg_retire_valid = mem2wb_valid && !halted_q;
    assign dbg_retire_pc    = mem2wb_pc;
    assign dbg_retire_insn  = mem2wb_insn;

    assign halted    = halted_q;
    assign exit_code = exit_code_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halted_q    <= 1'b0;
            exit_code_q <= 32'd0;
        end else if (!halted_q) begin
            if (ecall_commit) begin
                halted_q    <= 1'b1;
                exit_code_q <= reg_x10;
            end
        end
    end

endmodule
