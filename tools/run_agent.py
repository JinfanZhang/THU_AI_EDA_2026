#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Agent 流水线的命令行入口（不依赖网页）。

作业二用它跑 L0：每次运行的 artifact、token 用量和耗时都会落在
runs/agent/<run_id>/ 下，run_summary.json 汇总一次完整运行的成本。

    .venv/bin/python tools/run_agent.py --project rv32i5 --max-repair-attempts 8
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ai_eda.agent.orchestrator import run_agent
from ai_eda.model.client import ModelClient

DEFAULT_SUPPLEMENT = (
    "Spec 已足够实现：请严格按 Spec 的端口、时序和验收条件实现；"
    "Spec 未明确的内部实现细节由 Planner/Coder 决定，不要为此暂停。"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="rv32i5")
    parser.add_argument("--max-tokens", type=int, default=60000)
    parser.add_argument("--max-calls", type=int, default=100)
    parser.add_argument("--max-repair-attempts", type=int, default=8)
    parser.add_argument("--reasoning-effort", choices=("low", "high", "max"), default="low")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--planner-skill", action="store_true")
    parser.add_argument("--resume-from")
    parser.add_argument("--model", default=None, help="覆盖课程默认模型，例如 deepseek-v4-pro")
    parser.add_argument("--log", default="agent_run.log")
    args = parser.parse_args()

    if args.model:
        ModelClient.MODEL_NAME = args.model
    log_path = Path(args.log)
    started = time.time()

    def log(line: str) -> None:
        stamp = time.strftime("%H:%M:%S")
        text = f"[{stamp}] {line}"
        print(text, flush=True)
        with log_path.open("a", encoding="utf-8") as handle:
            handle.write(text + "\n")

    def on_event(event: dict) -> None:
        status = event.get("status")
        if status in {"running", "streaming"}:
            return
        node = event.get("node_id")
        attempt = event.get("attempt")
        usage = event.get("usage") or {}
        duration = event.get("duration_ms")
        log(
            f"{node} attempt={attempt} status={status} "
            f"duration={duration}ms tokens={usage.get('total_tokens')}"
        )

    def request_input(request: dict) -> str:
        log("Parser 要求补充 Spec：" + json.dumps(request, ensure_ascii=False)[:400])
        log("自动回复默认补充，继续流程。")
        return DEFAULT_SUPPLEMENT

    log(f"开始运行 project={args.project} max_tokens={args.max_tokens} "
        f"max_calls={args.max_calls} repairs={args.max_repair_attempts}")

    result = run_agent(
        thinking=True,
        reasoning_effort=args.reasoning_effort,
        temperature=args.temperature,
        max_tokens=args.max_tokens,
        max_calls=args.max_calls,
        max_repair_attempts=args.max_repair_attempts,
        planner_skill=args.planner_skill,
        resume_from=args.resume_from,
        project_id=args.project,
        on_event=on_event,
        request_input=request_input,
    )

    inner = result.get("result") or {}
    passed = bool(inner.get("passed"))
    log(f"结束：passed={passed} stage={inner.get('stage')} "
        f"tester_attempts={inner.get('tester_attempts')} "
        f"wall={round(time.time() - started, 1)}s")
    print(json.dumps(
        {
            "run_id": result.get("run_id"),
            "status": result.get("status"),
            "passed": passed,
            "stage": inner.get("stage"),
            "tester_attempts": inner.get("tester_attempts"),
            "metrics": inner.get("metrics"),
            "cpu_capability": inner.get("cpu_capability"),
            "test_suites": inner.get("test_suites"),
            "performance": inner.get("performance"),
        },
        ensure_ascii=False,
        indent=2,
        default=str,
    ))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
