import LabDomain

/// LAB-011 Model Routing Observatory: see where a request would run, what may leave the device,
/// and why a larger model is or is not available.
///
/// Local-only is the default policy. Private Cloud Compute eligibility is modeled separately from
/// on-device model availability. A cloud request is never sent without an explicit consent grant
/// and an open entitlement gate. Exhausted quota falls back to local generation or a manual
/// workflow; it never switches to a paid third-party provider.
public enum ModelRouting {
    public static let experimentID = "LAB-011"
    public static let title = "Model Routing Observatory"
    public static let symbol = "arrow.triangle.branch"

    /// Every observatory read and proposal uses the model-tool adapter (ADR-011): it can never
    /// commit. Commits that finish the local fallback go through the host as the app UI.
    public static let proposer = ActorScope(adapter: .modelTool, grants: [.read, .propose])

    static let diagnosticSubject = DiagnosticSubject("LAB-011")!

    /// The managed entitlement Apple assigns for Private Cloud Compute. CoreLocal does not carry
    /// it; CloudOptional would, after program enrollment and account assignment ([S07]).
    public static let pccEntitlement = "com.apple.developer.private-cloud-compute"
}
