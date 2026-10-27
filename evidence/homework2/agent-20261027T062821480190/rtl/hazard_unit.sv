module hazard_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        redirect,
    input  logic        halted,
    input  logic        id_is_ecall,
    input  logic        ifid_valid,
    input  logic [31:0] ifid_instr,
    input  logic        id_ex_valid,
    input  logic        id_ex_is_load,
    input  logic [4:0]  id_ex_rd,
    output logic        halt_pending,
    output logic        stall_load_use,
    output logic        flush_ifid,
    output logic        flush_idex
);

    logic [6:0] ifid_opcode;
    logic [4:0] ifid_rs1;
    logic [4:0] ifid_rs2;

    assign ifid_opcode = ifid_instr[6:0];
    assign ifid_rs1    = ifid_instr[19:15];
    assign ifid_rs2    = ifid_instr[24:20];

    // Which source registers does the ID-stage instruction actually read?
    logic uses_rs1;
    logic uses_rs2;

    always_comb begin
        uses_rs1 = 1'b0;
        uses_rs2 = 1'b0;
        case (ifid_opcode)
            7'b0110011: begin // OP
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
            end
            7'b0010011: begin // OP-IMM
                uses_rs1 = 1'b1;
            end
            7'b0000011: begin // LOAD
                uses_rs1 = 1'b1;
            end
            7'b0100011: begin // STORE
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
            end
            7'b1100011: begin // BRANCH
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
            end
            7'b1100111: begin // JALR
                uses_rs1 = 1'b1;
            end
            default: begin
                uses_rs1 = 1'b0;
                uses_rs2 = 1'b0;
            end
        endcase
    end

    logic load_use_raw;

    always_comb begin
        load_use_raw = 1'b0;
        if (ifid_valid && id_ex_valid && id_ex_is_load && (id_ex_rd != 5'd0)) begin
            if (uses_rs1 && (ifid_rs1 != 5'd0) && (id_ex_rd == ifid_rs1))
                load_use_raw = 1'b1;
            else if (uses_rs2 && (ifid_rs2 != 5'd0) && (id_ex_rd == ifid_rs2))
                load_use_raw = 1'b1;
        end
    end

    // Control redirect has priority over load-use stall.
    assign stall_load_use = load_use_raw && !redirect && !halted && !halt_pending;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            halt_pending <= 1'b0;
        end else if (id_is_ecall && !redirect) begin
            halt_pending <= 1'b1;
        end
    end

    // Stall must NOT clear IF/ID: the stalled instruction stays resident.
    assign flush_ifid = redirect | halt_pending | halted | (id_is_ecall & ~redirect);
    // Stall injects exactly one bubble into EX by clearing ID/EX valid.
    assign flush_idex = redirect | halted | halt_pending | stall_load_use;

endmodule
