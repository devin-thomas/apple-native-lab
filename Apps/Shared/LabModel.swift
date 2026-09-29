import LabCatalog
import LabSupport
import Observation

/// App-wide state for a lab host: the experiment registry plus what built and runs this binary.
@MainActor
@Observable
final class LabModel {
    let registry: ExperimentRegistry?
    let registryError: String?
    let provenance = BuildProvenance.current
    let device = DeviceSnapshot.current
    let featureLevel = FeatureLevel.current

    init() {
        do {
            registry = try ExperimentRegistry.bundled()
            registryError = nil
        } catch {
            registry = nil
            registryError = String(describing: error)
        }
    }
}
