#!/usr/bin/env python3
"""Generate the bundled experiment catalog from experiments/LAB-*.md.

The experiment specs are the single source of truth. Change a spec's frontmatter
(for example its `state`), then rerun this script; never hand-edit the JSON.
Run from anywhere: python3 script/generate_catalog.py [--check]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPERIMENTS = ROOT / "experiments"
TICKETS = ROOT / "tickets"
OUTPUT = ROOT / "Packages/LabFeatures/Sources/LabCatalog/Resources/experiments.json"
STATES = {"specified", "spiked", "implemented", "device-verified", "release-ready", "blocked"}


def frontmatter(text: str, path: Path) -> dict:
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not match:
        sys.exit(f"{path.name}: missing frontmatter")
    fields = {}
    for line in match.group(1).splitlines():
        key, _, raw = line.partition(":")
        raw = raw.strip()
        fields[key.strip()] = json.loads(raw) if raw.startswith(("[", '"')) else raw
    return fields


def section_paragraph(text: str, heading: str) -> str:
    match = re.search(rf"^## {re.escape(heading)}\n\n(.+?)(?:\n\n|\Z)", text, re.S | re.M)
    return " ".join(match.group(1).split()) if match else ""


def bold_line(text: str, label: str) -> str:
    match = re.search(rf"^\*\*{re.escape(label)}:\*\* (.+)$", text, re.M)
    if not match:
        return ""
    value = match.group(1).split(" API names are")[0].strip()
    return value.rstrip(".")


def main() -> None:
    index = (EXPERIMENTS / "INDEX.md").read_text()
    categories = re.findall(r"^## (.+)$", index, re.M)
    experiments = []
    for path in sorted(EXPERIMENTS.glob("LAB-*.md")):
        text = path.read_text()
        meta = frontmatter(text, path)
        if meta["state"] not in STATES:
            sys.exit(f"{path.name}: unknown state {meta['state']!r}")
        if meta["category"] not in categories:
            sys.exit(f"{path.name}: category {meta['category']!r} is not in INDEX.md")
        experiments.append({
            "id": meta["id"],
            "title": meta["title"],
            "category": meta["category"],
            "milestone": meta["milestone"],
            "state": meta["state"],
            "dependsOn": meta.get("depends_on", []),
            "moment": section_paragraph(text, "The moment"),
            "hosts": bold_line(text, "Hosts"),
            "primaryAPIs": bold_line(text, "Primary APIs"),
            "tickets": sorted(p.stem for p in TICKETS.glob(f"{meta['id']}-*.md")),
            "specPath": f"experiments/{path.name}",
        })
    catalog = {
        "schemaVersion": 1,
        "sourceReview": "2026-09-29",
        "categories": categories,
        "experiments": experiments,
    }
    rendered = json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        if not OUTPUT.exists() or OUTPUT.read_text() != rendered:
            sys.exit("experiments.json is stale; run python3 script/generate_catalog.py")
        print(f"catalog up to date ({len(experiments)} experiments)")
        return
    OUTPUT.write_text(rendered)
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({len(experiments)} experiments, {len(categories)} categories)")


if __name__ == "__main__":
    main()
