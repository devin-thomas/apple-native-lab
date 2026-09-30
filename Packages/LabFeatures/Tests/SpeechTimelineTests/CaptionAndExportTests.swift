import Foundation
import LabDomain
import Testing
@testable import SpeechTimeline

/// The fallback's caption import, and the two exports: WebVTT text and the timeline document with
/// its audio reference.
@Suite struct CaptionAndExportTests {
    // MARK: Caption import

    @Test func theCaptionFixtureBecomesALabeledTimeline() throws {
        let timeline = try SpeechFixture.captions(at: Repository.fixture(.sampleCaptions))
        #expect(timeline.segments.count == 4)
        #expect(timeline.segments.allSatisfy { $0.source == .captionImport }, "a caption is never shown as recognition")
        #expect(timeline.segments.map(\.range.startMilliseconds) == [0, 1_800, 3_900, 5_600])
        #expect(timeline.segments[2].text == "Water the fern on Thursday.", "the voice tag is removed, so it names no speaker")
        #expect(timeline.provisional == nil)
        // The captions match the script line for line.
        #expect(timeline.segments.map(\.text) == (try SpeechFixture.script(at: Repository.fixture(.sampleScript))))
    }

    @Test func overlappingCaptionsAreRefusedWhole() throws {
        let data = try Data(contentsOf: Repository.speech("speech-captions-overlapping.vtt"))
        #expect(throws: CaptionError.overlappingCues(line: 6)) { try CaptionDocument.parse(data) }
    }

    @Test func malformedCaptionsAreRefusedWhole() throws {
        let data = try Data(contentsOf: Repository.speech("speech-captions-malformed.vtt"))
        #expect(throws: CaptionError.invalidCue(line: 4, .invalidRange)) { try CaptionDocument.parse(data) }
        let second = Data("WEBVTT\n\n0:3.5 --> 00:04.000\nNot a timestamp.\n".utf8)
        #expect(throws: CaptionError.malformedTiming(line: 3)) { try CaptionDocument.parse(second) }
    }

    @Test func otherInvalidCaptionFilesAreRefused() {
        #expect(throws: CaptionError.missingHeader) { try CaptionDocument.parse(Data("1\n00:00.000 --> 00:01.000\nHi\n".utf8)) }
        #expect(throws: CaptionError.notUTF8) { try CaptionDocument.parse(Data([0x57, 0x45, 0xFF, 0xFE])) }
        #expect(throws: CaptionError.noCues) { try CaptionDocument.parse(Data("WEBVTT\n\nNOTE nothing here\n".utf8)) }
        #expect(throws: CaptionError.tooLarge(limit: SpeechTimelineLimits.documentBytes)) {
            try CaptionDocument.parse(Data(repeating: 0x41, count: SpeechTimelineLimits.documentBytes + 1))
        }
        #expect(throws: CaptionError.malformedTiming(line: 3)) {
            try CaptionDocument.parse(Data("WEBVTT\n\n00:61.000 --> 00:62.000\nSeconds past 59.\n".utf8))
        }
        let empty = Data("WEBVTT\n\n00:00.000 --> 00:01.000\n<v Someone></v>\n".utf8)
        #expect(throws: CaptionError.invalidCue(line: 3, .emptyText)) { try CaptionDocument.parse(empty) }
    }

    @Test func cueIdentifiersSettingsAndReferencesAreRead() throws {
        let text = "\u{FEFF}WEBVTT\r\n\r\nintro\r\n00:00.500 --> 00:02.000 align:start line:0\r\nSalt &amp; <i>pepper</i>\r\nsecond line\r\n"
        let cues = try CaptionDocument.parse(Data(text.utf8))
        #expect(cues == [CaptionDocument.Cue(range: range(500, 2_000), text: "Salt & pepper second line", line: 4)])
    }

    // MARK: Exports

    @Test func webVTTExportRoundTripsTimesAndCorrectedText() throws {
        var timeline = observedTimeline()
        try timeline.correct(timeline.segments[0].id, to: "Blue tape marks the <second> shelf & more.")
        timeline.apply(provisional(5_520, 6_000, "The spare"))
        let rendered = CaptionDocument.render(timeline)
        #expect(!rendered.contains("The spare"), "provisional text is never exported")
        let cues = try CaptionDocument.parse(Data(rendered.utf8))
        #expect(cues.map(\.range) == timeline.segments.map(\.range))
        #expect(cues.map(\.text) == timeline.segments.map(\.text))
    }

    @Test func theTimelineExportKeepsAudioReferenceTimesAndSources() throws {
        var timeline = observedTimeline()
        try timeline.correct(timeline.segments[0].id, to: "Blue tape marks the second shelf.")
        timeline.apply(provisional(5_520, 6_000, "The spare"))
        let audio = AudioReference(origin: .synthesizedSample, sha256: String(repeating: "a", count: 64), durationMilliseconds: 5_520, fileType: "caf")
        let data = try TimelineExport(timeline: timeline, audio: audio, language: "en-US").encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("The spare"))
        #expect(text.contains("\"recognized\":\"Blue tape marks the 2nd shelf.\""))
        #expect(text.contains("\"startMs\":1680"))

        let (export, restored) = try TimelineExport.decode(data)
        #expect(export.audio == audio)
        #expect(export.language == "en-US")
        #expect(restored.segments == timeline.segments, "ranges, words, corrections, and sources survive")
        #expect(try TimelineExport(timeline: restored, audio: audio, language: "en-US").encoded() == data, "the encoding is canonical")
    }

    @Test func anExportThisBuildDidNotWriteIsRefused() throws {
        let valid = try TimelineExport(timeline: observedTimeline(), audio: .none, language: "en-US").encoded()
        var object = try #require(try JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["speaker"] = "someone"
        #expect(throws: ExportError.unknownFields) { try TimelineExport.decode(try JSONSerialization.data(withJSONObject: object)) }
        object["speaker"] = nil
        object["schemaVersion"] = 2
        #expect(throws: ExportError.unsupportedVersion) { try TimelineExport.decode(try JSONSerialization.data(withJSONObject: object)) }
        object["schemaVersion"] = 1
        object["format"] = "something-else"
        #expect(throws: ExportError.notATimeline) { try TimelineExport.decode(try JSONSerialization.data(withJSONObject: object)) }
        #expect(throws: ExportError.malformed) { try TimelineExport.decode(Data("[1]".utf8)) }
    }

    @Test func anExportWithOverlappingSegmentsIsRefused() throws {
        let valid = try TimelineExport(timeline: observedTimeline(), audio: .none, language: "en-US").encoded()
        let overlapping = String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "\"startMs\":3960", with: "\"startMs\":3000")
        #expect(throws: ExportError.invalidTimeline(.overlaps(SegmentID(1)))) { try TimelineExport.decode(Data(overlapping.utf8)) }
    }

    @Test func anAudioReferenceNamesContentNotAPath() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "lab-013-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "A Person's Private Name.m4a")
        try Data("not really audio".utf8).write(to: url)
        let reference = try AudioReference.file(at: url, origin: .importedFile, durationMilliseconds: 1_000)
        #expect(reference.sha256 == ContentDigest.sha256(Data("not really audio".utf8)).hex)
        #expect(reference.fileType == "m4a")
        let encoded = String(decoding: try JSONEncoder().encode(reference), as: UTF8.self)
        #expect(!encoded.contains("Private"), "the file's name never enters the export")
        #expect(!encoded.contains(folder.path()))
    }
}
