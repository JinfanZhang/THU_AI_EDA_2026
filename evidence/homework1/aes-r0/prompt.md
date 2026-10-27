你是一名数字 IC 设计工程师。请用 SystemVerilog 实现一个单模块 AES-128 加密核，要求一次生成即可通过 iverilog -g2012 仿真与 Yosys 综合，并且面积尽量小。

## 输出格式（严格遵守）

只输出**一个** ```systemverilog 代码块，里面**只有** `module aes128 ... endmodule` 这一份 RTL。不要输出 testbench、不要 `include`、不要 `$readmemh`、不要例化任何其他模块（包括自己）、不要任何解释文字或 Markdown 段落。

## 端口（必须完全一致，不得改名/改位宽）

```systemverilog
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
```

## 字节序（最容易错，务必按此实现）

- key / plaintext / ciphertext 都是 FIPS-197 向量，**最高有效字节是 byte 0**：byte i 位于位段 `[127-8i -: 8]`。
- 状态矩阵列优先：`state[r][c] = byte[4*c + r]`，r,c = 0..3。也就是说 `plaintext[127:120]` 是 state[0][0]，`plaintext[119:112]` 是 state[1][0]，依此类推。
- 密钥字：`w0 = key[127:96]`，`w1 = key[95:64]`，`w2 = key[63:32]`，`w3 = key[31:0]`；输出 ciphertext 用同样的字节序，不做额外交换。

## 算法（FIPS-197，只做加密）

1. 初始：`state = plaintext ^ {w0,w1,w2,w3}`（K0）。
2. 第 1–9 轮：`SubBytes → ShiftRows → MixColumns → AddRoundKey(K_r)`。
3. 第 10 轮：`SubBytes → ShiftRows → AddRoundKey(K10)`，**不做 MixColumns**。
4. SubBytes：对每个字节查标准 AES S-box（下表为准）。
5. ShiftRows：`state'[r][c] = state[r][(c+r) mod 4]`（第 r 行循环左移 r 字节）。
6. MixColumns：每列左乘 `[[2,3,1,1],[1,2,3,1],[1,1,2,3],[3,1,1,2]]`，乘 2 用 GF(2^8) 的 xtime（模多项式 0x11b），乘 3 = xtime(x) ^ x。
7. 密钥扩展：生成 w[0..43]。`w[i] = w[i-4] ^ temp`；`i % 4 == 0` 时 `temp = SubWord(RotWord(w[i-1])) ^ Rcon[i/4]`，Rcon[1..10] = 01,02,04,08,10,20,40,80,1b,36；否则 `temp = w[i-1]`。

S-box（十六进制，行是高 4 位、列是低 4 位，逐字节照抄）：

```text
63 7c 77 7b f2 6b 6f c5 30 01 67 2b fe d7 ab 76
ca 82 c9 7d fa 59 47 f0 ad d4 a2 af 9c a4 72 c0
b7 fd 93 26 36 3f f7 cc 34 a5 e5 f1 71 d8 31 15
04 c7 23 c3 18 96 05 9a 07 12 80 e2 eb 27 b2 75
09 83 2c 1a 1b 6e 5a a0 52 3b d6 b3 29 e3 2f 84
53 d1 00 ed 20 fc b1 5b 6a cb be 39 4a 4c 58 cf
d0 ef aa fb 43 4d 33 85 45 f9 02 7f 50 3c 9f a8
51 a3 40 8f 92 9d 38 f5 bc b6 da 21 10 ff f3 d2
cd 0c 13 ec 5f 97 44 17 c4 a7 7e 3d 64 5d 19 73
60 81 4f dc 22 2a 90 88 46 ee b8 14 de 5e 0b db
e0 32 3a 0a 49 06 24 5c c2 d3 ac 62 91 95 e4 79
e7 c8 37 6d 8d d5 4e a9 6c 56 f4 ea 65 7a ae 08
ba 78 25 2e 1c a6 b4 c6 e8 dd 74 1f 4b bd 8b 8a
70 3e b5 66 48 03 f6 0e 61 35 57 b9 86 c1 1d 9e
e1 f8 98 11 69 d9 8e 94 9b 1e 87 e9 ce 55 28 df
8c a1 89 0d bf e6 42 68 41 99 2d 0f b0 54 bb 16
```

## 握手与复位时序（教师 TB 逐拍检查）

1. `rst_n` 是**同步**低有效复位：只在 clk 上升沿生效，异步触发或写成 `always_ff @(posedge clk or negedge rst_n)` 都不合格。复位沿清 done 和所有内部状态。
2. 复位释放后 idle：`ready=1`、`done=0`。
3. `start && ready` 在上升沿成立 → 该沿锁存 key/plaintext 并开始加密；**从下一拍起 ready 必须为 0**，忙碌期间忽略新的 start。
4. 完成后 `done` 拉高**恰好一个周期**，且该周期 `ciphertext` 有效；done 之后下一拍 `done=0` 且 `ready=1`，能够立刻接受下一次 start（支持背靠背，不留气泡）。
5. 从接收 start 的沿到 done 为高的沿，延迟**不超过 200 个时钟周期**。
6. `done=0` 时 ciphertext 可任意；TB 只在 done 周期采样。

## 实现结构建议（正确性优先，再谈面积）

- S-box 写成一个 `function automatic logic [7:0] sbox(input logic [7:0] a);`，内部用 `case` 覆盖 0..255，**函数体内用给函数名赋值的方式返回，禁止使用 SystemVerilog 的 `return`**（Yosys 前端不支持，会导致综合失败）。
- 用单轮的迭代式状态机：一拍完成一轮 SubBytes + ShiftRows + MixColumns + AddRoundKey，寄存器只保存 128-bit state、128-bit 当前轮密钥和 4-bit 轮计数器。
- SubBytes 一拍内对 16 个字节并行各调一次 sbox 函数。
- 密钥扩展**在线进行**：只保存当前轮密钥（128 bit）和 Rcon 计数，每轮用 4 次 sbox 算出下一组轮密钥，不要把 11 组轮密钥全存下来（面积更小）。
- FSM 用 `typedef enum logic [1:0]`；数据通路用 `always_ff`，组合逻辑用 `always_comb` 或 `function`。
- 只使用 Yosys 支持的写法：`logic`、`always_ff`、`always_comb`、`function`、`localparam`，不要 class/interface/assertion/动态数组。

## 面积与功耗优化要求（必须在实现中体现）

- 说明性内容不要输出，但在实现上按以下取舍：MixColumns 用 xtime 组合逻辑复用，不要 4 份独立的 GF 乘法器；ShiftRows 只做连线置换；避免宽位多路选择器和冗余计数器。
- 优先保证一次综合即通过且功能正确；在此基础上尽量减少 S-box 实例数量与寄存器位宽。

再强调一次：输出只有一个 ```systemverilog 代码块，模块名 aes128，端口与上面完全一致。
