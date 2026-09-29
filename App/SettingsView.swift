import SwiftUI
import UniformTypeIdentifiers
import WellbeingCore

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(("\u{FEFF}" + text).utf8))
    }
}

struct SettingsView: View {
    @Environment(JournalStore.self) private var store
    @Environment(SessionTimer.self) private var timer
    @State private var exporting = false
    @State private var document = CSVDocument(text: "")
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Wellbeing", systemImage: "leaf.fill").font(.title2).foregroundStyle(.teal)
                    Text("Votre journal personnel, simplement.").foregroundStyle(.secondary)
                    LabeledContent("Version", value: "1.0.0")
                }
                Section("Vos données") {
                    LabeledContent("Séances enregistrées", value: "\(store.sessions.count)")
                    Button {
                        document = CSVDocument(text: Journal.csv(store.sessions))
                        exporting = true
                    } label: { Label("Exporter en CSV", systemImage: "square.and.arrow.up") }
                    .disabled(store.sessions.isEmpty || store.loadFailed)
                    Text("L’export contient vos notes personnelles. Choisissez un emplacement qui vous convient.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Confidentialité") {
                    Label("Sans compte, publicité ni suivi", systemImage: "person.crop.circle.badge.checkmark")
                    Text("L’app n’envoie aucune donnée à un serveur. Le journal reste dans son espace local et peut être inclus dans les sauvegardes de votre appareil. Exportez-le avant de désinstaller l’app ou son conteneur.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Effacer le journal et le chronomètre", role: .destructive) { confirmErase = true }
                        .disabled(store.loadFailed)
                }
            }
            .navigationTitle("Réglages")
            .fileExporter(isPresented: $exporting, document: document,
                          contentType: .commaSeparatedText, defaultFilename: "wellbeing-journal") { result in
                if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
            }
            .confirmationDialog("Effacer toutes les données ?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) {
                    if store.deleteAll() { timer.reset() }
                }
                Button("Annuler", role: .cancel) {}
            } message: { Text("Cette action est définitive. Exportez votre journal si vous souhaitez en conserver une copie.") }
        }
    }
}
