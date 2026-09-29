import LabSupport

/// One statically registered experiment, as described by its specification.
///
/// `state` is copied from the spec's frontmatter. The catalog never promotes an
/// experiment; only a spec change backed by evidence does.
public struct ExperimentDescriptor: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var category: String
    public var milestone: Milestone
    public var state: ImplementationState
    public var dependsOn: [String]
    public var moment: String
    public var hosts: String
    public var primaryAPIs: String
    public var tickets: [String]
    public var specPath: String

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.state == rhs.state }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public enum Milestone: String, Codable, Sendable, CaseIterable, Comparable {
    case m1 = "M1"
    case m2 = "M2"
    case m3 = "M3"
    case m4 = "M4"

    public var title: String {
        switch self {
        case .m1: "First release"
        case .m2: "Ecosystem payoff"
        case .m3: "Spatial and multi-device"
        case .m4: "Gated and commercial"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
