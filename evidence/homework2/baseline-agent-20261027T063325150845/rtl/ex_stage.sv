module ex_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [1:0]  fwd_a_sel,
    input  logic [1:0]  fwd_b_sel,
    input  logic [31:0] wb_data,
    input  logic        id_ex_valid,
    input  logic [31:0] id_ex_pc,
    input  logic [31:0] id_ex_pc4,
    input  logic [31:0] id_ex_instr,
    input  logic [31:0] id_ex_rs1_data,
    input  logic [31:0] id_ex_rs2_data,
    input  logic [4:0]  id_ex_rs1,
    input  logic [4:0]  id_ex_rs2,
    input  logic [4:0]  id_ex_rd,
    input  logic [31:0] id_ex_imm,
    input  logic [3:0]  id_ex_alu_op,
    input  logic [1:0]  id_ex_alu_a_sel,
    input  logic        id_ex_alu_b_sel,
    input  logic        id_ex_reg_write,
    input  logic        id_ex_mem_read,
    input  logic        id_ex_mem_write,
    input  logic [2:0]  id_ex_mem_size,
    input  logic [1:0]  id_ex_wb_sel,
    input  logic [3:0]  id_ex_branch,
    input  logic [1:0]  id_ex_jump,
    input  logic        id_ex_is_ecall,
    output logic        ex_mem_valid,
    output logic [31:0] ex_mem_pc4,
    output logic [4:0]  ex_mem_rd,
    output logic [31:0] ex_mem_alu_result,
    output logic [31:0] ex_mem_rs2_data,
    output logic [4:0]  ex_mem_rs2,
    output logic        ex_mem_reg_write,
    output logic        ex_mem_mem_read,
    output logic        ex_mem_mem_write,
    output logic [2:0]  ex_mem_mem_size,
    output logic [1:0]  ex_mem_wb_sel,
    output logic        ex_mem_is_ecall,
    output logic        redirect,
    output logic [31:0] redirect_target
);

    localparam logic [3:0] ALU_ADD  = 4'd0;
    localparam logic [3:0] ALU_SUB  = 4'd1;
    localparam logic [3:0] ALU_SLL  = 4'd2;
    localparam logic [3:0] ALU_SLT  = 4'd3;
    localparam logic [3:0] ALU_SLTU = 4'd4;
    localparam logic [3:0] ALU_XOR  = 4'd5;
    localparam logic [3:0] ALU_SRL  = 4'd6;
    localparam logic [3:0] ALU_SRA  = 4'd7;
    localparam logic [3:0] ALU_OR   = 4'd8;
    localparam logic [3:0] ALU_AND  = 4'd9;

    localparam logic [1:0] A_RS1  = 2'd0;
    localparam logic [1:0] A_PC   = 2'd1;
    localparam logic [1:0] A_ZERO = 2'd2;

    localparam logic [3:0] BR_NONE = 4'd0;
    localparam logic [3:0] BR_BEQ  = 4'd1;
    localparam logic [3:0] BR_BNE  = 4'd2;
    localparam logic [3:0] BR_BLT  = 4'd3;
    localparam logic [3:0] BR_BGE  = 4'd4;
    localparam logic [3:0] BR_BLTU = 4'd5;
    localparam logic [3:0] BR_BGEU = 4'd6;

    localparam logic [1:0] JMP_NONE = 2'd0;
    localparam logic [1:0] JMP_JAL  = 2'd1;
    localparam logic [1:0] JMP_JALR = 2'd2;

    localparam logic [1:0] WB_ALU  = 2'd0;
    localparam logic [1:0] WB_LOAD = 2'd1;
    localparam logic [1:0] WB_PC4  = 2'd2;

    logic [31:0] rs1_fwd;
    logic [31:0] rs2_fwd;
    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [31:0] alu_result;
    logic [31:0] jump_target;
    logic        branch_taken;
    logic        jump_taken;
    logic        redirect_comb;
    logic [31:0] redirect_target_comb;
    logic [31:0] ex_result;

    always_comb begin
        rs1_fwd = id_ex_rs1_data;
        if (fwd_a_sel == 2'b10)
            rs1_fwd = ex_mem_alu_result;
        else if (fwd_a_sel == 2'b01)
            rs1_fwd = wb_data;

        rs2_fwd = id_ex_rs2_data;
        if (fwd_b_sel == 2'b10)
            rs2_fwd = ex_mem_alu_result;
        else if (fwd_b_sel == 2'b01)
            rs2_fwd = wb_data;
    end

    always_comb begin
        case (id_ex_alu_a_sel)
            A_PC:    alu_a = id_ex_pc;
            A_ZERO:  alu_a = 32'd0;
            default: alu_a = rs1_fwd;
        endcase
        alu_b = id_ex_alu_b_sel ? id_ex_imm : rs2_fwd;
    end

    always_comb begin
        case (id_ex_alu_op)
            ALU_ADD:  alu_result = alu_a + alu_b;
            ALU_SUB:  alu_result = alu_a - alu_b;
            ALU_SLL:  alu_result = alu_a << alu_b[4:0];
            ALU_SLT:  alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;
            ALU_XOR:  alu_result = alu_a ^ alu_b;
            ALU_SRL:  alu_result = alu_a >> alu_b[4:0];
            ALU_SRA:  alu_result = $signed(alu_a) >>> alu_b[4:0];
            ALU_OR:   alu_result = alu_a | alu_b;
            ALU_AND:  alu_result = alu_a & alu_b;
            default:  alu_result = 32'd0;
        endcase
    end

    always_comb begin
        branch_taken = 1'b0;
        if (id_ex_valid) begin
            case (id_ex_branch)
                BR_BEQ:  branch_taken = (rs1_fwd == rs2_fwd);
                BR_BNE:  branch_taken = (rs1_fwd != rs2_fwd);
                BR_BLT:  branch_taken = ($signed(rs1_fwd) < $signed(rs2_fwd));
                BR_BGE:  branch_taken = ($signed(rs1_fwd) >= $signed(rs2_fwd));
                BR_BLTU: branch_taken = (rs1_fwd < rs2_fwd);
                BR_BGEU: branch_taken = (rs1_fwd >= rs2_fwd);
                default: branch_taken = 1'b0;
            endcase
        end
    end

    always_comb begin
        jump_taken = 1'b0;
        jump_target = 32'd0;
        if (id_ex_valid) begin
            case (id_ex_jump)
                JMP_JAL: begin
                    jump_taken = 1'b1;
                    jump_target = id_ex_pc + id_ex_imm;
                end
                JMP_JALR: begin
                    jump_taken = 1'b1;
                    jump_target = (rs1_fwd + id_ex_imm) & 32'hFFFF_FFFE;
                end
                default: begin
                    jump_taken = 1'b0;
                    jump_target = 32'd0;
                end
            endcase
        end
    end

    always_comb begin
        redirect_comb = 1'b0;
        redirect_target_comb = 32'd0;
        if (id_ex_valid) begin
            if (jump_taken) begin
                redirect_comb = 1'b1;
                redirect_target_comb = jump_target;
            end else if (branch_taken) begin
                redirect_comb = 1'b1;
                redirect_target_comb = id_ex_pc + id_ex_imm;
            end
        end
    end

    assign redirect = redirect_comb;
    assign redirect_target = redirect_target_comb;

    always_comb begin
        if (id_ex_wb_sel == WB_PC4)
            ex_result = id_ex_pc4;
        else
            ex_result = alu_result;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ex_mem_valid      <= 1'b0;
            ex_mem_pc4        <= 32'd0;
            ex_mem_rd         <= 5'd0;
            ex_mem_alu_result <= 32'd0;
            ex_mem_rs2_data   <= 32'd0;
            ex_mem_rs2        <= 5'd0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_mem_size   <= 3'd0;
            ex_mem_wb_sel     <= 2'd0;
            ex_mem_is_ecall   <= 1'b0;
        end else begin
            ex_mem_valid      <= id_ex_valid;
            ex_mem_pc4        <= id_ex_pc4;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_alu_result <= ex_result;
            ex_mem_rs2_data   <= rs2_fwd;
            ex_mem_rs2        <= id_ex_rs2;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_mem_size   <= id_ex_mem_size;
            ex_mem_wb_sel     <= id_ex_wb_sel;
            ex_mem_is_ecall   <= id_ex_is_ecall;
        end
    end

endmodule
