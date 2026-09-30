import SwiftUI
import WellbeingCore

struct TimerView: View {
    @Environment(JournalStore.self) private var store
    @Environment(SessionTimer.self) private var timer
    @Environment(\.scenePhase) private var scenePhase
    @State private var draftSession: Session?
    @State private var confirmReset = false
    @State private var savingTimer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Image(systemName: "leaf.circle.fill").font(.system(size: 48)).foregroundStyle(.teal)
                        Text("Un moment pour vous").font(.title2.bold())
                        Text("Observez votre ressenti, à votre rythme.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 20) {
                        // The periodic timeline never stopped: a `TabView` keeps its
                        // children alive, so a once-a-second redraw ran for the whole
                        // session, on another tab, with the screen held awake.
                        if scenePhase == .active {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                elapsedLabel(at: context.date)
                            }
                        } else {
                            elapsedLabel(at: Date())
                        }
                        Text(timer.draft.startedAt == nil ? "À votre rythme" : "Séance en cours")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            timer.toggle()
                        } label: {
                            Label(timer.draft.startedAt == nil ? "Démarrer / reprendre" : "Pause",
                                  systemImage: timer.draft.startedAt == nil ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)

                        Button {
                            timer.pause()
                            savingTimer = true
                            draftSession = Session(duration: max(1, timer.draft.elapsed()))
                        } label: {
                            Label("Terminer et noter", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .disabled((timer.draft.startedAt == nil && timer.draft.accumulated == 0) || store.loadFailed)
                    }
                    .padding(24).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))

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
                }.padding(.horizontal, 20).padding(.bottom, 24)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .navigationTitle("Wellbeing")
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

    private func elapsedLabel(at date: Date) -> some View {
        let label = durationLabel(timer.draft.elapsed(at: date))
        return Text(label)
            .font(.system(size: 64, weight: .light, design: .rounded))
            .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            .accessibilityLabel("Durée : \(label)")
    }
}
