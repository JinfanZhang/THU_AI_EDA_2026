"""Tester 报告的压缩包（failure_packet）。

原始 ``test_report.json`` 可能有上万行 stdout / trace；Diagnoser 只需要能定位根因
的那几个证据。这里把它压成一段几百到两千字的 packet，并保留对原始报告的引用，
让下游可以按需回查，而不是把整份报告重新塞进 Prompt。
"""

from __future__ import annotations

import hashlib
import re
from datetime import datetime, timezone
from typing import Any

from ai_eda.agent.reporting import report_summary, stage_label

SCHEMA_VERSION = "failure_packet/1"
MAX_CHECKS = 10
MAX_LOG_CHARS = 2500

_STOPWORDS = {
    "the", "and", "for", "with", "from", "that", "this", "test", "tests",
    "check", "checks", "expected", "actual", "case", "cases", "pass", "passed",
    "fail", "failed", "simulation", "compile", "waiting",
}


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _tokens(text: str) -> list[str]:
    words = re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", text.lower())
    return [word for word in dict.fromkeys(words) if word not in _STOPWORDS]


def _first_deviation(report: dict[str, Any]) -> str | None:
    """trace 里第一处 expected/actual 不一致——最接近根因的快速证据。"""
    for row in report.get("trace") or []:
        if not isinstance(row, dict):
            continue
        differences = []
        for key, value in row.items():
            if not key.startswith("expected_"):
                continue
            actual_key = key.removeprefix("expected_")
            actual = row.get(actual_key, row.get(f"out_{actual_key}"))
            if actual is not None and str(actual) != str(value):
                differences.append(f"{actual_key}={actual} (expected {value})")
        if differences:
            label = row.get("event") or row.get("case") or "sample"
            return f"cycle {row.get('cycle', '?')} · {label}: " + "; ".join(differences)
    return None


def _candidate_modules(
    report: dict[str, Any], files: dict[str, str], plan: dict[str, Any]
) -> list[dict[str, Any]]:
    """用失败检查里的词去和文件名做词面匹配，只给候选，不给结论。"""
    evidence_parts = [str(report.get("stage") or "")]
    for check in report.get("checks") or []:
        evidence_parts.append(str(check.get("name") or ""))
        evidence_parts.append(str(check.get("detail") or ""))
    evidence_tokens = set(_tokens(" ".join(evidence_parts)))

    top_module = str(plan.get("top_module") or "")
    ranked: list[dict[str, Any]] = []
    for path in files:
        stem = path.rsplit("/", 1)[-1]
        if stem.endswith(".sv"):
            stem = stem[:-3]
        hits = evidence_tokens & set(_tokens(stem))
        reasons = []
        if hits:
            reasons.append("名称命中 " + ", ".join(sorted(hits)))
        if top_module and stem == top_module:
            reasons.append("顶层模块")
        ranked.append(
            {
                "path": path,
                "score": len(hits) + (2 if top_module and stem == top_module else 0),
                "reason": "；".join(reasons) or "同项目文件",
            }
        )
    ranked.sort(key=lambda item: -item["score"])
    return ranked[:6]


def build_failure_packet(
    *,
    run_id: str,
    attempt: int,
    project_id: str,
    report: dict[str, Any],
    plan: dict[str, Any],
    files: dict[str, str],
    references: dict[str, str],
) -> dict[str, Any]:
    """把一份 Tester 报告压成 Diagnoser 的输入。"""
    checks = []
    for item in (report.get("checks") or [])[:MAX_CHECKS]:
        if not isinstance(item, dict):
            continue
        checks.append(
            {
                "name": str(item.get("name") or ""),
                "detail": str(item.get("detail") or "")[:400],
            }
        )

    failing_suites = [
        item.get("name")
        for item in (report.get("test_suites") or [])
        if item.get("name") and not item.get("passed") and not item.get("skipped")
    ]

    stage = str(report.get("stage") or "")
    raw_log = ""
    if stage == "compile":
        raw_log = str(report.get("stderr") or "") + "\n" + str(report.get("stdout") or "")
    else:
        raw_log = str(report.get("stdout") or "")
    log_excerpt = raw_log.strip()[-MAX_LOG_CHARS:]

    inventory = [
        {
            "path": path,
            "bytes": len(content.encode("utf-8")),
            "sha256": sha256_text(content)[:16],
        }
        for path, content in sorted(files.items())
    ]

    return {
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "attempt": attempt,
        "project_id": project_id,
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "stage": stage,
        "stage_label": stage_label(stage),
        "passed": bool(report.get("passed")),
        "summary": report_summary(report),
        "failed_checks": checks,
        "failed_check_count": len(report.get("checks") or []),
        "first_deviation": _first_deviation(report),
        "failing_suites": failing_suites[:8],
        "log_excerpt": log_excerpt,
        "candidate_modules": _candidate_modules(report, files, plan),
        "file_inventory": inventory,
        "references": dict(references),
    }


def packet_to_prompt(packet: dict[str, Any]) -> str:
    """把 packet 渲染成给模型的紧凑文本（避免直接 dump 整个 JSON）。"""
    lines = [
        f"失败阶段：{packet.get('stage_label')}（{packet.get('stage')}）",
        f"结论：{packet.get('summary')}",
    ]
    deviation = packet.get("first_deviation")
    if deviation:
        lines.append(f"首个偏差：{deviation}")
    checks = packet.get("failed_checks") or []
    if checks:
        lines.append(f"失败检查（共 {packet.get('failed_check_count')} 项，列出 {len(checks)} 项）：")
        lines.extend(f"- {item['name']}: {item['detail']}" for item in checks)
    suites = packet.get("failing_suites") or []
    if suites:
        lines.append("失败测试组：" + ", ".join(str(item) for item in suites))
    candidates = packet.get("candidate_modules") or []
    if candidates:
        lines.append("候选模块（按词面命中排序，仅为线索）：")
        lines.extend(f"- {item['path']}：{item['reason']}" for item in candidates)
    log = packet.get("log_excerpt")
    if log:
        lines.append("日志片段（尾部）：")
        lines.append(log)
    return "\n".join(lines)
