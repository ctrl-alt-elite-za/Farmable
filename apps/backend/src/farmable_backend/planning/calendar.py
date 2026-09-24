"""Reviewed SA payment calendar. Refuse years outside the published coverage."""

from calendar import monthrange
from datetime import date, timedelta

from farmable_backend.record_access import ApiError

CALENDAR_VERSION = "za-2026-2027-reviewed-2026-09-23"
# Sources and the extra proclamation are documented in production-planning.md.
EASTER_HOLIDAYS = {2026: ((4, 3), (4, 6)), 2027: ((3, 26), (3, 29))}
FIXED = ((1, 1), (3, 21), (4, 27), (5, 1), (6, 16), (8, 9), (9, 24), (12, 16), (12, 25), (12, 26))
EXTRA = {date(2026, 11, 4)}


def holidays(year):
    if year not in EASTER_HOLIDAYS:
        raise ApiError(422, "calendar_unavailable")
    days = {date(year, month, day) for month, day in (*FIXED, *EASTER_HOLIDAYS[year])}
    days |= {day + timedelta(days=1) for day in days if day.weekday() == 6}
    return days | {day for day in EXTRA if day.year == year}


def payment_date(harvest):
    result, remaining = harvest, 5
    while remaining:
        result += timedelta(days=1)
        if result.weekday() < 5 and result not in holidays(result.year):
            remaining -= 1
    return result


def add_months(start, months):
    offset = start.year * 12 + start.month - 1 + months
    year, month = offset // 12, offset % 12 + 1
    if year not in EASTER_HOLIDAYS:
        raise ApiError(422, "calendar_unavailable")
    return date(year, month, min(start.day, monthrange(year, month)[1]))
