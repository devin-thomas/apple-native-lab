"""Temporary repository copies for the validator tests.

Negative fixtures are written only into a copy under the system temporary directory, never into
the checkout, so the repository never holds a broken link or a dependency cycle.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

VALIDATE = Path(__file__).resolve().parent.parent
ROOT = VALIDATE.parent.parent
if str(VALIDATE) not in sys.path:
    sys.path.insert(0, str(VALIDATE))

# These tests run inside CI. Their fixture ledgers, summaries, and annotations must never reach
# the real job, so the variables that point at the job's files are removed for the test process.
CI_VARIABLES = ("GITHUB_STEP_SUMMARY", "GITHUB_ENV", "GITHUB_OUTPUT", "GITHUB_ACTIONS", "LAB_CI_LEDGER")
for _name in CI_VARIABLES:
    os.environ.pop(_name, None)

from common import git_files  # noqa: E402


def source_files() -> list:
    tracked = git_files(ROOT)
    if tracked is not None:
        return [path.relative_to(ROOT) for path in tracked]
    found = []
    for directory, subdirectories, files in os.walk(ROOT):
        subdirectories[:] = [d for d in subdirectories if d not in {".git", "build", ".build", "DerivedData"}]
        found.extend((Path(directory) / name).relative_to(ROOT) for name in files)
    return found


class RepositoryCopyTestCase(unittest.TestCase):
    """Each test gets a fresh copy of every file Git would track, at `self.root`."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="lab-validate-")
        self.addCleanup(self.temporary.cleanup)
        self.outside = Path(os.path.realpath(self.temporary.name))
        self.root = self.outside / "repository"
        for name in source_files():
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)

    def write(self, name: str, text: str) -> Path:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def edit(self, name: str, pattern: str, replacement: str) -> None:
        path = self.root / name
        text = path.read_text(encoding="utf-8")
        changed, count = re.subn(pattern, replacement, text, count=1, flags=re.M)
        self.assertEqual(count, 1, f"fixture edit did not apply to {name}: {pattern}")
        path.write_text(changed, encoding="utf-8")

    def set_depends_on(self, ticket: str, dependencies: list) -> None:
        quoted = ", ".join(f'"{dependency}"' for dependency in dependencies)
        self.edit(f"tickets/{ticket}.md", r"^depends_on: .*$", f"depends_on: [{quoted}]")

    def init_git(self) -> None:
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
