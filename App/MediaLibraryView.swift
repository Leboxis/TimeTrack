import SwiftUI

struct MediaLibraryView: View {
    private let items = MediaCatalog.all

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("Contenu à venir", systemImage: "play.circle",
                    description: Text("Les médias ajoutés apparaîtront ici."))
            } else {
                List(items) { item in
                    Text(item.title).font(.headline).foregroundStyle(.primary)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Médias")
    }
}
