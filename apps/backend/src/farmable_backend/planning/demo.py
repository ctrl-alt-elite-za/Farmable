"""Run contextual examples locally without an API, credentials or a database."""

import argparse
import json
import sys

from .engine import plan_section
from .schemas import PlanningRequest


def demo_requests() -> dict[str, PlanningRequest]:
    common = {
        "section_id": "demo-empty-section",
        "area_m2": "400",
        "planting_date": "2026-09-18",
        "budget_cents": 300_000,
    }
    half_cabbage = [{"crop": "cabbage", "percent": 50}]
    return {
        "normal": PlanningRequest.model_validate(common),
        "keep_half_cabbage": PlanningRequest.model_validate(
            {**common, "min_crop_shares": half_cabbage}
        ),
        "tight_budget": PlanningRequest.model_validate(
            {**common, "budget_cents": 210_000, "min_crop_shares": half_cabbage}
        ),
        "impossible_budget": PlanningRequest.model_validate(
            {**common, "budget_cents": 100_000, "min_crop_shares": half_cabbage}
        ),
        "smaller_section": PlanningRequest.model_validate(
            {**common, "area_m2": "200", "min_crop_shares": half_cabbage}
        ),
        "unsupported_date": PlanningRequest.model_validate(
            {**common, "planting_date": "2026-10-01"}
        ),
    }


def main() -> None:
    requests = demo_requests()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["all", *requests], default="all")
    args = parser.parse_args()
    selected = requests if args.scenario == "all" else {args.scenario: requests[args.scenario]}
    json.dump(
        {name: plan_section(request).model_dump(mode="json") for name, request in selected.items()},
        sys.stdout,
        indent=2,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
