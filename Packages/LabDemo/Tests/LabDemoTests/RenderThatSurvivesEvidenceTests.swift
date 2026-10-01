import Foundation
@testable import LabDemo
import LabSupport
import Testing

/// A LAB-032 run in the iOS simulator, as the UI-test harness that drove it observed it.
///
/// The facts are read from a file kept outside the repository. The record is built on the
/// simulator path, so it supports `implemented` at most; the provenance is read from the
/// Info.plist of the simulator build that was installed, and a device build is refused. No field
/// may carry a UUID, which is what a simulator's identifier and a job's identifier are.
struct RenderSimulatorRun: Codable {
    /// The record's file name in the export, without `.json`.
    let name: String
    let check: String
    let observedAt: Date
    /// The simulated model, such as "iPhone 17 Pro".
    let deviceClass: String
    /// The simulator runtime, such as "27.0 (24A434)".
    let osVersion: String
    let buildInfoPlist: String
    let inputs: [String]
    let steps: [String]
    let result: RunResult
    let observed: String
    let limitations: [String]

    static let subject = "LAB-032"

    enum Refusal: Error, Equatable {
        case namesAnIdentifier(field: String)
        case notASimulatorBuild(sdk: String)
    }

    struct Facts: Codable {
        let runs: [RenderSimulatorRun]
    }

    static func load(_ url: URL) throws -> [RenderSimulatorRun] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Facts.self, from: Data(contentsOf: url)).runs
    }

    func record() throws -> EvidenceRecord {
        let text: [(String, String)] = [("deviceClass", deviceClass), ("osVersion", osVersion), ("check", check), ("observed", observed)]
            + inputs.map { ("inputs", $0) } + steps.map { ("steps", $0) } + limitations.map { ("limitations", $0) }
        for (field, value) in text where Self.containsUUID(value) {
            throw Refusal.namesAnIdentifier(field: field)
        }
        let info = try #require(NSDictionary(contentsOf: URL(filePath: buildInfoPlist)) as? [String: Any], "the build's Info.plist")
        let provenance = BuildProvenance(infoDictionary: info)
        guard provenance.sdkName.hasPrefix("iphonesimulator") else { throw Refusal.notASimulatorBuild(sdk: provenance.sdkName) }
        return try EvidenceRecord(
            subject: Self.subject,
            check: check,
            date: observedAt,
            provenance: provenance,
            execution: .simulator(SimulatedDevice(platform: .iOS, deviceClass: deviceClass, osVersion: osVersion)),
            inputs: inputs,
            steps: steps,
            outcome: RunOutcome(result, detail: observed),
            limitations: limitations
        )
    }

    var exportPath: String { "records/\(name).json" }

    private static func containsUUID(_ value: String) -> Bool {
        value.components(separatedBy: CharacterSet(charactersIn: " \t\n()[]{},;:/=\"'.…")).contains { UUID(uuidString: $0) != nil }
    }
}

@Suite struct RenderThatSurvivesEvidence {
    private func infoPlist(in folder: TemporaryFolder, sdk: String = "iphonesimulator27.0") throws -> URL {
        let info: [String: Any] = [
            "LabSourceRevision": "0000000", "DTSDKName": sdk, "DTXcode": "2700", "DTXcodeBuild": "27A266a",
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "LabBuildProfile": "CoreLocal", "MinimumOSVersion": "26.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        return try folder.write(data, to: "Info.plist")
    }

    private func run(plist: URL, observed: String = "Stopped at 2 of 9.", inputs: [String] = ["recipes@sha256:00"]) -> RenderSimulatorRun {
        RenderSimulatorRun(
            name: "render-simulator", check: "Leave and return in the simulator", observedAt: fixedDate, deviceClass: "iPhone 17 Pro",
            osVersion: "27.0 (24A434)", buildInfoPlist: plist.path(percentEncoded: false), inputs: inputs,
            steps: ["Render, leave, return."], result: .passed, observed: observed, limitations: ["Simulator only."]
        )
    }

    /// The generator: a simulator record supports `implemented` at most and is no device proof; a
    /// device build is refused; and no record may name a simulator or a job by its identifier.
    @Test func aSimulatorRunIsRecordedOnTheSimulatorPathOnly() throws {
        let folder = try TemporaryFolder()
        let plist = try infoPlist(in: folder)
        let record = try run(plist: plist).record()
        #expect(record.subject == "LAB-032" && record.path == .simulator)
        #expect(record.supportedState == .implemented)
        #expect(throws: PromotionError.notPhysical(.simulator)) { try DeviceProof(record) }

        let id = UUID().uuidString
        #expect(throws: RenderSimulatorRun.Refusal.namesAnIdentifier(field: "observed")) {
            try run(plist: plist, observed: "Job \(id) stopped.").record()
        }
        #expect(throws: RenderSimulatorRun.Refusal.namesAnIdentifier(field: "inputs")) {
            try run(plist: plist, inputs: ["work:Work/\(id)/segment-000.mov@sha256:00"]).record()
        }
        let deviceFolder = try TemporaryFolder()
        let device = try infoPlist(in: deviceFolder, sdk: "iphoneos27.0")
        #expect(throws: RenderSimulatorRun.Refusal.notASimulatorBuild(sdk: "iphoneos27.0")) { try run(plist: device).record() }
    }

    /// Writes LAB-032's observed runs through the review. Runs only when the runs are named:
    ///
    ///     LAB_032_RUN_FACTS=<facts.json> LAB_HOST_EVIDENCE_RECORD=<record> \
    ///     LAB_DEMO_EVIDENCE_DIR=<folder> \
    ///     swift test --package-path Packages/LabDemo --filter RenderThatSurvivesEvidence
    ///
    /// `LAB_HOST_EVIDENCE_RECORD` is the record `RenderSurvivesHostEvidenceTests` attached,
    /// exported from its result bundle. Every record must be for LAB-032 at one source revision.
    /// Keep the facts and the export outside the repository, and copy `records/*.json` into
    /// `evidence/LAB-032/`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LAB_032_RUN_FACTS"] != nil))
    func theObservedRunsExportThroughTheReview() throws {
        let environment = ProcessInfo.processInfo.environment
        let folder = URL(filePath: try #require(environment["LAB_DEMO_EVIDENCE_DIR"]), directoryHint: .isDirectory)
        let runs = try RenderSimulatorRun.load(URL(filePath: try #require(environment["LAB_032_RUN_FACTS"])))

        var artifacts: [ExportArtifact] = []
        var records: [(String, EvidenceRecord)] = []
        for run in runs {
            let record = try run.record()
            try #require(record.provenance.sourceRevision != "unknown" && record.provenance.xcodeBuild != "unknown")
            artifacts.append(try .record(record, at: run.exportPath, tier: .publicFixture))
            records.append((run.exportPath, record))
        }
        if let path = environment["LAB_HOST_EVIDENCE_RECORD"] {
            let host = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: URL(filePath: path)))
            let exportPath = "records/render-that-survives-host.json"
            artifacts.append(try .record(host, at: exportPath, tier: .publicFixture))
            records.append((exportPath, host))
        }
        try #require(!records.isEmpty)
        let revisions = Set(records.map(\.1.provenance.sourceRevision))
        try #require(revisions.count == 1, "one source revision per export: \(revisions.sorted())")
        try #require(records.allSatisfy { $0.1.subject == RenderSimulatorRun.subject })

        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-032 Render That Survives qualification",
            artifacts: artifacts,
            untested: [
                "A physical iPhone or iPad: no device was used.",
                "Continued processing granted by iOS: the simulator answered that it is unavailable.",
                "Background GPU: the lab requests no entitlement for it.",
            ],
            provenance: records[0].1.provenance
        ))
        try #require(preview.refused.isEmpty)
        let written = try preview.write(into: folder, folderName: "lab-032-render-that-survives")
        for (path, record) in records {
            let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: path)))
            #expect(stored == record)
        }
    }
}
