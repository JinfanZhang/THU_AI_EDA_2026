module ex_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        id_ex_valid,
    input  logic [31:0] id_ex_pc,
    input  logic [31:0] id_ex_pc_plus4,
    input  logic [31:0] id_ex_rs1_data,
    input  logic [31:0] id_ex_rs2_data,
    input  logic [4:0]  id_ex_rs1_addr,
    input  logic [4:0]  id_ex_rs2_addr,
    input  logic [4:0]  id_ex_rd_addr,
    input  logic [31:0] id_ex_imm,
    input  logic [3:0]  id_ex_alu_op,
    input  logic [1:0]  id_ex_alu_a_sel,
    input  logic        id_ex_alu_b_sel,
    input  logic [2:0]  id_ex_branch,
    input  logic [1:0]  id_ex_jump,
    input  logic [1:0]  id_ex_wb_sel,
    input  logic        id_ex_reg_write,
    input  logic        id_ex_mem_read,
    input  logic        id_ex_mem_write,
    input  logic [1:0]  id_ex_mem_size,
    input  logic        id_ex_mem_unsigned,
    input  logic        id_ex_ecall,
    input  logic [1:0]  forward_a,
    input  logic [1:0]  forward_b,
    input  logic [31:0] mem_wb_wb_data,
    output logic        ex_redirect,
    output logic [31:0] ex_redirect_pc,
    output logic        ex_mem_valid,
    output logic [31:0] ex_mem_pc,
    output logic [31:0] ex_mem_alu_result,
    output logic [31:0] ex_mem_wb_data,
    output logic [31:0] ex_mem_store_data,
    output logic [4:0]  ex_mem_rd_addr,
    output logic [4:0]  ex_mem_rs2_addr,
    output logic        ex_mem_reg_write,
    output logic        ex_mem_mem_read,
    output logic        ex_mem_mem_write,
    output logic [1:0]  ex_mem_mem_size,
    output logic        ex_mem_mem_unsigned,
    output logic        ex_mem_ecall
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

    localparam logic [1:0] A_SEL_RS1 = 2'd0;
    localparam logic [1:0] A_SEL_PC  = 2'd1;
    localparam logic [1:0] A_SEL_ZERO= 2'd2;

    localparam logic [2:0] BR_NONE = 3'd0;
    localparam logic [2:0] BR_BEQ  = 3'd1;
    localparam logic [2:0] BR_BNE  = 3'd2;
    localparam logic [2:0] BR_BLT  = 3'd3;
    localparam logic [2:0] BR_BGE  = 3'd4;
    localparam logic [2:0] BR_BLTU = 3'd5;
    localparam logic [2:0] BR_BGEU = 3'd6;

    localparam logic [1:0] JUMP_NONE = 2'd0;
    localparam logic [1:0] JUMP_JAL  = 2'd1;
    localparam logic [1:0] JUMP_JALR = 2'd2;

    localparam logic [1:0] WB_ALU  = 2'd0;
    localparam logic [1:0] WB_PC4  = 2'd1;
    localparam logic [1:0] WB_MEM  = 2'd2;
    localparam logic [1:0] WB_PC   = 2'd3;

    logic [31:0] rs1_fwd;
    logic [31:0] rs2_fwd;
    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [31:0] alu_result;
    logic [31:0] pc_target;
    logic        branch_taken;
    logic        jump_taken;
    logic        redirect;
    logic [31:0] redirect_pc;
    logic [31:0] wb_data;

    // Forwarding: EX/MEM (forward==2'd1) has priority over MEM/WB (forward==2'd2).
    // The forwarding mux is applied to the rs2 value BEFORE the alu_b_sel
    // immediate substitution so that register-operand instructions consume
    // the (forwarded) rs2 and only imm-selecting instructions use id_ex_imm.
    always_comb begin
        rs1_fwd = id_ex_rs1_data;
        if (forward_a == 2'd1)
            rs1_fwd = ex_mem_wb_data;
        else if (forward_a == 2'd2)
            rs1_fwd = mem_wb_wb_data;

        rs2_fwd = id_ex_rs2_data;
        if (forward_b == 2'd1)
            rs2_fwd = ex_mem_wb_data;
        else if (forward_b == 2'd2)
            rs2_fwd = mem_wb_wb_data;
    end

    always_comb begin
        case (id_ex_alu_a_sel)
            A_SEL_PC:   alu_a = id_ex_pc;
            A_SEL_ZERO: alu_a = 32'd0;
            default:    alu_a = rs1_fwd;
        endcase
        // id_ex_alu_b_sel: 1 = use immediate, 0 = use (forwarded) rs2
        alu_b = id_ex_alu_b_sel ? id_ex_imm : rs2_fwd;
    end

    always_comb begin
        case (id_ex_alu_op)
            ALU_SUB:  alu_result = alu_a - alu_b;
            ALU_SLL:  alu_result = alu_a << alu_b[4:0];
            ALU_SLT:  alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;
            ALU_XOR:  alu_result = alu_a ^ alu_b;
            ALU_SRL:  alu_result = alu_a >> alu_b[4:0];
            ALU_SRA:  alu_result = $signed(alu_a) >>> alu_b[4:0];
            ALU_OR:   alu_result = alu_a | alu_b;
            ALU_AND:  alu_result = alu_a & alu_b;
            default:  alu_result = alu_a + alu_b;
        endcase
    end

    always_comb begin
        branch_taken = 1'b0;
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

    always_comb begin
        jump_taken = (id_ex_jump == JUMP_JAL) || (id_ex_jump == JUMP_JALR);
        if (id_ex_jump == JUMP_JALR)
            pc_target = (rs1_fwd + id_ex_imm) & 32'hFFFF_FFFE;
        else
            pc_target = id_ex_pc + id_ex_imm;
    end

    always_comb begin
        redirect = id_ex_valid && (branch_taken || jump_taken);
        redirect_pc = pc_target;
    end

    always_comb begin
        case (id_ex_wb_sel)
            WB_PC4:  wb_data = id_ex_pc_plus4;
            WB_MEM:  wb_data = alu_result;
            WB_PC:   wb_data = id_ex_pc + id_ex_imm;
            default: wb_data = alu_result;
        endcase
    end

    assign ex_redirect = redirect;
    assign ex_redirect_pc = redirect_pc;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ex_mem_valid       <= 1'b0;
            ex_mem_pc          <= 32'd0;
            ex_mem_alu_result  <= 32'd0;
            ex_mem_wb_data     <= 32'd0;
            ex_mem_store_data  <= 32'd0;
            ex_mem_rd_addr     <= 5'd0;
            ex_mem_rs2_addr    <= 5'd0;
            ex_mem_reg_write   <= 1'b0;
            ex_mem_mem_read    <= 1'b0;
            ex_mem_mem_write   <= 1'b0;
            ex_mem_mem_size    <= 2'd0;
            ex_mem_mem_unsigned<= 1'b0;
            ex_mem_ecall       <= 1'b0;
        end else begin
            ex_mem_valid       <= id_ex_valid;
            ex_mem_pc          <= id_ex_pc;
            ex_mem_alu_result  <= alu_result;
            ex_mem_wb_data     <= wb_data;
            ex_mem_store_data  <= rs2_fwd;
            ex_mem_rd_addr     <= id_ex_rd_addr;
            ex_mem_rs2_addr    <= id_ex_rs2_addr;
            ex_mem_reg_write   <= id_ex_reg_write;
            ex_mem_mem_read    <= id_ex_mem_read;
            ex_mem_mem_write   <= id_ex_mem_write;
            ex_mem_mem_size    <= id_ex_mem_size;
            ex_mem_mem_unsigned<= id_ex_mem_unsigned;
            ex_mem_ecall       <= id_ex_ecall;
        end
    end

endmodule
