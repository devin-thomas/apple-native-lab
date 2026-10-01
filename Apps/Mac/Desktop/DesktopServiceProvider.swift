import AppKit
import DesktopNativePower

/// The Services menu handler for selected text. It reads a string and imports it through the
/// same station as Lab › Import Selected Text. It does not interpret the string as a command.
@MainActor
final class DesktopServiceProvider: NSObject {
    static let shared = DesktopServiceProvider()

    static func install() {
        NSApp.servicesProvider = shared
        NSUpdateDynamicServices()
    }

    @objc func importSelectedText(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        guard let text = pasteboard.string(forType: .string) else {
            errorPointer?.pointee = DesktopPowerError.invalidText.description as NSString
            return
        }
        guard let session = DesktopPowerHost.session else {
            errorPointer?.pointee = DesktopPowerError.unavailable.description as NSString
            return
        }
        Task { @MainActor in
            await session.importServiceText(text)
        }
    }
}
