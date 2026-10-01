import Foundation
@testable import LabDemo
import LabSupport
import Testing

/// LAB-013-B: the committed Speech Timeline records pass the exporter's rights review as they are.
///
/// Every record in `evidence/LAB-013/` is read from the repository and offered to
/// `EvidenceExporter` as `public-fixture`, with no override. The review must approve each one, and
/// each must be for LAB-013, carry no identifier a device or simulator could be traced by, and no
/// path of the machine it ran on. To keep the export the review writes:
///
///     LAB_DEMO_EVIDENCE_DIR=<folder outside the repository> \
///       swift test --package-path Packages/LabDemo --filter SpeechTimelineEvidence
@Suite struct SpeechTimelineEvidence {
    static let folder = Showcase.repositoryRoot.appending(path: "evidence/LAB-013", directoryHint: .isDirectory)

    static func records() throws -> [(name: String, record: EvidenceRecord)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .filter { $0.hasSuffix(".json") }
            .sorted()
        return try names.map { name in
            let data = try Data(contentsOf: folder.appending(path: name))
            return (name, try JSONDecoder().decode(EvidenceRecord.self, from: data))
        }
    }

    @Test func theCommittedRecordsPassTheReviewAsPublicFixtures() throws {
        let records = try Self.records()
        try #require(records.count >= 2)
        var artifacts: [ExportArtifact] = []
        for (name, record) in records {
            #expect(record.subject == "LAB-013", "\(name)")
            let text = try String(contentsOf: Self.folder.appending(path: name), encoding: .utf8)
            let words = text.components(separatedBy: CharacterSet(charactersIn: " \t\n()[]{},;:/=\"'.@"))
            #expect(!words.contains { UUID(uuidString: $0) != nil }, "\(name) names no device or simulator identifier")
            #expect(!text.contains("/Users/") && !text.contains("/private/"), "\(name) names no path on the machine it ran on")
            // A record on the physical path is the development Mac, never an iPhone or iPad.
            if record.path == .physical {
                #expect(text.contains(#""platform" : "macOS""#), "\(name): physical evidence here is the Mac only")
            }
            artifacts.append(try .record(record, at: "records/\(name)", tier: .publicFixture))
        }
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-013 Speech Timeline qualification",
            artifacts: artifacts,
            untested: [
                "A physical iPhone or iPad: no device took part.",
                "A microphone: live recording is blocked on the owner's decision (purpose string and the Mac audio-input entitlement).",
                "A model download, real voices, and languages other than en-US.",
            ],
            provenance: records[0].record.provenance
        ))
        #expect(preview.refused.isEmpty, "\(preview.summaryText)")
        #expect(!preview.summaryText.contains("included by override"))
        if let parent = ProcessInfo.processInfo.environment["LAB_DEMO_EVIDENCE_DIR"] {
            let written = try preview.write(into: URL(filePath: parent, directoryHint: .isDirectory), folderName: "lab-013-speech-timeline")
            for (name, record) in records {
                let stored = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: "records/\(name)")))
                #expect(stored == record)
            }
        }
    }
}
