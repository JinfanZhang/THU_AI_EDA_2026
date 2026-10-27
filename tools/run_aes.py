#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AES 作业运行器：在教师 TB/PPA 流程外包一层，补记 token 用量与墙钟耗时。

用法：
    .venv/bin/python tools/run_aes.py --prompt homework/H1_custom_area.md --run-id aes-r2 \
        --max-tokens 60000 --thinking --reasoning-effort low

教师 TB、综合与功耗评估全部调用 ai_eda.rtl.runner 的原始实现，本脚本只负责
生成、计时、记录 usage 和落盘，不修改任何教师材料。
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ai_eda.config import PROJECT_ROOT, PROMPTS_ROOT, TASKS_ROOT
from ai_eda.model.client import ModelClient
from ai_eda.rtl.runner import save_generation_run, save_report, test_rtl

TASK = "homework_aes128"
TB_TOP = "tb_homework_aes128"
POWER_TB_TOP = "tb_power_homework_aes128"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", required=True, help="相对路径以 content/prompts/ 为根目录")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--max-tokens", type=int, default=60000)
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--thinking", action="store_true")
    parser.add_argument("--reasoning-effort", choices=("low", "high", "max"), default="high")
    parser.add_argument("--timeout-seconds", type=int, default=20)
    args = parser.parse_args()

    task_dir = TASKS_ROOT / TASK
    prompt_path = Path(args.prompt)
    if not prompt_path.is_absolute():
        prompt_path = PROMPTS_ROOT / prompt_path
    prompt_text = prompt_path.read_text(encoding="utf-8")

    client = ModelClient(
        temperature=args.temperature,
        max_tokens=args.max_tokens,
        thinking=args.thinking,
        reasoning_effort=args.reasoning_effort,
    )

    started = time.time()
    response = client.generate_once_detail(prompt_text)
    elapsed = time.time() - started

    run_dir = save_generation_run(
        task_name=TASK,
        spec_path=task_dir / "spec.md",
        testbench_path=task_dir / "tb.sv",
        testbench_top=TB_TOP,
        prompt_path=prompt_path,
        run_id=args.run_id,
        raw_response=response["answer"] or "",
        reasoning=response.get("reasoning"),
        temperature=args.temperature,
        max_tokens=args.max_tokens,
        thinking=args.thinking,
        reasoning_effort=args.reasoning_effort,
        timeout_seconds=args.timeout_seconds,
        finish_reason=response.get("finish_reason"),
        usage=response.get("usage"),
    )

    meta_path = run_dir / "metadata.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta["elapsed_seconds"] = round(elapsed, 1)
    meta["tested"] = True
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    report = test_rtl(
        task_name=TASK,
        testbench_path=task_dir / "tb.sv",
        testbench_top=TB_TOP,
        rtl_path=run_dir / "generated.sv",
        power_testbench_path=task_dir / "power_tb.sv",
        power_testbench_top=POWER_TB_TOP,
        timeout_seconds=args.timeout_seconds,
        run_dir=run_dir,
        rtl_top_module="aes128",
    )
    save_report(run_dir, report)

    metrics = report.get("metrics") or {}
    summary = {
        "run_id": args.run_id,
        "run_dir": str(run_dir.relative_to(PROJECT_ROOT)),
        "passed": report.get("passed"),
        "stage": report.get("stage"),
        "elapsed_seconds": round(elapsed, 1),
        "usage": response.get("usage"),
        "finish_reason": response.get("finish_reason"),
        "area": metrics.get("area"),
        "total_power_w": metrics.get("total_power_w"),
        "checks": report.get("checks"),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if report.get("passed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
