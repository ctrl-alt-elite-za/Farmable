"""Internal demo shapes. Frontend endpoint contracts are deliberately not defined here."""

from datetime import date
from decimal import Decimal
from typing import Annotated, Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

Crop = Literal["cabbage", "spinach"]
CostCategory = Literal["seed", "fertiliser", "water", "labour", "transport_packaging"]
Cents = Annotated[int, Field(strict=True, ge=0)]
BudgetCents = Annotated[int, Field(strict=True, ge=0, le=1_000_000_000)]
Percent = Annotated[int, Field(strict=True, ge=0, le=100)]
Identifier = Annotated[str, Field(min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")]
Area = Annotated[Decimal, Field(gt=0, le=1_000_000, allow_inf_nan=False)]


class DemoModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, allow_inf_nan=False)


class MinimumCropShare(DemoModel):
    crop: Crop
    percent: Percent


class PlanningRequest(DemoModel):
    section_id: Identifier
    area_m2: Annotated[Decimal, Field(ge=1, le=1_000_000, decimal_places=2, allow_inf_nan=False)]
    planting_date: date
    budget_cents: BudgetCents
    crops: Annotated[tuple[Crop, ...], Field(min_length=1, max_length=2)] = (
        "cabbage",
        "spinach",
    )
    block_count: Annotated[int, Field(strict=True, ge=1, le=4)] = 4
    min_crop_shares: Annotated[tuple[MinimumCropShare, ...], Field(max_length=2)] = ()
    max_results: Annotated[int, Field(strict=True, ge=1, le=10)] = 3

    @model_validator(mode="after")
    def unique_selected_crops(self) -> Self:
        if len(set(self.crops)) != len(self.crops):
            raise ValueError("Crops must be unique")
        share_crops = [share.crop for share in self.min_crop_shares]
        if len(set(share_crops)) != len(share_crops):
            raise ValueError("Each crop can have only one minimum share")
        if not set(share_crops).issubset(self.crops):
            raise ValueError("Minimum shares must refer to selected crops")
        return self


class SampleCost(DemoModel):
    category: CostCategory
    cents_per_m2: Annotated[int, Field(strict=True, ge=0, le=1_000_000)]


class SampleCrop(DemoModel):
    crop: Crop
    yield_kg_per_m2: Annotated[Decimal, Field(gt=0, le=100, decimal_places=3, allow_inf_nan=False)]
    price_cents_per_kg: Annotated[int, Field(strict=True, ge=0, le=1_000_000)]
    costs: Annotated[tuple[SampleCost, ...], Field(min_length=1, max_length=5)]
    harvest_days_min: Annotated[int, Field(strict=True, ge=1, le=365)]
    harvest_days_max: Annotated[int, Field(strict=True, ge=1, le=365)]

    @model_validator(mode="after")
    def valid_costs_and_window(self) -> Self:
        if self.harvest_days_min > self.harvest_days_max:
            raise ValueError("Harvest window must be ordered")
        if len({cost.category for cost in self.costs}) != len(self.costs):
            raise ValueError("Cost categories must be unique")
        return self


class SampleScenario(DemoModel):
    scenario_id: Identifier
    data_version: Identifier
    label: Annotated[str, Field(min_length=1, max_length=300)]
    planting_start: date
    planting_end: date
    crops: Annotated[tuple[SampleCrop, ...], Field(min_length=1, max_length=2)]
    assumptions: Annotated[tuple[Annotated[str, Field(max_length=500)], ...], Field(max_length=10)]

    @model_validator(mode="after")
    def valid_scenario(self) -> Self:
        if self.planting_start > self.planting_end:
            raise ValueError("Supported planting dates must be ordered")
        if len({crop.crop for crop in self.crops}) != len(self.crops):
            raise ValueError("Sample crops must be unique")
        return self


class CostEstimate(DemoModel):
    category: CostCategory
    cost_cents: Cents


class CropEstimate(DemoModel):
    crop: Crop
    area_m2: Area
    estimated_quantity_kg: Annotated[Decimal, Field(gt=0, allow_inf_nan=False)]
    price_cents_per_kg: Cents
    sales_cents: Cents
    costs: tuple[CostEstimate, ...]
    total_cost_cents: Cents
    margin_cents: Annotated[int, Field(strict=True)]
    harvest_start: date
    harvest_end: date


class Allocation(DemoModel):
    crop: Crop
    block_count: Annotated[int, Field(strict=True, ge=1, le=4)]
    # Display percentages are rounded; constraint checks use exact block counts.
    share_percent: Annotated[Decimal, Field(gt=0, le=100, allow_inf_nan=False)]
    estimate: CropEstimate


class CandidatePlan(DemoModel):
    blocks: Annotated[tuple[Crop | None, ...], Field(min_length=1, max_length=4)]
    allocations: tuple[Allocation, ...]
    unplanted_area_m2: Annotated[Decimal, Field(ge=0, allow_inf_nan=False)]
    sales_cents: Cents
    total_cost_cents: Cents
    margin_cents: Annotated[int, Field(strict=True)]
    remaining_budget_cents: Cents


class PlanFailure(DemoModel):
    code: Literal[
        "unsupported_date",
        "unsupported_crop",
        "conflicting_minimum_shares",
        "minimum_shares_do_not_fit_blocks",
        "minimum_share_exceeds_budget",
        "budget_too_low",
    ]
    message: Annotated[str, Field(min_length=1, max_length=500)]
    minimum_required_budget_cents: Cents | None = None


class PlanningResult(DemoModel):
    request: PlanningRequest
    scenario: SampleScenario
    soil_information: Literal["unknown"] = "unknown"
    feasible: bool
    comparisons: tuple[CropEstimate, ...] = ()
    plans: tuple[CandidatePlan, ...] = ()
    reason: PlanFailure | None = None

    @model_validator(mode="after")
    def complete_outcome(self) -> Self:
        if self.feasible and (not self.plans or self.reason is not None):
            raise ValueError("A feasible result needs plans and no failure reason")
        if not self.feasible and (self.plans or self.reason is None):
            raise ValueError("An infeasible result needs a reason and no partial plans")
        return self
