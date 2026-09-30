import SwiftUI

struct MethodListView: View {
    private let methods = MethodCatalog.all
    @State private var showsFeed = false
    /// Driven explicitly rather than by `NavigationLink`. Three links sharing one
    /// `List` row is what produced the reported bug: SwiftUI treats the row as a
    /// single navigation target, so tapping Galeries could land on Medias, and it drew
    /// a disclosure chevron for each link it found. One path and plain buttons remove
    /// both at the source, since there is no link left for the row to disagree with.
    @State private var path: [MethodRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 10) {
                        Button { showsFeed = true } label: {
                            tile("Flux", "play.rectangle")
                        }
                        Button { path.append(.medias) } label: {
                            tile("Médias", "play.circle")
                        }
                        Button { path.append(.galeries) } label: {
                            tile("Galeries", "photo.on.rectangle")
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
            .navigationDestination(for: MethodRoute.self) { route in
                switch route {
                case .medias: MediaLibraryView()
                case .galeries: GalleryPickerView()
                }
            }
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
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(RatingPalette.duration.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}

/// What the three tiles can open. Hashable so it can ride the navigation path.
private enum MethodRoute: Hashable {
    case medias, galeries
}
