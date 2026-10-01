import AudioWorkshop
import CoreAudioKit
import Observation
import SwiftUI

/// The AUv3 extension's principal class (LAB-029). A host asks it for the workshop's filter and
/// gain as an effect, and shows its view. The unit is the same `WorkshopAudioUnit` the app hosts
/// in-process, with the same C kernel; the extension opens no store, writes no file, and records
/// nothing. A host saves the unit's preset with its own project through `fullState`.
public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnit: WorkshopAudioUnit?
    private var hosting: UIHostingController<AudioUnitControls>?

    /// A host may call this on any thread; the unit is created and the view updated on the main thread.
    nonisolated public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        // The closures return the concrete unit, which is Sendable; `AUAudioUnit` itself is not.
        let make = { @MainActor () throws -> WorkshopAudioUnit in
            let unit = try WorkshopAudioUnit(componentDescription: componentDescription, options: [])
            self.audioUnit = unit
            if self.isViewLoaded { self.show(unit) }
            return unit
        }
        if Thread.isMainThread {
            return try MainActor.assumeIsolated { try make() }
        }
        return try DispatchQueue.main.sync { try MainActor.assumeIsolated { try make() } }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        if let audioUnit { show(audioUnit) }
    }

    private func show(_ unit: WorkshopAudioUnit) {
        hosting?.view.removeFromSuperview()
        hosting?.removeFromParent()
        let controller = UIHostingController(rootView: AudioUnitControls(model: UnitParameters(unit: unit)))
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        hosting = controller
    }
}

/// The unit's parameters as observable values. A host's automation arrives through a parameter
/// observer on any thread and is applied on the main actor.
@MainActor
@Observable
final class UnitParameters {
    private(set) var values: [String: Double] = [:]
    @ObservationIgnored private let unit: WorkshopAudioUnit
    @ObservationIgnored private var token: AUParameterObserverToken?

    init(unit: WorkshopAudioUnit) {
        self.unit = unit
        refresh()
        token = unit.parameterTree?.token(byAddingParameterObserver: { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        })
    }

    var parameters: [AUParameter] { unit.parameterTree?.allParameters ?? [] }

    func refresh() {
        for parameter in parameters { values[parameter.identifier] = Double(parameter.value) }
    }

    func set(_ parameter: AUParameter, _ value: Double) {
        parameter.setValue(AUValue(value), originator: token)
        values[parameter.identifier] = value
    }
}

struct AudioUnitControls: View {
    let model: UnitParameters

    var body: some View {
        Form {
            Section {
                ForEach(model.parameters, id: \.address) { parameter in
                    row(parameter)
                }
            } header: {
                Text(WorkshopAudioUnit.componentName)
            } footer: {
                Text("The Native Lab Audio Workshop's low-pass filter and gain. Your host saves these settings with its project.")
            }
        }
    }

    @ViewBuilder private func row(_ parameter: AUParameter) -> some View {
        let value = model.values[parameter.identifier] ?? Double(parameter.value)
        if parameter.unit == .boolean {
            Toggle(parameter.displayName, isOn: Binding(get: { value >= 0.5 }, set: { model.set(parameter, $0 ? 1 : 0) }))
        } else {
            VStack(alignment: .leading) {
                LabeledContent(parameter.displayName, value: parameter.string(fromValue: nil))
                Slider(value: Binding(get: { value }, set: { model.set(parameter, $0) }),
                       in: Double(parameter.minValue)...Double(parameter.maxValue)) { Text(parameter.displayName) }
                    .accessibilityValue(parameter.string(fromValue: nil))
            }
        }
    }
}
