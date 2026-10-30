// rtl/wb_stage.sv
module wb_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem_wb_valid,
    input  logic [31:0] mem_wb_pc,
    input  logic [31:0] mem_wb_insn,
    input  logic [31:0] mem_wb_pc_plus4,
    input  logic [31:0] mem_wb_alu_result,
    input  logic [31:0] mem_wb_load_data,
    input  logic [4:0]  mem_wb_rd_addr,
    input  logic        mem_wb_reg_write,
    input  logic        mem_wb_ecall,
    input  logic [1:0]  mem_wb_epoch,
    output logic        regfile_write_en,
    output logic [4:0]  regfile_write_addr,
    output logic [31:0] regfile_write_data,
    output logic        mem_wb_valid_out,
    output logic        mem_wb_reg_write_out,
    output logic [4:0]  mem_wb_rd_addr_out,
    output logic [31:0] mem_wb_wb_data_out,
    output logic        dbg_retire_valid,
    output logic [31:0] dbg_retire_pc,
    output logic [31:0] dbg_retire_insn,
    output logic        halted,
    output logic [31:0] exit_code
);

    // Writeback data selection
    logic [31:0] wb_data;
    logic        is_load;
    logic [6:0]  opcode;
    logic [2:0]  funct3;

    // Commit-edge detection
    logic        mem_wb_valid_r;
    logic        commit_pulse;

    assign opcode  = mem_wb_insn[6:0];
    assign funct3  = mem_wb_insn[14:12];
    assign is_load = (opcode == 7'b0000011);

    always_comb begin
        if (is_load) begin
            case (funct3)
                3'b000:  wb_data = {{24{mem_wb_load_data[7]}},  mem_wb_load_data[7:0]};   // LB
                3'b001:  wb_data = {{16{mem_wb_load_data[15]}}, mem_wb_load_data[15:0]};  // LH
                3'b010:  wb_data = mem_wb_load_data;                                      // LW
                3'b100:  wb_data = {24'b0, mem_wb_load_data[7:0]};                        // LBU
                3'b101:  wb_data = {16'b0, mem_wb_load_data[15:0]};                       // LHU
                default: wb_data = mem_wb_load_data;
            endcase
        end else begin
            wb_data = mem_wb_alu_result;
        end
    end

    // Track previous MEM/WB valid to detect the architectural commit edge.
    // A valid instruction commits only on the 0 -> 1 transition of mem_wb_valid.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_wb_valid_r <= 1'b0;
        end else begin
            mem_wb_valid_r <= mem_wb_valid;
        end
    end

    assign commit_pulse = mem_wb_valid && !mem_wb_valid_r && !halted;

    // Register file write
    assign regfile_write_en   = mem_wb_valid && mem_wb_reg_write && (mem_wb_rd_addr != 5'b0) && !halted;
    assign regfile_write_addr = mem_wb_rd_addr;
    assign regfile_write_data = wb_data;

    // Pass-through outputs
    assign mem_wb_valid_out      = mem_wb_valid;
    assign mem_wb_reg_write_out  = mem_wb_reg_write;
    assign mem_wb_rd_addr_out    = mem_wb_rd_addr;
    assign mem_wb_wb_data_out    = wb_data;

    // Debug retire: single-cycle pulse on the commit edge only.
    assign dbg_retire_valid = commit_pulse;
    assign dbg_retire_pc    = mem_wb_pc;
    assign dbg_retire_insn  = mem_wb_insn;

    // Halt and exit code
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halted    <= 1'b0;
            exit_code <= 32'b0;
        end else if (!halted && mem_wb_valid && mem_wb_ecall) begin
            halted    <= 1'b1;
            exit_code <= regfile_write_data;
        end
    end

endmodule
