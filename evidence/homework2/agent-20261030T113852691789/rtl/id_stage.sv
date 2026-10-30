module id_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        if_id_valid,
    input  logic [31:0] if_id_pc,
    input  logic [31:0] if_id_pc_plus4,
    input  logic [31:0] if_id_instr,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    output logic [4:0]  rs1_addr,
    output logic [4:0]  rs2_addr,
    input  logic        flush_ex,
    output logic        id_valid,
    output logic        id_ecall,
    output logic        id_rs1_used,
    output logic        id_rs2_used,
    output logic        id_ex_valid,
    output logic [31:0] id_ex_pc,
    output logic [31:0] id_ex_pc_plus4,
    output logic [31:0] id_ex_rs1_data,
    output logic [31:0] id_ex_rs2_data,
    output logic [4:0]  id_ex_rs1_addr,
    output logic [4:0]  id_ex_rs2_addr,
    output logic [4:0]  id_ex_rd_addr,
    output logic [31:0] id_ex_imm,
    output logic [3:0]  id_ex_alu_op,
    output logic [1:0]  id_ex_alu_a_sel,
    output logic        id_ex_alu_b_sel,
    output logic [2:0]  id_ex_branch,
    output logic [1:0]  id_ex_jump,
    output logic [1:0]  id_ex_wb_sel,
    output logic        id_ex_reg_write,
    output logic        id_ex_mem_read,
    output logic        id_ex_mem_write,
    output logic [1:0]  id_ex_mem_size,
    output logic        id_ex_mem_unsigned,
    output logic        id_ex_ecall
);

    localparam logic [6:0] OP_RTYPE  = 7'b0110011;
    localparam logic [6:0] OP_ITYPE  = 7'b0010011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_SYSTEM = 7'b1110011;

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
    localparam logic [2:0] BR_EQ   = 3'd1;
    localparam logic [2:0] BR_NE   = 3'd2;
    localparam logic [2:0] BR_LT   = 3'd3;
    localparam logic [2:0] BR_GE   = 3'd4;
    localparam logic [2:0] BR_LTU  = 3'd5;
    localparam logic [2:0] BR_GEU  = 3'd6;

    localparam logic [1:0] JMP_NONE = 2'd0;
    localparam logic [1:0] JMP_JAL  = 2'd1;
    localparam logic [1:0] JMP_JALR = 2'd2;

    localparam logic [1:0] WB_ALU  = 2'd0;
    localparam logic [1:0] WB_MEM  = 2'd1;
    localparam logic [1:0] WB_PC4  = 2'd2;

    localparam logic [1:0] MS_BYTE = 2'd0;
    localparam logic [1:0] MS_HALF = 2'd1;
    localparam logic [1:0] MS_WORD = 2'd2;

    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [4:0]  rd_addr;
    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;
    logic [31:0] imm;

    logic        c_alu_a_pc;
    logic        c_alu_b_imm;
    logic [3:0]  c_alu_op;
    logic [2:0]  c_branch;
    logic [1:0]  c_jump;
    logic [1:0]  c_wb_sel;
    logic        c_reg_write;
    logic        c_mem_read;
    logic        c_mem_write;
    logic [1:0]  c_mem_size;
    logic        c_mem_unsigned;
    logic        c_ecall;
    logic        c_rs1_used;
    logic        c_rs2_used;

    // Internal replay control: when the load-use hazard is active, the
    // dependent instruction in IF/ID must be held (not consumed) and a
    // single bubble injected into ID/EX. flush_ex (redirect) has priority.
    logic        stall_ex;

    assign opcode = if_id_instr[6:0];
    assign funct3 = if_id_instr[14:12];
    assign funct7 = if_id_instr[31:25];
    assign rd_addr = if_id_instr[11:7];

    assign rs1_addr = if_id_instr[19:15];
    assign rs2_addr = if_id_instr[24:20];

    // I-type: sign-extend instr[31:20] (keeps instr[20] as bit 0)
    assign imm_i = {{20{if_id_instr[31]}}, if_id_instr[31:20]};
    // S-type: sign-extend {instr[31:25], instr[11:7]}
    assign imm_s = {{20{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};
    // B-type: sign-extend {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
    assign imm_b = {{19{if_id_instr[31]}}, if_id_instr[31], if_id_instr[7],
                    if_id_instr[30:25], if_id_instr[11:8], 1'b0};
    // U-type: {instr[31:12], 12'b0}
    assign imm_u = {if_id_instr[31:12], 12'b0};
    // J-type: sign-extend {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
    assign imm_j = {{11{if_id_instr[31]}}, if_id_instr[31], if_id_instr[19:12],
                    if_id_instr[20], if_id_instr[30:21], 1'b0};

    always_comb begin
        imm          = 32'b0;
        c_alu_a_pc   = 1'b0;
        c_alu_b_imm  = 1'b0;
        c_alu_op     = ALU_ADD;
        c_branch     = BR_NONE;
        c_jump       = JMP_NONE;
        c_wb_sel     = WB_ALU;
        c_reg_write  = 1'b0;
        c_mem_read   = 1'b0;
        c_mem_write  = 1'b0;
        c_mem_size   = MS_WORD;
        c_mem_unsigned = 1'b0;
        c_ecall      = 1'b0;
        c_rs1_used   = 1'b0;
        c_rs2_used   = 1'b0;

        case (opcode)
            OP_RTYPE: begin
                c_reg_write = 1'b1;
                c_rs1_used  = 1'b1;
                c_rs2_used  = 1'b1;
                c_wb_sel    = WB_ALU;
                c_alu_b_imm = 1'b0;
                case (funct3)
                    3'b000: c_alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                    3'b001: c_alu_op = ALU_SLL;
                    3'b010: c_alu_op = ALU_SLT;
                    3'b011: c_alu_op = ALU_SLTU;
                    3'b100: c_alu_op = ALU_XOR;
                    3'b101: c_alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: c_alu_op = ALU_OR;
                    3'b111: c_alu_op = ALU_AND;
                    default: c_alu_op = ALU_ADD;
                endcase
            end
            OP_ITYPE: begin
                imm         = imm_i;
                c_reg_write = 1'b1;
                c_rs1_used  = 1'b1;
                c_alu_b_imm = 1'b1;
                c_wb_sel    = WB_ALU;
                case (funct3)
                    3'b000: c_alu_op = ALU_ADD;
                    3'b001: c_alu_op = ALU_SLL;
                    3'b010: c_alu_op = ALU_SLT;
                    3'b011: c_alu_op = ALU_SLTU;
                    3'b100: c_alu_op = ALU_XOR;
                    3'b101: c_alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: c_alu_op = ALU_OR;
                    3'b111: c_alu_op = ALU_AND;
                    default: c_alu_op = ALU_ADD;
                endcase
            end
            OP_LOAD: begin
                imm            = imm_i;
                c_reg_write    = 1'b1;
                c_rs1_used     = 1'b1;
                c_alu_b_imm    = 1'b1;
                c_alu_op       = ALU_ADD;
                c_mem_read     = 1'b1;
                c_wb_sel       = WB_MEM;
                c_mem_unsigned = funct3[2];
                case (funct3[1:0])
                    2'b00: c_mem_size = MS_BYTE;
                    2'b01: c_mem_size = MS_HALF;
                    default: c_mem_size = MS_WORD;
                endcase
            end
            OP_STORE: begin
                imm         = imm_s;
                c_rs1_used  = 1'b1;
                c_rs2_used  = 1'b1;
                c_alu_b_imm = 1'b1;
                c_alu_op    = ALU_ADD;
                c_mem_write = 1'b1;
                case (funct3[1:0])
                    2'b00: c_mem_size = MS_BYTE;
                    2'b01: c_mem_size = MS_HALF;
                    default: c_mem_size = MS_WORD;
                endcase
            end
            OP_BRANCH: begin
                imm        = imm_b;
                c_rs1_used = 1'b1;
                c_rs2_used = 1'b1;
                c_alu_op   = ALU_SUB;
                case (funct3)
                    3'b000: c_branch = BR_EQ;
                    3'b001: c_branch = BR_NE;
                    3'b100: c_branch = BR_LT;
                    3'b101: c_branch = BR_GE;
                    3'b110: c_branch = BR_LTU;
                    3'b111: c_branch = BR_GEU;
                    default: c_branch = BR_NONE;
                endcase
            end
            OP_JAL: begin
                imm         = imm_j;
                c_reg_write = 1'b1;
                c_jump      = JMP_JAL;
                c_wb_sel    = WB_PC4;
            end
            OP_JALR: begin
                imm         = imm_i;
                c_reg_write = 1'b1;
                c_rs1_used  = 1'b1;
                c_alu_b_imm = 1'b1;
                c_alu_op    = ALU_ADD;
                c_jump      = JMP_JALR;
                c_wb_sel    = WB_PC4;
            end
            OP_LUI: begin
                imm         = imm_u;
                c_reg_write = 1'b1;
                c_alu_a_pc  = 1'b0;
                c_alu_b_imm = 1'b1;
                c_alu_op    = ALU_ADD;
                c_wb_sel    = WB_ALU;
            end
            OP_AUIPC: begin
                imm         = imm_u;
                c_reg_write = 1'b1;
                c_alu_a_pc  = 1'b1;
                c_alu_b_imm = 1'b1;
                c_alu_op    = ALU_ADD;
                c_wb_sel    = WB_ALU;
            end
            OP_SYSTEM: begin
                if (if_id_instr == 32'h0000_0073) begin
                    c_ecall = 1'b1;
                end
            end
            default: begin
            end
        endcase
    end

    assign id_valid     = if_id_valid;
    assign id_ecall     = if_id_valid && c_ecall;
    assign id_rs1_used  = if_id_valid && c_rs1_used;
    assign id_rs2_used  = if_id_valid && c_rs2_used;

    // Replay control: hold the dependent instruction in IF/ID and inject a
    // single bubble into ID/EX. flush_ex (redirect) always wins.
    assign stall_ex = if_id_valid && !flush_ex &&
                      ((c_rs1_used && (if_id_instr[19:15] == id_ex_rd_addr)) ||
                       (c_rs2_used && (if_id_instr[24:20] == id_ex_rd_addr))) &&
                      id_ex_valid && id_ex_mem_read && (id_ex_rd_addr != 5'd0);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            id_ex_valid       <= 1'b0;
            id_ex_pc          <= 32'b0;
            id_ex_pc_plus4    <= 32'b0;
            id_ex_rs1_data    <= 32'b0;
            id_ex_rs2_data    <= 32'b0;
            id_ex_rs1_addr    <= 5'b0;
            id_ex_rs2_addr    <= 5'b0;
            id_ex_rd_addr     <= 5'b0;
            id_ex_imm         <= 32'b0;
            id_ex_alu_op      <= ALU_ADD;
            id_ex_alu_a_sel   <= A_SEL_RS1;
            id_ex_alu_b_sel   <= 1'b0;
            id_ex_branch      <= BR_NONE;
            id_ex_jump        <= JMP_NONE;
            id_ex_wb_sel      <= WB_ALU;
            id_ex_reg_write   <= 1'b0;
            id_ex_mem_read    <= 1'b0;
            id_ex_mem_write   <= 1'b0;
            id_ex_mem_size    <= MS_WORD;
            id_ex_mem_unsigned<= 1'b0;
            id_ex_ecall       <= 1'b0;
        end else if (flush_ex) begin
            id_ex_valid       <= 1'b0;
            id_ex_pc          <= 32'b0;
            id_ex_pc_plus4    <= 32'b0;
            id_ex_rs1_data    <= 32'b0;
            id_ex_rs2_data    <= 32'b0;
            id_ex_rs1_addr    <= 5'b0;
            id_ex_rs2_addr    <= 5'b0;
            id_ex_rd_addr     <= 5'b0;
            id_ex_imm         <= 32'b0;
            id_ex_alu_op      <= ALU_ADD;
            id_ex_alu_a_sel   <= A_SEL_RS1;
            id_ex_alu_b_sel   <= 1'b0;
            id_ex_branch      <= BR_NONE;
            id_ex_jump        <= JMP_NONE;
            id_ex_wb_sel      <= WB_ALU;
            id_ex_reg_write   <= 1'b0;
            id_ex_mem_read    <= 1'b0;
            id_ex_mem_write   <= 1'b0;
            id_ex_mem_size    <= MS_WORD;
            id_ex_mem_unsigned<= 1'b0;
            id_ex_ecall       <= 1'b0;
        end else if (stall_ex) begin
            // Inject exactly one bubble into ID/EX; the dependent instruction
            // remains held in IF/ID and advances on the next cycle.
            id_ex_valid       <= 1'b0;
            id_ex_pc          <= 32'b0;
            id_ex_pc_plus4    <= 32'b0;
            id_ex_rs1_data    <= 32'b0;
            id_ex_rs2_data    <= 32'b0;
            id_ex_rs1_addr    <= 5'b0;
            id_ex_rs2_addr    <= 5'b0;
            id_ex_rd_addr     <= 5'b0;
            id_ex_imm         <= 32'b0;
            id_ex_alu_op      <= ALU_ADD;
            id_ex_alu_a_sel   <= A_SEL_RS1;
            id_ex_alu_b_sel   <= 1'b0;
            id_ex_branch      <= BR_NONE;
            id_ex_jump        <= JMP_NONE;
            id_ex_wb_sel      <= WB_ALU;
            id_ex_reg_write   <= 1'b0;
            id_ex_mem_read    <= 1'b0;
            id_ex_mem_write   <= 1'b0;
            id_ex_mem_size    <= MS_WORD;
            id_ex_mem_unsigned<= 1'b0;
            id_ex_ecall       <= 1'b0;
        end else begin
            id_ex_valid       <= if_id_valid;
            id_ex_pc          <= if_id_pc;
            id_ex_pc_plus4    <= if_id_pc_plus4;
            // Capture the real operand payload: rs1/rs2 come from the regfile
            // read ports (rs1_data/rs2_data), NOT from the instruction fields.
            id_ex_rs1_data    <= rs1_data;
            id_ex_rs2_data    <= rs2_data;
            id_ex_rs1_addr    <= if_id_instr[19:15];
            id_ex_rs2_addr    <= if_id_instr[24:20];
            id_ex_rd_addr     <= rd_addr;
            id_ex_imm         <= imm;
            id_ex_alu_op      <= c_alu_op;
            id_ex_alu_a_sel   <= c_alu_a_pc ? A_SEL_PC : A_SEL_RS1;
            id_ex_alu_b_sel   <= c_alu_b_imm;
            id_ex_branch      <= c_branch;
            id_ex_jump        <= c_jump;
            id_ex_wb_sel      <= c_wb_sel;
            id_ex_reg_write   <= c_reg_write;
            id_ex_mem_read    <= c_mem_read;
            id_ex_mem_write   <= c_mem_write;
            id_ex_mem_size    <= c_mem_size;
            id_ex_mem_unsigned<= c_mem_unsigned;
            id_ex_ecall       <= c_ecall;
        end
    end

endmodule
