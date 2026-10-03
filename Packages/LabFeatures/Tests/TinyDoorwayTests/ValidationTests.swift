import Foundation
import LabDomain
import Testing
@testable import TinyDoorway

@Suite struct ValidationTests {
    @Test func acceptedFixturesValidate() throws {
        let file = try Fixtures.links()
        for entry in file.accepted {
            let context = InvocationContext(source: .fixtureReplay, rawURL: entry.url)
            let result = DoorwayValidator.validate(context)
            switch (entry.expect, result) {
            case ("proposal", .proposal(let proposal)):
                #expect(proposal.action == .visit)
                #expect(proposal.itemID == DoorwayPolicy.sampleItemID)
                #expect(!proposal.seal.hex.isEmpty)
            case ("information", .informationPage):
                break
            default:
                Issue.record("\(entry.name): expected \(entry.expect), got \(String(describing: result))")
            }
        }
    }

    @Test func refusedFixturesNeverProduceAProposal() throws {
        let file = try Fixtures.links()
        for entry in file.refused {
            let context = InvocationContext(source: .fixtureReplay, rawURL: entry.url)
            let result = DoorwayValidator.validate(context)
            guard case .refused = result else {
                Issue.record("\(entry.name) should be refused, got \(String(describing: result))")
                continue
            }
        }
    }

    @Test func demoLinksMatchTheHappyPath() {
        let https = DoorwayValidator.validate(InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitHTTPS))
        let deep = DoorwayValidator.validate(InvocationContext(source: .fixtureReplay, rawURL: DemoLinks.visitDeepLink))
        guard case .proposal(let a) = https, case .proposal(let b) = deep else {
            Issue.record("demo links must produce proposals")
            return
        }
        #expect(a.itemID == b.itemID)
        #expect(a.channel == .universalLink)
        #expect(b.channel == .deepLink)
        #expect(a.seal != b.seal) // channel is part of the seal
    }

    @Test func offlineBlocksHTTPSButNotDeepLinks() {
        let offlineHTTPS = DoorwayValidator.validate(
            InvocationContext(source: .openedURL, rawURL: DemoLinks.visitHTTPS, reachability: .offline)
        )
        guard case .refused(.offline(let message)) = offlineHTTPS else {
            Issue.record("offline https should refuse with an explanation")
            return
        }
        #expect(message.contains("offline"))
        #expect(message.contains("deep link") || message.contains("nativelab://"))

        let offlineDeep = DoorwayValidator.validate(
            InvocationContext(source: .openedURL, rawURL: DemoLinks.visitDeepLink, reachability: .offline)
        )
        guard case .proposal = offlineDeep else {
            Issue.record("offline deep link must still validate")
            return
        }
    }

    @Test func appClipSourceIsRefusedWhenClipIsNotConfigured() {
        #expect(DoorwayClipStatus.current != .configured)
        let result = DoorwayValidator.validate(
            InvocationContext(source: .appClip, rawURL: DemoLinks.visitHTTPS)
        )
        guard case .refused(.clipUnavailable(let reason)) = result else {
            Issue.record("app clip source without a target must refuse")
            return
        }
        #expect(reason.contains("App Clip"))
    }

    @Test func privilegedPathsAndParametersCannotExecute() {
        let cases = [
            "https://doorway.nativelab.example/open/reset-demo",
            "https://doorway.nativelab.example/admin/delete",
            "https://doorway.nativelab.example/open/visit?item=af451890-ca80-4de9-b18b-4007066c9177&operation=archiveItem",
            "https://doorway.nativelab.example/open/visit?grant=yes&item=af451890-ca80-4de9-b18b-4007066c9177",
            "https://evil.example/open/visit?item=af451890-ca80-4de9-b18b-4007066c9177",
            "javascript:alert(1)",
            "nativelab://other/open/visit?item=af451890-ca80-4de9-b18b-4007066c9177",
        ]
        for url in cases {
            let result = DoorwayValidator.validate(InvocationContext(source: .pasted, rawURL: url))
            guard case .refused = result else {
                Issue.record("\(url) must be refused")
                continue
            }
        }
    }

    @Test func unknownItemUUIDIsRefusedBeforeTheStore() {
        let url = "https://doorway.nativelab.example/open/visit?item=00000000-0000-0000-0000-000000000001"
        let result = DoorwayValidator.validate(InvocationContext(source: .pasted, rawURL: url))
        guard case .refused(.itemUnavailable) = result else {
            Issue.record("unknown item must be refused as unavailable")
            return
        }
    }

    @Test func credentialsAreRefused() {
        let url = "https://user:pass@doorway.nativelab.example/open/visit?item=af451890-ca80-4de9-b18b-4007066c9177"
        let result = DoorwayValidator.validate(InvocationContext(source: .pasted, rawURL: url))
        guard case .refused(.linkContainsCredentials) = result else {
            Issue.record("credentials must be refused")
            return
        }
    }
}
