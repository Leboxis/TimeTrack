import SwiftUI

/// Hides content while the app is not active. Presented sheets are layered above the
/// root view, so the mask has to be applied to every presented screen as well.
struct PrivacyMask: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            if scenePhase != .active {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    Label("Wellbeing", systemImage: "leaf.fill").font(.largeTitle).foregroundStyle(.teal)
                }
            }
        }
    }
}

extension View {
    func privacyMask() -> some View { modifier(PrivacyMask()) }
}
