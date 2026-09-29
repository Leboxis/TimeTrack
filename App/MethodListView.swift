import SwiftUI

struct MethodListView: View {
    private let methods = MethodCatalog.all

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        NavigationLink {
                            FeedView()
                        } label: {
                            Label("Flux", systemImage: "play.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        NavigationLink {
                            MediaLibraryView()
                        } label: {
                            Label("Médias", systemImage: "play.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        NavigationLink {
                            GalleryPickerView()
                        } label: {
                            Label("Galeries", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
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
    }
}
