from datetime import date
from decimal import Decimal
from typing import Annotated, Literal, Self
from uuid import UUID

from pydantic import Field, model_validator

from farmable_backend.planning.schemas import (
    BudgetCents,
    CandidatePlan,
    Crop,
    DemoModel,
    Identifier,
    MinimumCropShare,
    PlanningRequest,
    PlanningResult,
)

from .geometry import boundary_area

Longitude = Annotated[float, Field(strict=True, ge=-180, le=180, allow_inf_nan=False)]
Latitude = Annotated[float, Field(strict=True, ge=-85, le=85, allow_inf_nan=False)]
Ring = Annotated[tuple[tuple[Longitude, Latitude], ...], Field(min_length=4, max_length=33)]
InputArea = Annotated[Decimal, Field(ge=1, le=1_000_000, decimal_places=2, allow_inf_nan=False)]


class EmptyRequest(DemoModel):
    pass


class Boundary(DemoModel):
    type: Literal["Polygon"] = "Polygon"
    coordinates: Annotated[tuple[Ring, ...], Field(min_length=1, max_length=1)]

    @model_validator(mode="after")
    def simple_local_polygon(self) -> Self:
        boundary_area(self.coordinates[0])
        return self


class SectionWrite(DemoModel):
    name: Annotated[str, Field(min_length=1, max_length=60)]
    area_m2: InputArea | None = None
    boundary: Boundary | None = None

    @model_validator(mode="after")
    def one_area_source(self) -> Self:
        if not self.name.strip():
            raise ValueError("Section name cannot be blank")
        if (self.area_m2 is None) == (self.boundary is None):
            raise ValueError("Supply either a boundary or a farmer-supplied area, not both")
        return self

    def resolved_area(self) -> Decimal:
        if self.boundary is not None:
            return boundary_area(self.boundary.coordinates[0])
        assert self.area_m2 is not None  # noqa: S101 - validated above
        return self.area_m2


class DemoSection(DemoModel):
    id: UUID
    name: Annotated[str, Field(min_length=1, max_length=60)]
    area_m2: InputArea
    area_source: Literal["example_boundary", "boundary_estimate", "farmer_supplied"]
    boundary: Boundary | None = None
    revision: Annotated[int, Field(strict=True, ge=1)] = 1
    current_crop: Crop | None = None
    soil_information: Literal["unknown"] = "unknown"
    health_assessment: None = None
    planned_plan_id: UUID | None = None


class PlanInputs(DemoModel):
    planting_date: date
    budget_cents: BudgetCents
    crops: Annotated[tuple[Crop, ...], Field(min_length=1, max_length=2)] = ("cabbage", "spinach")
    block_count: Annotated[int, Field(strict=True, ge=1, le=4)] = 4
    min_crop_shares: Annotated[tuple[MinimumCropShare, ...], Field(max_length=2)] = ()
    max_results: Annotated[int, Field(strict=True, ge=1, le=10)] = 3

    @model_validator(mode="after")
    def validate_planning_inputs(self) -> Self:
        self.for_section("input-validation", Decimal("1"))
        return self

    def for_section(self, section_id: str, area: Decimal) -> PlanningRequest:
        return PlanningRequest.model_validate(
            {**self.model_dump(), "section_id": section_id, "area_m2": area}
        )


class PlanWrite(PlanInputs):
    selection_index: Annotated[int, Field(strict=True, ge=0, le=9)] = 0

    def for_section(self, section_id: str, area: Decimal) -> PlanningRequest:
        return PlanningRequest.model_validate(
            {
                **self.model_dump(exclude={"selection_index"}),
                "section_id": section_id,
                "area_m2": area,
            }
        )


class SavedPlan(DemoModel):
    id: UUID
    section_id: UUID
    section_revision: Annotated[int, Field(strict=True, ge=1)]
    version: Annotated[int, Field(strict=True, ge=1)]
    parent_plan_id: UUID | None = None
    status: Literal["proposed", "approved"] = "proposed"
    result: PlanningResult
    selection_index: Annotated[int, Field(strict=True, ge=0, le=9)]

    @property
    def selected(self) -> CandidatePlan:
        return self.result.plans[self.selection_index]

    @model_validator(mode="after")
    def valid_selection(self) -> Self:
        if not self.result.feasible or self.selection_index >= len(self.result.plans):
            raise ValueError("A saved plan needs a feasible selected allocation")
        if self.result.request.section_id != str(self.section_id):
            raise ValueError("Plan snapshot must belong to its section")
        return self


class Operation(DemoModel):
    key: Identifier
    fingerprint: Annotated[str, Field(pattern=r"^[0-9a-f]{64}$", max_length=64)]
    resource_id: UUID


class DemoFarm(DemoModel):
    id: UUID
    name: Literal["Hammanskraal example farm"] = "Hammanskraal example farm"
    sections: Annotated[tuple[DemoSection, ...], Field(max_length=20)]
    plans: Annotated[tuple[SavedPlan, ...], Field(max_length=40)] = ()
    operations: Annotated[tuple[Operation, ...], Field(max_length=100)] = ()


class Dashboard(DemoModel):
    farm_id: UUID
    name: str = Field(max_length=60)
    sections: tuple[DemoSection, ...]
    total_section_area_m2: Decimal
    approved_plans: tuple[SavedPlan, ...]
    analytics: None = None
    label: Literal["Prototype using sample crop and market data. Not a live forecast."] = (
        "Prototype using sample crop and market data. Not a live forecast."
    )


class DemoSession(DemoModel):
    access_token: Annotated[str, Field(min_length=43, max_length=43)]
    dashboard: Dashboard
