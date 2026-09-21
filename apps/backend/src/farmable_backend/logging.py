import json
import logging
import re
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

request_id: ContextVar[str] = ContextVar("request_id", default="system")
_PHONE = re.compile(r"(?<!\w)(?:\+\d[\d ()-]{8,}\d|0\d{9}|\d{10,15})(?!\w)")
_EMAIL = re.compile(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}")
_CREDENTIAL = re.compile(
    r"(?i)\b(bearer\s+|(?:token|password|secret|api[_-]?key|otp|code)\s*[=:]\s*)" r"[^\s,;\"']+"
)
_URL_PASSWORD = re.compile(r"(://[^\s:/]+:)[^@\s]+(@)")
_TOKEN = re.compile(r"\b[A-Za-z0-9_-]{24,}(?:\.[A-Za-z0-9_-]+)*\b")
_COORDINATE = re.compile(r"(?<!\w)-?\d{1,3}\.\d{3,}(?!\w)")
_CODE = re.compile(r"(?<!\w)\d{4,8}(?!\w)")
_FIELD_ALLOWLIST = frozenset({"status", "method", "route", "duration_ms"})


def correlation_id(value: str | None) -> str:
    try:
        return str(UUID(value or ""))
    except ValueError:
        return str(uuid4())


def mask_phone(match: re.Match[str]) -> str:
    digits = re.sub(r"\D", "", match.group())
    prefix = "+" + digits[:2] if match.group().startswith("+") else digits[:3]
    visible_prefix = 2 if match.group().startswith("+") else 3
    return prefix + "*" * (len(digits) - visible_prefix - 3) + digits[-3:]


def mask_text(value: str) -> str:
    value = _URL_PASSWORD.sub(r"\1[redacted]\2", value)
    value = _CREDENTIAL.sub(r"\1[redacted]", value)
    value = _PHONE.sub(mask_phone, value)
    value = _EMAIL.sub("[email]", value)
    value = _TOKEN.sub("[token]", value)
    value = _COORDINATE.sub("[coordinate]", value)
    return _CODE.sub("[code]", value)


def mask(value: Any, key: str | None = None) -> Any:
    if key is not None:
        # The phone field is a separately masked exception, never a raw allowlist entry.
        if key == "phone" and isinstance(value, str):
            phone = _PHONE.fullmatch(value)
            return mask_phone(phone) if phone else "[redacted]"
        if key not in _FIELD_ALLOWLIST:
            return "[redacted]"
        if isinstance(value, str):
            return mask_text(value)
        if value is None or isinstance(value, bool | int | float):
            return value
        # Even allowlisted names must not carry nested payloads or arbitrary objects.
        return "[redacted]"
    if isinstance(value, dict):
        return {mask_text(str(k)): mask(v, str(k)) for k, v in value.items()}
    if isinstance(value, list | tuple):
        return [mask(v) for v in value]
    return "[redacted]"  # Unkeyed values are not trusted operational metadata.


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        message = mask_text(record.getMessage())
        if record.name.startswith("procrastinate"):
            # Vendor messages embed job argument reprs. Never let those enter our logs.
            message = "Queue event"
        if record.name.startswith(("google.", "urllib3")):
            # Cloud retry/debug messages can contain object URLs, signed
            # credentials and provider response bodies. Keep them opaque even
            # when an operator enables debug logging.
            message = "Storage transport event"
        data = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname.lower(),
            "logger": record.name,
            "request_id": request_id.get(),
            "message": message,
        }
        # Only deliberately structured fields, never exception strings/tracebacks or raw args.
        if hasattr(record, "fields"):
            data["fields"] = mask(record.fields)
        return json.dumps(data, ensure_ascii=True)


def configure_logging(level: str = "info") -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(level=level.upper(), handlers=[handler], force=True)
    # Wire logs contain provider URLs, location queries, and potentially credentials.
    for name in ("httpx", "httpcore"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True
        logger.setLevel(logging.WARNING)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access", "procrastinate", "sqlalchemy"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True
