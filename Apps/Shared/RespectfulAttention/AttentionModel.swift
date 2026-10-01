import Foundation
import LabDomain
import Observation
import RespectfulAttention

/// The Respectful Attention page: previews, the in-app agenda, and the one cancel action.
///
/// Scheduling and cancelling go through `AttentionActions`, so the page and the intents share one
/// receipt path. Opening the page does not schedule anything and does not prompt.
@MainActor
@Observable
final class AttentionModel {
    enum Phase: Hashable {
        case notStarted
        case ready
        case unavailable(String)
    }

    static let shared = AttentionModel()
    private static let gateKey = "RespectfulAttention.promptGate"

    private(set) var phase: Phase = .notStarted
    private(set) var stored: [LabAttention] = []
    private(set) var gate: PromptGate
    private(set) var lastMessage: String?
    private(set) var isWorking = false
    var filtersToSampleFocus = false

    @ObservationIgnored private var library: LabLibrary?
    @ObservationIgnored private let system: any SystemAttentionClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let deviceZone: @Sendable () -> TimeZone

    init(
        system: (any SystemAttentionClient)? = nil,
        defaults: UserDefaults = .standard,
        deviceZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.system = system ?? AttentionModel.makeSystem()
        self.defaults = defaults
        self.deviceZone = deviceZone
        if let data = defaults.data(forKey: Self.gateKey), let stored = try? JSONDecoder().decode(PromptGate.self, from: data) {
            gate = stored
        } else {
            gate = PromptGate(permission: .notDetermined)
        }
    }

    var offers: [AttentionOffer] { RespectfulAttention.offers }

    func preview(_ offer: AttentionOffer) -> AttentionPreview {
        offer.preview(deviceZone: deviceZone())
    }

    var permissionNote: String {
        switch gate.permission {
        case .notDetermined where gate.mayPrompt:
            "Alarms and reminders stay off until you allow them. The agenda below works either way."
        case .denied:
            "Notifications stay off. Native Lab will not ask again. The agenda still runs while the app is open."
        case .authorized:
            "Alarms and reminders are allowed for lab alerts only."
        case .unavailable, .notDetermined:
            "This build keeps system alarms and notifications off. The agenda runs in the app."
        }
    }

    func connect(_ library: LabLibrary) { self.library = library }

    func refresh() async {
        guard let library else { return }
        do {
            let stored = try await library.attentions()
            let systemPermission = await system.permission()
            if systemPermission == .denied, gate.permission != .denied {
                gate = PromptGate(permission: .denied, prompts: max(gate.prompts, 1))
                storeGate()
            } else if systemPermission == .unavailable, gate.permission == .notDetermined {
                gate = PromptGate(permission: .unavailable, prompts: gate.prompts)
                storeGate()
            }
            self.stored = stored
            phase = .ready
        } catch {
            phase = .unavailable(error.message)
        }
    }

    func schedule(_ offer: AttentionOffer) async {
        await work {
            guard let backend = self.backend else { throw AttentionError.unavailable("Native Lab is still opening.") }
            let outcome = try await AttentionActions(backend: backend, entryPoint: .appUI)
                .schedule(offer, consent: .explicit)
            if self.gate.permission == .authorized, offer.channel != .focusFilter {
                await self.system.schedule(offer)
            }
            self.lastMessage = outcome.receipt.summary
        }
    }

    /// One prompt, and only while the gate still allows it. A denial is stored and not repeated.
    func allowSystemAlerts() async {
        guard gate.mayPrompt else { return }
        let client = system
        let next = await gate.resolving { await client.requestPermission() }
        gate = next
        storeGate()
        lastMessage = permissionNote
    }

    func cancelAll() async {
        let ids = stored.map(\.id)
        await work {
            guard let backend = self.backend else { throw AttentionError.unavailable("Native Lab is still opening.") }
            let outcome = try await AttentionActions(backend: backend, entryPoint: .appUI).cancelAll()
            await self.system.cancel(labIDs: ids)
            self.lastMessage = outcome.receipt.summary
        }
    }

    func alarmState(for offer: AttentionOffer, systemScheduled: Bool) -> AlarmState {
        AlarmRouting.state(
            channel: offer.channel,
            routeAvailable: gate.permission != .unavailable,
            permission: gate.permission,
            systemScheduled: systemScheduled
        )
    }

    private var backend: LibraryAttentionBackend? {
        library.map { LibraryAttentionBackend(library: $0) }
    }

    private func work(_ body: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await body()
            await refresh()
        } catch let error as AttentionError {
            lastMessage = error.message
            await refresh()
        } catch {
            lastMessage = "Cancelled. Nothing was changed."
        }
    }

    private func storeGate() {
        if let data = try? JSONEncoder().encode(gate) {
            defaults.set(data, forKey: Self.gateKey)
        }
    }

    private static func makeSystem() -> any SystemAttentionClient {
        #if os(iOS) && LAB_PROFILE_SYSTEM_SURFACES
        LiveAttentionSystem()
        #else
        UnavailableAttentionSystem()
        #endif
    }
}

private extension LabLibrary.SubmitFailure {
    var message: String {
        switch self {
        case .unavailable(let reason): reason
        case .refused: "The lab store refused the read."
        }
    }
}
