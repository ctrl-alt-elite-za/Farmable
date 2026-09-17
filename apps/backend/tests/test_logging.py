import json
import logging

import pytest
from farmable_backend.logging import JsonFormatter, mask, mask_text, request_id


def test_log_masking():
    record = logging.LogRecord(
        "test",
        logging.INFO,
        __file__,
        1,
        "Contact +27821234567 farmer@example.com token=secret-code OTP=123456 at -26.2041,28.0473",
        (),
        None,
    )
    record.fields = {
        "phone": "+27821234567",
        "email": "farmer@example.com",
        "token": "abc",
        "code": 123456,
        "coordinates": [-26.2041, 28.0473],
        "nested": {"password": "sensitive", "text": "farmer@example.com"},
    }
    encoded = JsonFormatter().format(record)
    data = json.loads(encoded)
    assert "+27******567" in encoded
    assert data["fields"]["phone"] == "+27******567"
    for secret in [
        "+27821234567",
        "farmer@example.com",
        "secret-code",
        "123456",
        "26.2041",
        "28.0473",
        "sensitive",
    ]:
        assert secret not in encoded
    assert data["request_id"] == "system"


@pytest.mark.parametrize(
    "value",
    [
        "Bearer top-secret",
        "password=abc",
        "postgresql://user:secret@host/db",
        "eyJhbGciOiJIUzI1NiJ9abcdef.eyJzdWIiOiJmYXJtZXIifQ.signature",
        "verification 123456",
        "location -26.204100 28.047300",
    ],
)
def test_free_text_sensitive_values(value):
    assert mask_text(value) != value


@pytest.mark.parametrize("phone", ["27821234567", "+27821234567", "0821234567"])
def test_phone_numbers_are_masked_in_messages_and_string_fields(phone):
    record = logging.LogRecord("test", logging.INFO, __file__, 1, "Contact %s", (phone,), None)
    record.fields = {"msisdn": phone, "phone": phone, "route": f"/contact/{phone}"}
    encoded = JsonFormatter().format(record)
    assert phone not in encoded
    assert json.loads(encoded)["fields"]["msisdn"] == "[redacted]"


@pytest.mark.parametrize(
    "fields",
    [
        {"lat": -26.2041, "lng": 28.0473},
        {"mobile": 27821234567},
        {"point": [-26.2041, 28.0473]},
        {"future_field": "short-private-value"},
        {"nested": {"status": 500, "mobile": 27821234567}},
        {"items": [{"lat": -26.2041}, {"lng": 28.0473}]},
        {"": 27821234567},
    ],
)
def test_unlisted_structured_fields_are_redacted_by_default(fields):
    record = logging.LogRecord("test", logging.INFO, __file__, 1, "Safe event", (), None)
    record.fields = fields
    encoded = JsonFormatter().format(record)
    assert json.loads(encoded)["fields"] == dict.fromkeys(fields, "[redacted]")
    for secret in ["26.2041", "28.0473", "27821234567", "short-private-value"]:
        assert secret not in encoded


def test_allowlisted_operational_fields_remain_useful():
    fields = {"status": 500, "method": "GET", "route": "/health/ready", "duration_ms": 12.5}
    record = logging.LogRecord("test", logging.INFO, __file__, 1, "Request completed", (), None)
    record.fields = fields
    assert json.loads(JsonFormatter().format(record))["fields"] == fields


@pytest.mark.parametrize("field", ["status", "method", "route", "duration_ms", "phone"])
def test_allowlisted_fields_do_not_allow_nested_payloads(field):
    assert mask({field: {"point": [-26.2041, 28.0473]}}) == {field: "[redacted]"}
    assert mask({field: [-26.2041, 28.0473, 27821234567]}) == {field: "[redacted]"}


def test_unkeyed_numeric_values_are_redacted():
    assert mask([-26.2041, 28.0473, 27821234567]) == ["[redacted]"] * 3
    assert mask(27821234567) == "[redacted]"


def test_exception_details_are_not_serialized():
    try:
        raise RuntimeError("private detail")
    except RuntimeError:
        import sys

        record = logging.LogRecord("test", logging.ERROR, __file__, 1, "Failed", (), sys.exc_info())
    assert "private detail" not in JsonFormatter().format(record)
    assert mask(object()) == "[redacted]"


def test_request_context_is_present_on_every_record():
    context = request_id.set("correlation")
    try:
        record = logging.LogRecord("test", logging.INFO, __file__, 1, "hello", (), None)
        assert json.loads(JsonFormatter().format(record))["request_id"] == "correlation"
    finally:
        request_id.reset(context)


def test_queue_argument_reprs_are_never_logged():
    record = logging.LogRecord(
        "procrastinate.worker",
        logging.INFO,
        __file__,
        1,
        "Starting job(phone='sensitive', token='short-secret', coords=[1.2, 2.3])",
        (),
        None,
    )
    assert json.loads(JsonFormatter().format(record))["message"] == "Queue event"
