import Foundation
import LabDomain
import Testing
@testable import PickUpHere

@Suite struct FallbackTests {
    @Test func theActivityAndLinkCarryOnlyTheIdentifierAndPosition() async throws {
        let lab = try await PickUpLab.make()
        let item = try await lab.addItem(title: "Workbench", note: Sentinel.note)
        let offer = try await PickUpResolver(backend: lab.backend).prepare(item: item.id, section: 1)
        #expect(Set(offer.userInfo.keys) == ContinuationPayload.keys)
        #expect(offer.userInfo.values.allSatisfy { !$0.contains(Sentinel.text) && !$0.contains("Workbench") })
        let link = offer.link.absoluteString
        #expect(!link.contains(Sentinel.text))
        #expect(!link.contains("Workbench"))
        let parsed = try ContinuationLink.token(parsing: offer.link)
        #expect(parsed == offer.token)

        let activity = HandoffActivity.make(from: offer, handoffEligible: true)
        #expect(activity.activityType == HandoffActivity.activityType)
        #expect(activity.title == "Pick Up Here")
        #expect(activity.title != item.title.value)
        #expect(activity.isEligibleForHandoff)
        #expect(!activity.isEligibleForSearch)
        #expect(!activity.isEligibleForPublicIndexing)
        #expect(!activity.supportsContinuationStreams)
        #expect(activity.webpageURL == nil)
        #expect(try HandoffActivity.token(from: activity) == offer.token)
        let described = String(describing: activity.userInfo)
        #expect(!described.contains(Sentinel.text))
    }

    @Test func aPayloadThatCarriesTheDraftIsRefused() async throws {
        let lab = try await PickUpLab.make()
        let item = try await lab.addItem(title: "Workbench", note: Sentinel.note)
        let offer = try await PickUpResolver(backend: lab.backend).prepare(item: item.id, section: 0)
        var smuggled = offer.userInfo
        smuggled["note"] = Sentinel.text
        #expect(throws: PickUpError.invalidPayload) {
            try ContinuationPayload.token(from: smuggled)
        }
        let error = PickUpError.invalidPayload
        #expect(!error.sentence.contains(Sentinel.text))

        var components = URLComponents(url: offer.link, resolvingAgainstBaseURL: false)!
        components.queryItems?.append(URLQueryItem(name: "note", value: Sentinel.text))
        #expect(throws: PickUpError.invalidPayload) {
            try ContinuationLink.token(parsing: components.url!)
        }
    }

    @Test func aChangedActivityTypeIsRefused() async throws {
        let lab = try await PickUpLab.make()
        let item = try await lab.addItem(title: "Workbench", note: "One section")
        let offer = try await PickUpResolver(backend: lab.backend).prepare(item: item.id, section: 0)
        let activity = NSUserActivity(activityType: "nativelab.something-else")
        HandoffActivity.fill(activity, with: offer, handoffEligible: false)
        #expect(throws: PickUpError.invalidPayload) { try HandoffActivity.token(from: activity) }
    }

    @Test func handoffCanStayOffAndTheCopiedDocumentStillImports() async throws {
        let source = try await PickUpLab.make()
        let item = try await source.addItem(id: SampleDraft.documentID, title: SampleDraft.title, note: SampleDraft.note)
        let offer = try await PickUpResolver(backend: source.backend).prepare(item: item.id, section: SampleDraft.selectedSection)
        let activity = HandoffActivity.make(from: offer, handoffEligible: false)
        #expect(!activity.isEligibleForHandoff)
        #expect(try HandoffActivity.token(from: activity) == offer.token)

        let destination = try await PickUpLab.make()
        let hint = try ContinuationLink.token(parsing: offer.link)
        let missing = try await PickUpResolver(backend: destination.backend).resume(hint)
        guard case .needsImport = missing else {
            Issue.record("Expected an import prompt")
            return
        }
        let document = try ContinuationDocument(decoding: offer.document.encoded())
        #expect(document.sections == SampleDraft.sections)
        let imported = try await ContinuationImporter.importDocument(document, into: destination.collection, backend: destination.backend)
        let receipt = try #require(imported.receipt)
        #expect(receipt.status == .committed)
        #expect(receipt.admitted.adapter == .appUI)
        guard case .createItem(let draft) = receipt.admitted.operation else {
            Issue.record("Expected a create")
            return
        }
        #expect(draft.id == SampleDraft.documentID)
        let resumed = try #require(try await PickUpResolver(backend: destination.backend).resume(hint).resumed)
        #expect(resumed.section == SampleDraft.selectedSection)
        #expect(resumed.sectionText == SampleDraft.sections[1])
        #expect(await destination.itemCount() == 1)
    }

    @Test func importingAgainDoesNotDuplicateTheDraft() async throws {
        let lab = try await PickUpLab.make()
        let document = try SampleDraft.document()
        let first = try await ContinuationImporter.importDocument(document, into: lab.collection, backend: lab.backend)
        #expect(first.receipt != nil)
        let second = try await ContinuationImporter.importDocument(document, into: lab.collection, backend: lab.backend)
        #expect(second.receipt == nil)
        #expect(await lab.itemCount() == 1)
    }

    @Test func aModelToolCannotImport() async throws {
        let lab = try await PickUpLab.make()
        let tool = ServicePickUpBackend(
            service: lab.service,
            actor: ActorScope(adapter: .modelTool, grants: [.read, .propose, .commit])
        )
        let document = try SampleDraft.document()
        await #expect(throws: PickUpError.notAuthorized) {
            try await ContinuationImporter.importDocument(document, into: lab.collection, backend: tool)
        }
        #expect(await lab.itemCount() == 0)
    }

    @Test func aHostileDocumentIsRefusedAndWritesNothing() async throws {
        let lab = try await PickUpLab.make()
        let samples = [
            Data("{\"format\":\"native-lab-continuation\",\"schemaVersion\":1,\"documentID\":\"01600000-0000-4000-8000-000000000016\",\"revision\":1,\"title\":\"Workbench layout\",\"sections\":[\"Bench\"],\"grant\":\"allow\"}\n".utf8),
            Data("not json".utf8),
            Data("{\"format\":\"native-lab-continuation\",\"schemaVersion\":1,\"documentID\":\"01600000-0000-4000-8000-000000000016\",\"revision\":1,\"title\":\"Workbench layout\",\"sections\":[\"Bench\"],\"format\":\"native-lab-continuation\"}".utf8),
        ]
        for sample in samples {
            #expect(throws: PickUpError.self) { try ContinuationDocument(decoding: sample) }
        }
        #expect(await lab.itemCount() == 0)
    }
}
