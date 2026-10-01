import Foundation
import Synchronization

/// Reads homes and applies selected light changes. The fictional source is the CoreLocal path.
/// A live source is optional and stops when permission is revoked.
public protocol HomeAccessSource: Sendable {
    var permission: HomePermission { get async }
    /// Asks for home access. Simulated sources stay authorized for the fictional home only.
    func requestAccess() async -> HomePermission
    func homes(on route: HomeRoute) async throws(HomeSceneError) -> [HomeSnapshot]
    func apply(_ change: LightChange, to accessory: AccessorySnapshot, in home: HomeSnapshot) async throws(HomeSceneError) -> AccessoryOutcome
}

/// Deterministic fictional home. Permission is always authorized for the simulated route; live
/// mode is refused unless a separate live source is supplied.
public final class FictionalHomeSource: HomeAccessSource, @unchecked Sendable {
    private let state: Mutex<HomeSnapshot>

    public init(hallwayReachable: Bool = false) {
        state = Mutex(FictionalHome.snapshot(hallwayReachable: hallwayReachable))
    }

    public var permission: HomePermission { .authorized }

    public func requestAccess() async -> HomePermission { .authorized }

    public func homes(on route: HomeRoute) async throws(HomeSceneError) -> [HomeSnapshot] {
        switch route {
        case .simulated:
            return [state.withLock { $0 }]
        case .live:
            throw .liveUnavailable("Live HomeKit is not linked in this CoreLocal build. Use the fictional home.")
        }
    }

    public func apply(
        _ change: LightChange,
        to accessory: AccessorySnapshot,
        in home: HomeSnapshot
    ) async throws(HomeSceneError) -> AccessoryOutcome {
        _ = home
        guard accessory.kind == .light else {
            return .failed(accessory.id, "“\(accessory.name)” is not a light. Nothing was changed for it.")
        }
        guard !accessory.isExcludedByDefault else {
            return .failed(accessory.id, "“\(accessory.name)” is excluded by default. Nothing was changed for it.")
        }
        guard accessory.isReachable else {
            return .failed(accessory.id, "“\(accessory.name)” is disconnected. Nothing was changed for it.")
        }
        if change.isEmpty {
            return .failed(accessory.id, "No change was selected for “\(accessory.name)”.")
        }
        if let brightness = change.brightness, !(0...100).contains(brightness) {
            throw .invalidInput("Brightness must be between 0 and 100.")
        }
        state.withLock { snapshot in
            guard let index = snapshot.accessories.firstIndex(where: { $0.id == accessory.id }) else { return }
            let current = snapshot.accessories[index]
            let next = AccessorySnapshot(
                id: current.id,
                name: current.name,
                room: current.room,
                kind: current.kind,
                isReachable: current.isReachable,
                isOn: change.isOn ?? current.isOn,
                brightness: change.brightness ?? current.brightness
            )
            var accessories = snapshot.accessories
            accessories[index] = next
            snapshot = HomeSnapshot(
                id: snapshot.id,
                name: snapshot.name,
                accessories: accessories,
                isSimulated: true
            )
        }
        return .succeeded(accessory.id, "“\(accessory.name)” → \(change.summary).")
    }
}

/// A source that reports a fixed permission sequence. Used to prove revoked access stops live mode.
public final class ScriptedPermissionSource: HomeAccessSource, @unchecked Sendable {
    private let inner: FictionalHomeSource
    private let permissions: Mutex<[HomePermission]>
    private let current: Mutex<HomePermission>

    public init(permissions: [HomePermission], hallwayReachable: Bool = false) {
        precondition(!permissions.isEmpty)
        inner = FictionalHomeSource(hallwayReachable: hallwayReachable)
        self.permissions = Mutex(permissions)
        current = Mutex(.notDetermined)
    }

    public var permission: HomePermission { current.withLock { $0 } }

    public func requestAccess() async -> HomePermission {
        let next = permissions.withLock { queue -> HomePermission in
            if queue.isEmpty { return current.withLock { $0 } }
            return queue.removeFirst()
        }
        current.withLock { $0 = next }
        return next
    }

    /// Advances to the next scripted permission without a request, for revocation mid-session.
    public func revokeTo(_ permission: HomePermission) {
        current.withLock { $0 = permission }
    }

    public func homes(on route: HomeRoute) async throws(HomeSceneError) -> [HomeSnapshot] {
        if route == .live && !permission.allowsLiveMode {
            throw .permissionRevoked(permission)
        }
        if route == .live {
            // Same accessories as the fixture, labeled not simulated, for live-mode tests without HomeKit.
            let home = FictionalHome.snapshot(hallwayReachable: true)
            return [
                HomeSnapshot(
                    id: home.id,
                    name: home.name + " (live stand-in)",
                    accessories: home.accessories,
                    isSimulated: false
                ),
            ]
        }
        return try await inner.homes(on: .simulated)
    }

    public func apply(
        _ change: LightChange,
        to accessory: AccessorySnapshot,
        in home: HomeSnapshot
    ) async throws(HomeSceneError) -> AccessoryOutcome {
        if !home.isSimulated && !permission.allowsLiveMode {
            throw .permissionRevoked(permission)
        }
        return try await inner.apply(change, to: accessory, in: home)
    }
}
