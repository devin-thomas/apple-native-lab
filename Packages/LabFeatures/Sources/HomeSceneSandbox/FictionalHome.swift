import Foundation
import LabDomain

/// Stable fixture identifiers and the deterministic fictional home. No real accessories.
public enum FictionalHome {
    public static let homeID = UUID(uuidString: "03703703-7037-4037-8037-037037037001")!
    public static let homeName = "Cedar Fixture Home"

    public static let collection = CollectionID(rawValue: UUID(uuidString: "03703703-7037-4037-8037-037037037010")!)
    public static let item = ItemID(rawValue: UUID(uuidString: "03703703-7037-4037-8037-037037037011")!)
    public static let collectionTitle = "Home Scene Sandbox"
    public static let sealedNote = "No scene committed yet. The fictional home has not written a run."

    public static let createCollectionRequest = RequestID(rawValue: UUID(uuidString: "03703703-7037-4037-8037-0370370370C1")!)
    public static let createItemRequest = RequestID(rawValue: UUID(uuidString: "03703703-7037-4037-8037-0370370370C2")!)

    public static let livingLamp = AccessoryID(UUID(uuidString: "03703703-7037-4037-8037-037037037101")!)
    public static let hallwayLamp = AccessoryID(UUID(uuidString: "03703703-7037-4037-8037-037037037102")!)
    public static let frontLock = AccessoryID(UUID(uuidString: "03703703-7037-4037-8037-037037037201")!)
    public static let patioDoor = AccessoryID(UUID(uuidString: "03703703-7037-4037-8037-037037037202")!)
    public static let entryAlarm = AccessoryID(UUID(uuidString: "03703703-7037-4037-8037-037037037203")!)
    public static let hallThermostat = AccessoryID(UUID(uuidString: "03703703-7037-4037-8037-037037037204")!)

    /// Labeled in the UI so a fixture run is never mistaken for a live home.
    public static let simulationLabel =
        "Deterministic fictional home. No real accessories. Labeled as a replay of the domain contract, not a HomeKit proof."

    /// The fixed home: two lights (one disconnected), plus lock, door, alarm, and heating that
    /// stay excluded by default.
    public static func snapshot(hallwayReachable: Bool = false) -> HomeSnapshot {
        HomeSnapshot(
            id: homeID,
            name: homeName,
            accessories: [
                AccessorySnapshot(
                    id: livingLamp,
                    name: "Living room lamp",
                    room: "Living room",
                    kind: .light,
                    isReachable: true,
                    isOn: false,
                    brightness: 40
                ),
                AccessorySnapshot(
                    id: hallwayLamp,
                    name: "Hallway lamp",
                    room: "Hallway",
                    kind: .light,
                    isReachable: hallwayReachable,
                    isOn: true,
                    brightness: 80
                ),
                AccessorySnapshot(
                    id: frontLock,
                    name: "Front door lock",
                    room: "Entry",
                    kind: .lock,
                    isReachable: true
                ),
                AccessorySnapshot(
                    id: patioDoor,
                    name: "Patio door",
                    room: "Patio",
                    kind: .door,
                    isReachable: true
                ),
                AccessorySnapshot(
                    id: entryAlarm,
                    name: "Entry alarm",
                    room: "Entry",
                    kind: .alarm,
                    isReachable: true
                ),
                AccessorySnapshot(
                    id: hallThermostat,
                    name: "Hall thermostat",
                    room: "Hallway",
                    kind: .heating,
                    isReachable: true
                ),
            ],
            isSimulated: true
        )
    }
}
