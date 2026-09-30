import SwiftUI

@main
struct WellbeingApp: App {
    @State private var store = JournalStore()
    @State private var timer = SessionTimer()
    /// Set while a full-screen feed is on screen so the tab bar stops stealing height.
    @State private var hidesTabBar = false

    var body: some Scene {
        WindowGroup {
            RootView(hidesTabBar: $hidesTabBar)
                .environment(store)
                .environment(timer)
                .tint(.teal)
        }
    }
}

struct RootView: View {
    @Environment(JournalStore.self) private var store
    @Binding var hidesTabBar: Bool

    var body: some View {
        @Bindable var store = store
        TabView {
            TimerView().tabItem { Label("Séance", systemImage: "timer") }
            JournalView().tabItem { Label("Journal", systemImage: "book.closed") }
            TrendsView().tabItem { Label("Tendances", systemImage: "chart.xyaxis.line") }
            MethodListView(hidesTabBar: $hidesTabBar).tabItem { Label("Méthode", systemImage: "text.book.closed") }
            SettingsView().tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .privacyMask()
        .toolbar(hidesTabBar ? .hidden : .automatic, for: .tabBar)
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
