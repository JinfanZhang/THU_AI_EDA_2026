module ex_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        idex_valid,
    input  logic [31:0] idex_pc,
    input  logic [31:0] idex_pc_plus4,
    input  logic [31:0] idex_rs1_data,
    input  logic [31:0] idex_rs2_data,
    input  logic [4:0]  idex_rs1_addr,
    input  logic [4:0]  idex_rs2_addr,
    input  logic [31:0] idex_imm,
    input  logic [4:0]  idex_rd_addr,
    input  logic [3:0]  idex_alu_op,
    input  logic [1:0]  idex_alu_a_sel,
    input  logic        idex_alu_b_sel,
    input  logic        idex_reg_write,
    input  logic        idex_mem_read,
    input  logic        idex_mem_write,
    input  logic [1:0]  idex_mem_size,
    input  logic        idex_mem_unsign,
    input  logic [1:0]  idex_wb_sel,
    input  logic        idex_branch,
    input  logic [2:0]  idex_branch_op,
    input  logic        idex_jump,
    input  logic        idex_jalr,
    input  logic        idex_is_ecall,
    input  logic [31:0] ex_rs1_data,
    input  logic [31:0] ex_rs2_data,
    output logic        ex_redirect,
    output logic [31:0] redirect_pc,
    input  logic        exmem_flush,
    output logic        exmem_valid,
    output logic [31:0] exmem_pc_plus4,
    output logic [31:0] exmem_alu_result,
    output logic [31:0] exmem_rs2_data,
    output logic [4:0]  exmem_rs2_addr,
    output logic [4:0]  exmem_rd_addr,
    output logic        exmem_reg_write,
    output logic        exmem_mem_read,
    output logic        exmem_mem_write,
    output logic [1:0]  exmem_mem_size,
    output logic        exmem_mem_unsign,
    output logic [1:0]  exmem_wb_sel,
    output logic        exmem_is_ecall
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

    localparam logic [1:0] WB_ALU  = 2'd0;
    localparam logic [1:0] WB_LOAD = 2'd1;
    localparam logic [1:0] WB_PC4  = 2'd2;

    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [31:0] alu_y;
    logic [31:0] alu_result;
    logic        branch_taken;
    logic        jump_taken;
    logic        redirect;
    logic [31:0] target_pc;

    // Forwarded operands are the single source of truth for EX datapath.
    // ex_rs1_data / ex_rs2_data already include EX/MEM and MEM/WB forwarding
    // (selected by forwarding_unit outside this module).
    logic [31:0] op_a;
    logic [31:0] op_b;

    assign op_a = ex_rs1_data;
    assign op_b = ex_rs2_data;

    always_comb begin
        alu_a = 32'd0;
        case (idex_alu_a_sel)
            A_SEL_RS1:  alu_a = op_a;
            A_SEL_PC:   alu_a = idex_pc;
            A_SEL_ZERO: alu_a = 32'd0;
            default:    alu_a = 32'd0;
        endcase
    end

    always_comb begin
        alu_b = idex_alu_b_sel ? idex_imm : op_b;
    end

    always_comb begin
        alu_y = 32'd0;
        case (idex_alu_op)
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
            default:  alu_y = 32'd0;
        endcase
    end

    always_comb begin
        alu_result = alu_y;
        if (idex_jump && (idex_wb_sel == WB_PC4)) begin
            alu_result = idex_pc_plus4;
        end
    end

    always_comb begin
        branch_taken = 1'b0;
        if (idex_branch) begin
            case (idex_branch_op)
                3'd0: branch_taken = (op_a == op_b);
                3'd1: branch_taken = (op_a != op_b);
                3'd2: branch_taken = ($signed(op_a) <  $signed(op_b));
                3'd3: branch_taken = ($signed(op_a) >= $signed(op_b));
                3'd4: branch_taken = (op_a <  op_b);
                3'd5: branch_taken = (op_a >= op_b);
                default: branch_taken = 1'b0;
            endcase
        end
    end

    always_comb begin
        jump_taken = idex_jump;
    end

    always_comb begin
        if (idex_jalr) begin
            target_pc = (op_a + idex_imm) & 32'hFFFF_FFFE;
        end else begin
            target_pc = idex_pc + idex_imm;
        end
    end

    always_comb begin
        redirect   = idex_valid & (branch_taken | jump_taken);
        ex_redirect = redirect;
        redirect_pc = target_pc;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            exmem_valid      <= 1'b0;
            exmem_pc_plus4   <= 32'd0;
            exmem_alu_result <= 32'd0;
            exmem_rs2_data   <= 32'd0;
            exmem_rs2_addr   <= 5'd0;
            exmem_rd_addr    <= 5'd0;
            exmem_reg_write  <= 1'b0;
            exmem_mem_read   <= 1'b0;
            exmem_mem_write  <= 1'b0;
            exmem_mem_size   <= 2'd0;
            exmem_mem_unsign <= 1'b0;
            exmem_wb_sel     <= 2'd0;
            exmem_is_ecall   <= 1'b0;
        end else if (exmem_flush) begin
            exmem_valid      <= 1'b0;
            exmem_pc_plus4   <= 32'd0;
            exmem_alu_result <= 32'd0;
            exmem_rs2_data   <= 32'd0;
            exmem_rs2_addr   <= 5'd0;
            exmem_rd_addr    <= 5'd0;
            exmem_reg_write  <= 1'b0;
            exmem_mem_read   <= 1'b0;
            exmem_mem_write  <= 1'b0;
            exmem_mem_size   <= 2'd0;
            exmem_mem_unsign <= 1'b0;
            exmem_wb_sel     <= 2'd0;
            exmem_is_ecall   <= 1'b0;
        end else begin
            exmem_valid      <= idex_valid;
            exmem_pc_plus4   <= idex_pc_plus4;
            exmem_alu_result <= alu_result;
            // Latch the FORWARDED store data, not the stale ID-stage read.
            // op_b is the forwarding_unit-selected rs2 value (EX/MEM or
            // MEM/WB forwarded); idex_rs2_data would be the stale ID read.
            exmem_rs2_data   <= op_b;
            exmem_rs2_addr   <= idex_rs2_addr;
            exmem_rd_addr    <= idex_rd_addr;
            exmem_reg_write  <= idex_reg_write;
            exmem_mem_read   <= idex_mem_read;
            exmem_mem_write  <= idex_mem_write;
            exmem_mem_size   <= idex_mem_size;
            exmem_mem_unsign <= idex_mem_unsign;
            exmem_wb_sel     <= idex_wb_sel;
            exmem_is_ecall   <= idex_is_ecall;
        end
    end

endmodule
