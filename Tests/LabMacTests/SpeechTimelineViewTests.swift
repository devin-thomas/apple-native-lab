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
    /// LAB-013-B: while a transcription runs, the guess reads as one element that says it is
    /// provisional, apart from the segments; once it is finalized, it reads as a segment with its
    /// times and source, and the guess is gone. A route change's pause is in the tree as text.
    @Test func provisionalTextReadsApartFromTheSegmentsAndAPauseIsStated() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SpeechTimelineViewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = try await SpeechHostLab.startedLibrary(in: folder)
        let capture = ScriptedRuns([[.update(speechFinal(0, 1_200, "Spoken first.")), CaptureStop.routeChange(reason: 2)!]])
        let model = SpeechHostLab.model(in: folder, recognizer: PacedRecognizer(pause: .milliseconds(1_500)),
                                        capture: capture, stager: SpeechHostLab.microphoneAllowed())
        let hosted = HostedView(
            Form { SpeechTimelineSections(model: model) }
                .formStyle(.grouped)
                .task { await model.refreshSupport() }
                .environment(library),
            size: CGSize(width: 640, height: 2_400)
        )
        defer { hosted.close() }
        let audio = folder.appending(path: "chosen.caf")
        try Data("not decoded".utf8).write(to: audio)
        await model.refreshSupport()
        model.importAudio(from: audio)

        let guessing = try await tree(of: hosted) { $0.labels.contains { $0.hasPrefix("Provisional, still changing: Blue tape") } }
        #expect(!guessing.labels.contains { $0.hasPrefix("From ") }, "no segment yet, only the guess:\n\(guessing.dump)")

        let finalized = try await tree(of: hosted) { $0.labels.contains("From 1 second to 3 seconds, Blue tape marks the 2nd shelf., On-device transcription") }
        #expect(!finalized.labels.contains { $0.hasPrefix("Provisional") && $0.contains("Blue tape") }, "the finalized words are not also read as provisional")
        model.cancel()
        try await SpeechHostLab.waitUntilIdle(model)

        await model.record()
        try await SpeechHostLab.waitUntilIdle(model)
        let paused = try await tree(of: hosted) { Self.text($0).contains("Recording paused because the audio route changed") }
        #expect(Self.text(paused).contains("the audio device in use was disconnected. 1 segment kept."))
        #expect(paused.labels.contains { $0.hasPrefix("From 0 seconds to 1 second, Spoken first.") })
    }
}
