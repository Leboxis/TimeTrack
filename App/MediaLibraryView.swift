import SwiftUI

struct MediaLibraryView: View {
    private let categories = MediaCatalog.categories

    var body: some View {
        List {
            if categories.isEmpty {
                ContentUnavailableView("Contenu à venir", systemImage: "play.circle",
                    description: Text("Les médias ajoutés apparaîtront ici."))
            }
            ForEach(categories) { category in
                Section {
                    if category.items.isEmpty {
                        Text("Aucun contenu.").foregroundStyle(.secondary)
                    }
                    ForEach(category.items) { item in
                        NavigationLink {
                            MediaPlayerView(item: item)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.kind == .audio ? "waveform" : "play.rectangle")
                                    .foregroundStyle(.teal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.headline).foregroundStyle(.primary)
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Label(category.title, systemImage: category.systemImage)
                }
            }
        }
        .navigationTitle("Médias")
    }
}
