"""Experiment frontmatter uses the SPEC state vocabulary, and every copy of that vocabulary agrees.

SPEC.md section 7 is the source of truth for implementation states. The catalog generator and
the Swift `ImplementationState` must list exactly the same states.
"""
from __future__ import annotations

import re
from pathlib import Path

from common import CheckResult, find_cycles, read_frontmatter, relative

FRONTMATTER_CHECK = "experiment-frontmatter"
VOCABULARY_CHECK = "state-vocabulary"

FIELDS = ("id", "title", "state", "milestone", "category", "depends_on", "source_review")
EXPERIMENT_ID = re.compile(r"^LAB-\d{3}$")
MILESTONE = re.compile(r"^M\d+$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SPEC_SENTENCE = re.compile(r"Use exactly these implementation states:([^\n]*?)\.(?:\s|$)")
CATALOG_STATES = re.compile(r"^STATES = \{([^}]*)\}", re.M)
SWIFT_ENUM = re.compile(r"enum ImplementationState\b[^{]*\{(.*?)\n\}", re.S)
SWIFT_CASE = re.compile(r"^\s*case (\w+)(?: = \"([^\"]+)\")?\s*$", re.M)

SWIFT_STATES = Path("Packages/LabSupport/Sources/LabSupport/ImplementationState.swift")
CATALOG_SCRIPT = Path("script/generate_catalog.py")


def spec_states(root: Path):
    """The states SPEC.md section 7 lists, in order, or None when the sentence is missing."""
    spec = root / "SPEC.md"
    if not spec.exists():
        return None
    match = SPEC_SENTENCE.search(spec.read_text(encoding="utf-8"))
    return re.findall(r"`([^`]+)`", match.group(1)) if match else None


def swift_states(root: Path):
    path = root / SWIFT_STATES
    if not path.exists():
        return None
    body = SWIFT_ENUM.search(path.read_text(encoding="utf-8"))
    if not body:
        return None
    return [raw or name for name, raw in SWIFT_CASE.findall(body.group(1))]


def catalog_states(root: Path):
    path = root / CATALOG_SCRIPT
    if not path.exists():
        return None
    match = CATALOG_STATES.search(path.read_text(encoding="utf-8"))
    return sorted(re.findall(r"\"([^\"]+)\"", match.group(1))) if match else None


def check_vocabulary(root: Path) -> CheckResult:
    spec = spec_states(root)
    if not spec:
        return CheckResult(
            VOCABULARY_CHECK, "blocked",
            "SPEC.md section 7 no longer has the sentence \"Use exactly these implementation states: ...\", "
            "so there is no vocabulary to compare against",
        )
    problems = []
    swift = swift_states(root)
    if swift is None:
        problems.append(f"{SWIFT_STATES}: cannot find the ImplementationState enum")
    elif swift != spec:
        problems.append(f"{SWIFT_STATES}: states {swift} differ from SPEC.md {spec}")
    catalog = catalog_states(root)
    if catalog is None:
        problems.append(f"{CATALOG_SCRIPT}: cannot find STATES")
    elif catalog != sorted(spec):
        problems.append(f"{CATALOG_SCRIPT}: STATES {catalog} differ from SPEC.md {sorted(spec)}")
    if problems:
        return CheckResult(VOCABULARY_CHECK, "failed", "the state vocabulary copies disagree with SPEC.md", problems)
    return CheckResult(
        VOCABULARY_CHECK, "passed",
        f"SPEC.md, ImplementationState, and the catalog generator agree on {len(spec)} states: {', '.join(spec)}",
    )


def index_categories(root: Path) -> list:
    index = root / "experiments" / "INDEX.md"
    return re.findall(r"^## (.+)$", index.read_text(encoding="utf-8"), re.M) if index.exists() else []


def check_frontmatter(root: Path) -> CheckResult:
    files = sorted((root / "experiments").glob("LAB-*.md"))
    if not files:
        return CheckResult(FRONTMATTER_CHECK, "not-run", "no experiment specs found under experiments/")
    states = spec_states(root)
    if not states:
        return CheckResult(FRONTMATTER_CHECK, "blocked", "SPEC.md section 7 state vocabulary not found; cannot check states")
    categories = index_categories(root)
    problems = []
    graph: dict = {}
    for path in files:
        name = relative(path, root)
        fields, parse_problems = read_frontmatter(path.read_text(encoding="utf-8"))
        problems.extend(f"{name}: {message}" for message in parse_problems)
        missing = [key for key in FIELDS if key not in fields]
        unknown = sorted(set(fields) - set(FIELDS))
        if missing:
            problems.append(f"{name}: missing {', '.join(missing)}")
        if unknown:
            problems.append(f"{name}: unknown key {', '.join(unknown)}; allowed keys are {', '.join(FIELDS)}")
        experiment_id = fields.get("id")
        if "id" in fields and not (isinstance(experiment_id, str) and EXPERIMENT_ID.match(experiment_id)
                                   and path.name.startswith(experiment_id + "-")):
            problems.append(f"{name}: id {experiment_id!r} must be LAB-nnn and match the file name")
            experiment_id = None
        if "state" in fields and fields["state"] not in states:
            problems.append(f"{name}: state {fields['state']!r} is not in the SPEC vocabulary ({', '.join(states)})")
        if "title" in fields and (not isinstance(fields["title"], str) or not fields["title"].strip()):
            problems.append(f"{name}: title must be non-empty text")
        if "milestone" in fields and not (isinstance(fields["milestone"], str) and MILESTONE.match(fields["milestone"])):
            problems.append(f"{name}: milestone {fields['milestone']!r} is not M followed by a number")
        if "category" in fields and fields["category"] not in categories:
            problems.append(f"{name}: category {fields['category']!r} is not a heading in experiments/INDEX.md")
        if "source_review" in fields and not (isinstance(fields["source_review"], str) and DATE.match(fields["source_review"])):
            problems.append(f"{name}: source_review must be a YYYY-MM-DD date")
        depends_on = fields.get("depends_on")
        if "depends_on" in fields and not (isinstance(depends_on, list) and all(isinstance(d, str) for d in depends_on)):
            problems.append(f"{name}: depends_on must be a JSON list of experiment IDs")
        elif isinstance(experiment_id, str):
            graph[experiment_id] = depends_on or []
    for experiment_id, depends_on in sorted(graph.items()):
        problems.extend(
            f"{experiment_id}: depends_on {dependency}, which has no experiment spec in experiments/"
            for dependency in depends_on if dependency not in graph
        )
    problems.extend(f"experiment dependency cycle: {' -> '.join(cycle)}" for cycle in find_cycles(graph))
    if problems:
        return CheckResult(FRONTMATTER_CHECK, "failed", f"{len(problems)} problems in {len(files)} experiment specs", problems)
    counts: dict = {}
    for path in files:
        state = read_frontmatter(path.read_text(encoding="utf-8"))[0]["state"]
        counts[state] = counts.get(state, 0) + 1
    tally = ", ".join(f"{count} {state}" for state, count in sorted(counts.items()))
    return CheckResult(FRONTMATTER_CHECK, "passed", f"{len(files)} experiment specs well formed with SPEC states ({tally})")
