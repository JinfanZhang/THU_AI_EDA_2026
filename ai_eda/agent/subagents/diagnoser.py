"""Diagnoser 子 Agent：只读压缩后的失败证据，产出可交接的修复简报。

它不写 RTL，也不看完整工程。输入是 failure_packet + 相关 Spec 片段 + 候选模块的
接口契约；输出是 repair_brief.json（根因假设、置信度、相关文件/符号、不可破坏的
约束、验证目标）。Patch Agent 只拿这份简报和点名的文件干活。
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .base import SubAgent
from .common import extract_json_payload, safe_project_path
from .failure_packet import packet_to_prompt
from .rv32i_hints import checklist_for

DIAGNOSER_SYSTEM_PROMPT = """You are the Repair Diagnoser of a digital IC design agent.
You do NOT write or modify RTL. Your only product is a compact repair brief that a separate Patch Agent will act on.

You receive:
1. a failure_packet: the compressed evidence from one Tester run (stage, first deviation, failed checks, failing suites, log tail, candidate modules, file inventory);
2. an excerpt of the frozen spec relevant to the failure;
3. the interface contract of the candidate modules;
4. the repair history (previous hypotheses and whether they were applied).

Your job:
- Form ONE root-cause hypothesis that explains the majority of failed checks, not just the first one.
- If the previous hypotheses were already applied and the same checks still fail, reject them and propose a genuinely different root cause.
- Name only the files that truly need changes (1-3). Do not name the whole project.
- Give the constraint list the Patch Agent must not break (port names, handshake timing, reset semantics, module boundaries).
- Give concrete verification targets: which checks must flip to pass, and what value is expected.

Rules:
- Never propose changing the teacher TB, the spec, or the scoring scripts.
- Never propose hardcoding test vectors or faking debug/feature flags.
- Prefer the smallest root cause that is consistent with the evidence.
- Return ONLY a JSON object, no Markdown fences, no prose outside JSON.

Return schema:
{"hypothesis": "one paragraph describing the root cause and the mechanism", "confidence": "high|medium|low", "files": ["rtl/example.sv"], "symbols": ["signal_or_state_names"], "constraints": ["..."], "verification_targets": ["..."], "rejected_hypotheses": ["..."]}
"""

MAX_SPEC_EXCERPT = 6000
MAX_HISTORY = 6


def _spec_excerpt(spec: str, packet: dict[str, Any]) -> str:
    """按失败证据里的词去选 Spec 段落，避免把 45k 字符整份塞进去。"""
    keywords = set()
    for item in packet.get("candidate_modules") or []:
        stem = str(item.get("path") or "").rsplit("/", 1)[-1].removesuffix(".sv")
        keywords.update(part for part in re.split(r"[_\-]", stem) if len(part) > 2)
    for item in packet.get("failed_checks") or []:
        keywords.update(re.findall(r"[A-Za-z_][A-Za-z0-9_]{3,}", str(item.get("name") or "")))
    keywords = {word.lower() for word in keywords} - {"test", "check", "core", "module", "rtl"}

    paragraphs = [block.strip() for block in re.split(r"\n\s*\n", spec) if block.strip()]
    scored = []
    for index, block in enumerate(paragraphs):
        lower = block.lower()
        hits = sum(1 for word in keywords if word in lower)
        scored.append((hits, index, block))

    chosen: list[tuple[int, str]] = []
    head = "\n\n".join(paragraphs[:3])[:1800]
    if head:
        chosen.append((0, head))
    for hits, index, block in sorted(scored, key=lambda row: (-row[0], row[1])):
        if hits <= 0:
            break
        chosen.append((index, block))
        if sum(len(text) for _, text in chosen) >= MAX_SPEC_EXCERPT:
            break
    text = "\n\n".join(block for _, block in chosen)
    return text[:MAX_SPEC_EXCERPT]


def _interfaces_block(plan: dict[str, Any], files: list[str]) -> str:
    lines = []
    for module in plan.get("modules") or []:
        if not isinstance(module, dict):
            continue
        if module.get("file") not in files:
            continue
        lines.append(f"{module.get('name')} ({module.get('file')}):")
        lines.append(str(module.get("interfaces") or "").strip()[:1800])
    return "\n".join(lines) or "（计划中没有匹配的模块）"


class DiagnoserAgent(SubAgent):
    name = "diagnoser"
    title = "05 · Diagnoser"
    node_type = "diagnoser"

    ALLOWED_CONFIDENCE = {"high", "medium", "low"}

    def run(
        self,
        packet_ref: str,
        *,
        attempt: int,
        spec_ref: str,
        plan_ref: str,
    ) -> Path:
        packet = self.runtime.read_json_artifact(packet_ref)
        plan = self.runtime.read_json_artifact(plan_ref)
        spec = self.runtime.read_text_artifact(spec_ref)
        if not isinstance(packet, dict) or not isinstance(plan, dict):
            raise ValueError("Diagnoser 输入 artifact 格式无效")

        plan_files = [
            module["file"] for module in plan.get("modules") or [] if isinstance(module, dict)
        ]
        candidates = [item["path"] for item in packet.get("candidate_modules") or []
                      if isinstance(item, dict) and item.get("path") in plan_files]

        history = self.context.get("hypotheses") or []
        history = [item for item in history if isinstance(item, dict)][-MAX_HISTORY:]

        prompt = "\n\n".join(
            [
                f"这是同一项目的第 {attempt} 轮修复诊断。",
                "## failure_packet\n" + packet_to_prompt(packet),
                "## 相关 Spec 片段\n" + _spec_excerpt(spec, packet),
                "## 候选模块的接口契约\n" + _interfaces_block(plan, candidates or plan_files[:4]),
                "## 之前的诊断历史（已应用但仍失败，不要重复）\n"
                + (json.dumps(history, ensure_ascii=False, indent=2) if history else "（无，这是第一轮）"),
                "只返回约定的 JSON 对象：hypothesis / confidence / files / symbols / constraints / verification_targets / rejected_hypotheses。"
                f"可修改文件限定在：{', '.join(plan_files)}",
            ]
        )

        event = self.runtime.begin_event(
            "diagnoser", self.node_type, f"{self.title} · Round {attempt}", prompt, attempt
        )
        system_prompt = (
            DIAGNOSER_SYSTEM_PROMPT
            + "\n\n"
            + checklist_for(self.runtime.options.get("project"))
        )
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": prompt},
        ]

        # 模型偶尔会返回截断或带解释的文本；这里像 Patch Agent 一样再要一次严格 JSON。
        payload: dict[str, Any] = {}
        last_error: ValueError | None = None
        for parse_attempt in range(1, 3):
            if parse_attempt > 1:
                messages.append(
                    {
                        "role": "user",
                        "content": (
                            f"上一次输出不是合法 JSON（{last_error}）。"
                            "请只输出一个 JSON 对象：hypothesis / confidence / files / "
                            "symbols / constraints / verification_targets / rejected_hypotheses，"
                            "不要 Markdown 围栏或解释文字。"
                        ),
                    }
                )
            result = self.runtime.call_model_messages(
                event, messages, model_options={"thinking": True}
            )
            answer = result.get("answer") or ""
            messages.append({"role": "assistant", "content": answer})
            try:
                payload = extract_json_payload(answer)
                last_error = None
                break
            except ValueError as error:
                last_error = error
                event["diagnoser_parse_error"] = str(error)
        if last_error is not None:
            raise ValueError(f"Diagnoser 未返回合法 JSON：{last_error}") from last_error

        brief = self._validate(payload, plan_files, packet, packet_ref)

        brief_ref = self.runtime.write_json_artifact(
            f"repair_brief_attempt{attempt}.json", brief
        )
        self.save_context(
            hypotheses=history
            + [{"attempt": attempt, "hypothesis": brief["hypothesis"], "files": brief["files"]}]
        )
        self.finish(
            event,
            "info",
            response=brief["hypothesis"][:400],
            confidence=brief["confidence"],
            files=brief["files"],
            reasoning=event.get("reasoning"),
            usage=event.get("usage"),
            repair_brief=brief_ref,
        )
        return self.runtime.write_handoff(
            "diagnoser",
            "patcher",
            {
                "attempt": attempt,
                "repair_brief": brief,
                "artifacts": {"repair_brief": brief_ref, "spec": spec_ref, "plan": plan_ref},
            },
            attempt=attempt,
            label="Diagnoser → Patch Agent: repair brief",
        )

    def _validate(
        self,
        payload: dict[str, Any],
        plan_files: list[str],
        packet: dict[str, Any],
        packet_ref: str,
    ) -> dict[str, Any]:
        hypothesis = str(payload.get("hypothesis") or "").strip()
        if not hypothesis:
            raise ValueError("Diagnoser 没有给出根因假设")

        confidence = str(payload.get("confidence") or "medium").lower()
        if confidence not in self.ALLOWED_CONFIDENCE:
            confidence = "medium"

        files = [str(item) for item in payload.get("files") or [] if isinstance(item, str)]
        files = [item for item in files if item in plan_files]
        if not files:
            candidates = [item["path"] for item in packet.get("candidate_modules") or []
                          if isinstance(item, dict) and item.get("path") in plan_files]
            files = candidates[:1] or plan_files[:1]
        if not files:
            raise ValueError("Diagnoser 没有可修改的文件")

        def clean_list(value: Any, limit: int, width: int = 240) -> list[str]:
            items = []
            for item in value or []:
                text = str(item).strip()
                if text:
                    items.append(text[:width])
            return items[:limit]

        return {
            "schema_version": "repair_brief/1",
            "run_id": packet.get("run_id"),
            "attempt": packet.get("attempt"),
            "stage": packet.get("stage"),
            "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "hypothesis": hypothesis[:1500],
            "confidence": confidence,
            "files": files[:3],
            "symbols": clean_list(payload.get("symbols"), 12, 80),
            "constraints": clean_list(payload.get("constraints"), 10),
            "verification_targets": clean_list(payload.get("verification_targets"), 10),
            "rejected_hypotheses": clean_list(payload.get("rejected_hypotheses"), 6),
            "packet_ref": packet_ref,
            "report_ref": (packet.get("references") or {}).get("report"),
        }
