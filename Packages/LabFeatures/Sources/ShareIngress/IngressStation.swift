import Foundation
import LabDomain
import LabStaging

/// Stages one intake, attachment by attachment, into one `IngressArea`, and records where each
/// came from.
///
/// This is all the share extension does before it finishes, and it is how the host's paste,
/// file-picker, and drop fallbacks import too. It never opens the store, adopts anything, or
/// issues a grant: adoption is a separate, explicit step in the host (`ImportAdopter` through
/// the one `OperationService`).
///
/// - Each attachment becomes its own staged import, in the source's order, with an origin that
///   records the intake, its position, and the declared type. So one malformed, oversized, or
///   unreadable attachment is refused on its own, and never blocks the others or a later intake.
/// - Content is data. Nothing in it is interpreted, and nothing in it can choose what happens next.
/// - An intake of more attachments than `ImportLimits.maximumFiles`, or with files together larger
///   than `maximumTotalBytes`, is refused, the first before anything is read.
/// - Cancelling the intake's task stops the current attachment between chunks (or, for a slow or
///   cloud-backed provider, at once), removes its partial copy, and then removes everything this
///   intake staged, so a cancelled share leaves nothing behind. A later intake is unaffected.
public struct IngressStation: Sendable {
    public let area: IngressArea
    private let diagnostics: DiagnosticsLog?
    private let now: @Sendable () -> Date

    public init(area: IngressArea, diagnostics: DiagnosticsLog? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.area = area
        self.diagnostics = diagnostics
        self.now = now
    }

    public var limits: ImportLimits { area.staging.limits }

    public func receive(_ sources: [any AttachmentSource], via surface: IngressSurface) async -> IntakeReport {
        let clock = ContinuousClock()
        let start = clock.now
        let report = await receiveChecked(sources, via: surface)
        var counts: [DiagnosticName: Int] = [
            "attachments": sources.count, "staged": report.stagedCount,
            "duplicates": report.duplicateCount, "refused": report.refusedCount,
        ]
        if report.wasCancelled { counts["cancelled"] = 1 }
        if let refusal = report.refusal {
            diagnostics?.record("ingress.receive", failure: refusal, subject: IngressArea.subject, duration: clock.now - start, counts: counts)
        } else if report.wasCancelled {
            diagnostics?.record("ingress.receive", failure: ImportRejection.cancelled, subject: IngressArea.subject,
                                duration: clock.now - start, counts: counts)
        } else {
            diagnostics?.record("ingress.receive", outcome: .succeeded, subject: IngressArea.subject, duration: clock.now - start, counts: counts)
        }
        return report
    }

    private func receiveChecked(_ sources: [any AttachmentSource], via surface: IngressSurface) async -> IntakeReport {
        let batch = BatchID()
        func refused(_ rejection: ImportRejection) -> IntakeReport {
            IntakeReport(batch: batch, surface: surface, source: area.source, refusal: rejection, outcomes: [], wasCancelled: false)
        }
        guard area.source.accepts(surface) else { return refused(.notAuthorized) }
        guard !sources.isEmpty else { return refused(.emptyContent) }
        guard sources.count <= limits.maximumFiles else { return refused(.tooManyFiles(limit: limits.maximumFiles)) }

        let receivedAt = now()
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "ShareIngress-\(batch)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch {
            return refused(.stagingUnavailable)
        }
        defer { try? FileManager.default.removeItem(at: scratch) }

        var outcomes: [AttachmentOutcome] = []
        var newlyStaged: [StagingID] = []
        var budget = limits.maximumTotalBytes
        for (index, source) in sources.enumerated() {
            let position = index + 1
            guard !Task.isCancelled else { break }
            let result: AttachmentResult
            do throws(ImportRejection) {
                let loaded = try await source.load(budget: budget, scratch: scratch)
                guard !Task.isCancelled else { throw .cancelled }
                let staged: StagingOutcome
                switch loaded {
                case .text(let bytes):
                    staged = try await area.staging.stageText(utf8: bytes)
                case .link(let url, let title):
                    staged = try await area.staging.stageLink(url, title: title)
                case .file(let file, let byteCount):
                    guard byteCount <= budget else { throw .totalSizeTooLarge(limit: limits.maximumTotalBytes) }
                    staged = try await area.staging.stageFiles([file])
                    budget -= byteCount
                }
                switch staged {
                case .staged(let id):
                    newlyStaged.append(id)
                    result = .staged(id)
                case .duplicate(let id):
                    result = .duplicate(id)
                }
                if let origin = ImportOrigin(
                    stagingID: staged.id, surface: surface, receivedAt: receivedAt, batch: batch,
                    position: position, count: sources.count, contentType: source.contentType
                ) {
                    area.origins.record(origin)
                }
            } catch .cancelled {
                result = .cancelled
            } catch .totalSizeTooLarge {
                // Name this folder's limit, which may be stricter than the standard one.
                result = .refused(.totalSizeTooLarge(limit: limits.maximumTotalBytes))
            } catch {
                result = .refused(error.repositioned(position))
            }
            outcomes.append(AttachmentOutcome(position: position, contentType: source.contentType, result: result))
        }

        guard Task.isCancelled || outcomes.contains(where: { $0.result == .cancelled }) else {
            return IntakeReport(batch: batch, surface: surface, source: area.source, refusal: nil, outcomes: outcomes, wasCancelled: false)
        }
        // Cancelled: remove what this intake staged. Imports that were already waiting before it
        // (duplicates) stay, with the origin they already had.
        for id in newlyStaged {
            try? await area.staging.discard(id)
            if area.origins.origin(for: id)?.batch == batch { area.origins.remove(id) }
        }
        let cancelled = sources.enumerated().map { index, source in
            AttachmentOutcome(position: index + 1, contentType: source.contentType, result: .cancelled)
        }
        return IntakeReport(batch: batch, surface: surface, source: area.source, refusal: nil, outcomes: cancelled, wasCancelled: true)
    }
}
