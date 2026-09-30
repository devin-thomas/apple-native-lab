import SwiftUI
import UIKit

/// The share extension's principal class (LAB-007).
///
/// It hosts the sheet, stages what was shared into the App Group folder through
/// `IngressStation`, and completes the request. It never opens the lab store, adopts anything,
/// or assumes the app is running: the app reads the folder the next time it shows its inbox.
final class ShareViewController: UIViewController {
    private var session: ShareSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let session = ShareSession(items: items, bundle: .main) { [weak self] finish in
            self?.complete(finish)
        }
        self.session = session
        let host = UIHostingController(rootView: ShareSheetView(session: session))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        session.start()
    }

    private func complete(_ finish: ShareSession.Finish) {
        switch finish {
        case .done:
            extensionContext?.completeRequest(returningItems: nil)
        case .cancelled:
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
