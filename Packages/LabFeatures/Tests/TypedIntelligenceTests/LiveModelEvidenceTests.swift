#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import CryptoKit
import Foundation
import FoundationModels
import LabDomain
import LabSupport
import Synchronization
import Testing
@testable import TypedIntelligence

/// LAB-010-B's model evidence: the real on-device model drafts each fixture note twice through
/// `TypedIntelligenceFlow`, and the run becomes an `EvidenceRecord`. Opt-in, because it needs an
/// eligible device with Apple Intelligence on and the model ready:
///
///     LAB_LIVE_MODEL=1 LAB_LIVE_MODEL_EVIDENCE_DIR=<folder outside the repository> \
///     LAB_SOURCE_REVISION=<sha> LAB_SDK_NAME=macosx27.0 LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a \
///     swift test --package-path Packages/LabFeatures --filter LiveModelEvidenceTests
///
/// In a simulator, pass the same variables to `xcodebuild test` with a `TEST_RUNNER_` prefix.
///
/// The execution path comes from `DeviceSnapshot.current`, as for any live run: physical on a Mac
/// or device, simulator in a simulator. The record states only what this process observed. It
/// never holds text the model wrote: a model-written title or addition is described by its length
/// and a SHA-256 prefix, and a quote from the note by its offset and length in the fixture. Nothing
/// here prints the model's text either, so no expectation compares it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LAB_LIVE_MODEL"] == "1", "set LAB_LIVE_MODEL=1 to run the on-device model"))
struct LiveModelEvidenceTests {
    static let attempts = 2

    @Test func aLiveModelRunBecomesAnEvidenceRecord() async throws {
        let environment = ProcessInfo.processInfo.environment
        let started = Date()
        let snapshot = DeviceSnapshot.current
        let execution = try Execution(observing: snapshot)

        // The model's own state: read directly before any draft, then by the extractor's own
        // check, which every draft repeats, and directly again after the last draft.
        let model = SystemLanguageModel.default
        let firstRead = Self.describe(model.availability)
        let supportsLocale = model.supportsLocale()
        let locale = Locale.current.identifier
        let variant = OnDeviceModelExtractor.variantName
        let contextSize = model.contextSize
        let unavailable = OnDeviceModelExtractor.unavailability()

        var problems: [String] = []
        var paragraphs: [String] = []
        if unavailable == nil {
            for fixture in IntelligenceFixture.allCases {
                let note = try Repository.note(fixture)
                var digests: [String] = []
                var sentences: [String] = []
                for attempt in 1...Self.attempts {
                    let observed = try await Self.draft(note, attempt: attempt)
                    problems += observed.problems.map { "\(fixture.title), attempt \(attempt): \($0)" }
                    if let digest = observed.digest { digests.append(digest) }
                    sentences.append("Attempt \(attempt): \(observed.summary)")
                }
                let ending = digests.count < Self.attempts
                    ? " \(digests.count) of \(Self.attempts) attempts produced a draft."
                    : Set(digests).count == 1 ? " Every attempt produced the same draft (same digest)." : " The attempts produced different drafts."
                paragraphs.append("\(fixture.title) (\(fixture.fileName)). " + sentences.joined(separator: " ") + ending)
            }
        }
        let lastRead = Self.describe(model.availability)

        let machine = execution.path == .physical
            ? "\(execution.summary), \(snapshot.memoryGigabytes) GB memory."
            : "\(execution.summary), on the development Mac."
        let header = "SystemLanguageModel.default.availability read \(firstRead) before any draft; the extractor's own check then found "
            + (unavailable.map { "it unavailable (\($0.rawValue))" } ?? "it available")
            + "; after the last draft it read \(lastRead). supportsLocale() \(supportsLocale) for \(locale); "
            + "variant \(variant.map { "“\($0)”" } ?? "not reported by this SDK"); contextSize \(contextSize) tokens. \(machine) "
        let timebase = "Intervals are single readings of swift-continuous-clock (Swift ContinuousClock in the test process: monotonic, "
            + "counts time asleep), in milliseconds. A draft interval covers the whole flow.draft call; generation covers the "
            + "extractor, which includes the model's tool calls; the rest is validation and the service's check."
        let body = header + paragraphs.joined(separator: " ") + " " + timebase
        let outcome: RunOutcome = if let unavailable {
            .blocked(reason: header + "No draft was attempted, because the model was unavailable here (\(unavailable.rawValue)).")
        } else if problems.isEmpty {
            .passed(observed: body)
        } else {
            .failed(observed: "\(problems.count) of \(IntelligenceFixture.allCases.count * Self.attempts) attempts did not meet the check: "
                + problems.joined(separator: "; ") + ". " + body)
        }

        let seedBytes = try Data(contentsOf: Repository.root.appending(path: "Fixtures/demo/seed.json"))
        let inputs = try IntelligenceFixture.allCases.map { fixture in
            "note:\(fixture.rawValue)@sha256:\(Self.hex(SHA256.hash(data: try Data(contentsOf: Repository.fixtureURL(fixture)))))"
        } + ["seed:demo@sha256:\(Self.hex(SHA256.hash(data: seedBytes)))"]

        let pathLimitation: String = switch execution.path {
        case .physical where snapshot.platform == "macOS":
            "Physical path, because the system model ran on this Mac's own hardware (DeviceSnapshot). The flow was driven by a test process, not by a person in the installed app. The experiment is not promoted on this record: its declared promotion run is the owner's iPhone, and any promotion needs the integrator's review of the run."
        case .physical:
            "Physical path, because the system model ran on this device's own hardware (DeviceSnapshot). The flow was driven by a test process, not by a person in the installed app, and any promotion needs the integrator's review of the run."
        case .simulator:
            "Simulator path: the simulator runs the host Mac's system model. It is not device evidence, and it shows nothing about a real iPhone's availability or output."
        default:
            "Neither a physical device nor a simulator was detected."
        }
        let record = try EvidenceRecord(
            subject: "LAB-010",
            check: "Typed Local Intelligence's on-device model path: the live system model drafted each fixture note \(Self.attempts) times through TypedIntelligenceFlow, validated and checked as the proposer, with no approval and no writes",
            date: started,
            provenance: BuildProvenance(
                sourceRevision: environment["LAB_SOURCE_REVISION"] ?? "unknown",
                sdkName: environment["LAB_SDK_NAME"] ?? "unknown",
                xcodeVersion: environment["LAB_XCODE_VERSION"] ?? "unknown",
                xcodeBuild: environment["LAB_XCODE_BUILD"] ?? "unknown"
            ),
            execution: execution,
            inputs: inputs,
            steps: [
                "LAB_LIVE_MODEL=1 swift test --package-path Packages/LabFeatures --filter LiveModelEvidenceTests (in a simulator: xcodebuild test with TEST_RUNNER_LAB_LIVE_MODEL=1 and -only-testing:TypedIntelligenceTests/LiveModelEvidenceTests)",
                "Read SystemLanguageModel.default: availability, supportsLocale(), variant, contextSize",
                "For each fixture note, \(Self.attempts) times: a fresh in-memory store seeded with the demo seed, then TypedIntelligenceFlow.draft with OnDeviceModelExtractor over the 12 demo samples, as the app offers them, within the app's \(TypedIntelligence.defaultTimeLimit.components.seconds)-second limit",
                "OnDeviceModelExtractor: guided generation with the sample title narrowed to the offered titles, greedy sampling, maximumResponseTokens 512, and the one read-only findSamples tool",
                "Count the proposer's reads (each findSamples call is one), the store's writes, and every authorized access; compare the stored items before and after",
            ],
            outcome: outcome,
            limitations: [
                pathLimitation,
                "The model's choice of sample varies by environment. In LAB-010-A the macOS test process and the iOS simulator on the same Mac chose different swatches for the ambiguous note, and each repeated its own choice. The choices here are this environment's, not a property of the experiment, and say nothing about other devices, OS builds, or model versions.",
                "No factual-accuracy claim. Guided generation kept the sample to an offered title; it cannot make the choice or the added text right. The ambiguous note has no single right answer, and every draft goes to a person for review.",
                "Timings are single intervals, not a benchmark, and no performance claim is made. The first draft in the process may include loading the model; cold and warm start are not separated. The model's asset state is known only from the availability reads in the detail.",
                "No approval, commit, or view ran: this record covers drafting, validation, and the service's check. Applying a reviewed draft is covered by the fixture tests and the showcase replay.",
                "No note text beyond the committed fixture notes is recorded. Model-written titles and additions appear only as a length and a SHA-256 prefix, and quotes as their offset and length in the fixture.",
                "A physical iPhone or iPad was not used.",
            ]
        )

        if let unavailable { Issue.record("the model is unavailable here (\(unavailable.rawValue)); the record is blocked") }
        #expect(problems.isEmpty, "\(problems.joined(separator: "; "))")
        #expect(record.path == execution.path)
        if let folder = environment["LAB_LIVE_MODEL_EVIDENCE_DIR"] {
            for fact in ["LAB_SOURCE_REVISION", "LAB_SDK_NAME", "LAB_XCODE_VERSION", "LAB_XCODE_BUILD"] {
                try #require(environment[fact].map { !$0.isEmpty } == true, "a kept record names \(fact)")
            }
            let name = environment["LAB_LIVE_MODEL_EVIDENCE_NAME"]
                ?? (execution.path == .simulator ? "typed-intelligence-model-ios-simulator" : "typed-intelligence-model-mac")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
            let data = try encoder.encode(record) + Data("\n".utf8)
            let url = URL(filePath: folder, directoryHint: .isDirectory).appending(path: "\(name).json")
            try data.write(to: url)
            #expect(try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: url)) == record)
        }
    }

    // MARK: One draft

    struct Observation {
        var summary: String
        var digest: String?
        var problems: [String]
    }

    /// Drafts `note` once on a fresh seeded store and describes the result without its text.
    static func draft(_ note: SourceNote, attempt: Int) async throws -> Observation {
        let lab = try await Lab.seeded()
        let backend = ReadCountingBackend(lab.backend)
        let flow = TypedIntelligenceFlow(backend: backend)
        let candidates = try await flow.candidates()
        let offered = Set(candidates.map(\.title))
        let before = await lab.items()
        lab.recorder.clear()
        let readsBefore = backend.reads
        let extractor = TimedExtractor()
        let clock = ContinuousClock()
        let start = clock.now
        let result = await flow.draft(note, with: extractor, candidates: candidates)
        let total = clock.now - start
        let lookups = backend.reads - readsBefore

        var problems: [String] = []
        let accesses = lab.recorder.accesses
        if !accesses.allSatisfy({ $0.adapter == .modelTool }) { problems.append("an access was not the model tool's") }
        if accesses.contains(where: { if case .commit = $0.access { true } else { false } }) { problems.append("a commit was attempted") }
        if lab.store.appliedCount != 0 { problems.append("\(lab.store.appliedCount) store writes") }
        if await lab.items() != before { problems.append("the stored items changed") }

        let reviewable: ReviewableProposal
        switch result {
        case .failure(.timedOut(let limit)):
            let seconds = limit.components.seconds
            problems.append("no draft within the app's \(seconds)-second limit")
            return Observation(
                summary: "no draft: the flow stopped it at the app's \(seconds)-second limit after \(milliseconds(total)) ms; nothing was proposed; \(lab.store.appliedCount) store writes.",
                digest: nil, problems: problems
            )
        case .failure(let failure):
            problems.append("no draft (\(failure))")
            return Observation(summary: "no draft (\(failure)) after \(milliseconds(total)) ms; \(lab.store.appliedCount) store writes.", digest: nil, problems: problems)
        case .success(let value):
            reviewable = value
            if total >= flow.timeLimit { problems.append("the draft took longer than the time limit") }
        }
        let proposal = reviewable.proposal
        guard let target = proposal.target, offered.contains(target.title) else {
            problems.append("the sample is not one of the offered titles")
            return Observation(summary: "no offered sample.", digest: extractor.digest, problems: problems)
        }
        var dropped = 0
        for issue in proposal.issues { if case .evidenceNotInNote(let count) = issue { dropped += count } }
        for span in proposal.evidence {
            let start = note.text.index(note.text.startIndex, offsetBy: span.offset)
            if !note.text[start...].hasPrefix(span.quote) { problems.append("a kept quote is not at its offset") }
        }

        let others = proposal.otherPossibleSamples.map(\.title)
        let generation = extractor.duration ?? .zero
        var parts = [
            "sample \(target.title)",
            "other possible samples \(others.isEmpty ? "none" : others.joined(separator: ", "))",
            describeTitle(proposal, note: note),
            describeAddition(proposal.addedNote, note: note),
            "evidence kept \(proposal.evidence.count) of \(proposal.evidence.count + dropped)"
                + (proposal.evidence.isEmpty ? "" : " (" + proposal.evidence.map { "offset \($0.offset), \($0.length) characters" }.joined(separator: "; ") + ")"),
        ]
        let blocking = reviewable.issues.filter(\.isBlocking).map(issueName)
        let advisories = reviewable.issues.filter { !$0.isBlocking }.map(issueName)
        parts.append("blocking issues \(blocking.isEmpty ? "none" : blocking.joined(separator: ", "))")
        parts.append("advisories \(advisories.isEmpty ? "none" : advisories.joined(separator: ", "))")
        parts.append(reviewable.isApprovable ? "approvable" : "not approvable")
        parts.append("\(lookups) findSamples \(lookups == 1 ? "call" : "calls")")
        parts.append("draft \(milliseconds(total)) ms (generation \(milliseconds(generation)) ms, validation and check \(milliseconds(total - generation)) ms)")
        parts.append("\(lab.store.appliedCount) store writes")
        parts.append("draft digest sha256:\(extractor.digest ?? "none")")
        return Observation(summary: parts.joined(separator: "; ") + ".", digest: extractor.digest, problems: problems)
    }

    static func describeTitle(_ proposal: ExtractionProposal, note: SourceNote) -> String {
        guard let diff = proposal.diff, diff.changesTitle else { return "title kept" }
        if let range = note.text.range(of: diff.titleAfter, options: [.caseInsensitive]) {
            return "title changed to a phrase of the note (offset \(note.text.distance(from: note.text.startIndex, to: range.lowerBound)), \(diff.titleAfter.count) characters)"
        }
        return "title changed to \(diff.titleAfter.count) model-written characters (sha256:\(prefix(diff.titleAfter)))"
    }

    static func describeAddition(_ added: String, note: SourceNote) -> String {
        guard !added.isEmpty else { return "adds nothing to the note" }
        if let range = note.text.range(of: added) {
            return "adds \(added.count) characters copied from the note (offset \(note.text.distance(from: note.text.startIndex, to: range.lowerBound)))"
        }
        return "adds \(added.count) model-written characters (sha256:\(prefix(added)))"
    }

    /// The case name of an issue, with sample titles where the issue names them.
    static func issueName(_ issue: ValidationIssue) -> String {
        switch issue {
        case .otherPossibleSamples(let titles): "otherPossibleSamples(\(titles.joined(separator: ", ")))"
        case .noteNamesOtherSamples(let titles): "noteNamesOtherSamples(\(titles.joined(separator: ", ")))"
        case .evidenceNotInNote(let count): "evidenceNotInNote(\(count))"
        case .sampleNameMatchesSeveral(let count): "sampleNameMatchesSeveral(\(count))"
        case .titleTooLong: "titleTooLong"
        case .addedNoteTooLong: "addedNoteTooLong"
        case .noteWouldBeTooLong: "noteWouldBeTooLong"
        case .sampleChanged: "sampleChanged"
        case .refusedByService: "refusedByService"
        case .noSampleChosen: "noSampleChosen"
        case .unknownSample: "unknownSample"
        case .sampleArchived: "sampleArchived"
        case .titleEmpty: "titleEmpty"
        case .titleHasControlCharacters: "titleHasControlCharacters"
        case .addedNoteHasControlCharacters: "addedNoteHasControlCharacters"
        case .noChange: "noChange"
        case .noEvidence: "noEvidence"
        case .addedNoteAlreadyPresent: "addedNoteAlreadyPresent"
        }
    }

    /// An availability value as the SDK spells it, such as `.unavailable(.modelNotReady)`.
    static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available: ".available"
        case .unavailable(let reason): ".unavailable(.\(reason))"
        }
    }

    static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The first 16 hex digits of the text's SHA-256: enough to compare, and no text.
    static func prefix(_ text: String) -> String {
        String(hex(SHA256.hash(data: Data(text.utf8))).prefix(16))
    }
}

/// The on-device model extractor, timed, with a digest of its raw draft. The draft's text stays
/// in memory: only its digest leaves this type.
private final class TimedExtractor: NoteExtractor, Sendable {
    let source = ProposalSource.onDeviceModel
    private let state = Mutex<(duration: Duration?, digest: String?)>((nil, nil))

    var duration: Duration? { state.withLock { $0.duration } }
    var digest: String? { state.withLock { $0.digest } }

    func extract(_ request: ExtractionRequest) async throws(ExtractionFailure) -> ExtractionDraft {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let draft = try await OnDeviceModelExtractor().extract(request)
            let elapsed = clock.now - start
            let fields: [String: Any] = [
                "sampleTitle": draft.sampleTitle, "otherPossibleSamples": draft.otherPossibleSamples,
                "newTitle": draft.newTitle, "addedNote": draft.addedNote, "evidence": draft.evidence,
            ]
            let canonical = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
            let digest = String(LiveModelEvidenceTests.hex(SHA256.hash(data: canonical)).prefix(16))
            state.withLock { $0 = (elapsed, digest) }
            return draft
        } catch {
            let elapsed = clock.now - start
            state.withLock { $0 = (elapsed, nil) }
            throw error
        }
    }
}

/// Counts the proposer's reads through the backend. After the samples are listed, each read is
/// one `findSamples` call.
private final class ReadCountingBackend: TypedIntelligenceBackend {
    private let base: ServiceIntelligenceBackend
    private let count = Mutex(0)

    init(_ base: ServiceIntelligenceBackend) { self.base = base }

    var reads: Int { count.withLock { $0 } }

    func items(_ filter: ItemFilter) async throws(IntelligenceError) -> [LabItem] {
        count.withLock { $0 += 1 }
        return try await base.items(filter)
    }

    func propose(_ operation: DomainOperation) async throws(IntelligenceError) -> OperationProposal { try await base.propose(operation) }
    func commit(_ change: ApprovedChange) async throws(IntelligenceError) -> ActionReceipt { try await base.commit(change) }
}
#endif
