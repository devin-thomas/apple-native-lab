import LabCatalog
import LabSupport
import Observation

/// App-wide state for a lab host: the catalog plus what built and runs this binary.
@MainActor
@Observable
final class LabModel {
    let catalog: ExperimentCatalog?
    let catalogError: String?
    let provenance = BuildProvenance.current
    let device = DeviceSnapshot.current
    let featureLevel = FeatureLevel.current

    init() {
        do {
            catalog = try ExperimentCatalog.bundled()
            catalogError = nil
        } catch {
            catalog = nil
            catalogError = String(describing: error)
        }
    }
}
