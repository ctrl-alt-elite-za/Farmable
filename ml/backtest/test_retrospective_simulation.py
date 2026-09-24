"""Fabricated inputs only: exercise the registered policy, not real outcomes."""

import hashlib
from dataclasses import replace
from datetime import date
from decimal import Decimal as D
from decimal import localcontext
from pathlib import Path

import pytest
from farmable_ml import retrospective
from farmable_ml.challenger import lightgbm_quantiles
from farmable_ml.cpi import CpiSeries
from farmable_ml.data import Crop, ObservationPolicy, PriceObservation, observations_before
from farmable_ml.forecast import (
    Forecast,
    InsufficientHistory,
    historical_range,
    same_month_last_year,
    select_method,
    shift_month,
)
from farmable_ml.reports import RETROSPECTIVE_SCENARIO, Bootstrap, build_report, canonical_json
from farmable_ml.retrospective import (
    ASSUMPTIONS,
    ORIGINAL_PROTOCOL_SHA256,
    PROTOCOL_SHA256,
    ForecastAudit,
    RetrospectiveSimulation,
    choose,
)

POLICY = ObservationPolicy.RETROSPECTIVE


def prices():
    return tuple(
        PriceObservation(
            crop,
            "synthetic",
            date(year, month, 1),
            date(2026, 9, 23),
            D(10 + month),
            "a" * 64,
        )
        for crop in Crop
        for year in range(2008, 2025)
        for month in range(1, 13)
    )


def cpi():
    return CpiSeries(
        "b" * 64,
        tuple(
            (date(year, month, 1), D(200 if year == 2025 else 100))
            for year in range(2008, 2026)
            for month in range(1, 13)
        ),
    )


def audit(crop, origin, price):
    target = shift_month(origin, ASSUMPTIONS[crop].harvest_months)
    return ForecastAudit(
        crop,
        origin,
        target,
        Forecast(crop, origin, target, "historical_range", price, price, price),
        None,
        None,
        None,
        "synthetic audit helper",
    )


def candidate_audits(origin, price=D(10)):
    return tuple(
        audit(crop, origin, price)
        for crop, inputs in ASSUMPTIONS.items()
        if origin.month in inputs.planting_months
    )


def test_retrospective_next_month_eligibility_preserves_publication_policy_and_dates():
    origin = date(2012, 1, 1)
    rows = tuple(row for row in prices() if row.crop == Crop.CABBAGE)
    assert observations_before(rows, origin) == ()
    eligible = observations_before(rows, origin, policy=POLICY)
    assert eligible[-1].observation_month == date(2011, 12, 1)
    assert all(row.available_on == date(2026, 9, 23) for row in eligible)
    assert all(row.observation_month < origin for row in eligible)
    with pytest.raises(ValueError, match="supported observation policy"):
        observations_before(rows, origin, policy="typo")


def test_simple_models_include_the_previous_month_at_the_analytical_cutoff():
    args = dict(
        crop=Crop.CABBAGE, market="synthetic", origin=date(2012, 1, 1), target=date(2012, 12, 1)
    )
    with pytest.raises(InsufficientHistory):
        historical_range(prices(), **args)
    assert historical_range(prices(), **args, policy=POLICY).p50 == D(22)
    assert same_month_last_year(prices(), **args, policy=POLICY).p50 == D(22)


def test_selection_reconstructs_each_retrospective_fold_and_never_sees_future_rows():
    rows = tuple(row for row in prices() if row.crop == Crop.CABBAGE)
    seen = []

    def predictor(history, origin, target):
        assert all(row.observation_month < origin for row in history)
        assert max(row.observation_month for row in history) == shift_month(origin, -1)
        seen.append(origin)
        value = D(10 + target.month)
        return Forecast(Crop.CABBAGE, origin, target, "fixture", value, value, value)

    result = select_method(
        rows,
        crop=Crop.CABBAGE,
        market="synthetic",
        cutoff=date(2018, 1, 1),
        horizon_months=3,
        methods={"first": predictor, "second": predictor},
        tie_order=("first", "second"),
        policy=POLICY,
    )
    assert result.winner == "first"
    assert len(result.folds) == 36
    assert result.folds[-1].target == date(2017, 12, 1)
    assert len(set(seen)) == 36


def test_lightgbm_retrospective_policy_is_repeatable_and_future_mutation_safe():
    origin = date(2015, 1, 1)
    rows = tuple(row for row in prices() if row.crop == Crop.CABBAGE)
    changed = tuple(
        replace(row, price_rand_per_kg=D(999999)) if row.observation_month >= origin else row
        for row in rows
    )
    args = dict(crop=Crop.CABBAGE, market="synthetic", origin=origin, target=date(2015, 6, 1))
    with pytest.raises(InsufficientHistory):
        lightgbm_quantiles(rows, **args)
    before = lightgbm_quantiles(rows, **args, policy=POLICY)
    assert before == lightgbm_quantiles(changed, **args, policy=POLICY)
    assert before == lightgbm_quantiles(rows, **args, policy=POLICY)


def test_frozen_assumptions_match_both_registered_protocol_tables():
    protocol = Path("ml/backtest/PROTOCOL.md").read_bytes()
    assert hashlib.sha256(protocol).hexdigest() == PROTOCOL_SHA256
    assert ORIGINAL_PROTOCOL_SHA256.encode() in protocol
    months = {
        name: index
        for index, name in enumerate(
            ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"), 1
        )
    }
    checked = []
    for line in protocol.decode().splitlines():
        if not line.startswith("|"):
            continue
        fields = [part.strip() for part in line.split("|")[1:-1]]
        crop = fields[0].replace(" ", "_")
        if crop not in ASSUMPTIONS:
            continue
        inputs = ASSUMPTIONS[Crop(crop)]
        if len(fields) == 4:
            assert inputs.planting_months == frozenset(
                months[name] for name in fields[1].split(", ")
            )
            assert inputs.harvest_months == int(fields[2])
            assert inputs.yield_kg_per_ha == D(fields[3].replace(",", ""))
        else:
            assert inputs.cost_2025_rand_per_ha == D(fields[1].replace(",", ""))
            assert inputs.marketing_rate == D(fields[2].removesuffix("%")) / 100
        checked.append(crop)
    assert len(checked) == 16 and set(checked) == set(Crop)
    with pytest.raises(TypeError):
        ASSUMPTIONS[Crop.CABBAGE] = ASSUMPTIONS[Crop.SPINACH]


def test_marketing_cost_and_duration_formula_is_shared_and_context_independent():
    expected = (D(10) * D("0.875") * D(75000) - D("115183.85")) / 3
    assert ASSUMPTIONS[Crop.CABBAGE].margin(D(10)) == expected
    with localcontext() as context:
        context.prec = 6
        assert ASSUMPTIONS[Crop.CABBAGE].margin(D(10)) == expected
    assert ASSUMPTIONS[Crop.TOMATOES].margin(D(10)) == (D(625000) - D("168968.20")) / 3


def test_choose_preserves_negative_margins_and_alphabetical_exact_ties(monkeypatch):
    origin = date(2018, 6, 1)  # No crop is in season under the frozen table.
    assert choose((), origin=origin).skip_reason == "no_in_season_candidates"
    origin = date(2018, 9, 1)
    forecasts = candidate_audits(origin, D("0.0001"))
    expected = max(forecasts, key=lambda row: ASSUMPTIONS[row.crop].margin(row.selected.p50)).crop
    assert all(ASSUMPTIONS[row.crop].margin(row.selected.p50) < 0 for row in forecasts)
    assert choose(tuple(reversed(forecasts)), origin=origin).recommended == expected
    # Isolate the tie-break from division rounding in crop-specific budgets.
    monkeypatch.setattr(retrospective.ProductionAssumptions, "margin", lambda self, price: D(-1))
    assert choose(tuple(reversed(forecasts)), origin=origin).recommended == min(
        row.crop for row in forecasts
    )


def test_missing_or_mismatched_candidate_cannot_silently_change_the_choice():
    origin = date(2018, 1, 1)
    forecasts = candidate_audits(origin)
    with pytest.raises(ValueError, match="exactly one"):
        choose(forecasts[:-1], origin=origin)
    with pytest.raises(ValueError, match="horizon"):
        choose((replace(forecasts[0], target=date(2020, 1, 1)), *forecasts[1:]), origin=origin)
    unavailable = replace(forecasts[0], selected=None, skip_reason="insufficient history")
    choice = choose((unavailable, *forecasts[1:]), origin=origin)
    assert choice.recommended is None and choice.skip_reason == "missing_forecast"


@pytest.fixture
def cheap_challenger(monkeypatch):
    # Integration tests exercise walk-forward orchestration cheaply. The test
    # above independently fits the pinned LightGBM implementation on this policy.
    def predict(records, *, crop, market, origin, target, policy):
        return replace(
            historical_range(
                records, crop=crop, market=market, origin=origin, target=target, policy=policy
            ),
            method="lightgbm",
        )

    monkeypatch.setattr(retrospective, "lightgbm_quantiles", predict)


def test_integrated_predictions_and_choices_ignore_future_prices(cheap_challenger):
    origin = date(2018, 1, 1)
    rows = prices()
    changed = tuple(
        replace(row, price_rand_per_kg=D(99999)) if row.observation_month >= origin else row
        for row in rows
    )
    first = RetrospectiveSimulation(rows, cpi(), market="synthetic")
    second = RetrospectiveSimulation(tuple(reversed(changed)), cpi(), market="synthetic")
    choices = first.freeze((origin,))
    assert choices == second.freeze((origin,))
    assert choices[0].recommended is not None
    assert first.score(choices) != second.score(choices)  # Outcomes may change, the choice cannot.
    cabbage = next(row for row in choices[0].forecasts if row.crop == Crop.CABBAGE)
    assert cabbage.selected.p50 == D(28)  # April nominal 14, normalized once to 2025 rand.
    assert cabbage.selection.winner == "historical_range"  # Exact method ties.
    scored = next(row for row in first.score(choices) if row.default == Crop.CABBAGE)
    assert scored.default_margin == ASSUMPTIONS[Crop.CABBAGE].margin(D(28))


def test_missing_outcomes_never_reselect_and_post_2024_stays_skipped(cheap_challenger):
    origin = date(2018, 1, 1)
    rows = prices()
    full = RetrospectiveSimulation(rows, cpi(), market="synthetic")
    choices = full.freeze((origin,))
    winner = choices[0].recommended
    harvest = shift_month(origin, ASSUMPTIONS[winner].harvest_months)
    missing = RetrospectiveSimulation(
        tuple(row for row in rows if (row.crop, row.observation_month) != (winner, harvest)),
        cpi(),
        market="synthetic",
    )
    assert missing.freeze((origin,)) == choices
    assert all(row.skip_reason for row in missing.score(choices))
    assert all(row.recommended == winner for row in missing.score(choices))
    late = full.freeze((date(2024, 12, 1),))
    extra = tuple(
        replace(row, observation_month=shift_month(row.observation_month, 12))
        for row in rows
        if row.observation_month.year == 2024
    )
    supplied_2025 = RetrospectiveSimulation(rows + extra, cpi(), market="synthetic")
    assert supplied_2025.score(late) == full.score(late)
    assert all(row.skip_reason for row in full.score(late))


def test_duplicate_or_mixed_market_inputs_and_invalid_grids_fail_closed():
    rows = prices()
    for invalid in ((), rows + rows[:1], rows + (replace(rows[0], market="other"),)):
        with pytest.raises(ValueError):
            RetrospectiveSimulation(invalid, cpi(), market="synthetic")
    simulation = RetrospectiveSimulation(rows, cpi(), market="synthetic")
    for origins in ((), (date(2011, 1, 1),), (date(2018, 1, 1),) * 2):
        with pytest.raises(ValueError, match="registered"):
            simulation.freeze(origins)
    with pytest.raises(ValueError, match="missing CPI"):
        RetrospectiveSimulation(
            rows, replace(cpi(), observations=cpi().observations[:-1]), market="synthetic"
        )


def test_every_default_grid_is_retained_and_synthetic_report_is_deterministic(cheap_challenger):
    simulation = RetrospectiveSimulation(prices(), cpi(), market="synthetic")
    result = simulation.run()
    assert len(result.decisions) == 1248 and len(result.choices) == 156
    assert len({(row.origin, row.default) for row in result.decisions}) == 1248
    assert any(row.skip_reason == "out_of_season" for row in result.decisions)
    assert any(row.skip_reason == "missing_realized_price" for row in result.decisions)
    assert any(row.skip_reason == "missing_forecast" for row in result.decisions)
    kwargs = dict(
        input_hashes={"fabricated": "a" * 64},
        data_kind="synthetic",
        scenario=RETROSPECTIVE_SCENARIO,
        config=Bootstrap(replicates=100),
    )
    first = build_report(result.decisions, **kwargs)
    repeated = RetrospectiveSimulation(tuple(reversed(prices())), cpi(), market="synthetic").run()
    assert result == repeated
    assert canonical_json(first) == canonical_json(build_report(repeated.decisions, **kwargs))
    assert first["coverage"]["data_kind"] == "synthetic"


def test_all_failed_methods_retain_the_fold_evidence(cheap_challenger):
    simulation = RetrospectiveSimulation(prices(), cpi(), market="synthetic")
    row = simulation.forecast(Crop.CABBAGE, date(2012, 1, 1))
    assert row.selected is None and row.selection is None
    assert row.skip_reason == "no method supports all common validation targets"
    assert len(row.failed_selection_folds) == 36
    assert dict(row.failed_selection_scores) == {"historical_range": None, "lightgbm": None}
    assert any(loss is None for fold in row.failed_selection_folds for _, loss in fold.losses)


def test_mutated_frozen_choices_cannot_be_scored(cheap_challenger):
    simulation = RetrospectiveSimulation(prices(), cpi(), market="synthetic")
    choices = simulation.freeze((date(2018, 1, 1),))
    with pytest.raises(ValueError, match="duplicate frozen"):
        simulation.score(choices * 2)
    winner = choices[0].recommended
    other = next(crop for crop in Crop if crop != winner)
    with pytest.raises(ValueError, match="forecast evidence"):
        simulation.score((replace(choices[0], recommended=other),))


def test_actual_lightgbm_and_baseline_integrate_with_walk_forward_selection():
    simulation = RetrospectiveSimulation(prices(), cpi(), market="synthetic")
    result = simulation.run((date(2018, 5, 1),))  # Cabbage is the only in-season crop in May.
    row = result.choices[0].forecasts[0]
    assert row.selected is not None and row.selection is not None and row.diagnostic is not None
    assert dict(row.selection.scores)["lightgbm"] is not None
    assert len(row.selection.folds) == 36
    assert result.choices[0].recommended == Crop.CABBAGE
    assert len(result.decisions) == 8
    assert next(item for item in result.decisions if item.default == Crop.CABBAGE).gain == 0
    assert simulation.run((date(2018, 5, 1),)) == result


def test_run_does_not_depend_on_the_callers_decimal_precision(cheap_challenger):
    origin = (date(2018, 1, 1),)
    reference = RetrospectiveSimulation(prices(), cpi(), market="synthetic").run(origin)
    with localcontext() as context:
        context.prec = 6
        assert RetrospectiveSimulation(prices(), cpi(), market="synthetic").run(origin) == reference
