/// What the build itself declares about one experiment, compiled in rather than loaded (ADR-010).
///
/// The spec-generated descriptor says what the experiment is and which state its spec claims. The
/// registration adds what a host needs before any module exists: the declared fallback route,
/// which stays usable when the live adapter is unavailable. Every descriptor needs exactly one
/// registration, and `ExperimentRegistry` refuses to load otherwise.
///
/// When an experiment gains a module, its registration is where the host learns about it. Nothing
/// is ever registered at run time, and no registration names code to load.
public struct ExperimentRegistration: Sendable, Hashable {
    public let id: String
    /// The first paragraph of the spec's Fallback section, verbatim. A test compares every entry
    /// with its spec, so the spec stays the source of truth.
    public let fallback: String

    public init(_ id: String, fallback: String) {
        self.id = id
        self.fallback = fallback
    }
}
