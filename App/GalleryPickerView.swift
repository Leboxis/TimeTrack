import SwiftUI

struct GalleryPickerView: View {
    private let galleries = GalleryCatalog.all

    var body: some View {
        Group {
            if galleries.isEmpty {
                ContentUnavailableView("Aucune galerie", systemImage: "photo.on.rectangle",
                    description: Text("Les galeries ajoutées apparaîtront ici."))
            } else {
                List(galleries) { gallery in
                    NavigationLink {
                        GalleryViewer(gallery: gallery)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(gallery.title).font(.headline).foregroundStyle(.primary)
                            Text("\(gallery.imageNames.count) image(s)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Galeries")
    }
}
