import Foundation
@testable import LabDemo
import LabSupport
import Testing

/// A manual run on a physical device, as the people who ran and observed it report it.
///
/// The facts are read from a file kept outside the repository, because the run's own material,
/// such as a copy of the device's store, stays private. The record is built by `EvidenceRecord`,
/// which refuses serial numbers and device identifiers; the provenance is read from the built
/// app's Info.plist; and the export passes the same rights and privacy review as a replay.
struct DeviceRunFacts: Codable {
    /// The record's file name in the export, without `.json`.
    let name: String
    let subject: String
    let check: String
    /// When the result was observed, such as when the device's store was copied.
    let observedAt: Date
    let platform: String
    let deviceClass: String
    let osVersion: String
    let profileExpiry: Date?
    /// The Info.plist of the build that was installed. The provenance is read from it.
    let buildInfoPlist: String
    let inputs: [String]
    let steps: [String]
    let result: RunResult
    let observed: String
    let limitations: [String]
    /// Why a record derived from a person's device may be exported. The export records it.
    let overrideReason: String

    static func load(_ url: URL) throws -> DeviceRunFacts {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DeviceRunFacts.self, from: Data(contentsOf: url))
    }

    func record() throws -> EvidenceRecord {
        let info = try #require(NSDictionary(contentsOf: URL(filePath: buildInfoPlist)) as? [String: Any], "the build's Info.plist")
        guard let platform = LabPlatform(rawValue: platform) else { throw EvidenceError.unknownPlatform(platform) }
        return try EvidenceRecord(
            subject: subject,
            check: check,
            date: observedAt,
            provenance: BuildProvenance(infoDictionary: info),
            execution: .physical(try PhysicalDevice(
                platform: platform, deviceClass: deviceClass, osVersion: osVersion, profileExpiry: profileExpiry
            )),
            inputs: inputs,
            steps: steps,
            outcome: RunOutcome(result, detail: observed),
            limitations: limitations
        )
    }

    var exportPath: String { "records/\(name).json" }

    /// The record as a reviewed artifact. It comes from a person's device, so it is `user-private`
    /// and needs a recorded override to leave.
    func exportRequest(for record: EvidenceRecord, provenance: BuildProvenance) throws -> EvidenceExportRequest {
        EvidenceExportRequest(
            title: "\(subject) run on a physical device",
            artifacts: [try .record(record, at: exportPath, tier: .userPrivate)],
            overrides: [try TierOverride(path: exportPath, tier: .userPrivate, reason: overrideReason)],
            provenance: provenance
        )
    }
}

@Suite struct DeviceRunEvidence {
    private func facts(deviceClass: String = "iPhone17,1 (iPhone 16 Pro)", plist: URL) -> DeviceRunFacts {
        DeviceRunFacts(
            name: "device-run", subject: "LAB-001", check: "A manual run on a device", observedAt: fixedDate,
            platform: "iOS", deviceClass: deviceClass, osVersion: "27.0 (24A5430a)", profileExpiry: fixedDate,
            buildInfoPlist: plist.path(percentEncoded: false), inputs: ["store-copy@sha256:00"], steps: ["Run it."],
            result: .passed, observed: "It worked.", limitations: ["Manual run."],
            overrideReason: "Aggregates only; no content from the device."
        )
    }

    private func infoPlist(in folder: TemporaryFolder) throws -> URL {
        let info: [String: Any] = [
            "LabSourceRevision": "0000000", "DTSDKName": "iphoneos27.0", "DTXcode": "2700", "DTXcodeBuild": "27A266a",
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "LabBuildProfile": "CoreLocal", "MinimumOSVersion": "26.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        return try folder.write(data, to: "Info.plist")
    }

    /// The generator itself: the provenance comes from the Info.plist, a serial number is refused,
    /// only a passing physical record proves a device, and the export needs its recorded override.
    @Test func aDeviceRunIsValidatedProvesOnlyTheDeviceAndNeedsItsOverride() throws {
        let folder = try TemporaryFolder()
        let plist = try infoPlist(in: folder)

        #expect(throws: EvidenceError.deviceIdentifier(field: "device.deviceClass")) {
            try facts(deviceClass: "iPhone17,1 C02XK0XXJGH5", plist: plist).record()
        }
        let good = facts(plist: plist)
        let record = try good.record()
        #expect(record.path == .physical)
        #expect(record.provenance.toolchainSummary == "Xcode 27.0 (27A266a), iphoneos27.0")
        #expect(record.provenance.buildProfile == "CoreLocal")
        #expect(record.supportedState == .deviceVerified)
        #expect(try DeviceProof(record).device.deviceClass == "iPhone17,1 (iPhone 16 Pro)")

        let exporter = EvidenceExporter(now: { fixedDate })
        let refused = try exporter.preview(EvidenceExportRequest(
            title: "No override", artifacts: [try .record(record, at: good.exportPath, tier: .userPrivate)], provenance: record.provenance
        ))
        #expect(refused.refused.map(\.path) == [good.exportPath])
        let approved = try exporter.preview(try good.exportRequest(for: record, provenance: record.provenance))
        #expect(approved.refused.isEmpty)
        #expect(approved.summaryText.contains("user-private, included by override: Aggregates only; no content from the device."))
    }

    /// Writes an observed run's record through the review. Runs only when both are named:
    ///
    ///     LAB_DEVICE_RUN_FACTS=<facts.json> LAB_DEMO_EVIDENCE_DIR=<folder> \
    ///     swift test --package-path Packages/LabDemo --filter DeviceRunEvidence
    ///
    /// Keep the facts file and the export outside the repository, and copy the exported record
    /// into `evidence/<subject>/`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LAB_DEVICE_RUN_FACTS"] != nil))
    func theObservedRunExportsThroughTheReview() throws {
        let environment = ProcessInfo.processInfo.environment
        let facts = try DeviceRunFacts.load(URL(filePath: try #require(environment["LAB_DEVICE_RUN_FACTS"])))
        let folder = URL(filePath: try #require(environment["LAB_DEMO_EVIDENCE_DIR"]), directoryHint: .isDirectory)
        let record = try facts.record()
        try #require(record.provenance.sourceRevision != "unknown" && record.provenance.xcodeBuild != "unknown")
        let proof = try DeviceProof(record)
        #expect(proof.record == record)

        let preview = try EvidenceExporter().preview(try facts.exportRequest(for: record, provenance: record.provenance))
        try #require(preview.refused.isEmpty)
        let written = try preview.write(into: folder, folderName: "\(facts.name)-export")
        let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: facts.exportPath)))
        #expect(stored == record)
    }
}
