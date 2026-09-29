from __future__ import annotations

import io
import itertools
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

from support import ROOT, VALIDATE, RepositoryCopyTestCase

import all as validate_all
import ci
import ledger
from common import EXIT_CODES, RESULTS, CheckResult, combine


def run_script(*arguments, env=None) -> subprocess.CompletedProcess:
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", **(env or {}))
    return subprocess.run([sys.executable, *map(str, arguments)], capture_output=True, text=True, env=environment)


class CombineTests(unittest.TestCase):
    """The same precedence as RunResult.combining in Packages/LabSupport."""

    def test_every_pair_takes_the_worst(self):
        precedence = ["failed", "blocked", "not-run", "passed"]
        for first, second in itertools.product(RESULTS, repeat=2):
            worst = next(result for result in precedence if result in (first, second))
            self.assertEqual(combine([first, second]), worst)

    def test_nothing_is_not_run(self):
        self.assertEqual(combine([]), "not-run")

    def test_unknown_result_is_refused(self):
        with self.assertRaises(ValueError):
            combine(["skipped"])
        with self.assertRaises(ValueError):
            CheckResult("x", "ok", "summary")


class AllEntryPointTests(RepositoryCopyTestCase):
    def test_repository_passes_with_exit_zero(self):
        process = run_script(VALIDATE / "all.py", "--json")
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        report = json.loads(process.stdout)
        self.assertEqual(report["overall"], "passed")
        self.assertEqual({check["result"] for check in report["checks"]}, {"passed"})
        self.assertEqual(len(report["checks"]), len(validate_all.CHECKS))

    def test_broken_link_fails_with_exit_one_and_a_clear_message(self):
        self.write("docs/NOTE.md", "[gone](GONE.md)\n")
        process = run_script(VALIDATE / "all.py", "--root", self.root)
        self.assertEqual(process.returncode, EXIT_CODES["failed"])
        self.assertIn("FAILED   links", process.stdout)
        self.assertIn("docs/NOTE.md:1: link to `GONE.md`:", process.stdout)
        self.assertIn("docs/GONE.md does not exist", process.stdout)
        self.assertIn("Overall: FAILED", process.stdout)

    def test_dependency_cycle_fails_with_exit_one_and_a_clear_message(self):
        self.set_depends_on("CORE-001", ["CORE-002"])
        process = run_script(VALIDATE / "all.py", "--root", self.root)
        self.assertEqual(process.returncode, EXIT_CODES["failed"])
        self.assertIn("FAILED   ticket-graph", process.stdout)
        self.assertIn("dependency cycle: CORE-001 -> CORE-002 -> CORE-001", process.stdout)

    def test_blocked_is_reported_distinctly_from_passed(self):
        self.edit("SPEC.md", r"Use exactly these implementation states:", "The implementation states are:")
        process = run_script(VALIDATE / "all.py", "--root", self.root)
        self.assertEqual(process.returncode, EXIT_CODES["blocked"], process.stdout)
        self.assertIn("BLOCKED  state-vocabulary", process.stdout)
        self.assertIn("Overall: BLOCKED", process.stdout)

    def test_crashing_validator_fails_instead_of_passing(self):
        def crash(root):
            raise RuntimeError("boom")
        with mock.patch.object(validate_all, "CHECKS", (("crash", crash),)):
            results = validate_all.run_checks(self.root)
        self.assertEqual([(r.check, r.result) for r in results], [("crash", "failed")])

    def test_results_are_appended_to_the_ledger(self):
        path = self.outside / "ledger.jsonl"
        self.write("docs/NOTE.md", "[gone](GONE.md)\n")
        run_script(VALIDATE / "all.py", "--root", self.root, "--ledger", path)
        entries = ledger.read(path)
        self.assertEqual(entries["validate:links"][0], "failed")
        self.assertEqual(entries["validate:ticket-graph"][0], "passed")


class XcodeSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.applications = Path(self.temporary.name)
        self.ledger = self.applications / "ledger.jsonl"

    def install(self, name: str, version: str, build: str) -> None:
        contents = self.applications / name / "Contents"
        contents.mkdir(parents=True)
        with (contents / "version.plist").open("wb") as handle:
            plistlib.dump({"CFBundleShortVersionString": version, "ProductBuildVersion": build}, handle)

    def select(self) -> tuple:
        github_env = self.applications / "github_env"
        output = io.StringIO()
        with redirect_stdout(output):
            code = ci.main(["--ledger", str(self.ledger), "select-xcode", "--applications", str(self.applications),
                            "--github-env", str(github_env)])
        exported = dict(line.split("=", 1) for line in github_env.read_text().splitlines())
        return code, exported, ledger.read(self.ledger)["xcode-selection"]

    def test_prefers_27_and_adds_a_26_compatibility_compile(self):
        self.install("Xcode_26.4.app", "26.4", "17E192")
        self.install("Xcode_27.0_beta.app", "27.0", "27A5228h")
        self.install("Xcode_16.4.app", "16.4", "16F6")
        code, exported, entry = self.select()
        self.assertEqual(code, 0)
        self.assertTrue(exported["DEVELOPER_DIR"].endswith("Xcode_27.0_beta.app/Contents/Developer"))
        self.assertTrue(exported["LAB_COMPAT_DEVELOPER_DIR"].endswith("Xcode_26.4.app/Contents/Developer"))
        self.assertEqual(entry[0], "passed")

    def test_release_beats_beta_of_the_same_version(self):
        self.install("Xcode-27.0.0-Beta.4.app", "27.0", "27A5228h")
        self.install("Xcode.app", "27.0", "27A266a")
        _, exported, _ = self.select()
        self.assertEqual(exported["LAB_XCODE"], "27.0 (27A266a)")
        self.assertEqual(exported["LAB_COMPAT_REASON"], "no Xcode 26 is installed on this runner")

    def test_newest_26_when_27_is_absent_and_says_so(self):
        self.install("Xcode_26.2.app", "26.2", "17C52")
        self.install("Xcode_26.4.1.app", "26.4.1", "17E202")
        code, exported, entry = self.select()
        self.assertEqual(code, 0)
        self.assertEqual(exported["LAB_XCODE"], "26.4.1 (17E202)")
        self.assertNotIn("LAB_COMPAT_DEVELOPER_DIR", exported)
        self.assertIn("26-family compatibility level", entry[1])

    def test_symbolic_link_alias_is_listed_once(self):
        self.install("Xcode_26.4.app", "26.4", "17E192")
        os.symlink(self.applications / "Xcode_26.4.app", self.applications / "Xcode.app")
        self.assertEqual(len(ci.installed_xcodes(self.applications)), 1)

    def test_no_supported_xcode_is_blocked_not_passed(self):
        self.install("Xcode_16.4.app", "16.4", "16F6")
        self.install("Xcode_28.0.app", "28.0", "28A100")
        code, exported, entry = self.select()
        self.assertEqual(code, EXIT_CODES["blocked"])
        self.assertEqual(exported["LAB_XCODE_READY"], "false")
        self.assertEqual(entry[0], "blocked")
        self.assertIn("installed: 16.4 (16F6), 28.0 (28A100)", entry[1])


class RunAndSummaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.ledger = Path(self.temporary.name) / "ledger.jsonl"

    def ci(self, *arguments) -> tuple:
        output = io.StringIO()
        with redirect_stdout(output):
            code = ci.main(["--ledger", str(self.ledger), *arguments])
        return code, output.getvalue()

    def python(self, source: str) -> list:
        return ["--", sys.executable, "-c", source]

    def test_classify_distinguishes_every_result(self):
        self.assertEqual(ci.classify(1, [], True, "cmd", 1)[0], "failed")
        self.assertEqual(ci.classify(0, [], False, "cmd", 1)[0], "passed")
        self.assertEqual(ci.classify(0, [], True, "cmd", 1)[0], "not-run")
        self.assertEqual(ci.classify(0, ["Test run with 0 tests in 0 suites passed"], True, "cmd", 1)[0], "not-run")
        self.assertEqual(ci.classify(0, ["Executed 0 tests, with 0 failures", "Test run with 3 tests in 1 suite passed"],
                                     True, "cmd", 1), ("passed", "3 tests passed after 1 s: cmd"))
        self.assertEqual(ci.test_count(["Executed 2 tests, with 0 failures", "Executed 5 tests, with 0 failures",
                                        "Ran 4 tests in 0.1s"]), 9)

    def test_run_preserves_the_exit_code_and_records_failure(self):
        code, _ = self.ci("run", "step", *self.python("import sys; sys.exit(7)"))
        self.assertEqual(code, 7)
        self.assertEqual(ledger.read(self.ledger)["step"][0], "failed")

    def test_zero_tests_is_not_run_and_not_green(self):
        code, _ = self.ci("run", "tests", "--expect-tests", *self.python("print('Test run with 0 tests in 0 suites passed')"))
        self.assertEqual(code, EXIT_CODES["not-run"])
        self.assertEqual(ledger.read(self.ledger)["tests"][0], "not-run")

    def test_missing_command_is_blocked(self):
        code, _ = self.ci("run", "tool", "--", "lab-command-that-does-not-exist")
        self.assertEqual(code, EXIT_CODES["blocked"])
        self.assertEqual(ledger.read(self.ledger)["tool"][0], "blocked")

    def test_required_check_that_never_ran_fails_the_summary(self):
        self.ci("record", "validators", "passed", "7 checks passed")
        summary = Path(self.temporary.name) / "summary.md"
        code, output = self.ci("summarize", "--require", "validators", "swift-test:LabSupport",
                               "--summary-file", str(summary))
        self.assertEqual(code, 1)
        self.assertIn("| `swift-test:LabSupport` | NOT-RUN | required | no result was recorded", summary.read_text())
        self.assertIn("**Overall: NOT-RUN.**", output)

    def test_blocked_required_check_fails_the_summary(self):
        self.ci("record", "xcode-selection", "blocked", "no Xcode 26 or 27")
        code, output = self.ci("summarize", "--require", "xcode-selection")
        self.assertEqual(code, 1)
        self.assertIn("**Overall: BLOCKED.**", output)

    def test_optional_not_run_is_listed_but_does_not_gate(self):
        self.ci("record", "validators", "passed", "7 checks passed")
        self.ci("record", "device-qualification", "not-run", "Hosted runners have no devices")
        code, output = self.ci("summarize", "--require", "validators", "--optional", "device-qualification", "compat-26:*")
        self.assertEqual(code, 0)
        self.assertIn("| `device-qualification` | NOT-RUN | optional | Hosted runners have no devices |", output)
        self.assertIn("| `compat-26:*` | NOT-RUN | optional |", output)
        self.assertIn("**Overall: PASSED.**", output)

    def test_optional_failure_gates(self):
        self.ci("record", "compat-26:LabWatch", "failed", "exit 65")
        code, _ = self.ci("summarize", "--optional", "compat-26:*")
        self.assertEqual(code, 1)

    def test_unlisted_entries_gate_as_required(self):
        self.ci("record", "surprise", "failed", "exit 1")
        self.assertEqual(self.ci("summarize")[0], 1)

    def test_repeated_check_keeps_its_worst_result(self):
        self.ci("record", "step", "failed", "first attempt")
        self.ci("record", "step", "passed", "second attempt")
        self.assertEqual(ledger.read(self.ledger)["step"], ("failed", "first attempt"))

    def test_fixture_runs_cannot_reach_the_real_job(self):
        for name in ("GITHUB_STEP_SUMMARY", "GITHUB_ENV", "GITHUB_ACTIONS", "LAB_CI_LEDGER"):
            self.assertNotIn(name, os.environ)

    def test_annotations_escape_workflow_command_syntax(self):
        self.assertEqual(ci.annotation("error", "a:b,c", "50% done\nnext"), "::error title=a%3Ab%2Cc::50%25 done%0Anext")


class FeatureLevelTests(unittest.TestCase):
    def test_27_sdk_with_the_flag_is_the_27_level(self):
        result, detail = ci.feature_level("LabMac-Core", {"SDK_NAME": "macosx27.0", "OTHER_SWIFT_FLAGS": "-D DEBUG -DLAB_SDK_27"})
        self.assertEqual(result, "passed")
        self.assertIn("27 SDK level: LAB_SDK_27 compiled in", detail)

    def test_26_sdk_without_the_flag_is_the_compatibility_level(self):
        result, detail = ci.feature_level("LabWatch", {"SDK_NAME": "watchsimulator26.4", "OTHER_SWIFT_FLAGS": ""})
        self.assertEqual(result, "passed")
        self.assertIn("26-family compatibility level: LAB_SDK_27 compiled out", detail)

    def test_mismatched_flag_fails(self):
        self.assertEqual(ci.feature_level("LabPhone-Core", {"SDK_NAME": "iphonesimulator26.4", "OTHER_SWIFT_FLAGS": "-DLAB_SDK_27"})[0], "failed")
        self.assertEqual(ci.feature_level("LabPhone-Core", {"SDK_NAME": "iphonesimulator27.0", "OTHER_SWIFT_FLAGS": ""})[0], "failed")

    def test_application_target_settings_are_chosen(self):
        entries = [{"target": "LabMacTests", "buildSettings": {"WRAPPER_EXTENSION": "xctest", "SDK_NAME": "x"}},
                   {"target": "LabMac", "buildSettings": {"WRAPPER_EXTENSION": "app", "SDK_NAME": "macosx27.0"}}]
        self.assertEqual(ci.application_settings(entries)["SDK_NAME"], "macosx27.0")


if __name__ == "__main__":
    unittest.main()
