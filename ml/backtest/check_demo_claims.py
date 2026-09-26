"""Check that every statistic the demo speaks or shows comes from the backtest (#26).

    python ml/backtest/check_demo_claims.py docs/demo-script.md [--run RUN_ID]

Every percentage and rand amount in the script's narration must equal, at the
precision it is written, a figure in the run's ``slide_sentence.txt`` or in the
``results`` of its ``decision_backtest.json``. When the slide sentence reports
INSUFFICIENT EVIDENCE, no backtest figure may be quoted at all: the run's own
verdict is that none of them can be relied on.

Text in code spans or fenced blocks is not a claim: it is what the farmer says
(`My budget is R3 000`) or what the app shows, not something the team asserts.
Exits 0 when every claim is backed, 1 otherwise, listing each unbacked claim.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

RESULTS = Path(__file__).resolve().parent / "results"
INSUFFICIENT = "INSUFFICIENT EVIDENCE"

_FENCE = re.compile(r"^(```|~~~).*?^\1[^\n]*$", re.MULTILINE | re.DOTALL)
_SPAN = re.compile(r"`[^`\n]*`")
_NUMBER = r"(?:\d{1,3}(?:[ ,\u00a0]\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)"
_PERCENT = re.compile(rf"({_NUMBER})\s?(?:%|percent\b)", re.IGNORECASE)
_RAND = re.compile(rf"\bR\s?(-?{_NUMBER})(?!\d)")


@dataclass(frozen=True)
class Claim:
    line: int
    text: str
    kind: str  # "percent" or "rand"
    value: float
    decimals: int


def _parse(number: str) -> tuple[float, int]:
    plain = re.sub(r"[ ,\u00a0]", "", number)
    decimals = len(plain.split(".", 1)[1]) if "." in plain else 0
    return float(plain), decimals


def narration(markdown: str) -> str:
    """The script with code spans and fences blanked, keeping line numbers."""
    blank = lambda match: re.sub(r"[^\n]", " ", match.group(0))  # noqa: E731
    return _SPAN.sub(blank, _FENCE.sub(blank, markdown))


def claims(markdown: str) -> list[Claim]:
    found = []
    for number, line in enumerate(narration(markdown).splitlines(), 1):
        for kind, pattern in (("percent", _PERCENT), ("rand", _RAND)):
            for match in pattern.finditer(line):
                value, decimals = _parse(match.group(1))
                found.append(Claim(number, match.group(0).strip(), kind, value, decimals))
    return found


def _numbers(value: Any) -> list[float]:
    if isinstance(value, bool):
        return []
    if isinstance(value, int | float):
        return [float(value)] if math.isfinite(value) else []
    if isinstance(value, dict):
        return [n for item in value.values() for n in _numbers(item)]
    if isinstance(value, list):
        return [n for item in value for n in _numbers(item)]
    return []


@dataclass(frozen=True)
class Evidence:
    sufficient: bool
    percents: tuple[float, ...]
    rands: tuple[float, ...]


def evidence(run: Path) -> Evidence:
    sentence = (run / "slide_sentence.txt").read_text(encoding="utf-8")
    if sentence.strip().upper().startswith(INSUFFICIENT):
        return Evidence(False, (), ())
    results = json.loads((run / "decision_backtest.json").read_text(encoding="utf-8"))
    figures = _numbers(results.get("results", {}))
    spoken_percents = [_parse(m.group(1))[0] for m in _PERCENT.finditer(sentence)]
    spoken_rands = [_parse(m.group(1))[0] for m in _RAND.finditer(sentence)]
    # Rates are stored as fractions (0.73) and percentages as percentages (404.0).
    percents = [*figures, *(f * 100 for f in figures), *spoken_percents]
    return Evidence(True, tuple(percents), tuple([*figures, *spoken_rands]))


def backed(claim: Claim, source: Evidence) -> bool:
    pool = source.percents if claim.kind == "percent" else source.rands
    return any(round(figure, claim.decimals) == claim.value for figure in pool)


def latest_run() -> Path:
    runs = sorted(p for p in RESULTS.iterdir() if (p / "slide_sentence.txt").is_file())
    if len(runs) != 1:
        raise SystemExit(f"expected one backtest run in {RESULTS}, found {len(runs)}; pass --run")
    return runs[0]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument("script", type=Path)
    parser.add_argument("--run", help="backtest run id under ml/backtest/results")
    args = parser.parse_args(argv)
    run = RESULTS / args.run if args.run else latest_run()
    source = evidence(run)
    unbacked = [c for c in claims(args.script.read_text(encoding="utf-8")) if not backed(c, source)]
    if not unbacked:
        print(f"PASS: every statistic in {args.script} is backed by run {run.name}")
        return 0
    reason = (
        "the run reports INSUFFICIENT EVIDENCE, so no backtest figure may be quoted"
        if not source.sufficient
        else f"not in slide_sentence.txt or the results of run {run.name}"
    )
    for claim in unbacked:
        print(f"{args.script}:{claim.line}: {claim.text!r}: {reason}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
