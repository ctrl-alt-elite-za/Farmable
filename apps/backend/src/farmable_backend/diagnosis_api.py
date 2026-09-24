"""Authenticated focus-diagnosis submission, cancellation and bounded polling."""

from uuid import UUID

from fastapi import APIRouter, Depends, Request

from farmable_backend.diagnosis import DiagnosisStore
from farmable_backend.diagnosis_schemas import DiagnosisCreate, DiagnosisNotice, DiagnosisView
from farmable_backend.record_access import ApiError
from farmable_backend.records_api import Limit, bearer, runtime, token
from farmable_backend.records_schemas import Page
from farmable_backend.schemas import ErrorResponse

router = APIRouter(
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 404, 409, 429, 503)},
)


def store(request):
    return DiagnosisStore(runtime(request).service.sessions)


@router.get("/diagnoses/notice", response_model=DiagnosisNotice, operation_id="diagnosisNotice")
async def notice():
    return DiagnosisNotice()


@router.post(
    "/farms/{farm_id}/sections/{section_id}/diagnoses",
    response_model=DiagnosisView,
    status_code=202,
    operation_id="submitDiagnosis",
)
async def submit(request: Request, farm_id: UUID, section_id: UUID, payload: DiagnosisCreate):
    if (
        not getattr(request.app.state, "diagnosis_enabled", False)
        or request.app.state.services.crop_health.settings.integrations_mode == "disabled"
    ):
        raise ApiError(503, "diagnosis_disabled")
    return await runtime(request).call(
        store(request).submit, token(request), farm_id, section_id, payload
    )


@router.get(
    "/farms/{farm_id}/diagnoses", response_model=Page[DiagnosisView], operation_id="listDiagnoses"
)
async def listing(request: Request, farm_id: UUID, cursor: UUID | None = None, limit: Limit = 50):
    return await runtime(request).call(
        store(request).read, token(request), farm_id, cursor=cursor, limit=limit
    )


@router.get(
    "/farms/{farm_id}/diagnoses/{diagnosis_id}",
    response_model=DiagnosisView,
    operation_id="getDiagnosis",
)
async def get(request: Request, farm_id: UUID, diagnosis_id: UUID):
    return await runtime(request).call(store(request).read, token(request), farm_id, diagnosis_id)


@router.post(
    "/farms/{farm_id}/diagnoses/{diagnosis_id}/cancel",
    response_model=DiagnosisView,
    operation_id="cancelDiagnosis",
)
async def cancel(request: Request, farm_id: UUID, diagnosis_id: UUID):
    return await runtime(request).call(
        store(request).read, token(request), farm_id, diagnosis_id, cancel=True
    )
