import Foundation
import Testing
@testable import LabSupport

@Suite struct StatePromotionTests {
    /// Every path, result, starting state, and target, against the rule stated independently here.
    @Test func exhaustivePromotionTable() throws {
        for execution in try EvidenceGolden.allExecutions() {
            for outcome in EvidenceGolden.allOutcomes() {
                let record = try EvidenceGolden.record(execution: execution, outcome: outcome)
                for current in ImplementationState.allCases {
                    for target in ImplementationState.allCases {
                        let allowed = expectedAllowed(from: current, to: target, path: execution.path, result: outcome.result)
                        let promoted = try? current.promoted(to: target, by: record)
                        #expect((promoted != nil) == allowed, "\(current) -> \(target) by \(execution.path) \(outcome.result)")
                        if let promoted { #expect(promoted == target) }
                    }
                }
            }
        }
    }

    @Test(arguments: [ExecutionPath.simulator, .fixture, .staticReview])
    func onlyAPhysicalRecordReachesDeviceVerified(path: ExecutionPath) throws {
        let execution = try EvidenceGolden.allExecutions().first { $0.path == path }!
        let record = try EvidenceGolden.record(execution: execution)
        #expect(record.supportedState != .deviceVerified)
        #expect(throws: PromotionError.notPhysical(path)) { try DeviceProof(record) }
        #expect(throws: PromotionError.notPhysical(path)) {
            try ImplementationState.implemented.promoted(to: .deviceVerified, by: record)
        }
    }

    /// A proof can only be derived from a validated record, never read from a file.
    @Test func proofIsNotDecodable() {
        #expect(!(DeviceProof.self is any Decodable.Type))
    }

    @Test func passingPhysicalRecordProvesTheDevice() throws {
        let record = try EvidenceGolden.record(execution: .physical(try EvidenceGolden.physicalDevice()))
        let proof = try DeviceProof(record)
        #expect(proof.device == (try EvidenceGolden.physicalDevice()))
        #expect(record.supportedState == .deviceVerified)
        #expect(try ImplementationState.implemented.promoted(toDeviceVerifiedBy: proof) == .deviceVerified)
    }

    @Test(arguments: [RunResult.failed, .blocked, .notRun])
    func physicalRecordThatDidNotPassProvesNothing(result: RunResult) throws {
        let record = try EvidenceGolden.record(
            execution: .physical(try EvidenceGolden.physicalDevice()),
            outcome: RunOutcome(result, detail: "Observed on hardware.")
        )
        #expect(record.supportedState == nil)
        #expect(throws: PromotionError.notPassed(result)) { try DeviceProof(record) }
    }

    @Test func simulatorPassEstablishesImplementedOnly() throws {
        let record = try EvidenceGolden.record(execution: .simulator(SimulatedDevice(platform: .iOS)))
        #expect(record.supportedState == .implemented)
        #expect(try ImplementationState.spiked.promoted(to: .implemented, by: record) == .implemented)
    }

    @Test func noRecordReachesReleaseReady() throws {
        let record = try EvidenceGolden.record(execution: .physical(try EvidenceGolden.physicalDevice()))
        #expect(throws: PromotionError.requiresReleaseReview) {
            try ImplementationState.deviceVerified.promoted(to: .releaseReady, by: record)
        }
    }

    @Test func staticReviewCannotEstablishARunningState() throws {
        let record = try EvidenceGolden.record(execution: .staticReview)
        #expect(throws: PromotionError.exceedsPath(.staticReview, requested: .implemented)) {
            try ImplementationState.spiked.promoted(to: .implemented, by: record)
        }
    }

    @Test func proofCannotDemote() throws {
        let proof = try DeviceProof(try EvidenceGolden.record(execution: .physical(try EvidenceGolden.physicalDevice())))
        #expect(throws: PromotionError.notAPromotion(from: .releaseReady, to: .deviceVerified)) {
            try ImplementationState.releaseReady.promoted(toDeviceVerifiedBy: proof)
        }
    }

    @Test func errorsExplainThemselves() {
        #expect(PromotionError.notPhysical(.simulator).description.contains("physical run"))
        #expect(PromotionError.exceedsPath(.fixture, requested: .deviceVerified).description.contains("at most implemented"))
    }

    private func expectedAllowed(
        from current: ImplementationState,
        to target: ImplementationState,
        path: ExecutionPath,
        result: RunResult
    ) -> Bool {
        guard result == .passed, target > current else { return false }
        switch target {
        case .spiked: return true
        case .implemented: return path != .staticReview
        case .deviceVerified: return path == .physical
        case .specified, .blocked, .releaseReady: return false
        }
    }
}
