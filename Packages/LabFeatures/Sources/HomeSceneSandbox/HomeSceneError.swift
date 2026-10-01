import Foundation
import LabDomain

/// Why a home-scene step did not complete. Nothing is changed for these cases unless a partial
/// accessory list already applied (partial failure is reported, not thrown).
public enum HomeSceneError: Error, Hashable, Sendable {
    case cancelled
    case invalidInput(String)
    case notFound(String)
    case liveUnavailable(String)
    case permissionRevoked(HomePermission)
    case labUnavailable(String)
    case operation(OperationError)
    case stateChanged
    case emptySelection
    case sensitiveKindExcluded(AccessoryKind)

    public var message: String {
        switch self {
        case .cancelled:
            "Cancelled. Nothing further was changed."
        case .invalidInput(let detail):
            "\(detail) Nothing was changed."
        case .notFound(let detail):
            "\(detail) Nothing was changed."
        case .liveUnavailable(let detail):
            detail
        case .permissionRevoked(let permission):
            "\(permission.explanation) Live mode stopped."
        case .labUnavailable(let reason):
            reason
        case .operation(.unauthorized):
            "This entry point is not allowed to record the scene run. Nothing was changed."
        case .operation(.storeFailure):
            "Native Lab could not read or save its data. Nothing was changed. Try again."
        case .operation:
            "The scene run could not be recorded. Nothing was changed."
        case .stateChanged:
            "The scene record changed. Review the scene and commit again. No lamps changed."
        case .emptySelection:
            "Select at least one light change before committing. Nothing was changed."
        case .sensitiveKindExcluded(let kind):
            "\(kind.title) accessories are excluded by default. Nothing was changed for them."
        }
    }
}

extension HomeSceneError: LocalizedError, CustomLocalizedStringResourceConvertible {
    public var errorDescription: String? { message }
    public var localizedStringResource: LocalizedStringResource { "\(message)" }
}
