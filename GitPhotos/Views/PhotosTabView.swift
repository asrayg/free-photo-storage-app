import SwiftUI

/// The main "Photos" timeline: day-grouped grid with pinch-to-zoom density and a
/// fast-scroll date scrubber.
@MainActor
struct PhotosTabView: View {
    let store: PhotoStore
    @Binding var navHidden: Bool

    @State private var columns = 3
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var openID: String?

    private var sections: [PhotoSection] { store.dailySections(store.libraryPhotos) }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.libraryPhotos.isEmpty {
                    ProgressView("Loading library…")
                } else if store.libraryPhotos.isEmpty {
                    ContentUnavailableView(
                        "No photos yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Tap Add to upload, or turn on Auto-sync in Collections → Settings."))
                } else {
                    PhotoGrid(store: store, sections: sections, columns: $columns,
                              allowPinch: true, showScrubber: true,
                              selecting: $selecting, selection: $selection) { photo in
                        openID = photo.id
                    }
                }
            }
            .navigationTitle(selecting ? "\(selection.count) selected" : "Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selecting {
                        Button("Cancel") { finishSelect() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.libraryPhotos.isEmpty {
                        Button(selecting ? "Done" : "Select") {
                            if selecting { finishSelect() } else { selecting = true }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if store.upload.isActive {
                    UploadBanner(upload: store.upload)
                } else if selecting {
                    selectionBar
                }
            }
            .onChange(of: selecting) { _, v in navHidden = v }
            .fullScreenCover(item: Binding(get: { openID.map { IDBox(id: $0) } }, set: { openID = $0?.id })) { box in
                PhotoDetailView(store: store, photos: store.libraryPhotos, initialID: box.id, mode: .normal)
            }
        }
    }

    private var selected: [Photo] { store.libraryPhotos.filter { selection.contains($0.id) } }
    private func finishSelect() { selecting = false; selection = []; navHidden = false }

    private var selectionBar: some View {
        HStack(spacing: 28) {
            Button {
                let items = selected; finishSelect()
                Task { for p in items { await store.setFavorite(p, true) } }
            } label: {
                VStack(spacing: 4) { Image(systemName: "heart"); Text("Favorite").font(.caption) }
            }
            .disabled(selection.isEmpty)

            Button(role: .destructive) {
                let items = selected; finishSelect()
                Task { await store.trash(items) }
            } label: {
                VStack(spacing: 4) { Image(systemName: "trash"); Text("Remove").font(.caption) }
            }
            .disabled(selection.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

struct UploadBanner: View {
    let upload: PhotoStore.UploadProgress

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(upload.completed + upload.failed),
                         total: Double(max(upload.total, 1)))
            Text("\(upload.completed)/\(upload.total)")
                .font(.caption.monospacedDigit())
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
