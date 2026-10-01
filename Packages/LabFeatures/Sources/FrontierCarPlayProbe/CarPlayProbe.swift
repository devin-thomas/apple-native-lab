#if os(iOS)
import UIKit
import CarPlay

/// Compile-only audio-category template. Attaching it needs an approved CarPlay host.
@MainActor
public enum CarPlayProbe {
    public static func audioTemplate() -> CPListTemplate {
        let item = CPListItem(text: "Harbor tone", detailText: "Original fixture preview")
        return CPListTemplate(title: "Sample audio", sections: [CPListSection(items: [item])])
    }
}
#endif
