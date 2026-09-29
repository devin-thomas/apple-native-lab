"""Stored evidence records keep the rules the Swift `EvidenceRecord` enforces.

Records live at evidence/<ticket-or-experiment-ID>/<name>.json. Each must decode as an
`EvidenceRecord` (Packages/LabSupport/Sources/LabSupport/Evidence): known subject, ISO 8601
date, a result from the evidence vocabulary with a non-empty detail, and physical-device facts
only on the physical path. Unknown keys are refused, so a file cannot carry a claimed state
beside the evidence; the state a record supports follows from its path and result alone.
"""
from __future__ import annotations

import json
import re
import uuid
from pathlib import Path

from common import ID_PATTERN, RESULTS, CheckResult, relative

CHECK = "evidence-records"
EVIDENCE_DIR = Path("evidence")
SCHEMA_VERSION = 1

PATHS = ("physical", "simulator", "fixture", "static-review")
PLATFORMS = ("iOS", "macOS", "watchOS", "tvOS", "visionOS")
RECORD_KEYS = {"schemaVersion", "subject", "check", "date", "provenance", "execution", "inputs", "steps",
               "outcome", "limitations"}
PROVENANCE_KEYS = {"sourceRevision", "sdkName", "xcodeVersion", "xcodeBuild", "appVersion", "buildNumber",
                   "buildProfile", "minimumOS"}
DEVICE_KEYS = {"platform", "deviceClass", "osVersion"}
DATE_TIME = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
TOKEN_SEPARATORS = re.compile(r"[ \t()\[\]{},;:/=]+")


def blank(value) -> bool:
    return not isinstance(value, str) or not value.strip()


def looks_like_identifier(value: str) -> bool:
    """The same screen as Swift's DeviceIdentifierScreen: UUIDs, hardware UDIDs, serial numbers."""
    for token in TOKEN_SEPARATORS.split(value):
        if not token:
            continue
        try:
            uuid.UUID(token)
            if len(token) == 36:
                return True
        except ValueError:
            pass
        digits = token.replace("-", "")
        if len(digits) >= 24 and all(c in "0123456789abcdefABCDEF" for c in digits):
            return True
        if (10 <= len(token) <= 12 and re.fullmatch(r"[A-Z0-9]+", token)
                and sum(c.isdigit() for c in token) >= 2 and sum(c.isalpha() for c in token) >= 2):
            return True
    return False


def string_list_problems(record: dict, key: str) -> list:
    value = record.get(key)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        return [f"{key} must be a list of text"]
    return [f"{key} has an empty entry"] if any(blank(item) for item in value) else []


def execution_problems(execution) -> list:
    if not isinstance(execution, dict):
        return ["execution must be an object"]
    path = execution.get("path")
    if path not in PATHS:
        return [f"execution.path {path!r} is not one of {', '.join(PATHS)}"]
    problems = []
    allowed = {"path", {"physical": "device", "simulator": "simulator"}.get(path, "path")}
    extra = sorted(set(execution) - allowed)
    if extra:
        problems.append(f"a {path} execution cannot carry {', '.join(extra)}: device facts belong only to the "
                        "physical path, and simulator facts only to the simulator path")
    if path == "physical":
        device = execution.get("device")
        if not isinstance(device, dict):
            return problems + ["a physical execution must name its device class and OS in execution.device"]
        unknown = sorted(set(device) - DEVICE_KEYS - {"profileExpiry"})
        if unknown:
            problems.append(f"execution.device has unknown key {', '.join(unknown)}")
        if device.get("platform") not in PLATFORMS:
            problems.append(f"execution.device.platform {device.get('platform')!r} is not one of {', '.join(PLATFORMS)}")
        for key in ("deviceClass", "osVersion"):
            if blank(device.get(key)):
                problems.append(f"execution.device.{key} must not be empty")
            elif looks_like_identifier(device[key]):
                problems.append(f"execution.device.{key} looks like a serial number or device identifier")
        if "profileExpiry" in device and not (isinstance(device["profileExpiry"], str)
                                              and DATE_TIME.match(device["profileExpiry"])):
            problems.append("execution.device.profileExpiry must be an ISO 8601 UTC time such as 2026-10-06T00:00:00Z")
    elif path == "simulator":
        simulator = execution.get("simulator")
        if not isinstance(simulator, dict) or simulator.get("platform") not in PLATFORMS:
            problems.append("a simulator execution must name its platform in execution.simulator")
    return problems


def record_problems(record) -> list:
    """Every reason `record` would not decode as a valid EvidenceRecord."""
    if not isinstance(record, dict):
        return ["the record must be a JSON object"]
    problems = []
    missing = sorted(RECORD_KEYS - set(record))
    unknown = sorted(set(record) - RECORD_KEYS)
    if missing:
        problems.append(f"missing {', '.join(missing)}")
    if unknown:
        problems.append(f"unknown key {', '.join(unknown)}; a record states evidence, and its supported state "
                        "follows from execution.path and outcome.result")
    if record.get("schemaVersion") != SCHEMA_VERSION:
        problems.append(f"schemaVersion {record.get('schemaVersion')!r} is not {SCHEMA_VERSION}")
    subject = record.get("subject")
    if not (isinstance(subject, str) and ID_PATTERN.match(subject)):
        problems.append(f"subject {subject!r} is not a ticket or experiment ID such as CORE-007 or LAB-001-B")
    if blank(record.get("check")):
        problems.append("check must not be empty")
    if not (isinstance(record.get("date"), str) and DATE_TIME.match(record["date"])):
        problems.append("date must be an ISO 8601 UTC time such as 2026-09-29T12:00:00Z")
    provenance = record.get("provenance")
    if not isinstance(provenance, dict):
        problems.append("provenance must be an object")
    else:
        unknown_provenance = sorted(set(provenance) - PROVENANCE_KEYS)
        if unknown_provenance:
            problems.append(f"provenance has unknown key {', '.join(unknown_provenance)}")
        if not all(isinstance(value, str) for value in provenance.values()):
            problems.append("provenance values must be text")
    problems.extend(execution_problems(record.get("execution")))
    for key in ("inputs", "steps", "limitations"):
        if key in record:
            problems.extend(string_list_problems(record, key))
    outcome = record.get("outcome")
    if not isinstance(outcome, dict):
        problems.append("outcome must be an object with result and detail")
    else:
        if set(outcome) - {"result", "detail"}:
            problems.append(f"outcome has unknown key {', '.join(sorted(set(outcome) - {'result', 'detail'}))}")
        if outcome.get("result") not in RESULTS:
            problems.append(f"outcome.result {outcome.get('result')!r} is not one of {', '.join(RESULTS)}")
        if blank(outcome.get("detail")):
            problems.append("outcome.detail must say what was observed or why the check did not run")
    return problems


def known_subjects(root: Path) -> set:
    tickets = {path.stem for path in (root / "tickets").glob("*.md")}
    experiments = {path.name[:7] for path in (root / "experiments").glob("LAB-*.md")}
    return tickets | experiments


def check(root: Path) -> CheckResult:
    directory = root / EVIDENCE_DIR
    files = sorted(directory.rglob("*.json")) if directory.is_dir() else []
    if not files:
        return CheckResult(CHECK, "passed", f"no evidence records stored yet: {EVIDENCE_DIR}/ holds 0 JSON files")
    subjects = known_subjects(root)
    problems = []
    for path in files:
        name = relative(path, root)
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            problems.append(f"{name}: not valid JSON ({error})")
            continue
        problems.extend(f"{name}: {message}" for message in record_problems(record))
        subject = record.get("subject") if isinstance(record, dict) else None
        folder = path.relative_to(directory).parts[0] if len(path.relative_to(directory).parts) > 1 else None
        if isinstance(subject, str) and folder != subject:
            problems.append(f"{name}: a {subject} record belongs under {EVIDENCE_DIR}/{subject}/")
        if isinstance(subject, str) and ID_PATTERN.match(subject) and subject not in subjects:
            problems.append(f"{name}: subject {subject} has no ticket or experiment spec")
    if problems:
        return CheckResult(CHECK, "failed", f"{len(problems)} problems in {len(files)} evidence records", problems)
    return CheckResult(CHECK, "passed", f"{len(files)} evidence records under {EVIDENCE_DIR}/ are valid")
