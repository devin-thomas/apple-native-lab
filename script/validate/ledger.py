"""A run ledger: one JSON object per line, each a check ID, a result, and a detail.

CI steps append to it as they run; the summary reads it at the end, and any required check that
never wrote a line is reported as not-run.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

from common import RESULTS, combine

ENVIRONMENT = "LAB_CI_LEDGER"


def resolve(path) -> Path:
    chosen = path or os.environ.get(ENVIRONMENT)
    if not chosen:
        raise SystemExit(f"no ledger: pass --ledger or set {ENVIRONMENT}")
    return Path(chosen)


def append(path: Path, check: str, result: str, detail: str) -> None:
    if result not in RESULTS:
        raise ValueError(f"unknown result {result!r}; use one of {', '.join(RESULTS)}")
    if not detail.strip():
        raise ValueError("a ledger entry must say what was observed or why the check did not run")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as ledger:
        ledger.write(json.dumps({"check": check, "result": result, "detail": detail}) + "\n")


def read(path: Path) -> dict:
    """{check: (result, detail)}. A check recorded twice keeps its worst result."""
    entries: dict = {}
    if not path.exists():
        return entries
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        entry = json.loads(line)
        check, result, detail = entry["check"], entry["result"], entry["detail"]
        if result not in RESULTS:
            raise ValueError(f"{path}:{number}: unknown result {result!r}")
        if check in entries:
            previous, previous_detail = entries[check]
            worst = combine([previous, result])
            detail = detail if worst == result else previous_detail
            result = worst
        entries[check] = (result, detail)
    return entries
