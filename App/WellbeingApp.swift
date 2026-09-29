import SwiftUI

@main
struct WellbeingApp: App {
    @State private var store = JournalStore()
    @State private var timer = SessionTimer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(timer)
                .tint(.teal)
        }
    }
}

struct RootView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        TabView {
            TimerView().tabItem { Label("Séance", systemImage: "timer") }
            JournalView().tabItem { Label("Journal", systemImage: "book.closed") }
            TrendsView().tabItem { Label("Tendances", systemImage: "chart.xyaxis.line") }
            SettingsView().tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .overlay {
            if scenePhase != .active {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    Label("Wellbeing", systemImage: "leaf.fill").font(.largeTitle).foregroundStyle(.teal)
                }
            }
        }
        .alert("Journal", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("Compris", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
