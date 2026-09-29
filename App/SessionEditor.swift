import SwiftUI
import WellbeingCore

struct SessionEditor: View {
    @Environment(\.dismiss) private var dismiss
    // One-time editable copy for this sheet; parent data is only changed on save.
    @State private var session: Session
    @State private var seconds: String
    @State private var saveFailed = false
    @State private var confirmDelete = false
    let onSave: (Session) -> Bool
    /// Provided only when editing a session that already exists in the journal.
    var onDelete: (() -> Void)? = nil

    init(session: Session, onSave: @escaping (Session) -> Bool, onDelete: (() -> Void)? = nil) {
        _session = State(initialValue: session)
        _seconds = State(initialValue: String(Int(session.duration)))
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var duration: Double? { Double(seconds.replacingOccurrences(of: ",", with: ".")) }
    private var valid: Bool {
        guard let duration else { return false }
        var updated = session
        updated.duration = duration
        return updated.isValid
    }

    static let feelingLabels = ["Difficile", "Mitigé", "Neutre", "Bien", "Très bien"]
    static let orgasmLabels = ["Difficile", "Faible", "Correct", "Bon", "Excellent"]
    static let mentalLabels = ["Anxieux", "Agité", "Neutre", "Apaisé", "Serein"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Séance") {
                    DatePicker("Date", selection: $session.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Text("Durée en secondes")
                        TextField("60", text: $seconds).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    if let duration, duration >= 1, duration <= 86_400 {
                        Text(durationLabel(duration)).foregroundStyle(.secondary)
                    } else {
                        Text("Saisissez une durée entre 1 seconde et 24 heures.").font(.caption).foregroundStyle(.red)
                    }
                }
                Section {
                    RatingRow(title: "Ressenti", labels: Self.feelingLabels, value: $session.feeling)
                    RatingRow(title: "Orgasme", labels: Self.orgasmLabels, value: $session.orgasm)
                    RatingRow(title: "Mental", labels: Self.mentalLabels, value: $session.mental)
                } header: {
                    Text("Comment vous sentez-vous ?")
                }
                Section {
                    Picker("Type d’éjaculation", selection: $session.ejaculation) {
                        ForEach(Ejaculation.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Notes personnelles") {
                    TextField("Contexte, énergie, ressenti…", text: $session.notes, axis: .vertical)
                        .lineLimit(4...12)
                    if session.notes.count > 10_000 {
                        Text("Notes trop longues : \(session.notes.count) caractères pour 10 000 maximum.")
                            .font(.caption).foregroundStyle(.red)
                    } else {
                        Text("\(session.notes.count) / 10 000 caractères").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if onDelete != nil {
                    Section {
                        Button("Supprimer cette séance", role: .destructive) { confirmDelete = true }
                    }
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
            .confirmationDialog("Supprimer cette séance ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action est définitive.")
            }
            .privacyMask()
        }
    }
}
