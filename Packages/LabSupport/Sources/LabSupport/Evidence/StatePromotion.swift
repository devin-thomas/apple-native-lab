/// Proof that a check passed on physical hardware: the only input that can promote a state to
/// `device-verified` (SPEC §7).
///
/// Its only initializer takes a record and refuses anything but a passing physical run, and it is
/// not `Decodable`, so a simulator, fixture, or static-review result can never become one.
public struct DeviceProof: Sendable, Equatable {
    public let record: EvidenceRecord
    public let device: PhysicalDevice

    public init(_ record: EvidenceRecord) throws {
        guard case .physical(let device) = record.execution else {
            throw PromotionError.notPhysical(record.path)
        }
        guard record.result.isPassed else { throw PromotionError.notPassed(record.result) }
        self.record = record
        self.device = device
    }
}

/// Why a record cannot move an implementation state.
public enum PromotionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Only a passing record supports a promotion.
    case notPassed(RunResult)
    /// Only a physical run can prove a device.
    case notPhysical(ExecutionPath)
    /// The record's path cannot support the requested state.
    case exceedsPath(ExecutionPath, requested: ImplementationState)
    /// `release-ready` needs acceptance, device, privacy, and accessibility review, not one record.
    case requiresReleaseReview
    /// The requested state is not above the current one, or is not reached through evidence.
    case notAPromotion(from: ImplementationState, to: ImplementationState)

    public var description: String {
        switch self {
        case .notPassed(let result):
            "A \(result.rawValue) check supports no promotion."
        case .notPhysical(let path):
            "Device verification needs a physical run; this record's path is \(path.rawValue)."
        case .exceedsPath(let path, let requested):
            "A \(path.rawValue) run supports at most \(path.highestSupportedState.rawValue), not \(requested.rawValue)."
        case .requiresReleaseReview:
            "Release-ready needs acceptance, device, privacy, and accessibility review, not a single record."
        case .notAPromotion(let from, let to):
            "Moving from \(from.rawValue) to \(to.rawValue) is not a promotion."
        }
    }
}

extension ImplementationState {
    /// The state `record` promotes this one to, or an error saying why it cannot.
    ///
    /// Promotion to `device-verified` goes through `DeviceProof`, so it requires a passing
    /// physical record. A passing simulator or fixture record reaches `implemented` at most, and a
    /// static review `spiked`. No record reaches `release-ready`, and `specified` and `blocked`
    /// are not promotions.
    public func promoted(to target: ImplementationState, by record: EvidenceRecord) throws -> ImplementationState {
        try checkPromotion(to: target)
        if target == .deviceVerified {
            return try promoted(toDeviceVerifiedBy: try DeviceProof(record))
        }
        guard record.result.isPassed else { throw PromotionError.notPassed(record.result) }
        guard target <= record.path.highestSupportedState else {
            throw PromotionError.exceedsPath(record.path, requested: target)
        }
        return target
    }

    /// `device-verified`, given proof of a passing physical run.
    public func promoted(toDeviceVerifiedBy proof: DeviceProof) throws -> ImplementationState {
        try checkPromotion(to: .deviceVerified)
        return .deviceVerified
    }

    private func checkPromotion(to target: ImplementationState) throws {
        if target == .releaseReady { throw PromotionError.requiresReleaseReview }
        guard target.isLive || target == .spiked, target > self else {
            throw PromotionError.notAPromotion(from: self, to: target)
        }
    }
}
