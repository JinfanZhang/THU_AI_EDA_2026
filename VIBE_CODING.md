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

## 五、10-30 复跑与追溯字段

- 同一配置（deepseek-flash、thinking low、max_tokens 60000、8 轮修复）复跑一次：`agent-20261030T113852691789`，
  8 轮修复仍未收敛，消耗 435,050 tokens、891.1 s。同一份代码两次结果差别明显 —— RTL 生成方差比预想大，
  因此把失败样本也保留在 `evidence/` 里，不挑好看的提交。
- 按讲义建议，给三类交接 artifact 补上追溯字段：
  - `failure_packet`：`run_id` / `attempt` / `project_id` / `created_at` / 每个文件的 `bytes` 与 `sha256`；
  - `repair_brief`：`run_id` / `attempt` / `created_at` / `packet_ref` / `report_ref`；
  - `rtl_manifest`：`run_id` / `attempt` / `created_at`，逐文件 `path` / `artifact` / `bytes` / `sha256`。
- 原始 `test_report.json` 始终作为 artifact 保存，packet 只引用不复制，保证证据可回查。

## 六、L2 换挡（10-30 晚）

- 按用户要求从 L0 换成 L2：L3 试了三次都不行（Planner 截断、iverilog 语法限制、9 轮编译不过），
  L2 从零生成 9 轮 467k tokens 也停在仿真不停机。
- 转折点：课程自带 L1 参考实现（`content/agent/skills/rv32i5_l1_reference`，教师 TB 验证过）。
  把 Coder 的参考实现 fallback 扩展到 L2，让 Agent 从能跑能停机的 L1 起步，再补预测器。
- 光有参考还不够：第一次参考起步跑了 11 轮、414k tokens，predictor 组始终没实现（base/cache 能过）。
  把 BTB/BHT 的规格（索引 PC[5:2]、tag PC[31:6]、BHT 复位 01、分配规则、误预测判据、dbg 计数）
  写成提示注入 Diagnoser/Patch 后，2 次 Tester、95,474 tokens、201.5 s 通过。
- 期间修了一个自己的 bug：Diagnoser 遇到模型返回非法 JSON 时直接崩，补了两次重试。
- 诚实记录：L2 是“参考实现 + Agent 改造”，不是从零设计；报告、evidence、本日志三处都写明了。
- 跑仿真时全程 `nice -n 19 taskset -c 0,1`，只占两个核、最低优先级，避免影响用户打游戏。
