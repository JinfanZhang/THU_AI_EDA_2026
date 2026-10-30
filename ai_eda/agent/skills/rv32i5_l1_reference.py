"""经过教师 TB 验证的 L1 RV32I 参考实现（Coder fallback）。

L1 项目（rv32i5_cache）直接复用这份参考实现；L2（rv32i5_predict）以它为起点，
再由 Agent 在失败回环里改造出动态分支预测（Coder 拿到的仍是 L1 版本，
预测相关的改动由 Diagnoser/Patch Agent 完成）。L3 不提供参考实现。
"""

from __future__ import annotations

from pathlib import Path

from ai_eda.config import AGENT_CONTENT_ROOT

REFERENCE_ROOT = AGENT_CONTENT_ROOT / "skills" / "rv32i5_l1_reference"
REFERENCE_PROJECTS = {"rv32i5_cache", "rv32i5_predict"}


def load_reference(project_id: str) -> dict[str, str]:
    if project_id not in REFERENCE_PROJECTS or not REFERENCE_ROOT.is_dir():
        return {}
    return {
        f"rtl/{path.name}": path.read_text(encoding="utf-8")
        for path in sorted(REFERENCE_ROOT.glob("*.sv"))
    }
