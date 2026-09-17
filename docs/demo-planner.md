# Offline demo planner core

This is a **partial hackathon prototype**, related to #8, #22, #25 and #26.
It does not complete those issues. #11/#12 frontend wiring and persistence are
not implemented here. No endpoint, database table, migration, authentication
flow or frontend API contract has been added.

## Run it

After the repository's normal `uv sync --locked` setup, from the repo root:

```bash
uv run python -m farmable_backend.planning.demo
uv run python -m farmable_backend.planning.demo --scenario tight_budget
uv run pytest apps/backend/tests/test_demo_planner.py -q
```

These commands need no `.env`, provider key, running API, database or internet
connection once dependencies are installed. They make no paid or live calls.
This is not a claim that the frontend or its map works offline.

## Contextual examples

All examples use invented details, a 400 m² available section and a planting date
of 18 September 2026 unless noted. Money in code/JSON is **integer ZAR cents**.

| Scenario                       | Starting budget | Minimum cabbage | Best allocation                                          | Listed spending | Illustrative margin |
| ------------------------------ | --------------- | --------------- | -------------------------------------------------------- | --------------- | ------------------- |
| `normal`                       | R3,000          | None            | Four spinach blocks                                      | R2,400          | R2,400              |
| `keep_half_cabbage`            | R3,000          | 50%             | Two cabbage, two spinach                                 | R2,700          | R1,700              |
| `tight_budget`                 | R2,100          | 50%             | Two cabbage, one spinach, one unplanted                  | R2,100          | R1,100              |
| `impossible_budget`            | R1,000          | 50%             | No workable planted plan; minimum listed spending R1,500 | —               | —                   |
| `smaller_section` (200 m²)     | R3,000          | 50%             | Two cabbage, two spinach                                 | R1,350          | R850                |
| `unsupported_date` (1 October) | R3,000          | None            | Unsupported sample date; no invented estimates           | —               | —                   |

These are arithmetic fixtures, **not researched yields, market prices or
agronomic guidance**. The scenario only supports September 2026. Within that
month, changing the planting date shifts the sample harvest windows; prices
and yields do not change. Other dates are explicitly unsupported.

Every result carries the full versioned sample inputs, assumptions and label:
“Prototype using sample crop and market data. Not a live forecast.” Soil is
`unknown`; neither weather nor soil suitability is assessed. Do not describe
the returned margin as guaranteed profit.

## Internal interface, not an agreed HTTP contract

```python
from farmable_backend.planning import PlanningRequest, plan_section

request = PlanningRequest.model_validate({
    "section_id": "demo-empty-section",
    "area_m2": "400",
    "planting_date": "2026-09-18",
    "budget_cents": 300000,
    "min_crop_shares": [{"crop": "cabbage", "percent": 50}],
})
result = plan_section(request)
print(result.model_dump_json(indent=2))
```

Decimal quantities and areas serialize as **decimal strings**, not floats.
Third-block areas/quantities use fixed decimal precision; rounded percentages
are display values only. Money is calculated from the original area and block
ratio, dividing last so recurring thirds do not alter half-cent rounding.
Prices are cents per kilogram; input costs are cents per square metre. Quantity
is allocated area × yield; sales are quantity × price. Each listed cost line
and sales are rounded once to cents, half up. Total costs are the sum of those
rounded lines; margin is sales minus total listed costs.

The solver tries all allocations of the chosen crops plus unplanted space into
one to four equal blocks (at most 81 combinations for two crops/four blocks).
It returns distinct allocations, ranked by highest margin, then lowest cost,
then canonical crop order. Cabbage/spinach are the only supported crops.
The all-unplanted allocation is not offered as a successful planting plan.

Minimum shares use **exact integer block counts**, not the rounded percentages
shown for display. Budget means **total listed spending ≤ starting cash**;
there is no weekly cash-flow, commission or payment-delay model. Replanning
means calling the same pure function with a newly validated request: the old
request/result is not modified. This does not implement voice interruption or
persisted plan versions.

Invalid shapes, unknown fields, duplicate crops/shares and out-of-range inputs
raise Pydantic validation errors. Well-formed but unsupported/infeasible
requests return `feasible: false`, a reason code/message and **no partial plan**.
Supported-date comparisons may still be shown for an infeasible budget; they
are unconstrained whole-section estimates, not affordable approved plans.

## Frontend integration and rehearsal still required

1. Agree on endpoint/request/response shapes and adapt this internal interface.
2. Resolve section ownership, boundaries and area on the server before calling
   the planner. `section_id` here is only a correlation ID, not authorization.
3. Connect the section editor, comparison, constraint controls and approval.
   Show the sample-data label on comparisons and approved plan cards; indicate
   approved plans as **planned**, not physically planted.
4. Add the agreed lightweight saving/reset behaviour. If saving fails, do not
   show success or silently imply a local fallback is server persistence.
5. Rehearse the normal → half-cabbage → tight-budget → approve → reopen flow
   three consecutive times on the actual demo browser. Check the impossible
   budget and unsupported-date states separately, and record a private backup.

The CLI/tests verify the core only. No browser rehearsal, backup recording,
staging readiness, voice behaviour or issue #26 acceptance is claimed.
Full #8 tables/contracts, #22 production planner/cash-flow/security, #25 voice
cancellation and #26 native rehearsal remain outstanding.
