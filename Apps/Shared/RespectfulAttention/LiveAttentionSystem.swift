#if os(iOS) && LAB_PROFILE_SYSTEM_SURFACES
import AlarmKit
import Foundation
import LabDomain
import RespectfulAttention
import SwiftUI
import UserNotifications

/// AlarmKit and local notifications for the SystemSurfaces iPhone build (LAB-043).
///
/// CoreLocal does not compile this file's body, so it never links either framework. Scheduling
/// uses the lab alert's own identifier. Cancel removes those identifiers and does not look for
/// any other alarm. Authorization is requested only when the caller asks; a denied state is read
/// back and not requested again.
struct LiveAttentionSystem: SystemAttentionClient {
    private struct Metadata: AlarmMetadata {
        var reason: String
    }

    func permission() async -> SystemPermission {
        let alarm = mapped(AlarmManager.shared.authorizationState)
        let notes = await notificationPermission()
        if alarm == .denied || notes == .denied { return .denied }
        if alarm == .notDetermined || notes == .notDetermined { return .notDetermined }
        if alarm == .authorized && notes == .authorized { return .authorized }
        return .unavailable
    }

    func requestPermission() async -> SystemPermission {
        let alarm: SystemPermission
        do { alarm = mapped(try await AlarmManager.shared.requestAuthorization()) }
        catch { alarm = .denied }
        let notes = await withCheckedContinuation { (continuation: CheckedContinuation<SystemPermission, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted ? .authorized : .denied)
            }
        }
        if alarm == .denied || notes == .denied { return .denied }
        if alarm == .authorized && notes == .authorized { return .authorized }
        return alarm
    }

    func schedule(_ offer: AttentionOffer) async {
        switch offer.channel {
        case .focusFilter:
            return
        case .reminder:
            let content = UNMutableNotificationContent()
            content.title = "Lab reminder"
            content.body = offer.reason
            content.threadIdentifier = "lab-alert"
            let trigger = UNCalendarNotificationTrigger(dateMatching: offer.moment.dateComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: LabAlertIdentity.notificationID(offer.id), content: content, trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
        case .alarm:
            let alert = alarmAlert(title: offer.reason)
            let presentation = AlarmPresentation(alert: alert)
            let attributes = AlarmAttributes<Metadata>(
                presentation: presentation, metadata: Metadata(reason: offer.reason), tintColor: .accentColor
            )
            let configuration = AlarmManager.AlarmConfiguration<Metadata>.alarm(
                schedule: .fixed(offer.moment.instant(deviceZone: .current)),
                attributes: attributes
            )
            try? await AlarmManager.shared.schedule(id: offer.id.rawValue, configuration: configuration)
        }
    }

    func cancel(labIDs: [AttentionID]) async {
        for id in labIDs {
            try? AlarmManager.shared.cancel(id: id.rawValue)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: labIDs.map(LabAlertIdentity.notificationID)
        )
    }

    private func notificationPermission() async -> SystemPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .unavailable
        }
    }

    private func mapped(_ state: AlarmManager.AuthorizationState) -> SystemPermission {
        switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .unavailable
        }
    }

    private func alarmAlert(title: String) -> AlarmPresentation.Alert {
        let text = LocalizedStringResource(stringLiteral: title)
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: text)
        }
        return AlarmPresentation.Alert(
            title: text,
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        )
    }
}
#endif
