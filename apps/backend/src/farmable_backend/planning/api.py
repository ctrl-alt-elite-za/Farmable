from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response

from farmable_backend.planning.contracts import (
    ConfirmedPlan,
    PlanConfirmation,
    PlanPreview,
    PlanRequest,
)
from farmable_backend.planning.service import Planner
from farmable_backend.records_api import bearer, runtime, token
from farmable_backend.schemas import ErrorResponse

router = APIRouter(
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 404, 409, 413, 422, 503)},
)


def planner(request):
    worker = runtime(request)
    return worker, Planner(
        worker.service.sessions,
        request.app.state.forecast_data_mode,
        request.app.state.services.open_meteo.settings.integrations_mode,
    )


@router.post(
    "/farms/{farm_id}/planning/preview",
    response_model=PlanPreview,
    operation_id="previewPlantingPlan",
)
async def preview(request: Request, response: Response, farm_id: UUID, payload: PlanRequest):
    worker, service = planner(request)
    response.headers["Cache-Control"] = "no-store"
    return await worker.call(service.preview, token(request), farm_id, payload)


@router.post(
    "/farms/{farm_id}/planning/confirm",
    response_model=ConfirmedPlan,
    operation_id="confirmPlantingPlan",
)
async def confirm(request: Request, response: Response, farm_id: UUID, payload: PlanConfirmation):
    worker, service = planner(request)
    response.headers["Cache-Control"] = "no-store"
    return await worker.call(service.confirm, token(request), farm_id, payload)
