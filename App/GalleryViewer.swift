import SwiftUI
import UIKit

/// Swipeable viewer: drag left or right, or tap the page dots, to move between images.
struct GalleryViewer: View {
    let gallery: Gallery
    @State private var index = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(gallery.imageNames.enumerated()), id: \.offset) { position, name in
                    Group {
                        if let uiImage = UIImage(named: name) {
                            Image(uiImage: uiImage).resizable().scaledToFit()
                        } else {
                            ContentUnavailableView("Image introuvable", systemImage: "photo")
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .ignoresSafeArea()
            VStack {
                HStack {
                    Button {
                        index = max(0, index - 1)
                    } label: {
                        Label("Précédente", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(index == 0)
                    Spacer()
                    Text("\(min(index + 1, max(gallery.imageNames.count, 1))) / \(gallery.imageNames.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Button {
                        index = min(gallery.imageNames.count - 1, index + 1)
                    } label: {
                        Label("Suivante", systemImage: "chevron.right")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(index >= gallery.imageNames.count - 1)
                }
                .tint(.white)
                .padding()
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
