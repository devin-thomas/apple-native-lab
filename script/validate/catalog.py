"""The bundled catalog, experiments.json, matches the experiment specs.

Runs the repository's own generator in check mode, so the rule lives in one place.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from common import CheckResult

CHECK = "catalog"
GENERATOR = Path("script/generate_catalog.py")


def check(root: Path) -> CheckResult:
    generator = root / GENERATOR
    if not generator.exists():
        return CheckResult(CHECK, "blocked", f"{GENERATOR} is missing, so catalog freshness cannot be checked")
    process = subprocess.run(
        [sys.executable, str(generator), "--check"], cwd=root, capture_output=True, text=True,
    )
    output = (process.stdout + process.stderr).strip()
    if process.returncode == 0:
        return CheckResult(CHECK, "passed", f"{GENERATOR} --check: {output or 'exit 0'}")
    return CheckResult(
        CHECK, "failed", f"{GENERATOR} --check exited {process.returncode}",
        [output or "no output"],
    )
