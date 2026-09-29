#!/usr/bin/env python3
"""CI evidence helpers: record every step as passed, failed, blocked, or not-run.

    ci.py [--ledger PATH] select-xcode [--applications DIR] [--github-env PATH]
    ci.py [--ledger PATH] run CHECK [--expect-tests] -- COMMAND ...
    ci.py [--ledger PATH] record CHECK RESULT DETAIL
    ci.py [--ledger PATH] feature-level [--project PATH] SCHEME=DESTINATION ... [-- XCODEBUILD-ARGS]
    ci.py [--ledger PATH] summarize --require CHECK ... [--optional CHECK ...] [--summary-file PATH]

Each step appends to a run ledger (--ledger, or LAB_CI_LEDGER). `summarize` reads it, reports
any required check with no entry as not-run, and exits 0 only when every required check passed
and nothing optional failed or was blocked. A skipped step can therefore never look passed.
Python 3 standard library only.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import plistlib
import re
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

sys.dont_write_bytecode = True  # Keep the checkout free of __pycache__ folders.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import ledger  # noqa: E402
from common import EXIT_CODES, RESULTS, ROOT, combine  # noqa: E402

# The toolchain families this project builds with, most preferred first (ADR-009): a 27 SDK builds
# the newer adapters; a 26 SDK builds the 26-family core with them compiled out.
SUPPORTED_MAJORS = (27, 26)
NOT_EXECUTED = "no result was recorded: the step did not execute (an earlier step failed or was blocked, or the run was cancelled)"

SWIFT_TESTING_COUNT = re.compile(r"Test run with (\d+) tests?\b")
XCTEST_COUNT = re.compile(r"Executed (\d+) tests?, with")
UNITTEST_COUNT = re.compile(r"^Ran (\d+) tests? in ")
COUNTS = (SWIFT_TESTING_COUNT, XCTEST_COUNT, UNITTEST_COUNT)


# Xcode selection -------------------------------------------------------------------------------

@dataclass(frozen=True)
class Xcode:
    app: Path
    version: str
    build: str
    beta: bool

    @property
    def numbers(self) -> tuple:
        parts = [int(part) for part in re.findall(r"\d+", self.version)[:3]]
        return tuple(parts + [0] * (3 - len(parts)))

    @property
    def major(self) -> int:
        return self.numbers[0]

    @property
    def label(self) -> str:
        return f"{self.version} ({self.build}){' beta' if self.beta else ''}"

    @property
    def developer_dir(self) -> Path:
        return self.app / "Contents" / "Developer"


def installed_xcodes(applications: Path) -> list:
    """Every Xcode under `applications`, once each even when a symbolic link aliases it."""
    found: dict = {}
    for app in sorted(applications.glob("Xcode*.app")):
        real = Path(os.path.realpath(app))
        try:
            with (real / "Contents" / "version.plist").open("rb") as handle:
                info = plistlib.load(handle)
        except (OSError, plistlib.InvalidFileException):
            continue
        version = str(info.get("CFBundleShortVersionString", "")).strip()
        if not re.match(r"^\d+", version):
            continue
        build = str(info.get("ProductBuildVersion", "unknown"))
        beta = "beta" in real.name.lower() or bool(re.search(r"\d[A-Z]5\d{3}[a-z]$", build))
        found.setdefault(real, Xcode(real, version, build, beta))
    return sorted(found.values(), key=lambda xcode: (xcode.numbers, not xcode.beta, xcode.build))


def best(xcodes: list, major: int):
    """The newest release of `major`, or its newest beta when no release is installed."""
    candidates = [xcode for xcode in xcodes if xcode.major == major]
    return max(candidates, key=lambda xcode: (not xcode.beta, xcode.numbers, xcode.build), default=None)


def select_xcode(xcodes: list):
    """(primary, compatibility): the newest supported family's Xcode, plus the newest 26.x when
    the primary is 27, so the job can also prove the 26-family compatibility level."""
    for major in SUPPORTED_MAJORS:
        primary = best(xcodes, major)
        if primary:
            compatibility = best(xcodes, 26) if major != 26 else None
            return primary, compatibility
    return None, None


def command_select_xcode(arguments) -> int:
    xcodes = installed_xcodes(Path(arguments.applications))
    print(f"Installed Xcode applications under {arguments.applications}:")
    for xcode in xcodes:
        print(f"  {xcode.label:<24} {xcode.app}")
    if not xcodes:
        print("  none")
    primary, compatibility = select_xcode(xcodes)
    installed = ", ".join(xcode.label for xcode in xcodes) or "none"
    path = ledger.resolve(arguments.ledger)
    environment = {}
    if primary is None:
        detail = (f"no Xcode {' or '.join(map(str, SUPPORTED_MAJORS))} on this runner (installed: {installed}); "
                  "the 26.0 deployment floor needs a 26 or 27 SDK")
        ledger.append(path, "xcode-selection", "blocked", detail)
        environment["LAB_XCODE_READY"] = "false"
        print(f"BLOCKED: {detail}")
    else:
        if primary.major == 27:
            level = "27 SDKs: builds include the LAB_SDK_27 adapters"
        else:
            level = ("no Xcode 27 on this runner, so the builds prove the 26-family compatibility level "
                     "with LAB_SDK_27 compiled out (ADR-009)")
        detail = f"Xcode {primary.label} at {primary.app}; {level}; installed: {installed}"
        ledger.append(path, "xcode-selection", "passed", detail)
        environment.update({
            "DEVELOPER_DIR": str(primary.developer_dir),
            "LAB_XCODE_READY": "true",
            "LAB_XCODE": primary.label,
            "LAB_XCODE_MAJOR": str(primary.major),
        })
        print(f"Selected Xcode {primary.label}: {level}")
    if compatibility:
        environment["LAB_COMPAT_DEVELOPER_DIR"] = str(compatibility.developer_dir)
        environment["LAB_COMPAT_XCODE"] = compatibility.label
        print(f"Compatibility compile will use Xcode {compatibility.label}")
    else:
        reason = ("the primary builds already use a 26 SDK" if primary and primary.major == 26
                  else "no Xcode 26 is installed on this runner")
        environment["LAB_COMPAT_REASON"] = reason
        print(f"No separate compatibility compile: {reason}")
    github_env = arguments.github_env or os.environ.get("GITHUB_ENV")
    if github_env:
        with open(github_env, "a", encoding="utf-8") as handle:
            for key, value in environment.items():
                handle.write(f"{key}={value}\n")
    else:
        for key, value in environment.items():
            print(f"{key}={value}")
    return EXIT_CODES["passed"] if primary else EXIT_CODES["blocked"]


# Running and recording steps -------------------------------------------------------------------

def test_count(output_lines: list):
    """Tests the output reports as executed, or None when it reports no count at all.

    Each framework prints running totals, so the largest count per framework is its total.
    Swift Testing, XCTest, and Python unittest totals are added together.
    """
    totals = [[int(m.group(1)) for line in output_lines for m in pattern.finditer(line)] for pattern in COUNTS]
    if not any(totals):
        return None
    return sum(max(counts, default=0) for counts in totals)


def classify(exit_code: int, output_lines: list, expect_tests: bool, shown: str, seconds: float) -> tuple:
    timing = f"after {seconds:.0f} s"
    if exit_code != 0:
        return "failed", f"exit {exit_code} {timing}: {shown}"
    if not expect_tests:
        return "passed", f"exit 0 {timing}: {shown}"
    count = test_count(output_lines)
    if count is None:
        return "not-run", f"exit 0 {timing}, but no test count was reported, so no test is known to have run: {shown}"
    if count == 0:
        return "not-run", f"exit 0 {timing}, but 0 tests ran: {shown}"
    return "passed", f"{count} tests passed {timing}: {shown}"


def command_run(arguments) -> int:
    command = arguments.rest
    if not command:
        raise SystemExit("run: give the command after --")
    path = ledger.resolve(arguments.ledger)
    shown = shlex.join(command)
    print(f"==> {arguments.check}: {shown}", flush=True)
    started = time.monotonic()
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   errors="replace")
    except OSError as error:
        detail = f"could not start {command[0]}: {error.strerror or error}"
        ledger.append(path, arguments.check, "blocked", detail)
        print(f"BLOCKED: {detail}")
        return EXIT_CODES["blocked"]
    counted = []
    with process:
        for line in process.stdout:
            sys.stdout.write(line)
            if any(pattern.search(line) for pattern in COUNTS):
                counted.append(line)
    exit_code = process.wait()
    sys.stdout.flush()
    result, detail = classify(exit_code, counted, arguments.expect_tests, shown, time.monotonic() - started)
    ledger.append(path, arguments.check, result, detail)
    print(f"{result.upper()}: {arguments.check}: {detail}")
    return exit_code if exit_code != 0 else EXIT_CODES[result]


def command_record(arguments) -> int:
    ledger.append(ledger.resolve(arguments.ledger), arguments.check, arguments.result, arguments.detail)
    print(f"{arguments.result.upper()}: {arguments.check}: {arguments.detail}")
    return 0


# Feature level ---------------------------------------------------------------------------------

def feature_level(scheme: str, settings: dict) -> tuple:
    """(result, detail) for one scheme's resolved build settings (ADR-009)."""
    sdk = settings.get("SDK_NAME", "unknown")
    flags = settings.get("OTHER_SWIFT_FLAGS", "").split()
    compiled_in = "-DLAB_SDK_27" in flags
    sdk_major = re.search(r"(\d+)(?:\.\d+)*$", sdk)
    major = int(sdk_major.group(1)) if sdk_major else None
    if major == 27 and compiled_in:
        return "passed", f"{scheme}: {sdk}, 27 SDK level: LAB_SDK_27 compiled in, newer adapters available"
    if major == 26 and not compiled_in:
        return "passed", f"{scheme}: {sdk}, 26-family compatibility level: LAB_SDK_27 compiled out"
    return "failed", (f"{scheme}: {sdk} resolved with LAB_SDK_27 {'set' if compiled_in else 'unset'}; "
                      "Config/Base.xcconfig should set it for exactly the 27 SDKs (ADR-009)")


def application_settings(entries: list) -> dict:
    for entry in entries:
        settings = entry.get("buildSettings", {})
        if settings.get("WRAPPER_EXTENSION") == "app" or settings.get("PRODUCT_TYPE", "").endswith(".application"):
            return settings
    return entries[0].get("buildSettings", {}) if entries else {}


def command_feature_level(arguments) -> int:
    path = ledger.resolve(arguments.ledger)
    specs, extra = arguments.specs, arguments.rest
    outcomes = []
    for spec in specs:
        scheme, separator, destination = spec.partition("=")
        if not separator:
            raise SystemExit(f"feature-level: expected SCHEME=DESTINATION, found {spec!r}")
        check = f"{arguments.check_prefix}feature-level:{scheme}"
        command = ["xcodebuild", "-project", arguments.project, "-scheme", scheme, "-destination", destination,
                   "-showBuildSettings", "-json", *extra]
        try:
            process = subprocess.run(command, capture_output=True, text=True, errors="replace")
        except OSError as error:
            result, detail = "blocked", f"{scheme}: could not start xcodebuild: {error.strerror or error}"
        else:
            if process.returncode != 0:
                tail = " ".join(process.stderr.strip().splitlines()[-3:])
                result, detail = "failed", f"{scheme}: xcodebuild -showBuildSettings exited {process.returncode}: {tail}"
            else:
                try:
                    entries = json.loads(process.stdout[process.stdout.find("["):])
                except json.JSONDecodeError:
                    entries = None
                if not entries:
                    result, detail = "failed", f"{scheme}: xcodebuild -showBuildSettings -json printed no settings"
                else:
                    result, detail = feature_level(scheme, application_settings(entries))
        ledger.append(path, check, result, detail)
        print(f"{result.upper()}: {detail}")
        outcomes.append(result)
    return EXIT_CODES[combine(outcomes)]


# Summary ---------------------------------------------------------------------------------------

def annotation(level: str, title: str, message: str) -> str:
    def escape(text: str, property_value: bool = False) -> str:
        text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        return text.replace(":", "%3A").replace(",", "%2C") if property_value else text
    return f"::{level} title={escape(title, True)}::{escape(message)}"


def summary_rows(entries: dict, required: list, optional: list) -> list:
    """(check, result, gate, detail) rows. A required pattern with no entry is not-run."""
    rows = []
    covered = set()
    for gate, patterns in (("required", required), ("optional", optional)):
        for pattern in patterns:
            matches = sorted(check for check in entries if fnmatch.fnmatchcase(check, pattern) and check not in covered)
            if not matches and pattern not in covered:
                rows.append((pattern, "not-run", gate, NOT_EXECUTED))
                covered.add(pattern)
            for check in matches:
                result, detail = entries[check]
                rows.append((check, result, gate, detail))
                covered.add(check)
    for check in sorted(set(entries) - covered):
        result, detail = entries[check]
        rows.append((check, result, "required", detail))
    return rows


def gate_result(rows: list) -> str:
    """Required rows gate on everything; optional rows gate only on failed or blocked."""
    gating = [result for _, result, gate, _ in rows if gate == "required"]
    gating += [result for _, result, gate, _ in rows if gate == "optional" and result in ("failed", "blocked")]
    return combine(gating)


def render_summary(rows: list) -> str:
    overall = gate_result(rows)
    required = [result for _, result, gate, _ in rows if gate == "required"]
    counts = ", ".join(f"{required.count(state)} {state}" for state in RESULTS)
    lines = ["## CI evidence summary", "",
             f"**Overall: {overall.upper()}.** Required checks: {counts}.", ""]
    levels = [detail for check, result, _, detail in rows if "feature-level:" in check and result == "passed"]
    if levels:
        lines += ["Feature level built:", ""] + [f"- {level}" for level in levels] + [""]
    lines += ["| Check | Result | Gate | Detail |", "|---|---|---|---|"]
    for check, result, gate, detail in rows:
        cell = detail.replace("|", "\\|").replace("\n", " ")
        lines.append(f"| `{check}` | {result.upper()} | {gate} | {cell} |")
    lines += ["", "Only PASSED is passing. BLOCKED and NOT-RUN rows did not pass, and an optional row "
              "that did not run is listed rather than hidden."]
    return "\n".join(lines) + "\n"


def command_summarize(arguments) -> int:
    entries = ledger.read(ledger.resolve(arguments.ledger))
    rows = summary_rows(entries, arguments.require, arguments.optional)
    text = render_summary(rows)
    print(text)
    summary_file = arguments.summary_file or os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_file:
        with open(summary_file, "a", encoding="utf-8") as handle:
            handle.write(text)
    in_actions = os.environ.get("GITHUB_ACTIONS") == "true"
    for check, result, gate, detail in rows:
        if result == "passed":
            continue
        gating = gate == "required" or result in ("failed", "blocked")
        line = annotation("error" if gating else "notice", f"{check} {result}", detail)
        print(line if in_actions else line.replace("::", "", 1))
    overall = gate_result(rows)
    return 0 if overall == "passed" else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--ledger", help=f"run ledger path (default: ${ledger.ENVIRONMENT})")
    commands = parser.add_subparsers(dest="action", required=True)

    select = commands.add_parser("select-xcode", help="choose the Xcode for this run and export DEVELOPER_DIR")
    select.add_argument("--applications", default="/Applications")
    select.add_argument("--github-env", help="file to append KEY=VALUE lines to (default: $GITHUB_ENV)")
    select.set_defaults(handler=command_select_xcode)

    run = commands.add_parser("run", help="run a command and record its result")
    run.add_argument("check")
    run.add_argument("--expect-tests", action="store_true",
                     help="record not-run unless the output reports at least one executed test")
    run.set_defaults(handler=command_run)

    record = commands.add_parser("record", help="record a result without running anything")
    record.add_argument("check")
    record.add_argument("result", choices=RESULTS)
    record.add_argument("detail")
    record.set_defaults(handler=command_record)

    level = commands.add_parser("feature-level", help="record each scheme's SDK and LAB_SDK_27 level")
    level.add_argument("--project", default=str(ROOT / "AppleNativeLab.xcodeproj"))
    level.add_argument("--check-prefix", default="", help="prefix for the recorded check IDs, such as compat-26:")
    level.add_argument("specs", nargs="+", metavar="SCHEME=DESTINATION")
    level.set_defaults(handler=command_feature_level)

    summarize = commands.add_parser("summarize", help="report the ledger and gate the job")
    summarize.add_argument("--require", nargs="+", default=[], help="checks (or glob patterns) that must pass")
    summarize.add_argument("--optional", nargs="+", default=[], help="checks that may be not-run")
    summarize.add_argument("--summary-file", help="Markdown summary file (default: $GITHUB_STEP_SUMMARY)")
    summarize.set_defaults(handler=command_summarize)

    argv = list(sys.argv[1:] if argv is None else argv)
    # Everything after the first `--` is passed through untouched: the command for `run`, extra
    # xcodebuild arguments for `feature-level`.
    rest = argv[argv.index("--") + 1:] if "--" in argv else []
    argv = argv[:argv.index("--")] if "--" in argv else argv
    arguments = parser.parse_args(argv)
    arguments.rest = rest
    if arguments.action not in ("run", "feature-level") and rest:
        parser.error(f"{arguments.action} takes no arguments after --")
    return arguments.handler(arguments)


if __name__ == "__main__":
    sys.exit(main())
