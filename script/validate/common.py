"""Shared result vocabulary and helpers for the repository validators.

Results use the lab's evidence vocabulary (docs/TEST_STRATEGY.md): passed, failed, blocked,
not-run. Only `passed` is passing, and nothing checked is `not-run`, never `passed`. The
precedence matches `RunResult.combining` in Packages/LabSupport. Standard library only.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parent.parent.parent

RESULTS = ("passed", "failed", "blocked", "not-run")
# Distinct exit codes so a caller can tell an incomplete run from a failing one.
# 2 is left to argparse usage errors.
EXIT_CODES = {"passed": 0, "failed": 1, "blocked": 3, "not-run": 4}

# Directories that hold build products or tool state, never documentation.
SKIPPED_DIRS = {".git", "build", ".build", "DerivedData", ".swiftpm", "node_modules", "xcuserdata"}

ID_PATTERN = re.compile(r"^[A-Z]+-\d{3}(-[A-Z])?$")
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.S)


def combine(results: Iterable[str]) -> str:
    """The worst result: failed, then blocked, then not-run. Nothing at all is not-run."""
    seen = set(results)
    unknown = seen - set(RESULTS)
    if unknown:
        raise ValueError(f"unknown result {sorted(unknown)[0]!r}")
    if not seen:
        return "not-run"
    for result in ("failed", "blocked", "not-run"):
        if result in seen:
            return result
    return "passed"


@dataclass
class CheckResult:
    check: str
    result: str
    summary: str
    problems: list = field(default_factory=list)

    def __post_init__(self) -> None:
        if self.result not in RESULTS:
            raise ValueError(f"unknown result {self.result!r}")
        if not self.summary.strip():
            raise ValueError("a check result must say what was observed")

    def as_dict(self) -> dict:
        return {"check": self.check, "result": self.result, "summary": self.summary, "problems": self.problems}


def relative(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path)


def git_files(root: Path):
    """Every file Git would track, committed or new but never ignored, or None outside Git."""
    if not (root / ".git").exists():
        return None
    try:
        listed = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            check=True, capture_output=True, text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return sorted({root / name for name in listed.split("\0") if name and (root / name).is_file()})


def repository_files(root: Path, suffix: str) -> list:
    """Files ending in `suffix` that Git would track. Outside a Git checkout, such as a temporary
    copy, walks the tree and skips build folders."""
    tracked = git_files(root)
    if tracked is not None:
        return [path for path in tracked if path.name.endswith(suffix)]
    found = []
    for directory, subdirectories, files in os.walk(root):
        subdirectories[:] = sorted(d for d in subdirectories if d not in SKIPPED_DIRS)
        found.extend(Path(directory) / name for name in files if name.endswith(suffix))
    return sorted(found)


def read_frontmatter(text: str) -> tuple:
    """Parses strict frontmatter: one `key: <JSON value>` per line.

    Returns (fields, problems). Fields holds every line that parsed; problems name each line that
    did not, so one typo does not hide the rest.
    """
    match = FRONTMATTER.match(text)
    if not match:
        if text.startswith("---\r\n"):
            return {}, ["frontmatter uses CRLF line endings; use LF"]
        return {}, ["missing frontmatter: the file must start with a `---` block"]
    fields: dict = {}
    problems = []
    for number, line in enumerate(match.group(1).split("\n"), start=2):
        if not line.strip():
            continue
        key, separator, raw = line.partition(":")
        key = key.strip()
        if not separator or not key:
            problems.append(f"line {number}: expected `key: value`, found {line!r}")
            continue
        if key in fields:
            problems.append(f"line {number}: duplicate key `{key}`")
            continue
        try:
            fields[key] = json.loads(raw.strip())
        except json.JSONDecodeError:
            problems.append(f"line {number}: `{key}` must be a JSON value such as \"text\" or [\"ID\"], found {raw.strip()!r}")
    return fields, problems


def find_cycles(graph: dict) -> list:
    """The cycles a depth-first search closes, at least one for any cyclic part of the graph.

    Each is rotated to start at its smallest ID and closed, such as ["A", "B", "A"]. Edges to
    unknown nodes are ignored; the caller reports those separately.
    """
    cycles = set()
    state: dict = {}
    for start in sorted(graph):
        if state.get(start):
            continue
        stack = [(start, iter(sorted(graph.get(start, ()))))]
        path = [start]
        state[start] = "open"
        while stack:
            node, edges = stack[-1]
            advanced = False
            for target in edges:
                if target not in graph:
                    continue
                if state.get(target) == "open":
                    loop = path[path.index(target):]
                    pivot = loop.index(min(loop))
                    cycles.add(tuple(loop[pivot:] + loop[:pivot]))
                elif not state.get(target):
                    state[target] = "open"
                    path.append(target)
                    stack.append((target, iter(sorted(graph.get(target, ())))))
                    advanced = True
                    break
            if not advanced:
                state[node] = "closed"
                path.pop()
                stack.pop()
    return [list(cycle) + [cycle[0]] for cycle in sorted(cycles)]
