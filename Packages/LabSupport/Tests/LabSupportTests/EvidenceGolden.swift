import Foundation
@testable import LabSupport

/// Neutral sample records and their canonical JSON.
///
/// script/validate/tests/test_evidence.py reads every raw string literal in this file and
/// checks that the repository's evidence validator accepts it, so the Swift encoder and the
/// Python validator agree on the layout. Keep only valid records here.
enum EvidenceGolden {
    /// 2026-09-29T12:00:00Z.
    static let date = Date(timeIntervalSince1970: 1_790_683_200)
    /// 2026-10-06T00:00:00Z.
    static let expiry = Date(timeIntervalSince1970: 1_791_244_800)

    static let provenance = BuildProvenance(
        sourceRevision: "3d138f6",
        sdkName: "iphoneos27.0",
        xcodeVersion: "27.0",
        xcodeBuild: "27A266a"
    )

    static func physicalDevice() throws -> PhysicalDevice {
        try PhysicalDevice(platform: .iOS, deviceClass: "iPhone17,1 (iPhone 16 Pro)", osVersion: "27.0 (24A5430a)", profileExpiry: expiry)
    }

    static func record(
        execution: Execution,
        outcome: RunOutcome = .passed(observed: "The fixture round trip matched."),
        subject: String = "LAB-000-B"
    ) throws -> EvidenceRecord {
        try EvidenceRecord(
            subject: subject,
            check: "Neutral sample check",
            date: date,
            provenance: provenance,
            execution: execution,
            inputs: ["fixture:neutral-sample@sha256:0000"],
            steps: ["swift test --package-path Packages/LabSupport"],
            outcome: outcome,
            limitations: ["Sample record for tests."]
        )
    }

    /// Every execution path, each with the device facts it requires.
    static func allExecutions() throws -> [Execution] {
        [
            .physical(try physicalDevice()),
            .simulator(SimulatedDevice(platform: .iOS, deviceClass: "iPhone 17", osVersion: "27.0")),
            .simulator(SimulatedDevice(platform: .watchOS)),
            .fixture,
            .staticReview,
        ]
    }

    static func allOutcomes() -> [RunOutcome] {
        [
            .passed(observed: "53 tests passed."),
            .failed(observed: "1 of 53 tests failed: the decoded record differed."),
            .blocked(reason: "No physical Watch was reachable."),
            .notRun(reason: "The step did not execute."),
        ]
    }

    static let physicalPassedJSON = #"""
    {
      "schemaVersion": 1,
      "subject": "LAB-000-B",
      "check": "Neutral sample check",
      "date": "2026-09-29T12:00:00Z",
      "provenance": {
        "sourceRevision": "3d138f6",
        "sdkName": "iphoneos27.0",
        "xcodeVersion": "27.0",
        "xcodeBuild": "27A266a",
        "appVersion": "unknown",
        "buildNumber": "unknown",
        "buildProfile": "unknown",
        "minimumOS": "unknown"
      },
      "execution": {
        "path": "physical",
        "device": {
          "platform": "iOS",
          "deviceClass": "iPhone17,1 (iPhone 16 Pro)",
          "osVersion": "27.0 (24A5430a)",
          "profileExpiry": "2026-10-06T00:00:00Z"
        }
      },
      "inputs": ["fixture:neutral-sample@sha256:0000"],
      "steps": ["swift test --package-path Packages/LabSupport"],
      "outcome": {"result": "passed", "detail": "The fixture round trip matched."},
      "limitations": ["Sample record for tests."]
    }
    """#

    static let simulatorBlockedJSON = #"""
    {
      "schemaVersion": 1,
      "subject": "LAB-000-B",
      "check": "Neutral sample check",
      "date": "2026-09-29T12:00:00Z",
      "provenance": {"sourceRevision": "3d138f6", "sdkName": "iphoneos27.0", "xcodeVersion": "27.0", "xcodeBuild": "27A266a"},
      "execution": {"path": "simulator", "simulator": {"platform": "iOS", "deviceClass": "iPhone 17", "osVersion": "27.0"}},
      "inputs": ["fixture:neutral-sample@sha256:0000"],
      "steps": ["swift test --package-path Packages/LabSupport"],
      "outcome": {"result": "blocked", "detail": "No physical Watch was reachable."},
      "limitations": ["Sample record for tests."]
    }
    """#

    static let fixtureNotRunJSON = #"""
    {
      "schemaVersion": 1,
      "subject": "CORE-007",
      "check": "Neutral sample check",
      "date": "2026-09-29T12:00:00Z",
      "provenance": {"sourceRevision": "3d138f6", "sdkName": "macosx27.0", "xcodeVersion": "27.0"},
      "execution": {"path": "fixture"},
      "inputs": [],
      "steps": [],
      "outcome": {"result": "not-run", "detail": "The step did not execute."},
      "limitations": []
    }
    """#
}
