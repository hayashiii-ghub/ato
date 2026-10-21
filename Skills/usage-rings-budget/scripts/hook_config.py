#!/usr/bin/env python3
"""Print a hook configuration fragment without reading or changing settings."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shlex
import sys


CLIENTS = ("codex", "claude", "cursor", "antigravity")


class _ConfigParser(argparse.ArgumentParser):
    def print_help(self, file=None):
        # Preview callers reserve stdout for configuration JSON, including on --help.
        super().print_help(file=sys.stderr if file is None else file)


def _absolute_path(path: str) -> str:
    if not path:
        raise ValueError("Paths must not be empty.")
    return str(Path(path).expanduser().resolve())


def config_for(client: str, runner: str, cli: str | None = None) -> dict:
    if client not in CLIENTS:
        raise ValueError("Unsupported client: " + client)
    command = "python3 " + shlex.quote(_absolute_path(runner)) + " --client " + client
    if cli is not None:
        command += " --cli " + shlex.quote(_absolute_path(cli))

    if client == "cursor":
        return {"version": 1, "hooks": {"postToolUse": [{"command": command, "timeout": 5}]}}

    handler = {"type": "command", "command": command, "timeout": 5}
    if client == "antigravity":
        return {"ato-budget": {"PreInvocation": [handler]}}
    if client == "codex":
        handler.update({"async": True, "additionalContextLimit": 256})
    return {"hooks": {"PostToolUse": [{"matcher": ".*", "hooks": [handler]}]}}


def main() -> None:
    parser = _ConfigParser(description=__doc__)
    parser.add_argument("--client", choices=CLIENTS, required=True)
    parser.add_argument("--runner", default=str(Path(__file__).with_name("usage_hook.py")))
    parser.add_argument("--cli")
    arguments = parser.parse_args()
    try:
        configuration = config_for(arguments.client, arguments.runner, arguments.cli)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    json.dump(configuration, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
