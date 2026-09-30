import AppKit
import Foundation
import LabDomain
import LabSupport
import SwiftUI
import Testing
import TypedIntelligence
@testable import NativeLab

/// LAB-010 in the real views, rendered inside the running Mac app and operated through the
/// accessibility API. The model gate is closed by a fake device, so this is the unavailable path
/// as a person meets it: the gate is named, the non-model paths are labeled, and the fallback
/// completes through accessibility presses alone.
///
/// Not a VoiceOver or Voice Control pass; see docs/ACCESSIBILITY_REVIEW.md for what that means.
@MainActor
@Suite struct TypedIntelligenceViewTests {
    /// A device where Apple Intelligence is turned off.
    struct AppleIntelligenceOff: CapabilitySource {
        var isSimulator: Bool { false }
        func permissionStatus(_ permission: PermissionKind) -> PermissionStatus { .notReadable }
        func hasCaptureDevice(_ kind: CaptureDeviceKind) -> Bool? { nil }
        func speechTranscription() async -> SpeechTranscriptionReading {
            SpeechTranscriptionReading(transcriberAvailable: nil, localeIdentifier: "en_US", asset: .unknown)
        }
        func languageModel() -> LanguageModelReading {
            LanguageModelReading(availability: .appleIntelligenceNotEnabled, supportsCurrentLocale: nil, localeIdentifier: "en_US")
        }
        func worldTracking() -> WorldTrackingReading? { nil }
        func ultraWideband() -> UltraWidebandReading? { nil }
        func entitlement(_ key: String) -> EntitlementReading { .notReadable }
        func declaresPurposeString(_ key: String) -> Bool { false }
    }

    private func startedLibrary() async throws -> LabLibrary {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TypedIntelligenceViewTests-\(UUID().uuidString)")
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

    private static func text(_ nodes: [AccessibilityNode]) -> String {
        nodes.map { "\($0.label) \($0.value) \($0.hint)" }.joined(separator: "\n")
    }

    @Test func theUnavailablePathNamesTheGateAndCompletesThroughAccessibility() async throws {
        let library = try await startedLibrary()
        let registry = CapabilityRegistry(platform: .macOS, source: AppleIntelligenceOff())
        let hosted = HostedView(
            TypedIntelligenceView(fixture: .injectedNote, registry: registry).environment(library),
            size: CGSize(width: 640, height: 2_400)
        )
        defer { hosted.close() }

        let start = try await tree(of: hosted) { $0.buttons.contains { $0.label == "Draft with the Sample Parser" && $0.isEnabled } }
        // The probe's words name the gate that closed the model route.
        #expect(Self.text(start).contains("Apple Intelligence is turned off"), "\(start.dump)")
        #expect(Self.text(start).contains("Neither is a model"))
        // The model button is present and disabled; both non-model paths are enabled and say so.
        let model = try #require(start.buttons.first(labeled: "Draft with the On-Device Model"))
        #expect(!model.isEnabled)
        let parser = try #require(start.buttons.first(labeled: "Draft with the Sample Parser"))
        let manual = try #require(start.buttons.first(labeled: "Write It Myself"))
        #expect(parser.isEnabled && parser.hint.contains("Not a model"))
        #expect(manual.isEnabled && manual.hint.contains("Not a model"))

        // The fallback, pressed through accessibility: draft, review, apply.
        #expect(try await hosted.press("Draft with the Sample Parser"))
        let review = try await tree(of: hosted) { $0.buttons.contains { $0.label == "Apply Change" && $0.isEnabled } }
        #expect(Self.text(review).contains("Sample parser (not a model)"), "the draft is labeled with its source\n\(review.dump)")
        #expect(library.receipts.allSatisfy { $0.receipt.admitted.operation.kind == .resetDemo }, "nothing applied before Apply")
        #expect(try await hosted.press("Apply Change"))
        for _ in 0..<50 where !library.receipts.contains(where: { $0.receipt.admitted.operation.kind == .updateItem }) {
            try await Task.sleep(for: .milliseconds(40))
        }
        let applied = try #require(library.receipts.first { $0.receipt.admitted.operation.kind == .updateItem })
        #expect(applied.receipt.admitted.adapter == .appUI)
        #expect(applied.receipt.conflict == nil)
    }
}
