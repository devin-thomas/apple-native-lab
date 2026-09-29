/// Turns raw readings into gates. Pure, so every rule is testable with a fake source.
enum CapabilityProbes {
    static func gates(
        for capability: Capability,
        on platform: LabPlatform,
        source: any CapabilitySource
    ) async -> [CapabilityGate] {
        var gates = [osAPIGate(for: capability, on: platform)]
        switch capability {
        case .camera:
            gates.append(captureHardwareGate(
                noun: "camera", symbol: capability.probedSymbols(on: platform).last ?? "",
                reading: source.hasCaptureDevice(.video)))
        case .microphone:
            gates.append(captureHardwareGate(
                noun: "microphone", symbol: capability.probedSymbols(on: platform).last ?? "",
                reading: source.hasCaptureDevice(.audio)))
        case .speechRecognition:
            gates += speechGates(await source.speechTranscription())
        case .onDeviceLanguageModel:
            gates += languageModelGates(source.languageModel())
        case .worldTracking:
            gates.append(worldTrackingGate(source.worldTracking()))
        case .sceneReconstruction:
            gates.append(sceneReconstructionGate(source.worldTracking()))
        case .ultraWideband:
            gates.append(ultraWidebandGate(source.ultraWideband()))
        case .bluetooth:
            gates.append(CapabilityGate(.hardware, .unknown,
                "Radio power state is readable only from a CBCentralManager, and creating one can prompt, so it is not read."))
        case .localNetwork:
            break
        }
        if let permission = capability.permission {
            gates.append(permissionGate(permission, source: source))
        }
        if let entitlement = entitlementGate(for: capability, on: platform, source: source) {
            gates.append(entitlement)
        }
        gates.append(.noDeviceEvidence)
        if source.isSimulator && capability.isPhysicalSensor {
            gates = gates.map(simulatedHardware)
        }
        return gates
    }

    /// A simulator can report a sensor as present (the iOS 27 simulator reports Ultra Wideband
    /// precise distance, for one), but that is not hardware. A negative reading still means the
    /// capability cannot run here, so only a positive one becomes unknown.
    static func simulatedHardware(_ gate: CapabilityGate) -> CapabilityGate {
        guard gate.kind == .hardware, gate.state == .met else { return gate }
        return CapabilityGate(.hardware, .unknown,
            "Simulator: \(gate.detail) A simulated reading is not hardware evidence.")
    }

    static func osAPIGate(for capability: Capability, on platform: LabPlatform) -> CapabilityGate {
        guard let framework = capability.framework(on: platform) else {
            return CapabilityGate(.osAPI, .met,
                "Network framework is part of the \(platform.title) SDK. This probe reads no symbol.")
        }
        return CapabilityGate(.osAPI, .met,
            "\(framework) is compiled into this \(platform.title) build and available from the 26.0 floor.")
    }

    static func captureHardwareGate(noun: String, symbol: String, reading: Bool?) -> CapabilityGate {
        switch reading {
        case true?: CapabilityGate(.hardware, .met, "A \(noun) is present (\(symbol)).")
        case false?: CapabilityGate(.hardware, .unmet, "No \(noun) was found (\(symbol)).")
        case nil: CapabilityGate(.hardware, .unknown, "\(noun.capitalized) hardware is not measurable on this platform.")
        }
    }

    static func speechGates(_ reading: SpeechTranscriptionReading) -> [CapabilityGate] {
        let locale = reading.localeIdentifier
        switch reading.transcriberAvailable {
        case nil:
            return [
                CapabilityGate(.hardware, .unknown, "SpeechTranscriber is not compiled for this platform."),
                CapabilityGate(.asset, .unknown, "Not measured."),
            ]
        case false?:
            return [
                CapabilityGate(.hardware, .unmet,
                    "SpeechTranscriber.isAvailable is false: this device does not offer on-device transcription."),
                CapabilityGate(.asset, .unknown, "Not measured on a device without on-device transcription."),
            ]
        case true?:
            let hardware = CapabilityGate(.hardware, .met, "SpeechTranscriber.isAvailable is true.")
            let asset: CapabilityGate = switch reading.asset {
            case .installed:
                CapabilityGate(.asset, .met, "The on-device transcription model for \(locale) is installed.")
            case .downloadable:
                CapabilityGate(.asset, .needsAction,
                    "\(locale) is supported but its model is not installed. A feature action downloads it.")
            case .unsupportedLocale:
                CapabilityGate(.asset, .unmet, "No on-device transcription model exists for \(locale).")
            case .unknown:
                CapabilityGate(.asset, .unknown, "The model state for \(locale) could not be read.")
            }
            return [hardware, asset]
        }
    }

    static func languageModelGates(_ reading: LanguageModelReading) -> [CapabilityGate] {
        let symbol = "SystemLanguageModel.default.availability"
        let locale = reading.localeIdentifier
        var service: CapabilityGate {
            switch reading.supportsCurrentLocale {
            case true?: CapabilityGate(.service, .met, "Apple Intelligence is on and the model supports \(locale).")
            case false?: CapabilityGate(.service, .unmet, "Apple Intelligence is on, but the model does not support \(locale).")
            case nil: CapabilityGate(.service, .unknown, "Language support for \(locale) was not read.")
            }
        }
        switch reading.availability {
        case .available:
            return [
                CapabilityGate(.hardware, .met, "This device is eligible (\(symbol) is .available)."),
                service,
                CapabilityGate(.asset, .met, "The system model is ready."),
            ]
        case .deviceNotEligible:
            return [
                CapabilityGate(.hardware, .unmet, "\(symbol) reports .deviceNotEligible."),
                CapabilityGate(.service, .unknown, "Not reported for an ineligible device."),
                CapabilityGate(.asset, .unknown, "Not reported for an ineligible device."),
            ]
        case .appleIntelligenceNotEnabled:
            return [
                CapabilityGate(.hardware, .met, "This device is eligible; the model reports a setting, not hardware."),
                CapabilityGate(.service, .unmet, "Apple Intelligence is turned off (\(symbol) reports .appleIntelligenceNotEnabled)."),
                CapabilityGate(.asset, .unknown, "Not reported while Apple Intelligence is off."),
            ]
        case .modelNotReady:
            return [
                CapabilityGate(.hardware, .met, "This device is eligible; the model reports an asset state, not hardware."),
                service,
                CapabilityGate(.asset, .unmet,
                    "The model is not ready (\(symbol) reports .modelNotReady). The system may still be downloading it."),
            ]
        case .unrecognized(let reason):
            let detail = "\(symbol) reported \(reason), which this build does not recognize."
            return [
                CapabilityGate(.hardware, .unknown, detail),
                CapabilityGate(.service, .unknown, detail),
                CapabilityGate(.asset, .unknown, detail),
            ]
        case .notCompiled:
            return [CapabilityGate(.hardware, .unknown, "FoundationModels is not compiled for this platform.")]
        }
    }

    static func worldTrackingGate(_ reading: WorldTrackingReading?) -> CapabilityGate {
        switch reading?.worldTracking {
        case true?: CapabilityGate(.hardware, .met, "ARWorldTrackingConfiguration.isSupported is true.")
        case false?: CapabilityGate(.hardware, .unmet,
            "ARWorldTrackingConfiguration.isSupported is false: this device cannot run world tracking.")
        case nil: CapabilityGate(.hardware, .unknown, "ARKit is not compiled for this platform.")
        }
    }

    static func sceneReconstructionGate(_ reading: WorldTrackingReading?) -> CapabilityGate {
        guard let reading else {
            return CapabilityGate(.hardware, .unknown, "ARKit is not compiled for this platform.")
        }
        if reading.worldTracking && reading.sceneReconstruction {
            return CapabilityGate(.hardware, .met, "ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) is true.")
        }
        return CapabilityGate(.hardware, .unmet,
            "ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) is false on this device.")
    }

    static func ultraWidebandGate(_ reading: UltraWidebandReading?) -> CapabilityGate {
        guard let reading else {
            return CapabilityGate(.hardware, .unknown, "Nearby Interaction is not compiled for this platform.")
        }
        guard reading.preciseDistance else {
            return CapabilityGate(.hardware, .unmet,
                "NISession.deviceCapabilities reports no precise distance measurement on this device.")
        }
        let direction = reading.direction ? "and direction" : "without direction"
        return CapabilityGate(.hardware, .met, "NISession.deviceCapabilities reports precise distance \(direction).")
    }

    static func permissionGate(_ permission: PermissionKind, source: any CapabilitySource) -> CapabilityGate {
        if let reason = permission.unreadableReason {
            return CapabilityGate(.permission, .unknown, reason)
        }
        let status = source.permissionStatus(permission)
        let detail = switch status {
        case .authorized: "\(permission.title) access is allowed."
        case .notDetermined: "The lab asks only when an experiment action needs it."
        case .denied: "\(permission.title) access was declined. The alternate route applies, and the lab does not ask again."
        case .restricted: "\(permission.title) access is restricted by device policy. The alternate route applies."
        case .notReadable: "\(permission.title) permission cannot be read on this platform."
        case .unrecognized: "The system returned a \(permission.title) status this build does not recognize."
        }
        return CapabilityGate(.permission, status.gateState, detail)
    }

    static func entitlementGate(
        for capability: Capability,
        on platform: LabPlatform,
        source: any CapabilitySource
    ) -> CapabilityGate? {
        let purposeKeys = [capability.permission?.purposeStringKey].compactMap(\.self)
        let entitlements = capability.requiredEntitlements(on: platform)
        guard !purposeKeys.isEmpty || !entitlements.isEmpty else { return nil }

        var missing = purposeKeys.filter { !source.declaresPurposeString($0) }
        var unreadable: [String] = []
        for key in entitlements {
            switch source.entitlement(key) {
            case .present: break
            case .absent: missing.append(key)
            case .notReadable: unreadable.append(key)
            }
        }
        let required = (purposeKeys + entitlements).joined(separator: ", ")
        if !missing.isEmpty {
            return CapabilityGate(.entitlement, .unmet,
                "This build lacks \(missing.joined(separator: ", ")). An experiment that needs this capability adds them to its own profile.")
        }
        if !unreadable.isEmpty {
            return CapabilityGate(.entitlement, .unknown,
                "The running build's entitlements are not readable here: \(unreadable.joined(separator: ", ")).")
        }
        return CapabilityGate(.entitlement, .met, "This build carries \(required).")
    }
}
