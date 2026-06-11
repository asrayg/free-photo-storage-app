import SwiftUI
import PhotosUI

@MainActor
struct LibraryView: View {
    @Bindable var store: PhotoStore
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var selectedPhoto: Photo?
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var confirmDeleteSelection = false

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
            .navigationTitle(isSelecting ? "\(selection.count) selected" : "GitPhotos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button("Done") { isSelecting = false; selection = [] }
                    } else {
                        PhotosPicker(selection: $pickedItems, maxSelectionCount: 100, matching: .images) {
                            Image(systemName: "plus")
                        }
                        .disabled(store.upload.isActive)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting {
                        Button("Cancel") { isSelecting = false; selection = [] }
                    } else {
                        NavigationLink {
                            SettingsView(store: store)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isSelecting && !store.manifest.photos.isEmpty {
                        Button("Select") { isSelecting = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if store.upload.isActive {
                    uploadBanner
                } else if isSelecting {
                    selectionBar
                }
            }
            .confirmationDialog("Remove \(selection.count) photo(s) from GitHub?", isPresented: $confirmDeleteSelection, titleVisibility: .visible) {
                Button("Remove \(selection.count)", role: .destructive) {
                    let toDelete = store.manifest.photos.filter { selection.contains($0.id) }
                    isSelecting = false
                    selection = []
                    Task { await store.delete(toDelete) }
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
                                ThumbnailCell(store: store, photo: photo, isSelected: selection.contains(photo.id), showSelection: isSelecting)
                                    .onTapGesture {
                                        if isSelecting {
                                            toggle(photo)
                                        } else {
                                            selectedPhoto = photo
                                        }
                                    }
                                    .onLongPressGesture {
                                        if !isSelecting { isSelecting = true }
                                        toggle(photo)
                                    }
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

    private func toggle(_ photo: Photo) {
        if selection.contains(photo.id) { selection.remove(photo.id) }
        else { selection.insert(photo.id) }
    }

    private var selectionBar: some View {
        HStack {
            Button(role: .destructive) {
                confirmDeleteSelection = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
            Spacer()
            Text("\(selection.count) selected").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.bar, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 4)
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
    var isSelected = false
    var showSelection = false
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
                if showSelection {
                    Color.black.opacity(isSelected ? 0.35 : 0)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Color.accentColor : .white)
                                .background(Circle().fill(.black.opacity(0.25)))
                                .padding(5)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: photo.id) {
            image = await store.thumbnail(for: photo)
        }
    }
}
