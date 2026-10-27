module aes128 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic [127:0] key,
    input  logic [127:0] plaintext,
    output logic         ready,
    output logic         done,
    output logic [127:0] ciphertext
);

    function automatic logic [7:0] sbox(input logic [7:0] a);
        case (a)
            8'h00: sbox = 8'h63; 8'h01: sbox = 8'h7c; 8'h02: sbox = 8'h77; 8'h03: sbox = 8'h7b;
            8'h04: sbox = 8'hf2; 8'h05: sbox = 8'h6b; 8'h06: sbox = 8'h6f; 8'h07: sbox = 8'hc5;
            8'h08: sbox = 8'h30; 8'h09: sbox = 8'h01; 8'h0a: sbox = 8'h67; 8'h0b: sbox = 8'h2b;
            8'h0c: sbox = 8'hfe; 8'h0d: sbox = 8'hd7; 8'h0e: sbox = 8'hab; 8'h0f: sbox = 8'h76;
            8'h10: sbox = 8'hca; 8'h11: sbox = 8'h82; 8'h12: sbox = 8'hc9; 8'h13: sbox = 8'h7d;
            8'h14: sbox = 8'hfa; 8'h15: sbox = 8'h59; 8'h16: sbox = 8'h47; 8'h17: sbox = 8'hf0;
            8'h18: sbox = 8'had; 8'h19: sbox = 8'hd4; 8'h1a: sbox = 8'ha2; 8'h1b: sbox = 8'haf;
            8'h1c: sbox = 8'h9c; 8'h1d: sbox = 8'ha4; 8'h1e: sbox = 8'h72; 8'h1f: sbox = 8'hc0;
            8'h20: sbox = 8'hb7; 8'h21: sbox = 8'hfd; 8'h22: sbox = 8'h93; 8'h23: sbox = 8'h26;
            8'h24: sbox = 8'h36; 8'h25: sbox = 8'h3f; 8'h26: sbox = 8'hf7; 8'h27: sbox = 8'hcc;
            8'h28: sbox = 8'h34; 8'h29: sbox = 8'ha5; 8'h2a: sbox = 8'he5; 8'h2b: sbox = 8'hf1;
            8'h2c: sbox = 8'h71; 8'h2d: sbox = 8'hd8; 8'h2e: sbox = 8'h31; 8'h2f: sbox = 8'h15;
            8'h30: sbox = 8'h04; 8'h31: sbox = 8'hc7; 8'h32: sbox = 8'h23; 8'h33: sbox = 8'hc3;
            8'h34: sbox = 8'h18; 8'h35: sbox = 8'h96; 8'h36: sbox = 8'h05; 8'h37: sbox = 8'h9a;
            8'h38: sbox = 8'h07; 8'h39: sbox = 8'h12; 8'h3a: sbox = 8'h80; 8'h3b: sbox = 8'he2;
            8'h3c: sbox = 8'heb; 8'h3d: sbox = 8'h27; 8'h3e: sbox = 8'hb2; 8'h3f: sbox = 8'h75;
            8'h40: sbox = 8'h09; 8'h41: sbox = 8'h83; 8'h42: sbox = 8'h2c; 8'h43: sbox = 8'h1a;
            8'h44: sbox = 8'h1b; 8'h45: sbox = 8'h6e; 8'h46: sbox = 8'h5a; 8'h47: sbox = 8'ha0;
            8'h48: sbox = 8'h52; 8'h49: sbox = 8'h3b; 8'h4a: sbox = 8'hd6; 8'h4b: sbox = 8'hb3;
            8'h4c: sbox = 8'h29; 8'h4d: sbox = 8'he3; 8'h4e: sbox = 8'h2f; 8'h4f: sbox = 8'h84;
            8'h50: sbox = 8'h53; 8'h51: sbox = 8'hd1; 8'h52: sbox = 8'h00; 8'h53: sbox = 8'hed;
            8'h54: sbox = 8'h20; 8'h55: sbox = 8'hfc; 8'h56: sbox = 8'hb1; 8'h57: sbox = 8'h5b;
            8'h58: sbox = 8'h6a; 8'h59: sbox = 8'hcb; 8'h5a: sbox = 8'hbe; 8'h5b: sbox = 8'h39;
            8'h5c: sbox = 8'h4a; 8'h5d: sbox = 8'h4c; 8'h5e: sbox = 8'h58; 8'h5f: sbox = 8'hcf;
            8'h60: sbox = 8'hd0; 8'h61: sbox = 8'hef; 8'h62: sbox = 8'haa; 8'h63: sbox = 8'hfb;
            8'h64: sbox = 8'h43; 8'h65: sbox = 8'h4d; 8'h66: sbox = 8'h33; 8'h67: sbox = 8'h85;
            8'h68: sbox = 8'h45; 8'h69: sbox = 8'hf9; 8'h6a: sbox = 8'h02; 8'h6b: sbox = 8'h7f;
            8'h6c: sbox = 8'h50; 8'h6d: sbox = 8'h3c; 8'h6e: sbox = 8'h9f; 8'h6f: sbox = 8'ha8;
            8'h70: sbox = 8'h51; 8'h71: sbox = 8'ha3; 8'h72: sbox = 8'h40; 8'h73: sbox = 8'h8f;
            8'h74: sbox = 8'h92; 8'h75: sbox = 8'h9d; 8'h76: sbox = 8'h38; 8'h77: sbox = 8'hf5;
            8'h78: sbox = 8'hbc; 8'h79: sbox = 8'hb6; 8'h7a: sbox = 8'hda; 8'h7b: sbox = 8'h21;
            8'h7c: sbox = 8'h10; 8'h7d: sbox = 8'hff; 8'h7e: sbox = 8'hf3; 8'h7f: sbox = 8'hd2;
            8'h80: sbox = 8'hcd; 8'h81: sbox = 8'h0c; 8'h82: sbox = 8'h13; 8'h83: sbox = 8'hec;
            8'h84: sbox = 8'h5f; 8'h85: sbox = 8'h97; 8'h86: sbox = 8'h44; 8'h87: sbox = 8'h17;
            8'h88: sbox = 8'hc4; 8'h89: sbox = 8'ha7; 8'h8a: sbox = 8'h7e; 8'h8b: sbox = 8'h3d;
            8'h8c: sbox = 8'h64; 8'h8d: sbox = 8'h5d; 8'h8e: sbox = 8'h19; 8'h8f: sbox = 8'h73;
            8'h90: sbox = 8'h60; 8'h91: sbox = 8'h81; 8'h92: sbox = 8'h4f; 8'h93: sbox = 8'hdc;
            8'h94: sbox = 8'h22; 8'h95: sbox = 8'h2a; 8'h96: sbox = 8'h90; 8'h97: sbox = 8'h88;
            8'h98: sbox = 8'h46; 8'h99: sbox = 8'hee; 8'h9a: sbox = 8'hb8; 8'h9b: sbox = 8'h14;
            8'h9c: sbox = 8'hde; 8'h9d: sbox = 8'h5e; 8'h9e: sbox = 8'h0b; 8'h9f: sbox = 8'hdb;
            8'ha0: sbox = 8'he0; 8'ha1: sbox = 8'h32; 8'ha2: sbox = 8'h3a; 8'ha3: sbox = 8'h0a;
            8'ha4: sbox = 8'h49; 8'ha5: sbox = 8'h06; 8'ha6: sbox = 8'h24; 8'ha7: sbox = 8'h5c;
            8'ha8: sbox = 8'hc2; 8'ha9: sbox = 8'hd3; 8'haa: sbox = 8'hac; 8'hab: sbox = 8'h62;
            8'hac: sbox = 8'h91; 8'had: sbox = 8'h95; 8'hae: sbox = 8'he4; 8'haf: sbox = 8'h79;
            8'hb0: sbox = 8'he7; 8'hb1: sbox = 8'hc8; 8'hb2: sbox = 8'h37; 8'hb3: sbox = 8'h6d;
            8'hb4: sbox = 8'h8d; 8'hb5: sbox = 8'hd5; 8'hb6: sbox = 8'h4e; 8'hb7: sbox = 8'ha9;
            8'hb8: sbox = 8'h6c; 8'hb9: sbox = 8'h56; 8'hba: sbox = 8'hf4; 8'hbb: sbox = 8'hea;
            8'hbc: sbox = 8'h65; 8'hbd: sbox = 8'h7a; 8'hbe: sbox = 8'hae; 8'hbf: sbox = 8'h08;
            8'hc0: sbox = 8'hba; 8'hc1: sbox = 8'h78; 8'hc2: sbox = 8'h25; 8'hc3: sbox = 8'h2e;
            8'hc4: sbox = 8'h1c; 8'hc5: sbox = 8'ha6; 8'hc6: sbox = 8'hb4; 8'hc7: sbox = 8'hc6;
            8'hc8: sbox = 8'he8; 8'hc9: sbox = 8'hdd; 8'hca: sbox = 8'h74; 8'hcb: sbox = 8'h1f;
            8'hcc: sbox = 8'h4b; 8'hcd: sbox = 8'hbd; 8'hce: sbox = 8'h8b; 8'hcf: sbox = 8'h8a;
            8'hd0: sbox = 8'h70; 8'hd1: sbox = 8'h3e; 8'hd2: sbox = 8'hb5; 8'hd3: sbox = 8'h66;
            8'hd4: sbox = 8'h48; 8'hd5: sbox = 8'h03; 8'hd6: sbox = 8'hf6; 8'hd7: sbox = 8'h0e;
            8'hd8: sbox = 8'h61; 8'hd9: sbox = 8'h35; 8'hda: sbox = 8'h57; 8'hdb: sbox = 8'hb9;
            8'hdc: sbox = 8'h86; 8'hdd: sbox = 8'hc1; 8'hde: sbox = 8'h1d; 8'hdf: sbox = 8'h9e;
            8'he0: sbox = 8'he1; 8'he1: sbox = 8'hf8; 8'he2: sbox = 8'h98; 8'he3: sbox = 8'h11;
            8'he4: sbox = 8'h69; 8'he5: sbox = 8'hd9; 8'he6: sbox = 8'h8e; 8'he7: sbox = 8'h94;
            8'he8: sbox = 8'h9b; 8'he9: sbox = 8'h1e; 8'hea: sbox = 8'h87; 8'heb: sbox = 8'he9;
            8'hec: sbox = 8'hce; 8'hed: sbox = 8'h55; 8'hee: sbox = 8'h28; 8'hef: sbox = 8'hdf;
            8'hf0: sbox = 8'h8c; 8'hf1: sbox = 8'ha1; 8'hf2: sbox = 8'h89; 8'hf3: sbox = 8'h0d;
            8'hf4: sbox = 8'hbf; 8'hf5: sbox = 8'he6; 8'hf6: sbox = 8'h42; 8'hf7: sbox = 8'h68;
            8'hf8: sbox = 8'h41; 8'hf9: sbox = 8'h99; 8'hfa: sbox = 8'h2d; 8'hfb: sbox = 8'h0f;
            8'hfc: sbox = 8'hb0; 8'hfd: sbox = 8'h54; 8'hfe: sbox = 8'hbb; 8'hff: sbox = 8'h16;
            default: sbox = 8'h00;
        endcase
    endfunction

    function automatic logic [7:0] xtime(input logic [7:0] a);
        xtime = {a[6:0], 1'b0} ^ (a[7] ? 8'h1b : 8'h00);
    endfunction

    typedef enum logic [1:0] {IDLE, ROUND, DONE} fsm_t;
    fsm_t fsm_state;

    logic [127:0] state_reg;
    logic [127:0] round_key_reg;
    logic [3:0]   round_cnt;
    logic [7:0]   rcon_reg;

    logic [127:0] sb_vec;
    logic [127:0] sr_vec;
    logic [127:0] mc_vec;
    logic [127:0] next_state;
    logic [127:0] next_round_key;
    logic [7:0]   next_rcon;

    assign sb_vec[127:120] = sbox(state_reg[127:120]);
    assign sb_vec[119:112] = sbox(state_reg[119:112]);
    assign sb_vec[111:104] = sbox(state_reg[111:104]);
    assign sb_vec[103:96]  = sbox(state_reg[103:96]);
    assign sb_vec[95:88]   = sbox(state_reg[95:88]);
    assign sb_vec[87:80]   = sbox(state_reg[87:80]);
    assign sb_vec[79:72]   = sbox(state_reg[79:72]);
    assign sb_vec[71:64]   = sbox(state_reg[71:64]);
    assign sb_vec[63:56]   = sbox(state_reg[63:56]);
    assign sb_vec[55:48]   = sbox(state_reg[55:48]);
    assign sb_vec[47:40]   = sbox(state_reg[47:40]);
    assign sb_vec[39:32]   = sbox(state_reg[39:32]);
    assign sb_vec[31:24]   = sbox(state_reg[31:24]);
    assign sb_vec[23:16]   = sbox(state_reg[23:16]);
    assign sb_vec[15:8]    = sbox(state_reg[15:8]);
    assign sb_vec[7:0]     = sbox(state_reg[7:0]);

    assign sr_vec[127:120] = sb_vec[127:120];
    assign sr_vec[119:112] = sb_vec[87:80];
    assign sr_vec[111:104] = sb_vec[47:40];
    assign sr_vec[103:96]  = sb_vec[7:0];
    assign sr_vec[95:88]   = sb_vec[95:88];
    assign sr_vec[87:80]   = sb_vec[55:48];
    assign sr_vec[79:72]   = sb_vec[15:8];
    assign sr_vec[71:64]   = sb_vec[103:96];
    assign sr_vec[63:56]   = sb_vec[63:56];
    assign sr_vec[55:48]   = sb_vec[23:16];
    assign sr_vec[47:40]   = sb_vec[111:104];
    assign sr_vec[39:32]   = sb_vec[71:64];
    assign sr_vec[31:24]   = sb_vec[31:24];
    assign sr_vec[23:16]   = sb_vec[119:112];
    assign sr_vec[15:8]    = sb_vec[79:72];
    assign sr_vec[7:0]     = sb_vec[39:32];

    logic [7:0] s0,  s1,  s2,  s3,  s4,  s5,  s6,  s7;
    logic [7:0] s8,  s9,  s10, s11, s12, s13, s14, s15;
    logic [7:0] t0,  t1,  t2,  t3,  t4,  t5,  t6,  t7;
    logic [7:0] t8,  t9,  t10, t11, t12, t13, t14, t15;

    assign s0  = sr_vec[127:120]; assign s1  = sr_vec[119:112];
    assign s2  = sr_vec[111:104]; assign s3  = sr_vec[103:96];
    assign s4  = sr_vec[95:88];   assign s5  = sr_vec[87:80];
    assign s6  = sr_vec[79:72];   assign s7  = sr_vec[71:64];
    assign s8  = sr_vec[63:56];   assign s9  = sr_vec[55:48];
    assign s10 = sr_vec[47:40];   assign s11 = sr_vec[39:32];
    assign s12 = sr_vec[31:24];   assign s13 = sr_vec[23:16];
    assign s14 = sr_vec[15:8];    assign s15 = sr_vec[7:0];

    assign t0  = xtime(s0);  assign t1  = xtime(s1);
    assign t2  = xtime(s2);  assign t3  = xtime(s3);
    assign t4  = xtime(s4);  assign t5  = xtime(s5);
    assign t6  = xtime(s6);  assign t7  = xtime(s7);
    assign t8  = xtime(s8);  assign t9  = xtime(s9);
    assign t10 = xtime(s10); assign t11 = xtime(s11);
    assign t12 = xtime(s12); assign t13 = xtime(s13);
    assign t14 = xtime(s14); assign t15 = xtime(s15);

    assign mc_vec[127:120] = t0  ^ t1  ^ s1  ^ s2  ^ s3;
    assign mc_vec[119:112] = s0  ^ t1  ^ t2  ^ s2  ^ s3;
    assign mc_vec[111:104] = s0  ^ s1  ^ t2  ^ t3  ^ s3;
    assign mc_vec[103:96]  = t0  ^ s0  ^ s1  ^ s2  ^ t3;
    assign mc_vec[95:88]   = t4  ^ t5  ^ s5  ^ s6  ^ s7;
    assign mc_vec[87:80]   = s4  ^ t5  ^ t6  ^ s6  ^ s7;
    assign mc_vec[79:72]   = s4  ^ s5  ^ t6  ^ t7  ^ s7;
    assign mc_vec[71:64]   = t4  ^ s4  ^ s5  ^ s6  ^ t7;
    assign mc_vec[63:56]   = t8  ^ t9  ^ s9  ^ s10 ^ s11;
    assign mc_vec[55:48]   = s8  ^ t9  ^ t10 ^ s10 ^ s11;
    assign mc_vec[47:40]   = s8  ^ s9  ^ t10 ^ t11 ^ s11;
    assign mc_vec[39:32]   = t8  ^ s8  ^ s9  ^ s10 ^ t11;
    assign mc_vec[31:24]   = t12 ^ t13 ^ s13 ^ s14 ^ s15;
    assign mc_vec[23:16]   = s12 ^ t13 ^ t14 ^ s14 ^ s15;
    assign mc_vec[15:8]    = s12 ^ s13 ^ t14 ^ t15 ^ s15;
    assign mc_vec[7:0]     = t12 ^ s12 ^ s13 ^ s14 ^ t15;

    logic [31:0] kw0, kw1, kw2, kw3;
    logic [7:0]  sw0, sw1, sw2, sw3;
    logic [31:0] ktemp, nw0, nw1, nw2, nw3;

    assign kw0 = round_key_reg[127:96];
    assign kw1 = round_key_reg[95:64];
    assign kw2 = round_key_reg[63:32];
    assign kw3 = round_key_reg[31:0];

    assign sw0 = sbox(kw3[23:16]);
    assign sw1 = sbox(kw3[15:8]);
    assign sw2 = sbox(kw3[7:0]);
    assign sw3 = sbox(kw3[31:24]);

    assign ktemp = {sw0 ^ rcon_reg, sw1, sw2, sw3};
    assign nw0   = kw0 ^ ktemp;
    assign nw1   = kw1 ^ nw0;
    assign nw2   = kw2 ^ nw1;
    assign nw3   = kw3 ^ nw2;
    assign next_round_key = {nw0, nw1, nw2, nw3};

    assign next_rcon = rcon_reg[7] ? (8'h1b ^ {rcon_reg[6:0], 1'b0})
                                   : {rcon_reg[6:0], 1'b0};

    assign next_state = ((round_cnt == 4'd10) ? sr_vec : mc_vec) ^ next_round_key;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fsm_state     <= IDLE;
            state_reg     <= 128'h0;
            round_key_reg <= 128'h0;
            round_cnt     <= 4'h0;
            rcon_reg      <= 8'h0;
        end else begin
            case (fsm_state)
                IDLE: begin
                    if (start) begin
                        state_reg     <= plaintext ^ key;
                        round_key_reg <= key;
                        round_cnt     <= 4'd1;
                        rcon_reg      <= 8'h01;
                        fsm_state     <= ROUND;
                    end
                end
                ROUND: begin
                    state_reg     <= next_state;
                    round_key_reg <= next_round_key;
                    rcon_reg      <= next_rcon;
                    if (round_cnt == 4'd10) begin
                        fsm_state <= DONE;
                    end else begin
                        round_cnt <= round_cnt + 4'd1;
                    end
                end
                DONE: begin
                    fsm_state <= IDLE;
                end
                default: fsm_state <= IDLE;
            endcase
        end
    end

    assign ready      = (fsm_state == IDLE);
    assign done       = (fsm_state == DONE);
    assign ciphertext = state_reg;

endmodule
