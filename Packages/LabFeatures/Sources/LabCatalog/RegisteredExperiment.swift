import LabSupport

/// One experiment as a host presents it: the spec's descriptor joined with the build's
/// registration.
///
/// The lifecycle state comes only from the spec, through the descriptor. Nothing here can promote
/// an experiment; a state changes when its spec changes with evidence behind it.
public struct RegisteredExperiment: Sendable, Identifiable, Hashable {
    public let descriptor: ExperimentDescriptor
    public let registration: ExperimentRegistration

    public var id: String { descriptor.id }
    public var title: String { descriptor.title }
    public var category: String { descriptor.category }
    public var milestone: Milestone { descriptor.milestone }
    public var state: ImplementationState { descriptor.state }
    public var moment: String { descriptor.moment }
    public var hosts: String { descriptor.hosts }
    public var primaryAPIs: String { descriptor.primaryAPIs }
    public var dependsOn: [String] { descriptor.dependsOn }
    public var fallback: String { registration.fallback }

    /// The experiment's specification in the public repository.
    public var specification: SourceLink {
        SourceLink(title: "Specification", relativePath: descriptor.specPath)
    }

    /// The build ticket first, then the qualification ticket.
    public var tickets: [SourceLink] {
        descriptor.tickets.map { ticket in
            let role = ticket.hasSuffix("-A") ? "Build ticket" : ticket.hasSuffix("-B") ? "Qualification ticket" : "Ticket"
            return SourceLink(title: "\(role) \(ticket)", relativePath: "tickets/\(ticket).md")
        }
    }

    /// Every source link, specification first.
    public var sourceLinks: [SourceLink] { [specification] + tickets }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.descriptor == rhs.descriptor }
    public func hash(into hasher: inout Hasher) { hasher.combine(descriptor) }
}
