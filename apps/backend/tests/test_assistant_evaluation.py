"""Synthetic grader/transport tests, not human-labelled model acceptance results."""

import asyncio
import json
from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from farmable_backend.assistant.evaluate import main
from farmable_backend.assistant.evaluation import (
    JUDGE_INSTRUCTION,
    EvaluationCase,
    EvaluationSet,
    JudgeBatch,
    Judgement,
    JudgePolicy,
    Verdict,
    digest,
    judge_cases,
    live_judge,
    report,
)
from farmable_backend.integrations.base import ServiceResult
from farmable_backend.integrations.settings import ServiceSettings
from pydantic import ValidationError


def dataset(count=40, provenance="synthetic"):
    cases = []
    for index in range(count):
        cases.append(
            EvaluationCase(
                id=f"case-{index}",
                split="calibration" if index < count // 2 else "holdout",
                provenance=provenance,
                language="en" if index % 2 else "zu",
                model="fixture-target",
                captured_at=datetime.now(UTC),
                prompt=f"Question {index}",
                response="A synthetic reply.",
                evidence=["Sample only."],
                required_tools=["get_crop_outlook"],
                observed_tools=["get_crop_outlook"],
                human_pass=index % 4 < 2,
                reviewer="synthetic-test-label-not-human",
            )
        )
    return EvaluationSet(target_revision="0" * 40, approved_test_data=True, cases=cases)


def batch(data, mode="synthetic"):
    return JudgeBatch(
        dataset_sha256=data.fingerprint(),
        rubric_sha256=digest(JUDGE_INSTRUCTION),
        judge_model="fixture-judge",
        judge_response_model="fixture-judge-version",
        judge_mode=mode,
        results=[
            Judgement(
                case_id=case.id,
                response_sha256=digest(case.judge_input()),
                verdict=Verdict(grounded=case.human_pass, safe=True, no_unconfirmed_action=True),
            )
            for case in data.cases
        ],
    )


def test_perfect_synthetic_results_cannot_become_live_acceptance():
    data = dataset()
    result = report(data, batch(data))
    assert result["splits"]["holdout"]["agreement"] == 1.0
    assert result["status"] == "insufficient_or_failed_evidence"
    assert result["production_accepted"] is False


def test_qualified_captures_only_become_ready_for_independent_review():
    data = dataset(provenance="live_capture")
    result = report(data, batch(data, "live"))
    assert result["status"] == "ready_for_human_review"
    assert not result["production_accepted"]


def test_false_passes_and_missing_tools_fail_holdout_threshold():
    data = dataset(provenance="live_capture")
    judged = batch(data, "live")
    judged.results[-1].verdict.grounded = True
    result = report(data, judged)
    assert result["splits"]["holdout"]["false_pass"] == 1
    assert result["status"] == "insufficient_or_failed_evidence"
    data.cases[-4].observed_tools = []
    judged = batch(data, "live")
    assert report(data, judged)["splits"]["holdout"]["false_fail"] == 1


def test_calibration_holdout_context_overlap_and_mixed_models_are_rejected():
    data = dataset().model_dump(mode="json")
    data["cases"][-1]["prompt"] = data["cases"][0]["prompt"]
    with pytest.raises(ValidationError, match="overlap"):
        EvaluationSet.model_validate(data)
    data = dataset().model_dump(mode="json")
    data["cases"][-1]["model"] = "different-target"
    with pytest.raises(ValidationError, match="one target"):
        EvaluationSet.model_validate(data)


@pytest.mark.parametrize("change", ["missing", "duplicate", "response", "rubric", "labels"])
def test_cherry_picked_or_stale_judgements_cannot_score(change):
    data = dataset()
    judged = batch(data)
    if change == "missing":
        judged.results.pop()
    elif change == "duplicate":
        judged.results[-1] = judged.results[0]
    elif change == "response":
        judged.results[-1].response_sha256 = "0" * 64
    elif change == "rubric":
        judged.rubric_sha256 = "0" * 64
    else:
        data.cases[-1].human_pass = True
    with pytest.raises(ValueError):
        report(data, judged)


def policy(**kwargs):
    return JudgePolicy(
        model="fixture-judge",
        response_models=["fixture-judge-version"],
        reviewed_on=datetime.now(UTC).date(),
        per_call_reserve_micro_usd=10,
        budget_micro_usd=kwargs.get("budget", 1000),
    )


def adapter():
    captured = []

    async def generate(payload):
        captured.append(payload)
        return ServiceResult(
            "gemini",
            True,
            data={
                "modelVersion": "fixture-judge-version",
                "candidates": [
                    {
                        "finishReason": "STOP",
                        "content": {
                            "parts": [
                                {
                                    "text": json.dumps(
                                        {
                                            "grounded": True,
                                            "safe": True,
                                            "no_unconfirmed_action": True,
                                        }
                                    )
                                }
                            ]
                        },
                    }
                ],
            },
        )

    return SimpleNamespace(
        settings=SimpleNamespace(gemini_model="fixture-judge", integrations_mode="fake"),
        generate=generate,
        captured=captured,
    )


def test_judge_does_not_see_human_labels_and_cannot_invoke_tools():
    data, fake = dataset(2), adapter()
    judged = asyncio.run(judge_cases(data, fake, policy()))
    assert judged.judge_mode == "synthetic" and len(fake.captured) == 2
    for payload in fake.captured:
        assert "tools" not in payload
        assert "human_pass" not in json.dumps(payload) and "reviewer" not in json.dumps(payload)
        assert "holdout" not in json.dumps(payload)
        assert payload["generationConfig"]["maxOutputTokens"] == 1024


def test_budget_refusal_happens_before_first_request():
    fake = adapter()
    with pytest.raises(ValueError, match="policy_refused"):
        asyncio.run(judge_cases(dataset(2), fake, policy(budget=10)))
    assert not fake.captured


def test_provider_failure_is_not_retried_or_reported_as_pass():
    fake = adapter()

    async def unavailable(payload):
        fake.captured.append(payload)
        return ServiceResult("gemini", False, error="timeout")

    fake.generate = unavailable
    with pytest.raises(ValueError, match="judge_unavailable"):
        asyncio.run(judge_cases(dataset(2), fake, policy()))
    assert len(fake.captured) == 1


def test_live_judge_requires_staging_before_network():
    with pytest.raises(ValueError, match="staging_required"):
        asyncio.run(live_judge(dataset(2), policy(), ServiceSettings()))


def test_cli_refuses_paid_judge_without_opt_in(monkeypatch, tmp_path, capsys):
    source = tmp_path / "cases.json"
    source.write_text(dataset(2).model_dump_json(), encoding="utf-8")
    monkeypatch.setattr("sys.argv", ["evaluate", "--set", "judge", "--cases", str(source)])
    assert main() == 2
    output = capsys.readouterr().out
    assert "Question" not in output and "evaluation_refused" in output
