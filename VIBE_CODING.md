# Vibe Coding 日志（作业过程）

> 记录每一步的意图、结果和踩到的坑，便于复现与追溯。所有数值都能在 `evidence/` 或本地 `runs/` 里核对。

## 一、环境与工具链

- WSL Ubuntu 24.04 + Python 3.12，iverilog 12.0 / Yosys 0.33 / OpenSTA 3.1.0（CUDD 3.0.0 自编译到 `~/.local`）。
- 教师 Spec、教师 TB、功耗脚本、评分流程一律不改，只写 RTL 与 Agent 侧代码。

## 二、作业一：AES-128 Prompt

1. 写基线 Prompt（16 个 S-box 并行、单轮一拍的迭代结构），跑通教师 TB：面积 35739.54、38.4 mW。
2. 把「面积由 S-box 实例数决定」写进 Prompt，改成 4 个 S-box 分时复用，独立跑两次：
   18821.28 / 5.07 mW、18933.91 / 5.82 mW（两次都过 TB，说明方向稳定）。
3. 加码到 2 个 S-box：第一次生成面积 16018.62 更小，但复位期间 `ready` 为 X，教师 TB 判失败。
   **这一步暴露的是 Prompt 缺口，不是模型能力问题**——补上「ready 用组合逻辑、busy 复位清零」的约束后重跑，17918.34 / 4.14 mW 通过。
4. 失败样本（aes-r4）没有删除，作为「更小面积但功能不对」的反面证据留在 `evidence/homework1/aes-r4/`。

## 三、作业二：Agent 重构

1. 先读旧 Modifier：它把 45k 字符 Spec、整份 Plan、全部 RTL 和原始失败报告一起塞进多轮对话，越修越重。
2. 设计两段式修复链：
   - 工具步骤：`test_report.json` → `failure_packet.json`（首个偏差、失败检查、日志尾部、候选模块，约 2 KB）；
   - Diagnoser：只读 packet + 相关 Spec 片段 + 候选接口 → `repair_brief.json`（根因假设、文件、约束、验证目标）；
   - Patch Agent：只读简报 + 点名文件 → 完整替换文件，重建 `rtl_manifest.json` 后回 Tester。
3. 第一次跑 L0：8 轮修复仍未收敛（`agent-20261027T061341516969`），失败集中在 load-use 之后的寄存器值与 DMEM 写事务。
   复盘结论：压缩上下文解决了「信息过载」，但没解决「领域知识缺口」。
4. 于是给 Diagnoser / Patch Agent 注入一份 RV32I 战术提示（load-use、前递优先级、x0、ECALL 提交、复位语义），
   再独立跑一次：3 次 Tester、2 轮修复通过，修复阶段 48,859 tokens（重构前 83,456）。
5. 从失败点续跑只需 1 轮修复（23,723 tokens、53.6 s），验证了「失败证据被压缩、可引用」的价值。
6. 重构前后的对比都在同一模型（deepseek-flash）、同一参数、同一教师 TB 下进行；失败样本与 baseline 都保留。

## 四、踩坑记录

- AES：Yosys 不支持函数体内的 `return`，Prompt 里必须提前禁止；`$readmemh` 也会导致综合失败。
- AES：`done` 必须恰好一拍，且 `done` 后下一拍要能满足背靠背 `start`。
- Agent：handoff 只能传 artifact 引用，不能复制大文本，否则又会回到「全量上下文」。
- 工程：`runs/` 与 `.api_key` 已在 `.gitignore` 中；提交前用 `git status` 确认没有密钥、虚拟环境和运行记录被带进去。
