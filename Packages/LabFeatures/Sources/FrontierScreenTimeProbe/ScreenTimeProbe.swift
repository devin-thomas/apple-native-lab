#if os(iOS)
import FamilyControls

/// Compile-only individual authorization seam, not linked by any host. No shields or monitors.
@MainActor
public enum ScreenTimeProbe {
    public static func authorizeSelf() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }
    public static func revoke(completion: @escaping (Result<Void, any Error>) -> Void) {
        AuthorizationCenter.shared.revokeAuthorization(completionHandler: completion)
    }
}
#endif
