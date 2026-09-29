import SwiftUI
import WellbeingCore

struct SessionEditor: View {
    @Environment(\.dismiss) private var dismiss
    // One-time editable copy for this sheet; parent data is only changed on save.
    @State private var session: Session
    @State private var seconds: String
    @State private var saveFailed = false
    let onSave: (Session) -> Bool

    init(session: Session, onSave: @escaping (Session) -> Bool) {
        _session = State(initialValue: session)
        _seconds = State(initialValue: String(Int(session.duration)))
        self.onSave = onSave
    }

    private var duration: Double? { Double(seconds.replacingOccurrences(of: ",", with: ".")) }
    private var valid: Bool {
        guard let duration else { return false }
        var updated = session
        updated.duration = duration
        return updated.isValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Séance") {
                    DatePicker("Date", selection: $session.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Text("Durée en secondes")
                        TextField("60", text: $seconds).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    if let duration, duration > 0, duration <= 86_400 {
                        Text(durationLabel(duration)).foregroundStyle(.secondary)
                    } else {
                        Text("Saisissez une durée entre 1 seconde et 24 heures.").font(.caption).foregroundStyle(.red)
                    }
                }
                Section {
                    Picker("Ressenti", selection: $session.feeling) {
                        Text("1 · Difficile").tag(1)
                        Text("2 · Mitigé").tag(2)
                        Text("3 · Neutre").tag(3)
                        Text("4 · Bien").tag(4)
                        Text("5 · Très bien").tag(5)
                    }
                } header: { Text("Comment vous sentez-vous ?") }
                Section("Notes personnelles") {
                    TextField("Contexte, énergie, ressenti…", text: $session.notes, axis: .vertical)
                        .lineLimit(4...12)
                    Text("\(session.notes.count) / 10 000 caractères").font(.caption).foregroundStyle(.secondary)
                }
                if saveFailed {
                    Text("Enregistrement impossible. Vos modifications restent affichées ; réessayez.").foregroundStyle(.red)
                }
            }
            .navigationTitle("Votre séance").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        guard let duration, valid else { return }
                        session.duration = duration
                        if onSave(session) { dismiss() } else { saveFailed = true }
                    }.disabled(!valid)
                }
            }
            .interactiveDismissDisabled()
        }
    }
}
