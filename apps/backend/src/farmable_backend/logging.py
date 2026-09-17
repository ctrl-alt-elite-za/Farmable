import json
import logging
import re
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

request_id: ContextVar[str] = ContextVar("request_id", default="system")
_PHONE = re.compile(r"(?<!\w)(?:\+\d[\d ()-]{8,}\d|0\d{9})(?!\w)")
_EMAIL = re.compile(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}")
_CREDENTIAL = re.compile(
    r"(?i)\b(bearer\s+|(?:token|password|secret|api[_-]?key|otp|code)\s*[=:]\s*)" r"[^\s,;\"']+"
)
_URL_PASSWORD = re.compile(r"(://[^\s:/]+:)[^@\s]+(@)")
_TOKEN = re.compile(r"\b[A-Za-z0-9_-]{24,}(?:\.[A-Za-z0-9_-]+)*\b")
_COORDINATE = re.compile(r"(?<!\w)-?\d{1,3}\.\d{3,}(?!\w)")
_CODE = re.compile(r"(?<!\w)\d{4,8}(?!\w)")
_SENSITIVE = re.compile(
    r"(?i)(phone|email|token|password|secret|authorization|cookie|api.?key|code|otp|"
    r"latitude|longitude|coordinates|location|geometry|args|kwargs|body|headers)"
)


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


def mask(value: Any, key: str = "") -> Any:
    if "phone" in key.lower() and isinstance(value, str):
        return mask_text(value) if _PHONE.search(value) else "[redacted]"
    if _SENSITIVE.search(key):
        return "[redacted]"
    if isinstance(value, dict):
        return {mask_text(str(k)): mask(v, str(k)) for k, v in value.items()}
    if isinstance(value, list | tuple):
        return [mask(v) for v in value]
    if isinstance(value, str):
        return mask_text(value)
    if value is None or isinstance(value, bool | int | float):
        return value
    return "[redacted]"  # Never serialize arbitrary objects or their repr.


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        message = mask_text(record.getMessage())
        if record.name.startswith("procrastinate"):
            # Vendor messages embed job argument reprs. Never let those enter our logs.
            message = "Queue event"
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
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access", "procrastinate", "sqlalchemy"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True
