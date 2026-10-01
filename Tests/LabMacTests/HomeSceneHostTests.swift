import HomeSceneSandbox
import Testing
@testable import NativeLab

/// Host wiring for LAB-037: the sidebar destination and experiment names.
@Suite struct HomeSceneHostTests {
    @Test func theSandboxIsASidebarDestinationWithCommand9() {
        #expect(SidebarDestination(storageKey: SidebarDestination.homeSceneSandbox.storageKey) == .homeSceneSandbox)
        #expect(SidebarDestination.homeSceneSandbox.title == HomeSceneExperiment.title)
        #expect(HomeSceneExperiment.id == "LAB-037")
        #expect(HomeKitPlatformFacts.homeKitClientAvailableInSDK == false)
        #expect(HomeKitPlatformFacts.coreLocalGateExplanation.contains("macOS")
            || HomeKitPlatformFacts.coreLocalGateExplanation.contains("fictional"))
    }
}
