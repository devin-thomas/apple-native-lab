from __future__ import annotations

import copy
import json
import re
import unittest

from support import ROOT, RepositoryCopyTestCase

import evidence

GOLDEN = ROOT / "Packages/LabSupport/Tests/LabSupportTests/EvidenceGolden.swift"


def swift_goldens() -> list:
    """Every raw multi-line string literal in EvidenceGolden.swift, parsed as JSON."""
    text = GOLDEN.read_text(encoding="utf-8")
    return [json.loads(body) for body in re.findall(r'#"""\n(.*?)\n\s*"""#', text, re.S)]


class SwiftAgreementTests(unittest.TestCase):
    def test_every_swift_golden_record_is_valid(self):
        goldens = swift_goldens()
        self.assertGreaterEqual(len(goldens), 3)
        for record in goldens:
            self.assertEqual(evidence.record_problems(record), [], record)

    def test_identifier_screen_matches_the_swift_cases(self):
        for value in ("00008120-001A2C3E0A38C01E", "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "Mac (C02XK0XXJGH5)",
                      "H4XK7JQ2VN", "0123456789abcdef0123456789abcdef01234567"):
            self.assertTrue(evidence.looks_like_identifier(value), value)
        for value in ("iPhone17,1 (iPhone 16 Pro)", "Mac16,5", "27.0 (24A5430a)", "Version 27.0 (Build 26A425)"):
            self.assertFalse(evidence.looks_like_identifier(value), value)


class ForgedRecordTests(unittest.TestCase):
    def setUp(self):
        self.physical = next(r for r in swift_goldens() if r["execution"]["path"] == "physical")
        self.simulator = next(r for r in swift_goldens() if r["execution"]["path"] == "simulator")

    def problems(self, record) -> str:
        return "\n".join(evidence.record_problems(record))

    def test_simulator_record_cannot_carry_a_physical_device(self):
        forged = copy.deepcopy(self.simulator)
        forged["execution"]["device"] = self.physical["execution"]["device"]
        forged["outcome"]["result"] = "passed"
        self.assertIn("a simulator execution cannot carry device", self.problems(forged))

    def test_fixture_record_cannot_carry_a_physical_device(self):
        forged = copy.deepcopy(self.physical)
        forged["execution"]["path"] = "fixture"
        self.assertIn("a fixture execution cannot carry device", self.problems(forged))

    def test_record_cannot_claim_a_state(self):
        forged = copy.deepcopy(self.simulator)
        forged["state"] = "device-verified"
        self.assertIn("unknown key state", self.problems(forged))

    def test_physical_record_needs_its_device(self):
        forged = copy.deepcopy(self.physical)
        del forged["execution"]["device"]
        self.assertIn("must name its device class and OS", self.problems(forged))

    def test_only_the_evidence_vocabulary_is_accepted(self):
        for result in ("skipped", "ok", "Passed", "success"):
            forged = copy.deepcopy(self.physical)
            forged["outcome"]["result"] = result
            self.assertIn(f"outcome.result '{result}' is not one of passed, failed, blocked, not-run", self.problems(forged))

    def test_blocked_or_not_run_must_say_why(self):
        for result in ("blocked", "not-run"):
            forged = copy.deepcopy(self.simulator)
            forged["outcome"] = {"result": result, "detail": " "}
            self.assertIn("outcome.detail must say", self.problems(forged))

    def test_serial_number_is_refused(self):
        forged = copy.deepcopy(self.physical)
        forged["execution"]["device"]["deviceClass"] = "iPhone17,1 C02XK0XXJGH5"
        self.assertIn("looks like a serial number", self.problems(forged))


class StoredEvidenceTests(RepositoryCopyTestCase):
    def store(self, name: str, record) -> None:
        self.write(f"evidence/{name}", json.dumps(record, indent=2))

    def record(self, subject: str = "CORE-007") -> dict:
        record = copy.deepcopy(swift_goldens()[0])
        record["subject"] = subject
        return record

    def test_no_records_yet_is_stated(self):
        result = evidence.check(self.root)
        self.assertEqual(result.result, "passed")
        self.assertIn("0 JSON files", result.summary)

    def test_valid_record_in_its_subject_folder_passes(self):
        self.store("CORE-007/3d138f6-sample.json", self.record())
        result = evidence.check(self.root)
        self.assertEqual(result.result, "passed", result.problems)
        self.assertIn("1 evidence records", result.summary)

    def test_record_in_the_wrong_folder_fails(self):
        self.store("CORE-004/sample.json", self.record("CORE-007"))
        self.assertIn("belongs under evidence/CORE-007/", "\n".join(evidence.check(self.root).problems))

    def test_unknown_subject_fails(self):
        self.store("LAB-999/sample.json", self.record("LAB-999"))
        self.assertIn("has no ticket or experiment spec", "\n".join(evidence.check(self.root).problems))

    def test_invalid_json_fails(self):
        self.write("evidence/CORE-007/broken.json", "{not json")
        self.assertEqual(evidence.check(self.root).result, "failed")


if __name__ == "__main__":
    unittest.main()
