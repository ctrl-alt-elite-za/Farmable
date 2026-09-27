"""Owner-scoped matching against curated, source-backed opportunities."""

from datetime import UTC, date, datetime
from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.advisory_schemas import AdvisoryMatch, FarmProfileUpdate, FarmProfileView
from farmable_backend.models import AdvisoryOpportunity, Farm, FarmProfile
from farmable_backend.record_access import ApiError, authenticate


class AdvisoryService:
    def __init__(self, sessions: sessionmaker[Session]):
        self.sessions = sessions

    def profile(self, authorization: str | None) -> FarmProfileView:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            farm = self._farm(session, owner)
            profile = session.get(FarmProfile, farm.id)
            return self._view(farm, profile)

    def update_profile(
        self, authorization: str | None, payload: FarmProfileUpdate
    ) -> FarmProfileView:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            farm = self._farm(session, owner)
            profile = session.get(FarmProfile, farm.id, with_for_update=True)
            if profile is None:
                profile = FarmProfile(farm_id=farm.id, owner_id=owner)
                session.add(profile)
            for field, value in payload.model_dump(exclude_unset=True).items():
                setattr(profile, field, value)
            session.flush()
            return self._view(farm, profile)

    def matches(self, authorization: str | None, kind: str, limit: int = 10) -> list[AdvisoryMatch]:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            farm = self._farm(session, owner)
            profile = session.get(FarmProfile, farm.id)
            today = datetime.now(UTC).date()
            rows = session.scalars(
                select(AdvisoryOpportunity)
                .where(
                    AdvisoryOpportunity.kind == kind,
                    AdvisoryOpportunity.active.is_(True),
                    or_(
                        AdvisoryOpportunity.closes_on.is_(None),
                        AdvisoryOpportunity.closes_on >= today,
                    ),
                )
                .order_by(AdvisoryOpportunity.closes_on.is_(None), AdvisoryOpportunity.closes_on)
                .limit(100)
            ).all()
            province = (profile.province if profile else "") or ""
            results = [
                self._match(row, profile, today)
                for row in rows
                if row.province is None or row.province.lower() in {"all", province.lower()}
            ]
            results.sort(key=lambda item: (-len(item.match_reasons), item.closes_on or date.max))
            return results[:limit]

    @staticmethod
    def _farm(session: Session, owner: UUID) -> Farm:
        farm = session.scalar(
            select(Farm).where(Farm.owner_id == owner, Farm.deleted_at.is_(None)).order_by(Farm.id)
        )
        if farm is None:
            raise ApiError(404, "farm_not_found")
        return farm

    @staticmethod
    def _view(farm: Farm, profile: FarmProfile | None) -> FarmProfileView:
        values = profile or FarmProfile(farm_id=farm.id, owner_id=farm.owner_id)
        return FarmProfileView(
            farm_id=farm.id,
            owner_id=farm.owner_id,
            province=values.province,
            municipality=values.municipality,
            farmer_type=values.farmer_type,
            business_status=values.business_status,
            farm_size_ha=values.farm_size_ha,
            annual_turnover_band=values.annual_turnover_band,
            crops=values.crops or [],
            goals=values.goals or [],
            equipment=values.equipment or [],
            updated_at=values.updated_at,
        )

    @staticmethod
    def _match(row: AdvisoryOpportunity, profile: FarmProfile | None, today: date) -> AdvisoryMatch:
        reasons: list[str] = []
        missing: list[str] = []
        province = (profile.province if profile else None) or ""
        farmer_type = (profile.farmer_type if profile else None) or ""
        business_status = (profile.business_status if profile else None) or ""
        profile_crops = {str(value).lower() for value in (profile.crops if profile else [])}
        if row.province is None or row.province.lower() in {"all", province.lower()}:
            reasons.append("location matches")
        else:
            return AdvisoryMatch(**AdvisoryService._payload(row, [], ["province"], today))
        if row.farmer_types:
            if farmer_type and farmer_type.lower() in {str(x).lower() for x in row.farmer_types}:
                reasons.append("farmer type matches")
            elif not farmer_type:
                missing.append("farmer_type")
            else:
                return AdvisoryMatch(
                    **AdvisoryService._payload(row, reasons, ["farmer_type"], today)
                )
        if row.business_statuses:
            if business_status and business_status.lower() in {
                str(x).lower() for x in row.business_statuses
            }:
                reasons.append("business status matches")
            elif not business_status:
                missing.append("business_status")
        if row.crops and profile_crops.intersection({str(x).lower() for x in row.crops}):
            reasons.append("crop interest matches")
        elif row.crops and not profile_crops:
            missing.append("crops")
        return AdvisoryMatch(**AdvisoryService._payload(row, reasons, missing, today))

    @staticmethod
    def _payload(row, reasons, missing, today):
        deadline = row.closes_on is None or row.closes_on >= today
        if deadline:
            reasons = [*reasons, "deadline is open or not published"]
        return {
            "id": row.id,
            "kind": row.kind,
            "name": row.name,
            "provider": row.provider,
            "summary": row.summary,
            "match_reasons": reasons,
            "missing_profile_fields": missing,
            "opens_on": row.opens_on,
            "closes_on": row.closes_on,
            "deadline_note": row.deadline_note,
            "source_url": row.source_url,
            "application_url": row.application_url,
            "verified_on": row.verified_on,
            "strategy_steps": row.strategy_steps or [],
        }
