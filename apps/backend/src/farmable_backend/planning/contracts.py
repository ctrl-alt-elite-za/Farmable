"""Active-outlook planning contract, separate from the unchanged demo planner."""

from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Any, Literal, Self
from uuid import UUID

from pydantic import Field, StrictBool, StrictInt, model_validator

from farmable_backend.forecast_contract import Crop
from farmable_backend.schemas import StrictModel

Money = Annotated[StrictInt, Field(ge=0, le=1_000_000_000)]
Percent = Annotated[StrictInt, Field(ge=0, le=100)]
Digest = Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]


class CropConstraint(StrictModel):
    crop: Crop
    minimum_percent: Percent = 0
    promised_kg: Annotated[
        Decimal, Field(ge=0, le=1_000_000, decimal_places=3, allow_inf_nan=False)
    ] = Decimal(0)


class PlanRequest(StrictModel):
    section_id: UUID
    planting_date: date
    budget_cents: Money
    # Do not silently compare today's nominal cash with constant-2025 forecasts.
    money_basis_year: Literal[2025]
    crops: Annotated[list[CropConstraint], Field(min_length=1, max_length=8)]
    block_count: Annotated[StrictInt, Field(ge=1, le=4)] = 4
    max_results: Annotated[StrictInt, Field(ge=1, le=5)] = 3
    cash_deadline: date | None = None
    goal_margin_cents: Money | None = None
    # Caller-supplied assumptions: the outlook contains totals, not cost timing/fees.
    planting_cost_percent: Percent
    market_commission_bps: Annotated[StrictInt, Field(ge=0, le=5000)]
    agent_commission_bps: Annotated[StrictInt, Field(ge=0, le=5000)]

    @model_validator(mode="after")
    def consistent(self) -> Self:
        if len({item.crop for item in self.crops}) != len(self.crops):
            raise ValueError("Crops must be unique")
        if self.market_commission_bps + self.agent_commission_bps >= 10000:
            raise ValueError("Combined commissions must be less than 100%")
        if self.cash_deadline is not None and self.cash_deadline < self.planting_date:
            raise ValueError("Cash deadline precedes planting")
        return self


class CashEvent(StrictModel):
    date: date
    cost_cents: int
    receipts_cents: int
    balance_cents: int


class Estimate(StrictModel):
    crop: Crop
    blocks: int
    area_m2: Decimal
    quantity_kg: Decimal
    production_cost_cents: int
    sales_cents: int
    commission_cents: int
    margin_cents: int
    harvest_date: date
    payment_date: date
    break_even_price_per_kg: Decimal
    price_only_break_even_chance_bounds: tuple[Decimal, Decimal]
    cost_schedule: list[tuple[date, int]]


class Candidate(StrictModel):
    id: Digest
    allocations: list[Estimate]
    unplanted_blocks: int
    margin_cents: int
    required_cash_cents: int
    cash_timeline: list[CashEvent]


class PlanPreview(StrictModel):
    engine_version: str
    request: PlanRequest
    section_version: int
    area_m2: Decimal
    source: dict[str, Any]
    comparisons: list[Estimate]
    candidates: list[Candidate]
    feasible: bool
    change_needed: dict[str, Any] | None
    assumptions: list[str]
    snapshot_hash: Digest


class PlanConfirmation(StrictModel):
    mutation_id: UUID
    plan_id: UUID
    expected_version: Annotated[StrictInt, Field(ge=0)] = 0
    confirmed: StrictBool
    request: PlanRequest
    snapshot_hash: Digest
    candidate_id: Digest


class ConfirmedPlan(StrictModel):
    id: UUID
    version: int
    approved_at: datetime
    replayed: bool
