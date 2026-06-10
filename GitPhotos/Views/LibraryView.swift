import SwiftUI
import PhotosUI

@MainActor
struct LibraryView: View {
    @Bindable var store: PhotoStore
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var selectedPhoto: Photo?

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.manifest.photos.isEmpty {
                    ProgressView("Loading library…")
                } else if store.manifest.photos.isEmpty {
                    ContentUnavailableView(
                        "No photos yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Tap + to upload photos. They're stored in private GitHub repos on your account."))
                } else {
                    grid
                }
            }
            .navigationTitle("Photon")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickedItems, maxSelectionCount: 100, matching: .images) {
                        Image(systemName: "plus")
                    }
                    .disabled(store.upload.isActive)
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView(store: store)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if store.upload.isActive {
                    uploadBanner
                }
            }
            .fullScreenCover(item: $selectedPhoto) { photo in
                PhotoDetailView(store: store, initial: photo)
            }
            .alert("Error", isPresented: .init(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .task {
                await store.bootstrap()
                await store.sync.start()
            }
            .onChange(of: pickedItems) { _, items in
                guard !items.isEmpty else { return }
                pickedItems = []
                Task { await store.uploadPickedItems(items) }
            }
            .refreshable {
                await store.bootstrap()
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                ForEach(store.photosByMonth, id: \.month) { group in
                    Section {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(group.photos) { photo in
                                ThumbnailCell(store: store, photo: photo)
                                    .onTapGesture { selectedPhoto = photo }
                            }
                        }
                    } header: {
                        Text(group.month)
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.bar)
                    }
                }
            }
        }
    }

    private var uploadBanner: some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(store.upload.completed + store.upload.failed),
                         total: Double(max(store.upload.total, 1)))
            Text("\(store.upload.completed)/\(store.upload.total)")
                .font(.caption.monospacedDigit())
        }
        .padding(12)
        .background(.bar, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}

struct ThumbnailCell: View {
    let store: PhotoStore
    let photo: Photo
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(Color(.systemGray5))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: photo.id) {
            image = await store.thumbnail(for: photo)
        }
    }
}
