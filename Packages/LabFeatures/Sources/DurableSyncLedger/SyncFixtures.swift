import Foundation

/// Original, neutral identities for the two-device fixture. They are not accounts on any service.
public enum SyncFixtures {
    public static let accountA = AccountID(uuidString: "017A0001-0000-4000-8000-000000000001")!
    public static let accountB = AccountID(uuidString: "017A0002-0000-4000-8000-000000000002")!
    public static let accountC = AccountID(uuidString: "017A0003-0000-4000-8000-000000000003")!
    public static let device1 = DeviceID(uuidString: "017D0001-0000-4000-8000-000000000001")!
    public static let device2 = DeviceID(uuidString: "017D0002-0000-4000-8000-000000000002")!
    public static let share = ShareID(uuidString: "017E0001-0000-4000-8000-000000000001")!
    public static let record = RecordID(uuidString: "017F0001-0000-4000-8000-000000000001")!

    public static let device1Label = "Device 1"
    public static let device2Label = "Device 2"
    public static let accountALabel = "Account A"
    public static let accountBLabel = "Account B"
}
