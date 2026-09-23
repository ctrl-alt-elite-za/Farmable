from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, Response

from farmable_backend.forecast_contract import Crop, Outlook
from farmable_backend.forecasts import outlook
from farmable_backend.record_access import ApiError
from farmable_backend.records_api import bearer, runtime, token
from farmable_backend.schemas import ErrorResponse

router = APIRouter(
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 404, 503)},
)


@router.get("/outlook", response_model=Outlook, operation_id="getCropOutlook")
async def get_outlook(
    request: Request,
    response: Response,
    section_id: UUID,
    crop: Crop,
    plant_month: Annotated[int, Query(ge=1, le=12)],
):
    if set(request.query_params) != {"section_id", "crop", "plant_month"} or any(
        len(request.query_params.getlist(key)) != 1 for key in request.query_params
    ):
        raise ApiError(422, "validation_error")
    worker = runtime(request)
    value = await worker.call(
        outlook,
        worker.service.sessions,
        token(request),
        section_id,
        crop,
        plant_month,
        request.app.state.forecast_data_mode,
        request.app.state.services.open_meteo.settings.integrations_mode,
    )
    response.headers["Cache-Control"] = "no-store"
    return value
