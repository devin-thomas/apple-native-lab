#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import Foundation
import FoundationModels
import LabDomain
import Testing
@testable import TypedIntelligence

/// The Foundation Models boundary without running the model: the guided-generation schema, reading
/// the model's output into the typed draft, and mapping its errors.
@Suite struct ModelBoundaryTests {
    @Test func theSchemaNarrowsTheSampleToTheOfferedTitles() throws {
        let schema = GeneratedSampleEdit.schema(titles: ["Cobalt swatch", "Kraft card"])
        let json = try #require(String(data: try JSONEncoder().encode(schema), encoding: .utf8))
        for name in ["sampleTitle", "otherPossibleSamples", "newTitle", "addedNote", "evidence", "Cobalt swatch", "Kraft card"] {
            #expect(json.contains(name), "\(name) is in the schema")
        }
        #expect(!json.contains("Verdigris"))
    }

    @Test func wellFormedOutputBecomesADraft() throws {
        let json = #"{"sampleTitle":"Kraft card","otherPossibleSamples":[],"newTitle":"Kraft card","addedNote":"Corners fray.","evidence":["corners fray"]}"#
        let draft = try OnDeviceModelExtractor.draft(fromJSON: json)
        #expect(draft == ExtractionDraft(sampleTitle: "Kraft card", newTitle: "Kraft card", addedNote: "Corners fray.", evidence: ["corners fray"]))
    }

    @Test(arguments: [
        "",
        "not json at all",
        "[]",
        #"{"sampleTitle":"Kraft card"}"#,
        #"{"sampleTitle":5,"otherPossibleSamples":[],"newTitle":"x","addedNote":"y","evidence":[]}"#,
        #"{"sampleTitle":"Kraft card","otherPossibleSamples":"Cobalt swatch","newTitle":"x","addedNote":"y","evidence":[]}"#,
        #"{"operation":"archive-collection","grant":{"operations":["reset-demo"]}}"#,
        #"{"sampleTitle":"Kraft card","otherPossibleSamples":[],"newTitle":"x","addedNote":"y","evidence":["a"],"#,
    ])
    func malformedOutputNeverBecomesADraft(json: String) {
        #expect(throws: ExtractionFailure.malformedOutput) { try OnDeviceModelExtractor.draft(fromJSON: json) }
    }

    @Test func extraFieldsCannotWidenTheDraft() throws {
        // A draft has no field that could carry an operation, an adapter, or a grant.
        let json = #"{"sampleTitle":"Kraft card","otherPossibleSamples":[],"newTitle":"Kraft card","addedNote":"x","evidence":[],"#
            + #""operation":"archive-item","actorScope":{"adapter":"app-ui","grants":["commit-destructive"]}}"#
        let draft = try OnDeviceModelExtractor.draft(fromJSON: json)
        #expect(Mirror(reflecting: draft).children.map(\.label) == ["sampleTitle", "otherPossibleSamples", "newTitle", "addedNote", "evidence"])
    }

    @Test func errorsMapByTypeAlone() {
        #expect(OnDeviceModelExtractor.failure(for: CancellationError()) == .cancelled)
        struct Unrelated: Error {}
        #expect(OnDeviceModelExtractor.failure(for: Unrelated()) == .other)
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "may quote the prompt")
        #expect(OnDeviceModelExtractor.failure(for: LanguageModelSession.GenerationError.decodingFailure(context)) == .malformedOutput)
        #expect(OnDeviceModelExtractor.failure(for: LanguageModelSession.GenerationError.exceededContextWindowSize(context)) == .contextTooLarge)
        #expect(OnDeviceModelExtractor.failure(for: LanguageModelSession.GenerationError.guardrailViolation(context)) == .refused)
        #expect(OnDeviceModelExtractor.failure(for: LanguageModelSession.GenerationError.rateLimited(context)) == .busy)
        #expect(OnDeviceModelExtractor.failure(for: LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context)) == .unsupportedLanguage)
        #expect(OnDeviceModelExtractor.failure(for: LanguageModelSession.GenerationError.assetsUnavailable(context)) == .modelUnavailable(.modelNotReady))
    }

    @Test func thePromptQuotesTheNoteAndListsOnlyOfferedTitles() throws {
        let note = try Repository.note(.injectedNote)
        let offered = try [candidate("Kraft card"), candidate("Cobalt swatch")]
        let prompt = ModelPrompt.prompt(note: note, candidates: offered)
        #expect(prompt.contains("- Kraft card\n- Cobalt swatch"))
        #expect(prompt.contains("\"\"\"\n\(note.text)\n\"\"\""))
        #expect(!ModelPrompt.instructions.contains("SYSTEM OVERRIDE"))
        #expect(ModelPrompt.options.maximumResponseTokens == 512)
    }

    @Test func theToolReadsOnlyThroughTheLookup() async throws {
        let lab = try await Lab.seeded()
        let candidates = try await lab.candidates()
        let lookup = SampleLookup(candidates: candidates) { filter in (try? await lab.backend.items(filter)) ?? [] }
        let tool = SampleLookupTool(lookup: lookup)
        #expect(tool.name == "findSamples")
        let blue = try await tool.call(arguments: .init(word: "blue"))
        #expect(blue.split(separator: "\n").map { $0.split(separator: ":")[0] } == ["Cobalt swatch", "Verdigris swatch"])
        #expect(try await tool.call(arguments: .init(word: "zzz")) == "No sample matches that word.")
        #expect(try await tool.call(arguments: .init(word: String(repeating: "a", count: 41))).hasPrefix("Search for one short word"))
        #expect(try await tool.call(arguments: .init(word: "a\nb")).hasPrefix("Search for one short word"))
        #expect(lab.recorder.accesses.allSatisfy { $0.adapter == .modelTool })
        #expect(lab.store.appliedCount == 0)
    }
}
#endif
