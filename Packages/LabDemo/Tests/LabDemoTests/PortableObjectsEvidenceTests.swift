import Foundation
@testable import LabDemo
import LabSupport
import Testing

/// A run of LAB-008 observed outside this package: in the iOS simulator through a UI-test harness,
/// or in the Mac app itself. The facts are read from a file kept outside the repository, the
/// provenance from the built app's Info.plist, and `EvidenceRecord` validates the result, so the
/// record carries no serial number or device identifier.
struct PortableObjectsRunFacts: Codable {
    /// The record's file name in the export, without `.json`.
    let name: String
    let check: String
    let observedAt: Date
    /// `simulator` or `physical`.
    let path: String
    let platform: String
    let deviceClass: String
    let osVersion: String
    let buildInfoPlist: String
    let inputs: [String]
    let steps: [String]
    let result: RunResult
    let observed: String
    let limitations: [String]
    /// The rights tier the export declares for the record.
    let tier: DataTier
    /// Required for any tier but `public-fixture`; the export records it.
    let overrideReason: String?

    static let subject = "LAB-008"

    static func load(_ url: URL) throws -> PortableObjectsRunFacts {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortableObjectsRunFacts.self, from: Data(contentsOf: url))
    }

    func record() throws -> EvidenceRecord {
        let info = try #require(NSDictionary(contentsOf: URL(filePath: buildInfoPlist)) as? [String: Any], "the build's Info.plist")
        guard let platform = LabPlatform(rawValue: platform) else { throw EvidenceError.unknownPlatform(platform) }
        let execution: Execution = switch path {
        case "simulator": .simulator(SimulatedDevice(platform: platform, deviceClass: deviceClass, osVersion: osVersion))
        case "physical": .physical(try PhysicalDevice(platform: platform, deviceClass: deviceClass, osVersion: osVersion))
        default: throw EvidenceError.blankField("path")
        }
        return try EvidenceRecord(
            subject: Self.subject,
            check: check,
            date: observedAt,
            provenance: BuildProvenance(infoDictionary: info),
            execution: execution,
            inputs: inputs,
            steps: steps,
            outcome: RunOutcome(result, detail: observed),
            limitations: limitations
        )
    }

    var exportPath: String { "records/\(name).json" }

    func artifact(_ record: EvidenceRecord) throws -> (ExportArtifact, TierOverride?) {
        let artifact = try ExportArtifact.record(record, at: exportPath, tier: tier)
        guard tier != .publicFixture else { return (artifact, nil) }
        return (artifact, try TierOverride(path: exportPath, tier: tier, reason: try #require(overrideReason, "a reason for \(name)")))
    }
}

@Suite struct PortableObjectsEvidence {
    private func infoPlist(in folder: TemporaryFolder, sdk: String) throws -> URL {
        let info: [String: Any] = [
            "LabSourceRevision": "0000000", "DTSDKName": sdk, "DTXcode": "2700", "DTXcodeBuild": "27A266a",
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "LabBuildProfile": "CoreLocal", "MinimumOSVersion": "26.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        return try folder.write(data, to: "Info.plist")
    }

    private func facts(path: String, plist: URL, result: RunResult = .passed, tier: DataTier = .publicFixture) -> PortableObjectsRunFacts {
        PortableObjectsRunFacts(
            name: "run", check: "A Files round trip", observedAt: fixedDate, path: path,
            platform: path == "simulator" ? "iOS" : "macOS", deviceClass: path == "simulator" ? "iPhone 17" : "Mac17,14",
            osVersion: "27.0", buildInfoPlist: plist.path(percentEncoded: false), inputs: ["sample@sha256:00"],
            steps: ["Export, then import."], result: result, observed: "Observed.", limitations: ["Simulator only."],
            tier: tier, overrideReason: tier == .publicFixture ? nil : "Hardware class and observations only."
        )
    }

    /// The generator: a simulator record supports `implemented` at most and is no device proof; a
    /// failed physical record supports nothing; a tier other than `public-fixture` needs its reason.
    @Test func recordsKeepTheirPathAndNeverProveMoreThanItAllows() throws {
        let folder = try TemporaryFolder()
        let simulator = try facts(path: "simulator", plist: try infoPlist(in: folder, sdk: "iphonesimulator27.0")).record()
        #expect(simulator.path == .simulator)
        #expect(simulator.subject == "LAB-008")
        #expect(simulator.supportedState == .implemented)
        #expect(throws: PromotionError.notPhysical(.simulator)) { try DeviceProof(simulator) }

        let failed = try facts(path: "physical", plist: try infoPlist(in: folder, sdk: "macosx27.0"), result: .failed).record()
        #expect(failed.path == .physical && failed.supportedState == nil)
        #expect(throws: PromotionError.notPassed(.failed)) { try DeviceProof(failed) }

        let privateFacts = facts(path: "physical", plist: try infoPlist(in: folder, sdk: "macosx27.0"), result: .failed, tier: .userPrivate)
        let (artifact, override) = try privateFacts.artifact(failed)
        let preview = try EvidenceExporter(now: { fixedDate }).preview(EvidenceExportRequest(
            title: "LAB-008", artifacts: [artifact], overrides: override.map { [$0] } ?? [], provenance: failed.provenance
        ))
        #expect(preview.refused.isEmpty)
        #expect(preview.summaryText.contains("included by override: Hardware class and observations only."))
    }

    /// Writes LAB-008's observed runs through the review. Runs only when the runs are named:
    ///
    ///     LAB_008_RUN_FACTS=<facts.json>[,<facts.json>…] LAB_HOST_EVIDENCE_RECORD=<record> \
    ///     LAB_DEMO_EVIDENCE_DIR=<folder> \
    ///     swift test --package-path Packages/LabDemo --filter PortableObjectsEvidence
    ///
    /// `LAB_HOST_EVIDENCE_RECORD` is the record `PortableObjectsHostEvidenceTests` attached,
    /// exported from its result bundle. Every record must be for LAB-008 at one source revision.
    /// Keep the facts and the export outside the repository, and copy `records/*.json` into
    /// `evidence/LAB-008/`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LAB_008_RUN_FACTS"] != nil))
    func theObservedRunsExportThroughTheReview() throws {
        let environment = ProcessInfo.processInfo.environment
        let folder = URL(filePath: try #require(environment["LAB_DEMO_EVIDENCE_DIR"]), directoryHint: .isDirectory)
        let facts = try #require(environment["LAB_008_RUN_FACTS"]).split(separator: ",").map { try PortableObjectsRunFacts.load(URL(filePath: String($0))) }

        var artifacts: [ExportArtifact] = []
        var overrides: [TierOverride] = []
        var records: [(String, EvidenceRecord)] = []
        for fact in facts {
            let record = try fact.record()
            try #require(record.provenance.sourceRevision != "unknown" && record.provenance.xcodeBuild != "unknown")
            let (artifact, override) = try fact.artifact(record)
            artifacts.append(artifact)
            if let override { overrides.append(override) }
            records.append((fact.exportPath, record))
        }
        if let path = environment["LAB_HOST_EVIDENCE_RECORD"] {
            let host = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: URL(filePath: path)))
            let exportPath = "records/portable-objects-host-round-trip.json"
            artifacts.append(try .record(host, at: exportPath, tier: .publicFixture))
            records.append((exportPath, host))
        }
        let revisions = Set(records.map(\.1.provenance.sourceRevision))
        try #require(revisions.count == 1, "one source revision per export: \(revisions.sorted())")
        try #require(records.allSatisfy { $0.1.subject == PortableObjectsRunFacts.subject })

        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-008 Portable Objects qualification",
            artifacts: artifacts,
            overrides: overrides,
            untested: [
                "A physical iPhone or iPad: the owner has not used Portable Objects on the iPhone.",
                "A person's own drag between Mac windows, to Finder, or into another app.",
            ],
            provenance: records[0].1.provenance
        ))
        try #require(preview.refused.isEmpty)
        let written = try preview.write(into: folder, folderName: "lab-008-portable-objects")
        for (path, record) in records {
            let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: path)))
            #expect(stored == record)
        }
    }
}
