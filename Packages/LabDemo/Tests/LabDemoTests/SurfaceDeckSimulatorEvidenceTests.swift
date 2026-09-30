import Foundation
@testable import LabDemo
import LabSupport
import Testing

/// A LAB-004 run in the iOS simulator, as the UI-test harness that drove it observed it.
///
/// The facts are read from a file kept outside the repository, next to the harness's own output.
/// The record is built by `EvidenceRecord` on the simulator path, so it supports `implemented` at
/// most; the provenance is read from the Info.plist of the simulator build that was installed, and
/// a device build is refused. No field may carry a UUID, which is what a simulator's identifier is.
struct SurfaceDeckSimulatorRun: Codable {
    /// The record's file name in the export, without `.json`.
    let name: String
    let check: String
    /// When the result was observed.
    let observedAt: Date
    /// The simulated model, such as "iPhone 17 Pro".
    let deviceClass: String
    /// The simulator runtime, such as "27.0 (24A434)".
    let osVersion: String
    /// The Info.plist of the simulator build that was installed.
    let buildInfoPlist: String
    let inputs: [String]
    let steps: [String]
    let result: RunResult
    let observed: String
    let limitations: [String]

    enum Refusal: Error, Equatable {
        case namesASimulator(field: String)
        case notASimulatorBuild(sdk: String)
    }

    struct Facts: Codable {
        let runs: [SurfaceDeckSimulatorRun]
    }

    static func load(_ url: URL) throws -> [SurfaceDeckSimulatorRun] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Facts.self, from: Data(contentsOf: url)).runs
    }

    func record() throws -> EvidenceRecord {
        let text: [(String, String)] = [("deviceClass", deviceClass), ("osVersion", osVersion), ("check", check), ("observed", observed)]
            + steps.map { ("steps", $0) } + limitations.map { ("limitations", $0) }
        for (field, value) in text where Self.containsUUID(value) {
            throw Refusal.namesASimulator(field: field)
        }
        let info = try #require(NSDictionary(contentsOf: URL(filePath: buildInfoPlist)) as? [String: Any], "the build's Info.plist")
        let provenance = BuildProvenance(infoDictionary: info)
        guard provenance.sdkName.hasPrefix("iphonesimulator") else { throw Refusal.notASimulatorBuild(sdk: provenance.sdkName) }
        return try EvidenceRecord(
            subject: "LAB-004",
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
        value.components(separatedBy: CharacterSet(charactersIn: " \t\n()[]{},;:/=\"'.")).contains { UUID(uuidString: $0) != nil }
    }
}

@Suite struct SurfaceDeckSimulatorEvidence {
    private func infoPlist(in folder: TemporaryFolder, sdk: String = "iphonesimulator27.0") throws -> URL {
        let info: [String: Any] = [
            "LabSourceRevision": "0000000", "DTSDKName": sdk, "DTXcode": "2700", "DTXcodeBuild": "27A266a",
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "LabBuildProfile": "SystemSurfaces", "MinimumOSVersion": "26.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        return try folder.write(data, to: "Info.plist")
    }

    private func run(plist: URL, deviceClass: String = "iPhone 17 Pro", observed: String = "It worked.") -> SurfaceDeckSimulatorRun {
        SurfaceDeckSimulatorRun(
            name: "simulator-run", check: "A run in the simulator", observedAt: fixedDate, deviceClass: deviceClass,
            osVersion: "27.0 (24A434)", buildInfoPlist: plist.path(percentEncoded: false), inputs: ["seed@sha256:00"],
            steps: ["Run it."], result: .passed, observed: observed, limitations: ["Simulator only."]
        )
    }

    /// The generator itself: a simulator record from a simulator build, never a device record, and
    /// never one that names the simulator it ran on.
    @Test func aSimulatorRunIsRecordedOnTheSimulatorPathOnly() throws {
        let folder = try TemporaryFolder()
        let plist = try infoPlist(in: folder)
        let record = try run(plist: plist).record()
        #expect(record.path == .simulator)
        #expect(record.supportedState == .implemented, "a simulator never supports device-verified")
        #expect(record.provenance.toolchainSummary == "Xcode 27.0 (27A266a), iphonesimulator27.0")
        #expect(record.provenance.buildProfile == "SystemSurfaces")
        #expect(throws: PromotionError.notPhysical(.simulator)) { try DeviceProof(record) }

        let udid = UUID().uuidString
        #expect(throws: SurfaceDeckSimulatorRun.Refusal.namesASimulator(field: "deviceClass")) {
            try run(plist: plist, deviceClass: "iPhone 17 Pro (\(udid))").record()
        }
        #expect(throws: SurfaceDeckSimulatorRun.Refusal.namesASimulator(field: "observed")) {
            try run(plist: plist, observed: "Ran on \(udid).").record()
        }
        let deviceFolder = try TemporaryFolder()
        let device = try infoPlist(in: deviceFolder, sdk: "iphoneos27.0")
        #expect(throws: SurfaceDeckSimulatorRun.Refusal.notASimulatorBuild(sdk: "iphoneos27.0")) { try run(plist: device).record() }

        // A simulator created for the run holds only the demo seed, so its record is public.
        let preview = try EvidenceExporter(now: { fixedDate }).preview(EvidenceExportRequest(
            title: "Simulator run", artifacts: [try .record(record, at: "records/simulator-run.json", tier: .publicFixture)],
            provenance: record.provenance
        ))
        #expect(preview.refused.isEmpty && preview.result == .passed)
    }

    /// Writes the observed runs' records through the review. Runs only when both are named:
    ///
    ///     LAB_SIMULATOR_RUN_FACTS=<facts.json> LAB_DEMO_EVIDENCE_DIR=<folder> \
    ///     swift test --package-path Packages/LabDemo --filter SurfaceDeckSimulatorEvidence
    ///
    /// Keep the facts file and the export outside the repository, and copy the exported records
    /// into `evidence/LAB-004/`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LAB_SIMULATOR_RUN_FACTS"] != nil))
    func theObservedRunsExportThroughTheReview() throws {
        let environment = ProcessInfo.processInfo.environment
        let runs = try SurfaceDeckSimulatorRun.load(URL(filePath: try #require(environment["LAB_SIMULATOR_RUN_FACTS"])))
        let folder = URL(filePath: try #require(environment["LAB_DEMO_EVIDENCE_DIR"]), directoryHint: .isDirectory)
        try #require(!runs.isEmpty)
        let records = try runs.map { try $0.record() }
        let provenance = try #require(records.first?.provenance)
        for record in records {
            try #require(record.provenance.sourceRevision != "unknown" && record.provenance.xcodeBuild != "unknown")
            try #require(record.provenance == provenance, "one build per export")
        }
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-004 Surface Deck in the iOS simulator",
            artifacts: try zip(runs, records).map { try .record($1, at: $0.exportPath, tier: .publicFixture) },
            untested: ["A physical iPhone: no device was used."],
            provenance: provenance
        ))
        try #require(preview.refused.isEmpty)
        let written = try preview.write(into: folder, folderName: "lab-004-surface-deck-simulator")
        for (run, record) in zip(runs, records) {
            let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: run.exportPath)))
            #expect(stored == record)
            #expect(stored.path == .simulator)
        }
    }
}
