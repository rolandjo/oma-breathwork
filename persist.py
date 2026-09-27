#!/usr/bin/env python3
"""Locked, atomic storage for Breathwork. Refuse to overwrite corrupt data."""
import datetime
import fcntl
import json
import math
import os
from pathlib import Path
import sys
import tempfile


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def validate_library(value):
    if not isinstance(value, dict) or value.get("version") != 1 or not isinstance(value.get("protocols"), list):
        raise ValueError("Invalid protocol library; restore the file before saving")
    seen = set()
    for record in value["protocols"]:
        if not isinstance(record, dict):
            raise ValueError("Invalid protocol record")
        key, name = record.get("id"), record.get("name")
        if not isinstance(key, str) or not key or key in seen or not isinstance(name, str) or not name.strip():
            raise ValueError("Invalid or duplicate protocol ID/name")
        seen.add(key)
        for field in ("inhale", "holdIn", "exhale", "holdOut"):
            duration = record.get(field)
            if not number(duration) or not (1 if field in ("inhale", "exhale") else 0) <= duration <= 30:
                raise ValueError("Invalid protocol duration")
    return value


def validate_stats(value):
    if not isinstance(value, dict) or not isinstance(value.get("days"), dict):
        raise ValueError("Invalid history file; restore it before saving")
    for day, minutes in value["days"].items():
        if datetime.date.fromisoformat(day).isoformat() != day or not number(minutes) or minutes < 0:
            raise ValueError("Invalid history entry")
    return value


def read_existing(path, fallback):
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream)
    except FileNotFoundError:
        return fallback


def atomic_write(path, value):
    # Unique files avoid collisions; rename exposes either the old or new JSON.
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, allow_nan=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def persist(path, operation, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with Path(str(path) + ".lock").open("a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if operation == "protocols":
            current = validate_library(read_existing(path, {"version": 1, "protocols": []}))
            expected = validate_library(payload["expected"])
            value = validate_library(payload["library"])
            if current != expected:
                raise ValueError("Protocols changed on disk. Reopen settings and try again")
        elif operation == "add-minutes":
            value = validate_stats(read_existing(path, {"days": {}}))
            day, minutes = payload["day"], payload["minutes"]
            if datetime.date.fromisoformat(day).isoformat() != day or not number(minutes) or minutes <= 0:
                raise ValueError("Invalid session duration/date")
            value["days"][day] = value["days"].get(day, 0) + minutes
        else:
            raise ValueError("Unknown storage operation")
        atomic_write(path, value)


if __name__ == "__main__":
    try:
        persist(sys.argv[1], sys.argv[2], json.loads(sys.argv[3]))
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
