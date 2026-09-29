import SwiftUI

/// Stands in for the generic empty state when the journal could not be read, so a
/// damaged file is never presented as an empty history.
struct LoadFailureNotice: View {
    @Environment(JournalStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Journal illisible", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text(store.loadFailureMessage).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
