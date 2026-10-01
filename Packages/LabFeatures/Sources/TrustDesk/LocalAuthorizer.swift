import Foundation
import Synchronization
#if !os(tvOS)
import LocalAuthentication
#endif

/// What a local-authorization attempt did. Success is the only result that may issue a grant.
/// A failure leaves the desk's records, secrets, and grants as they were.
public enum DeviceAuthorizationAttempt: Hashable, Sendable {
    case succeeded
    case biometricFailed
    case cancelled
    case unavailable(String)
}

/// Asks this device to confirm the person, or stands in for that ask in a test.
public protocol LocalAuthorizer: Sendable {
    func authorize() async -> DeviceAuthorizationAttempt
}

/// A fixed sequence of results. The desk tests use it so a biometric failure is deterministic
/// and never shows a system prompt.
public final class ScriptedLocalAuthorizer: LocalAuthorizer, Sendable {
    private let results: Mutex<[DeviceAuthorizationAttempt]>

    public init(results: [DeviceAuthorizationAttempt]) {
        self.results = Mutex(results)
    }

    public func authorize() async -> DeviceAuthorizationAttempt {
        results.withLock { stored in
            if stored.isEmpty { return .unavailable("The scripted authorizer has no further results.") }
            return stored.removeFirst()
        }
    }
}

/// LocalAuthentication for `LAPolicy.deviceOwnerAuthentication`.
///
/// That policy is this device's owner, by biometry or the device passcode. It is not an
/// account sign-in. On tvOS the framework does not offer the policy, so the attempt is
/// unavailable and the local-confirmation fallback remains. `probeWithoutPrompt` sets
/// `interactionNotAllowed`, so a test can see a real failure without a system dialog.
public struct DeviceOwnerAuthorizer: LocalAuthorizer {
    public init() {}

    public func authorize() async -> DeviceAuthorizationAttempt {
        #if os(tvOS)
        return .unavailable("LocalAuthentication is not available on this platform.")
        #else
        let context = LAContext()
        return await Self.evaluate(context, reason: "Authorize opening the sealed Trust Desk record.")
        #endif
    }

    /// Evaluates the same policy with interaction forbidden. It cannot succeed through a prompt,
    /// and it does not issue a grant; the desk does that only after `authorize()` succeeds.
    public func probeWithoutPrompt() async -> DeviceAuthorizationAttempt {
        #if os(tvOS)
        return .unavailable("LocalAuthentication is not available on this platform.")
        #else
        let context = LAContext()
        context.interactionNotAllowed = true
        return await Self.evaluate(context, reason: "Trust Desk availability probe.")
        #endif
    }

    #if !os(tvOS)
    private static func evaluate(_ context: LAContext, reason: String) async -> DeviceAuthorizationAttempt {
        await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .succeeded)
                    return
                }
                continuation.resume(returning: classify(error))
            }
        }
    }

    private static func classify(_ error: (any Error)?) -> DeviceAuthorizationAttempt {
        guard let error = error as? LAError else {
            return .unavailable("This device did not authorize.")
        }
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .authenticationFailed, .userFallback:
            return .biometricFailed
        #if os(iOS) || os(macOS)
        case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
            return .biometricFailed
        #endif
        case .notInteractive, .passcodeNotSet:
            return .unavailable("This device cannot show an authorization prompt right now.")
        default:
            return .unavailable("This device did not authorize.")
        }
    }
    #endif
}
