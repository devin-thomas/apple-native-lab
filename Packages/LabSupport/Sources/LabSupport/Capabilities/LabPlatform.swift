/// The operating system family a binary was compiled for.
///
/// Probe plans are keyed by platform so each target compiles only the frameworks its SDK
/// supports. visionOS is listed for completeness; it is outside the initial plan and has no probes.
public enum LabPlatform: String, CaseIterable, Sendable, Codable {
    case iOS
    case macOS
    case watchOS
    case tvOS
    case visionOS

    /// The platform this binary was compiled for.
    public static var current: LabPlatform {
        #if os(macOS)
        .macOS
        #elseif os(watchOS)
        .watchOS
        #elseif os(tvOS)
        .tvOS
        #elseif os(visionOS)
        .visionOS
        #else
        .iOS
        #endif
    }

    public var title: String { rawValue }
}
