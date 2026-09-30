import LabCatalog
import LabSupport

/// What the Apple TV host knows without asking anything: the catalog bundled with this build,
/// the build's own provenance, and a coarse description of this Apple TV.
///
/// Every value is read once at launch from the bundle and the operating system. None of it is
/// live: the catalog is a snapshot taken when this build was made, and the screens say so.
struct TVHost: Sendable {
    let provenance: BuildProvenance
    let device: DeviceSnapshot
    let featureLevel: TVFeatureLevel
    /// `nil` when the bundled catalog failed to load; `catalogProblem` then says why.
    let registry: ExperimentRegistry?
    let catalogProblem: String?

    static func load() -> TVHost {
        let registry: ExperimentRegistry?
        let problem: String?
        do {
            registry = try ExperimentRegistry.bundled()
            problem = nil
        } catch {
            registry = nil
            problem = String(describing: error)
        }
        return TVHost(
            provenance: .current,
            device: .current,
            featureLevel: .current,
            registry: registry,
            catalogProblem: problem
        )
    }
}

/// Which generation of platform adapters this binary was compiled with (ADR-009).
///
/// `LAB_SDK_27` is set by Config/Base.xcconfig only when building against a 27 SDK, so an older
/// Xcode still builds the 26-family host with the newer adapters compiled out.
enum TVFeatureLevel: String, Sendable {
    case sdk27 = "27 SDK: newer adapters available"
    case compatibility = "26-family compatibility: newer adapters compiled out"

    static var current: TVFeatureLevel {
        #if LAB_SDK_27
        .sdk27
        #else
        .compatibility
        #endif
    }
}
