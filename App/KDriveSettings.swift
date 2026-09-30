import SwiftUI
import UIKit
import WellbeingCore

struct KDriveSettings: View {
    @AppStorage("kDriveToken") private var token = ""
    @AppStorage("kDriveDriveID") private var driveID = ""
    @State private var showsToken = false
    @State private var status: String?
    @State private var testing = false

    private var isComplete: Bool {
        KDriveConfig(token: token, driveID: driveID).isComplete
    }

    var body: some View {
        Group {
            HStack {
                if showsToken {
                    TextField("Jeton API", text: $token)
                } else {
                    SecureField("Jeton API", text: $token)
                }
                Button { showsToken.toggle() } label: {
                    Image(systemName: showsToken ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                Button("Coller") {
                    if let value = UIPasteboard.general.string {
                        token = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .buttonStyle(.borderless)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            TextField("ID du Drive", text: $driveID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numberPad)

            Button {
                testing = true
                Task {
                    let config = KDriveConfig(token: token, driveID: driveID)
                    let result = await KDriveModel().testConnection(for: config)
                    status = result
                    testing = false
                }
            } label: {
                if testing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Tester la connexion")
                }
            }
            .disabled(!isComplete || testing)

            if let status {
                Label(status, systemImage: status.hasPrefix("Connecté") ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(status.hasPrefix("Connecté") ? .green : .orange)
            }
        }
        .onChange(of: token) { _, _ in status = nil }
        .onChange(of: driveID) { _, _ in status = nil }
    }
}
