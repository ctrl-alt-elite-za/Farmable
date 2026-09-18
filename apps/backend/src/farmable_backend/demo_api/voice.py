"""Narrow English demo commands, NOT a Gemini/general-purpose assistant."""

import re
from decimal import Decimal
from typing import Annotated, Self

from pydantic import Field, ValidationError, model_validator

from farmable_backend.planning import PlanningResult, plan_section
from farmable_backend.planning.schemas import DemoModel

from .schemas import DemoSection, PlanInputs

HELP = (
    "Try 'compare cabbage and spinach', 'I only have three thousand rand', "
    "or 'keep at least half as cabbage'. Review the transcript before using it. "
    "This English demo supports only these planning commands; use the controls otherwise."
)
SMALL = dict(
    zip(
        "zero one two three four five six seven eight nine ten eleven twelve thirteen "
        "fourteen fifteen sixteen seventeen eighteen nineteen".split(),
        range(20),
        strict=True,
    )
)
TENS = dict(
    zip(
        "twenty thirty forty fifty sixty seventy eighty ninety".split(),
        range(20, 100, 10),
        strict=True,
    )
)


class VoiceRequest(DemoModel):
    transcript: Annotated[str, Field(min_length=1, max_length=300)]
    controls: PlanInputs

    @model_validator(mode="after")
    def not_blank(self) -> Self:
        if not self.transcript.strip():
            raise ValueError("Transcript cannot be blank")
        return self


class VoiceResponse(DemoModel):
    understood: bool
    reply: Annotated[str, Field(min_length=1, max_length=1000)]
    controls: PlanInputs
    preview: PlanningResult | None = None


def _under_hundred(words: list[str]) -> int | None:
    if len(words) == 1:
        return SMALL.get(words[0], TENS.get(words[0]))
    if len(words) == 2 and words[0] in TENS and words[1] in SMALL:
        unit = SMALL[words[1]]
        if 1 <= unit <= 9:
            return TENS[words[0]] + unit
    return None


def _under_thousand(words: list[str]) -> int | None:
    if len(words) >= 2 and words[1] == "hundred" and 1 <= SMALL.get(words[0], 0) <= 9:
        rest = words[2:]
        if rest and rest[0] == "and":
            rest = rest[1:]
            if not rest:
                return None
        remainder = _under_hundred(rest) if rest else 0
        return SMALL[words[0]] * 100 + remainder if remainder is not None else None
    return _under_hundred(words)


def _spoken_integer(text: str) -> int | None:
    words = text.replace("-", " ").split()
    if "thousand" not in words:
        return _under_thousand(words)
    if words.count("thousand") != 1:
        return None
    index = words.index("thousand")
    thousands = _under_thousand(words[:index])
    rest = words[index + 1 :]
    if rest and rest[0] == "and":
        rest = rest[1:]
        if not rest:
            return None
    remainder = _under_thousand(rest) if rest else 0
    if thousands is None or thousands == 0 or remainder is None:
        return None
    return thousands * 1000 + remainder


def _budget(clause: str) -> int | None:
    match = re.fullmatch(
        r"(?:i (?:only )?have|my budget is|(?:set )?(?:my )?budget(?: to| is)?) "
        r"(?:r\s*|zar\s*)?(.+?)(?: rand)?",
        clause,
    )
    if match is None:
        return None
    amount = match[1]
    if re.fullmatch(r"(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?", amount):
        cents = int(Decimal(amount.replace(",", "")) * 100)
    else:
        number = _spoken_integer(amount)
        if number is None:
            return None
        cents = number * 100
    return cents if 0 <= cents <= 1_000_000_000 else None


def _share(clause: str) -> tuple[str, int] | None:
    match = re.fullmatch(
        r"(?:no,? )?(?:i want to )?keep (?:at least )?(.+?)"
        r"(?: (?:of (?:this|the) section|this section))? "
        r"(?:as )?(cabbage|spinach)",
        clause,
    )
    if match is None:
        planting = re.fullmatch(r"(?:i want to )?plant (?:only )?(cabbage|spinach)", clause)
        return (planting[1], 100) if planting else None
    quantity = match[1]
    if quantity == "half":
        return match[2], 50
    percent = re.fullmatch(r"(.+?)(?: percent|%)", quantity)
    if percent is None:
        return None
    value = (
        int(percent[1]) if re.fullmatch(r"[0-9]{1,3}", percent[1]) else _spoken_integer(percent[1])
    )
    if value is None or not 0 <= value <= 100:
        return None
    return match[2], value


def interpret(request: VoiceRequest, section: DemoSection) -> VoiceResponse:
    # Match the WHOLE command, never extract a valid-looking fragment from an injection/negation.
    text = " ".join(request.transcript.lower().strip().rstrip(".!?").split())
    if text.startswith("please "):
        text = text[7:]
    values = request.controls.model_dump(mode="json")
    budget = _budget(text)
    share = _share(text)
    compared = text in {"compare cabbage and spinach", "compare spinach and cabbage"}
    if budget is None and share is None and not compared:
        # One budget and one share, in either order; 'and' inside a spoken amount stays intact.
        combinations = []
        for separator in re.finditer(r" and ", text):
            left, right = text[: separator.start()], text[separator.end() :]
            for money, minimum in ((_budget(left), _share(right)), (_budget(right), _share(left))):
                if money is not None and minimum is not None:
                    combinations.append((money, minimum))
        if len(combinations) == 1:
            budget, share = combinations[0]
        else:
            return VoiceResponse(understood=False, reply=HELP, controls=request.controls)
    if budget is not None:
        values["budget_cents"] = budget
    if compared:
        values["crops"] = ["cabbage", "spinach"]
    if share is not None:
        crop, percent = share
        values["crops"] = ["cabbage", "spinach"]
        values["min_crop_shares"] = [
            item for item in values["min_crop_shares"] if item["crop"] != crop
        ] + [{"crop": crop, "percent": percent}]
    try:
        controls = PlanInputs.model_validate(values)
    except ValidationError:
        return VoiceResponse(understood=False, reply=HELP, controls=request.controls)
    result = plan_section(controls.for_section(str(section.id), section.area_m2))
    if not result.feasible:
        assert result.reason is not None  # noqa: S101 - planner outcome invariant
        reply = (
            result.reason.message + " No new plan was saved. Sample inputs, not a live forecast."
        )
    else:
        best = result.plans[0]
        blocks = ", ".join(crop or "unplanted" for crop in best.blocks)
        reply = (
            f"The proposed blocks are {blocks}. "
            f"Listed spending is {_money(best.total_cost_cents)}; "
            f"estimated margin after listed costs is {_money(best.margin_cents)}. "
            "Sample inputs, not a live forecast. Nothing is approved yet."
        )
    return VoiceResponse(understood=True, reply=reply, controls=controls, preview=result)


def _money(cents: int) -> str:
    sign = "minus " if cents < 0 else ""
    absolute = abs(cents)
    return f"{sign}R{absolute // 100}.{absolute % 100:02d}"
