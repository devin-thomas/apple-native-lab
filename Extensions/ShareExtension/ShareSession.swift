import Foundation
import Observation
import ShareIngress

/// One share: the attachments the share sheet handed over, staged in order into the App Group
/// folder, and the result.
///
/// Staging starts as soon as the sheet appears, copies bounded data while the providers' access
/// is valid, and then waits for Done. Cancel stops the current attachment, even one still
/// downloading from the cloud, and removes everything this share had staged before the request
/// is cancelled. Without its App Group container (a build signed by a team that cannot use App
/// Groups) nothing is staged and the sheet says so.
@MainActor
@Observable
final class ShareSession {
    enum Phase: Hashable {
        case staging(count: Int)
        case cancelling
        case finished(IntakeReport)
        /// This build cannot reach the shared folder.
        case unavailable
    }

    enum Finish {
        case done
        case cancelled
    }

    private(set) var phase: Phase

    @ObservationIgnored private let attachments: [ItemProviderAttachment]
    @ObservationIgnored private let station: IngressStation?
    @ObservationIgnored private let finish: (Finish) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?

    init(items: [NSExtensionItem], bundle: Bundle, finish: @escaping (Finish) -> Void) {
        attachments = ItemProviderAttachment.attachments(from: items)
        self.finish = finish
        if let root = IngressArea.shareExtensionRoot(for: bundle),
           let area = try? IngressArea(source: .shareExtension, root: root) {
            station = IngressStation(area: area)
            phase = .staging(count: attachments.count)
        } else {
            station = nil
            phase = .unavailable
        }
    }

    var isFinished: Bool {
        switch phase {
        case .finished, .unavailable: true
        case .staging, .cancelling: false
        }
    }

    func start() {
        guard let station, task == nil else { return }
        let attachments = attachments
        task = Task { [weak self] in
            let report = await station.receive(attachments, via: .shareExtension)
            guard let self else { return }
            if report.wasCancelled {
                finish(.cancelled)
            } else {
                phase = .finished(report)
            }
        }
    }

    func cancel() {
        guard let task, !isFinished else {
            finish(.cancelled)
            return
        }
        phase = .cancelling
        task.cancel()
    }

    func done() {
        finish(.done)
    }
}
