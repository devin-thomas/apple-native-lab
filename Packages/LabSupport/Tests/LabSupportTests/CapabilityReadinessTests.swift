import Testing
@testable import LabSupport

@Suite struct GateCombinationTests {
    private func gates(_ states: GateState...) -> [CapabilityGate] {
        let kinds: [GateKind] = [.hardware, .osAPI, .asset, .permission, .entitlement, .service]
        return zip(kinds, states).map { CapabilityGate($0, $1, "") }
    }

    @Test func unknownIsNeverReady() {
        // Every combination of three gate states: ready only when every gate was measured and met.
        for a in GateState.allCases {
            for b in GateState.allCases {
                for c in GateState.allCases {
                    let readiness = CapabilityReadiness.combining(gates(a, b, c))
                    let allMet = [a, b, c].allSatisfy { $0 == .met }
                    #expect(readiness.isReady == allMet, "\(a), \(b), \(c) gave \(readiness)")
                    if [a, b, c].contains(.unknown) {
                        #expect(!readiness.isReady)
                    }
                }
            }
        }
    }

    @Test func onlyAvailableIsReady() {
        #expect(CapabilityReadiness.allCases.filter(\.isReady) == [.available])
    }

    @Test func precedenceIsUnmetThenDeniedThenUnknownThenAction() {
        #expect(CapabilityReadiness.combining(gates(.met, .met, .met)) == .available)
        #expect(CapabilityReadiness.combining(gates(.met, .needsAction, .met)) == .needsAction)
        #expect(CapabilityReadiness.combining(gates(.needsAction, .unknown, .met)) == .unknown)
        #expect(CapabilityReadiness.combining(gates(.unknown, .denied, .needsAction)) == .denied)
        #expect(CapabilityReadiness.combining(gates(.restricted, .unknown, .met)) == .denied)
        #expect(CapabilityReadiness.combining(gates(.denied, .unmet, .unknown)) == .unavailable)
    }

    @Test func nothingMeasuredIsUnknown() {
        #expect(CapabilityReadiness.combining([]) == .unknown)
        #expect(CapabilityReadiness.combining([.noDeviceEvidence]) == .unknown)
    }

    @Test func verificationNeverChangesAvailability() {
        let measured = gates(.met, .met)
        let verifiedClaim = CapabilityGate(.verification, .met, "claimed")
        #expect(CapabilityReadiness.combining(measured + [.noDeviceEvidence]) == .available)
        #expect(CapabilityReadiness.combining(measured + [verifiedClaim]) == .available)
        #expect(CapabilityReadiness.combining(gates(.unknown) + [verifiedClaim]) == .unknown)
    }

    @Test func decidingGatesNameTheReason() {
        let set = [
            CapabilityGate(.hardware, .met, ""),
            CapabilityGate(.entitlement, .unmet, "missing"),
            CapabilityGate(.permission, .needsAction, ""),
            .noDeviceEvidence,
        ]
        #expect(CapabilityReadiness.decidingGates(set, for: .unavailable).map(\.kind) == [.entitlement])
        #expect(CapabilityReadiness.decidingGates(set, for: .available).isEmpty)
    }

    @Test func readinessHasNoVerifiedValue() {
        #expect(!CapabilityReadiness.allCases.map(\.rawValue).contains { $0.contains("verified") })
    }
}
