"""An explicit read-only tool allowlist. Never dispatch arbitrary names/SQL/URLs."""

import json
from datetime import UTC, datetime

from pydantic import ValidationError
from sqlalchemy import select

from farmable_backend.assistant.schemas import AdvisoryArgs, OutlookArgs, SectionListArgs
from farmable_backend.forecasts import outlook
from farmable_backend.models import AdvisoryOpportunity, Farm, FarmProfile, Section
from farmable_backend.planning.contracts import PlanRequest
from farmable_backend.planning.service import Planner
from farmable_backend.record_access import ApiError, section_scope

DECLARATIONS = [
    {
        "name": "find_funding",
        "description": (
            "Find curated South African agricultural funding opportunities matched to the "
            "current farm profile. Show source and verification date; never claim eligibility "
            "is final."
        ),
        "parameters": {"type": "OBJECT", "properties": {"limit": {"type": "INTEGER"}}},
    },
    {
        "name": "find_procurement",
        "description": (
            "Find curated procurement routes and strategy steps for the current farm profile. "
            "Use official sources and say when live tender details must be checked."
        ),
        "parameters": {"type": "OBJECT", "properties": {"limit": {"type": "INTEGER"}}},
    },
    {
        "name": "preview_planting_plan",
        "description": "Compare active-outlook allocations without saving. Ask the farmer for "
        "missing constraints, cost timing and fees; never invent them. Money must be in 2025 ZAR. "
        "Return the preview for explicit confirmation through the app; you cannot confirm it.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "section_id": {"type": "STRING"},
                "planting_date": {"type": "STRING"},
                "budget_cents": {"type": "INTEGER"},
                "money_basis_year": {"type": "INTEGER", "description": "Must be 2025."},
                "crops": {
                    "type": "ARRAY",
                    "items": {
                        "type": "OBJECT",
                        "properties": {
                            "crop": {"type": "STRING"},
                            "minimum_percent": {"type": "INTEGER"},
                            "promised_kg": {"type": "NUMBER"},
                        },
                        "required": ["crop"],
                    },
                },
                "block_count": {"type": "INTEGER"},
                "max_results": {"type": "INTEGER"},
                "cash_deadline": {"type": "STRING"},
                "goal_margin_cents": {"type": "INTEGER"},
                "planting_cost_percent": {"type": "INTEGER"},
                "market_commission_bps": {"type": "INTEGER"},
                "agent_commission_bps": {"type": "INTEGER"},
            },
            "required": [
                "section_id",
                "planting_date",
                "budget_cents",
                "money_basis_year",
                "crops",
                "planting_cost_percent",
                "market_commission_bps",
                "agent_commission_bps",
            ],
        },
    },
    {
        "name": "list_sections",
        "description": "List sections in the current farmer's farm.",
        "parameters": {"type": "OBJECT", "properties": {"limit": {"type": "INTEGER"}}},
    },
    {
        "name": "get_crop_outlook",
        "description": (
            "Read a crop outlook for a section in this farm. "
            "It is not a budget allocation or saved plan."
        ),
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "section_id": {"type": "STRING"},
                "crop": {"type": "STRING"},
                "plant_month": {"type": "INTEGER"},
            },
            "required": ["section_id", "crop", "plant_month"],
        },
    },
]


def execute(store, auth, conversation_id, name, args, mode):
    try:
        if name == "preview_planting_plan":
            request = PlanRequest.model_validate(args)
            # Keep the existing consent/farm lock through this read-only calculation.
            with store.sessions.begin() as session:
                conversation = store.scope(session, auth, conversation_id, lock=True)
                store.require_consent(session, conversation_id)
                section = section_scope(
                    session,
                    conversation.owner_id,
                    conversation.farm_id,
                    request.section_id,
                    lock=True,
                )
                result = (
                    Planner(store.sessions, mode, store.services.integrations_mode)
                    .snapshot(session, section, request)
                    .model_dump(mode="json")
                )
                if len(json.dumps(result).encode()) > 24000:
                    raise ApiError(503, "plan_too_large")
                return result
        if name == "list_sections":
            payload = SectionListArgs.model_validate(args)
            with store.sessions() as session:
                conversation = store.scope(session, auth, conversation_id)
                store.require_consent(session, conversation_id)
                rows = list(
                    session.scalars(
                        select(Section)
                        .where(
                            Section.owner_id == conversation.owner_id,
                            Section.farm_id == conversation.farm_id,
                            Section.deleted_at.is_(None),
                        )
                        .order_by(Section.id)
                        .limit(payload.limit + 1)
                    )
                )
                return {
                    "sections": [
                        {
                            "id": str(row.id),
                            "name": row.name,
                            "area_m2": str(row.area_m2) if row.area_m2 else None,
                        }
                        for row in rows[: payload.limit]
                    ],
                    "truncated": len(rows) > payload.limit,
                }
        if name in {"find_funding", "find_procurement"}:
            payload = AdvisoryArgs.model_validate(args)
            kind = "funding" if name == "find_funding" else "procurement"
            with store.sessions() as session:
                conversation = store.scope(session, auth, conversation_id)
                store.require_consent(session, conversation_id)
                farm = session.scalar(
                    select(Farm).where(
                        Farm.id == conversation.farm_id,
                        Farm.owner_id == conversation.owner_id,
                        Farm.deleted_at.is_(None),
                    )
                )
                profile = session.get(FarmProfile, conversation.farm_id)
                rows = session.scalars(
                    select(AdvisoryOpportunity)
                    .where(
                        AdvisoryOpportunity.kind == kind,
                        AdvisoryOpportunity.active.is_(True),
                    )
                    .order_by(
                        AdvisoryOpportunity.closes_on.is_(None), AdvisoryOpportunity.closes_on
                    )
                    .limit(100)
                ).all()
                if farm is None:
                    raise ApiError(404, "farm_not_found")
                province = (profile.province if profile else "") or ""
                crops = {str(value).lower() for value in (profile.crops if profile else [])}
                today = datetime.now(UTC).date()
                result = []
                for row in rows:
                    if row.closes_on is not None and row.closes_on < today:
                        continue
                    if row.province and row.province.lower() not in {"all", province.lower()}:
                        continue
                    crop_match = (
                        not row.crops
                        or not crops
                        or crops.intersection(str(value).lower() for value in row.crops)
                    )
                    if not crop_match:
                        continue
                    result.append(
                        {
                            "name": row.name,
                            "provider": row.provider,
                            "summary": row.summary,
                            "deadline": row.closes_on.isoformat() if row.closes_on else None,
                            "deadline_note": row.deadline_note,
                            "source_url": row.source_url,
                            "application_url": row.application_url,
                            "verified_on": row.verified_on.isoformat(),
                            "strategy_steps": row.strategy_steps or [],
                        }
                    )
                    if len(result) >= payload.limit:
                        break
                return {"kind": kind, "profile_complete": profile is not None, "matches": result}
        if name == "get_crop_outlook":
            query = OutlookArgs.model_validate(args)
            with store.sessions() as session:
                conversation = store.scope(session, auth, conversation_id)
                store.require_consent(session, conversation_id)
                section_scope(
                    session, conversation.owner_id, conversation.farm_id, query.section_id
                )
            result = outlook(
                store.sessions,
                auth,
                query.section_id,
                query.crop,
                query.plant_month,
                mode,
                store.services.integrations_mode,
            ).model_dump(mode="json")
            if len(json.dumps(result).encode()) > 12000:
                raise ApiError(503, "outlook_too_large")
            return result
        return {"error": "tool_not_allowed"}
    except ValidationError:
        return {"error": "invalid_tool_arguments"}
    except ApiError as error:
        # Authentication loss ends the turn; scope failures reveal no resource details.
        if error.status in {401, 403}:
            raise
        return {"error": error.code}
