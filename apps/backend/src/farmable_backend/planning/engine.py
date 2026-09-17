"""Pure, deterministic sample-data planning. No database, provider, clock or random calls."""

from datetime import timedelta
from decimal import ROUND_HALF_UP, Context, Decimal, localcontext
from itertools import product

from .demo_data import DEMO_SCENARIO
from .schemas import (
    Allocation,
    CandidatePlan,
    CostEstimate,
    Crop,
    CropEstimate,
    PlanFailure,
    PlanningRequest,
    PlanningResult,
    SampleCrop,
    SampleScenario,
)


def _cents(value: Decimal) -> int:
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _estimate(
    crop: SampleCrop,
    area: Decimal,
    request: PlanningRequest,
    *,
    count: int = 1,
    block_count: int = 1,
) -> CropEstimate:
    area_numerator = area * count
    quantity_numerator = area_numerator * crop.yield_kg_per_m2
    quantity = quantity_numerator / block_count
    # Divide last: rounding a recurring third before multiplication can move an
    # exact half-cent below its tie, causing a one-cent budget/accounting error.
    sales = _cents(quantity_numerator * crop.price_cents_per_kg / block_count)
    costs = tuple(
        CostEstimate(
            category=cost.category,
            cost_cents=_cents(area_numerator * cost.cents_per_m2 / block_count),
        )
        for cost in crop.costs
    )
    total_cost = sum(cost.cost_cents for cost in costs)
    return CropEstimate(
        crop=crop.crop,
        area_m2=area_numerator / block_count,
        estimated_quantity_kg=quantity,
        price_cents_per_kg=crop.price_cents_per_kg,
        sales_cents=sales,
        costs=costs,
        total_cost_cents=total_cost,
        margin_cents=sales - total_cost,
        harvest_start=request.planting_date + timedelta(days=crop.harvest_days_min),
        harvest_end=request.planting_date + timedelta(days=crop.harvest_days_max),
    )


def plan_section(
    request: PlanningRequest, scenario: SampleScenario = DEMO_SCENARIO
) -> PlanningResult:
    """Rank distinct equal-block allocations by margin, cost, then canonical crop order.

    `section_id` is just a correlation identifier here, NOT an ownership check. A future
    API must resolve the authenticated section and its area before calling this core.
    """
    # Do not inherit an unrelated caller's decimal precision, rounding or traps.
    with localcontext(Context(prec=32, rounding=ROUND_HALF_UP)):
        return _plan_section(request, scenario)


def _plan_section(request: PlanningRequest, scenario: SampleScenario) -> PlanningResult:
    crops = {crop.crop: crop for crop in scenario.crops}
    selected = tuple(sorted(request.crops))

    def outcome(
        *,
        comparisons: tuple[CropEstimate, ...] = (),
        plans: tuple[CandidatePlan, ...] = (),
        reason: PlanFailure | None = None,
    ) -> PlanningResult:
        return PlanningResult(
            request=request,
            scenario=scenario,
            feasible=bool(plans),
            comparisons=comparisons,
            plans=plans,
            reason=reason,
        )

    if not scenario.planting_start <= request.planting_date <= scenario.planting_end:
        return outcome(
            reason=PlanFailure(
                code="unsupported_date",
                message="This sample scenario only covers the stated supported planting dates.",
            )
        )
    if not set(selected).issubset(crops):
        return outcome(
            reason=PlanFailure(
                code="unsupported_crop", message="This scenario has no sample inputs for that crop."
            )
        )

    comparisons = tuple(
        sorted(
            (_estimate(crops[crop], request.area_m2, request) for crop in selected),
            key=lambda estimate: (-estimate.margin_cents, estimate.crop),
        )
    )
    if sum(share.percent for share in request.min_crop_shares) > 100:
        return outcome(
            comparisons=comparisons,
            reason=PlanFailure(
                code="conflicting_minimum_shares",
                message="The requested minimum crop shares exceed the whole section.",
            ),
        )

    options: tuple[Crop | None, ...] = (*selected, None)
    seen: set[tuple[int, ...]] = set()
    candidates: list[CandidatePlan] = []
    minimum_cost: int | None = None
    # Estimate each crop/count once, retaining the block ratio until final rounding.
    estimates = {
        (crop, count): _estimate(
            crops[crop], request.area_m2, request, count=count, block_count=request.block_count
        )
        for crop in selected
        for count in range(1, request.block_count + 1)
    }
    for blocks in product(options, repeat=request.block_count):
        counts = tuple(blocks.count(crop) for crop in options)
        if counts in seen or counts[-1] == request.block_count:
            continue
        seen.add(counts)
        if any(
            blocks.count(share.crop) * 100 < share.percent * request.block_count
            for share in request.min_crop_shares
        ):
            continue
        allocations = tuple(
            Allocation(
                crop=crop,
                block_count=blocks.count(crop),
                share_percent=(Decimal(blocks.count(crop)) * 100 / request.block_count).quantize(
                    Decimal("0.01"), rounding=ROUND_HALF_UP
                ),
                estimate=estimates[(crop, blocks.count(crop))],
            )
            for crop in selected
            if crop in blocks
        )
        cost = sum(allocation.estimate.total_cost_cents for allocation in allocations)
        minimum_cost = cost if minimum_cost is None else min(minimum_cost, cost)
        if cost > request.budget_cents:
            continue
        sales = sum(allocation.estimate.sales_cents for allocation in allocations)
        candidates.append(
            CandidatePlan(
                blocks=blocks,
                allocations=allocations,
                unplanted_area_m2=request.area_m2 * counts[-1] / request.block_count,
                sales_cents=sales,
                total_cost_cents=cost,
                margin_cents=sales - cost,
                remaining_budget_cents=request.budget_cents - cost,
            )
        )

    if not candidates:
        if minimum_cost is None:
            reason = PlanFailure(
                code="minimum_shares_do_not_fit_blocks",
                message="These minimum shares cannot fit the selected number of equal blocks. "
                "Relax a share or change the block count (up to four).",
            )
        else:
            has_minimum = any(share.percent > 0 for share in request.min_crop_shares)
            reason = PlanFailure(
                code="minimum_share_exceeds_budget" if has_minimum else "budget_too_low",
                message="No planted allocation meets the budget under these sample assumptions. "
                "Increase the budget, reduce the section area or relax a minimum crop share.",
                minimum_required_budget_cents=minimum_cost,
            )
        return outcome(comparisons=comparisons, reason=reason)

    candidates.sort(
        key=lambda candidate: (
            -candidate.margin_cents,
            candidate.total_cost_cents,
            tuple(block or "unplanted" for block in candidate.blocks),
        )
    )
    return outcome(comparisons=comparisons, plans=tuple(candidates[: request.max_results]))
