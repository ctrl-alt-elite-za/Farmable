"""A quarantined test must link an issue; it is skipped, never retried silently."""

import pytest


def pytest_collection_modifyitems(items):
    for item in items:
        marker = item.get_closest_marker("quarantine")
        if marker is not None:
            issue = marker.kwargs.get("issue")
            if not isinstance(issue, int) or isinstance(issue, bool) or issue < 1:
                raise pytest.UsageError("quarantine requires issue=<positive issue number>")
            item.add_marker(pytest.mark.skip(reason=f"quarantined: #{issue}"))
