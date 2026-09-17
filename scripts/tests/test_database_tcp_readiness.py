"""Prevent migrations starting against Postgres's socket-only bootstrap server."""

import shlex
from pathlib import Path

import yaml


def test_compose_database_health_requires_tcp():
    root = Path(__file__).resolve().parents[2]
    compose = yaml.safe_load((root / "compose.yaml").read_text())
    probe = compose["services"]["database"]["healthcheck"]["test"]
    assert probe[0] == "CMD-SHELL"
    command = shlex.split(probe[1])
    assert command[0] == "pg_isready"
    assert "-h" in command, "Socket readiness includes the temporary initdb server"
    assert command[command.index("-h") + 1] == "127.0.0.1"
