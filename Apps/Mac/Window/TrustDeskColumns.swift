import SwiftUI
import TrustDesk

/// Trust Desk in the Mac window. The content column is the identity, the local grant, and the
/// sealed record. The detail column is the passkey simulation, so the two are not one control.
struct TrustDeskListColumn: View {
    @Bindable var window: MainWindowState
    var session: TrustDeskSession

    var body: some View {
        TrustDeskForm(session: session) { record in
            window.inspect(record)
        }
    }
}

struct TrustDeskDetailColumn: View {
    var session: TrustDeskSession

    var body: some View {
        List {
            Section {
                Text("Local authorization unlocks one record in this app. It expires, and it can be revoked. A biometric failure leaves the record, the secret, and any earlier grant as they were. Confirm locally is the recovery, and it is not a passkey.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Unlocking this app")
            }
            Section {
                Text(session.passkeyLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The simulation registers and authenticates against \(TrustDeskFixture.relyingPartyID). The user handle is the identity, so a display-name change does not replace the credential. The private material cannot be exported.")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("A passkey")
            }
        }
        .navigationTitle("How they differ")
    }
}
