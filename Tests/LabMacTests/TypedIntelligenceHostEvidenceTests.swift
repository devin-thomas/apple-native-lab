import AppKit
import Foundation
import LabDomain
import LabStore
import LabSupport
import SwiftUI
import Testing
import TypedIntelligence
@testable import NativeLab

/// LAB-010-B criterion 1 with its evidence: the model-unavailable path in the sandboxed Mac app,
/// for every gate the probe can find closed. Each case uses a fake device, because this Mac and the
/// iOS simulator both report the model available; the record says so and is fixture-path
/// evidence, never device proof.
///
/// For each closed gate, the real `TypedIntelligenceView` is rendered and operated through the
/// accessibility API: the gate is named in the probe's words, the model button is disabled, and
/// the sample parser's draft is applied by accessibility presses alone. Then the manual editor
/// completes the same flow through the real `IntelligenceWorkbench`. Each case starts from a fresh
/// SQLite store that the host's first run seeds, never the app's real store.
///
/// The test attaches an `EvidenceRecord`, with the toolchain read from this app bundle. To keep it:
///
///     xcodebuild … -scheme LabMac-Core -only-testing:LabMacTests/TypedIntelligenceHostEvidenceTests \
///       -resultBundlePath <bundle> LAB_SOURCE_REVISION=<sha> test
///     xcrun xcresulttool export attachments --path <bundle> --output-path <folder>
@MainActor
@Suite struct TypedIntelligenceHostEvidenceTests {
    static let check = "Typed Local Intelligence's model-unavailable path in the Mac app, with a fake device for each gate the probe can find closed: the gate is named, the model is not offered, and the sample parser and the manual editor both complete the change"

    /// A device whose language model reads as given. Nothing else is measured.
    struct FakeModelDevice: CapabilitySource {
        let reading: LanguageModelReading
        var isSimulator: Bool { false }
        func permissionStatus(_ permission: PermissionKind) -> PermissionStatus { .notReadable }
        func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { nil }
        func speechTranscription() async -> SpeechTranscriptionReading {
            SpeechTranscriptionReading(transcriberAvailable: nil, localeIdentifier: "en_US", asset: .unknown)
        }
        func languageModel() -> LanguageModelReading { reading }
        func worldTracking() -> WorldTrackingReading? { nil }
        func ultraWideband() -> UltraWidebandReading? { nil }
        func entitlement(_ key: String) -> EntitlementReading { .notReadable }
        func declaresPurposeString(_ key: String) -> Bool { false }
    }

    /// Each closed gate, the reading that closes it, and the probe's words for it.
    static let cases: [(name: String, reading: LanguageModelReading, words: String)] = [
        ("device not eligible", LanguageModelReading(availability: .deviceNotEligible, supportsCurrentLocale: nil, localeIdentifier: "en_US"),
         "Hardware: SystemLanguageModel.default.availability reports .deviceNotEligible."),
        ("Apple Intelligence off", LanguageModelReading(availability: .appleIntelligenceNotEnabled, supportsCurrentLocale: nil, localeIdentifier: "en_US"),
         "Service: Apple Intelligence is turned off (SystemLanguageModel.default.availability reports .appleIntelligenceNotEnabled)."),
        ("model not ready", LanguageModelReading(availability: .modelNotReady, supportsCurrentLocale: true, localeIdentifier: "en_US"),
         "On-device asset: The model is not ready (SystemLanguageModel.default.availability reports .modelNotReady)."),
        ("language not supported", LanguageModelReading(availability: .available, supportsCurrentLocale: false, localeIdentifier: "en_US"),
         "Service: Apple Intelligence is on, but the model does not support en_US."),
    ]

    static let kraft = ItemID(rawValue: UUID(uuidString: "6E2CED9D-B946-4188-8417-2E85C6A7268C")!)

    @Test func theUnavailablePathCompletesForEveryClosedGate() async throws {
        let started = Date()
        var checks = 0
        var differences: [String] = []
        func check(_ condition: Bool, _ what: String) {
            checks += 1
            #expect(condition, "\(what)")
            if !condition { differences.append(what) }
        }

        for (name, reading, words) in Self.cases {
            let registry = CapabilityRegistry(platform: .macOS, source: FakeModelDevice(reading: reading))

            // The rendered view, operated through accessibility.
            let library = try await startedLibrary()
            let hosted = HostedView(
                TypedIntelligenceView(fixture: .injectedNote, registry: registry).environment(library),
                size: CGSize(width: 640, height: 2_400)
            )
            defer { hosted.close() }
            let start = try await tree(of: hosted) { $0.buttons.contains { $0.label == "Draft with the Sample Parser" && $0.isEnabled } }
            let text = Self.text(start)
            check(text.contains(words), "\(name): the gate in the probe's words")
            check(text.contains("Neither is a model"), "\(name): the non-model paths are offered")
            check(start.buttons.first(labeled: "Draft with the On-Device Model")?.isEnabled == false, "\(name): the model button is disabled")
            let parser = start.buttons.first(labeled: "Draft with the Sample Parser")
            let manual = start.buttons.first(labeled: "Write It Myself")
            check(parser?.isEnabled == true && parser?.hint.contains("Not a model") == true, "\(name): the parser button says Not a model")
            check(manual?.isEnabled == true && manual?.hint.contains("Not a model") == true, "\(name): the manual editor button says Not a model")

            check(try await hosted.press("Draft with the Sample Parser"), "\(name): the parser button is pressed")
            let review = try await tree(of: hosted) { $0.buttons.contains { $0.label == "Apply Change" && $0.isEnabled } }
            check(Self.text(review).contains("Sample parser (not a model)"), "\(name): the draft is labeled with its source")
            check(library.receipts.allSatisfy { $0.receipt.admitted.operation.kind == .resetDemo }, "\(name): nothing applied before Apply")
            check(try await hosted.press("Apply Change"), "\(name): Apply is pressed")
            for _ in 0..<50 where !library.receipts.contains(where: { $0.receipt.admitted.operation.kind == .updateItem }) {
                try await Task.sleep(for: .milliseconds(40))
            }
            let parsed = library.receipts.first { $0.receipt.admitted.operation.kind == .updateItem }?.receipt
            check(parsed?.admitted.adapter == .appUI && parsed?.conflict == nil, "\(name): the parser's change committed as the app UI")
            check(parsed?.changes.map(\.entity) == [.item(Self.kraft)], "\(name): the parser's change edited the kraft card only")

            // The manual editor, through the workbench the view uses, on its own fresh store.
            let manualLibrary = try await startedLibrary()
            let workbench = IntelligenceWorkbench(fixture: .injectedNote, registry: registry)
            await workbench.start(with: manualLibrary)
            check(!workbench.modelIsOffered && workbench.readiness?.route == .fallback, "\(name): the workbench does not offer the model")
            workbench.draft(with: .onDeviceModel)
            check(workbench.phase == .ready && workbench.source == nil, "\(name): asking for the model starts nothing")
            workbench.draft(with: .manualEditor)
            let kraft = workbench.candidates.first { $0.id == Self.kraft }
            workbench.targetID = kraft?.id
            workbench.targetChanged(from: nil)
            workbench.addedNote = "Corners fray after a week in a drawer."
            workbench.fieldsChanged()
            try await waitUntil { !workbench.isRevising }
            check(workbench.source == .manualEditor && workbench.canApply, "\(name): the manual edit can be applied")
            await workbench.apply()
            let written = workbench.applied?.receipt
            check(written?.admitted.adapter == .appUI && written?.conflict == nil, "\(name): the manual edit committed as the app UI")
            let stored = try await manualLibrary.openedService().item(Self.kraft, as: LabDataService.appUI)
            check(stored.note.value == "Brown and stiff. Takes pencil well.\nCorners fray after a week in a drawer.", "\(name): the manual edit is stored")
        }

        func bundled(_ name: String, _ ext: String) throws -> String {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: ext))
            return ContentDigest.sha256(try Data(contentsOf: url)).hex
        }
        let record = try EvidenceRecord(
            subject: "LAB-010",
            check: Self.check,
            date: started,
            provenance: .current,
            execution: .fixture,
            inputs: IntelligenceFixture.allCases.map { fixture in
                "note:\(fixture.rawValue)@sha256:\((try? bundled(fixture.rawValue, "txt")) ?? "missing")"
            } + ["seed:app-bundle@sha256:\(try bundled("seed", "json"))"]
                + Self.cases.map { "fake-device:\($0.name)" },
            steps: [
                "xcodebuild -scheme LabMac-Core -only-testing:LabMacTests/TypedIntelligenceHostEvidenceTests test",
                "For each fake device: SystemLanguageModel availability .deviceNotEligible; .appleIntelligenceNotEnabled; .modelNotReady; and .available with the locale unsupported",
                "Render TypedIntelligenceView for the note with injected instructions on a fresh SQLite store the host's first run seeds, and read its accessibility tree",
                "Press Draft with the Sample Parser, then Apply Change, through the accessibility press action",
                "On another fresh store, through IntelligenceWorkbench for the same note: ask for the model, then Write It Myself, choose the kraft card, add a line, and apply",
            ],
            outcome: differences.isEmpty
                ? .passed(observed: "All \(checks) checks passed for the \(Self.cases.count) closed gates. Each time the view named the gate in the probe's own words and offered the non-model paths; the model button was disabled; both non-model buttons were enabled with the hint \"Not a model\". The sample parser's draft was labeled \"Sample parser (not a model)\" and was applied by accessibility presses alone as one edit to the kraft card with an app-ui receipt. Asking the workbench for the model started nothing, and the manual editor's edit was applied with an app-ui receipt and stored.")
                : .failed(observed: "\(differences.count) of \(checks) checks failed: " + differences.joined(separator: "; ") + "."),
            limitations: [
                "Fixture path: the model's availability was faked. This Mac and the iOS 27.0 simulator both report the model available, so no real device with the model unavailable was used. This is not device proof of the unavailable path.",
                "Hosted tests in the sandboxed Mac app on the development Mac, on fresh stores. The iPhone screens were not driven.",
                "Accessibility presses stand in for a person. No VoiceOver, Voice Control, or Full Keyboard Access pass was made.",
                "The manual editor was driven through the workbench, not by choosing the sample in the rendered picker.",
            ]
        )
        Attachment.record(try Self.json(record), named: "LAB-010-typed-intelligence-host-unavailable.json")
        #expect(record.result == .passed)
        #expect(record.provenance.xcodeBuild != "unknown" && record.provenance.sdkName.hasPrefix("macosx"))
        #expect(record.supportedState == .implemented)
    }

    // MARK: Helpers

    private func startedLibrary() async throws -> LabLibrary {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TypedIntelligenceHostEvidenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    private func tree(of hosted: HostedView, until condition: ([AccessibilityNode]) -> Bool) async throws -> [AccessibilityNode] {
        var nodes: [AccessibilityNode] = []
        for _ in 0..<20 {
            nodes = try await hosted.tree()
            if condition(nodes) { return nodes }
        }
        Issue.record("the view never reached the expected state\n\(nodes.dump)")
        return nodes
    }

    private func waitUntil(seconds: Int = 4, _ condition: () -> Bool) async throws {
        for _ in 0..<(seconds * 50) {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("condition not met in \(seconds) seconds")
    }

    private static func text(_ nodes: [AccessibilityNode]) -> String {
        nodes.map { "\($0.label) \($0.value) \($0.hint)" }.joined(separator: "\n")
    }

    private static func json(_ record: EvidenceRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
    }
}
