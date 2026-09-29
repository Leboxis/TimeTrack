import SwiftUI
import WellbeingCore

struct TimerView: View {
    @Environment(JournalStore.self) private var store
    @Environment(SessionTimer.self) private var timer
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
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(durationLabel(timer.draft.elapsed(at: context.date)))
                                .font(.system(size: 64, weight: .light, design: .rounded))
                                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                                .accessibilityLabel("Durée : \(durationLabel(timer.draft.elapsed(at: context.date)))")
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
                        Text("Le journal n’a pas pu être chargé. Fermez puis rouvrez l’app ; le fichier existant n’a pas été modifié.")
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
}
