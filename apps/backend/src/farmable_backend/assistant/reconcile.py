"""Read-only comparison of a bounded Google billing JSON snapshot and usage ledger.

No cloud credentials, BigQuery queries, budget refunds, or changes to billing.
The operator supplies a complete export snapshot and explicit account/project scope.
"""

import argparse
import hashlib
import json
from datetime import UTC, datetime
from decimal import Decimal, InvalidOperation, localcontext
from pathlib import Path

from sqlalchemy import func, select

from farmable_backend.models import AssistantModelCall, AssistantTurn

MAX_BYTES = 16 * 1024 * 1024
MAX_ROWS = 20_000


class ReconciliationError(ValueError):
    """Fixed codes only; never print private billing rows or credentials."""


def timestamp(value):
    try:
        result = datetime.fromisoformat(value)
        if result.tzinfo is None:
            raise ValueError
        return result.astimezone(UTC)
    except (TypeError, ValueError):
        raise ReconciliationError("invalid_timestamp") from None


def money(value):
    try:
        if isinstance(value, bool) or len(str(value)) > 64:
            raise ValueError
        result = Decimal(str(value))
        exponent = result.as_tuple().exponent
        if (
            not result.is_finite()
            or abs(result) > Decimal("1e12")
            or not isinstance(exponent, int)
            or exponent < -18
        ):
            raise ValueError
        return result
    except (InvalidOperation, ValueError, TypeError):
        raise ReconciliationError("invalid_money") from None


def rows(raw):
    if len(raw) > MAX_BYTES:
        raise ReconciliationError("export_too_large")
    try:
        text = raw.decode("utf-8")
        if text.lstrip().startswith("["):
            result = json.loads(text, parse_float=Decimal)
        else:
            result = [
                json.loads(line, parse_float=Decimal) for line in text.splitlines() if line.strip()
            ]
        if (
            not isinstance(result, list)
            or not 0 < len(result) <= MAX_ROWS
            or not all(isinstance(row, dict) for row in result)
        ):
            raise ValueError
        return result
    except (ValueError, UnicodeError, RecursionError):
        raise ReconciliationError("invalid_export") from None


def export_totals(raw, *, account, project, service_ids, start, end):
    with localcontext() as context:
        context.prec = 50
        return _export_totals(
            raw, account=account, project=project, service_ids=service_ids, start=start, end=end
        )


def _export_totals(raw, *, account, project, service_ids, start, end):
    if not account or not project or not service_ids or not start < end:
        raise ReconciliationError("scope_required")
    gross = credits = Decimal(0)
    count = ignored = 0
    months, export_times = set(), []
    try:
        for row in rows(raw):
            if (
                row.get("billing_account_id") != account
                or (row.get("project") or {}).get("id") != project
                or (row.get("service") or {}).get("id") not in service_ids
            ):
                ignored += 1
                continue
            first, last = timestamp(row["usage_start_time"]), timestamp(row["usage_end_time"])
            if last <= first:
                raise ReconciliationError("invalid_usage_interval")
            if last <= start or first >= end:
                ignored += 1
                continue
            if first < start or last > end:
                raise ReconciliationError("partial_usage_interval")
            if row["currency"] != "USD":
                raise ReconciliationError("currency_conversion_required")
            month = row["invoice"]["month"]
            if not isinstance(month, str) or len(month) != 6:
                raise ValueError
            datetime.strptime(month, "%Y%m")
            if row["cost_type"] not in {"regular", "adjustment", "tax", "rounding_error"}:
                raise ValueError
            exported = timestamp(row["export_time"])
            if exported < last:
                raise ReconciliationError("invalid_export_time")
            gross += money(row["cost"])
            if not isinstance(row["credits"], list):
                raise ValueError
            credits += sum((money(credit["amount"]) for credit in row["credits"]), Decimal(0))
            months.add(month)
            export_times.append(exported)
            count += 1
    except ReconciliationError:
        raise
    except (KeyError, TypeError, ValueError, AttributeError):
        raise ReconciliationError("invalid_billing_row") from None
    if count == 0:
        raise ReconciliationError("no_matching_rows")
    return {
        "scope": {
            "project": project,
            "account_sha256": hashlib.sha256(account.encode()).hexdigest(),
            "service_ids": sorted(set(service_ids)),
            "start": start.isoformat(),
            "end": end.isoformat(),
        },
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "selected_rows": count,
        "ignored_rows": ignored,
        "invoice_months": sorted(months),
        "latest_export_time": max(export_times).isoformat(),
        "gross_usd": str(gross),
        "credits_usd": str(credits),
        "net_usd": str(gross + credits),
    }


def ledger_totals(sessions, project, start, end):
    bounds = (
        AssistantModelCall.created_at >= start,
        AssistantModelCall.created_at < end,
        AssistantModelCall.data_kind == "provider",
    )
    with sessions() as session:
        states = session.execute(
            select(
                AssistantModelCall.state,
                func.count(),
                func.sum(AssistantModelCall.estimated_micro_usd),
            )
            .where(*bounds, AssistantModelCall.billing_project == project)
            .group_by(
                AssistantModelCall.state,
            )
        ).all()
        unscoped = session.scalar(
            select(func.count())
            .select_from(AssistantModelCall)
            .where(
                *bounds,
                AssistantModelCall.billing_project.is_(None),
            )
        )
        no_receipt = session.scalar(
            select(func.count())
            .select_from(AssistantTurn)
            .where(
                AssistantTurn.created_at >= start,
                AssistantTurn.created_at < end,
                AssistantTurn.model != "fixture-model",
                ~select(AssistantModelCall.id)
                .where(
                    AssistantModelCall.turn_id == AssistantTurn.id,
                )
                .exists(),
            )
        )
    return {
        "priced_calls": sum(count for state, count, _ in states if state == "priced"),
        "unknown_calls": sum(count for state, count, _ in states if state != "priced"),
        "estimated_micro_usd": sum(cost or 0 for _, _, cost in states),
        "unscoped_calls": unscoped,
        "turns_without_receipts": no_receipt,
    }


def compare(export, ledger):
    estimate = Decimal(ledger["estimated_micro_usd"]) / 1_000_000
    incomplete = any(
        ledger[name] for name in ("unknown_calls", "unscoped_calls", "turns_without_receipts")
    )
    with localcontext() as context:
        context.prec = 50
        difference = Decimal(export["gross_usd"]) - estimate
    return {
        "schema_version": 1,
        "status": "incomplete_ledger"
        if incomplete or not ledger["priced_calls"]
        else ("matches_recorded_estimate" if difference == 0 else "difference"),
        "ledger": ledger,
        "billing_snapshot": export,
        "gross_minus_estimate_usd": str(difference),
        "invoice_verified": False,
        "warning": (
            "Comparison to the supplied usage-window export only, "
            "not invoice finality or a spend-cap guarantee. "
            "Live voice, diagnosis and other providers are not priced by this text ledger. "
            "Late charges/credits and legacy or deleted pre-ledger turns "
            "require operator reconciliation. "
            "Reruns compare a full snapshot; they do not accumulate charges or refund reservations."
        ),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export", type=Path, required=True)
    parser.add_argument("--billing-account", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--service-id", action="append", required=True)
    parser.add_argument("--start", required=True)
    parser.add_argument("--end", required=True)
    args = parser.parse_args()
    database = None
    try:
        from farmable_backend.config import Settings
        from farmable_backend.database import Database

        first, last = timestamp(args.start), timestamp(args.end)
        with args.export.open("rb") as source:
            raw = source.read(MAX_BYTES + 1)
        export = export_totals(
            raw,
            account=args.billing_account,
            project=args.project,
            service_ids=args.service_id,
            start=first,
            end=last,
        )
        database = Database(Settings())
        report = compare(export, ledger_totals(database.sessions, args.project, first, last))
        print(json.dumps(report, sort_keys=True))
        return 0 if report["status"] == "matches_recorded_estimate" else 1
    except ReconciliationError as error:
        print(json.dumps({"error": str(error)}))
        return 2
    except Exception:
        print(json.dumps({"error": "reconciliation_unavailable"}))
        return 2
    finally:
        if database is not None:
            database.close()


if __name__ == "__main__":
    raise SystemExit(main())
