import SwiftUI
import WellbeingCore

struct TimerView: View {
    @Environment(JournalStore.self) private var store
    @Environment(SessionTimer.self) private var timer
    @Environment(\.scenePhase) private var scenePhase
    @State private var draftSession: Session?
    @State private var confirmReset = false
    @State private var savingTimer = false

    private var isRunning: Bool { timer.draft.startedAt != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // The periodic timeline never stopped: a `TabView` keeps its
                    // children alive, so a once-a-second redraw ran for the whole
                    // session, on another tab, with the screen held awake. It now wraps
                    // the dial alone, and only while the scene is frontmost.
                    if scenePhase == .active {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            TimerDial(elapsed: timer.draft.elapsed(at: context.date),
                                      isRunning: isRunning,
                                      animates: true)
                        }
                    } else {
                        TimerDial(elapsed: timer.draft.elapsed(), isRunning: isRunning, animates: false)
                    }

                    Button { timer.toggle() } label: {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(RatingPalette.duration, in: Circle())
                    }
                    .accessibilityLabel(isRunning ? "Mettre en pause" : "Démarrer ou reprendre")

                    Button {
                        timer.pause()
                        savingTimer = true
                        draftSession = Session(duration: max(1, timer.draft.elapsed()))
                    } label: {
                        Label("Terminer et noter", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled((!isRunning && timer.draft.accumulated == 0) || store.loadFailed)

                    Text("Un moment pour vous. Observez votre ressenti, à votre rythme.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack {
                        Button("Réinitialiser", role: .destructive) { confirmReset = true }
                        Spacer()
                        Button("Saisie manuelle") { savingTimer = false; draftSession = Session(duration: 60) }
                            .disabled(store.loadFailed)
                    }.font(.subheadline)

                    Label("Journal personnel • données sur cet appareil", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                    if store.loadFailed {
                        Text("Le journal n’a pas pu être lu en entier. Ouvrez Réglages pour exporter les séances récupérées ou réinitialiser le fichier local.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 24)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .navigationTitle("Séance")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $draftSession) { session in
                SessionEditor(session: session) { saved in
                    if store.save(saved) {
                        if savingTimer { timer.reset() }
                        return true
                    }
                    return false
                }
            }
            .confirmationDialog("Réinitialiser le chronomètre ?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Réinitialiser", role: .destructive) { timer.reset() }
                Button("Annuler", role: .cancel) {}
            }
        }
    }
}
