"""Authenticated account, privacy, export and deletion routes (#9 backend slice)."""

import hashlib
import io
import json
import zipfile
from datetime import UTC, date, datetime, timedelta
from types import SimpleNamespace
from typing import get_args
from uuid import UUID, uuid4

import pytest
from farmable_backend.account import AccountService
from farmable_backend.account_api import AccountRuntime
from farmable_backend.account_schemas import Language
from farmable_backend.auth import AuthService, Channel, DeterministicFakeOtpProvider, SessionTokens
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.main import create_app
from farmable_backend.models import (
    ACCOUNT_LANGUAGES,
    AuthIdentity,
    AuthSession,
    Base,
    Farm,
    FinancialRecord,
    PhotoAttempt,
    PhotoUpload,
    Section,
    SyncChange,
    SyncMutation,
    User,
    VerificationChallenge,
)
from farmable_backend.photo_jobs import PhotoJobs
from farmable_backend.records_api import RecordRuntime
from farmable_backend.records_service import RecordsService
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

PASSWORD = "correct horse battery staple"  # noqa: S105 - synthetic test credential


def _register(auth, first_name, surname, phone, email):
    user = auth.signup(first_name, surname, phone, email, PASSWORD)
    auth.verify(user.id, Channel.PHONE, "111111")
    tokens = auth.verify(user.id, Channel.EMAIL, "222222")
    assert isinstance(tokens, SessionTokens)
    return tokens


def _headers(tokens):
    return {"Authorization": f"Bearer {tokens.access_token}"}


@pytest.fixture
def accounts(settings):
    # Sequential HTTP checks use SQLite, like the existing ORM unit suite.
    # PostgreSQL ownership and deletion behaviour is covered separately.
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )

    @event.listens_for(engine, "connect")
    def enable_foreign_keys(dbapi_connection, _connection_record):
        cursor = dbapi_connection.cursor()  # raw-sql: allow -- SQLite test configuration.
        cursor.execute("PRAGMA foreign_keys=ON")  # raw-sql: allow -- SQLite test configuration.
        cursor.close()

    Base.metadata.create_all(engine)
    sessions = sessionmaker(engine, expire_on_commit=False)
    auth = AuthService(sessions, DeterministicFakeOtpProvider())
    alice = _register(auth, "Sipho", "Dlamini", "+27123456789", "sipho@example.com")
    bob = _register(auth, "Nandi", "Mokoena", "+27820000000", "nandi@example.com")
    app = create_app(
        settings,
        readiness=lambda: {"database": "ok", "worker": "ok"},
        service_settings=ServiceSettings(environment="ci", integrations_mode="fake"),
    )
    app.state.auth = auth
    app.state.account = AccountRuntime(AccountService(sessions, DeterministicFakeOtpProvider()))
    app.state.records = RecordRuntime(RecordsService(sessions), lambda: None)
    with TestClient(app) as client:
        yield SimpleNamespace(
            client=client, sessions=sessions, auth=auth, alice=alice, bob=bob, app=app
        )
    engine.dispose()


def _seed_records(accounts):
    for tokens, section_name, category in (
        (accounts.alice, "Cabbage", "seed"),
        (accounts.bob, "Spinach", "fuel"),
    ):
        with accounts.sessions.begin() as session:
            farm = session.scalar(select(Farm).where(Farm.owner_id == tokens.user.id))
            section = Section(owner_id=tokens.user.id, farm_id=farm.id, name=section_name)
            session.add(section)
            session.flush()
            session.add(
                FinancialRecord(
                    owner_id=tokens.user.id,
                    farm_id=farm.id,
                    section_id=section.id,
                    type="expense",
                    category=category,
                    amount_cents=1500,
                    date=date(2026, 1, 15),
                )
            )


def _seed_photo_upload(accounts, tokens):
    """Direct ORM inserts, as _seed_records does: the reserve() path would drag
    in rate limiting and object storage this deletion test does not exercise."""
    with accounts.sessions.begin() as session:
        farm = session.scalar(select(Farm).where(Farm.owner_id == tokens.user.id))
        section = Section(owner_id=tokens.user.id, farm_id=farm.id, name="Photo block")
        session.add(section)
        session.flush()
        mutation = SyncMutation(
            mutation_id=uuid4(),
            farm_id=farm.id,
            owner_id=tokens.user.id,
            record_type="media",
            operation="upload",
            record_id=uuid4(),
            request_fingerprint="0" * 64,
        )
        session.add(mutation)
        session.flush()
        upload = PhotoUpload(
            farm_id=farm.id,
            owner_id=tokens.user.id,
            section_id=section.id,
            mutation_row_id=mutation.id,
            local_media_id=uuid4(),
            content_type="image/jpeg",
            byte_length=1234,
        )
        session.add(upload)
        session.flush()
        now = datetime.now(UTC)
        session.add(
            PhotoAttempt(
                upload_id=upload.id,
                sequence=upload.sequence,
                expires_at=now + timedelta(hours=1),
                form_expires_at=now + timedelta(minutes=5),
                next_attempt_at=now,
            )
        )
        return upload.id


def _make_photo_ready_for_cleanup(accounts, upload_id):
    with accounts.sessions.begin() as session:
        upload = session.get(PhotoUpload, upload_id)
        attempt = session.scalar(select(PhotoAttempt).where(PhotoAttempt.upload_id == upload_id))
        old = datetime.now(UTC) - timedelta(hours=2)
        upload.state = "ready"
        attempt.terminal_at = old
        attempt.form_expires_at = old
        attempt.clean_generation = "1"
        return attempt.id


def _seed_sync_change(accounts, tokens):
    """A pre-existing change-feed row, so the post-deletion count assertion is
    not vacuously satisfied by there never having been any rows."""
    with accounts.sessions.begin() as session:
        farm = session.scalar(select(Farm).where(Farm.owner_id == tokens.user.id))
        section = session.scalar(select(Section).where(Section.owner_id == tokens.user.id))
        mutation = SyncMutation(
            mutation_id=uuid4(),
            farm_id=farm.id,
            owner_id=tokens.user.id,
            record_type="section",
            operation="create",
            record_id=section.id,
            request_fingerprint="1" * 64,
        )
        session.add(mutation)
        session.flush()
        session.add(
            SyncChange(
                farm_id=farm.id,
                owner_id=tokens.user.id,
                mutation_id=mutation.id,
                record_type="section",
                record_id=section.id,
                operation="create",
                version=1,
            )
        )


def test_language_options_match_the_database_constraint():
    assert set(get_args(Language)) == set(ACCOUNT_LANGUAGES)


def test_profile_returns_only_the_authenticated_account(accounts):
    response = accounts.client.get("/account/profile", headers=_headers(accounts.alice))
    assert response.status_code == 200
    assert response.json() == {
        "id": str(accounts.alice.user.id),
        "first_name": "Sipho",
        "surname": "Dlamini",
        "phone": "+27123456789",
        "email": "sipho@example.com",
        "phone_verified": True,
        "email_verified": True,
        "preferred_language": "en",
        "pending_email": None,
        "pending_phone": None,
    }
    assert response.headers["cache-control"] == "no-store"


def test_profile_updates_persist(accounts):
    alice = _headers(accounts.alice)
    patched = accounts.client.patch(
        "/account/profile",
        headers=alice,
        json={"first_name": "Sipho Junior", "preferred_language": "zu"},
    )
    assert patched.status_code == 200
    assert patched.json()["first_name"] == "Sipho Junior"
    assert patched.json()["preferred_language"] == "zu"
    assert accounts.client.get("/account/profile", headers=alice).json() == patched.json()
    other = accounts.client.get("/account/profile", headers=_headers(accounts.bob)).json()
    assert other["first_name"] == "Nandi"
    assert other["preferred_language"] == "en"


def test_language_writes_serialize_on_the_owner_row(accounts):
    # account_profiles is a get-or-insert keyed on the owner, so two concurrent
    # first-time language writes would both miss and the second would fail the
    # primary key. The write path must take the owner-row lock first, as
    # voice_api.admit and RecordsService.photo_rate do for their own rate tables.
    # SQLite renders no FOR UPDATE clause, so assert the locking SELECT is issued.
    statements: list[str] = []

    @event.listens_for(accounts.sessions.kw["bind"], "before_cursor_execute")
    def record(conn, cursor, statement, parameters, context, executemany):  # noqa: PLR0913
        statements.append(" ".join(statement.split()))

    try:
        for path, payload in (
            ("/account/profile", {"preferred_language": "st"}),
            ("/account/farm", {"preferred_language": "xh"}),
        ):
            statements.clear()
            response = accounts.client.patch(path, headers=_headers(accounts.alice), json=payload)
            assert response.status_code == 200
            locking = [item for item in statements if item.startswith("SELECT users.id")]
            profile_writes = [
                index
                for index, item in enumerate(statements)
                if "account_profiles" in item and item.startswith(("SELECT", "INSERT", "UPDATE"))
            ]
            assert locking, f"{path} took no owner-row lock: {statements}"
            assert profile_writes, f"{path} never touched account_profiles: {statements}"
            assert statements.index(locking[0]) < profile_writes[0]
    finally:
        event.remove(accounts.sessions.kw["bind"], "before_cursor_execute", record)


def test_profile_rejects_unknown_fields(accounts):
    alice = _headers(accounts.alice)
    response = accounts.client.patch(
        "/account/profile",
        headers=alice,
        json={"owner_id": str(accounts.bob.user.id), "first_name": "Mallory"},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert accounts.client.get("/account/profile", headers=alice).json()["first_name"] == "Sipho"


def test_farm_details_and_preferred_language_updates_persist(accounts):
    alice = _headers(accounts.alice)
    farm = accounts.client.get("/account/farm", headers=alice)
    assert farm.status_code == 200
    assert farm.json()["name"] == "My farm"
    assert farm.json()["owner_id"] == str(accounts.alice.user.id)
    assert farm.json()["preferred_language"] == "en"
    renamed = accounts.client.patch(
        "/account/farm",
        headers=alice,
        json={"name": "Dlamini Farm", "preferred_language": "af"},
    )
    assert renamed.status_code == 200
    assert renamed.json()["name"] == "Dlamini Farm"
    assert renamed.json()["preferred_language"] == "af"
    assert accounts.client.get("/account/farm", headers=alice).json() == renamed.json()
    profile = accounts.client.get("/account/profile", headers=alice).json()
    assert profile["preferred_language"] == "af"
    other = accounts.client.get("/account/farm", headers=_headers(accounts.bob)).json()
    assert other["name"] == "My farm"
    assert other["owner_id"] == str(accounts.bob.user.id)


def test_farm_location_updates_persist(accounts):
    alice = _headers(accounts.alice)
    updated = accounts.client.patch(
        "/account/farm", headers=alice, json={"latitude": -26.2, "longitude": 28.3}
    )
    assert updated.status_code == 200
    assert updated.json()["latitude"] == -26.2
    assert updated.json()["longitude"] == 28.3
    assert accounts.client.get("/account/farm", headers=alice).json() == updated.json()
    other = accounts.client.get("/account/farm", headers=_headers(accounts.bob)).json()
    assert other["latitude"] is None
    assert other["longitude"] is None


def test_farm_location_out_of_range_is_rejected(accounts):
    alice = _headers(accounts.alice)
    response = accounts.client.patch("/account/farm", headers=alice, json={"latitude": 95})
    assert response.status_code == 422


def test_email_change_requires_confirmation_before_it_applies(accounts):
    alice = _headers(accounts.alice)
    patched = accounts.client.patch(
        "/account/profile", headers=alice, json={"email": "sipho.new@example.com"}
    )
    assert patched.status_code == 200
    assert patched.json()["email"] == "sipho@example.com"  # Unchanged until confirmed.
    assert patched.json()["pending_email"] == "sipho.new@example.com"
    confirmed = accounts.client.post(
        "/account/contact/confirm", headers=alice, json={"channel": "email", "code": "222222"}
    )
    assert confirmed.status_code == 200
    assert confirmed.json()["email"] == "sipho.new@example.com"
    assert confirmed.json()["pending_email"] is None
    assert accounts.client.get("/account/profile", headers=alice).json()["email"] == (
        "sipho.new@example.com"
    )


def test_phone_change_requires_confirmation_before_it_applies(accounts):
    alice = _headers(accounts.alice)
    patched = accounts.client.patch(
        "/account/profile", headers=alice, json={"phone": "+27821234567"}
    )
    assert patched.status_code == 200
    assert patched.json()["phone"] == "+27123456789"
    assert patched.json()["pending_phone"] == "+27821234567"
    confirmed = accounts.client.post(
        "/account/contact/confirm", headers=alice, json={"channel": "phone", "code": "111111"}
    )
    assert confirmed.status_code == 200
    assert confirmed.json()["phone"] == "+27821234567"


def test_contact_change_wrong_code_is_rejected_and_does_not_apply(accounts):
    alice = _headers(accounts.alice)
    accounts.client.patch("/account/profile", headers=alice, json={"email": "sipho.new@example.com"})
    wrong = accounts.client.post(
        "/account/contact/confirm", headers=alice, json={"channel": "email", "code": "000000"}
    )
    assert wrong.status_code == 400
    assert wrong.json()["error"]["code"] == "invalid_verification"
    assert accounts.client.get("/account/profile", headers=alice).json()["email"] == (
        "sipho@example.com"
    )


def test_confirm_without_a_pending_change_is_rejected(accounts):
    alice = _headers(accounts.alice)
    response = accounts.client.post(
        "/account/contact/confirm", headers=alice, json={"channel": "email", "code": "222222"}
    )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "no_pending_change"


def test_email_change_to_an_existing_account_is_enumeration_safe(accounts):
    alice = _headers(accounts.alice)
    # Bob's email already exists. The response must look identical to a
    # genuine pending change, and the value must never actually go pending
    # (a later confirm attempt has nothing to confirm).
    patched = accounts.client.patch(
        "/account/profile", headers=alice, json={"email": "nandi@example.com"}
    )
    assert patched.status_code == 200
    assert patched.json()["email"] == "sipho@example.com"
    assert patched.json()["pending_email"] is None
    confirm = accounts.client.post(
        "/account/contact/confirm", headers=alice, json={"channel": "email", "code": "222222"}
    )
    assert confirm.status_code == 400
    assert confirm.json()["error"]["code"] == "no_pending_change"
    # Bob's own account is completely unaffected.
    bob_profile = accounts.client.get("/account/profile", headers=_headers(accounts.bob)).json()
    assert bob_profile["email"] == "nandi@example.com"


def test_contact_change_rejects_unauthenticated_callers(accounts):
    response = accounts.client.post(
        "/account/contact/confirm", json={"channel": "email", "code": "222222"}
    )
    assert response.status_code == 401


def test_owner_scope_blocks_cross_account_reads_and_mutations(accounts):
    alice = _headers(accounts.alice)
    bob = _headers(accounts.bob)
    farm_id = accounts.client.get("/account/farm", headers=alice).json()["id"]
    assert accounts.client.get(f"/farms/{farm_id}/sections", headers=bob).status_code == 404
    intrusion = accounts.client.post(
        f"/farms/{farm_id}/observations",
        headers=bob,
        json={
            "mutation_id": str(uuid4()),
            "observation_id": str(uuid4()),
            "section_id": str(uuid4()),
            "type": "health",
            "note": "Intrusion attempt",
            "created_at": datetime.now(UTC).isoformat(),
        },
    )
    assert intrusion.status_code == 404
    victim = accounts.client.get("/account/profile", headers=alice).json()
    assert victim["email"] == "sipho@example.com"


def test_json_export_contains_only_the_callers_data(accounts):
    _seed_records(accounts)
    alice = _headers(accounts.alice)
    response = accounts.client.get("/account/export?format=json", headers=alice)
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/json")
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["content-disposition"] == (
        'attachment; filename="farmable-export.json"'
    )
    document = response.json()
    assert document["schema_version"] == 1
    assert document["account"]["email"] == "sipho@example.com"
    assert [farm["name"] for farm in document["farms"]] == ["My farm"]
    assert [item["name"] for item in document["sections"]] == ["Cabbage"]
    assert [item["category"] for item in document["financial_records"]] == ["seed"]
    assert document["observations"] == []
    owned = document["farms"] + document["sections"] + document["financial_records"]
    for record in owned:
        assert record["owner_id"] == str(accounts.alice.user.id)
    assert "nandi@example.com" not in response.text
    assert "+27820000000" not in response.text
    assert "Spinach" not in response.text


def test_export_never_contains_credential_or_session_material(accounts):
    alice = _headers(accounts.alice)
    owner_id = accounts.alice.user.id
    with accounts.sessions() as session:
        identity = session.get(AuthIdentity, owner_id)
        challenges = session.scalars(
            select(VerificationChallenge).where(VerificationChallenge.user_id == owner_id)
        ).all()
        stored = session.scalars(select(AuthSession).where(AuthSession.user_id == owner_id)).all()
        assert challenges and stored
        material = [identity.password_hash]
        material += [item.code_hash for item in challenges]
        material += [item.access_token_hash for item in stored]
        material += [item.refresh_token_hash for item in stored]
    body = accounts.client.get("/account/export?format=json", headers=alice).text
    for value in material:
        assert value not in body
    for field in ("password_hash", "code_hash", "access_token_hash", "refresh_token_hash"):
        assert field not in body
    for table in ("verification_challenges", "auth_sessions", "auth_identities"):
        assert table not in body
    assert PASSWORD not in body
    assert accounts.alice.access_token not in body
    assert accounts.alice.refresh_token not in body


def test_zip_export_is_deterministic_and_uses_a_safe_entry_name(accounts):
    _seed_records(accounts)
    alice = _headers(accounts.alice)
    response = accounts.client.get("/account/export?format=zip", headers=alice)
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/zip"
    assert response.headers["content-disposition"] == ('attachment; filename="farmable-export.zip"')
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        assert archive.namelist() == ["export.json"]
        document = json.loads(archive.read("export.json"))
    expected = accounts.client.get("/account/export?format=json", headers=alice).json()
    assert document == expected
    assert "nandi@example.com" not in json.dumps(document)
    assert "Spinach" not in json.dumps(document)
    repeated = accounts.client.get("/account/export?format=zip", headers=alice)
    assert repeated.content == response.content


def test_export_rejects_an_unsupported_format(accounts):
    alice = _headers(accounts.alice)
    response = accounts.client.get("/account/export?format=pdf", headers=alice)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_logout_revokes_only_the_current_session(accounts):
    alice = _headers(accounts.alice)
    second = accounts.auth.login("sipho@example.com", PASSWORD)
    assert accounts.client.post("/auth/logout", headers=alice).status_code == 204
    assert accounts.client.get("/account/profile", headers=alice).status_code == 401
    survivor = accounts.client.get("/account/profile", headers=_headers(second))
    assert survivor.status_code == 200
    stale = accounts.client.post(
        "/auth/refresh", json={"refresh_token": accounts.alice.refresh_token}
    )
    assert stale.status_code == 401


def test_revoke_all_invalidates_every_session_for_the_caller(accounts):
    alice = _headers(accounts.alice)
    second = accounts.auth.login("sipho@example.com", PASSWORD)
    assert accounts.client.post("/auth/revoke-all", headers=alice).status_code == 204
    for tokens in (accounts.alice, second):
        blocked = accounts.client.get("/account/profile", headers=_headers(tokens))
        assert blocked.status_code == 401
        refreshed = accounts.client.post(
            "/auth/refresh", json={"refresh_token": tokens.refresh_token}
        )
        assert refreshed.status_code == 401
    untouched = accounts.client.get("/account/profile", headers=_headers(accounts.bob))
    assert untouched.status_code == 200


def test_delete_requires_password_confirmation(accounts):
    alice = _headers(accounts.alice)
    missing = accounts.client.request("DELETE", "/account", headers=alice, json={})
    assert missing.status_code == 422
    wrong = accounts.client.request(
        "DELETE", "/account", headers=alice, json={"password": "not the password"}
    )
    assert wrong.status_code == 401
    assert wrong.json()["error"]["code"] == "invalid_credentials"
    assert accounts.client.get("/account/profile", headers=alice).status_code == 200


def test_deleted_account_loses_login_refresh_and_record_access(accounts):
    _seed_records(accounts)
    alice = _headers(accounts.alice)
    owner_id = accounts.alice.user.id
    farm_id = accounts.client.get("/account/farm", headers=alice).json()["id"]
    removed = accounts.client.request(
        "DELETE", "/account", headers=alice, json={"password": PASSWORD}
    )
    assert removed.status_code == 204
    assert accounts.client.get("/account/profile", headers=alice).status_code == 401
    assert accounts.client.get(f"/farms/{farm_id}/sections", headers=alice).status_code == 401
    refreshed = accounts.client.post(
        "/auth/refresh", json={"refresh_token": accounts.alice.refresh_token}
    )
    assert refreshed.status_code == 401
    login = accounts.client.post(
        "/auth/login",
        json={
            "identifier": "sipho@example.com",
            "password": PASSWORD,
            "turnstile_token": "fixture-token",
        },
    )
    assert login.status_code == 401
    assert login.json()["error"]["code"] == "invalid_credentials"
    with accounts.sessions() as session:
        assert session.get(AuthIdentity, owner_id) is None
        assert session.get(User, owner_id) is not None
        sessions_left = session.scalars(
            select(AuthSession).where(AuthSession.user_id == owner_id)
        ).all()
        challenges_left = session.scalars(
            select(VerificationChallenge).where(VerificationChallenge.user_id == owner_id)
        ).all()
        assert list(sessions_left) == []
        assert list(challenges_left) == []
        farm = session.get(Farm, UUID(farm_id))
        assert farm is not None and farm.deleted_at is not None
        section = session.scalar(select(Section).where(Section.owner_id == owner_id))
        assert section is not None and section.deleted_at is not None


def test_deletion_retains_photo_upload_rows_for_the_cleanup_worker(accounts):
    # photo_uploads/photo_attempts are deliberately NOT removed by account
    # deletion. PhotoJobs.cleanup_candidates (photo_jobs.py) is a real janitor
    # that finds terminal/expired uploads by joining these two tables and
    # deletes their GCS blobs using a key derived from upload.media_id +
    # attempt.id, stored nowhere else. Hard-deleting these rows here would
    # destroy that key before the janitor ever runs, orphaning the blob in
    # GCS permanently. See account.py:delete_account.
    alice_upload = _seed_photo_upload(accounts, accounts.alice)
    bob_upload = _seed_photo_upload(accounts, accounts.bob)
    removed = accounts.client.request(
        "DELETE", "/account", headers=_headers(accounts.alice), json={"password": PASSWORD}
    )
    assert removed.status_code == 204
    with accounts.sessions() as session:
        assert session.get(PhotoUpload, alice_upload) is not None
        assert (
            session.scalars(
                select(PhotoAttempt).where(PhotoAttempt.upload_id == alice_upload)
            ).all()
            != []
        )
        # The other owner's rows are naturally untouched either way.
        assert session.get(PhotoUpload, bob_upload) is not None
        assert (
            session.scalars(select(PhotoAttempt).where(PhotoAttempt.upload_id == bob_upload)).all()
            != []
        )
    # Unreachable afterward: every account/records route requires a live
    # session, and all of this owner's sessions were revoked by the deletion.
    still_authorized = accounts.client.get("/account/profile", headers=_headers(accounts.alice))
    assert still_authorized.status_code == 401


def test_deletion_requeues_ready_photos_for_full_cleanup(accounts):
    jobs = PhotoJobs(accounts.sessions)
    pending_upload = _seed_photo_upload(accounts, accounts.alice)
    pending_attempt = _make_photo_ready_for_cleanup(accounts, pending_upload)
    cleaned_upload = _seed_photo_upload(accounts, accounts.alice)
    cleaned_attempt = _make_photo_ready_for_cleanup(accounts, cleaned_upload)
    bob_upload = _seed_photo_upload(accounts, accounts.bob)
    bob_attempt = _make_photo_ready_for_cleanup(accounts, bob_upload)

    # Model the normal janitor having already removed the source object while
    # deliberately preserving the ready clean object.
    claim = jobs.cleanup_claim(cleaned_upload, cleaned_attempt)
    assert claim is not None and claim[2] is True
    jobs.cleanup_finish(cleaned_upload, cleaned_attempt, claim[1].cleanup_token, True)

    removed = accounts.client.request(
        "DELETE", "/account", headers=_headers(accounts.alice), json={"password": PASSWORD}
    )
    assert removed.status_code == 204

    with accounts.sessions() as session:
        assert session.get(PhotoUpload, pending_upload).state == "failed"
        assert session.get(PhotoUpload, cleaned_upload).state == "failed"
        assert session.get(PhotoAttempt, cleaned_attempt).cleaned_at is None
        assert session.get(PhotoUpload, bob_upload).state == "ready"

    # Both the never-cleaned and previously-cleaned attempts are durable
    # candidates after the grace period. A fixed time avoids sleeping here.
    deletion_grace_elapsed = datetime.now(UTC) + timedelta(hours=2)
    with pytest.MonkeyPatch.context() as monkeypatch:
        monkeypatch.setattr("farmable_backend.photo_jobs.db_now", lambda _: deletion_grace_elapsed)
        candidates = set(jobs.cleanup_candidates())
        assert (pending_upload, pending_attempt) in candidates
        assert (cleaned_upload, cleaned_attempt) in candidates
        pending_claim = jobs.cleanup_claim(pending_upload, pending_attempt)
        cleaned_claim = jobs.cleanup_claim(cleaned_upload, cleaned_attempt)
        bob_claim = jobs.cleanup_claim(bob_upload, bob_attempt)

    assert pending_claim is not None and pending_claim[2] is False
    assert cleaned_claim is not None and cleaned_claim[2] is False
    assert bob_claim is not None and bob_claim[2] is True


def test_deletion_tombstones_without_publishing_sync_changes(accounts):
    # Pins the documented deviation in delete_account: unlike tombstone_observation
    # and its siblings, the bulk deletion loop sets deleted_at only -- it does not
    # bump version, flip sync_state to "pending", or write a SyncChange row.
    # See the comment on delete_account's loop for why. If that ever changes
    # silently, this test fails rather than the contract drifting unnoticed.
    _seed_records(accounts)
    _seed_sync_change(accounts, accounts.alice)
    owner_id = accounts.alice.user.id
    with accounts.sessions.begin() as session:
        # sync_state defaults to "pending" for every seeded row, which would
        # make the equality assertion below pass even if deletion started
        # flipping it to "pending" itself (the tombstone_* pattern's second
        # field) -- a silent no-op mutation the test couldn't catch. Setting
        # one row to a different value first makes that leg of the pin live:
        # it now only survives if deletion truly leaves sync_state alone.
        farm = session.scalar(select(Farm).where(Farm.owner_id == owner_id))
        farm.sync_state = "synced"
    with accounts.sessions() as session:
        before = {
            model: [
                (row.id, row.version, row.sync_state)
                for row in session.scalars(
                    select(model).where(model.owner_id == owner_id).order_by(model.id)
                )
            ]
            for model in (Farm, Section, FinancialRecord)
        }
        changes_before = session.scalars(
            select(SyncChange).where(SyncChange.owner_id == owner_id)
        ).all()
    assert all(rows for rows in before.values())
    assert len(changes_before) == 1
    removed = accounts.client.request(
        "DELETE", "/account", headers=_headers(accounts.alice), json={"password": PASSWORD}
    )
    assert removed.status_code == 204
    with accounts.sessions() as session:
        for model, rows in before.items():
            after = session.scalars(
                select(model).where(model.owner_id == owner_id).order_by(model.id)
            ).all()
            assert [(row.id, row.version, row.sync_state) for row in after] == rows
            assert all(row.deleted_at is not None for row in after)
        changes_after = session.scalars(
            select(SyncChange).where(SyncChange.owner_id == owner_id)
        ).all()
        assert len(changes_after) == len(changes_before)


def test_deletion_leaves_other_owners_untouched(accounts):
    _seed_records(accounts)
    bob = _headers(accounts.bob)
    removed = accounts.client.request(
        "DELETE", "/account", headers=_headers(accounts.alice), json={"password": PASSWORD}
    )
    assert removed.status_code == 204
    profile = accounts.client.get("/account/profile", headers=bob)
    assert profile.status_code == 200
    assert profile.json()["email"] == "nandi@example.com"
    farm = accounts.client.get("/account/farm", headers=bob)
    assert farm.status_code == 200
    export = accounts.client.get("/account/export?format=json", headers=bob)
    assert "sipho@example.com" not in export.text
    assert [item["name"] for item in export.json()["sections"]] == ["Spinach"]
    stale = accounts.client.get(
        f"/farms/{farm.json()['id']}/sections", headers=_headers(accounts.alice)
    )
    assert stale.status_code == 401


@pytest.mark.parametrize(
    "path", ["/account/profile", "/account/farm", "/account/export?format=json"]
)
def test_account_reads_reject_anonymous_callers(accounts, path):
    response = accounts.client.get(path)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_session"
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("path", ["/auth/logout", "/auth/revoke-all"])
def test_session_routes_reject_anonymous_callers(accounts, path):
    response = accounts.client.post(path)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_session"


def test_unverified_sessions_cannot_reach_account_routes(accounts):
    user = accounts.auth.signup("Thabo", "Nkosi", "+27831112222", "thabo@example.com", PASSWORD)
    accounts.auth.verify(user.id, Channel.PHONE, "111111")
    token = "c" * 43
    with accounts.sessions.begin() as session:
        session.add(
            AuthSession(
                user_id=user.id,
                access_token_hash=hashlib.sha256(token.encode()).hexdigest(),
                refresh_token_hash=hashlib.sha256(b"unverified-refresh").hexdigest(),
                expires_at=datetime.now(UTC) + timedelta(hours=1),
            )
        )
    response = accounts.client.get("/account/profile", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_session"
