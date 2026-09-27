"""Authenticated farm-profile and advisory opportunity endpoints."""

from fastapi import APIRouter, Depends, Request, Response
from fastapi.security import HTTPBearer

from farmable_backend.advisory_schemas import AdvisoryMatch, FarmProfileUpdate, FarmProfileView
from farmable_backend.record_access import ApiError
from farmable_backend.records_api import token
from farmable_backend.schemas import ErrorResponse

router = APIRouter(
    prefix="/advisory",
    dependencies=[Depends(HTTPBearer(auto_error=False, scheme_name="SessionBearer"))],
    responses={status: {"model": ErrorResponse} for status in (401, 404, 503)},
)


def runtime(request: Request):
    value = getattr(request.app.state, "advisory", None)
    if value is None:
        raise ApiError(503, "advisory_unavailable")
    return value


@router.get("/farm-profile", response_model=FarmProfileView, operation_id="getFarmProfile")
async def get_profile(request: Request, response: Response):
    response.headers["Cache-Control"] = "no-store"
    return await runtime(request).call(runtime(request).service.profile, token(request))


@router.patch("/farm-profile", response_model=FarmProfileView, operation_id="updateFarmProfile")
async def update_profile(request: Request, response: Response, payload: FarmProfileUpdate):
    response.headers["Cache-Control"] = "no-store"
    return await runtime(request).call(
        runtime(request).service.update_profile, token(request), payload
    )


@router.get(
    "/opportunities/{kind}", response_model=list[AdvisoryMatch], operation_id="listAdvisoryMatches"
)
async def opportunities(request: Request, kind: str, limit: int = 10):
    if kind not in {"funding", "procurement"} or not 1 <= limit <= 20:
        raise ApiError(422, "validation_error")
    value = runtime(request)
    return await value.call(value.service.matches, token(request), kind, limit)
