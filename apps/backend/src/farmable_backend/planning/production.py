"""Bounded deterministic allocation over validated active forecast rows; no demo fallback."""

from collections import defaultdict
from decimal import ROUND_CEILING, ROUND_HALF_UP, Context, Decimal, localcontext
from fractions import Fraction
from itertools import combinations_with_replacement

from farmable_backend.farm_records import _fingerprint
from farmable_backend.planning.calendar import CALENDAR_VERSION, add_months, payment_date
from farmable_backend.planning.contracts import Candidate, CashEvent, Estimate, PlanPreview
from farmable_backend.record_access import ApiError

ENGINE_VERSION = "active-outlook-v1/" + CALENDAR_VERSION
ASSUMPTIONS = [
    "All money, including your budget and goal, is constant-2025 ZAR, not today's nominal cash.",
    "Yield is the source estimate, not guaranteed harvest; weather exposure does not "
    "quantify loss.",
    "Harvest date adds the source growing-month count; it is an approximate planning date.",
    "Cost timing and commissions are your explicit assumptions, not facts inferred from "
    "the outlook.",
    "Remaining production cost is spread monthly through harvest; commissions are withheld "
    "at payment.",
    "Receipts arrive five SA business days after harvest, using the stated reviewed calendar.",
    "Cash feasibility and ranking use P50 prices; price-only break-even bounds are not calibrated "
    "farm-profit probabilities. Cross-crop price correlation is unknown.",
    "One planting date and up to four equal blocks; unlisted costs, tax and losses are excluded.",
]


def cents(value):
    if isinstance(value, Fraction):
        return (2 * value.numerator + value.denominator) // (2 * value.denominator)
    return int(value.quantize(Decimal(1), rounding=ROUND_HALF_UP))


def estimate(row, area, count, request):
    hectares_exact = Fraction(area) * count / (request.block_count * 10000)
    quantity_exact = hectares_exact * Fraction(row.yield_kg_per_ha)
    hectares = Decimal(hectares_exact.numerator) / hectares_exact.denominator
    quantity = Decimal(quantity_exact.numerator) / quantity_exact.denominator
    cost = cents(hectares_exact * Fraction(row.cost_per_ha) * 100)
    sales = cents(quantity_exact * Fraction(row.p50) * 100)
    # Generated clients expose cents as numbers. Keep even four-crop totals
    # comfortably below JavaScript's exact integer limit; do not send rounded money.
    if max(cost, sales) > 1_000_000_000_000_000:
        raise ApiError(503, "outlook_unavailable")
    fee_bps = request.market_commission_bps + request.agent_commission_bps
    fee = cents(Decimal(sales) * fee_bps / 10000)
    upfront = cents(Decimal(cost) * request.planting_cost_percent / 100)
    remaining, remainder = divmod(cost - upfront, row.growing_months)
    costs = [(request.planting_date, upfront)]
    costs.extend(
        (add_months(request.planting_date, month + 1), remaining + (month < remainder))
        for month in range(row.growing_months)
    )
    harvest = add_months(request.planting_date, row.growing_months)
    break_even_exact = Fraction(cost, 100) / (quantity_exact * Fraction(10000 - fee_bps, 10000))
    break_even = Decimal(break_even_exact.numerator) / break_even_exact.denominator
    quantiles = [(row.p10, Decimal("0.1")), (row.p50, Decimal("0.5")), (row.p90, Decimal("0.9"))]
    lower = max(
        (1 - q for price, q in quantiles if Fraction(price) >= break_even_exact), default=Decimal(0)
    )
    upper = min(
        (1 - q for price, q in quantiles if Fraction(price) < break_even_exact), default=Decimal(1)
    )
    return Estimate(
        crop=row.crop,
        blocks=count,
        area_m2=hectares * 10000,
        quantity_kg=quantity,
        production_cost_cents=cost,
        sales_cents=sales,
        commission_cents=fee,
        margin_cents=sales - fee - cost,
        harvest_date=harvest,
        payment_date=payment_date(harvest),
        break_even_price_per_kg=break_even.quantize(Decimal("0.0001"), rounding=ROUND_CEILING),
        price_only_break_even_chance_bounds=(lower, upper),
        cost_schedule=costs,
    )


def candidate(allocations, unplanted, budget):
    dates = defaultdict(lambda: [0, 0])
    for item in allocations:
        for day, cost in item.cost_schedule:
            dates[day][0] += cost
        dates[item.payment_date][1] += item.sales_cents - item.commission_cents
    running, required, timeline = 0, 0, []
    for day, (cost, receipts) in sorted(dates.items()):
        # Conservatively require cash for costs before receiving same-day proceeds.
        running -= cost
        required = max(required, -running)
        running += receipts
        timeline.append(
            CashEvent(
                date=day, cost_cents=cost, receipts_cents=receipts, balance_cents=budget + running
            )
        )
    values = dict(
        allocations=allocations,
        unplanted_blocks=unplanted,
        margin_cents=sum(a.margin_cents for a in allocations),
        required_cash_cents=required,
        cash_timeline=timeline,
    )
    identifier = _fingerprint(
        {"allocations": [a.model_dump(mode="json") for a in allocations], "unplanted": unplanted}
    )
    return Candidate(id=identifier, **values)


def calculate(request, section, rows, source):
    with localcontext(Context(prec=40, rounding=ROUND_HALF_UP)):
        return _calculate(request, section, rows, source)


def _calculate(request, section, rows, source):
    selected = sorted(request.crops, key=lambda item: item.crop)
    estimates = {
        (item.crop, count): estimate(rows[item.crop], section.area_m2, count, request)
        for item in selected
        for count in range(1, request.block_count + 1)
    }
    comparisons = [estimates[(item.crop, request.block_count)] for item in selected]
    feasible, cash_needed = [], []
    max_margin = None
    constraints_fit = False
    # At most C(12,4)=495 combinations for eight crops and the unplanted option.
    for choices in combinations_with_replacement(range(len(selected) + 1), request.block_count):
        counts = [choices.count(index) for index in range(len(selected))]
        if not any(counts):
            continue
        if any(
            count * 100 < item.minimum_percent * request.block_count
            or section.area_m2 * count * rows[item.crop].yield_kg_per_ha
            < item.promised_kg * request.block_count * 10000
            for item, count in zip(selected, counts, strict=True)
        ):
            continue
        allocations = [
            estimates[(item.crop, count)]
            for item, count in zip(selected, counts, strict=True)
            if count
        ]
        if request.cash_deadline is not None and any(
            item.payment_date > request.cash_deadline for item in allocations
        ):
            continue
        constraints_fit = True
        value = candidate(allocations, request.block_count - sum(counts), request.budget_cents)
        if value.required_cash_cents <= request.budget_cents:
            max_margin = (
                value.margin_cents if max_margin is None else max(max_margin, value.margin_cents)
            )
        if request.goal_margin_cents is not None and value.margin_cents < request.goal_margin_cents:
            continue
        cash_needed.append(value.required_cash_cents)
        if value.required_cash_cents <= request.budget_cents:
            feasible.append(value)
    feasible.sort(
        key=lambda value: (
            value.required_cash_cents
            if request.goal_margin_cents is not None
            else -value.margin_cents,
            -value.margin_cents,
            value.required_cash_cents,
            value.id,
        )
    )
    change = None
    if not feasible:
        change = {
            "code": "constraints_infeasible",
            "message": "Relax minimum shares/promised quantity or extend the cash deadline.",
        }
        if cash_needed:
            change = {
                "code": "budget_too_low",
                "minimum_budget_cents": min(cash_needed),
                "message": "Increase starting cash to the stated minimum or relax constraints.",
            }
        elif constraints_fit and request.goal_margin_cents is not None:
            change = {
                "code": "goal_unreachable",
                "maximum_margin_within_budget_cents": max_margin,
                "message": "Lower the margin goal or change the planting constraints.",
            }
    result = dict(
        engine_version=ENGINE_VERSION,
        request=request,
        section_version=section.version,
        area_m2=section.area_m2,
        source=source,
        comparisons=comparisons,
        candidates=feasible[: request.max_results],
        feasible=bool(feasible),
        change_needed=change,
        assumptions=ASSUMPTIONS,
    )
    preview = PlanPreview(snapshot_hash="0" * 64, **result)
    preview.snapshot_hash = _fingerprint(preview.model_dump(mode="json", exclude={"snapshot_hash"}))
    return preview
