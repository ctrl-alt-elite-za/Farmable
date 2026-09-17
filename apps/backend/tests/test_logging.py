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
