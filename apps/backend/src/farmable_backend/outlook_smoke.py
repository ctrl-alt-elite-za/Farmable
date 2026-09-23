"""Staging-only, authenticated HTTP acceptance for the explicitly seeded demo farm.

The trusted operator job creates one short-lived session for an ALREADY verified
demo identity. It never creates/verifies a user, changes a farm, or exposes a token.
"""

import hashlib
import json
import logging
import os
import re
import secrets
import time
from datetime import UTC, datetime, timedelta
from typing import Literal
from uuid import uuid4

import httpx
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.demo_seed import DEMO_CABBAGE_SECTION_ID, DEMO_FARM_ID, DEMO_OWNER_ID
from farmable_backend.forecast_contract import CROPS, SAMPLE_WARNING, Outlook
from farmable_backend.models import AuthIdentity, AuthSession
from farmable_backend.record_access import db_now, farm_scope, section_scope


class SmokeConfig(BaseModel):
    model_config = ConfigDict(hide_input_in_errors=True)
    environment: Literal["staging"]
    mode: Literal["sample", "historical"]
    api_url: str = Field(pattern=r"^https://[a-z0-9-]+(?:\.[a-z0-9-]+)*\.run\.app$")
    commit_sha: str = Field(pattern=r"^[0-9a-f]{40}$")


def read_response(client: httpx.Client, path: str, deadline: float, **kwargs) -> tuple[int, dict]:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError("smoke_deadline")
    with client.stream("GET", path, timeout=min(5, remaining), **kwargs) as response:
        data = bytearray()
        for chunk in response.iter_bytes():
            if time.monotonic() >= deadline or len(data) + len(chunk) > 65_536:
                raise ValueError("smoke_response_limit")
            data.extend(chunk)
        if path == "/outlook" and response.status_code == 200:
            if response.headers.get("cache-control") != "no-store":
                raise ValueError("smoke_cache_policy")
        value = json.loads(data)
        if not isinstance(value, dict):
            raise ValueError("smoke_response_shape")
        return response.status_code, value


def check_outlooks(client: httpx.Client, config: SmokeConfig, bearer: str, deadline: float) -> int:
    run_id = None
    count = 0
    for crop in CROPS:
        for month in range(1, 13):
            status, body = read_response(
                client,
                "/outlook",
                deadline,
                params={
                    "section_id": str(DEMO_CABBAGE_SECTION_ID),
                    "crop": crop,
                    "plant_month": month,
                },
                headers={"Authorization": bearer},
            )
            if status != 200:
                raise ValueError("smoke_outlook_unavailable")
            view = Outlook.model_validate(body)
            amounts = (
                view.price_range.p10,
                view.price_range.p50,
                view.price_range.p90,
                view.cost_per_ha,
                view.yield_kg_per_ha,
                view.break_even_price_per_kg,
            )
            if (
                view.crop != crop
                or view.plant_month != month
                or not 1 <= view.harvest_month <= 12
                or not all(value.is_finite() and value > 0 for value in amounts)
                or not view.price_range.p10 <= view.price_range.p50 <= view.price_range.p90
                or view.forecast_as_of > datetime.now(UTC)
                or re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", view.run_id) is None
                or (run_id is not None and view.run_id != run_id)
            ):
                raise ValueError("smoke_outlook_invalid")
            if config.mode == "sample":
                if (
                    view.data_kind != "synthetic"
                    or view.warning != SAMPLE_WARNING
                    or view.method != "fixture"
                ):
                    raise ValueError("smoke_sample_label")
            elif view.data_kind != "historical" or view.method == "fixture":
                raise ValueError("smoke_historical_kind")
            run_id = view.run_id
            count += 1
    return count


def smoke(sessions: sessionmaker[Session], config: SmokeConfig, client: httpx.Client) -> int:
    deadline = time.monotonic() + 120
    status, health = read_response(client, "/health/ready", deadline)
    if status != 200 or health.get("sha") != config.commit_sha:
        raise ValueError("smoke_wrong_revision")
    status, _ = read_response(
        client,
        "/outlook",
        deadline,
        params={"section_id": str(DEMO_CABBAGE_SECTION_ID), "crop": "cabbage", "plant_month": 1},
        headers={"Authorization": ""},
    )
    if status != 401:
        raise ValueError("smoke_auth_required")
    token = secrets.token_urlsafe(32)
    session_id = uuid4()
    with sessions.begin() as session:
        identity = session.get(AuthIdentity, DEMO_OWNER_ID)
        if identity is None or not identity.phone_verified or not identity.email_verified:
            raise ValueError("smoke_demo_identity_unverified")
        farm_scope(session, DEMO_OWNER_ID, DEMO_FARM_ID)
        section_scope(session, DEMO_OWNER_ID, DEMO_FARM_ID, DEMO_CABBAGE_SECTION_ID)
        session.add(
            AuthSession(
                id=session_id,
                user_id=DEMO_OWNER_ID,
                access_token_hash=hashlib.sha256(token.encode()).hexdigest(),
                refresh_token_hash=hashlib.sha256(secrets.token_bytes(32)).hexdigest(),
                expires_at=db_now(session) + timedelta(minutes=3),
            )
        )
    try:
        return check_outlooks(client, config, f"Bearer {token}", deadline)
    finally:
        # Delete only our own temporary session. If the job dies or DB is down,
        # its three-minute expiry still limits exposure; no refresh token exists.
        with sessions.begin() as session:
            own_session = session.get(AuthSession, session_id)
            if own_session is not None:
                session.delete(own_session)


def main() -> int:
    database = None
    count = 0
    succeeded = False
    # The CLI prints fixed status only, never headers, response bodies or DB errors.
    for name in ("httpx", "httpcore", "sqlalchemy"):
        logging.getLogger(name).setLevel(logging.CRITICAL)
    try:
        config = SmokeConfig(
            environment=os.environ.get("ENVIRONMENT", ""),  # type: ignore[arg-type]
            mode=os.environ.get("FORECAST_DATA_MODE", ""),  # type: ignore[arg-type]
            api_url=os.environ.get("OUTLOOK_SMOKE_API_URL", ""),
            commit_sha=os.environ.get("COMMIT_SHA", ""),
        )
        database = Database(Settings())
        with httpx.Client(
            base_url=config.api_url, follow_redirects=False, trust_env=False
        ) as client:
            count = smoke(database.sessions, config, client)
        succeeded = True
    except Exception:
        succeeded = False
    finally:
        if database is not None:
            try:
                database.close()
            except Exception:
                succeeded = False
    if succeeded:
        print(f"PASS: outlook present for all demo crops ({count} crop/month checks)")
        return 0
    print("FAIL: outlook smoke; check staging configuration, demo identity and active forecast")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
