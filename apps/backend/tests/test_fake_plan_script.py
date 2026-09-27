"""The fake model's scripted planning turn (#23): deterministic, opt-in by wording."""

from farmable_backend.assistant import tools
from farmable_backend.integrations.fakes import scripted_plan_step

SECTIONS = {
    "sections": [
        {"id": "s-no-area", "name": "Seedlings", "area_m2": None},
        {"id": "s-first", "name": "North block", "area_m2": "1200.00"},
        {"id": "s-named", "name": "Plan test beds", "area_m2": "400.00"},
    ],
    "truncated": False,
}


def body(message, *answers, mode="AUTO", with_tools=True):
    contents = [{"role": "user", "parts": [{"text": message}]}]
    if answers:
        contents.append({"role": "model", "parts": [{"functionCall": {"name": "x", "args": {}}}]})
        contents.append(
            {
                "role": "user",
                "parts": [
                    {"functionResponse": {"name": name, "response": response}}
                    for name, response in answers
                ],
            }
        )
    request = {
        "contents": contents,
        "toolConfig": {"functionCallingConfig": {"mode": mode}},
    }
    if with_tools:
        request["tools"] = [{"functionDeclarations": tools.DECLARATIONS}]
    return request


def test_other_requests_keep_the_fixture_reply():
    assert scripted_plan_step(body("How is my cabbage doing?")) is None
    assert scripted_plan_step(body("Plan my beds", with_tools=False)) is None
    assert scripted_plan_step(body("Plan my beds", mode="NONE")) is None


def test_a_plan_request_lists_sections_then_previews_the_named_one():
    first = scripted_plan_step(body("Plan cabbage on Plan test beds"))
    assert first == {"functionCall": {"name": "list_sections", "args": {"limit": 20}}}

    second = scripted_plan_step(body("Plan cabbage on Plan test beds", ("list_sections", SECTIONS)))
    call = second["functionCall"]
    assert call["name"] == "preview_planting_plan"
    assert call["args"]["section_id"] == "s-named"
    declared = next(d for d in tools.DECLARATIONS if d["name"] == "preview_planting_plan")
    assert set(declared["parameters"]["required"]) <= set(call["args"])

    third = scripted_plan_step(
        body("Plan cabbage on Plan test beds", ("preview_planting_plan", {"feasible": True}))
    )
    assert "text" in third


def test_without_a_named_section_the_first_with_an_area_is_planned():
    step = scripted_plan_step(body("Make me a plan", ("list_sections", SECTIONS)))
    assert step["functionCall"]["args"]["section_id"] == "s-first"
