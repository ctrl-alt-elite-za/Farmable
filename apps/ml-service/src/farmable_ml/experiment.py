"""Offline retrospective experiment engine; the public runner enforces the history gate.

All model caches belong to one immutable input series. Recommendations are frozen
before outcomes are consulted. Synthetic tests exercise the same orchestration.
"""

from collections.abc import Callable
from dataclasses import asdict, replace
from datetime import date
from decimal import Decimal
from typing import Any

from farmable_ml.challenger import lightgbm_quantiles
from farmable_ml.data import Crop, ObservationPolicy, PriceObservation, observations_before
from farmable_ml.decision import (
    Candidate,
    Decision,
    Recommendation,
    recommend,
    score_recommendation,
)
from farmable_ml.forecast import (
    Forecast,
    InsufficientHistory,
    SelectionUnavailable,
    historical_range,
    pinball_loss,
    same_month_last_year,
    select_method,
    shift_month,
)
from farmable_ml.reports import HISTORICAL_MONTHS
from farmable_ml.scenario import ASSUMPTIONS, MARKET, eligible_crops

D = Decimal
POLICY = ObservationPolicy.RETROSPECTIVE
METHODS: dict[str, Callable[..., Forecast]] = {
    "historical_range": historical_range,
    "lightgbm": lightgbm_quantiles,
    "same_month_last_year": same_month_last_year,
}


class Experiment:
    """Inputs must already be in constant 2025 rand under the registered scenario."""

    def __init__(self, records: tuple[PriceObservation, ...]):
        if not records or any(
            row.market != MARKET or row.availability_kind != "analytical_next_month"
            for row in records
        ):
            raise ValueError("experiment requires explicit Joburg analytical scenario inputs")
        self.records = tuple(sorted(records, key=lambda row: (row.crop, row.observation_month)))
        keys = {(row.crop, row.observation_month) for row in records}
        if len(keys) != len(records):
            raise ValueError("duplicate scenario price")
        self.cache: dict[tuple[Crop, date, date, str], Forecast | str] = {}
        self.selections: dict[tuple[Crop, date], dict[str, Any]] = {}

    def predict(self, crop: Crop, origin: date, target: date, method: str) -> Forecast:
        key = (crop, origin, target, method)
        if key not in self.cache:
            try:
                self.cache[key] = METHODS[method](
                    observations_before(self.records, origin, policy=POLICY),
                    crop=crop,
                    market=MARKET,
                    origin=origin,
                    target=target,
                    policy=POLICY,
                )
            except InsufficientHistory as exc:
                self.cache[key] = str(exc)
        result = self.cache[key]
        if isinstance(result, str):
            raise InsufficientHistory(result)
        return result

    def selected_forecast(self, crop: Crop, origin: date) -> Forecast:
        horizon = ASSUMPTIONS[crop].harvest_offset_months
        target = shift_month(origin, horizon)

        def adapter(name: str):
            def predict(history, fold_origin, fold_target):
                # Every cached prediction independently reconstructs its own cutoff.
                return self.predict(crop, fold_origin, fold_target, name)

            return predict

        try:
            selection = select_method(
                self.records,
                crop=crop,
                market=MARKET,
                cutoff=origin,
                horizon_months=horizon,
                methods={name: adapter(name) for name in ("historical_range", "lightgbm")},
                tie_order=("historical_range", "lightgbm"),
                policy=POLICY,
            )
            self.selections[crop, origin] = asdict(selection)
            return self.predict(crop, origin, target, selection.winner)
        except InsufficientHistory as exc:
            details: dict[str, Any] = {"failure": str(exc), "winner": None}
            if isinstance(exc, SelectionUnavailable):
                details.update(scores=exc.scores, folds=[asdict(fold) for fold in exc.folds])
            if (crop, origin) in self.selections:
                self.selections[crop, origin]["prediction_failure"] = str(exc)
            else:
                self.selections[crop, origin] = details
            raise

    def recommendation(self, origin: date) -> Recommendation:
        eligible = eligible_crops(origin)
        if not eligible:
            raise InsufficientHistory("no_in_season_candidates")
        candidates = []
        failures = []
        for crop in sorted(eligible):
            assumption = ASSUMPTIONS[crop]
            try:
                forecast = self.selected_forecast(crop, origin)
            except InsufficientHistory as exc:
                failures.append(str(exc))
                continue
            candidates.append(
                Candidate(
                    forecast,
                    assumption.yield_kg_per_ha,
                    assumption.cost_rand_per_ha,
                    D(assumption.harvest_offset_months),
                    date(2025, 1, 1),
                    "2025 ZAR",
                    assumption_kind="fixed_scenario",
                    marketing_rate=assumption.marketing_rate,
                )
            )
        if failures:
            raise InsufficientHistory("unavailable_forecast")
        return recommend(tuple(candidates), eligible=eligible)

    def decisions(self, origins: tuple[date, ...] = HISTORICAL_MONTHS) -> tuple[Decision, ...]:
        # Freeze every recommendation before creating the realized-price lookup.
        frozen: dict[date, Recommendation | str] = {}
        for origin in origins:
            try:
                frozen[origin] = self.recommendation(origin)
            except InsufficientHistory as exc:
                frozen[origin] = str(exc)
        actual = {
            (row.crop, row.observation_month): row.price_rand_per_kg
            for row in self.records
            if row.observation_month <= date(2024, 12, 1)
        }
        multipliers = dict.fromkeys(actual, D(1))
        decisions = []
        for origin in origins:
            choice = frozen[origin]
            for default in Crop:
                if default not in eligible_crops(origin):
                    decisions.append(
                        Decision(origin, default, default, None, None, "out_of_season")
                    )
                elif isinstance(choice, str):
                    decisions.append(Decision(origin, default, default, None, None, choice))
                else:
                    scored = score_recommendation(
                        choice,
                        default=default,
                        actual_prices=actual,
                        reporting_multipliers=multipliers,
                    )
                    if scored.skip_reason:
                        scored = replace(scored, skip_reason="missing_realized_price")
                    decisions.append(scored)
        return tuple(decisions)

    def forecast_evaluation(self, origins: tuple[date, ...] = HISTORICAL_MONTHS) -> dict[str, Any]:
        actual = {
            (row.crop, row.observation_month): row.price_rand_per_kg
            for row in self.records
            if row.observation_month <= date(2024, 12, 1)
        }
        rows = []
        for crop in Crop:
            for origin in origins:
                target = shift_month(origin, ASSUMPTIONS[crop].harvest_offset_months)
                for method in METHODS:
                    item: dict[str, Any] = {
                        "crop": crop.value,
                        "origin": origin,
                        "target": target,
                        "method": method,
                    }
                    try:
                        prediction = self.predict(crop, origin, target, method)
                        value = actual.get((crop, target))
                        item.update(
                            p10=prediction.p10,
                            p50=prediction.p50,
                            p90=prediction.p90,
                            actual=value,
                            pinball_loss=pinball_loss(prediction, value) if value else None,
                            failure=None if value else "missing_realized_price",
                        )
                    except InsufficientHistory as exc:
                        item["failure"] = str(exc)
                    rows.append(item)
        summaries = []
        for crop in Crop:
            for method in METHODS:
                losses = [
                    row["pinball_loss"]
                    for row in rows
                    if row["crop"] == crop
                    and row["method"] == method
                    and row.get("pinball_loss") is not None
                ]
                summaries.append(
                    {
                        "crop": crop.value,
                        "method": method,
                        "scored_targets": len(losses),
                        "mean_pinball_loss": sum(losses, D(0)) / len(losses) if losses else None,
                    }
                )
        return {"rows": rows, "summaries": summaries}

    def forecast_ledger(self) -> list[dict[str, Any]]:
        return [
            {
                "crop": crop.value,
                "origin": origin,
                "target": target,
                "method": method,
                "failure": None,
                "p10": None,
                "p50": None,
                "p90": None,
                **({"failure": result} if isinstance(result, str) else asdict(result)),
            }
            for (crop, origin, target, method), result in sorted(self.cache.items())
        ]
