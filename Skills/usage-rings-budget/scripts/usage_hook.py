#!/usr/bin/env python3
"""Read ato?'s snapshot and return optional, client-specific allowance context."""

import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import stat
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone


CLIENTS = {
    "codex": ("codex", "session_id", "PostToolUse"),
    "claude": ("claude", "session_id", "PostToolUse"),
    "cursor": ("cursor", "conversation_id", "postToolUse"),
    "antigravity": ("gemini", "conversationId", "PreInvocation"),
}
MAX_INPUT = 65_536
MAX_STATE = 1_048_576
MAX_SESSIONS = 128
MAX_WINDOWS = 8
MAX_BOUNDARIES = 8
CHECK_INTERVAL = 60
RETENTION = 7 * 24 * 60 * 60
CLI_TIMEOUT = 2
MAX_AGE = 1_200


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def timestamp(value):
    if not isinstance(value, str) or len(value) > 64:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed.timestamp() if parsed.tzinfo else None
    except (ValueError, OverflowError):
        return None


def session_key(client, payload):
    _, field, event = CLIENTS[client]
    if not isinstance(payload, dict):
        return None
    session = payload.get(field)
    if not isinstance(session, str) or not 1 <= len(session) <= 512:
        return None
    actual_event = payload.get("hook_event_name", payload.get("hookEventName"))
    if (actual_event is None and client != "antigravity") or (actual_event is not None and actual_event != event):
        return None
    return hashlib.sha256((client + "\0" + session).encode()).hexdigest()


def find_cli(explicit):
    if explicit:
        path = Path(explicit)
        return path if path.is_absolute() and path.is_file() and os.access(path, os.X_OK) else None
    suffix = "Usage Rings.app/Contents/Helpers/usage-rings"
    candidates = [Path.home() / "Applications" / suffix, Path("/Applications") / suffix]
    found = [path for path in candidates if path.is_file() and os.access(path, os.X_OK)]
    return found[0] if len(found) == 1 else None


def read_report(cli, provider):
    result = subprocess.run(
        [str(cli), "status", "--json", "--provider", provider],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        timeout=CLI_TIMEOUT, check=False,
    )
    if result.returncode != 0 or len(result.stdout) > MAX_INPUT:
        return None
    return json.loads(result.stdout)


def fresh_services(report, provider, now):
    if not isinstance(report, dict) or type(report.get("schemaVersion")) is not int or report["schemaVersion"] != 1:
        return []
    generated = timestamp(report.get("generatedAt"))
    if generated is None or not -60 <= now - generated < MAX_AGE:
        return []
    services, alerts = report.get("services"), report.get("alerts")
    if not isinstance(services, list) or not isinstance(alerts, list):
        return []
    valid = []
    for service in services:
        if not isinstance(service, dict) or service.get("provider") != provider or service.get("state") not in ("ready", "partial"):
            continue
        observed = timestamp(service.get("observedAt"))
        if observed is None or not -60 <= now - observed < MAX_AGE:
            continue
        if not isinstance(service.get("windows"), list):
            continue
        valid.append((service, observed))
    return valid


def fresh_alerts(report, provider, now):
    windows = {}
    for service, observed in fresh_services(report, provider, now):
        for window in service["windows"]:
            if isinstance(window, dict) and isinstance(window.get("id"), str):
                windows[window["id"]] = (window, observed)
    if not windows:
        return []
    valid = {}
    for alert in report["alerts"]:
        if not isinstance(alert, dict) or alert.get("provider") != provider:
            continue
        window_id = alert.get("windowId")
        if not isinstance(window_id, str) or not 1 <= len(window_id) <= 128 or window_id not in windows:
            continue
        window, observed = windows[window_id]
        remaining = alert.get("remainingPercent")
        if (window.get("isMain") is not True or window.get("state") != "ready"
                or not number(remaining) or not 0 <= remaining < 20
                or not number(window.get("remainingPercent"))
                or window.get("remainingPercent") != remaining
                or timestamp(alert.get("observedAt")) != observed):
            continue
        reset_raw = alert.get("resetsAt")
        reset = timestamp(reset_raw)
        expiry = timestamp(window.get("validUntil"))
        if (window.get("resetsAt") != reset_raw or expiry is None or expiry <= now
                or (reset_raw is not None and (reset is None or reset <= now))):
            continue
        stage = next(level for level in (5, 10, 20) if remaining < level)
        valid[window_id] = {"id": window_id, "remaining": remaining, "observed": observed,
                            "reset": reset, "stage": stage, "period": window.get("period")}
    return [valid[key] for key in sorted(valid)[:MAX_WINDOWS]]


def reset_text(reset, now):
    if reset is None:
        return "reset unknown"
    minutes = max(0, math.ceil((reset - now) / 60))
    days, rest = divmod(minutes, 1_440)
    hours, minutes = divmod(rest, 60)
    if days:
        return f"reset in {days}d {hours}h"
    return f"reset in {hours}h {minutes}m" if hours else f"reset in {minutes}m"


def notice_for(alert, provider, now):
    labels = {"codex": "Codex", "claude": "Claude", "cursor": "Cursor", "gemini": "Gemini (Antigravity)"}
    # Only fixed labels and numeric values enter model context; hook payloads and titles may contain instructions.
    window = hashlib.sha256(alert["id"].encode()).hexdigest()[:8]
    known = {"primary": "Primary", "secondary": "Secondary", "five_hour": "5h", "seven_day": "Week",
             "fiveHours": "5h", "week": "Week", "total": "Month"}
    period = alert["period"] if isinstance(alert["period"], str) else None
    title = {"fiveHours": "5h", "week": "Week"}.get(period, known.get(alert["id"], "window " + window))
    observed = datetime.fromtimestamp(alert["observed"], timezone.utc).isoformat(timespec="seconds")
    return (f"ato? / {labels[provider]} / {title}: {alert['remaining']:g}% remaining; "
            f"{reset_text(alert['reset'], now)} (below {alert['stage']}%; observed {observed}).")


def output_for(client, notice):
    if client == "cursor":
        return {"additional_context": notice}
    if client == "antigravity":
        return {"injectSteps": [{"ephemeralMessage": notice}]}
    return {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": notice}}


def secure_file(directory_fd, name, flags):
    descriptor = os.open(name, flags | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK, 0o600, dir_fd=directory_fd)
    info = os.fstat(descriptor)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1:
        os.close(descriptor)
        raise ValueError("Unsafe hook state")
    return descriptor


def load_state(directory_fd):
    try:
        descriptor = secure_file(directory_fd, "state.json", os.O_RDONLY)
    except FileNotFoundError:
        return {}
    with os.fdopen(descriptor, "rb") as source:
        data = source.read(MAX_STATE + 1)
    if len(data) > MAX_STATE:
        raise ValueError("Oversized hook state")
    state = json.loads(data)
    if not isinstance(state, dict) or state.get("version") != 1 or not isinstance(state.get("sessions"), dict):
        raise ValueError("Invalid hook state")
    return state["sessions"]


def save_state(directory_fd, sessions):
    data = json.dumps({"version": 1, "sessions": sessions}, separators=(",", ":"), allow_nan=False).encode()
    if len(data) > MAX_STATE:
        raise ValueError("Oversized hook state")
    temporary = ".state-" + secrets.token_hex(8)
    try:
        descriptor = secure_file(directory_fd, temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(data)
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary, "state.json", src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
    finally:
        try:
            os.unlink(temporary, dir_fd=directory_fd)
        except FileNotFoundError:
            pass


def run(client, payload, cli, state_directory):
    key = session_key(client, payload)
    if key is None or cli is None:
        return None
    root = Path(state_directory)
    root.mkdir(mode=0o700, parents=False, exist_ok=True)
    directory_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    lock_fd = None
    try:
        info = os.fstat(directory_fd)
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            return None
        lock_fd = secure_file(directory_fd, "lock", os.O_RDWR | os.O_CREAT)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        now = time.time()
        sessions = load_state(directory_fd)
        sessions = {session: value for session, value in sessions.items()
                    if isinstance(session, str) and len(session) == 64 and isinstance(value, dict)
                    and number(value.get("checkedAt")) and -60 <= now - value["checkedAt"] < RETENTION}
        previous = sessions.get(key, {})
        if number(previous.get("checkedAt")) and now - previous["checkedAt"] < CHECK_INTERVAL:
            return None
        stages = previous.get("windows", {})
        if not isinstance(stages, dict):
            stages = {}
        current = {"checkedAt": now, "windows": {}}
        if number(previous.get("observed")):
            current["observed"] = previous["observed"]
        notices = []
        try:
            report = read_report(cli, CLIENTS[client][0])
            alerts = fresh_alerts(report, CLIENTS[client][0], time.time())
            # A later high reading also supersedes an older low reading, even when it has no alert.
            for _, observed in fresh_services(report, CLIENTS[client][0], time.time()):
                current["observed"] = max(current.get("observed", observed), observed)
            for alert in alerts:
                old = stages.get(alert["id"], {})
                boundaries = old.get("notices", {}) if isinstance(old, dict) else {}
                boundaries = {boundary: stage for boundary, stage in boundaries.items()
                              if isinstance(boundary, str) and len(boundary) <= 64 and stage in (5, 10, 20)} if isinstance(boundaries, dict) else {}
                boundary = str(alert["reset"])
                if isinstance(old, dict) and old.get("stage") in (5, 10, 20):
                    boundaries.setdefault(str(old.get("reset")), old["stage"])
                already = boundaries.get(boundary)
                if (number(current.get("observed")) and current["observed"] > alert["observed"]
                        or number(previous.get("observed")) and previous["observed"] >= alert["observed"]
                        or isinstance(old, dict) and number(old.get("observed")) and old["observed"] >= alert["observed"]):
                    continue
                if already not in (5, 10, 20) or alert["stage"] < already:
                    notices.append(notice_for(alert, CLIENTS[client][0], time.time()))
                    already = alert["stage"]
                boundaries.pop(boundary, None)
                boundaries[boundary] = already
                boundaries = dict(list(boundaries.items())[-MAX_BOUNDARIES:])
                current["windows"][alert["id"]] = {"reset": alert["reset"], "stage": already,
                                                    "observed": alert["observed"], "notices": boundaries}
        except (OSError, ValueError, TypeError, RecursionError, subprocess.SubprocessError):
            pass
        # Missing/expired data must not erase a stage and repeat it when the cache becomes readable again.
        for window, value in stages.items():
            if window not in current["windows"] and isinstance(value, dict) and len(current["windows"]) < MAX_WINDOWS:
                current["windows"][window] = value
        sessions[key] = current
        sessions = dict(sorted(sessions.items(), key=lambda item: item[1]["checkedAt"], reverse=True)[:MAX_SESSIONS])
        save_state(directory_fd, sessions)
        return output_for(client, "\n".join(notices)) if notices else None
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
        os.close(directory_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", choices=CLIENTS, required=True)
    parser.add_argument("--cli", help="Absolute path to the installed usage-rings helper")
    parser.add_argument("--state-dir", default=str(Path(tempfile.gettempdir()) / f"ato-budget-hooks-{os.getuid()}"))
    args = parser.parse_args()
    output = None
    try:
        data = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(data) <= MAX_INPUT:
            payload = json.loads(data)
            output = run(args.client, payload, find_cli(args.cli), args.state_dir)
    except (OSError, ValueError, TypeError, OverflowError, RecursionError, subprocess.SubprocessError):
        # An unavailable allowance is unknown; a monitoring hook must never block authorized work.
        pass
    print(json.dumps(output or {}, separators=(",", ":"), allow_nan=False))


if __name__ == "__main__":
    main()
