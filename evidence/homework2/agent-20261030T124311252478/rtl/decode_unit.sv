module decode_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        fetch_valid,
    input  logic [31:0] fetch_pc,
    input  logic [31:0] fetch_insn,
    output logic        dec_valid,
    output logic [31:0] dec_pc,
    output logic [31:0] dec_insn,
    output logic [4:0]  dec_rs1,
    output logic [4:0]  dec_rs2,
    output logic [4:0]  dec_rd,
    output logic [31:0] dec_imm,
    output logic [3:0]  dec_op_type,
    output logic [2:0]  dec_func3,
    output logic [6:0]  dec_func7,
    input  logic        ren_ready
);

    // Opcode fields
    logic [6:0] opcode;
    logic [2:0] func3;
    logic [6:0] func7;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;

    assign opcode = fetch_insn[6:0];
    assign func3  = fetch_insn[14:12];
    assign func7  = fetch_insn[31:25];
    assign rs1    = fetch_insn[19:15];
    assign rs2    = fetch_insn[24:20];
    assign rd     = fetch_insn[11:7];

    // Immediate generation
    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    assign imm_i = {{20{fetch_insn[31]}}, fetch_insn[31:20]};
    assign imm_s = {{20{fetch_insn[31]}}, fetch_insn[31:25], fetch_insn[11:7]};
    assign imm_b = {{19{fetch_insn[31]}}, fetch_insn[31], fetch_insn[7], fetch_insn[30:25], fetch_insn[11:8], 1'b0};
    assign imm_u = {fetch_insn[31:12], 12'b0};
    assign imm_j = {{11{fetch_insn[31]}}, fetch_insn[31], fetch_insn[19:12], fetch_insn[20], fetch_insn[30:21], 1'b0};

    // Op type encoding
    // 4'b0000: ALU R-type
    // 4'b0001: ALU I-type
    // 4'b0010: Load
    // 4'b0011: Store
    // 4'b0100: Branch
    // 4'b0101: JAL
    // 4'b0110: JALR
    // 4'b0111: LUI
    // 4'b1000: AUIPC
    // 4'b1001: ECALL
    // 4'b1010: NOP/unsupported
    logic [3:0] op_type_comb;
    logic [31:0] imm_comb;

    always_comb begin
        op_type_comb = 4'b1010;
        imm_comb = 32'b0;
        case (opcode)
            7'b0110011: begin
                op_type_comb = 4'b0000;
                imm_comb = 32'b0;
            end
            7'b0010011: begin
                op_type_comb = 4'b0001;
                imm_comb = imm_i;
            end
            7'b0000011: begin
                op_type_comb = 4'b0010;
                imm_comb = imm_i;
            end
            7'b0100011: begin
                op_type_comb = 4'b0011;
                imm_comb = imm_s;
            end
            7'b1100011: begin
                op_type_comb = 4'b0100;
                imm_comb = imm_b;
            end
            7'b1101111: begin
                op_type_comb = 4'b0101;
                imm_comb = imm_j;
            end
            7'b1100111: begin
                op_type_comb = 4'b0110;
                imm_comb = imm_i;
            end
            7'b0110111: begin
                op_type_comb = 4'b0111;
                imm_comb = imm_u;
            end
            7'b0010111: begin
                op_type_comb = 4'b1000;
                imm_comb = imm_u;
            end
            7'b1110011: begin
                if (fetch_insn == 32'h0000_0073)
                    op_type_comb = 4'b1001;
                else
                    op_type_comb = 4'b1010;
                imm_comb = 32'b0;
            end
            default: begin
                op_type_comb = 4'b1010;
                imm_comb = 32'b0;
            end
        endcase
    end

    // Pipeline register
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            dec_valid   <= 1'b0;
            dec_pc      <= 32'b0;
            dec_insn    <= 32'b0;
            dec_rs1     <= 5'b0;
            dec_rs2     <= 5'b0;
            dec_rd      <= 5'b0;
            dec_imm     <= 32'b0;
            dec_op_type <= 4'b1010;
            dec_func3   <= 3'b0;
            dec_func7   <= 7'b0;
        end else begin
            if (ren_ready) begin
                dec_valid   <= fetch_valid;
                dec_pc      <= fetch_pc;
                dec_insn    <= fetch_insn;
                dec_rs1     <= rs1;
                dec_rs2     <= rs2;
                dec_rd      <= rd;
                dec_imm     <= imm_comb;
                dec_op_type <= op_type_comb;
                dec_func3   <= func3;
                dec_func7   <= func7;
            end else begin
                dec_valid   <= dec_valid;
                dec_pc      <= dec_pc;
                dec_insn    <= dec_insn;
                dec_rs1     <= dec_rs1;
                dec_rs2     <= dec_rs2;
                dec_rd      <= dec_rd;
                dec_imm     <= dec_imm;
                dec_op_type <= dec_op_type;
                dec_func3   <= dec_func3;
                dec_func7   <= dec_func7;
            end
        end
    end

endmodule
