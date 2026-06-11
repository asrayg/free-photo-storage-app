import SwiftUI

@MainActor
struct PhotoDetailView: View {
    let store: PhotoStore
    let initial: Photo

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String?
    @State private var confirmDelete = false
    @State private var editTarget: EditTarget?
    @State private var loadingEditor = false

    private struct EditTarget: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private var photos: [Photo] {
        store.photosByMonth.flatMap(\.photos)
    }

    private var currentPhoto: Photo? {
        photos.first { $0.id == currentID } ?? photos.first
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentID) {
                ForEach(photos) { photo in
                    ZoomableImageView(store: store, photo: photo)
                        .tag(Optional(photo.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .navigationTitle(currentPhoto.map { Self.titleFormatter.string(from: $0.createdAt) } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            openEditor()
                        } label: {
                            if loadingEditor {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "slider.horizontal.3")
                            }
                        }
                        .disabled(loadingEditor)
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .confirmationDialog("Delete this photo from GitHub?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let photo = currentPhoto else { return }
                    Task {
                        await store.delete(photo)
                        if photos.isEmpty { dismiss() }
                    }
                }
            }
            .fullScreenCover(item: $editTarget) { target in
                if let photo = currentPhoto {
                    PhotoEditorView(store: store, photo: photo, original: target.image)
                }
            }
        }
        .onAppear { currentID = initial.id }
    }

    private func openEditor() {
        guard let photo = currentPhoto else { return }
        loadingEditor = true
        Task {
            if let image = await store.fullImage(for: photo) {
                editTarget = EditTarget(image: image)
            }
            loadingEditor = false
        }
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

/// Full-res image with pinch-to-zoom and double-tap-to-zoom.
struct ZoomableImageView: View {
    let store: PhotoStore
    let photo: Photo

    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoom)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoom = min(max(steadyZoom * value, 1), 5)
                                }
                                .onEnded { _ in
                                    steadyZoom = zoom
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(duration: 0.3)) {
                                zoom = zoom > 1 ? 1 : 2.5
                                steadyZoom = zoom
                            }
                        }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .task(id: photo.id) {
            // Show the cached thumbnail immediately while full-res downloads.
            if image == nil {
                image = await store.thumbnail(for: photo)
            }
            if let full = await store.fullImage(for: photo) {
                image = full
            }
        }
    }
}
