import SwiftUI
import WellbeingCore

struct GalleryPickerView: View {
    private let galleries = GalleryCatalog.all
    @AppStorage("kDriveToken") private var kDriveToken = ""
    @AppStorage("kDriveDriveID") private var kDriveDriveID = ""

    private var kDriveReady: Bool {
        KDriveConfig(token: kDriveToken, driveID: kDriveDriveID).isComplete
    }

    var body: some View {
        Group {
            if galleries.isEmpty && !kDriveReady {
                ContentUnavailableView("Aucune galerie", systemImage: "photo.on.rectangle",
                    description: Text("Les galeries ajoutées apparaîtront ici."))
            } else {
                List {
                    Section {
                        NavigationLink {
                            KDriveBrowserView()
                        } label: {
                            Label("kDrive", systemImage: "externaldrive")
                        }
                    } footer: {
                        Text(kDriveReady
                             ? "Parcours de tes dossiers kDrive, avec lecture des médias."
                             : "Renseigne le jeton API et l’ID du Drive dans les Réglages.")
                    }                    ForEach(galleries) { gallery in
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
        }
        .navigationTitle("Galeries")
    }
}
