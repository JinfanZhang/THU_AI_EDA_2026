"""Patch Agent：只拿诊断简报和点名的文件，产出完整修复文件。

和原来的 Modifier 不同，这里不再携带完整 Spec、整份 Plan、全部 RTL 和原始失败
报告，也不保留跨轮对话历史：每一轮只看 repair_brief、被点名模块的接口契约，以及
这些文件的当前内容。
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .base import SubAgent
from .common import extract_json_payload, safe_project_path, validate_modifier_files
from .rv32i_hints import checklist_for

PATCH_SYSTEM_PROMPT = """You are the Patch Agent of a digital IC design agent.
You receive ONLY: a repair brief from the Diagnoser, the interface contract of the named modules, and the current content of those files.

Your job:
- Implement the single root-cause fix described in the brief.
- Return complete file contents for the files you change (no diffs, no fragments).
- You may only touch files named in brief.files. Never rename ports, modules or files.
- Keep every constraint in brief.constraints intact; do not weaken or delete checks, do not fake debug/feature flags, never modify the teacher TB.
- Do not add external IP, simulation-only constructs, or new modules that the plan does not contain.
- If the brief looks wrong, still apply the most defensible minimal fix and explain the deviation in notes.
- The returned content MUST differ from the current content. Returning an unchanged file is an invalid patch.
- Return ONLY a JSON object, no Markdown fences, no prose outside JSON.

Return schema:
{"files": [{"path": "rtl/example.sv", "content": "complete SystemVerilog file"}], "notes": "what changed and which verification target it should flip"}
"""


def _interfaces_block(plan: dict[str, Any], files: list[str]) -> str:
    lines = []
    for module in plan.get("modules") or []:
        if isinstance(module, dict) and module.get("file") in files:
            lines.append(f"{module.get('name')} ({module.get('file')}):")
            lines.append(str(module.get("interfaces") or "").strip()[:2000])
    return "\n".join(lines) or "（计划中没有匹配的模块）"


class PatchAgent(SubAgent):
    name = "patcher"
    title = "06 · Patch Agent"
    node_type = "patcher"

    # 补丁阶段关掉思考：输出预算全部留给完整 RTL 文件。
    MODEL_OPTIONS = {"thinking": False}

    def run(
        self,
        brief_handoff: Path,
        *,
        attempt: int,
        file_refs: dict[str, str],
    ) -> Path:
        incoming = self.runtime.read_handoff(brief_handoff)["payload"]
        artifacts = incoming.get("artifacts") or {}
        brief_ref = artifacts.get("repair_brief")
        plan_ref = artifacts.get("plan")
        spec_ref = artifacts.get("spec")
        if not all(isinstance(ref, str) for ref in (brief_ref, plan_ref, spec_ref)):
            raise ValueError("Diagnoser → Patch 的 handoff 缺少 artifact")

        brief = self.runtime.read_json_artifact(brief_ref)
        plan = self.runtime.read_json_artifact(plan_ref)
        if not isinstance(brief, dict) or not isinstance(plan, dict):
            raise ValueError("Patch Agent 输入格式无效")

        allowed = [path for path in brief.get("files") or [] if path in file_refs]
        if not allowed:
            raise ValueError("repair brief 点名的文件不在当前工程中")

        current = {
            path: self.runtime.read_text_artifact(file_refs[path]) for path in allowed
        }

        prompt = "\n\n".join(
            [
                f"第 {attempt} 轮补丁，只改下面点名的文件。",
                "## repair brief\n"
                + json.dumps(
                    {
                        "hypothesis": brief.get("hypothesis"),
                        "confidence": brief.get("confidence"),
                        "files": allowed,
                        "symbols": brief.get("symbols") or [],
                        "constraints": brief.get("constraints") or [],
                        "verification_targets": brief.get("verification_targets") or [],
                        "rejected_hypotheses": brief.get("rejected_hypotheses") or [],
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
                "## 接口契约（不得改动）\n" + _interfaces_block(plan, allowed),
                "## 当前文件内容\n"
                + json.dumps(current, ensure_ascii=False, indent=2),
                "返回 JSON：{\"files\":[{\"path\":...,\"content\":...}],\"notes\":\"...\"}，"
                f"路径只能是：{', '.join(allowed)}",
            ]
        )

        event = self.runtime.begin_event(
            "patcher", self.node_type, f"{self.title} · Round {attempt}", prompt, attempt
        )

        payload: dict[str, Any] = {}
        changed: dict[str, str] = {}
        last_error: ValueError | None = None
        messages = [
            {
                "role": "system",
                "content": PATCH_SYSTEM_PROMPT
                + "\n\n"
                + checklist_for(self.runtime.options.get("project")),
            },
            {"role": "user", "content": prompt},
        ]
        for parse_attempt in range(1, 3):
            if parse_attempt > 1:
                messages.append(
                    {
                        "role": "user",
                        "content": (
                            f"上一次输出不能作为有效补丁（{last_error}）。"
                            "请重新对照 brief 的根因假设和当前文件内容，作出真正的修改；"
                            "只输出一个 JSON 对象，包含 files 数组和 notes。"
                        ),
                    }
                )
            result = self.runtime.call_model_messages(
                event, messages, model_options=self.MODEL_OPTIONS
            )
            answer = result.get("answer") or ""
            messages.append({"role": "assistant", "content": answer})
            try:
                payload = extract_json_payload(answer)
                candidates = validate_modifier_files(payload, plan)
                outside = [path for path in candidates if path not in allowed]
                if outside:
                    raise ValueError(f"补丁越界修改了未点名的文件：{outside}")
                changed = {
                    path: content
                    for path, content in candidates.items()
                    if content != current.get(path)
                }
                if not changed:
                    raise ValueError(
                        "补丁内容与当前文件完全相同，没有产生任何修改；必须换一种修复策略"
                    )
                last_error = None
                break
            except ValueError as error:
                last_error = error
                event["patcher_validation_error"] = str(error)

        if last_error is not None:
            raise ValueError(f"Patch Agent 未产出有效补丁：{last_error}") from last_error

        for relative, content in changed.items():
            target = safe_project_path(self.runtime.run_dir, relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            artifact_dir = self.runtime.run_dir / f"step-{event['step']:02d}-{event['node_id']}"
            artifact_dir.mkdir(parents=True, exist_ok=True)
            (artifact_dir / "generated.sv").write_text(content, encoding="utf-8")

        notes = str(payload.get("notes") or "")[:1000]
        updated_refs = dict(file_refs)
        for relative, content in changed.items():
            updated_refs[relative] = self.runtime.artifact_ref(
                safe_project_path(self.runtime.run_dir, relative)
            )

        entries = []
        for path, ref in sorted(updated_refs.items()):
            if path in changed:
                size = len(changed[path].encode("utf-8"))
            else:
                size = len(self.runtime.read_text_artifact(ref).encode("utf-8"))
            entries.append({"path": path, "artifact": ref, "bytes": size})
        next_manifest_ref = self.runtime.write_json_artifact(
            f"rtl_manifest_attempt{attempt}.json",
            {"schema_version": "rtl_manifest/2", "attempt": attempt, "files": entries},
        )

        self.save_context(
            attempts=int(self.context.get("attempts", 0)) + 1,
            plan_ref=plan_ref,
            rtl_manifest_ref=next_manifest_ref,
            brief_ref=brief_ref,
            changed_paths=sorted(changed),
        )
        self.finish(
            event,
            "info",
            response=f"修改了 {len(changed)} 个文件：" + "、".join(sorted(changed)),
            reasoning=event.get("reasoning"),
            usage=event.get("usage"),
            changed_paths=sorted(changed),
            notes=notes,
        )
        return self.runtime.write_handoff(
            "patcher",
            "tester",
            {
                "attempt": attempt,
                "changed_paths": sorted(changed),
                "notes": notes,
                "artifacts": {
                    "spec": spec_ref,
                    "plan": plan_ref,
                    "rtl_manifest": next_manifest_ref,
                    "repair_brief": brief_ref,
                },
            },
            attempt=attempt,
            label="Patch Agent → Tester: updated RTL manifest",
        )
