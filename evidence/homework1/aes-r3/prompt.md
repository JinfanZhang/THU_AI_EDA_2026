你是一名数字 IC 设计工程师。请用 SystemVerilog 实现一个**面积优先**的单模块 AES-128 加密核：一次生成就要通过 iverilog -g2012 仿真与 Yosys 综合，并且在 200 周期延迟上限内尽量少用 S-box 实例和寄存器。

## 输出格式（严格遵守）

只输出**一个** ```systemverilog 代码块，里面**只有** `module aes128 ... endmodule`。不要 testbench、不要 `include`、不要 `$readmemh`、不要例化任何其他模块（含自身）、不要任何解释文字。

## 端口（完全一致，不得改名/改位宽）

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

## 字节序（务必按此实现）

- key / plaintext / ciphertext 均为 FIPS-197 向量，**最高有效字节是 byte 0**：byte i 位于 `[127-8i -: 8]`。
- 状态矩阵列优先：`state[r][c] = byte[4*c + r]`。即 `plaintext[127:120]` 是 state[0][0]，`plaintext[119:112]` 是 state[1][0]，以此类推；连续 4 个字节正好是状态矩阵的一列。
- 密钥字：`w0 = key[127:96]`、`w1 = key[95:64]`、`w2 = key[63:32]`、`w3 = key[31:0]`；ciphertext 用同样字节序，不做交换。

## 算法（FIPS-197 加密）

1. 初始：`state = plaintext ^ {w0,w1,w2,w3}`。
2. 第 1–9 轮：`SubBytes → ShiftRows → MixColumns → AddRoundKey(K_r)`。
3. 第 10 轮：`SubBytes → ShiftRows → AddRoundKey(K10)`，**不做 MixColumns**。
4. ShiftRows：`state'[r][c] = state[r][(c+r) mod 4]`。
5. MixColumns：每列乘 `[[2,3,1,1],[1,2,3,1],[1,1,2,3],[3,1,1,2]]`，乘 2 用 xtime（模 0x11b），乘 3 = xtime(x)^x。
6. 密钥扩展：`w[i] = w[i-4] ^ temp`；`i%4==0` 时 `temp = SubWord(RotWord(w[i-1])) ^ Rcon[i/4]`，Rcon[1..10] = 01,02,04,08,10,20,40,80,1b,36。

S-box（行=高 4 位、列=低 4 位，逐字节照抄）：

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

1. `rst_n` 为**同步**低有效复位，只在 clk 上升沿生效（不能写成 `or negedge rst_n`）；复位沿清 done、ready 与全部内部状态。
2. 复位释放后 idle：`ready=1`、`done=0`。
3. `start && ready` 在上升沿成立 → 该沿锁存 key/plaintext 并开始；下一拍起 `ready` 必须为 0，忙碌期间忽略 start。
4. 完成后 `done` 拉高**恰好一拍**，该拍 `ciphertext` 有效；done 的下一拍 `done=0` 且 `ready=1`，可立刻接受下一次 start（支持背靠背）。
5. 从接收 start 的沿到 done 为高的沿，**不超过 200 个时钟周期**。
6. `done=0` 时 ciphertext 可任意值。

## 目标架构（4 个 S-box 分时复用，必须照此实现）

面积优化的关键：**只用 4 个 S-box 实例**（写成一个 `function automatic logic [7:0] sbox(input logic [7:0] a)`，函数内用 `case` 覆盖 0..255，**用给函数名赋值返回，禁止 `return`**——Yosys 前端不支持），而不是 16 个或 20 个。

状态机按轮推进，每轮三拍：

1. **KEY 拍**：用 4 个 S-box 对 `RotWord(w3)` 的 4 个字节做 SubWord，与该拍的 Rcon 异或得到 temp，组合算出下一组 4 个字（w4=w0^temp, w5=w1^w4, w6=w2^w5, w7=w3^w6），寄存为新的 128-bit 轮密钥。第 10 轮之后不需要再扩展，可省掉。
2. **SUB 拍 ×4**：每拍把当前 state 的 4 个字节（`state[4*j*8 +: 32]` 那一列，j=0..3）各过一次 sbox，写入 128-bit 的 `subst` 寄存器。4 拍填满 16 字节。
3. **MIX 拍**：对 `subst` 先做 ShiftRows（纯连线置换），再按轮次选择：第 1–9 轮做 MixColumns 后与新的轮密钥异或；第 10 轮只做 ShiftRows 与轮密钥异或，结果写回 `state`。

一轮 6 拍，10 轮约 60 拍，加上初始与收尾远低于 200 拍上限。请把轮计数器、阶段计数器、Rcon 计数器都做得很窄（如 4 bit / 2 bit），并让 MixColumns 的乘法器组合复用（一个 xtime 函数或一个共享的组合块），不要生成 4 份独立乘法阵列。

- MixColumns 也可写成对 4 个 32-bit 列并行一个组合函数；注意每列内只用一份 xtime 逻辑。
- ShiftRows 只做位选，不引入加法器。
- 除 128-bit `state`、128-bit 轮密钥、128-bit `subst` 外，不要保存其它宽的中间量（不要保存 11 组轮密钥）。

## 综合兼容性（必须遵守）

- 只用 Yosys 支持的写法：`logic`、`always_ff`、`always_comb`、`function`、`localparam`、`typedef enum`；不要 class/interface/assertion/动态数组/`$readmemh`。
- 函数体内不要用 `return`，用 Verilog-2005 风格给函数名赋值。
- 综合工具会产生 SYNTH FAILED 的写法一律不要用；`for` 循环仅在 `always_comb` 中对固定范围使用时才可接受（生成组合逻辑），否则用手写展开。

再强调：输出只有一个 ```systemverilog 代码块，模块名 aes128，端口与上面完全一致，四个 S-box 分时复用。
