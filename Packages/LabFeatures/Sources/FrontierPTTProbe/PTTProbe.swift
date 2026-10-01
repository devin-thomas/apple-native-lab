#if os(iOS)
import UIKit
import PushToTalk
import Foundation

/// Compile-only lifecycle seam. No host links this target; no APNs or audio transport exists.
@MainActor
public enum PTTProbe {
    public static func join(_ manager: PTChannelManager, channel: UUID) {
        manager.requestJoinChannel(channelUUID: channel,
            descriptor: PTChannelDescriptor(name: "Sample channel", image: nil))
    }
    public static func leave(_ manager: PTChannelManager, channel: UUID) {
        manager.leaveChannel(channelUUID: channel)
    }
}
#endif
