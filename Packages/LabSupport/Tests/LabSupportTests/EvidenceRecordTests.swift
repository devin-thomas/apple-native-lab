import Foundation
import Testing
@testable import LabSupport

@Suite struct RunResultTests {
    @Test func vocabularyMatchesTheTestStrategy() {
        #expect(RunResult.allCases.map(\.rawValue) == ["passed", "failed", "blocked", "not-run"])
    }

    @Test(arguments: ["skipped", "Passed", "PASSED", "ok", "success", "green", "notrun", "not_run", ""])
    func unknownResultIsRejected(raw: String) {
        let data = Data("\"\(raw)\"".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RunResult.self, from: data) }
    }

    @Test func onlyPassedIsPassing() {
        #expect(RunResult.allCases.filter(\.isPassed) == [.passed])
    }

    @Test func nothingRunCombinesToNotRun() {
        #expect(RunResult.combining([]) == .notRun)
    }

    /// Every pair, so a combination is never more favorable than its worst member.
    @Test func combinationTakesTheWorstResult() {
        let precedence: [RunResult] = [.failed, .blocked, .notRun, .passed]
        for first in RunResult.allCases {
            for second in RunResult.allCases {
                let worst = precedence.first { $0 == first || $0 == second }
                #expect(RunResult.combining([first, second]) == worst, "\(first) + \(second)")
            }
        }
        #expect(RunResult.combining([.passed, .passed]) == .passed)
        #expect(RunResult.combining([.passed, .notRun]) == .notRun)
    }
}

@Suite struct RunOutcomeTests {
    @Test(arguments: EvidenceGolden.allOutcomes())
    func summaryLeadsWithItsOwnResult(outcome: RunOutcome) {
        #expect(outcome.summary.hasPrefix(outcome.result.title + ": "))
        if !outcome.result.isPassed {
            #expect(!outcome.summary.hasPrefix(RunResult.passed.title))
        }
    }

    @Test(arguments: EvidenceGolden.allOutcomes())
    func notPassedNeverSerializesAsPassed(outcome: RunOutcome) throws {
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(outcome)) as? [String: String]
        #expect(object?["result"] == outcome.result.rawValue)
        if !outcome.result.isPassed {
            #expect(object?["result"] != "passed")
        }
        #expect(try JSONDecoder().decode(RunOutcome.self, from: try JSONEncoder().encode(outcome)) == outcome)
    }

    @Test(arguments: RunResult.allCases)
    func blankDetailIsRejectedWhenDecoding(result: RunResult) {
        let data = Data(#"{"result": "\#(result.rawValue)", "detail": "  "}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RunOutcome.self, from: data) }
    }
}

@Suite struct EvidenceRecordTests {
    @Test func roundTripsEveryPathAndResult() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for execution in try EvidenceGolden.allExecutions() {
            for outcome in EvidenceGolden.allOutcomes() {
                let record = try EvidenceGolden.record(execution: execution, outcome: outcome)
                let decoded = try JSONDecoder().decode(EvidenceRecord.self, from: try encoder.encode(record))
                #expect(decoded == record, "\(execution.path) \(outcome.result)")
            }
        }
    }

    @Test func goldenJSONDecodesToTheExpectedRecord() throws {
        let physical = try EvidenceGolden.record(execution: .physical(try EvidenceGolden.physicalDevice()))
        #expect(try decode(EvidenceGolden.physicalPassedJSON) == physical)

        let simulator = try EvidenceGolden.record(
            execution: .simulator(SimulatedDevice(platform: .iOS, deviceClass: "iPhone 17", osVersion: "27.0")),
            outcome: .blocked(reason: "No physical Watch was reachable.")
        )
        #expect(try decode(EvidenceGolden.simulatorBlockedJSON) == simulator)

        let fixture = try decode(EvidenceGolden.fixtureNotRunJSON)
        #expect(fixture.path == .fixture)
        #expect(fixture.result == .notRun)
        #expect(fixture.provenance.xcodeBuild == "unknown")
    }

    /// The encoder writes exactly the golden layout, so files written by this build and read by
    /// the repository validator agree.
    @Test func encodesTheGoldenLayout() throws {
        let record = try EvidenceGolden.record(execution: .physical(try EvidenceGolden.physicalDevice()))
        let encoded = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(record)) as? NSDictionary
        let golden = try JSONSerialization.jsonObject(with: Data(EvidenceGolden.physicalPassedJSON.utf8)) as? NSDictionary
        #expect(encoded != nil)
        #expect(encoded == golden)
    }

    @Test func datesAreWholeSecondsInUTC() throws {
        let record = try EvidenceGolden.record(execution: .fixture)
        let fractional = try EvidenceRecord(
            subject: record.subject, check: record.check, date: EvidenceGolden.date.addingTimeInterval(0.75),
            provenance: record.provenance, execution: .fixture, outcome: record.outcome
        )
        #expect(fractional.date == EvidenceGolden.date)
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(fractional)) as? [String: Any]
        #expect(object?["date"] as? String == "2026-09-29T12:00:00Z")
    }

    @Test(arguments: ["CORE-007", "LAB-001", "LAB-001-B", "CORE-012"])
    func acceptsTicketAndExperimentIDs(subject: String) throws {
        #expect(try EvidenceGolden.record(execution: .fixture, subject: subject).subject == subject)
    }

    @Test(arguments: ["", "core-007", "CORE-7", "CORE-0071", "LAB-001-b", "LAB-001-AB", "LAB 001", "CORE-007-", "-007"])
    func rejectsOtherSubjects(subject: String) {
        #expect(throws: EvidenceError.invalidSubject(subject)) {
            try EvidenceGolden.record(execution: .fixture, subject: subject)
        }
    }

    @Test(arguments: RunResult.allCases)
    func everyOutcomeMustSayWhat(result: RunResult) {
        #expect(throws: EvidenceError.blankField("outcome.detail")) {
            try EvidenceGolden.record(execution: .fixture, outcome: RunOutcome(result, detail: " \n"))
        }
    }

    @Test func blankListEntriesAreRejected() {
        #expect(throws: EvidenceError.blankField("limitations")) {
            try EvidenceRecord(
                subject: "CORE-007", check: "c", date: EvidenceGolden.date, provenance: EvidenceGolden.provenance,
                execution: .fixture, outcome: .passed(observed: "ok"), limitations: [""]
            )
        }
    }

    @Test func unsupportedSchemaVersionIsRejected() {
        let json = EvidenceGolden.fixtureNotRunJSON.replacingOccurrences(of: #""schemaVersion": 1"#, with: #""schemaVersion": 2"#)
        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test func missingFieldsAreRejected() {
        let json = EvidenceGolden.fixtureNotRunJSON.replacingOccurrences(of: #""limitations": []"#, with: #""other": []"#)
        #expect(throws: DecodingError.self) { try decode(json) }
    }

    /// The result cell of a rendered log row always starts with the record's own result.
    @Test func logRowLeadsWithTheResult() throws {
        for execution in try EvidenceGolden.allExecutions() {
            for outcome in EvidenceGolden.allOutcomes() {
                let row = try EvidenceGolden.record(execution: execution, outcome: outcome).logRow
                let cells = row.split(separator: "|", omittingEmptySubsequences: false).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                #expect(cells.count == 6, "\(row)")
                let resultCell = cells[4]
                #expect(resultCell.hasPrefix("\(outcome.result.title) (\(execution.path.title)"), "\(row)")
                if !outcome.result.isPassed {
                    #expect(!resultCell.hasPrefix(RunResult.passed.title), "\(row)")
                }
            }
        }
    }

    @Test func logRowEscapesTableSyntax() throws {
        let record = try EvidenceGolden.record(execution: .fixture, outcome: .failed(observed: "a | b\nc"))
        #expect(record.logRow.hasPrefix("| 2026-09-29 | Neutral sample check (LAB-000-B) | `swift test"))
        #expect(record.logRow.contains(#"Failed (Fixture): a \| b c"#))
    }

    private func decode(_ json: String) throws -> EvidenceRecord {
        try JSONDecoder().decode(EvidenceRecord.self, from: Data(json.utf8))
    }
}

@Suite struct ExecutionTests {
    /// A simulator or fixture record cannot carry physical-device fields, even in a hand-edited file.
    @Test(arguments: ["simulator", "fixture", "static-review"])
    func nonPhysicalPathCannotNameADevice(path: String) {
        let json = #"""
        {"path": "\#(path)", "simulator": {"platform": "iOS"}, "device": {"platform": "iOS", "deviceClass": "iPhone17,1", "osVersion": "27.0"}}
        """#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Execution.self, from: Data(json.utf8)) }
    }

    @Test func physicalPathNeedsItsDevice() {
        let json = #"{"path": "physical"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Execution.self, from: Data(json.utf8)) }
    }

    @Test func onlyTheSimulatorPathNamesASimulator() {
        let json = #"{"path": "fixture", "simulator": {"platform": "iOS"}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Execution.self, from: Data(json.utf8)) }
    }

    @Test(arguments: ["device", "hardware", "Physical", "static review", "emulator"])
    func unknownPathIsRejected(path: String) {
        let json = #"{"path": "\#(path)"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Execution.self, from: Data(json.utf8)) }
    }

    @Test func simulatorSnapshotIsNeverPhysical() throws {
        let snapshot = DeviceSnapshot(
            platform: "iOS", osVersion: "27.0", modelIdentifier: "iPhone18,3",
            environment: .simulator, memoryGigabytes: 8, processorCount: 6
        )
        let execution = try Execution(observing: snapshot)
        #expect(execution.path == .simulator)
        #expect(execution == .simulator(SimulatedDevice(platform: .iOS, deviceClass: "iPhone18,3", osVersion: "27.0")))
    }

    @Test func physicalSnapshotRecordsClassAndOS() throws {
        let snapshot = DeviceSnapshot(
            platform: "macOS", osVersion: "Version 27.0 (Build 26A425)", modelIdentifier: "Mac16,5",
            environment: .physical, memoryGigabytes: 36, processorCount: 18
        )
        let execution = try Execution(observing: snapshot)
        #expect(execution == .physical(try PhysicalDevice(
            platform: .macOS, deviceClass: "Mac16,5", osVersion: "Version 27.0 (Build 26A425)"
        )))
    }

    @Test func unknownSnapshotPlatformIsRejected() {
        let snapshot = DeviceSnapshot(
            platform: "unknown", osVersion: "1.0", modelIdentifier: "x", environment: .physical,
            memoryGigabytes: 1, processorCount: 1
        )
        #expect(throws: EvidenceError.unknownPlatform("unknown")) { try Execution(observing: snapshot) }
    }

    @Test(arguments: [
        "00008120-001A2C3E0A38C01E",
        "iPhone17,1 00008120001A2C3E0A38C01E",
        "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
        "0123456789abcdef0123456789abcdef01234567",
        "Mac (C02XK0XXJGH5)",
        "H4XK7JQ2VN",
    ])
    func deviceIdentifiersAreRefused(deviceClass: String) {
        #expect(throws: EvidenceError.deviceIdentifier(field: "device.deviceClass")) {
            try PhysicalDevice(platform: .iOS, deviceClass: deviceClass, osVersion: "27.0")
        }
    }

    @Test(arguments: [
        "iPhone17,1 (iPhone 16 Pro)", "Mac16,5", "Watch6,1 (Apple Watch Series 7)", "AppleTV14,1", "MacBookAir10,1",
    ])
    func deviceClassesAreAccepted(deviceClass: String) throws {
        let device = try PhysicalDevice(platform: .iOS, deviceClass: deviceClass, osVersion: "27.0 (24A5430a)")
        #expect(device.deviceClass == deviceClass)
    }

    @Test func blankDeviceFieldsAreRefused() {
        #expect(throws: EvidenceError.blankField("device.deviceClass")) {
            try PhysicalDevice(platform: .iOS, deviceClass: "", osVersion: "27.0")
        }
        #expect(throws: EvidenceError.blankField("device.osVersion")) {
            try PhysicalDevice(platform: .iOS, deviceClass: "iPhone17,1", osVersion: " ")
        }
    }

    @Test func decodedDeviceIsScreenedToo() {
        let json = #"{"platform": "iOS", "deviceClass": "00008120-001A2C3E0A38C01E", "osVersion": "27.0"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PhysicalDevice.self, from: Data(json.utf8)) }
    }
}

@Suite struct BuildProvenanceCodingTests {
    @Test func roundTrips() throws {
        let provenance = EvidenceGolden.provenance
        let decoded = try JSONDecoder().decode(BuildProvenance.self, from: try JSONEncoder().encode(provenance))
        #expect(decoded == provenance)
    }

    @Test func missingOrBlankValuesDecodeAsUnknown() throws {
        let json = #"{"sourceRevision": "", "sdkName": "macosx27.0"}"#
        let provenance = try JSONDecoder().decode(BuildProvenance.self, from: Data(json.utf8))
        #expect(provenance.sourceRevision == "unknown")
        #expect(provenance.sdkName == "macosx27.0")
        #expect(provenance.xcodeVersion == "unknown")
    }

    @Test func summarizesTheToolchain() {
        #expect(EvidenceGolden.provenance.toolchainSummary == "Xcode 27.0 (27A266a), iphoneos27.0")
    }
}
