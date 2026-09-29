#if canImport(os)
import os

/// Writes each diagnostic event to the unified system log as one line.
///
/// The line is `DiagnosticEvent.line`, which holds only fixed names, validated IDs, categories,
/// and numbers, so it is marked public; nothing else is interpolated. Rejections and failures are
/// logged at the default level, everything else at the info level, which the system does not
/// persist by default.
public struct OSLogDiagnosticSink: DiagnosticSink {
    public static let defaultSubsystem = "NativeLab"
    public static let defaultCategory = "diagnostics"

    private let logger: Logger

    /// - Parameters:
    ///   - subsystem: A fixed configuration value, such as the app's bundle identifier. Never
    ///     pass anything derived from user content.
    public init(subsystem: String = OSLogDiagnosticSink.defaultSubsystem, category: String = OSLogDiagnosticSink.defaultCategory) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func receive(_ event: DiagnosticEvent) {
        let line = event.line
        switch event.outcome {
        case .failed, .rejected:
            logger.notice("\(line, privacy: .public)")
        case .started, .succeeded, .cancelled:
            logger.info("\(line, privacy: .public)")
        }
    }
}
#endif
