# 运行证据（evidence）

这些是从本地 `runs/` 里挑出来的关键 artifact，随代码一起提交，便于助教按报告里的路径核对数值。
完整运行记录（含 VCD、逐节点 events.json、每个 agent 的 context.json）在本地 `runs/` 下，
`runs/` 已被 `.gitignore` 忽略，不随仓库提交。

## 作业一：AES-128（`homework1/`）

| 目录 | 说明 | 教师 TB | tokens | 耗时 | 面积 | 总功耗 |
|---|---|---|---|---|---|---|
| `aes-r0` | 基线 Prompt（16 S-box 并行） | PASS | 21,472 | 78.3 s | 35739.54 | 38.4 mW |
| `aes-r1` | 基线 Prompt（早期运行，CLI 未记录 usage） | PASS | — | — | 33891.44 | 36.7 mW |
| `aes-r2` | 面积版 Prompt（4 S-box）样本 1 | PASS | 31,536 | 121.5 s | 18821.28 | 5.07 mW |
| `aes-r3` | 面积版 Prompt（4 S-box）样本 2 | PASS | 32,028 | 118.7 s | 18933.91 | 5.82 mW |
| `aes-r4` | 极限面积 Prompt（2 S-box），复位语义失败 | FAIL | 29,346 | 124.2 s | 16018.62* | 3.85 mW* |
| `aes-r5` | 极限面积 Prompt + 复位约束（**最终采用**） | PASS | 26,268 | 102.8 s | 17918.34 | 4.14 mW |

\* 功能未通过，按课程口径不参与 PPA 比较，仅作为失败样本保留。

每个目录含 `generated.sv`（模型产出的 RTL）、`test_report.json`（教师 TB + Yosys/OpenSTA 结果）、
`metadata.json`（模型参数、prompt/response 哈希、usage、墙钟时间）。

## 作业二：Agent 重构（`homework2/`）

| 目录 | 说明 |
|---|---|
| `agent-20261027T063325150845` → 见 `baseline-*` | 重构前（Modifier 全量上下文） |
| `agent-20261027T061341516969` | 重构后、未注入 RV32I 战术提示：8 轮修复未收敛（FAIL 样本） |
| `agent-20261027T062821480190` | 重构后 + 提示，独立完整生成（**最终采用**） |
| `agent-20261027T062632716917` | 从失败点续跑：1 轮修复即通过 |
| `agent-20261030T113852691789` | 同配置复跑（10-30）：8 轮修复仍未收敛（FAIL），用于说明生成方差；该次的 artifact 带完整追溯字段 |

每个目录含 `run_summary.json`（模型参数、调用次数、tokens、墙钟时间、修复轮次）、
`tester-*/test_report.json`（教师 TB 的 checks/trace/metrics）、`artifacts/`
（`failure_packet_attempt*.json`、`repair_brief_attempt*.json`、`rtl_manifest_attempt*.json`、`plan.json`）、
以及最终的 `rtl/*.sv`。

### artifact 追溯字段

- `failure_packet_attempt*.json`：`schema_version`、`run_id`、`attempt`、`project_id`、`created_at`、
  `first_deviation`、`failed_checks`、`log_excerpt`、`candidate_modules`，以及
  `file_inventory`（每个文件的 `bytes` 与 `sha256`）。
- `repair_brief_attempt*.json`：`schema_version`、`run_id`、`attempt`、`created_at`、`hypothesis`、
  `confidence`、`files`、`symbols`、`constraints`、`verification_targets`、`packet_ref`、`report_ref`。
- `rtl_manifest_attempt*.json`：`schema_version`、`run_id`、`attempt`、`created_at`，
  每个文件带 `path`、`artifact` 引用、`bytes` 与 `sha256`。

原始 `test_report.json` 始终以 artifact 形式保留，packet 只引用不复制，保证可回查。

`baseline-*` 目录来自原始课程代码的 git worktree（同一模型、同一参数、同一教师 TB），
因此没有 `run_summary.json`，token 统计在 `events.json` 里；它的 artifact 是旧版 Modifier 生成的，不带上述追溯字段。
