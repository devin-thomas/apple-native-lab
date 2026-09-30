import LabSupport

// State is always a word plus a symbol on this host, never color alone. The symbols match the
// Mac and iPhone hosts, so the same state looks the same on every screen.

extension ImplementationState {
    var symbolName: String {
        switch self {
        case .specified: "doc.text"
        case .spiked: "flask"
        case .implemented: "hammer"
        case .deviceVerified: "checkmark.seal"
        case .releaseReady: "shippingbox"
        case .blocked: "exclamationmark.octagon"
        }
    }
}

extension CapabilityReadiness {
    var symbolName: String {
        switch self {
        case .available: "checkmark.circle"
        case .needsAction: "hand.tap"
        case .unknown: "questionmark.circle"
        case .denied: "hand.raised.slash"
        case .unavailable: "xmark.octagon"
        }
    }
}

extension GateState {
    var symbolName: String {
        switch self {
        case .met: "checkmark.circle.fill"
        case .needsAction: "hand.tap"
        case .denied: "hand.raised.slash"
        case .restricted: "lock"
        case .unmet: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

extension CapabilityGate {
    /// The gate's state in words, as the Mac and iPhone hosts phrase it.
    var stateTitle: String {
        switch (kind, state) {
        case (.verification, .unknown): "No device evidence"
        case (.permission, .needsAction): "Not asked yet"
        case (.asset, .needsAction): "Download needed"
        case (_, .met): "Met"
        case (_, .needsAction): "Needs action"
        case (_, .denied): "Denied"
        case (_, .restricted): "Restricted"
        case (_, .unmet): "Not met"
        case (_, .unknown): "Unknown"
        }
    }
}
