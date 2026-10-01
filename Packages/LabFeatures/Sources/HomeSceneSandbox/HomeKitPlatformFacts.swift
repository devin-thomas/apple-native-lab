import Foundation

/// Installed-SDK facts for HomeKit, recorded without linking HomeKit into CoreLocal.
///
/// HomeKit is `API_UNAVAILABLE(macos)` on the macOS 27.0 SDK (no `HomeKit.framework` there).
/// On iOS 27.0, `HMHomeManager.authorizationStatus` and `HMAccessory.isReachable` are present,
/// and light / lock / door / alarm / thermostat service types match this module's kinds. A live
/// adapter needs `com.apple.developer.homekit` and `NSHomeKitUsageDescription`; those stay out of
/// CoreLocal ([EXTENSION_AND_PERMISSION_MATRIX](../../../../docs/EXTENSION_AND_PERMISSION_MATRIX.md)).
public enum HomeKitPlatformFacts {
    /// Whether this OS's SDK ships the HomeKit client used for live mode.
    public static var homeKitClientAvailableInSDK: Bool {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        true
        #else
        false
        #endif
    }

    public static var authorizationStatusSymbol: String {
        "HMHomeManager.authorizationStatus"
    }

    public static var reachableSymbol: String {
        "HMAccessory.isReachable"
    }

    public static var powerStateSymbol: String {
        "HMCharacteristicTypePowerState"
    }

    public static var brightnessSymbol: String {
        "HMCharacteristicTypeBrightness"
    }

    public static var entitlementKey: String {
        "com.apple.developer.homekit"
    }

    public static var purposeStringKey: String {
        "NSHomeKitUsageDescription"
    }

    /// One sentence for the UI and evidence when live mode is not offered.
    public static var coreLocalGateExplanation: String {
        if homeKitClientAvailableInSDK {
            return "Live HomeKit needs a separate opt-in build with \(entitlementKey) and \(purposeStringKey). This CoreLocal build uses the fictional home only."
        }
        return "HomeKit is unavailable on macOS in the installed SDK. This Mac client uses the fictional home only."
    }
}
