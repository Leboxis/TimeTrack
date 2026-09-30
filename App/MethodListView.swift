import SwiftUI

struct MethodListView: View {
    private let methods = MethodCatalog.all
    @State private var showsFeed = false

    var body: some View {
        NavigationStack {
            List {
                // Three destinations of equal weight, so they sit side by side rather
                // than as three stacked rows: one row, three tiles.
                Section {
                    HStack(spacing: 10) {
                        Button { showsFeed = true } label: {
                            tile("Flux", "play.rectangle")
                        }
                        .buttonStyle(.plain)

                        NavigationLink { MediaLibraryView() } label: {
                            tile("Médias", "play.circle")
                        }
                        .buttonStyle(.plain)

                        NavigationLink { GalleryPickerView() } label: {
                            tile("Galeries", "photo.on.rectangle")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    // A row holding several NavigationLinks otherwise leaves stray
                    // grey rounded rectangles behind each label.
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if methods.isEmpty {
                    ContentUnavailableView("Aucune méthode", systemImage: "text.book.closed",
                        description: Text("Les méthodes ajoutées apparaîtront ici."))
                }
                ForEach(methods) { method in
                    NavigationLink {
                        MethodDetailView(method: method)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(method.title).font(.headline).foregroundStyle(.primary)
                            Text(method.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            if let cadence = method.cadence {
                                Label(cadence, systemImage: "calendar")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Méthode")
        }
        .fullScreenCover(isPresented: $showsFeed) { FeedView() }
    }

    private func tile(_ title: String, _ systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(RatingPalette.duration)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        // Equal width from the HStack, and a fixed height so the three read as one row
        // even if a title wraps differently.
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(RatingPalette.duration.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}
