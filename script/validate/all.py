#!/usr/bin/env python3
"""Run every repository validator and report each result as passed, failed, blocked, or not-run.

    python3 script/validate/all.py [--root PATH] [--json] [--ledger PATH]

Exit status: 0 when every check passed, 1 when any failed, 3 when none failed but one was
blocked, 4 when none failed or was blocked but one did not run. A check that did not run is never
counted as passed. Python 3 standard library only.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # Keep the checkout free of __pycache__ folders.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import catalog  # noqa: E402
import evidence  # noqa: E402
import experiments  # noqa: E402
import ledger  # noqa: E402
import links  # noqa: E402
import tickets  # noqa: E402
import workflows  # noqa: E402
from common import EXIT_CODES, ROOT, CheckResult, combine  # noqa: E402

CHECKS = (
    ("links", links.check),
    ("ticket-frontmatter", tickets.check_frontmatter),
    ("ticket-graph", tickets.check_graph),
    ("experiment-frontmatter", experiments.check_frontmatter),
    ("state-vocabulary", experiments.check_vocabulary),
    ("catalog", catalog.check),
    ("evidence-records", evidence.check),
    ("workflow-policy", workflows.check),
)


def run_checks(root: Path) -> list:
    results = []
    for name, check in CHECKS:
        try:
            result = check(root)
        except Exception as error:  # A crashing validator is a failed check, never a silent pass.
            result = CheckResult(name, "failed", f"the validator raised {type(error).__name__}", [str(error)])
        results.append(result)
    return results


def report(results: list, root: Path) -> str:
    lines = [f"Repository validation ({root})"]
    width = max(len(result.check) for result in results)
    for result in results:
        lines.append(f"  {result.result.upper():<8} {result.check:<{width}}  {result.summary}")
        lines.extend(f"  {'':<8} {'':<{width}}    - {problem}" for problem in result.problems)
    overall = combine(result.result for result in results)
    counts = ", ".join(f"{sum(r.result == state for r in results)} {state}" for state in EXIT_CODES)
    lines.append(f"Overall: {overall.upper()} ({counts})")
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--root", type=Path, default=ROOT, help="repository root to validate (default: this checkout)")
    parser.add_argument("--json", action="store_true", help="print results as JSON instead of text")
    parser.add_argument("--ledger", help=f"also append each result to this run ledger (or set {ledger.ENVIRONMENT})")
    arguments = parser.parse_args(argv)
    root = arguments.root.resolve()
    results = run_checks(root)
    overall = combine(result.result for result in results)
    if arguments.json:
        print(json.dumps({"overall": overall, "checks": [result.as_dict() for result in results]}, indent=2))
    else:
        print(report(results, root))
    if arguments.ledger:
        path = ledger.resolve(arguments.ledger)
        for result in results:
            detail = result.summary + "".join(f"; {problem}" for problem in result.problems[:5])
            ledger.append(path, f"validate:{result.check}", result.result, detail)
    return EXIT_CODES[overall]


if __name__ == "__main__":
    sys.exit(main())
