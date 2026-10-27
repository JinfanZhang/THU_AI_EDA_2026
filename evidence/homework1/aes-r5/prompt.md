你是一名数字 IC 设计工程师。请用 SystemVerilog 实现一个**极限面积优先**的单模块 AES-128 加密核：一次生成就要通过 iverilog -g2012 仿真与 Yosys 综合，并且在 200 周期延迟上限内只用 **2 个** S-box 实例。

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
5. 从接收 start 的沿到 done 为高的沿，**不超过 200 个时钟周期**（本设计的预算约 130 拍）。
6. `done=0` 时 ciphertext 可任意值。

## 复位期间输出必须干净（上一版在这里翻车，务必照做）

- `ready` 直接用组合逻辑给出：寄存器只维护一个 `busy`（1 表示正在加密），`always_comb ready = ~busy;`。`busy` 在复位分支里清 0，这样复位期间 `ready` 必然是 1，不会出现 X。
- `done` 也只在复位分支和正常完成分支里赋值；复位时清 0。不要用未初始化的寄存器拼 `ready`/`done`。
- 教师 TB 在 `rst_n=0` 的四个上升沿之后立刻检查 `ready===1 && done===0`，任何 X 都会被判失败。
- 其余状态寄存器同样在 `always_ff` 的 `if (!rst_n)` 分支里一起清零。

## 目标架构（2 个 S-box 分时复用，必须照此实现）

面积最小的关键是：**只综合出 2 个 S-box 实例**。写一个 `function automatic logic [7:0] sbox(input logic [7:0] a)`，内部 `case` 覆盖 0..255，**用给函数名赋值返回，禁止 `return`**（Yosys 前端不支持）。整个模块里这个函数只在两个位置被调用两次。

状态机按轮推进，每轮分三段：

1. **KEY 段（2 拍）**：对当前轮密钥最后一字 `w3` 做 `RotWord` 后，用 2 个 S-box 每拍替换 2 个字节，两拍凑齐 `SubWord(RotWord(w3))`，再与 Rcon 异或得 temp；组合出新的 4 个字（w4=w0^temp, w5=w1^w4, w6=w2^w5, w7=w3^w6），寄存为 128-bit 新轮密钥。第 10 轮后无需再扩展。
2. **SUB 段（8 拍）**：每拍把当前 state 的 **2 个字节**各过一次 sbox，写入 128-bit 的 `subst` 寄存器；8 拍填满 16 字节。
3. **MIX 拍（1 拍）**：对 `subst` 做 ShiftRows（纯连线置换），第 1–9 轮再做 MixColumns 并异或新轮密钥；第 10 轮只异或轮密钥。结果写回 `state`。

一轮 11 拍，10 轮约 110 拍，加初始与收尾仍远低于 200 拍上限。

- 寄存器只保留 128-bit `state`、128-bit 轮密钥、128-bit `subst`，以及很窄的轮/段/Rcon 计数器（4 bit / 3 bit 级）。不要保存 11 组轮密钥。
- MixColumns 用一个共享的组合块，一个 xtime 函数复用，不要生成多份乘法阵列。
- 两个 S-box 的输入用组合 mux 选择（来自 state 还是来自 `w3`），不要再多复制实例。

## 综合兼容性（必须遵守）

- 只用 Yosys 支持的写法：`logic`、`always_ff`、`always_comb`、`function`、`localparam`、`typedef enum`；不要 class/interface/assertion/动态数组/`$readmemh`。
- 函数体内不要用 `return`，用 Verilog-2005 风格给函数名赋值。
- `for` 循环只在 `always_comb` 中对固定小范围展开使用，其余手写展开。

再强调：输出只有一个 ```systemverilog 代码块，模块名 aes128，端口与上面完全一致，**只有 2 个 S-box 实例**。
