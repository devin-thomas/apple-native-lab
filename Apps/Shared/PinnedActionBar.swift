import SwiftUI

#if os(iOS)
/// A screen's primary action, pinned above the tab bar so it stays reachable however long the
/// page is. Its text grows with Dynamic Type up to accessibility size 2 and then holds, like a
/// toolbar; the large content viewer shows the label at the person's full size on a long press.
struct PinnedActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityShowsLargeContentViewer()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
    }
}
#endif
