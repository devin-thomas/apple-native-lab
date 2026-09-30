import AppKit
import Foundation
import LabDomain
import PortableObjects
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-008's export preview as assistive technology reads it, rendered in the running app and read
/// through AppKit's accessibility getters and legacy attribute requests.
///
/// In-process reads do not take the path an assistive app's out-of-process requests take. A label
/// on selectable text looped only on that path and crashed the app (LAB-008-A); it was found and
/// its fix confirmed by walking the live app from outside, which this test cannot do.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct PortableObjectsAccessibilityTests {
    private static var preview: ExportPreview {
        get throws {
            let document = try LabDocument(decoding: try #require(PortableSample.data))
            let item = LabItem(
                id: document.itemID, collectionID: CollectionID(), title: try EntityTitle(document.title),
                extras: try DocumentMapping.itemContent(of: document).extras
            )
            return try ExportPreview(item: item, collection: nil)
        }
    }

    /// Reads every element's title, description, help, and value the way an assistive app does
    /// through `AXUIElementCopyAttributeValue`, which reaches `accessibilityAttributeValue:`.
    private func readAsAssistiveClient(_ root: NSObject, depth: Int = 0) -> Int {
        guard depth < 40 else { return 0 }
        var count = 1
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        for attribute in ["AXRole", "AXTitle", "AXDescription", "AXHelp", "AXValue", "AXTitleUIElement"] where root.responds(to: getter) {
            _ = root.perform(getter, with: attribute)
        }
        for child in (root.value(forKey: "accessibilityChildren") as? [NSObject]) ?? [] {
            count += readAsAssistiveClient(child, depth: depth + 1)
        }
        return count
    }

    @Test(arguments: [320.0, 420.0, 560.0, 900.0])
    func theExportPreviewCanBeReadWholeAtEveryWidth(width: Double) async throws {
        let hosted = HostedView(ExportPreviewView(preview: try Self.preview), size: CGSize(width: width, height: 1_400))
        defer { hosted.close() }
        let tree = try await hosted.tree()
        #expect(tree.buttons.contains { $0.label == "Export…" })
        #expect(readAsAssistiveClient(hosted.root) > 10)
    }
}
