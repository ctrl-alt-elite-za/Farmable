import asyncio

from farmable_backend.manage import apply_queue_schema


class _Jobs:
    def __init__(self, installed: bool):
        self.installed = installed

    async def check_connection_async(self) -> bool:
        return self.installed


class _Schema:
    def __init__(self):
        self.applied = 0

    async def apply_schema_async(self) -> None:
        self.applied += 1


class _App:
    def __init__(self, installed: bool):
        self.job_manager = _Jobs(installed)
        self.schema_manager = _Schema()


def test_queue_schema_is_applied_to_a_new_database():
    app = _App(installed=False)
    assert asyncio.run(apply_queue_schema(app)) is True
    assert app.schema_manager.applied == 1


def test_queue_schema_is_not_reapplied_on_a_later_deploy():
    """The vendor schema is plain CREATEs: a second apply fails on an existing type."""
    app = _App(installed=True)
    assert asyncio.run(apply_queue_schema(app)) is False
    assert app.schema_manager.applied == 0
