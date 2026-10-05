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
    @State private var reddit = RedditSession.shared
    @State private var syncModel = FeedModel()
    @State private var syncStatus: String?
    @State private var loginPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                }
                Section {
                    Label(reddit.hasSession ? "Session Reddit détectée" : "Reddit · sans session",
                          systemImage: reddit.hasSession ? "checkmark.shield.fill" : "person.crop.circle.badge.questionmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(reddit.hasSession ? Color.green : Color.secondary)
                    if let account = reddit.account {
                        LabeledContent("Connecté en tant que", value: account.username)
                    }
                    Button {
                        syncStatus = nil
                        Task {
                            await syncModel.refreshSavedIDs(force: true)
                            // The button used to press, fire a request and show
                            // nothing at all: a successful sync and a no-op were
                            // indistinguishable.
                            syncStatus = syncModel.savedIDs.isEmpty
                                ? "Aucune sauvegarde synchronisée."
                                : "\(syncModel.savedIDs.count) sauvegarde(s) synchronisée(s)."
                        }
                    } label: {
                        if syncModel.refreshingSaved {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Synchronisation…")
                            }
                        } else {
                            Text("Synchroniser mes sauvegardes Reddit")
                        }
                    }
                    .disabled(!reddit.hasSession || syncModel.refreshingSaved)
                    if let syncStatus {
                        Text(syncStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(reddit.hasSession ? "Ouvrir Reddit" : "Se connecter à Reddit") {
                        loginPresented = true
                    }
                    .disabled(reddit.clearing)
                    Button("Se déconnecter de Reddit", role: .destructive) {
                        Task { await reddit.logout() }
                    }
                    .disabled(!reddit.hasSession || reddit.clearing)
                } header: {
                    Text("Reddit")
                } footer: {
                    Text("Session conservée dans le magasin de cookies du système, jamais dans les données de l’app. Elle donne accès à ton compte entier, pas seulement à la lecture. « Se déconnecter » l’efface.")
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
            .fullScreenCover(isPresented: $loginPresented) { RedditLoginView() }
        }
    }
}
