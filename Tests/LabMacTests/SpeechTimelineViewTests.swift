import AppKit
import Foundation
import LabDomain
import LabSupport
import SpeechTimeline
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-013 in the real views, rendered inside the running Mac app and operated through the
/// accessibility API, with the transcriber closed by a fake. This is the unavailable path as a
/// person meets it: the reason is stated, the on-device buttons are disabled, and the caption
/// fallback fills the timeline with labeled segments through accessibility presses alone.
///
/// Not a VoiceOver or Voice Control pass; see docs/ACCESSIBILITY_REVIEW.md for what that means.
@MainActor
@Suite struct SpeechTimelineViewTests {
    private struct NoTranscriber: SpeechFileRecognizing {
        func languages() async -> LanguageSupport { LanguageSupport(transcriberAvailable: false, supported: [], installed: []) }
        func transcribe(file: URL, language: String, onUpdate: @escaping @Sendable (RecognizerUpdate) async -> Void) async throws(RecognitionFailure) -> Int {
            throw .transcriberUnavailable
        }
    }

    private struct NoInstaller: SpeechModelInstalling {
        func install(language: String, progress: @escaping @Sendable (Double) -> Void) async throws(RecognitionFailure) {
            throw .transcriberUnavailable
        }
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

    @Test func theUnavailablePathIsStatedAndTheCaptionFallbackCompletesThroughAccessibility() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SpeechTimelineViewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        let model = SpeechTimelineModel(
            recognizer: NoTranscriber(), installer: NoInstaller(), capture: CountingCapture(),
            locateFolder: { folder }
        )
        // The Mac window's two columns, stacked: the sources, then the timeline.
        let hosted = HostedView(
            Form {
                SpeechSourcesSections(model: model)
                SpeechTimelineSections(model: model)
            }
            .formStyle(.grouped)
            .task { await model.refreshSupport() }
            .environment(library),
            size: CGSize(width: 640, height: 3_000)
        )
        defer { hosted.close() }

        let start = try await tree(of: hosted) { Self.text($0).contains("On-device transcription is not available on this device.") }
        let sample = try #require(start.buttons.first(labeled: "Speak and Transcribe the Sample"))
        #expect(!sample.isEnabled)
        #expect(start.buttons.first(labeled: "Record")?.isEnabled == false, "Record is closed with the transcriber")
        #expect(start.buttons.first(labeled: "Import Audio…")?.isEnabled == false)
        let captions = try #require(start.buttons.first(labeled: "Import Sample Captions"))
        #expect(captions.isEnabled)

        #expect(try await hosted.press("Import Sample Captions"))
        let filled = try await tree(of: hosted) { Self.text($0).contains("Imported caption (not recognition)") }
        let text = Self.text(filled)
        #expect(text.contains("From 0 seconds to 1 second, The kettle clicked off at seven., Imported caption (not recognition)"), "\(filled.dump)")
        #expect(text.contains("Imported captions (not recognition)"), "the source is named above the timeline")
        #expect(model.timeline.segments.count == 4)
    }
}
