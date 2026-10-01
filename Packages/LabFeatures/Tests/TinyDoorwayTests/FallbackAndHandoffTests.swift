import Foundation
import LabDomain
import Testing
@testable import TinyDoorway

@Suite struct FallbackAndHandoffTests {
    @Test func informationPageNeedsNoNetwork() {
        let https = DoorwayValidator.validate(InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.infoHTTPS))
        let deep = DoorwayValidator.validate(InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.infoDeepLink))
        guard case .informationPage(.universalLink) = https, case .informationPage(.deepLink) = deep else {
            Issue.record("info links must open the local page")
            return
        }
        #expect(!DoorwayFallback.informationBody.isEmpty)
        #expect(DoorwayFallback.informationBody.contains("does not require a public website"))
        #expect(!DoorwayFallback.informationBody.lowercased().contains("install now"))
        #expect(DoorwayFallback.caption == "Web information page or full-app deep link, with no forced installation promise.")
    }

    @Test func clipStatusExplainsTheDeploymentGate() {
        guard case .notConfigured(let reason) = DoorwayClipStatus.current else {
            Issue.record("CoreLocal must report the clip as not configured")
            return
        }
        #expect(reason.contains("associated domains") || reason.contains("Associated domains"))
        #expect(reason.contains("FrontierOptional") || reason.contains("App Clip"))
    }

    @Test func handoffRoundTripsAndIsNotAGrant() throws {
        guard case .proposal(let proposal) = DoorwayValidator.validate(
            InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitHTTPS)
        ) else {
            Issue.record("fixture must validate")
            return
        }
        let handoff = DoorwayHandoff(proposal: proposal, confirmedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try JSONEncoder().encode(handoff)
        let decoded = try JSONDecoder().decode(DoorwayHandoff.self, from: data)
        #expect(decoded == handoff)
        #expect(decoded.itemID == DoorwayPolicy.sampleItemID)
        #expect(decoded.seal == proposal.seal)
        // A handoff has no operation and no grant fields.
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("grant"))
        #expect(!json.contains("operation"))
    }

    @Test func allowedItemIDsMatchTheDemoSeed() throws {
        let seed = try Fixtures.demoSeed()
        let seedIDs = Set(seed.items.map(\.id))
        #expect(DoorwayPolicy.allowedItemIDs == seedIDs)
        #expect(seedIDs.contains(DoorwayPolicy.sampleItemID))
    }
}
