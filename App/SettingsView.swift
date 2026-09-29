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
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Wellbeing", systemImage: "leaf.fill").font(.title2).foregroundStyle(.teal)
                    Text("Votre journal personnel, simplement.").foregroundStyle(.secondary)
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                }
                if store.loadFailed {
                    Section {
                        LoadFailureNotice()
                    } header: {
                        Text("Lecture partielle")
                    } footer: {
                        Text("Réinitialiser remplace définitivement le fichier local par un journal vide. Exportez d’abord si les séances récupérées vous intéressent.")
                    }
                }
                Section("Vos données") {
                    LabeledContent("Séances enregistrées", value: "\(store.sessions.count)")
                    Button {
                        document = CSVDocument(text: Journal.csv(store.sessions))
                        exporting = true
                    } label: { Label("Exporter en CSV", systemImage: "square.and.arrow.up") }
                    .disabled(store.sessions.isEmpty)
                    Text("L’export contient vos notes personnelles. Choisissez un emplacement qui vous convient.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Confidentialité") {
                    Label("Sans compte, publicité ni suivi", systemImage: "person.crop.circle.badge.checkmark")
                    Text("L’app n’envoie aucune donnée à un serveur. Le journal reste dans son espace local et peut être inclus dans les sauvegardes de votre appareil. Exportez-le avant de désinstaller l’app ou son conteneur.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    if store.loadFailed {
                        Button("Réinitialiser le journal local", role: .destructive) { confirmReset = true }
                    }
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
            .confirmationDialog("Réinitialiser le journal ?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Réinitialiser", role: .destructive) {
                    if store.resetJournal() { timer.reset() }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Le fichier local sera remplacé par un journal vide. Les \(store.sessions.count) séance(s) récupérée(s) seront perdues : exportez-les d’abord.")
            }
        }
    }
}
