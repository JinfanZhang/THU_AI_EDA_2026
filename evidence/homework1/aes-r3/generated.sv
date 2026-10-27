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

    // ------------------------------------------------------------------
    // S-box (256-entry case, one function == one hardware S-box instance)
    // ------------------------------------------------------------------
    function automatic logic [7:0] sbox(input logic [7:0] a);
        case (a)
            8'h00: sbox = 8'h63;
            8'h01: sbox = 8'h7c;
            8'h02: sbox = 8'h77;
            8'h03: sbox = 8'h7b;
            8'h04: sbox = 8'hf2;
            8'h05: sbox = 8'h6b;
            8'h06: sbox = 8'h6f;
            8'h07: sbox = 8'hc5;
            8'h08: sbox = 8'h30;
            8'h09: sbox = 8'h01;
            8'h0a: sbox = 8'h67;
            8'h0b: sbox = 8'h2b;
            8'h0c: sbox = 8'hfe;
            8'h0d: sbox = 8'hd7;
            8'h0e: sbox = 8'hab;
            8'h0f: sbox = 8'h76;
            8'h10: sbox = 8'hca;
            8'h11: sbox = 8'h82;
            8'h12: sbox = 8'hc9;
            8'h13: sbox = 8'h7d;
            8'h14: sbox = 8'hfa;
            8'h15: sbox = 8'h59;
            8'h16: sbox = 8'h47;
            8'h17: sbox = 8'hf0;
            8'h18: sbox = 8'had;
            8'h19: sbox = 8'hd4;
            8'h1a: sbox = 8'ha2;
            8'h1b: sbox = 8'haf;
            8'h1c: sbox = 8'h9c;
            8'h1d: sbox = 8'ha4;
            8'h1e: sbox = 8'h72;
            8'h1f: sbox = 8'hc0;
            8'h20: sbox = 8'hb7;
            8'h21: sbox = 8'hfd;
            8'h22: sbox = 8'h93;
            8'h23: sbox = 8'h26;
            8'h24: sbox = 8'h36;
            8'h25: sbox = 8'h3f;
            8'h26: sbox = 8'hf7;
            8'h27: sbox = 8'hcc;
            8'h28: sbox = 8'h34;
            8'h29: sbox = 8'ha5;
            8'h2a: sbox = 8'he5;
            8'h2b: sbox = 8'hf1;
            8'h2c: sbox = 8'h71;
            8'h2d: sbox = 8'hd8;
            8'h2e: sbox = 8'h31;
            8'h2f: sbox = 8'h15;
            8'h30: sbox = 8'h04;
            8'h31: sbox = 8'hc7;
            8'h32: sbox = 8'h23;
            8'h33: sbox = 8'hc3;
            8'h34: sbox = 8'h18;
            8'h35: sbox = 8'h96;
            8'h36: sbox = 8'h05;
            8'h37: sbox = 8'h9a;
            8'h38: sbox = 8'h07;
            8'h39: sbox = 8'h12;
            8'h3a: sbox = 8'h80;
            8'h3b: sbox = 8'he2;
            8'h3c: sbox = 8'heb;
            8'h3d: sbox = 8'h27;
            8'h3e: sbox = 8'hb2;
            8'h3f: sbox = 8'h75;
            8'h40: sbox = 8'h09;
            8'h41: sbox = 8'h83;
            8'h42: sbox = 8'h2c;
            8'h43: sbox = 8'h1a;
            8'h44: sbox = 8'h1b;
            8'h45: sbox = 8'h6e;
            8'h46: sbox = 8'h5a;
            8'h47: sbox = 8'ha0;
            8'h48: sbox = 8'h52;
            8'h49: sbox = 8'h3b;
            8'h4a: sbox = 8'hd6;
            8'h4b: sbox = 8'hb3;
            8'h4c: sbox = 8'h29;
            8'h4d: sbox = 8'he3;
            8'h4e: sbox = 8'h2f;
            8'h4f: sbox = 8'h84;
            8'h50: sbox = 8'h53;
            8'h51: sbox = 8'hd1;
            8'h52: sbox = 8'h00;
            8'h53: sbox = 8'hed;
            8'h54: sbox = 8'h20;
            8'h55: sbox = 8'hfc;
            8'h56: sbox = 8'hb1;
            8'h57: sbox = 8'h5b;
            8'h58: sbox = 8'h6a;
            8'h59: sbox = 8'hcb;
            8'h5a: sbox = 8'hbe;
            8'h5b: sbox = 8'h39;
            8'h5c: sbox = 8'h4a;
            8'h5d: sbox = 8'h4c;
            8'h5e: sbox = 8'h58;
            8'h5f: sbox = 8'hcf;
            8'h60: sbox = 8'hd0;
            8'h61: sbox = 8'hef;
            8'h62: sbox = 8'haa;
            8'h63: sbox = 8'hfb;
            8'h64: sbox = 8'h43;
            8'h65: sbox = 8'h4d;
            8'h66: sbox = 8'h33;
            8'h67: sbox = 8'h85;
            8'h68: sbox = 8'h45;
            8'h69: sbox = 8'hf9;
            8'h6a: sbox = 8'h02;
            8'h6b: sbox = 8'h7f;
            8'h6c: sbox = 8'h50;
            8'h6d: sbox = 8'h3c;
            8'h6e: sbox = 8'h9f;
            8'h6f: sbox = 8'ha8;
            8'h70: sbox = 8'h51;
            8'h71: sbox = 8'ha3;
            8'h72: sbox = 8'h40;
            8'h73: sbox = 8'h8f;
            8'h74: sbox = 8'h92;
            8'h75: sbox = 8'h9d;
            8'h76: sbox = 8'h38;
            8'h77: sbox = 8'hf5;
            8'h78: sbox = 8'hbc;
            8'h79: sbox = 8'hb6;
            8'h7a: sbox = 8'hda;
            8'h7b: sbox = 8'h21;
            8'h7c: sbox = 8'h10;
            8'h7d: sbox = 8'hff;
            8'h7e: sbox = 8'hf3;
            8'h7f: sbox = 8'hd2;
            8'h80: sbox = 8'hcd;
            8'h81: sbox = 8'h0c;
            8'h82: sbox = 8'h13;
            8'h83: sbox = 8'hec;
            8'h84: sbox = 8'h5f;
            8'h85: sbox = 8'h97;
            8'h86: sbox = 8'h44;
            8'h87: sbox = 8'h17;
            8'h88: sbox = 8'hc4;
            8'h89: sbox = 8'ha7;
            8'h8a: sbox = 8'h7e;
            8'h8b: sbox = 8'h3d;
            8'h8c: sbox = 8'h64;
            8'h8d: sbox = 8'h5d;
            8'h8e: sbox = 8'h19;
            8'h8f: sbox = 8'h73;
            8'h90: sbox = 8'h60;
            8'h91: sbox = 8'h81;
            8'h92: sbox = 8'h4f;
            8'h93: sbox = 8'hdc;
            8'h94: sbox = 8'h22;
            8'h95: sbox = 8'h2a;
            8'h96: sbox = 8'h90;
            8'h97: sbox = 8'h88;
            8'h98: sbox = 8'h46;
            8'h99: sbox = 8'hee;
            8'h9a: sbox = 8'hb8;
            8'h9b: sbox = 8'h14;
            8'h9c: sbox = 8'hde;
            8'h9d: sbox = 8'h5e;
            8'h9e: sbox = 8'h0b;
            8'h9f: sbox = 8'hdb;
            8'ha0: sbox = 8'he0;
            8'ha1: sbox = 8'h32;
            8'ha2: sbox = 8'h3a;
            8'ha3: sbox = 8'h0a;
            8'ha4: sbox = 8'h49;
            8'ha5: sbox = 8'h06;
            8'ha6: sbox = 8'h24;
            8'ha7: sbox = 8'h5c;
            8'ha8: sbox = 8'hc2;
            8'ha9: sbox = 8'hd3;
            8'haa: sbox = 8'hac;
            8'hab: sbox = 8'h62;
            8'hac: sbox = 8'h91;
            8'had: sbox = 8'h95;
            8'hae: sbox = 8'he4;
            8'haf: sbox = 8'h79;
            8'hb0: sbox = 8'he7;
            8'hb1: sbox = 8'hc8;
            8'hb2: sbox = 8'h37;
            8'hb3: sbox = 8'h6d;
            8'hb4: sbox = 8'h8d;
            8'hb5: sbox = 8'hd5;
            8'hb6: sbox = 8'h4e;
            8'hb7: sbox = 8'ha9;
            8'hb8: sbox = 8'h6c;
            8'hb9: sbox = 8'h56;
            8'hba: sbox = 8'hf4;
            8'hbb: sbox = 8'hea;
            8'hbc: sbox = 8'h65;
            8'hbd: sbox = 8'h7a;
            8'hbe: sbox = 8'hae;
            8'hbf: sbox = 8'h08;
            8'hc0: sbox = 8'hba;
            8'hc1: sbox = 8'h78;
            8'hc2: sbox = 8'h25;
            8'hc3: sbox = 8'h2e;
            8'hc4: sbox = 8'h1c;
            8'hc5: sbox = 8'ha6;
            8'hc6: sbox = 8'hb4;
            8'hc7: sbox = 8'hc6;
            8'hc8: sbox = 8'he8;
            8'hc9: sbox = 8'hdd;
            8'hca: sbox = 8'h74;
            8'hcb: sbox = 8'h1f;
            8'hcc: sbox = 8'h4b;
            8'hcd: sbox = 8'hbd;
            8'hce: sbox = 8'h8b;
            8'hcf: sbox = 8'h8a;
            8'hd0: sbox = 8'h70;
            8'hd1: sbox = 8'h3e;
            8'hd2: sbox = 8'hb5;
            8'hd3: sbox = 8'h66;
            8'hd4: sbox = 8'h48;
            8'hd5: sbox = 8'h03;
            8'hd6: sbox = 8'hf6;
            8'hd7: sbox = 8'h0e;
            8'hd8: sbox = 8'h61;
            8'hd9: sbox = 8'h35;
            8'hda: sbox = 8'h57;
            8'hdb: sbox = 8'hb9;
            8'hdc: sbox = 8'h86;
            8'hdd: sbox = 8'hc1;
            8'hde: sbox = 8'h1d;
            8'hdf: sbox = 8'h9e;
            8'he0: sbox = 8'he1;
            8'he1: sbox = 8'hf8;
            8'he2: sbox = 8'h98;
            8'he3: sbox = 8'h11;
            8'he4: sbox = 8'h69;
            8'he5: sbox = 8'hd9;
            8'he6: sbox = 8'h8e;
            8'he7: sbox = 8'h94;
            8'he8: sbox = 8'h9b;
            8'he9: sbox = 8'h1e;
            8'hea: sbox = 8'h87;
            8'heb: sbox = 8'he9;
            8'hec: sbox = 8'hce;
            8'hed: sbox = 8'h55;
            8'hee: sbox = 8'h28;
            8'hef: sbox = 8'hdf;
            8'hf0: sbox = 8'h8c;
            8'hf1: sbox = 8'ha1;
            8'hf2: sbox = 8'h89;
            8'hf3: sbox = 8'h0d;
            8'hf4: sbox = 8'hbf;
            8'hf5: sbox = 8'he6;
            8'hf6: sbox = 8'h42;
            8'hf7: sbox = 8'h68;
            8'hf8: sbox = 8'h41;
            8'hf9: sbox = 8'h99;
            8'hfa: sbox = 8'h2d;
            8'hfb: sbox = 8'h0f;
            8'hfc: sbox = 8'hb0;
            8'hfd: sbox = 8'h54;
            8'hfe: sbox = 8'hbb;
            8'hff: sbox = 8'h16;
            default: sbox = 8'h00;
        endcase
    endfunction

    // ------------------------------------------------------------------
    // GF(2^8) multiply-by-2
    // ------------------------------------------------------------------
    function automatic logic [7:0] xtime(input logic [7:0] x);
        xtime = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h00);
    endfunction

    // ------------------------------------------------------------------
    // MixColumns for one 32-bit column (shares the single xtime function)
    // ------------------------------------------------------------------
    function automatic logic [31:0] mix_col(input logic [31:0] a);
        logic [7:0] b0, b1, b2, b3, t;
        begin
            b0 = a[31:24];
            b1 = a[23:16];
            b2 = a[15:8];
            b3 = a[7:0];
            t  = b0 ^ b1 ^ b2 ^ b3;
            mix_col[31:24] = b0 ^ t ^ xtime(b0 ^ b1);
            mix_col[23:16] = b1 ^ t ^ xtime(b1 ^ b2);
            mix_col[15:8]  = b2 ^ t ^ xtime(b2 ^ b3);
            mix_col[7:0]   = b3 ^ t ^ xtime(b3 ^ b0);
        end
    endfunction

    // ------------------------------------------------------------------
    // ShiftRows, pure wiring permutation on the byte lanes
    // ------------------------------------------------------------------
    function automatic logic [127:0] shift_rows(input logic [127:0] s);
        begin
            shift_rows[127:120] = s[127:120];
            shift_rows[119:112] = s[87:80];
            shift_rows[111:104] = s[47:40];
            shift_rows[103:96]  = s[7:0];
            shift_rows[95:88]   = s[95:88];
            shift_rows[87:80]   = s[55:48];
            shift_rows[79:72]   = s[15:8];
            shift_rows[71:64]   = s[103:96];
            shift_rows[63:56]   = s[63:56];
            shift_rows[55:48]   = s[23:16];
            shift_rows[47:40]   = s[111:104];
            shift_rows[39:32]   = s[71:64];
            shift_rows[31:24]   = s[31:24];
            shift_rows[23:16]   = s[119:112];
            shift_rows[15:8]    = s[79:72];
            shift_rows[7:0]     = s[39:32];
        end
    endfunction

    // ------------------------------------------------------------------
    // Rcon
    // ------------------------------------------------------------------
    function automatic logic [7:0] rcon_val(input logic [3:0] r);
        case (r)
            4'd1:  rcon_val = 8'h01;
            4'd2:  rcon_val = 8'h02;
            4'd3:  rcon_val = 8'h04;
            4'd4:  rcon_val = 8'h08;
            4'd5:  rcon_val = 8'h10;
            4'd6:  rcon_val = 8'h20;
            4'd7:  rcon_val = 8'h40;
            4'd8:  rcon_val = 8'h80;
            4'd9:  rcon_val = 8'h1b;
            4'd10: rcon_val = 8'h36;
            default: rcon_val = 8'h00;
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    logic [127:0] state;
    logic [127:0] rkey;
    logic [127:0] subst;
    logic [3:0]   round;
    logic [2:0]   phase;   // 0=KEY, 1..4=SUB, 5=MIX
    logic         busy;

    // ------------------------------------------------------------------
    // 4 time-multiplexed S-box instances
    // ------------------------------------------------------------------
    logic [31:0] sb_in;
    logic [31:0] sb_out;

    always_comb begin
        if (phase == 3'd0)
            sb_in = {rkey[23:0], rkey[31:24]};   // RotWord(w3)
        else if (phase == 3'd1)
            sb_in = state[127:96];
        else if (phase == 3'd2)
            sb_in = state[95:64];
        else if (phase == 3'd3)
            sb_in = state[63:32];
        else
            sb_in = state[31:0];

        sb_out[31:24] = sbox(sb_in[31:24]);
        sb_out[23:16] = sbox(sb_in[23:16]);
        sb_out[15:8]  = sbox(sb_in[15:8]);
        sb_out[7:0]   = sbox(sb_in[7:0]);
    end

    // ------------------------------------------------------------------
    // Key schedule temp word
    // ------------------------------------------------------------------
    logic [31:0] ktmp;
    always_comb ktmp = sb_out ^ {rcon_val(round), 24'h00};

    // ------------------------------------------------------------------
    // ShiftRows + MixColumns datapath
    // ------------------------------------------------------------------
    logic [127:0] sr_val;
    logic [127:0] mix_val;

    always_comb begin
        sr_val  = shift_rows(subst);
        mix_val = { mix_col(sr_val[127:96]),
                    mix_col(sr_val[95:64]),
                    mix_col(sr_val[63:32]),
                    mix_col(sr_val[31:0]) };
    end

    // ------------------------------------------------------------------
    // Control / datapath sequencing
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ready      <= 1'b1;
            done       <= 1'b0;
            busy       <= 1'b0;
            phase      <= 3'd0;
            round      <= 4'd0;
            state      <= 128'd0;
            subst      <= 128'd0;
            rkey       <= 128'd0;
            ciphertext <= 128'd0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                ready <= 1'b1;
                if (start && ready) begin
                    busy  <= 1'b1;
                    ready <= 1'b0;
                    rkey  <= key;
                    state <= plaintext ^ key;
                    round <= 4'd1;
                    phase <= 3'd0;
                end
            end else begin
                case (phase)
                    3'd0: begin
                        rkey <= {
                            rkey[127:96] ^ ktmp,
                            rkey[95:64]  ^ rkey[127:96] ^ ktmp,
                            rkey[63:32]  ^ rkey[95:64]  ^ rkey[127:96] ^ ktmp,
                            rkey[31:0]   ^ rkey[63:32]  ^ rkey[95:64]  ^ rkey[127:96] ^ ktmp
                        };
                        phase <= 3'd1;
                    end
                    3'd1: begin
                        subst[127:96] <= sb_out;
                        phase <= 3'd2;
                    end
                    3'd2: begin
                        subst[95:64] <= sb_out;
                        phase <= 3'd3;
                    end
                    3'd3: begin
                        subst[63:32] <= sb_out;
                        phase <= 3'd4;
                    end
                    3'd4: begin
                        subst[31:0] <= sb_out;
                        phase <= 3'd5;
                    end
                    3'd5: begin
                        if (round == 4'd10) begin
                            state      <= sr_val ^ rkey;
                            ciphertext <= sr_val ^ rkey;
                            done       <= 1'b1;
                            busy       <= 1'b0;
                            ready      <= 1'b1;
                            phase      <= 3'd0;
                            round      <= 4'd0;
                        end else begin
                            state <= mix_val ^ rkey;
                            round <= round + 4'd1;
                            phase <= 3'd0;
                        end
                    end
                    default: phase <= 3'd0;
                endcase
            end
        end
    end

endmodule
