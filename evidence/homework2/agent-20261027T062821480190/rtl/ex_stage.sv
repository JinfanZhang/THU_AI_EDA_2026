module ex_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush,
    input  logic        id_ex_valid,
    input  logic [31:0] id_ex_pc,
    input  logic [31:0] id_ex_pc4,
    input  logic [4:0]  id_ex_rs1,
    input  logic [4:0]  id_ex_rs2,
    input  logic [4:0]  id_ex_rd,
    input  logic [31:0] id_ex_rs1_data,
    input  logic [31:0] id_ex_rs2_data,
    input  logic [31:0] id_ex_imm,
    input  logic [3:0]  id_ex_alu_op,
    input  logic [1:0]  id_ex_alu_a_sel,
    input  logic [1:0]  id_ex_alu_b_sel,
    input  logic        id_ex_is_branch,
    input  logic [2:0]  id_ex_branch_f3,
    input  logic        id_ex_is_jal,
    input  logic        id_ex_is_jalr,
    input  logic        id_ex_is_load,
    input  logic        id_ex_is_store,
    input  logic [2:0]  id_ex_mem_f3,
    input  logic        id_ex_reg_write,
    input  logic        id_ex_is_ecall,
    input  logic [1:0]  fwd_a,
    input  logic [1:0]  fwd_b,
    input  logic [31:0] fwd_ex_mem_data,
    input  logic [31:0] fwd_mem_wb_data,
    output logic        redirect,
    output logic [31:0] redirect_pc,
    output logic        ex_mem_valid,
    output logic [31:0] ex_mem_result,
    output logic [31:0] ex_mem_store_data,
    output logic [4:0]  ex_mem_rs2,
    output logic [4:0]  ex_mem_rd,
    output logic        ex_mem_is_load,
    output logic        ex_mem_is_store,
    output logic [2:0]  ex_mem_mem_f3,
    output logic        ex_mem_reg_write,
    output logic        ex_mem_is_ecall
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

    logic [31:0] rs1_fwd;
    logic [31:0] rs2_fwd;
    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [31:0] alu_y;
    logic        branch_taken;
    logic        jump_taken;
    logic [31:0] branch_target;
    logic [31:0] jalr_target;
    logic [31:0] link_value;
    logic [31:0] result_next;

    always_comb begin
        rs1_fwd = id_ex_rs1_data;
        if (fwd_a == 2'b10) begin
            rs1_fwd = fwd_ex_mem_data;
        end else if (fwd_a == 2'b01) begin
            rs1_fwd = fwd_mem_wb_data;
        end

        rs2_fwd = id_ex_rs2_data;
        if (fwd_b == 2'b10) begin
            rs2_fwd = fwd_ex_mem_data;
        end else if (fwd_b == 2'b01) begin
            rs2_fwd = fwd_mem_wb_data;
        end
    end

    always_comb begin
        alu_a = rs1_fwd;
        if (id_ex_alu_a_sel == 2'b01) begin
            alu_a = id_ex_pc;
        end else if (id_ex_alu_a_sel == 2'b10) begin
            alu_a = 32'b0;
        end

        alu_b = rs2_fwd;
        if (id_ex_alu_b_sel == 2'b01) begin
            alu_b = id_ex_imm;
        end
    end

    always_comb begin
        alu_y = 32'b0;
        case (id_ex_alu_op)
            ALU_ADD:  alu_y = alu_a + alu_b;
            ALU_SUB:  alu_y = alu_a - alu_b;
            ALU_SLL:  alu_y = alu_a << alu_b[4:0];
            ALU_SLT:  alu_y = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_y = (alu_a < alu_b) ? 32'd1 : 32'd0;
            ALU_XOR:  alu_y = alu_a ^ alu_b;
            ALU_SRL:  alu_y = alu_a >> alu_b[4:0];
            ALU_SRA:  alu_y = $signed(alu_a) >>> alu_b[4:0];
            ALU_OR:   alu_y = alu_a | alu_b;
            ALU_AND:  alu_y = alu_a & alu_b;
            default:  alu_y = 32'b0;
        endcase
    end

    always_comb begin
        branch_taken = 1'b0;
        if (id_ex_is_branch) begin
            case (id_ex_branch_f3)
                3'b000: branch_taken = (rs1_fwd == rs2_fwd);
                3'b001: branch_taken = (rs1_fwd != rs2_fwd);
                3'b100: branch_taken = ($signed(rs1_fwd) < $signed(rs2_fwd));
                3'b101: branch_taken = ($signed(rs1_fwd) >= $signed(rs2_fwd));
                3'b110: branch_taken = (rs1_fwd < rs2_fwd);
                3'b111: branch_taken = (rs1_fwd >= rs2_fwd);
                default: branch_taken = 1'b0;
            endcase
        end
    end

    always_comb begin
        branch_target = id_ex_pc + id_ex_imm;
        jalr_target   = (rs1_fwd + id_ex_imm) & 32'hFFFF_FFFE;
        link_value    = id_ex_pc4;

        jump_taken = id_ex_is_jal | id_ex_is_jalr;

        redirect    = id_ex_valid & (branch_taken | jump_taken);
        redirect_pc = 32'b0;
        if (id_ex_is_jalr) begin
            redirect_pc = jalr_target;
        end else if (id_ex_is_jal) begin
            redirect_pc = branch_target;
        end else if (branch_taken) begin
            redirect_pc = branch_target;
        end
    end

    always_comb begin
        if (id_ex_is_jal | id_ex_is_jalr) begin
            result_next = link_value;
        end else begin
            result_next = alu_y;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ex_mem_valid      <= 1'b0;
            ex_mem_result     <= 32'b0;
            ex_mem_store_data <= 32'b0;
            ex_mem_rs2        <= 5'b0;
            ex_mem_rd         <= 5'b0;
            ex_mem_is_load    <= 1'b0;
            ex_mem_is_store   <= 1'b0;
            ex_mem_mem_f3     <= 3'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_is_ecall   <= 1'b0;
        end else if (flush) begin
            ex_mem_valid      <= 1'b0;
            ex_mem_result     <= 32'b0;
            ex_mem_store_data <= 32'b0;
            ex_mem_rs2        <= 5'b0;
            ex_mem_rd         <= 5'b0;
            ex_mem_is_load    <= 1'b0;
            ex_mem_is_store   <= 1'b0;
            ex_mem_mem_f3     <= 3'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_is_ecall   <= 1'b0;
        end else begin
            ex_mem_valid      <= id_ex_valid;
            ex_mem_result     <= result_next;
            ex_mem_store_data <= rs2_fwd;
            ex_mem_rs2        <= id_ex_rs2;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_is_load    <= id_ex_is_load;
            ex_mem_is_store   <= id_ex_is_store;
            ex_mem_mem_f3     <= id_ex_mem_f3;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_is_ecall   <= id_ex_is_ecall;
        end
    end

endmodule
