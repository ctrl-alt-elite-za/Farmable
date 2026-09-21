"""The prototype's arithmetic and constraints are real; its external inputs are sample data."""

import json
from datetime import date
from decimal import ROUND_DOWN, Decimal, localcontext
from fractions import Fraction
from itertools import product

import pytest
from farmable_backend.planning import PlanningRequest, PlanningResult, plan_section
from farmable_backend.planning.demo import demo_requests, main
from farmable_backend.planning.demo_data import DEMO_SCENARIO
from farmable_backend.planning.schemas import SampleScenario
from pydantic import ValidationError


def request(**changes) -> PlanningRequest:
    return PlanningRequest.model_validate(
        {
            "section_id": "demo-empty-section",
            "area_m2": "400",
            "planting_date": "2026-09-18",
            "budget_cents": 300_000,
            **changes,
        }
    )


def test_comparison_has_itemised_real_arithmetic_and_harvest_windows():
    result = plan_section(request())
    assert result.feasible
    spinach, cabbage = result.comparisons
    assert (spinach.crop, cabbage.crop) == ("spinach", "cabbage")
    assert cabbage.estimated_quantity_kg == Decimal("800")
    assert cabbage.sales_cents == 400_000
    assert [cost.cost_cents for cost in cabbage.costs] == [48_000, 72_000, 36_000, 84_000, 60_000]
    assert cabbage.total_cost_cents == 300_000
    assert cabbage.margin_cents == 100_000
    assert (cabbage.harvest_start, cabbage.harvest_end) == (date(2026, 12, 17), date(2027, 1, 6))
    assert spinach.estimated_quantity_kg == Decimal("600")
    assert spinach.sales_cents == 480_000
    assert spinach.total_cost_cents == 240_000
    assert spinach.margin_cents == 240_000
    assert (spinach.harvest_start, spinach.harvest_end) == (date(2026, 10, 23), date(2026, 11, 7))


def test_keep_half_cabbage_changes_the_best_plan_and_respects_every_returned_plan():
    original = plan_section(request())
    revised = plan_section(request(min_crop_shares=[{"crop": "cabbage", "percent": 50}]))
    assert original.plans[0].blocks == ("spinach",) * 4
    assert revised.plans[0].blocks == ("cabbage", "cabbage", "spinach", "spinach")
    assert revised.plans[0].total_cost_cents == 270_000
    assert revised.plans[0].margin_cents == 170_000
    assert revised.plans[0].remaining_budget_cents == 30_000
    for candidate in revised.plans:
        assert candidate.blocks.count("cabbage") * 100 >= 50 * len(candidate.blocks)
    assert original.request.min_crop_shares == ()  # Replanning did not mutate the old input.


def test_tight_budget_leaves_space_unplanted():
    result = plan_section(demo_requests()["tight_budget"])
    best = result.plans[0]
    assert best.blocks == ("cabbage", "cabbage", "spinach", None)
    assert best.unplanted_area_m2 == Decimal("100")
    assert best.total_cost_cents == 210_000
    assert best.margin_cents == 110_000
    assert best.remaining_budget_cents == 0


def test_impossible_budget_has_reason_minimum_cost_and_no_partial_plan():
    result = plan_section(demo_requests()["impossible_budget"])
    assert not result.feasible
    assert result.plans == ()
    assert result.reason.code == "minimum_share_exceeds_budget"
    assert result.reason.minimum_required_budget_cents == 150_000


@pytest.mark.parametrize("budget", [0, 59_999, 60_000, 100_000, 149_999, 150_000, 210_000, 300_000])
@pytest.mark.parametrize("share", [0, 25, 50, 75, 100])
def test_solver_matches_independent_exhaustive_integer_oracle(budget, share):
    # For 400 m² / four blocks, derive the integer oracle directly from fixture inputs.
    # This does not call the engine's estimate/ranking helpers.
    expected = []
    for cabbage, spinach in product(range(5), repeat=2):
        if cabbage + spinach == 0 or cabbage + spinach > 4 or cabbage * 25 < share:
            continue
        cost = cabbage * 75_000 + spinach * 60_000
        if cost <= budget:
            blocks = (
                ("cabbage",) * cabbage + ("spinach",) * spinach + (None,) * (4 - cabbage - spinach)
            )
            margin = cabbage * 25_000 + spinach * 60_000
            expected.append((margin, cost, blocks))
    expected.sort(
        key=lambda row: (-row[0], row[1], tuple(block or "unplanted" for block in row[2]))
    )
    result = plan_section(
        request(
            budget_cents=budget,
            min_crop_shares=[{"crop": "cabbage", "percent": share}],
            max_results=10,
        )
    )
    assert result.feasible == bool(expected)
    assert [
        (plan.margin_cents, plan.total_cost_cents, plan.blocks) for plan in result.plans
    ] == expected[:10]


@pytest.mark.parametrize("block_count", [1, 2, 3, 4])
def test_constraints_are_checked_with_exact_counts_not_rounded_display_percentages(block_count):
    result = plan_section(
        request(block_count=block_count, min_crop_shares=[{"crop": "cabbage", "percent": 34}])
    )
    assert result.feasible
    for candidate in result.plans:
        assert candidate.blocks.count("cabbage") * 100 >= 34 * block_count


def test_shares_that_cannot_fit_equal_blocks_are_explained():
    result = plan_section(
        request(
            min_crop_shares=[{"crop": "cabbage", "percent": 60}, {"crop": "spinach", "percent": 40}]
        )
    )
    assert not result.feasible
    assert result.reason.code == "minimum_shares_do_not_fit_blocks"
    assert result.reason.minimum_required_budget_cents is None
    assert not result.plans


def test_conflicting_shares_are_not_silently_relaxed():
    result = plan_section(
        request(
            min_crop_shares=[{"crop": "cabbage", "percent": 75}, {"crop": "spinach", "percent": 75}]
        )
    )
    assert not result.feasible
    assert result.reason.code == "conflicting_minimum_shares"
    assert not result.plans


def test_one_crop_request_does_not_allocate_the_other_crop():
    result = plan_section(request(crops=["cabbage"], budget_cents=150_000))
    assert [comparison.crop for comparison in result.comparisons] == ["cabbage"]
    assert result.plans[0].blocks == ("cabbage", "cabbage", None, None)
    assert all(
        block in ("cabbage", None) for candidate in result.plans for block in candidate.blocks
    )


@pytest.mark.parametrize("planting_date", ["2026-08-31", "2026-10-01", "2027-09-18"])
def test_unsupported_date_never_receives_invented_comparisons(planting_date):
    result = plan_section(request(planting_date=planting_date))
    assert not result.feasible
    assert result.reason.code == "unsupported_date"
    assert not result.plans
    assert not result.comparisons


@pytest.mark.parametrize("planting_date", ["2026-09-01", "2026-09-30"])
def test_supported_date_boundaries_are_inclusive(planting_date):
    assert plan_section(request(planting_date=planting_date)).feasible


def test_supported_date_change_moves_harvest_windows_but_does_not_randomise_prices():
    first = plan_section(request(planting_date="2026-09-01"))
    later = plan_section(request(planting_date="2026-09-02"))
    for original, updated in zip(first.comparisons, later.comparisons, strict=True):
        assert (updated.harvest_start - original.harvest_start).days == 1
        assert updated.margin_cents == original.margin_cents


def test_halving_area_halves_quantities_sales_and_costs():
    first = plan_section(request())
    smaller = plan_section(request(area_m2="200"))
    for original, updated in zip(first.comparisons, smaller.comparisons, strict=True):
        assert updated.estimated_quantity_kg * 2 == original.estimated_quantity_kg
        assert updated.sales_cents * 2 == original.sales_cents
        assert updated.total_cost_cents * 2 == original.total_cost_cents
        assert updated.margin_cents * 2 == original.margin_cents


def test_fractional_area_uses_half_up_cents_and_item_totals():
    result = plan_section(request(area_m2="1.01", crops=["spinach"], block_count=1))
    estimate = result.comparisons[0]
    assert estimate.estimated_quantity_kg == Decimal("1.515")
    assert estimate.sales_cents == 1212
    assert [cost.cost_cents for cost in estimate.costs] == [81, 121, 81, 172, 152]
    assert estimate.total_cost_cents == 607
    assert estimate.margin_cents == 605


def test_third_block_preserves_exact_half_cent_before_rounding():
    result = plan_section(
        request(area_m2="1.03", crops=["cabbage"], block_count=3, budget_cents=300)
    )
    estimate = result.plans[0].allocations[0].estimate
    assert estimate.costs[-1].category == "transport_packaging"
    assert estimate.costs[-1].cost_cents == 52  # 1.03 × 150 / 3 = exactly 51.5 cents.
    assert estimate.total_cost_cents == 258
    assert estimate.sales_cents == 343
    assert not plan_section(
        request(area_m2="1.03", crops=["cabbage"], block_count=3, budget_cents=257)
    ).feasible


def test_third_block_sales_preserve_exact_half_cent():
    data = DEMO_SCENARIO.model_dump()
    data["crops"][1]["price_cents_per_kg"] = 3
    scenario = SampleScenario.model_validate(data)
    result = plan_section(
        request(area_m2="1", crops=["spinach"], block_count=3, budget_cents=203), scenario
    )
    # 1 × 1.5 × 3 / 3 = exactly 1.5 cents, rounded up to 2, despite recurring area.
    assert result.plans[0].allocations[0].estimate.sales_cents == 2


@pytest.mark.parametrize("area", ["1", "1.01", "1.03", "1.07", "12.99", "400"])
@pytest.mark.parametrize("block_count", [1, 2, 3, 4])
@pytest.mark.parametrize("crop", ["cabbage", "spinach"])
def test_fractional_block_money_matches_independent_exact_fraction_oracle(area, block_count, crop):
    sample = next(item for item in DEMO_SCENARIO.crops if item.crop == crop)
    result = plan_section(request(area_m2=area, crops=[crop], block_count=block_count))

    def half_up(value: Fraction) -> int:
        return (2 * value.numerator + value.denominator) // (2 * value.denominator)

    for candidate in result.plans:
        allocation = candidate.allocations[0]
        exact_area = Fraction(area) * allocation.block_count / block_count
        assert allocation.estimate.sales_cents == half_up(
            exact_area * Fraction(sample.yield_kg_per_m2) * sample.price_cents_per_kg
        )
        for expected, actual in zip(sample.costs, allocation.estimate.costs, strict=True):
            assert actual.cost_cents == half_up(exact_area * expected.cents_per_m2)


def test_equal_margin_prefers_less_spending_then_canonical_crop_order():
    data = DEMO_SCENARIO.model_dump()
    data["crops"][0]["price_cents_per_kg"] = 675  # Cabbage and spinach both yield 600c/m² margin.
    result = plan_section(request(), SampleScenario.model_validate(data))
    assert result.plans[0].blocks == ("spinach",) * 4  # Same margin, lower listed spending.
    data["crops"][0]["price_cents_per_kg"] = 600
    data["crops"][0]["costs"] = data["crops"][1]["costs"]
    tied = plan_section(request(), SampleScenario.model_validate(data))
    assert tied.plans[0].blocks == ("cabbage",) * 4  # Equal margin and spending.


def test_plans_conserve_land_and_all_displayed_money_reconciles():
    for example in demo_requests().values():
        result = plan_section(example)
        for candidate in result.plans:
            assert (
                sum(allocation.estimate.area_m2 for allocation in candidate.allocations)
                + candidate.unplanted_area_m2
                == example.area_m2
            )
            assert candidate.total_cost_cents == sum(
                allocation.estimate.total_cost_cents for allocation in candidate.allocations
            )
            assert candidate.sales_cents == sum(
                allocation.estimate.sales_cents for allocation in candidate.allocations
            )
            assert candidate.margin_cents == candidate.sales_cents - candidate.total_cost_cents
            assert (
                candidate.remaining_budget_cents
                == example.budget_cents - candidate.total_cost_cents
            )
            for allocation in candidate.allocations:
                assert allocation.estimate.total_cost_cents == sum(
                    cost.cost_cents for cost in allocation.estimate.costs
                )


def test_repeated_calls_are_identical_and_do_not_depend_on_caller_decimal_context():
    example = request(area_m2="1.01", block_count=3)
    expected = plan_section(example).model_dump_json()
    with localcontext() as context:
        context.prec = 4
        context.rounding = ROUND_DOWN
        assert plan_section(example).model_dump_json() == expected
        assert context.prec == 4
        assert context.rounding == ROUND_DOWN
    assert plan_section(example).model_dump_json() == expected


def test_crop_input_order_does_not_change_recommendations():
    first = plan_section(request(crops=["cabbage", "spinach"]))
    reordered = plan_section(request(crops=["spinach", "cabbage"]))
    assert reordered.plans == first.plans
    assert reordered.comparisons == first.comparisons


def test_equivalent_permutations_are_not_duplicate_options():
    result = plan_section(request(max_results=10))
    counts = [(plan.blocks.count("cabbage"), plan.blocks.count("spinach")) for plan in result.plans]
    assert len(set(counts)) == len(counts)
    assert len(result.plans) == 10


def test_maximum_area_and_budget_are_bounded_but_computable():
    result = plan_section(request(area_m2="1000000", budget_cents=1_000_000_000))
    assert result.feasible
    assert result.plans[0].total_cost_cents <= 1_000_000_000


@pytest.mark.parametrize(
    "changes",
    [
        {"unexpected": True},
        {"section_id": ""},
        {"section_id": "x" * 81},
        {"area_m2": "0"},
        {"area_m2": "0.99"},
        {"area_m2": "-1"},
        {"area_m2": "1000000.01"},
        {"area_m2": "1.001"},
        {"area_m2": "NaN"},
        {"area_m2": "Infinity"},
        {"area_m2": True},
        {"planting_date": "not-a-date"},
        {"budget_cents": -1},
        {"budget_cents": 1_000_000_001},
        {"budget_cents": "300000"},
        {"budget_cents": 300000.5},
        {"budget_cents": True},
        {"crops": []},
        {"crops": ["maize"]},
        {"crops": ["cabbage", "cabbage"]},
        {"block_count": 0},
        {"block_count": 5},
        {"block_count": True},
        {"block_count": "4"},
        {"max_results": 0},
        {"max_results": 11},
        {"min_crop_shares": [{"crop": "cabbage", "percent": -1}]},
        {"min_crop_shares": [{"crop": "cabbage", "percent": 101}]},
        {"min_crop_shares": [{"crop": "cabbage", "percent": True}]},
        {"min_crop_shares": [{"crop": "cabbage", "percent": 50, "unknown": True}]},
        {
            "min_crop_shares": [
                {"crop": "cabbage", "percent": 25},
                {"crop": "cabbage", "percent": 50},
            ]
        },
        {"crops": ["spinach"], "min_crop_shares": [{"crop": "cabbage", "percent": 50}]},
    ],
)
def test_invalid_requests_are_rejected_not_coerced_or_ignored(changes):
    with pytest.raises(ValidationError):
        request(**changes)


def test_sample_metadata_and_all_contextual_examples_round_trip():
    for example in demo_requests().values():
        result = plan_section(example)
        assert PlanningResult.model_validate_json(result.model_dump_json()) == result
        assert (
            result.scenario.label
            == "Prototype using sample crop and market data. Not a live forecast."
        )
        assert result.scenario.data_version == "sample-v1"
        assert result.soil_information == "unknown"
        assert result.scenario.assumptions


def test_missing_scenario_crop_is_explicit_not_silently_substituted():
    data = DEMO_SCENARIO.model_dump()
    data["crops"] = [data["crops"][0]]
    scenario = SampleScenario.model_validate(data)
    result = plan_section(request(), scenario)
    assert not result.feasible
    assert result.reason.code == "unsupported_crop"
    assert not result.comparisons


def test_cli_runs_all_examples_without_configuration(monkeypatch, capsys):
    monkeypatch.setattr("sys.argv", ["demo"])
    main()
    report = json.loads(capsys.readouterr().out)
    assert set(report) == set(demo_requests())
    assert report["normal"]["feasible"] is True
    assert report["impossible_budget"]["reason"]["code"] == "minimum_share_exceeds_budget"
    assert report["unsupported_date"]["reason"]["code"] == "unsupported_date"


def test_cli_can_select_one_context(monkeypatch, capsys):
    monkeypatch.setattr("sys.argv", ["demo", "--scenario", "tight_budget"])
    main()
    assert set(json.loads(capsys.readouterr().out)) == {"tight_budget"}
