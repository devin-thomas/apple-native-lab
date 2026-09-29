"""CI workflows keep the public trust boundary (docs/SECURITY_AND_PRIVACY.md).

Pull requests, including forks, must run with no secrets, no signing material, no write access,
and no self-hosted runner. Each workflow under .github/workflows must therefore:

- avoid the `pull_request_target` and `workflow_run` triggers, which run with the base
  repository's secrets and write token;
- never reference `secrets.` (the automatic token is not needed either);
- declare top-level `permissions` and grant nothing beyond `read`;
- run only on GitHub-hosted runners, never `self-hosted`;
- pin every action to a full commit SHA.

This reads the YAML as text, line by line, with comments removed; it is a policy check, not a
YAML parser. Python 3 standard library only.
"""
from __future__ import annotations

import re
from pathlib import Path

from common import CheckResult, relative

CHECK = "workflow-policy"
WORKFLOWS = Path(".github/workflows")

FORBIDDEN_TRIGGERS = re.compile(r"(?<![\w-])(pull_request_target|workflow_run)(?![\w-])")
SECRETS = re.compile(r"\bsecrets\s*\.")
SELF_HOSTED = re.compile(r"self-hosted")
USES = re.compile(r"^\s*-?\s*uses:\s*['\"]?([^'\"\s]+)")
PINNED = re.compile(r"@[0-9a-f]{40}$")
PERMISSION_VALUE = re.compile(r"^\s*(?:permissions\s*:\s*|[\w-]+\s*:\s*)(read-all|write-all|write|read|none)\s*$")


def strip_comment(line: str) -> str:
    """The line without a trailing # comment. A # inside quotes is kept."""
    quote = None
    for index, character in enumerate(line):
        if character in "'\"" and quote in (None, character):
            quote = None if quote else character
        elif character == "#" and quote is None and (index == 0 or line[index - 1].isspace()):
            return line[:index].rstrip()
    return line.rstrip()


def workflow_problems(text: str) -> list:
    problems = []
    lines = [strip_comment(line) for line in text.splitlines()]
    top_level_permissions = False
    in_permissions = None
    for number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if in_permissions is not None and indent <= in_permissions:
            in_permissions = None
        if FORBIDDEN_TRIGGERS.search(line):
            problems.append(f"line {number}: {FORBIDDEN_TRIGGERS.search(line).group(1)} runs with the base "
                            "repository's secrets and write token; use pull_request")
        if SECRETS.search(line):
            problems.append(f"line {number}: references secrets; public CI must run without them")
        if SELF_HOSTED.search(line):
            problems.append(f"line {number}: self-hosted runner; public CI uses GitHub-hosted runners only")
        uses = USES.match(line)
        if uses and not uses.group(1).startswith("./") and not PINNED.search(uses.group(1)):
            problems.append(f"line {number}: {uses.group(1)} is not pinned to a full commit SHA")
        stripped = line.strip()
        if stripped.startswith("permissions:"):
            if indent == 0:
                top_level_permissions = True
            value = stripped[len("permissions:"):].strip()
            if value:
                if value not in ("read-all", "{}"):
                    problems.append(f"line {number}: permissions {value!r} grants more than read access")
            else:
                in_permissions = indent
            continue
        if in_permissions is not None:
            grant = PERMISSION_VALUE.match(line)
            if not grant or grant.group(1) not in ("read", "none"):
                problems.append(f"line {number}: permission {stripped!r} grants more than read access")
    if not top_level_permissions:
        problems.append("no top-level permissions block; declare `permissions: contents: read`")
    return problems


def check(root: Path) -> CheckResult:
    directory = root / WORKFLOWS
    files = sorted(list(directory.glob("*.yml")) + list(directory.glob("*.yaml"))) if directory.is_dir() else []
    if not files:
        return CheckResult(CHECK, "passed", f"no workflows under {WORKFLOWS}/ (0 files), so nothing can run in CI")
    problems = []
    for path in files:
        problems.extend(f"{relative(path, root)}: {problem}" for problem in workflow_problems(path.read_text(encoding="utf-8")))
    if problems:
        return CheckResult(CHECK, "failed", f"{len(problems)} trust-boundary problems in {len(files)} workflows", problems)
    return CheckResult(
        CHECK, "passed",
        f"{len(files)} workflow file{'' if len(files) == 1 else 's'}: no pull_request_target or workflow_run, "
        "no secrets, read-only permissions, GitHub-hosted runners, actions pinned by SHA",
    )
