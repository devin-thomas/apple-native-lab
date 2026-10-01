import Foundation
#if !os(watchOS)
import AuthenticationServices
#endif

/// Names the installed platform-passkey provider so a missing SDK fails the build.
///
/// This build does not present `ASAuthorizationController`. A production passkey needs a
/// relying party and a domain, and the provider is unavailable on watchOS. The desk's
/// ceremony is the labeled simulation in `PasskeySimulator`.
public enum PasskeyPlatformProbe {
    public static var providerIsInThisSDK: Bool {
        #if os(watchOS)
        false
        #else
        true
        #endif
    }

    #if !os(watchOS)
    /// The installed provider. Touching the metatype is the compile probe; nothing is presented.
    public static func providerSymbol() -> String {
        String(reflecting: ASAuthorizationPlatformPublicKeyCredentialProvider.self)
    }
    #endif
}
