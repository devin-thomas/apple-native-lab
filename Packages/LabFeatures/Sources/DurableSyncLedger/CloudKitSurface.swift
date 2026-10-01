import Foundation

/// What the installed SDK says about CloudKit, and what this build refuses to do with it.
///
/// Read from the iOS 27.0 SDK's `CloudKit.swiftinterface` and the CloudKit headers in Xcode 27.0
/// (27A266a) on 2026-09-30. This module does not import CloudKit. CoreLocal does not link it and
/// does not declare an iCloud entitlement. The optional profile below is the private or shared
/// database a later CloudOptional host would hand to `CKSyncEngine`; the public database is not a
/// case the ledger can select.
public enum CloudKitSurface {
    /// CoreLocal never links CloudKit.
    public static let linkedInCoreLocal = false
    /// `CKDatabase.Scope.public` exists in the SDK. This lab does not sync to it.
    public static let publicDatabaseIsForbidden = true
    /// `CKSyncEngine.Configuration.automaticallySync` exists. A live adapter must leave it false:
    /// synchronization is opportunistic, not a low-latency bus. Fetch and send stay explicit.
    public static let automaticSyncStaysOff = true

    /// `CKSyncEngine` and `CKSyncEngine.Configuration.init(database:stateSerialization:delegate:)`.
    public static let engineAvailability = "macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0"
    /// `fetchChanges(_:)` and `sendChanges(_:)`.
    public static let fetchAndSendAvailability = "macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0"
    /// `CKSyncEngine.Event.accountChange` with `signIn`, `signOut`, and `switchAccounts`.
    public static let accountChangeAvailability = "macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0"
    /// `CKDatabase.Scope` (`public`, `private`, `shared`) and `CKContainer.accountStatus`.
    public static let databaseScopeAvailability = "macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0"
    /// `CKAccountStatus.temporarilyUnavailable` — keep the local cache; do not enqueue work.
    public static let temporarilyUnavailableAvailability = "macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0"

    /// No iCloud container entitlement is declared for CoreLocal. A live engine needs
    /// `com.apple.developer.icloud-services` = CloudKit and a container the signing team owns.
    public static let entitlementInCoreLocal = false
}
