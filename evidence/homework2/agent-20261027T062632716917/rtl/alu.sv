module alu (
    input  logic [3:0]  alu_op,
    input  logic [31:0] alu_a,
    input  logic [31:0] alu_b,
    output logic [31:0] alu_y
);

    always @(*) begin
        alu_y = 32'd0;
        case (alu_op)
            4'd0: alu_y = alu_a + alu_b;
            4'd1: alu_y = alu_a - alu_b;
            4'd2: alu_y = alu_a << alu_b[4:0];
            4'd3: alu_y = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
            4'd4: alu_y = (alu_a < alu_b) ? 32'd1 : 32'd0;
            4'd5: alu_y = alu_a ^ alu_b;
            4'd6: alu_y = alu_a >> alu_b[4:0];
            4'd7: alu_y = $signed(alu_a) >>> alu_b[4:0];
            4'd8: alu_y = alu_a | alu_b;
            4'd9: alu_y = alu_a & alu_b;
            default: alu_y = 32'd0;
        endcase
    end

endmodule
