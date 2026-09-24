"""Offline protocol/captured-response evaluations, or an explicitly opted-in judge."""

import argparse
import asyncio
import json
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--set", choices=["dev", "captured", "judge"], required=True)
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--judgements", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--allow-paid", action="store_true")
    args = parser.parse_args()
    if args.set != "dev":
        return captured(args)
    root = Path(__file__).resolve().parents[5]
    print("Synthetic protocol/security checks only; not a live-model quality or judge report.")
    return subprocess.run(  # noqa: S603 -- fixed interpreter, tests and arguments.
        [
            sys.executable,
            "-m",
            "pytest",
            "apps/backend/tests/test_assistant.py",
            "apps/backend/tests/test_assistant_adversarial.py",
            "apps/backend/tests/test_assistant_evaluation.py",
            "-q",
        ],
        cwd=root,
        check=False,
    ).returncode


def captured(args):
    from farmable_backend.assistant.evaluation import (
        EvaluationSet,
        JudgeBatch,
        JudgePolicy,
        live_judge,
        load,
        report,
    )

    try:
        if args.cases is None:
            raise ValueError("cases_required")
        dataset = load(args.cases, EvaluationSet)
        if args.set == "captured":
            if args.judgements is None or args.live or args.allow_paid:
                raise ValueError("captured_is_offline")
            result = report(dataset, load(args.judgements, JudgeBatch))
            print(json.dumps(result, sort_keys=True))
            return 0 if result["status"] == "ready_for_human_review" else 1
        if not args.live or not args.allow_paid or args.policy is None or args.output is None:
            raise ValueError("explicit_paid_opt_in_required")
        # Refuse overwrite BEFORE spending. Partial/failed batches remain unusable.
        with args.output.open("x", encoding="utf-8") as destination:
            from farmable_backend.integrations.settings import ServiceSettings
            from farmable_backend.logging import configure_logging

            configure_logging("info")
            batch = asyncio.run(
                live_judge(dataset, load(args.policy, JudgePolicy), ServiceSettings())
            )
            destination.write(batch.model_dump_json(indent=2) + "\n")
        print(json.dumps({"status": "judgements_recorded", "dataset_sha256": batch.dataset_sha256}))
        return 0
    except Exception:
        # Validation/provider exceptions can contain whole private cases/credentials.
        print(json.dumps({"error": "evaluation_refused_or_unavailable"}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
