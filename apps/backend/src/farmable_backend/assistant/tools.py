"""An explicit read-only tool allowlist. Never dispatch arbitrary names/SQL/URLs."""

import json

from pydantic import ValidationError
from sqlalchemy import select

from farmable_backend.assistant.schemas import OutlookArgs, SectionListArgs
from farmable_backend.forecasts import outlook
from farmable_backend.models import Section
from farmable_backend.record_access import ApiError, section_scope

DECLARATIONS = [
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
        if name == "list_sections":
            payload = SectionListArgs.model_validate(args)
            with store.sessions() as session:
                conversation = store.scope(session, auth, conversation_id)
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
        if name == "get_crop_outlook":
            query = OutlookArgs.model_validate(args)
            with store.sessions() as session:
                conversation = store.scope(session, auth, conversation_id)
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
        if error.status == 401:
            raise
        return {"error": error.code}
