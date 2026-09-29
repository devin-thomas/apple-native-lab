"""Ticket frontmatter is well formed, and the dependency graph is complete and acyclic.

Every tickets/*.md file except INDEX.md starts with frontmatter holding exactly these keys, each
a JSON value: id, title, status, milestone, kind, depends_on.
"""
from __future__ import annotations

import re
from pathlib import Path

from common import ID_PATTERN, CheckResult, find_cycles, read_frontmatter, relative

FRONTMATTER_CHECK = "ticket-frontmatter"
GRAPH_CHECK = "ticket-graph"

FIELDS = ("id", "title", "status", "milestone", "kind", "depends_on")
STATUSES = ("planned", "in-progress", "blocked", "done")
KINDS = ("implementation", "qualification")
MILESTONE = re.compile(r"^M\d+$")


def ticket_files(root: Path) -> list:
    return sorted(path for path in (root / "tickets").glob("*.md") if path.name != "INDEX.md")


def load(root: Path) -> tuple:
    """Returns (tickets, problems): {id: depends_on} for every ticket whose id and depends_on
    could be read, and a list of (file, message) for everything malformed."""
    tickets: dict = {}
    problems = []
    for path in ticket_files(root):
        name = relative(path, root)
        fields, parse_problems = read_frontmatter(path.read_text(encoding="utf-8"))
        problems.extend((name, message) for message in parse_problems)
        missing = [key for key in FIELDS if key not in fields]
        unknown = sorted(set(fields) - set(FIELDS))
        if missing:
            problems.append((name, f"missing {', '.join(missing)}"))
        if unknown:
            problems.append((name, f"unknown key {', '.join(unknown)}; allowed keys are {', '.join(FIELDS)}"))
        ticket_id = fields.get("id")
        if "id" in fields:
            if not isinstance(ticket_id, str) or not ID_PATTERN.match(ticket_id):
                problems.append((name, f"id {ticket_id!r} is not an ID such as CORE-007 or LAB-001-B"))
                ticket_id = None
            elif ticket_id != path.stem:
                problems.append((name, f"id {ticket_id} does not match the file name {path.name}"))
            elif ticket_id in tickets:
                problems.append((name, f"id {ticket_id} is used by another ticket"))
        if "title" in fields and (not isinstance(fields["title"], str) or not fields["title"].strip()):
            problems.append((name, "title must be non-empty text"))
        if "status" in fields and fields["status"] not in STATUSES:
            problems.append((name, f"status {fields['status']!r} is not one of {', '.join(STATUSES)}"))
        if "kind" in fields and fields["kind"] not in KINDS:
            problems.append((name, f"kind {fields['kind']!r} is not one of {', '.join(KINDS)}"))
        if "milestone" in fields and not (isinstance(fields["milestone"], str) and MILESTONE.match(fields["milestone"])):
            problems.append((name, f"milestone {fields['milestone']!r} is not M followed by a number"))
        depends_on = fields.get("depends_on")
        if "depends_on" in fields:
            if not isinstance(depends_on, list) or not all(isinstance(item, str) for item in depends_on):
                problems.append((name, "depends_on must be a JSON list of ticket IDs"))
                depends_on = None
            elif len(set(depends_on)) != len(depends_on):
                problems.append((name, "depends_on lists a ticket more than once"))
        if isinstance(ticket_id, str) and ticket_id == path.stem and ticket_id not in tickets and depends_on is not None:
            tickets[ticket_id] = depends_on
    return tickets, problems


def check_frontmatter(root: Path) -> CheckResult:
    files = ticket_files(root)
    if not files:
        return CheckResult(FRONTMATTER_CHECK, "not-run", "no ticket files found under tickets/")
    _, problems = load(root)
    if problems:
        return CheckResult(
            FRONTMATTER_CHECK, "failed", f"{len(problems)} frontmatter problems in {len(files)} ticket files",
            [f"{name}: {message}" for name, message in problems],
        )
    return CheckResult(FRONTMATTER_CHECK, "passed", f"{len(files)} ticket files have well-formed frontmatter")


def check_graph(root: Path) -> CheckResult:
    files = ticket_files(root)
    if not files:
        return CheckResult(GRAPH_CHECK, "not-run", "no ticket files found under tickets/")
    tickets, _ = load(root)
    problems = []
    for ticket_id, depends_on in sorted(tickets.items()):
        for dependency in depends_on:
            if dependency not in tickets and not (root / "tickets" / f"{dependency}.md").exists():
                problems.append(f"tickets/{ticket_id}.md: depends_on {dependency}, which has no ticket file "
                                f"(tickets/{dependency}.md)")
    for cycle in find_cycles(tickets):
        problems.append(f"dependency cycle: {' -> '.join(cycle)}")
    unreadable = len(files) - len(tickets)
    edges = sum(len(depends_on) for depends_on in tickets.values())
    if problems:
        return CheckResult(GRAPH_CHECK, "failed", f"{len(problems)} dependency problems among {len(tickets)} tickets", problems)
    if unreadable:
        return CheckResult(
            GRAPH_CHECK, "blocked",
            f"{unreadable} of {len(files)} tickets have unreadable id or depends_on, so the graph is incomplete; "
            f"fix {FRONTMATTER_CHECK} first",
        )
    return CheckResult(GRAPH_CHECK, "passed", f"{len(tickets)} tickets, {edges} dependencies, every one exists, no cycles")
