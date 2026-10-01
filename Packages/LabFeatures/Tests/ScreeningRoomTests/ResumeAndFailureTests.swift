import Foundation
import LabDomain
@testable import ScreeningRoom
import Testing

/// LAB-031: the experiment resumes at the same position with the same captions, a damaged saved
/// resume point is ignored without harm, Reset removes only the experiment's file, and an
/// unplayable clip becomes a real error.
@Suite struct ResumeAndFailureTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("screening-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func aResumePointRoundTripsThroughItsFile() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileResumePointStore(folder: folder)
        #expect(store.load() == .none)

        var session = try ScreeningSession.withTestCard()
        try session.run(.seek(to: 7.25))
        try session.run(.selectCaption(.track("es")))
        try session.run(.present(.theater))
        let point = try #require(session.resumePoint)
        try store.save(point)
        #expect(store.load() == .found(point))

        // A new launch: a fresh session resumes paused, in the page, at the same place and captions.
        var next = ScreeningSession()
        #expect(next.resume(from: point) == true)
        #expect(next.state.clip == ScreeningClips.testCard.id)
        #expect(next.state.position == 7.25)
        #expect(next.state.caption == .track("es"))
        #expect(next.state.surface == .inline)
        #expect(!next.state.isPlaying)
        #expect(next.resume(from: point) == false, "resuming the same point again changes nothing")
    }

    @Test func resetRemovesOnlyTheResumePoint() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let neighbor = folder.appendingPathComponent("someone-elses.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: neighbor)
        let store = FileResumePointStore(folder: folder)
        try store.save(ResumePoint(clip: ScreeningClips.testCard.id, position: 2, caption: .off))

        try store.remove()
        try store.remove()
        #expect(store.load() == .none)
        #expect(FileManager.default.fileExists(atPath: neighbor.path), "reset touched a file it does not own")
    }

    @Test func aDamagedOrForeignResumePointIsIgnored() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = FileResumePointStore(folder: folder)
        let cases: [(String, Data)] = [
            ("not JSON", Data("resume at 0:04".utf8)),
            ("wrong version", Data(#"{"schemaVersion":9,"clip":"screening-test-card","position":1,"caption":{"off":{}}}"#.utf8)),
            ("negative position", Data(#"{"schemaVersion":1,"clip":"screening-test-card","position":-1,"caption":{"off":{}}}"#.utf8)),
            ("unknown clip", Data(#"{"schemaVersion":1,"clip":"elsewhere","position":1,"caption":{"off":{}}}"#.utf8)),
            ("failing clip", Data(#"{"schemaVersion":1,"clip":"screening-unknown-codec","position":1,"caption":{"off":{}}}"#.utf8)),
            ("oversized", Data(repeating: 0x20, count: FileResumePointStore.maximumBytes + 1)),
        ]
        for (label, bytes) in cases {
            try bytes.write(to: store.file)
            guard case .discarded = store.load() else {
                Issue.record("\(label) was accepted")
                continue
            }
        }
        // The valid form, for contrast.
        try store.save(ResumePoint(clip: ScreeningClips.testCard.id, position: 1, caption: .track("en-sdh")))
        #expect(store.load() == .found(ResumePoint(clip: ScreeningClips.testCard.id, position: 1, caption: .track("en-sdh"))))
    }

    @Test func aResumePointForACaptionTheClipLacksTurnsCaptionsOff() {
        var session = ScreeningSession()
        #expect(session.resume(from: ResumePoint(clip: ScreeningClips.testCard.id, position: 99, caption: .track("fr"))) == true)
        #expect(session.state.caption == .off)
        #expect(session.state.position == 10)
        #expect(session.resume(from: ResumePoint(clip: ScreeningClips.truncated.id, position: 0, caption: .off)) == false)
    }

    @Test func errorsMapToTheFailureAPersonSees() {
        let domain = PlaybackFailure.avFoundationErrorDomain
        #expect(PlaybackFailure.classify(domain: domain, code: -11831, whileOpening: true) == .protectedContent)
        #expect(PlaybackFailure.classify(domain: domain, code: -11833, whileOpening: false) == .unsupportedCodec(codes: []))
        #expect(PlaybackFailure.classify(domain: domain, code: -11864, whileOpening: true) == .unsupportedCodec(codes: []))
        #expect(PlaybackFailure.classify(domain: domain, code: -11829, whileOpening: true) == .unreadable(code: -11829))
        #expect(PlaybackFailure.classify(domain: domain, code: -11828, whileOpening: false) == .unreadable(code: -11828))
        #expect(PlaybackFailure.classify(domain: "NSOSStatusErrorDomain", code: -12848, whileOpening: true) == .unreadable(code: -12848))
        #expect(PlaybackFailure.classify(domain: domain, code: -11800, whileOpening: false) == .playbackFailed(domain: domain, code: -11800))
    }

    @Test func everyFailureSaysWhatHappenedAndWhatStillWorks() {
        let failures: [PlaybackFailure] = [
            .missingResource(name: "x.mov"), .unreadable(code: -11829), .unsupportedCodec(codes: ["lab0"]),
            .protectedContent, .playbackFailed(domain: "d", code: 1),
        ]
        for failure in failures {
            #expect(!failure.title.isEmpty)
            #expect(failure.message.hasSuffix("."))
            #expect(failure.recovery.contains("Test Card"))
        }
        #expect(PlaybackFailure.protectedContent.message.contains("never removes or works around protection"))
    }

    @Test func theFixturesDeclareWhatTheyAreFor() {
        #expect(ScreeningClips.all.map(\.fileName) == ["screening-test-card.mov", "screening-unknown-codec.mov", "screening-truncated.mov"])
        #expect(ScreeningClips.testCard.expectation == .plays)
        #expect(ScreeningClips.unknownCodec.expectation == .fails(.unsupportedCodec(codes: ["lab0"])))
        #expect(ScreeningClips.truncated.expectation == .fails(.unreadable(code: -11829)))
        #expect(Set(ScreeningClips.all.map(\.id)).count == ScreeningClips.all.count)
    }
}
